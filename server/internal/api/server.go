package api

import (
	"net/http"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/config"
	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/realtime"
	"github.com/salimastrakhan-ast/main/server/internal/store"
	"github.com/salimastrakhan-ast/main/server/internal/translate"
)

// Server связывает HTTP-маршруты с сервисами.
type Server struct {
	cfg   config.Config
	store *store.Store
	auth  *auth.Service
	hub   *realtime.Hub
	media *media.Storage
	tr    translate.Translator
}

func NewServer(cfg config.Config, st *store.Store, authSvc *auth.Service, hub *realtime.Hub, storage *media.Storage, tr translate.Translator) *Server {
	if tr == nil {
		tr = translate.NoopTranslator{}
	}
	return &Server{cfg: cfg, store: st, auth: authSvc, hub: hub, media: storage, tr: tr}
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
	mux.HandleFunc("PUT /v1/users/me/avatar", s.requireAuth(s.handleSetAvatar))
	mux.HandleFunc("DELETE /v1/users/me/avatar", s.requireAuth(s.handleDeleteAvatar))
	mux.HandleFunc("GET /v1/users/search", s.requireAuth(s.handleSearchUsers))

	mux.HandleFunc("GET /v1/contacts", s.requireAuth(s.handleContacts))
	mux.HandleFunc("POST /v1/contacts/sync", s.requireAuth(s.handleSyncContacts))

	mux.HandleFunc("POST /v1/devices/push-token", s.requireAuth(s.handlePushToken))

	mux.HandleFunc("GET /v1/chats", s.requireAuth(s.handleChats))
	mux.HandleFunc("GET /v1/chats/{id}/messages", s.requireAuth(s.handleHistory))
	mux.HandleFunc("GET /v1/chats/{id}/members", s.requireAuth(s.handleChatMembers))

	mux.HandleFunc("GET /v1/calls/ice", s.requireAuth(s.handleICEServers))

	mux.HandleFunc("POST /v1/media/upload", s.requireAuth(s.handleUpload))

	mux.HandleFunc("POST /v1/ai/translate", s.requireAuth(s.handleTranslate))

	// Токен проверяется первым кадром внутри соединения, а не заголовком:
	// браузерный WebSocket не умеет слать Authorization при подключении.
	mux.HandleFunc("GET /v1/ws", s.hub.Serve)

	return withCORS(parseOrigins(s.cfg.CORSOrigins), withRecover(withLogging(mux)))
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.store.Pool().Ping(r.Context()); err != nil {
		writeError(w, http.StatusServiceUnavailable, "db_down", "База недоступна")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
