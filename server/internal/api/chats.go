package api

import (
	"net/http"
	"strconv"

	"github.com/google/uuid"

	"github.com/salimastrakhan-ast/main/server/internal/media"
)

const historyPageLimit = 100

func (s *Server) handleChats(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())
	chats, err := s.store.ChatSummaries(r.Context(), me.UserID)
	if err != nil {
		writeAppError(w, err)
		return
	}
	media.ResolveSummaries(r.Context(), s.media, chats)
	writeJSON(w, http.StatusOK, map[string]any{"chats": chats})
}

// handleHistory листает ленту вверх: before_seq — номер, до которого нужны
// сообщения, ноль или отсутствие параметра означает «с конца».
func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	chatID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_chat_id", "Некорректный идентификатор чата")
		return
	}
	// Проверка участия обязательна: без неё историю чужого чата можно было бы
	// прочитать, зная его id.
	if _, err := s.store.Membership(r.Context(), chatID, me.UserID); err != nil {
		writeAppError(w, err)
		return
	}

	beforeSeq, _ := strconv.ParseInt(r.URL.Query().Get("before_seq"), 10, 64)
	limit := historyPageLimit
	if v, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && v > 0 && v < historyPageLimit {
		limit = v
	}

	messages, err := s.store.History(r.Context(), chatID, beforeSeq, limit)
	if err != nil {
		writeAppError(w, err)
		return
	}
	media.ResolveMessages(r.Context(), s.media, messages)
	writeJSON(w, http.StatusOK, map[string]any{"messages": messages})
}

func (s *Server) handleChatMembers(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	chatID, err := uuid.Parse(r.PathValue("id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad_chat_id", "Некорректный идентификатор чата")
		return
	}
	if _, err := s.store.Membership(r.Context(), chatID, me.UserID); err != nil {
		writeAppError(w, err)
		return
	}

	members, err := s.store.ChatMembers(r.Context(), chatID)
	if err != nil {
		writeAppError(w, err)
		return
	}
	ids := make([]uuid.UUID, len(members))
	for i, m := range members {
		ids[i] = m.UserID
	}
	users, err := s.store.UsersByIDs(r.Context(), ids)
	if err != nil {
		writeAppError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"members": members,
		"users":   publicUsers(users),
	})
}
