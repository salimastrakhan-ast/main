package realtime_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Базовый сценарий: Аня пишет — Боря получает, не запрашивая ничего.
func TestMessageReachesRecipient(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	ack := anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID:      borya.ID,
		Text:        "привет",
		ClientMsgID: uuid.New(),
	})
	if ack.T != ws.TypeAck {
		t.Fatalf("ответ на отправку = %s, данные: %s", ack.T, ack.D)
	}
	sent := decode[ws.MessageEventData](t, ack)
	if sent.Message.Seq != 1 {
		t.Errorf("первое сообщение получило seq %d, ожидался 1", sent.Message.Seq)
	}
	if sent.Message.SenderID != anya.ID {
		t.Errorf("отправитель %s, ожидался %s", sent.Message.SenderID, anya.ID)
	}

	got := decode[ws.MessageEventData](t, boryaConn.await(ws.EventMessageNew, 3*time.Second))
	if got.Message.Text != "привет" {
		t.Errorf("получен текст %q, ожидался %q", got.Message.Text, "привет")
	}
	if got.Message.ID != sent.Message.ID {
		t.Errorf("получено сообщение %s, отправлено %s", got.Message.ID, sent.Message.ID)
	}
}

// Отправитель не получает эхо собственного сообщения в то же соединение:
// подтверждения ему достаточно.
func TestSenderGetsNoEcho(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID:      borya.ID,
		Text:        "привет",
		ClientMsgID: uuid.New(),
	})
	anyaConn.expectNothing(500 * time.Millisecond)
}

// Второе устройство того же человека обязано увидеть отправленное с первого.
func TestOwnSecondDeviceSeesMessage(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	phone := e.connect(anyaToken)
	defer phone.close()
	// Второй токен того же пользователя — как будто открыт десктоп.
	_, desktopToken := e.newUser("79990000001")
	desktop := e.connect(desktopToken)
	defer desktop.close()

	phone.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID:      borya.ID,
		Text:        "с телефона",
		ClientMsgID: uuid.New(),
	})

	got := decode[ws.MessageEventData](t, desktop.await(ws.EventMessageNew, 3*time.Second))
	if got.Message.Text != "с телефона" {
		t.Errorf("на десктоп пришло %q", got.Message.Text)
	}
}

// Главный сценарий надёжности: клиент был офлайн, за это время пришли
// сообщения, и после переподключения он должен добрать ровно их.
func TestSyncDeliversMissedMessages(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	// Боря был в сети, получил первое сообщение и запомнил курсор.
	boryaConn := e.connect(boryaToken)
	first := decode[ws.MessageEventData](t, func() ws.Envelope {
		anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
			PeerID: borya.ID, Text: "первое", ClientMsgID: uuid.New(),
		})
		return boryaConn.await(ws.EventMessageNew, 3*time.Second)
	}())
	chatID := first.Message.ChatID
	cursor := first.Message.Seq

	// Боря ушёл в туннель.
	boryaConn.close()
	waitFor(t, 3*time.Second, func() bool { return e.hub.OnlineUsersCount() == 1 })

	for _, text := range []string{"второе", "третье", "четвёртое"} {
		anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
			ChatID: chatID, Text: text, ClientMsgID: uuid.New(),
		})
	}

	// Боря вернулся и досинхронизировался со своего курсора.
	boryaConn = e.connect(boryaToken)
	defer boryaConn.close()

	result := decode[ws.SyncResultData](t, boryaConn.call(ws.CmdSync, ws.SyncData{
		Cursors: map[uuid.UUID]int64{chatID: cursor},
	}))

	if len(result.Deltas) != 1 {
		t.Fatalf("дельт %d, ожидалась одна", len(result.Deltas))
	}
	delta := result.Deltas[0]
	if len(delta.Messages) != 3 {
		t.Fatalf("добрано %d сообщений, ожидалось 3", len(delta.Messages))
	}
	for i, want := range []string{"второе", "третье", "четвёртое"} {
		if got := delta.Messages[i].Text; got != want {
			t.Errorf("сообщение %d = %q, ожидалось %q", i, got, want)
		}
	}
	if delta.Truncated {
		t.Error("дельта помечена обрезанной, хотя влезла целиком")
	}

	// Уже прочитанное второй раз не приезжает.
	again := decode[ws.SyncResultData](t, boryaConn.call(ws.CmdSync, ws.SyncData{
		Cursors: map[uuid.UUID]int64{chatID: delta.LastSeq},
	}))
	if len(again.Deltas) != 0 {
		t.Errorf("повторный sync вернул %d дельт, ожидалось 0", len(again.Deltas))
	}
}

// Клиент, который не знает о чате вообще, получает его при первой же
// синхронизации — так работает добавление в группу, пока тебя не было.
func TestSyncDeliversUnknownChat(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "пока тебя не было", ClientMsgID: uuid.New(),
	})

	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	result := decode[ws.SyncResultData](t, boryaConn.call(ws.CmdSync, ws.SyncData{}))
	if len(result.Chats) != 1 {
		t.Fatalf("чатов %d, ожидался один", len(result.Chats))
	}
	if result.Chats[0].UnreadCount != 1 {
		t.Errorf("непрочитанных %d, ожидалось 1", result.Chats[0].UnreadCount)
	}
	if len(result.Deltas) != 1 || len(result.Deltas[0].Messages) != 1 {
		t.Fatalf("дельта не привезла сообщение: %+v", result.Deltas)
	}
}

