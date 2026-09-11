package api

import (
	"net/http"
	"strings"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

type requestCodeReq struct {
	Phone string `json:"phone"`
}

func (s *Server) handleRequestCode(w http.ResponseWriter, r *http.Request) {
	var req requestCodeReq
	if !decodeJSON(w, r, &req) {
		return
	}
	res, err := s.auth.RequestCode(r.Context(), req.Phone, clientIP(r, s.cfg.TrustProxy))
	if err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

type verifyReq struct {
	Phone     string `json:"phone"`
	Code      string `json:"code"`
	Platform  string `json:"platform"`
	Device    string `json:"device"`
	PushToken string `json:"push_token"`
}

func (s *Server) handleVerify(w http.ResponseWriter, r *http.Request) {
	var req verifyReq
	if !decodeJSON(w, r, &req) {
		return
	}
	session, err := s.auth.Verify(r.Context(), req.Phone, strings.TrimSpace(req.Code), auth.DeviceInfo{
		Platform:  req.Platform,
		Name:      req.Device,
		PushToken: req.PushToken,
	})
	if err != nil {
		writeAppError(w, err)
		return
	}
	session.User = s.withAvatar(r.Context(), session.User)
	writeJSON(w, http.StatusOK, session)
}

type refreshReq struct {
	RefreshToken string `json:"refresh_token"`
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if !decodeJSON(w, r, &req) {
		return
	}
	session, err := s.auth.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		writeAppError(w, err)
		return
	}
	session.User = s.withAvatar(r.Context(), session.User)
	writeJSON(w, http.StatusOK, session)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	var req refreshReq
	if !decodeJSON(w, r, &req) {
		return
	}
	if err := s.auth.Logout(r.Context(), req.RefreshToken); err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())
	user, err := s.store.UserByID(r.Context(), me.UserID)
	if err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.withAvatar(r.Context(), user))
}

type updateMeReq struct {
	DisplayName *string `json:"display_name"`
	Username    *string `json:"username"`
	AvatarURL   *string `json:"avatar_url"`
}

func (s *Server) handleUpdateMe(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())
	var req updateMeReq
	if !decodeJSON(w, r, &req) {
		return
	}
	if req.Username != nil {
		normalized := strings.ToLower(strings.TrimSpace(*req.Username))
		if !validUsername(normalized) {
			writeError(w, http.StatusBadRequest, "bad_username",
				"Имя пользователя: 3–32 символа, латиница, цифры и подчёркивание")
			return
		}
		req.Username = &normalized
	}
	user, err := s.store.UpdateUser(r.Context(), me.UserID, store.UserPatch{
		DisplayName: req.DisplayName,
		Username:    req.Username,
		AvatarURL:   req.AvatarURL,
	})
	if err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.withAvatar(r.Context(), user))
}

func validUsername(s string) bool {
	if len(s) < 3 || len(s) > 32 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z', c >= '0' && c <= '9', c == '_':
		default:
			return false
		}
	}
	return true
}

func (s *Server) handleSearchUsers(w http.ResponseWriter, r *http.Request) {
	query := strings.TrimSpace(r.URL.Query().Get("q"))
	if len(query) < 2 {
		writeError(w, http.StatusBadRequest, "bad_query", "Запрос должен быть не короче двух символов")
		return
	}
	// Если запрос похож на телефон — ищем ещё и по нему. Нормализуем тем
	// же кодом, что и при входе: иначе «+7 939 273-11-11» из адресной
	// книги никогда не сойдётся с «79392731111» в базе.
	phone := ""
	if normalized, err := auth.NormalizePhone(query); err == nil {
		phone = normalized
	}

	users, err := s.store.SearchUsers(r.Context(), query, phone, 20)
	if err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": s.publicUsers(r.Context(), users)})
}

func (s *Server) handleContacts(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())
	contacts, err := s.store.Contacts(r.Context(), me.UserID)
	if err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": s.publicUsers(r.Context(), contacts)})
}

type syncContactsReq struct {
	Contacts []struct {
		Phone string `json:"phone"`
		Name  string `json:"name"`
	} `json:"contacts"`
}

// handleSyncContacts принимает адресную книгу и отвечает теми, кто уже
// зарегистрирован.
//
// Сервер не хранит номера незарегистрированных людей: они не давали на это
// согласия, а пользы от них никакой.
func (s *Server) handleSyncContacts(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	var req syncContactsReq
	if !decodeJSON(w, r, &req) {
		return
	}
	if len(req.Contacts) > 5000 {
		writeError(w, http.StatusBadRequest, "too_many", "Слишком большая адресная книга")
		return
	}

	names := make(map[string]string, len(req.Contacts))
	phones := make([]string, 0, len(req.Contacts))
	for _, c := range req.Contacts {
		phone, err := auth.NormalizePhone(c.Phone)
		if err != nil {
			continue // Мусорные строки в книге — норма, просто пропускаем.
		}
		if _, seen := names[phone]; !seen {
			phones = append(phones, phone)
		}
		names[phone] = c.Name
	}

	found, err := s.store.UsersByPhones(r.Context(), phones)
	if err != nil {
		writeAppError(w, err)
		return
	}

	link := make(map[uuid.UUID]string, len(found))
	for _, u := range found {
		link[u.ID] = names[u.Phone]
	}
	if err := s.store.UpsertContacts(r.Context(), me.UserID, link); err != nil {
		writeAppError(w, err)
		return
	}
	// Телефоны здесь оставляем: их прислал сам клиент, и по ним он
	// сшивает найденных людей со своей адресной книгой.
	writeJSON(w, http.StatusOK, map[string]any{
		"users": s.usersWithPhones(r.Context(), found),
	})
}

type pushTokenReq struct {
	Token string `json:"token"`
}

func (s *Server) handlePushToken(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())
	var req pushTokenReq
	if !decodeJSON(w, r, &req) {
		return
	}
	if err := s.store.SetPushToken(r.Context(), me.DeviceID, req.Token); err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}
