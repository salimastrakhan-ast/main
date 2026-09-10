package api

import (
	"net/http"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/config"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

// Server связывает HTTP-маршруты с сервисами.
type Server struct {
	cfg   config.Config
	store *store.Store
	auth  *auth.Service
}

func NewServer(cfg config.Config, st *store.Store, authSvc *auth.Service) *Server {
	return &Server{cfg: cfg, store: st, auth: authSvc}
}

// Handler собирает маршрутизатор.
//
// Роутер — стандартный ServeMux: с Go 1.22 он умеет метод и параметры в
// шаблоне ("GET /v1/chats/{id}"), и стороннего роутера тут больше не нужно.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /healthz", s.handleHealth)

	mux.HandleFunc("POST /v1/auth/request-code", s.handleRequestCode)
	mux.HandleFunc("POST /v1/auth/verify", s.handleVerify)
	mux.HandleFunc("POST /v1/auth/refresh", s.handleRefresh)
	mux.HandleFunc("POST /v1/auth/logout", s.handleLogout)

	mux.HandleFunc("GET /v1/users/me", s.requireAuth(s.handleMe))
	mux.HandleFunc("PATCH /v1/users/me", s.requireAuth(s.handleUpdateMe))
	mux.HandleFunc("GET /v1/users/search", s.requireAuth(s.handleSearchUsers))

	mux.HandleFunc("GET /v1/contacts", s.requireAuth(s.handleContacts))
	mux.HandleFunc("POST /v1/contacts/sync", s.requireAuth(s.handleSyncContacts))

	mux.HandleFunc("POST /v1/devices/push-token", s.requireAuth(s.handlePushToken))

	return withRecover(withLogging(mux))
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.store.Pool().Ping(r.Context()); err != nil {
		writeError(w, http.StatusServiceUnavailable, "db_down", "База недоступна")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
