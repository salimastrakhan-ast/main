package realtime

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"github.com/coder/websocket"
	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

const (
	// Очередь исходящих кадров. Клиент, который не успевает их вычитывать,
	// отключается: копить для него сообщения в памяти сервера нельзя, он всё
	// равно доберёт их через sync при следующем подключении.
	sendQueueSize = 256

	writeTimeout = 10 * time.Second
	// Если от клиента ничего не пришло за это время — считаем соединение
	// мёртвым. Мобильная сеть рвётся молча, без FIN.
	readTimeout   = 90 * time.Second
	maxFrameBytes = 1 << 20

	authTimeout = 10 * time.Second
)

// Conn — одно клиентское соединение.
type Conn struct {
	id       uuid.UUID
	userID   uuid.UUID
	deviceID uuid.UUID

	sock  *websocket.Conn
	codec ws.Codec
	out   chan []byte
	log   *slog.Logger

	user   domain.User
	hub    *Hub
	closed chan struct{}
}

// send кладёт готовый кадр в очередь отправки.
//
// Очередь переполнена — рвём соединение вместо того, чтобы блокировать
// рассылку: один залипший клиент не должен тормозить чат для остальных.
func (c *Conn) send(frame []byte) {
	select {
	case c.out <- frame:
	case <-c.closed:
	default:
		c.log.Warn("клиент не успевает читать, отключаем", "user", c.userID)
		_ = c.sock.Close(websocket.StatusPolicyViolation, "клиент не успевает читать")
	}
}

func (c *Conn) reply(id, typ string, payload any) {
	frame, err := ws.Reply(c.codec, id, typ, payload)
	if err != nil {
		c.log.Error("не собран ответ", "err", err, "type", typ)
		return
	}
	c.send(frame)
}

func (c *Conn) replyError(id, code, message string) {
	frame, err := ws.ErrorReply(c.codec, id, code, message)
	if err != nil {
		c.log.Error("не собрана ошибка", "err", err)
		return
	}
	c.send(frame)
}

// Serve принимает соединение: апгрейд, авторизация первым кадром, циклы
// чтения и записи.
func (h *Hub) Serve(w http.ResponseWriter, r *http.Request) {
	sock, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		// Проверку Origin отключаем осознанно: мобильные клиенты его не
		// шлют, а доступ ограничивает токен в первом кадре, а не заголовок.
		InsecureSkipVerify: true,
		CompressionMode:    websocket.CompressionContextTakeover,
	})
	if err != nil {
		h.log.Debug("апгрейд не удался", "err", err)
		return
	}
	sock.SetReadLimit(maxFrameBytes)

	ctx, cancel := context.WithCancel(r.Context())
	defer cancel()

	conn := &Conn{
		id:     uuid.New(),
		sock:   sock,
		codec:  ws.JSONCodec{},
		out:    make(chan []byte, sendQueueSize),
		log:    h.log,
		hub:    h,
		closed: make(chan struct{}),
	}

	if err := conn.handshake(ctx); err != nil {
		conn.log.Debug("рукопожатие не удалось", "err", err)
		_ = sock.Close(websocket.StatusPolicyViolation, "не авторизован")
		return
	}
	conn.log = h.log.With("user", conn.userID, "conn", conn.id)

	if err := h.register(ctx, conn); err != nil {
		conn.log.Error("не зарегистрировано соединение", "err", err)
		_ = sock.Close(websocket.StatusInternalError, "внутренняя ошибка")
		return
	}
	defer func() {
		close(conn.closed)
		// Отключение обрабатываем в живом контексте: контекст запроса уже
		// отменён, а отписаться от Redis и снять presence всё равно надо.
		h.unregister(context.WithoutCancel(context.Background()), conn)
	}()

	conn.reply("", ws.EventReady, ws.ReadyData{
		User:      conn.user,
		SessionID: conn.id.String(),
		Codec:     conn.codec.Name(),
	})

	go conn.writeLoop(ctx)
	conn.readLoop(ctx)
}

// handshake ждёт первым кадром команду auth с access-токеном.
//
// До неё соединение не делает ничего: неавторизованный сокет не должен
// висеть открытым дольше пары секунд.
func (c *Conn) handshake(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, authTimeout)
	defer cancel()

	_, data, err := c.sock.Read(ctx)
	if err != nil {
		return err
	}
	env, err := c.codec.Decode(data)
	if err != nil {
		return err
	}
	if env.T != ws.CmdAuth {
		return errors.New("первым кадром должен быть auth")
	}

	var payload ws.AuthData
	if err := decodeData(env, &payload); err != nil {
		return err
	}
	claims, err := c.hub.tokens.Parse(payload.Token, time.Now())
	if err != nil {
		return err
	}
	user, err := c.hub.store.UserByID(ctx, claims.UserID)
	if err != nil {
		return fmt.Errorf("профиль не найден: %w", err)
	}

	c.userID = claims.UserID
	c.deviceID = claims.DeviceID
	c.user = user
	return nil
}

func (c *Conn) writeLoop(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		case <-c.closed:
			return
		case frame := <-c.out:
			writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
			err := c.sock.Write(writeCtx, websocket.MessageText, frame)
			cancel()
			if err != nil {
				c.log.Debug("запись не удалась", "err", err)
				_ = c.sock.Close(websocket.StatusInternalError, "ошибка записи")
				return
			}
		}
	}
}

func (c *Conn) readLoop(ctx context.Context) {
	for {
		readCtx, cancel := context.WithTimeout(ctx, readTimeout)
		_, data, err := c.sock.Read(readCtx)
		cancel()
		if err != nil {
			c.log.Debug("соединение закрыто", "err", err)
			return
		}

		env, err := c.codec.Decode(data)
		if err != nil {
			c.replyError("", ws.ErrCodeBadRequest, err.Error())
			continue
		}
		// Команды одного соединения обрабатываются по очереди: порядок
		// сообщений в чате должен совпадать с порядком отправки.
		c.handle(ctx, env)
	}
}
