package realtime

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/push"
	"github.com/salimastrakhan-ast/main/server/internal/store"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

const maxTextLen = 8192

func decodeData(env ws.Envelope, dst any) error {
	if len(env.D) == 0 {
		return errors.New("в команде нет данных")
	}
	if err := json.Unmarshal(env.D, dst); err != nil {
		return fmt.Errorf("разбор данных команды %s: %w", env.T, err)
	}
	return nil
}

func (c *Conn) handle(ctx context.Context, env ws.Envelope) {
	switch env.T {
	case ws.CmdPing:
		c.reply(env.ID, ws.TypePong, struct{}{})
	case ws.CmdSync:
		c.handleSync(ctx, env)
	case ws.CmdMessageSend:
		c.handleSend(ctx, env)
	case ws.CmdMessageEdit:
		c.handleEdit(ctx, env)
	case ws.CmdMessageDelete:
		c.handleDelete(ctx, env)
	case ws.CmdRead:
		c.handleRead(ctx, env)
	case ws.CmdTyping:
		c.handleTyping(ctx, env)
	case ws.CmdChatCreate:
		c.handleChatCreate(ctx, env)
	case ws.CmdChatAddMember:
		c.handleAddMember(ctx, env)
	case ws.CmdChatLeave:
		c.handleLeave(ctx, env)
	case ws.CmdAuth:
		c.replyError(env.ID, ws.ErrCodeConflict, "Соединение уже авторизовано")
	default:
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Неизвестная команда: "+env.T)
	}
}

// fail переводит ошибки хранилища в коды протокола.
func (c *Conn) fail(id string, err error) {
	switch {
	case errors.Is(err, store.ErrForbidden):
		c.replyError(id, ws.ErrCodeForbidden, "Нет доступа")
	case errors.Is(err, store.ErrNotFound):
		c.replyError(id, ws.ErrCodeNotFound, "Не найдено")
	case errors.Is(err, store.ErrConflict):
		c.replyError(id, ws.ErrCodeConflict, "Конфликт")
	default:
		c.log.Error("ошибка обработки команды", "err", err)
		c.replyError(id, ws.ErrCodeInternal, "Внутренняя ошибка")
	}
}

// handleSync отдаёт всё, что клиент пропустил.
//
// Клиент присылает свои курсоры по чатам. Сервер возвращает список диалогов
// целиком (он нужен, чтобы узнать о новых чатах и пересчитать непрочитанное)
// и дельту по каждому чату, где курсор отстал.
func (c *Conn) handleSync(ctx context.Context, env ws.Envelope) {
	var payload ws.SyncData
	if len(env.D) > 0 {
		if err := decodeData(env, &payload); err != nil {
			c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
			return
		}
	}

	summaries, err := c.hub.store.ChatSummaries(ctx, c.userID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}

	deltas := make([]ws.Delta, 0, len(summaries))
	for _, s := range summaries {
		cursor := payload.Cursors[s.Chat.ID]
		if cursor >= s.Chat.LastSeq {
			continue // Клиент в курсе всего, что было в этом чате.
		}
		msgs, truncated, err := c.hub.store.MessagesSince(ctx, s.Chat.ID, cursor, syncChatLimit)
		if err != nil {
			c.fail(env.ID, err)
			return
		}
		if len(msgs) == 0 {
			continue
		}
		deltas = append(deltas, ws.Delta{
			ChatID:    s.Chat.ID,
			Messages:  msgs,
			Truncated: truncated,
			LastSeq:   s.Chat.LastSeq,
		})
	}

	c.reply(env.ID, ws.EventSyncResult, ws.SyncResultData{Chats: summaries, Deltas: deltas})
}

