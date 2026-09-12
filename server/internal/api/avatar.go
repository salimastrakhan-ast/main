package api

import (
	"net/http"
	"strconv"
	"strings"

	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

// maxAvatarBytes — предел для аватара.
//
// Отдельно от общего лимита на вложения: там пятьдесят мегабайт, и это
// разумно для видео, но аватар такого размера означает, что человек по
// ошибке выбрал не тот файл, а показывать его придётся в кружке сорок на
// сорок точек.
const maxAvatarBytes = 8 << 20

// handleSetAvatar принимает картинку и делает её аватаром.
//
// Одним запросом, а не «загрузите файл, потом пришлите ссылку»: общая
// загрузка вложений возвращает подписанную ссылку и не отдаёт ключ объекта,
// а ссылка живёт шесть часов — положить её в профиль значит потерять аватар
// к вечеру. Поэтому ключ остаётся на сервере и в базу ложится он.
func (s *Server) handleSetAvatar(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	r.Body = http.MaxBytesReader(w, r.Body, maxAvatarBytes)
	if err := r.ParseMultipartForm(maxAvatarBytes); err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, "too_large",
			"Картинка больше "+strconv.Itoa(maxAvatarBytes>>20)+" МБ")
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "no_file", "Нужен файл в поле file")
		return
	}
	defer func() { _ = file.Close() }()

	mime := header.Header.Get("Content-Type")
	if !strings.HasPrefix(mime, "image/") {
		writeError(w, http.StatusBadRequest, "not_an_image", "Аватар должен быть картинкой")
		return
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

	previous, err := s.store.UserByID(r.Context(), me.UserID)
	if err != nil {
		writeAppError(w, err)
		return
	}

	user, err := s.store.UpdateUser(r.Context(), me.UserID, store.UserPatch{AvatarKey: &key})
	if err != nil {
		// Профиль не обновился — файл в хранилище больше не нужен.
		_ = s.media.Remove(r.Context(), key)
		writeAppError(w, err)
		return
	}

	// Старую картинку убираем только после успешной замены: упади мы
	// раньше, человек остался бы и без новой, и без прежней.
	if previous.AvatarKey != "" && previous.AvatarKey != key {
		_ = s.media.Remove(r.Context(), previous.AvatarKey)
	}

	writeJSON(w, http.StatusOK, s.withAvatar(r.Context(), user))
}

// handleDeleteAvatar снимает аватар и стирает файл.
func (s *Server) handleDeleteAvatar(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	previous, err := s.store.UserByID(r.Context(), me.UserID)
	if err != nil {
		writeAppError(w, err)
		return
	}

	empty := ""
	user, err := s.store.UpdateUser(r.Context(), me.UserID, store.UserPatch{AvatarKey: &empty})
	if err != nil {
		writeAppError(w, err)
		return
	}
	if previous.AvatarKey != "" {
		_ = s.media.Remove(r.Context(), previous.AvatarKey)
	}

	writeJSON(w, http.StatusOK, user)
}
