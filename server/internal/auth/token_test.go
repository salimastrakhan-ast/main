package auth

import (
	"testing"
	"time"

	"github.com/google/uuid"
)

func TestTokenRoundTrip(t *testing.T) {
	issuer := NewTokenIssuer([]byte("secret-secret-secret"), 15*time.Minute)
	userID, deviceID := uuid.New(), uuid.New()
	now := time.Now()

	token, err := issuer.Issue(userID, deviceID, now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	claims, err := issuer.Parse(token, now)
	if err != nil {
		t.Fatalf("Parse: %v", err)
	}
	if claims.UserID != userID || claims.DeviceID != deviceID {
		t.Errorf("claims = %+v, ожидались user %s и device %s", claims, userID, deviceID)
	}
}

func TestTokenExpires(t *testing.T) {
	issuer := NewTokenIssuer([]byte("secret-secret-secret"), time.Minute)
	now := time.Now()
	token, err := issuer.Issue(uuid.New(), uuid.New(), now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	if _, err := issuer.Parse(token, now.Add(2*time.Minute)); err == nil {
		t.Error("протухший токен принят")
	}
}

func TestTokenRejectsForeignSignature(t *testing.T) {
	mine := NewTokenIssuer([]byte("secret-secret-secret"), time.Minute)
	theirs := NewTokenIssuer([]byte("another-another-key"), time.Minute)
	now := time.Now()

	token, err := theirs.Issue(uuid.New(), uuid.New(), now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	if _, err := mine.Parse(token, now); err == nil {
		t.Error("токен, подписанный чужим ключом, принят")
	}
}

func TestTokenRejectsTampering(t *testing.T) {
	issuer := NewTokenIssuer([]byte("secret-secret-secret"), time.Minute)
	now := time.Now()
	token, err := issuer.Issue(uuid.New(), uuid.New(), now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}

	// Подмена одного символа в payload обязана ломать подпись — иначе можно
	// было бы подставить чужой user id.
	broken := []byte(token)
	for i, c := range broken {
		if c == '.' {
			broken[i+1] ^= 1
			break
		}
	}
	if _, err := issuer.Parse(string(broken), now); err == nil {
		t.Error("токен с изменённым payload принят")
	}

	if _, err := issuer.Parse("не.токен.вовсе", now); err == nil {
		t.Error("мусор принят как токен")
	}
	if _, err := issuer.Parse("", now); err == nil {
		t.Error("пустая строка принята как токен")
	}
}

func TestRefreshTokenIsUniqueAndHashed(t *testing.T) {
	a, hashA, err := NewRefreshToken()
	if err != nil {
		t.Fatalf("NewRefreshToken: %v", err)
	}
	b, _, err := NewRefreshToken()
	if err != nil {
		t.Fatalf("NewRefreshToken: %v", err)
	}
	if a == b {
		t.Error("два вызова вернули одинаковый токен")
	}
	if string(hashA) == a {
		t.Error("в базу уходит сам токен вместо его хэша")
	}
	if string(HashToken(a)) != string(hashA) {
		t.Error("HashToken даёт не тот хэш, что NewRefreshToken")
	}
}
