package realtime_test

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Пуш уходит только тому, кого нет в сети: у человека с открытым чатом
// сообщение и так уже на экране.
func TestPushGoesOnlyToOfflineRecipient(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	// У Бори есть устройство с push-токеном.
	device, err := e.store.CreateDevice(t.Context(), borya.ID, "android", "телефон", []byte("хэш"))
	if err != nil {
		t.Fatalf("создание устройства: %v", err)
	}
	if err := e.store.SetPushToken(t.Context(), device.ID, "rustore-token-123"); err != nil {
		t.Fatalf("сохранение push-токена: %v", err)
	}

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	// Боря в сети — пуша быть не должно.
	boryaConn := e.connect(boryaToken)
	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "пока ты тут", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	if got := len(e.pushes.all()); got != 0 {
		t.Errorf("пушей отправлено %d, ожидалось 0: получатель был в сети", got)
	}

	// Боря ушёл — теперь пуш нужен.
	boryaConn.close()
	waitFor(t, 3*time.Second, func() bool { return e.hub.OnlineUsersCount() == 1 })

	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: sent.Message.ChatID, Text: "а теперь нет", ClientMsgID: uuid.New(),
	})

	var notifications int
	waitFor(t, 3*time.Second, func() bool {
		notifications = len(e.pushes.all())
		return notifications > 0
	})

	n := e.pushes.all()[0]
	if n.UserID != borya.ID {
		t.Errorf("пуш ушёл %s, ожидался Боре %s", n.UserID, borya.ID)
	}
	if n.Body != "а теперь нет" {
		t.Errorf("текст пуша %q", n.Body)
	}
	if len(n.Tokens) != 1 || n.Tokens[0] != "rustore-token-123" {
		t.Errorf("токены в пуше: %v", n.Tokens)
	}
	if n.Badge != 2 {
		t.Errorf("бейдж %d, ожидалось 2 непрочитанных", n.Badge)
	}
}

// Отправителю пуш не приходит, даже если у него есть другие устройства.
func TestNoPushToSender(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	device, err := e.store.CreateDevice(t.Context(), anya.ID, "android", "второй", []byte("хэш"))
	if err != nil {
		t.Fatalf("создание устройства: %v", err)
	}
	if err := e.store.SetPushToken(t.Context(), device.ID, "токен-отправителя"); err != nil {
		t.Fatalf("сохранение push-токена: %v", err)
	}

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "сам себе", ClientMsgID: uuid.New(),
	})

	time.Sleep(300 * time.Millisecond)
	for _, n := range e.pushes.all() {
		if n.UserID == anya.ID {
			t.Errorf("отправителю ушёл пуш: %+v", n)
		}
	}
}
