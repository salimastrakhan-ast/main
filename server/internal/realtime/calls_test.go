package realtime_test

import (
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// Звонок держится на двух вещах: собеседник должен услышать предложение
// соединения, а посторонний — не суметь в него влезть. Всё остальное делает
// WebRTC на клиентах, и проверять это здесь нечего.

// chatCreated — ответ на chat.create: он отдаёт чат отдельным полем, а не
// сводкой, поэтому общего типа для него в протоколе нет.
type chatCreated struct {
	Chat struct {
		ID uuid.UUID `json:"id"`
	} `json:"chat"`
}

// sdp собирает правдоподобное по длине описание соединения: настоящее — это
// несколько килобайт текста, и проверять пределы на строке «привет» значило
// бы проверять не то.
func sdp(n int) string {
	return "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\n" + strings.Repeat("a=x\r\n", n)
}

// privateChat заводит личный чат тем же способом, что и клиент: первым
// сообщением. Отдельной команды «создать диалог» в протоколе нет.
func (e *env) privateChat(from *client, peer uuid.UUID) uuid.UUID {
	e.t.Helper()
	reply := from.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: peer, Text: "созвонимся?", ClientMsgID: uuid.New(),
	})
	return decode[ws.MessageEventData](e.t, reply).Message.ChatID
}

