package realtime_test

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Создание группы: участники узнают о ней событием, не спрашивая сервер.
func TestGroupCreationReachesMembers(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")
	vera, veraToken := e.newUser("79990000003")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()
	veraConn := e.connect(veraToken)
	defer veraConn.close()

	ack := anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title:     "Дача",
		MemberIDs: []uuid.UUID{borya.ID, vera.ID},
	})
	if ack.T != ws.TypeAck {
		t.Fatalf("создание группы не удалось: %s %s", ack.T, ack.D)
	}

	for name, conn := range map[string]*client{"Боря": boryaConn, "Вера": veraConn} {
		update := decode[ws.ChatUpdateData](t, conn.await(ws.EventChatUpdate, 3*time.Second))
		if update.Chat.Chat.Title != "Дача" {
			t.Errorf("%s получил чат %q, ожидалась «Дача»", name, update.Chat.Chat.Title)
		}
		if len(update.Chat.Members) != 3 {
			t.Errorf("%s видит %d участников, ожидалось 3", name, len(update.Chat.Members))
		}
	}

	// Создатель становится владельцем, остальные — обычными участниками.
	summary, err := e.store.ChatSummary(t.Context(), chatIDFrom(t, anyaConn), anya.ID)
	if err != nil {
		t.Fatalf("чтение чата: %v", err)
	}
	for _, m := range summary.Members {
		want := domain.RoleMember
		if m.UserID == anya.ID {
			want = domain.RoleOwner
		}
		if m.Role != want {
			t.Errorf("роль участника %s = %q, ожидалась %q", m.UserID, m.Role, want)
		}
	}
}

// chatIDFrom достаёт id единственного чата пользователя.
func chatIDFrom(t *testing.T, c *client) uuid.UUID {
	t.Helper()
	result := decode[ws.SyncResultData](t, c.call(ws.CmdSync, ws.SyncData{}))
	if len(result.Chats) != 1 {
		t.Fatalf("чатов %d, ожидался один", len(result.Chats))
	}
	return result.Chats[0].Chat.ID
}

// Сообщение в группе доходит до всех участников сразу.
func TestGroupMessageReachesEveryone(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")
	vera, veraToken := e.newUser("79990000003")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()
	veraConn := e.connect(veraToken)
	defer veraConn.close()

	anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Дача", MemberIDs: []uuid.UUID{borya.ID, vera.ID},
	})
	chatID := decode[ws.ChatUpdateData](t, boryaConn.await(ws.EventChatUpdate, 3*time.Second)).Chat.Chat.ID
	veraConn.await(ws.EventChatUpdate, 3*time.Second)

	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: chatID, Text: "выезжаем в субботу", ClientMsgID: uuid.New(),
	})

	for name, conn := range map[string]*client{"Боря": boryaConn, "Вера": veraConn} {
		got := decode[ws.MessageEventData](t, conn.await(ws.EventMessageNew, 3*time.Second))
		if got.Message.Text != "выезжаем в субботу" {
			t.Errorf("%s получил %q", name, got.Message.Text)
		}
	}
}

// Добавлять участников может владелец, но не рядовой участник.
func TestOnlyPrivilegedCanAddMembers(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")
	vera, _ := e.newUser("79990000003")
	grisha, grishaToken := e.newUser("79990000004")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Дача", MemberIDs: []uuid.UUID{borya.ID},
	})
	chatID := decode[ws.ChatUpdateData](t, boryaConn.await(ws.EventChatUpdate, 3*time.Second)).Chat.Chat.ID

	// Боря — рядовой участник, добавлять не может.
	resp := boryaConn.call(ws.CmdChatAddMember, ws.ChatAddMemberData{
		ChatID: chatID, UserIDs: []uuid.UUID{vera.ID},
	})
	if resp.T != ws.TypeError {
		t.Fatalf("рядовой участник добавил человека в группу: %s %s", resp.T, resp.D)
	}
	if code := decode[ws.ErrorData](t, resp).Code; code != ws.ErrCodeForbidden {
		t.Errorf("код ошибки %q, ожидался %q", code, ws.ErrCodeForbidden)
	}

	// Аня — владелец, может.
	grishaConn := e.connect(grishaToken)
	defer grishaConn.close()

	if resp := anyaConn.call(ws.CmdChatAddMember, ws.ChatAddMemberData{
		ChatID: chatID, UserIDs: []uuid.UUID{grisha.ID},
	}); resp.T != ws.TypeAck {
		t.Fatalf("владелец не смог добавить участника: %s %s", resp.T, resp.D)
	}

	// Добавленный узнаёт о группе сам, без переподключения.
	update := decode[ws.ChatUpdateData](t, grishaConn.await(ws.EventChatUpdate, 3*time.Second))
	if update.Chat.Chat.ID != chatID {
		t.Errorf("добавленный получил чат %s, ожидался %s", update.Chat.Chat.ID, chatID)
	}
}

