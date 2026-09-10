package ws

import (
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
)

// --- Команды клиента ---

// AuthData — первый кадр в соединении. До него сервер не принимает ничего.
type AuthData struct {
	Token string `json:"token"`
}

// SyncData — курсоры клиента: чат и последний известный ему updated_seq.
// Чаты, которых нет в карте, клиент получит целиком.
type SyncData struct {
	Cursors map[uuid.UUID]int64 `json:"cursors"`
}

// MessageSendData — отправка сообщения.
//
// Адресат задаётся либо чатом, либо собеседником: во втором случае личный чат
// заводится на лету, отдельной кнопки «создать диалог» в мессенджере нет.
//
// ClientMsgID клиент генерирует ДО отправки. Повтор с тем же значением
// возвращает уже созданное сообщение вместо второй копии.
type MessageSendData struct {
	ChatID        uuid.UUID   `json:"chat_id,omitempty"`
	PeerID        uuid.UUID   `json:"peer_id,omitempty"`
	Text          string      `json:"text"`
	ReplyToID     *uuid.UUID  `json:"reply_to_id,omitempty"`
	ClientMsgID   uuid.UUID   `json:"client_msg_id"`
	AttachmentIDs []uuid.UUID `json:"attachment_ids,omitempty"`
}

type MessageEditData struct {
	ChatID    uuid.UUID `json:"chat_id"`
	MessageID uuid.UUID `json:"message_id"`
	Text      string    `json:"text"`
}

type MessageDeleteData struct {
	ChatID    uuid.UUID `json:"chat_id"`
	MessageID uuid.UUID `json:"message_id"`
}

type ReadData struct {
	ChatID  uuid.UUID `json:"chat_id"`
	UpToSeq int64     `json:"up_to_seq"`
}

type TypingData struct {
	ChatID uuid.UUID `json:"chat_id"`
}

type ChatCreateData struct {
	Title     string      `json:"title"`
	MemberIDs []uuid.UUID `json:"member_ids"`
}

type ChatAddMemberData struct {
	ChatID  uuid.UUID   `json:"chat_id"`
	UserIDs []uuid.UUID `json:"user_ids"`
}

type ChatLeaveData struct {
	ChatID uuid.UUID `json:"chat_id"`
}

// --- События сервера ---

// ReadyData отправляется сразу после успешной авторизации соединения.
type ReadyData struct {
	User      domain.User `json:"user"`
	SessionID string      `json:"session_id"`
	Codec     string      `json:"codec"`
}

// Delta — то, что клиент пропустил в одном чате.
// Truncated означает, что пропущено больше, чем влезло в один ответ, и
// остаток надо дочитать через GET /v1/chats/{id}/messages.
type Delta struct {
	ChatID    uuid.UUID        `json:"chat_id"`
	Messages  []domain.Message `json:"messages"`
	Truncated bool             `json:"truncated"`
	LastSeq   int64            `json:"last_seq"`
}

type SyncResultData struct {
	Chats  []domain.ChatSummary `json:"chats"`
	Deltas []Delta              `json:"deltas"`
}

type MessageEventData struct {
	Message domain.Message `json:"message"`
}

type ReadUpdateData struct {
	ChatID      uuid.UUID `json:"chat_id"`
	UserID      uuid.UUID `json:"user_id"`
	LastReadSeq int64     `json:"last_read_seq"`
}

type TypingEventData struct {
	ChatID uuid.UUID `json:"chat_id"`
	UserID uuid.UUID `json:"user_id"`
}

type PresenceData struct {
	UserID   uuid.UUID `json:"user_id"`
	Online   bool      `json:"online"`
	LastSeen time.Time `json:"last_seen"`
}

// ChatUpdateData сообщает о новом чате или изменении состава.
// Событие приходит и тому, кого только что добавили в группу.
type ChatUpdateData struct {
	Chat domain.ChatSummary `json:"chat"`
	Gone bool               `json:"gone,omitempty"`
}
