// Package api — HTTP-слой: маршруты, разбор запросов, коды ответов.
// Бизнес-логики здесь нет, она в auth, chats и realtime.
package api

import (
	"encoding/json"
	"errors"
	"log/slog"
	"math"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

// ErrorBody — единый формат ошибки. Клиент разбирает машинный code, а
// message показывает человеку.
type ErrorBody struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if v == nil {
		return
	}
	if err := json.NewEncoder(w).Encode(v); err != nil {
		slog.Error("не удалось записать ответ", "err", err)
	}
}

func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, ErrorBody{Code: code, Message: message})
}

// writeAppError переводит ошибки доменных слоёв в HTTP-коды в одном месте,
// чтобы хендлеры не повторяли этот разбор.
func writeAppError(w http.ResponseWriter, err error) {
	var rl *auth.RateLimitedError
	switch {
	case errors.As(err, &rl):
		w.Header().Set("Retry-After", strconv.Itoa(int(rl.RetryAfter.Seconds())+1))
		writeError(w, http.StatusTooManyRequests, "rate_limited",
			"Слишком много попыток. Повторите через "+humanDuration(rl.RetryAfter))
	case errors.Is(err, auth.ErrBadPhone):
		writeError(w, http.StatusBadRequest, "bad_phone", "Некорректный номер телефона")
	case errors.Is(err, auth.ErrCodeInvalid):
		writeError(w, http.StatusBadRequest, "code_invalid", "Неверный код")
	case errors.Is(err, auth.ErrCodeExpired):
		writeError(w, http.StatusBadRequest, "code_expired", "Код истёк, запросите новый")
	case errors.Is(err, auth.ErrTooManyAttempts):
		writeError(w, http.StatusTooManyRequests, "too_many_attempts", "Слишком много попыток, запросите новый код")
	case errors.Is(err, auth.ErrBadToken):
		writeError(w, http.StatusUnauthorized, "bad_token", "Сессия недействительна, войдите заново")
	case errors.Is(err, store.ErrNotFound):
		writeError(w, http.StatusNotFound, "not_found", "Не найдено")
	case errors.Is(err, store.ErrForbidden):
		writeError(w, http.StatusForbidden, "forbidden", "Нет доступа")
	case errors.Is(err, store.ErrConflict):
		writeError(w, http.StatusConflict, "conflict", "Уже занято")
	default:
		slog.Error("внутренняя ошибка", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "Внутренняя ошибка")
	}
}

func humanDuration(d time.Duration) string {
	if d < time.Minute {
		return strconv.Itoa(int(math.Ceil(d.Seconds()))) + " с"
	}
	return strconv.Itoa(int(math.Ceil(d.Minutes()))) + " мин"
}

func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20))
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "Некорректное тело запроса")
		return false
	}
	return true
}

// clientIP достаёт адрес с учётом обратного прокси.
//
// X-Forwarded-For подделывается кем угодно, поэтому доверять ему можно только
// когда перед сервером стоит наш прокси, который эту цепочку перезаписывает.
func clientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
			if idx := strings.IndexByte(xff, ','); idx > 0 {
				return strings.TrimSpace(xff[:idx])
			}
			return strings.TrimSpace(xff)
		}
	}
	host := r.RemoteAddr
	if idx := strings.LastIndexByte(host, ':'); idx > 0 {
		host = host[:idx]
	}
	return strings.Trim(host, "[]")
}
