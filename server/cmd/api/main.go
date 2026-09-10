// Команда api — единая точка входа: REST и WebSocket на одном порту.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/salimastrakhan-ast/main/server/internal/api"
	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/config"
	"github.com/salimastrakhan-ast/main/server/internal/media"
	"github.com/salimastrakhan-ast/main/server/internal/push"
	"github.com/salimastrakhan-ast/main/server/internal/ratelimit"
	"github.com/salimastrakhan-ast/main/server/internal/realtime"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

func main() {
	if err := run(); err != nil {
		slog.Error("сервер остановлен с ошибкой", "err", err)
		os.Exit(1)
	}
}

func run() error {
	cfg, err := config.Load()
	if err != nil {
		return err
	}

	logger := newLogger(cfg.Env)
	slog.SetDefault(logger)

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	pool, err := store.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	if err := store.Migrate(ctx, pool); err != nil {
		return err
	}
	logger.Info("миграции применены")

	rdb, err := ratelimit.Connect(ctx, cfg.RedisURL)
	if err != nil {
		return err
	}
	defer func() { _ = rdb.Close() }()

	st := store.New(pool)
	tokens := auth.NewTokenIssuer(cfg.JWTSecret, cfg.AccessTTL)
	authSvc := auth.NewService(st, ratelimit.New(rdb), newSMSSender(cfg, logger), tokens, authConfig(cfg))

	storage, err := media.NewStorage(ctx, media.Config{
		Endpoint:  cfg.S3Endpoint,
		AccessKey: cfg.S3AccessKey,
		SecretKey: cfg.S3SecretKey,
		Bucket:    cfg.S3Bucket,
		UseSSL:    cfg.S3UseSSL,
	})
	if err != nil {
		return err
	}
	logger.Info("хранилище готово", "bucket", cfg.S3Bucket)

	hub := realtime.NewHub(st, rdb, push.NoopPusher{Logger: logger}, tokens, storage, logger)
	hubDone := make(chan struct{})
	go func() {
		defer close(hubDone)
		hub.Run(ctx)
	}()

	srv := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           api.NewServer(cfg, st, authSvc, hub, storage).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		// Таймаут записи не ставим: у долгоживущих WebSocket-соединений он
		// рвёт связь по расписанию. Свои таймауты они держат сами.
	}

	errc := make(chan error, 1)
	go func() {
		logger.Info("сервер слушает", "addr", cfg.HTTPAddr, "env", cfg.Env)
		if err := srv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errc <- err
		}
	}()

	select {
	case err := <-errc:
		return err
	case <-ctx.Done():
		logger.Info("получен сигнал завершения")
	}

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	err = srv.Shutdown(shutdownCtx)
	<-hubDone
	return err
}

func authConfig(cfg config.Config) auth.Config {
	ac := auth.DefaultConfig()
	ac.CodeTTL = cfg.AuthCodeTTL
	ac.RefreshTTL = cfg.RefreshTTL
	ac.MaxAttempts = cfg.AuthCodeTry
	ac.ExposeCode = cfg.DevExposeSMS
	// Секрет для HMAC кодов выводим из основного, чтобы не заводить вторую
	// переменную окружения, но не переиспользуем его один в один.
	ac.CodeSecret = append([]byte("code:"), cfg.JWTSecret...)
	return ac
}

func newSMSSender(cfg config.Config, logger *slog.Logger) auth.SMSSender {
	if cfg.SMSRuAPIKey == "" {
		if cfg.Env != "dev" {
			logger.Warn("SMS-провайдер не настроен, коды уходят только в лог")
		}
		return auth.LogSender{Logger: logger}
	}
	logger.Info("SMS через sms.ru")
	return auth.SMSRuSender{APIKey: cfg.SMSRuAPIKey, From: cfg.SMSRuFrom}
}

func newLogger(env string) *slog.Logger {
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}
	if env == "dev" {
		opts.Level = slog.LevelDebug
		return slog.New(slog.NewTextHandler(os.Stdout, opts))
	}
	return slog.New(slog.NewJSONHandler(os.Stdout, opts))
}
