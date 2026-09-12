package realtime_test

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Удаление чата и состав группы — про права. Ошибка здесь не «неудобно»,
// а «посторонний стёр переписку», поэтому проверяется каждый отказ.

// awaitGone ждёт «чата больше нет» по конкретному чату.
//
// Не первое попавшееся chat.update: до него приезжают события о создании
// группы и смене состава, и брать первое — значит проверять не то.
func awaitGone(c *client, chatID uuid.UUID) bool {
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		env := c.read(time.Until(deadline))
		if env.T != ws.EventChatUpdate {
			continue
		}
		update := decode[ws.ChatUpdateData](c.t, env)
		if update.Chat.Chat.ID == chatID && update.Gone {
			return true
		}
	}
	return false
}

func TestУчастникНеИсключаетДругих(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79002220001")
	borya, boryaToken := e.newUser("79002220002")
	vita, _ := e.newUser("79002220003")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	group := decode[chatCreated](t, anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Планёрка", MemberIDs: []uuid.UUID{borya.ID, vita.ID},
	}))

	reply := boryaConn.call(ws.CmdChatRemoveMem, ws.ChatRemoveMemberData{
		ChatID: group.Chat.ID, UserID: vita.ID,
	})
	if reply.T != ws.TypeError {
		t.Fatal("обычный участник исключил другого")
	}
	if code := decode[ws.ErrorData](t, reply).Code; code != ws.ErrCodeForbidden {
		t.Errorf("отказ кодом %q вместо forbidden", code)
	}
}

func TestВладелецИсключаетУчастника(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79002220004")
	borya, boryaToken := e.newUser("79002220005")
	vita, _ := e.newUser("79002220006")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	group := decode[chatCreated](t, anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Планёрка", MemberIDs: []uuid.UUID{borya.ID, vita.ID},
	}))

	reply := anyaConn.call(ws.CmdChatRemoveMem, ws.ChatRemoveMemberData{
		ChatID: group.Chat.ID, UserID: borya.ID,
	})
	if reply.T == ws.TypeError {
		t.Fatalf("владелец не смог исключить: %s", reply.D)
	}

	// Исключённый должен узнать, что чат у него закрылся, — иначе он
	// остаётся в списке мёртвой строкой. Ждём именно это событие: до него
	// придёт chat.update о создании группы.
	if !awaitGone(boryaConn, group.Chat.ID) {
		t.Error("исключённому не сказали, что чата больше нет")
	}

	members, err := e.store.MemberIDs(context.Background(), group.Chat.ID)
	if err != nil {
		t.Fatalf("состав: %v", err)
	}
	if len(members) != 2 {
		t.Errorf("в группе осталось %d участников вместо 2", len(members))
	}
}

func TestВладельцаИсключитьНельзя(t *testing.T) {
	// Иначе админ выставил бы из группы того, кто её создал, и вернуть его
	// было бы некому.
	e := newEnv(t)
	anya, anyaToken := e.newUser("79002220007")
	borya, boryaToken := e.newUser("79002220008")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	group := decode[chatCreated](t, anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Планёрка", MemberIDs: []uuid.UUID{borya.ID},
	}))

	reply := boryaConn.call(ws.CmdChatRemoveMem, ws.ChatRemoveMemberData{
		ChatID: group.Chat.ID, UserID: anya.ID,
	})
	if reply.T != ws.TypeError {
		t.Fatal("владельца исключили")
	}
}

func TestУдалениеЧатаУСебяНеТрогаетСобеседника(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79002220009")
	borya, boryaToken := e.newUser("79002220010")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	chatID := e.privateChat(anyaConn, borya.ID)
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	anyaConn.call(ws.CmdChatDelete, ws.ChatDeleteData{ChatID: chatID})

	// У Бори переписка на месте: он о ней ничего не просил.
	summaries, err := e.store.ChatSummaries(context.Background(), borya.ID)
	if err != nil {
		t.Fatalf("список чатов: %v", err)
	}
	found := false
	for _, s := range summaries {
		if s.Chat.ID == chatID {
			found = true
		}
	}
	if !found {
		t.Error("удаление у себя стёрло переписку и у собеседника")
	}
}

func TestУдалитьУВсехВЛичнойПерепискеНельзя(t *testing.T) {
	// Стереть историю у собеседника без его ведома — не то, что человек
	// вправе сделать чужими руками.
	e := newEnv(t)
	_, anyaToken := e.newUser("79002220011")
	borya, _ := e.newUser("79002220012")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	chatID := e.privateChat(anyaConn, borya.ID)
	reply := anyaConn.call(ws.CmdChatDelete, ws.ChatDeleteData{
		ChatID: chatID, ForEveryone: true,
	})
	if reply.T != ws.TypeError {
		t.Fatal("личную переписку удалили у обоих")
	}
	if code := decode[ws.ErrorData](t, reply).Code; code != ws.ErrCodeForbidden {
		t.Errorf("отказ кодом %q вместо forbidden", code)
	}
}

func TestУдалитьГруппуУВсехМожетТолькоВладелец(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79002220013")
	borya, boryaToken := e.newUser("79002220014")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	group := decode[chatCreated](t, anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Планёрка", MemberIDs: []uuid.UUID{borya.ID},
	}))

	refused := boryaConn.call(ws.CmdChatDelete, ws.ChatDeleteData{
		ChatID: group.Chat.ID, ForEveryone: true,
	})
	if refused.T != ws.TypeError {
		t.Fatal("участник удалил чужую группу у всех")
	}

	allowed := anyaConn.call(ws.CmdChatDelete, ws.ChatDeleteData{
		ChatID: group.Chat.ID, ForEveryone: true,
	})
	if allowed.T == ws.TypeError {
		t.Fatalf("владелец не смог удалить группу: %s", allowed.D)
	}

	// Группы больше нет ни у кого.
	summaries, err := e.store.ChatSummaries(context.Background(), borya.ID)
	if err != nil {
		t.Fatalf("список чатов: %v", err)
	}
	for _, s := range summaries {
		if s.Chat.ID == group.Chat.ID {
			t.Error("группа осталась у участника после удаления у всех")
		}
	}
}

func TestВыйтиЧерезИсключениеСебяНельзя(t *testing.T) {
	// Уход и исключение читаются по-разному и правами отличаются: подменять
	// одно другим значит путать их в истории.
	e := newEnv(t)
	anya, anyaToken := e.newUser("79002220015")
	borya, _ := e.newUser("79002220016")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	group := decode[chatCreated](t, anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Планёрка", MemberIDs: []uuid.UUID{borya.ID},
	}))

	reply := anyaConn.call(ws.CmdChatRemoveMem, ws.ChatRemoveMemberData{
		ChatID: group.Chat.ID, UserID: anya.ID,
	})
	if reply.T != ws.TypeError {
		t.Fatal("исключение себя прошло вместо выхода")
	}
}
