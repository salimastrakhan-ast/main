package auth

import (
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
)

var ErrBadToken = errors.New("невалидный токен")

// Claims — полезная нагрузка access-токена.
//
// DeviceID нужен, чтобы разлогинить одно устройство, не трогая остальные:
// отозванное устройство перестаёт обновлять токен, и его access протухает
// за AccessTTL.
type Claims struct {
	UserID   uuid.UUID `json:"sub"`
	DeviceID uuid.UUID `json:"did"`
	IssuedAt int64     `json:"iat"`
	Expires  int64     `json:"exp"`
}

// TokenIssuer выпускает и проверяет access-токены.
//
// Это компактный JWT-совместимый HS256 без внешних зависимостей: формат
// header.payload.signature с base64url. Библиотека тут дала бы только
// разбор чужих токенов, а мы проверяем исключительно свои.
type TokenIssuer struct {
	secret []byte
	ttl    time.Duration
}

func NewTokenIssuer(secret []byte, ttl time.Duration) *TokenIssuer {
	return &TokenIssuer{secret: secret, ttl: ttl}
}

func (t *TokenIssuer) TTL() time.Duration { return t.ttl }

func (t *TokenIssuer) Issue(userID, deviceID uuid.UUID, now time.Time) (string, error) {
	claims := Claims{
		UserID:   userID,
		DeviceID: deviceID,
		IssuedAt: now.Unix(),
		Expires:  now.Add(t.ttl).Unix(),
	}
	payload, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("сериализация claims: %w", err)
	}

	header := b64([]byte(`{"alg":"HS256","typ":"JWT"}`))
	body := b64(payload)
	signed := header + "." + body
	return signed + "." + b64(t.sign(signed)), nil
}

func (t *TokenIssuer) Parse(token string, now time.Time) (Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return Claims{}, ErrBadToken
	}

	want := t.sign(parts[0] + "." + parts[1])
	got, err := unb64(parts[2])
	if err != nil {
		return Claims{}, ErrBadToken
	}
	// Сравнение за постоянное время: иначе по времени ответа можно
	// подбирать подпись байт за байтом.
	if !hmac.Equal(want, got) {
		return Claims{}, ErrBadToken
	}

	raw, err := unb64(parts[1])
	if err != nil {
		return Claims{}, ErrBadToken
	}
	var claims Claims
	if err := json.Unmarshal(raw, &claims); err != nil {
		return Claims{}, ErrBadToken
	}
	if claims.UserID == uuid.Nil || now.Unix() >= claims.Expires {
		return Claims{}, ErrBadToken
	}
	return claims, nil
}

func (t *TokenIssuer) sign(data string) []byte {
	mac := hmac.New(sha256.New, t.secret)
	mac.Write([]byte(data))
	return mac.Sum(nil)
}

func b64(data []byte) string { return base64.RawURLEncoding.EncodeToString(data) }

func unb64(s string) ([]byte, error) { return base64.RawURLEncoding.DecodeString(s) }

// NewRefreshToken выдаёт непрозрачный случайный токен. В базе лежит только
// его SHA-256, поэтому дамп таблицы devices не даёт войти ни в один аккаунт.
func NewRefreshToken() (token string, hash []byte, err error) {
	buf := make([]byte, 32)
	if _, err := rand.Read(buf); err != nil {
		return "", nil, fmt.Errorf("генерация refresh-токена: %w", err)
	}
	token = base64.RawURLEncoding.EncodeToString(buf)
	return token, HashToken(token), nil
}

func HashToken(token string) []byte {
	sum := sha256.Sum256([]byte(token))
	return sum[:]
}
