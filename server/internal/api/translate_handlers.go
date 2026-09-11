package api

import (
	"encoding/json"
	"errors"
	"net/http"

	"github.com/salimastrakhan-ast/main/server/internal/translate"
)

type translateReq struct {
	Items      []translate.Item `json:"items"`
	TargetLang string           `json:"target_lang"`
}

// handleTranslate переводит пачку сообщений на язык читателя.
//
// Перевод намеренно не сохраняется: он принадлежит читателю, а не переписке.
// Двое в одном чате могут читать на разных языках, и складывать в сообщение
// чей-то один перевод значит сделать выбор за второго.
func (s *Server) handleTranslate(w http.ResponseWriter, r *http.Request) {
	var req translateReq
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "bad_request", "Не удалось разобрать запрос")
		return
	}
	if len(req.Items) == 0 || req.TargetLang == "" {
		writeError(w, http.StatusBadRequest, "bad_request", "Нужны сообщения и язык")
		return
	}
	// Предел на пачку: без него один запрос может увести всю ленту на сотни
	// сообщений и оплату за них.
	if len(req.Items) > 100 {
		writeError(w, http.StatusBadRequest, "too_many", "За раз не больше ста сообщений")
		return
	}

	results, err := s.tr.Translate(r.Context(), req.Items, req.TargetLang)
	if errors.Is(err, translate.ErrNotConfigured) {
		// Отдельный код, а не общая ошибка: по нему клиент говорит «перевод
		// не подключён», а не пугает человека неизвестной поломкой.
		writeError(w, http.StatusServiceUnavailable, "translate_not_configured",
			"Перевод пока не подключён")
		return
	}
	if err != nil {
		writeError(w, http.StatusBadGateway, "translate_failed", "Поставщик перевода не ответил")
		return
	}

	writeJSON(w, http.StatusOK, map[string]any{"items": results})
}
