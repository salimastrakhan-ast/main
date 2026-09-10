// Package store — доступ к Postgres. Здесь живёт весь SQL; выше по стеку
// запросов к базе нет.
package store

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Ошибки, на которые реагируют вышележащие слои.
var (
	ErrNotFound  = errors.New("не найдено")
	ErrForbidden = errors.New("нет доступа")
	ErrConflict  = errors.New("конфликт")
)

type Store struct {
	pool *pgxpool.Pool
}

func New(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

func (s *Store) Pool() *pgxpool.Pool { return s.pool }

// Connect поднимает пул и ждёт готовности базы: в docker-compose Postgres
// стартует не мгновенно, а сервер поднимается рядом.
func Connect(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("разбор DSN: %w", err)
	}
	cfg.MaxConns = 16
	cfg.MaxConnLifetime = time.Hour

	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return nil, fmt.Errorf("подключение к Postgres: %w", err)
	}

	deadline := time.Now().Add(30 * time.Second)
	for {
		if err = pool.Ping(ctx); err == nil {
			return pool, nil
		}
		if time.Now().After(deadline) || ctx.Err() != nil {
			pool.Close()
			return nil, fmt.Errorf("Postgres не отвечает: %w", err)
		}
		select {
		case <-ctx.Done():
			pool.Close()
			return nil, ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
	}
}