// Повтор отправки после обрыва связи не должен создавать вторую копию.
// Клиент ретраит при каждом переподключении, и без этого чат заполнялся бы
// дублями.
func TestRetryWithSameClientIDCreatesOneMessage(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	clientMsgID := uuid.New()
	first := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "одно и то же", ClientMsgID: clientMsgID,
	}))
	chatID := first.Message.ChatID

	// Три ретрая подряд — как после нескольких неудачных попыток отправки.
	for i := 0; i < 3; i++ {
		again := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
			ChatID: chatID, Text: "одно и то же", ClientMsgID: clientMsgID,
		}))
		if again.Message.ID != first.Message.ID {
			t.Fatalf("ретрай %d создал новое сообщение %s вместо %s", i, again.Message.ID, first.Message.ID)
		}
		if again.Message.Seq != first.Message.Seq {
			t.Errorf("ретрай %d вернул seq %d вместо %d", i, again.Message.Seq, first.Message.Seq)
		}
	}

	var count int
	err := e.store.Pool().QueryRow(context.Background(),
		`SELECT count(*) FROM messages WHERE chat_id = $1`, chatID).Scan(&count)
	if err != nil {
		t.Fatalf("подсчёт сообщений: %v", err)
	}
	if count != 1 {
		t.Errorf("в базе %d сообщений, ожидалось одно", count)
	}

	// Номера идут подряд: откат транзакции при конфликте не должен оставлять
	// дырок в нумерации, иначе клиент решит, что что-то пропустил.
	next := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: chatID, Text: "следующее", ClientMsgID: uuid.New(),
	}))
	if next.Message.Seq != first.Message.Seq+1 {
		t.Errorf("следующее сообщение получило seq %d, ожидался %d — ретраи сожгли номера",
			next.Message.Seq, first.Message.Seq+1)
	}
}

// Личный чат между двумя людьми ровно один, кто бы ни написал первым.
func TestPrivateChatIsNotDuplicated(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	fromAnya := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "привет", ClientMsgID: uuid.New(),
	}))
	fromBorya := decode[ws.MessageEventData](t, boryaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: anya.ID, Text: "и тебе", ClientMsgID: uuid.New(),
	}))

	if fromAnya.Message.ChatID != fromBorya.Message.ChatID {
		t.Errorf("на встречное сообщение завёлся второй чат: %s и %s",
			fromAnya.Message.ChatID, fromBorya.Message.ChatID)
	}
	if fromBorya.Message.Seq != 2 {
		t.Errorf("встречное сообщение получило seq %d, ожидался 2", fromBorya.Message.Seq)
	}
}

// «Избранное» — это личный чат с самим собой: одно место, куда можно
// отложить ссылку или заметку, и оно синхронизируется между устройствами
// как обычная переписка.
func TestSavedMessagesIsChatWithSelf(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")

	conn := e.connect(anyaToken)
	defer conn.close()

	first := decode[ws.MessageEventData](t, conn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: anya.ID, Text: "не забыть", ClientMsgID: uuid.New(),
	}))
	second := decode[ws.MessageEventData](t, conn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: anya.ID, Text: "и это тоже", ClientMsgID: uuid.New(),
	}))

	if first.Message.ChatID != second.Message.ChatID {
		t.Errorf("на второе сообщение завелось второе «Избранное»: %s и %s",
			first.Message.ChatID, second.Message.ChatID)
	}
	if second.Message.Seq != 2 {
		t.Errorf("второе сообщение получило seq %d, ожидался 2", second.Message.Seq)
	}

	// Участник ровно один: вторая строка с тем же ключом упёрлась бы в
	// первичный ключ, и создание чата упало бы.
	members, err := e.store.MemberIDs(context.Background(), first.Message.ChatID)
	if err != nil {
		t.Fatalf("участники «Избранного»: %v", err)
	}
	if len(members) != 1 || members[0] != anya.ID {
		t.Errorf("в «Избранном» участники %v, ожидался один — %s", members, anya.ID)
	}
}

// В чужой чат писать нельзя, даже зная его идентификатор.
func TestOutsiderCannotWriteToChat(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")
	_, chuzhoyToken := e.newUser("79990000003")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "личное", ClientMsgID: uuid.New(),
	}))

	chuzhoy := e.connect(chuzhoyToken)
	defer chuzhoy.close()

	resp := chuzhoy.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: sent.Message.ChatID, Text: "вклиниваюсь", ClientMsgID: uuid.New(),
	})
	if resp.T != ws.TypeError {
		t.Fatalf("посторонний смог написать в чужой чат: %s %s", resp.T, resp.D)
	}
	if errData := decode[ws.ErrorData](t, resp); errData.Code != ws.ErrCodeForbidden {
		t.Errorf("код ошибки %q, ожидался %q", errData.Code, ws.ErrCodeForbidden)
	}
}

// Без авторизации соединение не живёт.
func TestConnectionRequiresAuth(t *testing.T) {
	e := newEnv(t)
	_, token := e.newUser("79990000001")

	// Валидный токен — соединение поднимается.
	conn := e.connect(token)
	conn.close()

	// Протухший токен — нет.
	expired := e.tokens
	old, err := expired.Issue(uuid.New(), uuid.New(), time.Now().Add(-time.Hour))
	if err != nil {
		t.Fatalf("выпуск токена: %v", err)
	}
	if e.tryConnect(old) {
		t.Error("соединение с протухшим токеном осталось живым")
	}
	if e.tryConnect("мусор") {
		t.Error("соединение с мусорным токеном осталось живым")
	}
}
