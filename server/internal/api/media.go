package api

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

// handleUpload принимает файл и регистрирует его как черновик вложения.
//
// Файл загружается ДО отправки сообщения: клиент показывает превью с
// прогрессом, а потом отправляет сообщение со списком идентификаторов.
// Пока вложение не привязано к сообщению, им нельзя воспользоваться из
// другого аккаунта — привязку сторожит owner_id.
func (s *Server) handleUpload(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	// MaxBytesReader режет поток на лимите, поэтому огромный файл не
	// доедет до диска и не займёт память.
	r.Body = http.MaxBytesReader(w, r.Body, s.cfg.MaxUploadBytes)
	if err := r.ParseMultipartForm(8 << 20); err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, "too_large",
			"Файл больше "+strconv.FormatInt(s.cfg.MaxUploadBytes>>20, 10)+" МБ")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "no_file", "Нужен файл в поле file")
		return
	}
	defer func() { _ = file.Close() }()

	if header.Size > s.cfg.MaxUploadBytes {
		writeError(w, http.StatusRequestEntityTooLarge, "too_large",
			"Файл больше "+strconv.FormatInt(s.cfg.MaxUploadBytes>>20, 10)+" МБ")
		return
	}

	mime := header.Header.Get("Content-Type")
	if mime == "" {
		mime = "application/octet-stream"
	}

	key, err := s.media.Put(r.Context(), media.Upload{
		OwnerID:  me.UserID,
		FileName: header.Filename,
		Mime:     mime,
		Size:     header.Size,
		Body:     file,
	})
	if err != nil {
		writeAppError(w, err)
		return
	}

	attachment, err := s.store.CreateAttachment(r.Context(), store.NewAttachment{
		OwnerID:   me.UserID,
		Kind:      media.KindOf(mime),
		ObjectKey: key,
		FileName:  header.Filename,
		Mime:      mime,
		Size:      header.Size,
		Width:     intOrNil(r.FormValue("width")),
		Height:    intOrNil(r.FormValue("height")),
		Duration:  intOrNil(r.FormValue("duration")),
	})
	if err != nil {
		// Запись в базу не удалась — файл в хранилище больше не нужен.
		if rmErr := s.media.Remove(r.Context(), key); rmErr != nil {
			err = errors.Join(err, rmErr)
		}
		writeAppError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{
		"attachment": s.media.Resolve(r.Context(), []domain.Attachment{attachment})[0],
	})
}

func intOrNil(raw string) *int {
	v, err := strconv.Atoi(raw)
	if err != nil || v <= 0 {
		return nil
	}
	return &v
}
