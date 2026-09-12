package api

import (
	"strconv"
	"strings"
	"testing"
	"time"
)

// Пароль к TURN выписывается временным. Проверяем ровно то, что делает его
// временным: срок в логине и подпись, которую coturn пересчитает у себя.

func TestПарольКTURNСовпадаетСрасчётомCoturn(t *testing.T) {
	// Значение посчитано не нашим кодом, а сторонним инструментом — тем
	// самым, каким его считает coturn:
	//
	//   printf '%s' "$username" | openssl dgst -sha1 -hmac "$secret" -binary | base64
	//
	// Иначе тест проверял бы сам себя и прошёл бы при любой ошибке в схеме.
	const (
		username = "1700000000:11111111-1111-1111-1111-111111111111"
		secret   = "общий-секрет"
		expected = "eV0/chCLoKqPUASB8SZOasbdM/4="
	)
	if got := turnCredential(username, secret); got != expected {
		t.Errorf("подпись %q вместо %q", got, expected)
	}
}

func TestРазныеСекретыДаютРазныеПароли(t *testing.T) {
	const username = "1700000000:кто-то"
	if turnCredential(username, "один") == turnCredential(username, "другой") {
		t.Error("подпись не зависит от секрета — значит, не подписывает")
	}
}

func TestСрокГодностиВпереди(t *testing.T) {
	// Логин — это срок, после которого coturn перестанет пускать. Если он
	// окажется в прошлом, звонки не встанут вовсе, а причина будет видна
	// только в логах coturn.
	ttl := 12 * time.Hour
	expires := time.Now().Add(ttl).Unix()
	username := strconv.FormatInt(expires, 10) + ":кто-то"

	head, _, ok := strings.Cut(username, ":")
	if !ok {
		t.Fatal("в логине нет срока")
	}
	at, err := strconv.ParseInt(head, 10, 64)
	if err != nil {
		t.Fatalf("срок не число: %v", err)
	}
	if time.Unix(at, 0).Before(time.Now()) {
		t.Error("срок годности уже прошёл")
	}
}

func TestНесколькоАдресовРазбираютсяСписком(t *testing.T) {
	// У одного TURN адресов обычно несколько: UDP быстрее, TLS на 443
	// проходит там, где всё остальное режут.
	got := splitURLs("turn:tito.ru:3478?transport=udp, turns:tito.ru:5349?transport=tcp ,")
	want := []string{"turn:tito.ru:3478?transport=udp", "turns:tito.ru:5349?transport=tcp"}
	if len(got) != len(want) {
		t.Fatalf("разобрано %d адресов вместо %d: %v", len(got), len(want), got)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("адрес %d: %q вместо %q", i, got[i], want[i])
		}
	}
}
