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
	DatabaseURL string
	RedisURL    string

	JWTSecret    []byte
	AccessTTL    time.Duration
	RefreshTTL   time.Duration
	AuthCodeTTL  time.Duration
	AuthCodeTry  int
	DevExposeSMS bool

	S3Endpoint  string
	S3AccessKey string
	S3SecretKey string
	S3Bucket    string
	S3UseSSL    bool

	MaxUploadBytes int64
}

func Load() (Config, error) {
	c := Config{
		Env:         env("MAYAK_ENV", "dev"),
		HTTPAddr:    env("MAYAK_HTTP_ADDR", ":8080"),
		PublicURL:   env("MAYAK_PUBLIC_URL", "http://localhost:8080"),
		DatabaseURL: env("MAYAK_DATABASE_URL", "postgres://mayak:mayak@localhost:5433/mayak?sslmode=disable"),
		RedisURL:    env("MAYAK_REDIS_URL", "redis://localhost:6380/0"),

		AccessTTL:   envDuration("MAYAK_ACCESS_TTL", 15*time.Minute),
		RefreshTTL:  envDuration("MAYAK_REFRESH_TTL", 30*24*time.Hour),
		AuthCodeTTL: envDuration("MAYAK_AUTH_CODE_TTL", 5*time.Minute),
		AuthCodeTry: envInt("MAYAK_AUTH_CODE_ATTEMPTS", 5),

		S3Endpoint:  env("MAYAK_S3_ENDPOINT", "localhost:9000"),
		S3AccessKey: env("MAYAK_S3_ACCESS_KEY", "mayak"),
		S3SecretKey: env("MAYAK_S3_SECRET_KEY", "mayakmayak"),
		S3Bucket:    env("MAYAK_S3_BUCKET", "mayak-media"),
		S3UseSSL:    envBool("MAYAK_S3_USE_SSL", false),

		MaxUploadBytes: int64(envInt("MAYAK_MAX_UPLOAD_MB", 50)) << 20,
	}

	c.JWTSecret = []byte(env("MAYAK_JWT_SECRET", ""))
	if len(c.JWTSecret) == 0 {
		if c.Env != "dev" {
			return Config{}, errors.New("config: MAYAK_JWT_SECRET обязателен вне dev-окружения")
		}
		c.JWTSecret = []byte("dev-secret-not-for-production")
	}
	if len(c.JWTSecret) < 16 {
		return Config{}, fmt.Errorf("config: MAYAK_JWT_SECRET слишком короткий (%d байт, нужно от 16)", len(c.JWTSecret))
	}

	// В dev код подтверждения возвращается в ответе API, чтобы не поднимать
	// SMS-провайдера. В проде это дыра, поэтому включается только явно.
	c.DevExposeSMS = c.Env == "dev" && envBool("MAYAK_DEV_EXPOSE_SMS", true)

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
