// Package realtime держитWebSocket-соединения и разносит по ним события.
//
// Рассылка идёт через Redis по каналу на пользователя, а не на чат. Число
// подписок инстанса тогда равно числу онлайн-соединений, а не сумме их чатов,
// и человек, которого только что добавили в группу, начинает получать её
// события без переподписки.
package realtime

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/redis/go-redis/v9"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/push"
	"github.com/salimastrakhan-ast/main/server/internal/store"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

const (
	// presenceTTL с запасом больше интервала обновления: одна пропущенная
	// отметка не должна показывать человека офлайн.
	presenceTTL      = 90 * time.Second
	presenceRefresh  = 30 * time.Second
	presencePartners = 500

	syncChatLimit = 200
)

// wireEvent — событие в том виде, в каком оно едет через Redis.
//
// Здесь оно ещё не закодировано в кадр: конкретный кодек выбирается на
// стороне соединения, поэтому инстанс с клиентами на разных версиях
// протокола отдаст каждому его формат.
type wireEvent struct {
	Type string          `json:"t"`
	Data json.RawMessage `json:"d"`
	// Skip — соединение-источник. Отправитель уже получил ответ на команду,
	// и то же событие ему возвращать незачем.
	Skip uuid.UUID `json:"skip,omitempty"`
}

type Hub struct {
	store  *store.Store
	rdb    *redis.Client
	pusher push.Pusher
	tokens *auth.TokenIssuer
	media  media.Resolver
	log    *slog.Logger

	mu    sync.RWMutex
	conns map[uuid.UUID]map[*Conn]struct{}

	pubsub *redis.PubSub
}

func NewHub(st *store.Store, rdb *redis.Client, pusher push.Pusher, tokens *auth.TokenIssuer, resolver media.Resolver, log *slog.Logger) *Hub {
	if log == nil {
		log = slog.Default()
	}
	if resolver == nil {
		resolver = media.NoopResolver{}
	}
	return &Hub{
		store:  st,
		rdb:    rdb,
		pusher: pusher,
		tokens: tokens,
		media:  resolver,
		log:    log,
		conns:  make(map[uuid.UUID]map[*Conn]struct{}),
	}
}

// Run крутит приём событий из Redis и обновление presence. Возвращается,
// когда контекст отменён.
func (h *Hub) Run(ctx context.Context) {
	h.pubsub = h.rdb.Subscribe(ctx)
	defer func() { _ = h.pubsub.Close() }()

	events := h.pubsub.Channel()
	ticker := time.NewTicker(presenceRefresh)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case msg, ok := <-events:
			if !ok {
				return
			}
			h.dispatch(msg)
		case <-ticker.C:
			h.refreshPresence(ctx)
		}
	}
}

// dispatch разносит событие из Redis по локальным соединениям адресата.
func (h *Hub) dispatch(msg *redis.Message) {
	userID, err := userFromChannel(msg.Channel)
	if err != nil {
		h.log.Warn("непонятный канал", "channel", msg.Channel)
		return
	}
	var ev wireEvent
	if err := json.Unmarshal([]byte(msg.Payload), &ev); err != nil {
		h.log.Warn("не разобрано событие", "err", err)
		return
	}

	h.mu.RLock()
	conns := make([]*Conn, 0, len(h.conns[userID]))
	for c := range h.conns[userID] {
		conns = append(conns, c)
	}
	h.mu.RUnlock()

	for _, c := range conns {
		if c.id == ev.Skip {
			continue
		}
		frame, err := c.codec.Encode(ws.Envelope{T: ev.Type, D: ev.Data})
		if err != nil {
			h.log.Error("не закодировано событие", "err", err, "type", ev.Type)
			continue
		}
		c.send(frame)
	}
}

func userChannel(userID uuid.UUID) string { return "user:" + userID.String() }

func userFromChannel(channel string) (uuid.UUID, error) {
	const prefix = "user:"
	if len(channel) <= len(prefix) || channel[:len(prefix)] != prefix {
		return uuid.Nil, fmt.Errorf("канал %q не про пользователя", channel)
	}
	return uuid.Parse(channel[len(prefix):])
}

