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

// ChatPinData — закрепить или открепить чат.
type ChatPinData struct {
	ChatID uuid.UUID `json:"chat_id"`
	Pinned bool      `json:"pinned"`
}

// ChatMuteData — выключить звук чата.
//
// Пустой Until означает «вернуть звук»: отдельного поля «включить» не надо,
// а срок позволяет «на час» — то, о чём просят чаще, чем о вечной тишине.
type ChatMuteData struct {
	ChatID uuid.UUID  `json:"chat_id"`
	Until  *time.Time `json:"until,omitempty"`
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

// --- Звонки ---
//
// Сервер пересылает SDP и ICE-кандидатов между двумя людьми и не разбирает
// их содержимое: это описания соединения для WebRTC, и понимать их должны
// клиенты, а не он. Звук через сервер не идёт вовсе — он идёт напрямую
// между устройствами или, если сеть не даёт, через TURN.

// CallStartData — предложение соединения от звонящего.
//
// Адресат задаётся либо чатом, либо собеседником — как у message.send.
// Второе нужно, чтобы позвонить найденному человеку, не написав ему
// сначала: переписки с ним ещё нет, а звонить уже хочется.
type CallStartData struct {
	ChatID uuid.UUID `json:"chat_id,omitempty"`
	PeerID uuid.UUID `json:"peer_id,omitempty"`
	SDP    string    `json:"sdp"`
	Video  bool      `json:"video,omitempty"`
}

type CallAnswerData struct {
	CallID uuid.UUID `json:"call_id"`
	SDP    string    `json:"sdp"`
}

// CallICEData — очередной способ дозвониться, найденный клиентом.
//
// Кандидаты идут отдельно от SDP и по мере нахождения: ждать, пока клиент
// переберёт все сети, значит добавить к соединению несколько секунд тишины.
type CallICEData struct {
	CallID    uuid.UUID `json:"call_id"`
	Candidate string    `json:"candidate"`
	SDPMid    string    `json:"sdp_mid,omitempty"`
	SDPMLine  *int      `json:"sdp_m_line_index,omitempty"`
}

type CallHangupData struct {
	CallID uuid.UUID `json:"call_id"`
	Reason string    `json:"reason,omitempty"`
}

// CallStartedData — ответ звонящему на его call.start.
//
// Status говорит, звонит ли у собеседника телефон: если его нет в сети,
// незачем держать человека сорок секунд у гудков.
type CallStartedData struct {
	CallID uuid.UUID `json:"call_id"`
	Status string    `json:"status"` // "ringing" или "offline"
}

// CallIncomingData — входящий звонок.
type CallIncomingData struct {
	CallID uuid.UUID   `json:"call_id"`
	ChatID uuid.UUID   `json:"chat_id"`
	From   domain.User `json:"from"`
	SDP    string      `json:"sdp"`
	Video  bool        `json:"video,omitempty"`
}

type CallAcceptedData struct {
	CallID uuid.UUID `json:"call_id"`
	SDP    string    `json:"sdp"`
}

// CallEndedData — звонок закончился. Reason из констант CallEnd*.
type CallEndedData struct {
	CallID uuid.UUID `json:"call_id"`
	Reason string    `json:"reason"`
}
