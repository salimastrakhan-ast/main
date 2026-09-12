// Package auth — вход по номеру телефона.
//
// Схема как в Телеграме: пароля нет, регистрация и вход — это одно действие.
// Человек вводит номер, получает код, обменивает его на пару токенов.
// Короткий access живёт в памяти клиента, длинный refresh — в защищённом
// хранилище устройства и ротируется при каждом обновлении.
package auth

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"errors"
	"fmt"
	"math/big"
	"time"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/ratelimit"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

var (
	ErrRateLimited     = errors.New("слишком часто")
	ErrCodeInvalid     = errors.New("неверный код")
	ErrCodeExpired     = errors.New("код истёк")
	ErrTooManyAttempts = errors.New("слишком много попыток")
)

// RateLimitedError несёт время, через которое имеет смысл повторить.
type RateLimitedError struct{ RetryAfter time.Duration }

func (e *RateLimitedError) Error() string {
	return fmt.Sprintf("слишком часто, повторите через %s", e.RetryAfter)
}
func (e *RateLimitedError) Unwrap() error { return ErrRateLimited }

type Config struct {
	CodeTTL      time.Duration
	RefreshTTL   time.Duration
	MaxAttempts  int
	ExposeCode   bool
	CodeSecret   []byte
	PhoneLimit   int
	PhoneWindow  time.Duration
	IPLimit      int
	IPWindow     time.Duration
	VerifyLimit  int
	VerifyWindow time.Duration
}

func DefaultConfig() Config {
	return Config{
		CodeTTL:      5 * time.Minute,
		RefreshTTL:   30 * 24 * time.Hour,
		MaxAttempts:  5,
		PhoneLimit:   3,
		PhoneWindow:  10 * time.Minute,
		IPLimit:      20,
		IPWindow:     time.Hour,
		VerifyLimit:  10,
		VerifyWindow: 10 * time.Minute,
	}
}

type Service struct {
	store   *store.Store
	limiter *ratelimit.Limiter
	sms     SMSSender
	tokens  *TokenIssuer
	cfg     Config
}

func NewService(st *store.Store, limiter *ratelimit.Limiter, sms SMSSender, tokens *TokenIssuer, cfg Config) *Service {
	return &Service{store: st, limiter: limiter, sms: sms, tokens: tokens, cfg: cfg}
}

type RequestCodeResult struct {
	Phone      string `json:"phone"`
	ExpiresIn  int    `json:"expires_in"`
	RetryAfter int    `json:"retry_after"`
	DevCode    string `json:"dev_code,omitempty"`
}

// RequestCode генерирует код и отправляет его на номер.
func (s *Service) RequestCode(ctx context.Context, rawPhone, ip string) (RequestCodeResult, error) {
	phone, err := NormalizePhone(rawPhone)
	if err != nil {
		return RequestCodeResult{}, err
	}

	// Два независимых лимита: по номеру — чтобы не заваливать человека SMS
	// и не жечь деньги на отправке, по IP — чтобы одна машина не перебирала
	// номера пачками.
	if err := s.check(ctx, "rl:code:phone:"+phone, s.cfg.PhoneLimit, s.cfg.PhoneWindow); err != nil {
		return RequestCodeResult{}, err
	}
	if ip != "" {
		if err := s.check(ctx, "rl:code:ip:"+ip, s.cfg.IPLimit, s.cfg.IPWindow); err != nil {
			return RequestCodeResult{}, err
		}
	}

	code, err := newCode()
	if err != nil {
		return RequestCodeResult{}, err
	}
	if err := s.store.PutAuthCode(ctx, phone, s.hashCode(phone, code), time.Now().Add(s.cfg.CodeTTL)); err != nil {
		return RequestCodeResult{}, err
	}
	if err := s.sms.Send(ctx, phone, code); err != nil {
		return RequestCodeResult{}, err
	}

	res := RequestCodeResult{
		Phone:      phone,
		ExpiresIn:  int(s.cfg.CodeTTL.Seconds()),
		RetryAfter: int(s.cfg.PhoneWindow.Seconds() / float64(s.cfg.PhoneLimit)),
	}
	if s.cfg.ExposeCode {
		res.DevCode = code
	}
	return res, nil
}

type DeviceInfo struct {
	Platform  string
	Name      string
	PushToken string
}

type Session struct {
	User         domain.User   `json:"user"`
	Device       domain.Device `json:"device"`
	AccessToken  string        `json:"access_token"`
	RefreshToken string        `json:"refresh_token"`
	ExpiresIn    int           `json:"expires_in"`
}

