package realtime

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Звонки: сервер сводит две стороны и пересылает им описания соединения.
//
// Сам разговор через сервер не идёт. Клиенты обмениваются через него только
// SDP (описание того, какой звук они готовы принимать) и ICE-кандидатами
// (способами дозвониться друг до друга), а дальше открывают соединение
// напрямую. Содержимое этих строк сервер не разбирает: понимать их должны
// клиенты, и добавь он сюда свою логику — она сломается на следующей версии
// WebRTC.
//
// Состояние звонка живёт в Redis, а не в памяти инстанса. Два собеседника
// запросто окажутся на разных инстансах за балансировщиком, и тот, кто
// принимает звонок, должен знать, кому пересылать ответ, даже если оффер
// пришёл не через него.

const (
	// Звонок живёт в Redis дольше любого разговора: запись нужна, пока идёт
	// обмен кандидатами, а он продолжается и посреди беседы, если сеть
	// сменилась. Два часа — с запасом, и мусор всё равно подчистит TTL.
	callTTL = 2 * time.Hour

	// Предел на SDP и кандидата. Обычный оффер — несколько килобайт;
	// без предела сокет превращается в бесплатный канал для пересылки
	// чего угодно между двумя участниками.
	maxSDPLen       = 16 << 10
	maxCandidateLen = 1 << 10
)

// callRecord — кто с кем говорит. Больше серверу знать не нужно.
type callRecord struct {
	Caller uuid.UUID `json:"caller"`
	Callee uuid.UUID `json:"callee"`
	ChatID uuid.UUID `json:"chat_id"`
}

// peerOf возвращает второго участника звонка — того, кому пересылать.
// Ошибка означает, что зовущий к этому звонку отношения не имеет.
func (r callRecord) peerOf(user uuid.UUID) (uuid.UUID, error) {
	switch user {
	case r.Caller:
		return r.Callee, nil
	case r.Callee:
		return r.Caller, nil
	default:
		return uuid.Nil, errors.New("этот звонок не ваш")
	}
}

func callKey(id uuid.UUID) string { return "call:" + id.String() }

func (h *Hub) saveCall(ctx context.Context, id uuid.UUID, rec callRecord) error {
	body, err := json.Marshal(rec)
	if err != nil {
		return fmt.Errorf("сборка звонка: %w", err)
	}
	if err := h.rdb.Set(ctx, callKey(id), body, callTTL).Err(); err != nil {
		return fmt.Errorf("сохранение звонка: %w", err)
	}
	return nil
}

func (h *Hub) loadCall(ctx context.Context, id uuid.UUID) (callRecord, error) {
	body, err := h.rdb.Get(ctx, callKey(id)).Bytes()
	if errors.Is(err, redis.Nil) {
		return callRecord{}, errCallGone
	}
	if err != nil {
		return callRecord{}, fmt.Errorf("чтение звонка: %w", err)
	}
	var rec callRecord
	if err := json.Unmarshal(body, &rec); err != nil {
		return callRecord{}, fmt.Errorf("разбор звонка: %w", err)
	}
	return rec, nil
}

var errCallGone = errors.New("звонок уже закончился")

// callPeer находит второго участника и проверяет, что зовущий — участник.
//
// Обе ошибки клиенту выглядят одинаково безобидно, но различаются по коду:
// «звонка нет» и «звонок не ваш» — разные вещи, и подменять вторую первой
// значило бы прятать чужую попытку влезть в разговор.
func (c *Conn) callPeer(ctx context.Context, id string, callID uuid.UUID) (callRecord, uuid.UUID, bool) {
	rec, err := c.hub.loadCall(ctx, callID)
	if errors.Is(err, errCallGone) {
		c.replyError(id, ws.ErrCodeNotFound, "Звонок уже закончился")
		return callRecord{}, uuid.Nil, false
	}
	if err != nil {
		c.log.Error("не прочитан звонок", "err", err, "call", callID)
		c.replyError(id, ws.ErrCodeInternal, "Внутренняя ошибка")
		return callRecord{}, uuid.Nil, false
	}
	peer, err := rec.peerOf(c.userID)
	if err != nil {
		c.replyError(id, ws.ErrCodeForbidden, "Нет доступа")
		return callRecord{}, uuid.Nil, false
	}
	return rec, peer, true
}

