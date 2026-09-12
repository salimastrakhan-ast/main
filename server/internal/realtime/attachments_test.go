package realtime_test

import (
	"testing"
	"time"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/store"
	"github.com/salimastrakhan-ast/main/server/internal/ws"
)

// upload имитирует загрузку файла: в этих тестах важна привязка вложения к
// сообщению, а не то, как байты доехали до хранилища.
func (e *env) upload(ownerID uuid.UUID, name string) domain.Attachment {
	e.t.Helper()
	a, err := e.store.CreateAttachment(e.t.Context(), store.NewAttachment{
		OwnerID:   ownerID,
		Kind:      domain.AttachmentImage,
		ObjectKey: ownerID.String() + "/" + uuid.NewString() + ".png",
		FileName:  name,
		Mime:      "image/png",
		Size:      71,
	})
	if err != nil {
		e.t.Fatalf("регистрация вложения: %v", err)
	}
	return a
}

// Картинка доезжает до собеседника вместе с сообщением.
func TestMessageCarriesAttachment(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	att := e.upload(anya.ID, "кот.png")
	anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID:        borya.ID,
		Text:          "смотри какой",
		ClientMsgID:   uuid.New(),
		AttachmentIDs: []uuid.UUID{att.ID},
	})

	got := decode[ws.MessageEventData](t, boryaConn.await(ws.EventMessageNew, 3*time.Second))
	if len(got.Message.Attachments) != 1 {
		t.Fatalf("вложений %d, ожидалось одно", len(got.Message.Attachments))
	}
	if got.Message.Attachments[0].FileName != "кот.png" {
		t.Errorf("имя файла %q", got.Message.Attachments[0].FileName)
	}
}

// Чужое вложение прицепить нельзя, даже зная его идентификатор: иначе по
// перебору id можно было бы вытащить чужой файл в свой чат.
func TestCannotAttachSomeoneElsesFile(t *testing.T) {
	e := newEnv(t)
	anya, _ := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	att := e.upload(anya.ID, "личное.png")

	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	resp := boryaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID:        anya.ID,
		Text:          "твоё теперь моё",
		ClientMsgID:   uuid.New(),
		AttachmentIDs: []uuid.UUID{att.ID},
	})
	if resp.T != ws.TypeError {
		t.Fatalf("удалось прицепить чужое вложение: %s %s", resp.T, resp.D)
	}
	if code := decode[ws.ErrorData](t, resp).Code; code != ws.ErrCodeForbidden {
		t.Errorf("код ошибки %q, ожидался %q", code, ws.ErrCodeForbidden)
	}
	_ = borya
}

// Одно вложение — одно сообщение: повторно прицепить уже отправленный файл
// нельзя.
func TestAttachmentCannotBeReused(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	att := e.upload(anya.ID, "кот.png")
	first := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "раз", ClientMsgID: uuid.New(),
		AttachmentIDs: []uuid.UUID{att.ID},
	}))

	resp := anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: first.Message.ChatID, Text: "два", ClientMsgID: uuid.New(),
		AttachmentIDs: []uuid.UUID{att.ID},
	})
	if resp.T != ws.TypeError {
		t.Fatalf("вложение прицепилось ко второму сообщению: %s %s", resp.T, resp.D)
	}
}

// Сообщение из одной картинки без текста — нормальный случай.
func TestAttachmentOnlyMessage(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, boryaToken := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()
	boryaConn := e.connect(boryaToken)
	defer boryaConn.close()

	att := e.upload(anya.ID, "кот.png")
	ack := anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, ClientMsgID: uuid.New(),
		AttachmentIDs: []uuid.UUID{att.ID},
	})
	if ack.T != ws.TypeAck {
		t.Fatalf("сообщение без текста отвергнуто: %s %s", ack.T, ack.D)
	}

	// А вот совсем пустое сообщение — нет.
	if resp := anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, ClientMsgID: uuid.New(),
	}); resp.T != ws.TypeError {
		t.Errorf("принято пустое сообщение: %s %s", resp.T, resp.D)
	}
}

// Отправка сорвалась после привязки — вложение не должно потеряться.
// Ретрай с тем же client_msg_id возвращает то же сообщение вместе с файлом.
func TestRetryKeepsAttachment(t *testing.T) {
	e := newEnv(t)
	anya, anyaToken := e.newUser("79990000001")
	borya, _ := e.newUser("79990000002")

	anyaConn := e.connect(anyaToken)
	defer anyaConn.close()

	att := e.upload(anya.ID, "кот.png")
	clientMsgID := uuid.New()
	first := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		PeerID: borya.ID, Text: "смотри", ClientMsgID: clientMsgID,
		AttachmentIDs: []uuid.UUID{att.ID},
	}))

	again := decode[ws.MessageEventData](t, anyaConn.call(ws.CmdMessageSend, ws.MessageSendData{
		ChatID: first.Message.ChatID, Text: "смотри", ClientMsgID: clientMsgID,
		AttachmentIDs: []uuid.UUID{att.ID},
	}))
	if again.Message.ID != first.Message.ID {
		t.Fatalf("ретрай создал новое сообщение")
	}
	if len(again.Message.Attachments) != 1 {
		t.Errorf("после ретрая вложений %d, ожидалось одно", len(again.Message.Attachments))
	}
}