// Verify сверяет код и заводит сессию устройства.
func (s *Service) Verify(ctx context.Context, rawPhone, code string, dev DeviceInfo) (Session, error) {
	phone, err := NormalizePhone(rawPhone)
	if err != nil {
		return Session{}, err
	}
	if err := s.check(ctx, "rl:verify:"+phone, s.cfg.VerifyLimit, s.cfg.VerifyWindow); err != nil {
		return Session{}, err
	}

	// Счётчик попыток растёт до сверки — иначе параллельные запросы успевали
	// бы перебирать код, пока счётчик догоняет.
	stored, err := s.store.TakeAuthCodeAttempt(ctx, phone)
	if errors.Is(err, store.ErrNotFound) {
		return Session{}, ErrCodeInvalid
	}
	if err != nil {
		return Session{}, err
	}
	if stored.Attempts > s.cfg.MaxAttempts {
		_ = s.store.DeleteAuthCode(ctx, phone)
		return Session{}, ErrTooManyAttempts
	}
	if time.Now().After(stored.ExpiresAt) {
		_ = s.store.DeleteAuthCode(ctx, phone)
		return Session{}, ErrCodeExpired
	}
	if !hmac.Equal(stored.CodeHash, s.hashCode(phone, code)) {
		return Session{}, ErrCodeInvalid
	}

	// Код одноразовый: сразу после успешной сверки его быть не должно.
	if err := s.store.DeleteAuthCode(ctx, phone); err != nil {
		return Session{}, err
	}
	_ = s.limiter.Reset(ctx, "rl:verify:"+phone)

	user, err := s.store.EnsureUserByPhone(ctx, phone)
	if err != nil {
		return Session{}, err
	}
	return s.startSession(ctx, user, dev)
}

func (s *Service) startSession(ctx context.Context, user domain.User, dev DeviceInfo) (Session, error) {
	refresh, refreshHash, err := NewRefreshToken()
	if err != nil {
		return Session{}, err
	}
	device, err := s.store.CreateDevice(ctx, user.ID, dev.Platform, dev.Name, refreshHash)
	if err != nil {
		return Session{}, err
	}
	if dev.PushToken != "" {
		if err := s.store.SetPushToken(ctx, device.ID, dev.PushToken); err != nil {
			return Session{}, err
		}
	}

	access, err := s.tokens.Issue(user.ID, device.ID, time.Now())
	if err != nil {
		return Session{}, err
	}
	return Session{
		User:         user,
		Device:       device,
		AccessToken:  access,
		RefreshToken: refresh,
		ExpiresIn:    int(s.tokens.TTL().Seconds()),
	}, nil
}

// Refresh обменивает refresh-токен на новую пару.
//
// Старый токен перестаёт работать в тот же момент: если он утёк, у вора есть
// окно только до ближайшего обновления легальным клиентом.
func (s *Service) Refresh(ctx context.Context, refreshToken string) (Session, error) {
	newToken, newHash, err := NewRefreshToken()
	if err != nil {
		return Session{}, err
	}

	device, err := s.store.RotateRefresh(ctx, HashToken(refreshToken), newHash, s.cfg.RefreshTTL)
	if errors.Is(err, store.ErrNotFound) {
		return Session{}, ErrBadToken
	}
	if err != nil {
		return Session{}, err
	}

	user, err := s.store.UserByID(ctx, device.UserID)
	if err != nil {
		return Session{}, err
	}
	access, err := s.tokens.Issue(user.ID, device.ID, time.Now())
	if err != nil {
		return Session{}, err
	}
	return Session{
		User:         user,
		Device:       device,
		AccessToken:  access,
		RefreshToken: newToken,
		ExpiresIn:    int(s.tokens.TTL().Seconds()),
	}, nil
}

func (s *Service) Logout(ctx context.Context, refreshToken string) error {
	// Ротация в никуда: строка находится по старому хэшу, после чего
	// устройство помечается отозванным.
	_, hash, err := NewRefreshToken()
	if err != nil {
		return err
	}
	device, err := s.store.RotateRefresh(ctx, HashToken(refreshToken), hash, s.cfg.RefreshTTL)
	if errors.Is(err, store.ErrNotFound) {
		return nil // Уже разлогинен — считаем успехом.
	}
	if err != nil {
		return err
	}
	return s.store.RevokeDevice(ctx, device.ID)
}

func (s *Service) Tokens() *TokenIssuer { return s.tokens }

func (s *Service) check(ctx context.Context, key string, limit int, window time.Duration) error {
	ok, retryAfter, err := s.limiter.Allow(ctx, key, limit, window)
	if err != nil {
		return err
	}
	if !ok {
		return &RateLimitedError{RetryAfter: retryAfter}
	}
	return nil
}

// hashCode солит код номером и секретом сервера.
//
// Шестизначный код перебирается за миллион хэшей, поэтому голый SHA-256 из
// дампа базы вскрывается мгновенно. HMAC с серверным секретом делает дамп
// бесполезным без самого секрета.
func (s *Service) hashCode(phone, code string) []byte {
	mac := hmac.New(sha256.New, s.cfg.CodeSecret)
	mac.Write([]byte(phone))
	mac.Write([]byte{0})
	mac.Write([]byte(code))
	return mac.Sum(nil)
}

func newCode() (string, error) {
	n, err := rand.Int(rand.Reader, big.NewInt(1000000))
	if err != nil {
		return "", fmt.Errorf("генерация кода: %w", err)
	}
	return fmt.Sprintf("%06d", n.Int64()), nil
}