// handleCallStart — звонящий предлагает соединение.
func (c *Conn) handleCallStart(ctx context.Context, env ws.Envelope) {
	var payload ws.CallStartData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	if len(payload.SDP) == 0 || len(payload.SDP) > maxSDPLen {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Неверное описание соединения")
		return
	}

	chat, err := c.hub.store.ChatByID(ctx, payload.ChatID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	// Групповой звонок — это не «ещё один участник», а сведение потоков на
	// отдельном сервере. Пока его нет, честнее отказать, чем соединить
	// двоих из пяти и оставить остальных гадать.
	if chat.Type != domain.ChatPrivate {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "В группах звонков пока нет")
		return
	}

	members, err := c.hub.store.MemberIDs(ctx, payload.ChatID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	callee := uuid.Nil
	mine := false
	for _, id := range members {
		if id == c.userID {
			mine = true
			continue
		}
		callee = id
	}
	if !mine || callee == uuid.Nil {
		c.replyError(env.ID, ws.ErrCodeForbidden, "Нет доступа")
		return
	}

	me, err := c.hub.store.UserByID(ctx, c.userID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	me = media.ResolveUser(ctx, c.hub.media, me)

	callID := uuid.New()
	rec := callRecord{Caller: c.userID, Callee: callee, ChatID: payload.ChatID}
	if err := c.hub.saveCall(ctx, callID, rec); err != nil {
		c.log.Error("не сохранён звонок", "err", err)
		c.replyError(env.ID, ws.ErrCodeInternal, "Внутренняя ошибка")
		return
	}

	// Если собеседника нет в сети, звонок всё равно заводится: у звонящего
	// он появится в истории как несостоявшийся, а клиент сразу покажет
	// «не в сети» вместо сорока секунд гудков в пустоту.
	status := "ringing"
	if !c.hub.IsOnline(ctx, callee) {
		status = "offline"
	}
	c.reply(env.ID, ws.TypeAck, ws.CallStartedData{CallID: callID, Status: status})
	if status == "offline" {
		return
	}

	c.hub.Publish(ctx, []uuid.UUID{callee}, uuid.Nil, ws.EventCallIncoming,
		ws.CallIncomingData{
			CallID: callID,
			ChatID: payload.ChatID,
			From:   me.Public(),
			SDP:    payload.SDP,
			Video:  payload.Video,
		})
}

// handleCallAnswer — трубку сняли, соединение согласовано.
func (c *Conn) handleCallAnswer(ctx context.Context, env ws.Envelope) {
	var payload ws.CallAnswerData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	if len(payload.SDP) == 0 || len(payload.SDP) > maxSDPLen {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Неверное описание соединения")
		return
	}
	rec, peer, ok := c.callPeer(ctx, env.ID, payload.CallID)
	if !ok {
		return
	}
	// Отвечать может только тот, кому звонили: иначе звонящий «ответил» бы
	// сам себе и сбил согласование.
	if c.userID != rec.Callee {
		c.replyError(env.ID, ws.ErrCodeForbidden, "Нет доступа")
		return
	}

	c.reply(env.ID, ws.TypeAck, struct{}{})
	c.hub.Publish(ctx, []uuid.UUID{peer}, uuid.Nil, ws.EventCallAccepted,
		ws.CallAcceptedData{CallID: payload.CallID, SDP: payload.SDP})
}

// handleCallICE пересылает очередной способ дозвониться.
//
// Подтверждения нет намеренно: кандидатов бывают десятки, и ответ на каждый
// удвоил бы трафик самой болтливой части звонка.
func (c *Conn) handleCallICE(ctx context.Context, env ws.Envelope) {
	var payload ws.CallICEData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	if len(payload.Candidate) > maxCandidateLen || len(payload.SDPMid) > 64 {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Неверный кандидат")
		return
	}
	_, peer, ok := c.callPeer(ctx, env.ID, payload.CallID)
	if !ok {
		return
	}
	c.hub.Publish(ctx, []uuid.UUID{peer}, uuid.Nil, ws.EventCallICE, payload)
}

// handleCallHangup завершает звонок для обеих сторон.
func (c *Conn) handleCallHangup(ctx context.Context, env ws.Envelope) {
	var payload ws.CallHangupData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	_, peer, ok := c.callPeer(ctx, env.ID, payload.CallID)
	if !ok {
		return
	}

	reason := payload.Reason
	switch reason {
	case ws.CallEndHangup, ws.CallEndDeclined, ws.CallEndMissed,
		ws.CallEndBusy, ws.CallEndFailed:
	default:
		reason = ws.CallEndHangup
	}

	if err := c.hub.rdb.Del(ctx, callKey(payload.CallID)).Err(); err != nil {
		c.log.Warn("не удалён звонок", "err", err, "call", payload.CallID)
	}
	c.reply(env.ID, ws.TypeAck, struct{}{})

	// Событие уходит обоим, а не только собеседнику: трубку могли положить
	// с телефона, а окно разговора открыто ещё и в браузере.
	c.hub.Publish(ctx, []uuid.UUID{peer, c.userID}, c.id, ws.EventCallEnded,
		ws.CallEndedData{CallID: payload.CallID, Reason: reason})
}