// Publish рассылает событие списку пользователей.
//
// Событие уходит и тому, кто его вызвал: у человека может быть открыт
// телефон и десктоп одновременно, и второе устройство обязано увидеть
// отправленное с первого.
func (h *Hub) Publish(ctx context.Context, userIDs []uuid.UUID, skip uuid.UUID, typ string, payload any) {
	if len(userIDs) == 0 {
		return
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		h.log.Error("не сериализовано событие", "err", err, "type", typ)
		return
	}
	body, err := json.Marshal(wireEvent{Type: typ, Data: raw, Skip: skip})
	if err != nil {
		h.log.Error("не собрано событие", "err", err, "type", typ)
		return
	}

	pipe := h.rdb.Pipeline()
	for _, id := range userIDs {
		pipe.Publish(ctx, userChannel(id), body)
	}
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, context.Canceled) {
		h.log.Error("не разослано событие", "err", err, "type", typ)
	}
}

// register добавляет соединение и подписывает инстанс на канал пользователя,
// если это его первое соединение здесь.
func (h *Hub) register(ctx context.Context, c *Conn) error {
	h.mu.Lock()
	first := len(h.conns[c.userID]) == 0
	if first {
		h.conns[c.userID] = make(map[*Conn]struct{})
	}
	h.conns[c.userID][c] = struct{}{}
	h.mu.Unlock()

	if !first {
		return nil
	}
	if err := h.pubsub.Subscribe(ctx, userChannel(c.userID)); err != nil {
		h.unregister(context.WithoutCancel(ctx), c)
		return fmt.Errorf("подписка на канал пользователя: %w", err)
	}
	h.setOnline(ctx, c.userID, true)
	return nil
}

func (h *Hub) unregister(ctx context.Context, c *Conn) {
	h.mu.Lock()
	conns := h.conns[c.userID]
	delete(conns, c)
	last := len(conns) == 0
	if last {
		delete(h.conns, c.userID)
	}
	h.mu.Unlock()

	if !last {
		return
	}
	if err := h.pubsub.Unsubscribe(ctx, userChannel(c.userID)); err != nil {
		h.log.Warn("не отписались от канала", "err", err, "user", c.userID)
	}
	h.setOnline(ctx, c.userID, false)
}

func presenceKey(userID uuid.UUID) string { return "presence:" + userID.String() }

// setOnline обновляет отметку присутствия и сообщает о ней собеседникам.
//
// Presence знают только те, с кем человек состоит в чатах: остальным это
// не нужно и знать не положено.
func (h *Hub) setOnline(ctx context.Context, userID uuid.UUID, online bool) {
	if online {
		if err := h.rdb.Set(ctx, presenceKey(userID), "1", presenceTTL).Err(); err != nil {
			h.log.Warn("не сохранён presence", "err", err, "user", userID)
		}
	} else {
		if err := h.rdb.Del(ctx, presenceKey(userID)).Err(); err != nil {
			h.log.Warn("не снят presence", "err", err, "user", userID)
		}
		if err := h.store.TouchUser(ctx, userID); err != nil {
			h.log.Warn("не обновлён last_seen", "err", err, "user", userID)
		}
	}

	partners, err := h.store.ChatPartners(ctx, userID, presencePartners)
	if err != nil {
		h.log.Warn("не получены собеседники", "err", err, "user", userID)
		return
	}
	h.Publish(ctx, partners, uuid.Nil, ws.EventPresence, ws.PresenceData{
		UserID:   userID,
		Online:   online,
		LastSeen: time.Now().UTC(),
	})
}

// IsOnline говорит, есть ли у человека живое соединение хоть на каком-то
// инстансе. По нему решается, слать ли пуш.
func (h *Hub) IsOnline(ctx context.Context, userID uuid.UUID) bool {
	n, err := h.rdb.Exists(ctx, presenceKey(userID)).Result()
	if err != nil {
		h.log.Warn("не проверен presence", "err", err, "user", userID)
		return false
	}
	return n > 0
}

// refreshPresence продлевает отметки локально подключённых пользователей.
// Ключ живёт с TTL, поэтому упавший инстанс перестаёт держать своих
// пользователей «в сети» сам по себе, без чужого вмешательства.
func (h *Hub) refreshPresence(ctx context.Context) {
	h.mu.RLock()
	users := make([]uuid.UUID, 0, len(h.conns))
	for id := range h.conns {
		users = append(users, id)
	}
	h.mu.RUnlock()

	if len(users) == 0 {
		return
	}
	pipe := h.rdb.Pipeline()
	for _, id := range users {
		pipe.Set(ctx, presenceKey(id), "1", presenceTTL)
	}
	if _, err := pipe.Exec(ctx); err != nil && !errors.Is(err, context.Canceled) {
		h.log.Warn("не продлён presence", "err", err)
	}
}

// OnlineUsersCount — число пользователей с соединениями на этом инстансе.
func (h *Hub) OnlineUsersCount() int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.conns)
}