func (c *Conn) handleSend(ctx context.Context, env ws.Envelope) {
	var payload ws.MessageSendData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	if payload.ClientMsgID == uuid.Nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Нужен client_msg_id")
		return
	}

	text := strings.TrimSpace(payload.Text)
	if len(text) > maxTextLen {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Сообщение слишком длинное")
		return
	}
	if text == "" && len(payload.AttachmentIDs) == 0 {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Пустое сообщение")
		return
	}

	chatID := payload.ChatID
	if chatID == uuid.Nil {
		// Отправка по собеседнику: личный чат заводится на лету.
		if payload.PeerID == uuid.Nil {
			c.replyError(env.ID, ws.ErrCodeBadRequest, "Нужен chat_id или peer_id")
			return
		}
		chat, err := c.hub.store.EnsurePrivateChat(ctx, c.userID, payload.PeerID)
		if err != nil {
			c.fail(env.ID, err)
			return
		}
		chatID = chat.ID
		// О новом чате надо рассказать обоим — иначе собеседник увидит
		// сообщение в чате, которого у него ещё нет.
		c.announceChat(ctx, chatID)
	}

	msg, created, err := c.hub.store.SendMessage(ctx, store.NewMessage{
		ChatID:        chatID,
		SenderID:      c.userID,
		Text:          text,
		ReplyToID:     payload.ReplyToID,
		ClientMsgID:   payload.ClientMsgID,
		AttachmentIDs: payload.AttachmentIDs,
	})
	if err != nil {
		c.fail(env.ID, err)
		return
	}

	// Ответ уходит всегда, в том числе на повтор: клиент ждёт подтверждения,
	// чтобы снять сообщение с очереди отправки.
	c.reply(env.ID, ws.TypeAck, ws.MessageEventData{Message: msg})

	if !created {
		return // Повтор после обрыва: событие адресатам уже уходило.
	}
	members, err := c.hub.store.MemberIDs(ctx, chatID)
	if err != nil {
		c.log.Error("не получены адресаты", "err", err, "chat", chatID)
		return
	}
	c.hub.Publish(ctx, members, c.id, ws.EventMessageNew, ws.MessageEventData{Message: msg})
	c.hub.notifyOffline(ctx, msg, members)
}

func (c *Conn) handleEdit(ctx context.Context, env ws.Envelope) {
	var payload ws.MessageEditData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	text := strings.TrimSpace(payload.Text)
	if text == "" || len(text) > maxTextLen {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Некорректный текст")
		return
	}

	msg, err := c.hub.store.EditMessage(ctx, payload.ChatID, payload.MessageID, c.userID, text)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	c.reply(env.ID, ws.TypeAck, ws.MessageEventData{Message: msg})
	c.broadcast(ctx, payload.ChatID, ws.EventMessageEdited, ws.MessageEventData{Message: msg})
}

