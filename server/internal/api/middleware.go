package api

import (
	"context"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/google/uuid"
)

type ctxKey int

const claimsKey ctxKey = iota

// Identity — кто выполняет запрос. Кладётся в контекст мидлварью авторизации.
type Identity struct {
	UserID   uuid.UUID
	DeviceID uuid.UUID
}

func identityFrom(ctx context.Context) (Identity, bool) {
	id, ok := ctx.Value(claimsKey).(Identity)
	return id, ok
}

// requireAuth пропускает дальше только с валидным access-токеном.
func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token := bearerToken(r)
		if token == "" {
			writeError(w, http.StatusUnauthorized, "no_token", "Нужен токен доступа")
			return
		}
		claims, err := s.auth.Tokens().Parse(token, time.Now())
		if err != nil {
			writeError(w, http.StatusUnauthorized, "bad_token", "Сессия недействительна, войдите заново")
			return
		}
		ctx := context.WithValue(r.Context(), claimsKey,
			Identity{UserID: claims.UserID, DeviceID: claims.DeviceID})
		next(w, r.WithContext(ctx))
	}
}

func bearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	if after, ok := strings.CutPrefix(h, "Bearer "); ok {
		return strings.TrimSpace(after)
	}
	return ""
}

// withRecover не даёт панике в одном запросе уронить весь сервер.
func withRecover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				slog.Error("паника в обработчике", "err", rec, "path", r.URL.Path)
				writeError(w, http.StatusInternalServerError, "internal", "Внутренняя ошибка")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type statusWriter struct {
	http.ResponseWriter
	status int
}

func (w *statusWriter) WriteHeader(code int) {
	w.status = code
	w.ResponseWriter.WriteHeader(code)
}

// Hijack нужен, чтобы WebSocket мог перехватить соединение сквозь обёртку.
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		sw := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(sw, r)
		slog.Debug("запрос",
			"method", r.Method,
			"path", r.URL.Path,
			"status", sw.status,
			"took", time.Since(start).Round(time.Millisecond))
	})
}