func TestЗвонокДоходитДоСобеседника(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79001110001")
	borya, boryaToken := e.newUser("79001110002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	chatID := e.privateChat(anyaConn, borya.ID)

	reply := anyaConn.call(ws.CmdCallStart, ws.CallStartData{ChatID: chatID, SDP: sdp(20)})
	started := decode[ws.CallStartedData](t, reply)
	if started.Status != "ringing" {
		t.Fatalf("собеседник в сети, а статус %q", started.Status)
	}

	incoming := decode[ws.CallIncomingData](t,
		boryaConn.await(ws.EventCallIncoming, 3*time.Second))
	if incoming.CallID != started.CallID {
		t.Errorf("звонок пришёл под другим номером: %s против %s",
			incoming.CallID, started.CallID)
	}
	if incoming.From.ID != anya.ID {
		t.Errorf("звонит %s, а показан %s", anya.ID, incoming.From.ID)
	}
	if incoming.ChatID != chatID {
		t.Errorf("звонок лёг не в тот чат")
	}

	// Ответ возвращается звонящему — на этом согласование и заканчивается.
	boryaConn.call(ws.CmdCallAnswer, ws.CallAnswerData{CallID: started.CallID, SDP: sdp(18)})
	accepted := decode[ws.CallAcceptedData](t,
		anyaConn.await(ws.EventCallAccepted, 3*time.Second))
	if accepted.CallID != started.CallID {
		t.Errorf("ответ пришёл по другому звонку")
	}
}

func TestЗвонокОфлайновомуСобеседникуНеГудит(t *testing.T) {
	// Человек не в сети — гудки в пустоту только злят. Клиент должен узнать
	// об этом сразу, а не через сорок секунд ожидания.
	e := newEnv(t)
	_, anyaToken := e.newUser("79001110003")
	borya, boryaToken := e.newUser("79001110004")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	boryaConn := e.connect(boryaToken)
	chatID := e.privateChat(anyaConn, borya.ID)
	boryaConn.close()
	// Присутствие снимается при закрытии соединения; дать этому случиться.
	waitFor(t, 3*time.Second, func() bool { return e.hub.OnlineUsersCount() == 1 })

	reply := anyaConn.call(ws.CmdCallStart, ws.CallStartData{ChatID: chatID, SDP: sdp(20)})
	if got := decode[ws.CallStartedData](t, reply).Status; got != "offline" {
		t.Errorf("статус %q вместо offline", got)
	}
}

func TestПосторонийНеВлезаетВЧужойЗвонок(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79001110005")
	borya, boryaToken := e.newUser("79001110006")
	_, vitaToken := e.newUser("79001110007")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()
	vitaConn := e.connect(vitaToken)
	defer vitaConn.close()

	chatID := e.privateChat(anyaConn, borya.ID)
	started := decode[ws.CallStartedData](t,
		anyaConn.call(ws.CmdCallStart, ws.CallStartData{ChatID: chatID, SDP: sdp(20)}))

	// Номер звонка Вите неоткуда взять, но если бы взял — реле обязано
	// отказать: иначе чужой разговор можно перехватить, зная один uuid.
	for _, cmd := range []struct {
		typ     string
		payload any
	}{
		{ws.CmdCallAnswer, ws.CallAnswerData{CallID: started.CallID, SDP: sdp(10)}},
		{ws.CmdCallICE, ws.CallICEData{CallID: started.CallID, Candidate: "candidate:1 1 udp"}},
		{ws.CmdCallHangup, ws.CallHangupData{CallID: started.CallID}},
	} {
		reply := vitaConn.call(cmd.typ, cmd.payload)
		if reply.T != ws.TypeError {
			t.Fatalf("%s от постороннего прошла: %s", cmd.typ, reply.T)
		}
		if code := decode[ws.ErrorData](t, reply).Code; code != ws.ErrCodeForbidden {
			t.Errorf("%s отказала кодом %q вместо forbidden", cmd.typ, code)
		}
	}
}

func TestЗвонящийНеОтвечаетСамСебе(t *testing.T) {
	// call.answer от звонящего сбило бы согласование: обе стороны решили
	// бы, что отвечает другая.
	e := newEnv(t)
	_, anyaToken := e.newUser("79001110008")
	borya, boryaToken := e.newUser("79001110009")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	chatID := e.privateChat(anyaConn, borya.ID)
	started := decode[ws.CallStartedData](t,
		anyaConn.call(ws.CmdCallStart, ws.CallStartData{ChatID: chatID, SDP: sdp(20)}))

	reply := anyaConn.call(ws.CmdCallAnswer, ws.CallAnswerData{CallID: started.CallID, SDP: sdp(10)})
	if reply.T != ws.TypeError {
		t.Fatalf("звонящий ответил сам себе")
	}
}

func TestСлишкомБольшоеОписаниеОтвергается(t *testing.T) {
	// Без предела реле превращается в бесплатный канал передачи чего угодно
	// между двумя участниками — мимо всех ограничений на вложения.
	e := newEnv(t)
	_, anyaToken := e.newUser("79001110010")
	borya, _ := e.newUser("79001110011")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	chatID := e.privateChat(anyaConn, borya.ID)

	huge := strings.Repeat("x", 17<<10)
	reply := anyaConn.call(ws.CmdCallStart, ws.CallStartData{ChatID: chatID, SDP: huge})
	if reply.T != ws.TypeError {
		t.Fatalf("огромный SDP прошёл")
	}
	if code := decode[ws.ErrorData](t, reply).Code; code != ws.ErrCodeBadRequest {
		t.Errorf("отказ кодом %q вместо bad_request", code)
	}
}

func TestОтбойСлышенОбеимСторонам(t *testing.T) {
	e := newEnv(t)
	_, anyaToken := e.newUser("79001110012")
	borya, boryaToken := e.newUser("79001110013")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	chatID := e.privateChat(anyaConn, borya.ID)
	started := decode[ws.CallStartedData](t,
		anyaConn.call(ws.CmdCallStart, ws.CallStartData{ChatID: chatID, SDP: sdp(20)}))
	boryaConn.await(ws.EventCallIncoming, 3*time.Second)

	boryaConn.call(ws.CmdCallHangup, ws.CallHangupData{
		CallID: started.CallID, Reason: ws.CallEndDeclined,
	})
	ended := decode[ws.CallEndedData](t, anyaConn.await(ws.EventCallEnded, 3*time.Second))
	if ended.Reason != ws.CallEndDeclined {
		t.Errorf("причина %q вместо declined", ended.Reason)
	}

	// Второй раз по тому же номеру — звонка уже нет.
	reply := anyaConn.call(ws.CmdCallHangup, ws.CallHangupData{CallID: started.CallID})
	if reply.T != ws.TypeError {
		t.Fatalf("отбой по закрытому звонку прошёл")
	}
	if code := decode[ws.ErrorData](t, reply).Code; code != ws.ErrCodeNotFound {
		t.Errorf("отказ кодом %q вместо not_found", code)
	}
}

func TestВГруппеЗвонковПокаНет(t *testing.T) {
	// Групповой звонок — это не «ещё один участник», а сведение потоков на
	// отдельном сервере. Пока его нет, отказ честнее, чем соединить двоих
	// из пяти.
	e := newEnv(t)
	_, anyaToken := e.newUser("79001110014")
	borya, _ := e.newUser("79001110015")
	vita, _ := e.newUser("79001110016")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	created := anyaConn.call(ws.CmdChatCreate, ws.ChatCreateData{
		Title: "Планёрка", MemberIDs: []uuid.UUID{borya.ID, vita.ID},
	})
	group := decode[chatCreated](t, created)

	reply := anyaConn.call(ws.CmdCallStart, ws.CallStartData{
		ChatID: group.Chat.ID, SDP: sdp(20),
	})
	if reply.T != ws.TypeError {
		t.Fatalf("звонок в группу прошёл")
	}
}
