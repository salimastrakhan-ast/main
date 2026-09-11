package api

import (
	"net/http"
	"slices"
	"strings"
)

// withCORS пускает веб-клиент, живущий на другом адресе.
//
// Мобильным клиентам это не нужно вовсе — правило браузерное. Список
// разрешённых источников задаётся явно: звёздочка в проде означала бы, что
// любой сайт может дёргать API от имени вошедшего человека.
func withCORS(allowed []string, next http.Handler) http.Handler {
	if len(allowed) == 0 {
		return next
	}
	any := slices.Contains(allowed, "*")

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin != "" && (any || slices.Contains(allowed, origin)) {
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Credentials", "true")
			// Ответ зависит от Origin, и без Vary промежуточный кэш отдаст
			// одному сайту заголовки, выписанные для другого.
			w.Header().Add("Vary", "Origin")
		}

		if r.Method == http.MethodOptions {
			// Список методов ведётся руками, и о нём легко забыть: аватар
			// ставится PUT, и без него браузер отказал ещё до запроса —
			// в логах сервера при этом было пусто.
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Max-Age", "600")
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func parseOrigins(raw string) []string {
	if strings.TrimSpace(raw) == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
