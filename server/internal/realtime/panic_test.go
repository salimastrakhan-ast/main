package realtime_test

import (
	"testing"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Мусор в команде не должен ронять соединение: после отказа по одной
// команде клиент обязан продолжать работать.
func TestBadCommandKeepsConnectionAlive(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	conn := e.connect(anyaToken)
	defer conn.close()

	bad := []struct {
		name string
		typ  string
		data any
	}{
		{"неизвестная команда", "чего-то.странное", map[string]string{}},
		{"отправка без client_msg_id", ws.CmdMessageSend, map[string]string{"text": "привет"}},
		{"отправка без адресата", ws.CmdMessageSend, ws.MessageSendData{
			Text: "привет", ClientMsgID: uuid.New()}},
		{"чтение несуществующего чата", ws.CmdRead, ws.ReadData{ChatID: uuid.New(), UpToSeq: 1}},
		{"правка несуществующего сообщения", ws.CmdMessageEdit, ws.MessageEditData{
			ChatID: uuid.New(), MessageID: uuid.New(), Text: "текст"}},
		{"группа без названия", ws.CmdChatCreate, ws.ChatCreateData{Title: "   "}},
	}

	for _, tc := range bad {
		resp := conn.call(tc.typ, tc.data)
		if resp.T != ws.TypeError {
			t.Errorf("%s: ответ %s, ожидалась ошибка", tc.name, resp.T)
		}
	}

	// Соединение живо и работает.
	if ack := conn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "всё ещё на связи", ClientMsgID: uuid.New(),
	}); ack.T != ws.TypeAck {
		t.Fatalf("после серии отказов соединение сломалось: %s %s", ack.T, ack.D)
	}

	if pong := conn.call(ws.CmdPing, struct{}{}); pong.T != ws.TypePong {
		t.Errorf("ping вернул %s", pong.T)
	}
}
