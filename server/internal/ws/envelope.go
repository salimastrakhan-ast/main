// Package ws описывает протокол обмена с клиентом.
//
// Кодирование вынесено за интерфейс Codec: сейчас реализация одна, JSON — его
// видно в логах глазами и не нужен codegen в сборке клиента. Когда трафик
// станет дорогим, рядом встанет реализация на Protobuf, а обработчики команд
// не изменятся.
package ws

import (
	"encoding/json"
	"errors"
	"fmt"
)

// Version — версия протокола. Клиент присылает свою в каждом конверте;
// расхождение видно сразу, а не в виде странных ошибок разбора.
const Version = 1

// Envelope — единица обмена в обе стороны.
//
//	{"v":1,"t":"message.send","id":"c-42","d":{...}}
//
// ID заполняется клиентом у команд и возвращается в ответе, чтобы клиент
// сопоставил ответ с запросом. У событий от сервера ID пустой.
type Envelope struct {
	V  int             `json:"v"`
	T  string          `json:"t"`
	ID string          `json:"id,omitempty"`
	D  json.RawMessage `json:"d,omitempty"`
}

// Команды клиента.
const (
	CmdAuth          = "auth"
	CmdSync          = "sync"
	CmdMessageSend   = "message.send"
	CmdMessageEdit   = "message.edit"
	CmdMessageDelete = "message.delete"
	CmdRead          = "read"
	CmdTyping        = "typing"
	CmdChatCreate    = "chat.create"
	CmdChatAddMember = "chat.addMember"
	CmdChatLeave     = "chat.leave"
	CmdPing          = "ping"
)

// Ответы на команды.
const (
	TypeAck   = "ack"
	TypeError = "error"
	TypePong  = "pong"
)

// События сервера.
const (
	EventReady          = "ready"
	EventSyncResult     = "sync.result"
	EventMessageNew     = "message.new"
	EventMessageEdited  = "message.edited"
	EventMessageDeleted = "message.deleted"
	EventReadUpdate     = "read.update"
	EventTyping         = "typing"
	EventPresence       = "presence"
	EventChatUpdate     = "chat.update"
)

// Коды ошибок протокола. Клиент реагирует на код, текст показывает человеку.
const (
	ErrCodeBadRequest  = "bad_request"
	ErrCodeUnauth      = "unauthorized"
	ErrCodeForbidden   = "forbidden"
	ErrCodeNotFound    = "not_found"
	ErrCodeConflict    = "conflict"
	ErrCodeRateLimited = "rate_limited"
	ErrCodeInternal    = "internal"
)

var ErrBadVersion = errors.New("неподдерживаемая версия протокола")

type ErrorData struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// Codec кодирует и декодирует конверты. Реализацию выбирает сервер при
// установке соединения.
type Codec interface {
	Name() string
	Decode(data []byte) (Envelope, error)
	Encode(env Envelope) ([]byte, error)
}

// JSONCodec — реализация по умолчанию.
type JSONCodec struct{}

func (JSONCodec) Name() string { return "json" }

func (JSONCodec) Decode(data []byte) (Envelope, error) {
	var env Envelope
	if err := json.Unmarshal(data, &env); err != nil {
		return Envelope{}, fmt.Errorf("разбор конверта: %w", err)
	}
	if env.V != Version {
		return Envelope{}, fmt.Errorf("%w: получена %d, поддерживается %d", ErrBadVersion, env.V, Version)
	}
	if env.T == "" {
		return Envelope{}, errors.New("в конверте нет типа")
	}
	return env, nil
}

func (JSONCodec) Encode(env Envelope) ([]byte, error) {
	env.V = Version
	data, err := json.Marshal(env)
	if err != nil {
		return nil, fmt.Errorf("сборка конверта: %w", err)
	}
	return data, nil
}

// Event собирает конверт события без привязки к запросу.
func Event(codec Codec, typ string, payload any) ([]byte, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("сериализация события %s: %w", typ, err)
	}
	return codec.Encode(Envelope{T: typ, D: raw})
}

// Reply собирает ответ на команду с её идентификатором.
func Reply(codec Codec, id, typ string, payload any) ([]byte, error) {
	raw, err := json.Marshal(payload)
	if err != nil {
		return nil, fmt.Errorf("сериализация ответа %s: %w", typ, err)
	}
	return codec.Encode(Envelope{T: typ, ID: id, D: raw})
}

func ErrorReply(codec Codec, id, code, message string) ([]byte, error) {
	return Reply(codec, id, TypeError, ErrorData{Code: code, Message: message})
}