// Вышедший из группы перестаёт получать её сообщения.
func TestLeftMemberStopsReceiving(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Дача", MemberIDs: []uuid.UUID{borya.ID},
	})
	chatID := decode[ws.ChatUpdateData](t, boryaConn.await(ws.EventChatUpdate, 3*time.Second)).Chat.Chat.ID

	if resp := boryaConn.call(ws.CmdChatLeave, ws.ChatLeaveData{ChatID: chatID}); resp.T != ws.TypeAck {
		t.Fatalf("выход из группы не удался: %s %s", resp.T, resp.D)
	}
	// Вышедшему приходит подтверждение, что чат у него закрылся.
	gone := decode[ws.ChatUpdateData](t, boryaConn.await(ws.EventChatUpdate, 3*time.Second))
	if !gone.Gone {
		t.Error("событие о выходе не помечено gone")
	}

	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: chatID, Text: "уже без Бори", ClientMsgID: uuid.New(),
	})
	boryaConn.expectNothing(700 * time.Millisecond)
}

// Отметка прочитанного двигает курсор и видна собеседнику.
func TestReadReceiptsReachSender(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "прочитай", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	boryaConn.call(ws.CmdRead, ws.ReadData{ChatID: sent.Message.ChatID, UpToSeq: sent.Message.Seq})

	update := decode[ws.ReadUpdateData](t, anyaConn.await(ws.EventReadUpdate, 3*time.Second))
	if update.LastReadSeq != sent.Message.Seq {
		t.Errorf("курсор чтения %d, ожидался %d", update.LastReadSeq, sent.Message.Seq)
	}
	if update.UserID != borya.ID {
		t.Errorf("прочитавший %s, ожидался %s", update.UserID, borya.ID)
	}
}

// Курсор прочитанного двигается только вперёд: пришедшее не по порядку
// событие не должно снова делать сообщения непрочитанными.
func TestReadCursorNeverGoesBack(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	var chatID uuid.UUID
	var lastSeq int64
	for i := 0; i < 3; i++ {
		sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
			PeerID: borya.ID, Text: "раз", ClientMsgID: uuid.New(),
		}))
		chatID, lastSeq = sent.Message.ChatID, sent.Message.Seq
		boryaConn.await(ws.EventMessageNew, 3*time.Second)
	}

	boryaConn.call(ws.CmdRead, ws.ReadData{ChatID: chatID, UpToSeq: lastSeq})
	anyaConn.await(ws.EventReadUpdate, 3*time.Second)

	// Опоздавшая отметка на более раннее сообщение.
	ack := boryaConn.call(ws.CmdRead, ws.ReadData{ChatID: chatID, UpToSeq: 1})
	if got := decode[ws.ReadUpdateData](t, ack).LastReadSeq; got != lastSeq {
		t.Errorf("курсор откатился до %d, должен был остаться на %d", got, lastSeq)
	}
	// Раз курсор не сдвинулся, собеседнику ничего не рассылается.
	anyaConn.expectNothing(500 * time.Millisecond)
}

// Правка видна собеседнику, а чужое сообщение править нельзя.
func TestEditMessage(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "превет", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	ack := anyaConn.call(ws.CmdMessageEdit, ws.MessageEditData{
		ChatID: sent.Message.ChatID, MessageID: sent.Message.ID, Text: "привет",
	})
	if ack.T != ws.TypeAck {
		t.Fatalf("правка не удалась: %s %s", ack.T, ack.D)
	}
	edited := decode[ws.MessageEventData](t, ack)
	if edited.Message.EditedAt == nil {
		t.Error("у отредактированного сообщения не проставлен edited_at")
	}
	if edited.Message.Seq != sent.Message.Seq {
		t.Errorf("правка сдвинула позицию в ленте: seq %d вместо %d", edited.Message.Seq, sent.Message.Seq)
	}

	got := decode[ws.MessageEventData](t, boryaConn.await(ws.EventMessageEdited, 3*time.Second))
	if got.Message.Text != "привет" {
		t.Errorf("собеседник видит %q, ожидалось «привет»", got.Message.Text)
	}

	// Чужое сообщение править нельзя.
	if resp := boryaConn.call(ws.CmdMessageEdit, ws.MessageEditData{
		ChatID: sent.Message.ChatID, MessageID: sent.Message.ID, Text: "подмена",
	}); resp.T != ws.TypeError {
		t.Errorf("удалось отредактировать чужое сообщение: %s %s", resp.T, resp.D)
	}
}