func (c *Conn) handleDelete(ctx context.Context, env ws.Envelope) {
	var payload ws.MessageDeleteData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	msg, err := c.hub.store.DeleteMessage(ctx, payload.ChatID, payload.MessageID, c.userID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	c.reply(env.ID, ws.TypeAck, ws.MessageEventData{Message: msg})
	c.broadcast(ctx, payload.ChatID, ws.EventMessageDeleted, ws.MessageEventData{Message: msg})
}

func (c *Conn) handleRead(ctx context.Context, env ws.Envelope) {
	var payload ws.ReadData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	current, moved, err := c.hub.store.MarkRead(ctx, payload.ChatID, c.userID, payload.UpToSeq)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	update := ws.ReadUpdateData{ChatID: payload.ChatID, UserID: c.userID, LastReadSeq: current}
	c.reply(env.ID, ws.TypeAck, update)

	if !moved {
		return // Курсор не сдвинулся — рассказывать нечего.
	}
	c.broadcast(ctx, payload.ChatID, ws.EventReadUpdate, update)
}

// handleTyping — единственная команда, которая ничего не пишет в базу.
// Событие живёт секунды, и хранить его негде и незачем.
func (c *Conn) handleTyping(ctx context.Context, env ws.Envelope) {
	var payload ws.TypingData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	if _, err := c.hub.store.Membership(ctx, payload.ChatID, c.userID); err != nil {
		c.fail(env.ID, err)
		return
	}
	c.broadcast(ctx, payload.ChatID, ws.EventTyping,
		ws.TypingEventData{ChatID: payload.ChatID, UserID: c.userID})
}

func (c *Conn) handleChatCreate(ctx context.Context, env ws.Envelope) {
	var payload ws.ChatCreateData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	title := strings.TrimSpace(payload.Title)
	if title == "" {
		c.replyError(env.ID, ws.ErrCodeBadRequest, "Нужно название группы")
		return
	}

	chat, err := c.hub.store.CreateGroup(ctx, c.userID, title, payload.MemberIDs)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	c.reply(env.ID, ws.TypeAck, map[string]any{"chat": chat})
	c.announceChat(ctx, chat.ID)
}

func (c *Conn) handleAddMember(ctx context.Context, env ws.Envelope) {
	var payload ws.ChatAddMemberData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	member, err := c.hub.store.Membership(ctx, payload.ChatID, c.userID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	if member.Role == domain.RoleMember {
		c.replyError(env.ID, ws.ErrCodeForbidden, "Добавлять участников может владелец или админ")
		return
	}
	if err := c.hub.store.AddMembers(ctx, payload.ChatID, payload.UserIDs); err != nil {
		c.fail(env.ID, err)
		return
	}
	c.reply(env.ID, ws.TypeAck, struct{}{})
	c.announceChat(ctx, payload.ChatID)
}

func (c *Conn) handleLeave(ctx context.Context, env ws.Envelope) {
	var payload ws.ChatLeaveData
	if err := decodeData(env, &payload); err != nil {
		c.replyError(env.ID, ws.ErrCodeBadRequest, err.Error())
		return
	}
	// Адресатов берём до удаления: вышедшему тоже надо сказать, что чат
	// у него закрылся, а после DELETE его в списке уже не будет.
	members, err := c.hub.store.MemberIDs(ctx, payload.ChatID)
	if err != nil {
		c.fail(env.ID, err)
		return
	}
	if err := c.hub.store.RemoveMember(ctx, payload.ChatID, c.userID); err != nil {
		c.fail(env.ID, err)
		return
	}
	c.reply(env.ID, ws.TypeAck, struct{}{})

	c.hub.Publish(ctx, members, uuid.Nil, ws.EventChatUpdate, ws.ChatUpdateData{
		Chat: domain.ChatSummary{Chat: domain.Chat{ID: payload.ChatID}},
		Gone: true,
	})
}

// broadcast рассылает событие участникам чата, кроме соединения-источника.
func (c *Conn) broadcast(ctx context.Context, chatID uuid.UUID, typ string, payload any) {
	members, err := c.hub.store.MemberIDs(ctx, chatID)
	if err != nil {
		c.log.Error("не получены адресаты", "err", err, "chat", chatID)
		return
	}
	c.hub.Publish(ctx, members, c.id, typ, payload)
}

// announceChat рассылает участникам актуальное состояние чата.
//
// Каждому уходит его собственная версия: непрочитанное и курсор чтения у всех
// свои, и подставлять чужие числа нельзя.
func (c *Conn) announceChat(ctx context.Context, chatID uuid.UUID) {
	members, err := c.hub.store.MemberIDs(ctx, chatID)
	if err != nil {
		c.log.Error("не получены адресаты", "err", err, "chat", chatID)
		return
	}
	for _, userID := range members {
		summary, err := c.hub.store.ChatSummary(ctx, chatID, userID)
		if err != nil {
			c.log.Error("не собран чат для рассылки", "err", err, "chat", chatID, "user", userID)
			continue
		}
		c.hub.Publish(ctx, []uuid.UUID{userID}, uuid.Nil, ws.EventChatUpdate,
			ws.ChatUpdateData{Chat: summary})
	}
}

// notifyOffline шлёт пуш тем участникам, у кого сейчас нет соединения.
func (h *Hub) notifyOffline(ctx context.Context, msg domain.Message, members []uuid.UUID) {
	offline := make([]uuid.UUID, 0, len(members))
	for _, id := range members {
		if id == msg.SenderID {
			continue
		}
		if !h.IsOnline(ctx, id) {
			offline = append(offline, id)
		}
	}
	if len(offline) == 0 {
		return
	}

	tokens, err := h.store.PushTokensFor(ctx, offline)
	if err != nil {
		h.log.Error("не получены push-токены", "err", err)
		return
	}
	sender, err := h.store.UserByID(ctx, msg.SenderID)
	if err != nil {
		h.log.Error("не получен отправитель", "err", err)
		return
	}

	for _, userID := range offline {
		deviceTokens := tokens[userID]
		if len(deviceTokens) == 0 {
			continue
		}
		badge, err := h.store.UnreadCount(ctx, msg.ChatID, userID)
		if err != nil {
			h.log.Warn("не посчитано непрочитанное", "err", err)
		}
		if err := h.pusher.Push(ctx, push.Notification{
			UserID: userID,
			ChatID: msg.ChatID,
			Title:  sender.DisplayName,
			Body:   msg.Text,
			Badge:  badge,
			Tokens: deviceTokens,
		}); err != nil {
			h.log.Error("не отправлен пуш", "err", err, "user", userID)
		}
	}
}
