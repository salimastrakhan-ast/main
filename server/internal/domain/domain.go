// Package domain описывает сущности мессенджера в виде, независимом от
// хранилища и транспорта. Слои store, api и ws общаются между собой этими
// типами.
package domain

import (
	"time"

	"github.com/google/uuid"
)

type ChatType string

const (
	ChatPrivate ChatType = "private"
	ChatGroup   ChatType = "group"
)

type Role string

const (
	RoleOwner  Role = "owner"
	RoleAdmin  Role = "admin"
	RoleMember Role = "member"
)

type AttachmentKind string

const (
	AttachmentImage AttachmentKind = "image"
	AttachmentVideo AttachmentKind = "video"
	AttachmentAudio AttachmentKind = "audio"
	AttachmentFile  AttachmentKind = "file"
)

type User struct {
	ID          uuid.UUID `json:"id"`
	Phone       string    `json:"phone,omitempty"`
	Username    string    `json:"username,omitempty"`
	DisplayName string    `json:"display_name"`
	AvatarURL   string    `json:"avatar_url,omitempty"`

	// AvatarKey — ключ объекта в хранилище. Клиенту не уходит: ему нужна
	// ссылка, а она подписывается заново при каждой выдаче, потому что
	// живёт шесть часов.
	AvatarKey string `json:"-"`

	CreatedAt  time.Time `json:"created_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

// Public отдаёт профиль без телефона — его видит только владелец аккаунта.
func (u User) Public() User {
	u.Phone = ""
	return u
}

type Device struct {
	ID         uuid.UUID `json:"id"`
	UserID     uuid.UUID `json:"user_id"`
	Platform   string    `json:"platform"`
	Name       string    `json:"name"`
	PushToken  string    `json:"-"`
	CreatedAt  time.Time `json:"created_at"`
	LastSeenAt time.Time `json:"last_seen_at"`
}

type Chat struct {
	ID        uuid.UUID `json:"id"`
	Type      ChatType  `json:"type"`
	Title     string    `json:"title"`
	AvatarURL string    `json:"avatar_url,omitempty"`
	CreatedBy uuid.UUID `json:"created_by,omitempty"`
	CreatedAt time.Time `json:"created_at"`
	LastSeq   int64     `json:"last_seq"`
}

type Member struct {
	ChatID      uuid.UUID `json:"chat_id"`
	UserID      uuid.UUID `json:"user_id"`
	Role        Role      `json:"role"`
	JoinedAt    time.Time `json:"joined_at"`
	LastReadSeq int64     `json:"last_read_seq"`
}

// MessageKind различает обычное сообщение и служебную запись.
//
// Служебная — это то, что положил сам сервер: пока только след звонка.
// Клиент рисует её отдельной строкой, а не пузырём.
type MessageKind string

const (
	MessageText MessageKind = "text"
	MessageCall MessageKind = "call"
)

// CallPayload — подробности записи о звонке.
//
// Исход и длительность: «отклонил» и «не ответил» — разные вещи, и в
// истории они должны различаться.
type CallPayload struct {
	Reason  string `json:"reason"`
	Seconds int    `json:"seconds"`
	// Video оставлено на будущее: сигналинг его уже переносит, клиенты
	// пока передают только звук.
	Video bool `json:"video,omitempty"`
}

type Message struct {
	ID       uuid.UUID   `json:"id"`
	ChatID   uuid.UUID   `json:"chat_id"`
	Seq      int64       `json:"seq"`
	SenderID uuid.UUID   `json:"sender_id"`
	Kind     MessageKind `json:"kind,omitempty"`

	// ForwardedFrom — автор оригинала у пересланного сообщения. Клиент
	// подписывает им пузырь: чужой текст не должен выглядеть своим.
	ForwardedFrom *uuid.UUID `json:"forwarded_from,omitempty"`
	// Имя автора рядом — снимком: получатель может быть незнаком с ним, и
	// разрешить идентификатор ему нечем. Снимок ещё и честнее ссылки:
	// позднее переименование чужого профиля не должно менять чужую
	// переписку.
	ForwardedName string       `json:"forwarded_name,omitempty"`
	Payload       *CallPayload `json:"payload,omitempty"`
	Text          string       `json:"text"`
	ReplyToID     *uuid.UUID   `json:"reply_to_id,omitempty"`
	ClientMsgID   uuid.UUID    `json:"client_msg_id"`
	CreatedAt     time.Time    `json:"created_at"`
	EditedAt      *time.Time   `json:"edited_at,omitempty"`
	DeletedAt     *time.Time   `json:"deleted_at,omitempty"`
	Attachments   []Attachment `json:"attachments,omitempty"`
}

type Attachment struct {
	ID        uuid.UUID      `json:"id"`
	Kind      AttachmentKind `json:"kind"`
	ObjectKey string         `json:"-"`
	URL       string         `json:"url,omitempty"`
	FileName  string         `json:"file_name,omitempty"`
	Mime      string         `json:"mime"`
	Size      int64          `json:"size"`
	Width     *int           `json:"width,omitempty"`
	Height    *int           `json:"height,omitempty"`
	Duration  *int           `json:"duration,omitempty"`
}

// ChatSummary — строка в списке диалогов: сам чат, его участники, последнее
// сообщение и число непрочитанного для текущего пользователя.
type ChatSummary struct {
	Chat        Chat     `json:"chat"`
	Members     []Member `json:"members"`
	Users       []User   `json:"users"`
	LastMessage *Message `json:"last_message,omitempty"`
	LastReadSeq int64    `json:"last_read_seq"`
	UnreadCount int64    `json:"unread_count"`

	// Закреплён и беззвучен — для текущего читателя, а не для чата вообще:
	// у каждого участника они свои.
	Pinned bool `json:"pinned"`
	Muted  bool `json:"muted"`
}