// Удаление стирает текст и доезжает до собеседника.
func TestDeleteMessage(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "ой, не туда", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	ack := anyaConn.call(ws.CmdMessageDelete, ws.MessageDeleteData{
		ChatID: sent.Message.ChatID, MessageID: sent.Message.ID,
	})
	if ack.T != ws.TypeAck {
		t.Fatalf("удаление не удалось: %s %s", ack.T, ack.D)
	}

	got := decode[ws.MessageEventData](t, boryaConn.await(ws.EventMessageDeleted, 3*time.Second))
	if got.Message.DeletedAt == nil {
		t.Error("у удалённого сообщения не проставлен deleted_at")
	}
	if got.Message.Text != "" {
		t.Errorf("текст удалённого сообщения остался: %q", got.Message.Text)
	}
}

// Правка, сделанная пока собеседник был офлайн, доезжает при синхронизации.
// Ради этого номер изменения выдаётся не только новым сообщениям.
func TestSyncDeliversEditsMadeWhileOffline(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "превет", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)
	chatID, cursor := sent.Message.ChatID, sent.Message.Seq

	boryaConn.close()
	waitFor(t, 3*time.Second, func() bool { return e.hub.OnlineUsersCount() == 1 })

	anyaConn.call(ws.CmdMessageEdit, ws.MessageEditData{
		ChatID: chatID, MessageID: sent.Message.ID, Text: "привет",
	})

	boryaConn = e.connect(boryaToken)
	defer boryaConn.close()

	result := decode[ws.SyncResultData](t, boryaConn.call(ws.CmdSync, ws.SyncData{
		Cursors: map[uuid.UUID]int64{chatID: cursor},
	}))
	if len(result.Deltas) != 1 || len(result.Deltas[0].Messages) != 1 {
		t.Fatalf("правка не приехала в дельте: %+v", result.Deltas)
	}
	msg := result.Deltas[0].Messages[0]
	if msg.Text != "привет" {
		t.Errorf("в дельте текст %q, ожидался «привет»", msg.Text)
	}
	if msg.ID != sent.Message.ID {
		t.Errorf("в дельте другое сообщение: %s вместо %s", msg.ID, sent.Message.ID)
	}
}

// Печатание рассылается собеседнику и не пишется в базу.
func TestTypingIsBroadcast(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "привет", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	before := chatLastSeq(t, e, sent.Message.ChatID)
	// typing — единственная команда без подтверждения: подтверждать каждое
	// нажатие клавиши значит удвоить трафик ради ничего.
	anyaConn.sendRaw(ws.CmdTyping, "", ws.TypingData{ChatID: sent.Message.ChatID})

	typing := decode[ws.TypingEventData](t, boryaConn.await(ws.EventTyping, 3*time.Second))
	if typing.UserID != anya.ID {
		t.Errorf("печатает %s, ожидалась %s", typing.UserID, anya.ID)
	}
	if after := chatLastSeq(t, e, sent.Message.ChatID); after != before {
		t.Errorf("печатание сожгло номер: %d вместо %d", after, before)
	}
}

func chatLastSeq(t *testing.T, e *env, chatID uuid.UUID) int64 {
	t.Helper()
	chat, err := e.store.ChatByID(t.Context(), chatID)
	if err != nil {
		t.Fatalf("чтение чата: %v", err)
	}
	return chat.LastSeq
}

// Появление и уход собеседника видны в presence.
func TestPresenceReachesChatPartners(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	// Заводим общий чат — до него они друг другу никто.
	boryaConn := e.connect(boryaToken)
	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "привет", ClientMsgID: uuid.New(),
	})
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	boryaConn.close()
	offline := decode[ws.PresenceData](t, anyaConn.await(ws.EventPresence, 3*time.Second))
	if offline.UserID != borya.ID || offline.Online {
		t.Errorf("ожидался уход Бори, пришло %+v", offline)
	}

	boryaConn = e.connect(boryaToken)
	defer boryaConn.close()
	online := decode[ws.PresenceData](t, anyaConn.await(ws.EventPresence, 3*time.Second))
	if online.UserID != borya.ID || !online.Online {
		t.Errorf("ожидалось появление Бори, пришло %+v", online)
	}

	if !e.hub.IsOnline(t.Context(), anya.ID) {
		t.Error("Аня подключена, но считается офлайн")
	}
}
