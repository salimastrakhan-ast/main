package realtime_test

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Пересылка — это копия, а не ссылка: оригинал могут удалить, и пересланное
// не должно исчезать следом. И она обязана помнить первого автора, иначе
// чужой текст выглядит своим.

func TestПересланноеПомнитАвтора(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79003330001")
	borya, boryaToken := e.newUser("79003330002")
	vita, _ := e.newUser("79003330003")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	// Аня пишет Боре, Боря пересылает это Вите.
	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "важное объявление", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	reply := boryaConn.call(ws.CmdMessageForward, ws.MessageForwardData{
		FromChatID:  sent.Message.ChatID,
		MessageID:   sent.Message.ID,
		ToPeerID:    vita.ID,
		ClientMsgID: uuid.New(),
	})
	if reply.T == ws.TypeError {
		t.Fatalf("пересылка отклонена: %s", reply.D)
	}
	forwarded := decode[ws.MessageEventData](t, reply).Message

	if forwarded.Text != "важное объявление" {
		t.Errorf("текст потерялся: %q", forwarded.Text)
	}
	if forwarded.SenderID != borya.ID {
		t.Errorf("отправитель %s вместо пересылающего", forwarded.SenderID)
	}
	if forwarded.ForwardedFrom == nil || *forwarded.ForwardedFrom != anya.ID {
		t.Errorf("автор оригинала не сохранён: %v", forwarded.ForwardedFrom)
	}
	// Имя — снимком: получатель может быть незнаком с автором, и разрешить
	// идентификатор ему нечем.
	if forwarded.ForwardedName == "" {
		t.Error("имя автора не сохранено — у получателя подпись будет пустой")
	}
	if forwarded.ChatID == sent.Message.ChatID {
		t.Error("пересланное осталось в исходном чате")
	}
}

func TestПересылкаПересланногоПомнитПервогоАвтора(t *testing.T) {
	// Цепочка «переслал того, кто переслал» никому не нужна, а имя первого —
	// то самое, что человек и ищет.
	e := newEnv(t)
	anya, anyaToken := e.newUser("79003330004")
	borya, boryaToken := e.newUser("79003330005")
	vita, vitaToken := e.newUser("79003330006")
	den, _ := e.newUser("79003330007")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()
	vitaConn := e.connect(vitaToken)
	defer vitaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "по цепочке", ClientMsgID: uuid.New(),
	}))

	first := decode[ws.MessageEventData](t, boryaConn.call(ws.CmdMessageForward, ws.MessageForwardData{
		FromChatID: sent.Message.ChatID, MessageID: sent.Message.ID,
		ToPeerID: vita.ID, ClientMsgID: uuid.New(),
	})).Message

	second := decode[ws.MessageEventData](t, vitaConn.call(ws.CmdMessageForward, ws.MessageForwardData{
		FromChatID: first.ChatID, MessageID: first.ID,
		ToPeerID: den.ID, ClientMsgID: uuid.New(),
	})).Message

	if second.ForwardedFrom == nil || *second.ForwardedFrom != anya.ID {
		t.Errorf("во второй пересылке автор %v вместо первого", second.ForwardedFrom)
	}
}

func TestЧужуюПерепискуНеПереслать(t *testing.T) {
	// Иначе по одному идентификатору вытаскивалась бы чужая переписка в
	// свою — и знать чужой chat_id было бы достаточно, чтобы её прочесть.
	e := newEnv(t)
	_, anyaToken := e.newUser("79003330008")
	borya, _ := e.newUser("79003330009")
	_, vitaToken := e.newUser("79003330010")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	vitaConn := e.connect(vitaToken)
	defer vitaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "не для всех", ClientMsgID: uuid.New(),
	}))

	reply := vitaConn.call(ws.CmdMessageForward, ws.MessageForwardData{
		FromChatID: sent.Message.ChatID, MessageID: sent.Message.ID,
		ToPeerID: borya.ID, ClientMsgID: uuid.New(),
	})
	if reply.T != ws.TypeError {
		t.Fatal("посторонний переслал чужое сообщение")
	}
	if code := decode[ws.ErrorData](t, reply).Code; code != ws.ErrCodeForbidden {
		t.Errorf("отказ кодом %q вместо forbidden", code)
	}
}

func TestУдалениеОригиналаНеТрогаетПересланное(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79003330011")
	borya, boryaToken := e.newUser("79003330012")
	vita, _ := e.newUser("79003330013")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "исчезающее", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	forwarded := decode[ws.MessageEventData](t, boryaConn.call(ws.CmdMessageForward, ws.MessageForwardData{
		FromChatID: sent.Message.ChatID, MessageID: sent.Message.ID,
		ToPeerID: vita.ID, ClientMsgID: uuid.New(),
	})).Message

	anyaConn.call(ws.CmdMessageDelete, ws.MessageDeleteData{
		ChatID: sent.Message.ChatID, MessageID: sent.Message.ID,
	})

	// Пересланное — своё сообщение в своей переписке, и чужое удаление его
	// не касается.
	history, _, err := e.store.MessagesSince(t.Context(), forwarded.ChatID, 0, 50)
	if err != nil {
		t.Fatalf("история: %v", err)
	}
	found := false
	for _, m := range history {
		if m.ID == forwarded.ID && m.Text == "исчезающее" && m.DeletedAt == nil {
			found = true
		}
	}
	if !found {
		t.Error("пересланное исчезло вслед за оригиналом")
	}
}

func TestПовторПересылкиНеДелаетВторуюКопию(t *testing.T) {
	// Клиент ретраит при каждом обрыве связи: без идемпотентности человек
	// получил бы два одинаковых сообщения.
	e := newEnv(t)
	_, anyaToken := e.newUser("79003330014")
	borya, boryaToken := e.newUser("79003330015")
	vita, _ := e.newUser("79003330016")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	sent := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "один раз", ClientMsgID: uuid.New(),
	}))
	boryaConn.await(ws.EventMessageNew, 3*time.Second)

	clientMsgID := uuid.New()
	forward := ws.MessageForwardData{
		FromChatID: sent.Message.ChatID, MessageID: sent.Message.ID,
		ToPeerID: vita.ID, ClientMsgID: clientMsgID,
	}
	first := decode[ws.MessageEventData](t, boryaConn.call(ws.CmdMessageForward, forward)).Message
	second := decode[ws.MessageEventData](t, boryaConn.call(ws.CmdMessageForward, forward)).Message

	if first.ID != second.ID {
		t.Errorf("повтор создал второе сообщение: %s и %s", first.ID, second.ID)
	}
}
