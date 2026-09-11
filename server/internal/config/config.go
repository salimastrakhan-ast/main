// Package config собирает настройки приложения из окружения.
//
// Значения по умолчанию рассчитаны на docker-compose из deploy/, поэтому
// локально сервер запускается вообще без переменных окружения.
package config

import (
	"errors"
	"fmt"
	"os"
	"strconv"
	"time"
)

type Config struct {
	Env         string
	HTTPAddr    string
	PublicURL   string
	TrustProxy  bool
	CORSOrigins string
	DatabaseURL string
	RedisURL    string

	JWTSecret    []byte
	AccessTTL    time.Duration
	RefreshTTL   time.Duration
	AuthCodeTTL  time.Duration
	AuthCodeTry  int
	DevExposeSMS bool
	SMSRuAPIKey  string
	SMSRuFrom    string

	S3Endpoint  string
	S3AccessKey string
	S3SecretKey string
	S3Bucket    string
	S3UseSSL    bool

	MaxUploadBytes int64
}

func Load() (Config, error) {
	c := Config{
		Env:       env("TITO_ENV", "dev"),
		HTTPAddr:  env("TITO_HTTP_ADDR", ":8080"),
		PublicURL: env("TITO_PUBLIC_URL", "http://localhost:8080"),
		// X-Forwarded-For можно верить только если перед сервером стоит наш
		// прокси: иначе любой клиент подделает свой IP и обойдёт лимиты.
		TrustProxy: envBool("TITO_TRUST_PROXY", false),
		// Пусто — CORS выключен, и это правильное значение для мобильных
		// клиентов. Веб-клиенту адрес перечисляют явно; звёздочка в проде
		// означала бы, что любой сайт ходит в API от имени вошедшего.
		CORSOrigins: env("TITO_CORS_ORIGINS", ""),
		DatabaseURL: env("TITO_DATABASE_URL", "postgres://tito:tito@localhost:5433/tito?sslmode=disable"),
		RedisURL:    env("TITO_REDIS_URL", "redis://localhost:6380/0"),

		AccessTTL:   envDuration("TITO_ACCESS_TTL", 15*time.Minute),
		RefreshTTL:  envDuration("TITO_REFRESH_TTL", 30*24*time.Hour),
		AuthCodeTTL: envDuration("TITO_AUTH_CODE_TTL", 5*time.Minute),
		AuthCodeTry: envInt("TITO_AUTH_CODE_ATTEMPTS", 5),

		SMSRuAPIKey: env("TITO_SMSRU_API_KEY", ""),
		SMSRuFrom:   env("TITO_SMSRU_FROM", ""),

		S3Endpoint:  env("TITO_S3_ENDPOINT", "localhost:9000"),
		S3AccessKey: env("TITO_S3_ACCESS_KEY", "tito"),
		S3SecretKey: env("TITO_S3_SECRET_KEY", "titotito"),
		S3Bucket:    env("TITO_S3_BUCKET", "tito-media"),
		S3UseSSL:    envBool("TITO_S3_USE_SSL", false),

		MaxUploadBytes: int64(envInt("TITO_MAX_UPLOAD_MB", 50)) << 20,
	}

	c.JWTSecret = []byte(env("TITO_JWT_SECRET", ""))
	if len(c.JWTSecret) == 0 {
		if c.Env != "dev" {
			return Config{}, errors.New("config: TITO_JWT_SECRET обязателен вне dev-окружения")
		}
		c.JWTSecret = []byte("dev-secret-not-for-production")
	}
	if len(c.JWTSecret) < 16 {
		return Config{}, fmt.Errorf("config: TITO_JWT_SECRET слишком короткий (%d байт, нужно от 16)", len(c.JWTSecret))
	}

	// В dev код подтверждения возвращается в ответе API, чтобы не поднимать
	// SMS-провайдера. В проде это дыра, поэтому включается только явно.
	c.DevExposeSMS = c.Env == "dev" && envBool("TITO_DEV_EXPOSE_SMS", true)

	return c, nil
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func envInt(key string, def int) int {
	if v, err := strconv.Atoi(os.Getenv(key)); err == nil {
		return v
	}
	return def
}

func envBool(key string, def bool) bool {
	if v, err := strconv.ParseBool(os.Getenv(key)); err == nil {
		return v
	}
	return def
}

func envDuration(key string, def time.Duration) time.Duration {
	if v, err := time.ParseDuration(os.Getenv(key)); err == nil {
		return v
	}
	return def
}
