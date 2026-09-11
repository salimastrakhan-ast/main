package api

import (
	"crypto/hmac"
	"crypto/sha1"
	"encoding/base64"
	"net/http"
	"strconv"
	"strings"
	"time"
)

// Раздача адресов для звонка.
//
// Клиенту нужны два вида серверов. STUN отвечает на вопрос «как я выгляжу
// снаружи» — этого хватает, когда оба собеседника за обычным домашним
// роутером. TURN пересылает звук через себя и нужен там, где прямое
// соединение не встаёт: симметричный NAT у оператора мобильной связи,
// корпоративная сеть, строгий фаервол. По разным оценкам это от десятой
// части до трети звонков, поэтому без TURN мессенджер работает «через раз»,
// и объяснить человеку, почему именно, невозможно.
//
// Пароль к TURN выписывается временный. Схема coturn `use-auth-secret`:
// логином служит срок годности со временем Unix, паролем — подпись этого
// логина общим секретом. Секрет знают только сервер и coturn; из приложения
// его не достать, а выписанный пароль протухает сам. Постоянный пароль,
// зашитый в клиент, означал бы открытый релей для всех, кто разобрал APK.

type iceServer struct {
	URLs       []string `json:"urls"`
	Username   string   `json:"username,omitempty"`
	Credential string   `json:"credential,omitempty"`
}

// handleICEServers отдаёт список серверов для звонка текущему пользователю.
func (s *Server) handleICEServers(w http.ResponseWriter, r *http.Request) {
	me, _ := identityFrom(r.Context())

	servers := make([]iceServer, 0, 2)
	if s.cfg.STUNURL != "" {
		servers = append(servers, iceServer{URLs: splitURLs(s.cfg.STUNURL)})
	}
	if s.cfg.TURNURL != "" && s.cfg.TURNSecret != "" {
		expires := time.Now().Add(s.cfg.TURNTTL).Unix()
		username := strconv.FormatInt(expires, 10) + ":" + me.UserID.String()
		servers = append(servers, iceServer{
			URLs:       splitURLs(s.cfg.TURNURL),
			Username:   username,
			Credential: turnCredential(username, s.cfg.TURNSecret),
		})
	}

	// Пустой список — рабочее состояние, а не ошибка: без TURN звонок всё
	// равно встанет там, где сети не мешают. Клиент показывает «не удалось
	// соединиться», если не встал, и это честнее отказа звонить вовсе.
	writeJSON(w, http.StatusOK, map[string]any{"ice_servers": servers})
}

// turnCredential подписывает логин общим с coturn секретом.
//
// SHA-1 здесь не выбор, а требование: так описан REST-механизм coturn
// (draft-uberti-behave-turn-rest), и подпись другим алгоритмом он не примет.
// Ключом она не является и живёт часы, так что слабость SHA-1 к коллизиям
// тут ни при чём.
func turnCredential(username, secret string) string {
	mac := hmac.New(sha1.New, []byte(secret))
	mac.Write([]byte(username))
	return base64.StdEncoding.EncodeToString(mac.Sum(nil))
}

// splitURLs разбирает список адресов через запятую.
//
// У одного TURN их обычно несколько: UDP быстрее, TCP и TLS на 443 проходят
// там, где всё остальное режут.
func splitURLs(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}
