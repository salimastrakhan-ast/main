// Package ratelimit — счётчики попыток в Redis.
//
// Лимиты живут в Redis, а не в памяти процесса, чтобы при нескольких
// инстансах сервера злоумышленник не получал лимит, умноженный на их число.
package ratelimit

import (
	"context"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

type Limiter struct {
	rdb *redis.Client
}

func New(rdb *redis.Client) *Limiter { return &Limiter{rdb: rdb} }

// Allow увеличивает счётчик ключа и говорит, укладываемся ли мы в лимит.
// Второе значение — через сколько имеет смысл повторить.
func (l *Limiter) Allow(ctx context.Context, key string, limit int, window time.Duration) (bool, time.Duration, error) {
	pipe := l.rdb.TxPipeline()
	incr := pipe.Incr(ctx, key)
	// NX не даёт продлевать окно каждым новым запросом: иначе непрерывный
	// поток попыток держал бы TTL вечно живым.
	pipe.ExpireNX(ctx, key, window)
	if _, err := pipe.Exec(ctx); err != nil {
		return false, 0, fmt.Errorf("счётчик лимита %s: %w", key, err)
	}

	if incr.Val() <= int64(limit) {
		return true, 0, nil
	}

	ttl, err := l.rdb.TTL(ctx, key).Result()
	if err != nil || ttl < 0 {
		ttl = window
	}
	return false, ttl, nil
}

// Reset снимает счётчик — вызывается после успешного входа, чтобы неудачные
// попытки не висели на человеке после того, как он всё-таки вошёл.
func (l *Limiter) Reset(ctx context.Context, key string) error {
	if err := l.rdb.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("сброс лимита %s: %w", key, err)
	}
	return nil
}

// Connect поднимает клиент Redis и проверяет доступность.
func Connect(ctx context.Context, rawURL string) (*redis.Client, error) {
	opt, err := redis.ParseURL(rawURL)
	if err != nil {
		return nil, fmt.Errorf("разбор адреса Redis: %w", err)
	}
	rdb := redis.NewClient(opt)

	deadline := time.Now().Add(30 * time.Second)
	for {
		if err = rdb.Ping(ctx).Err(); err == nil {
			return rdb, nil
		}
		if time.Now().After(deadline) || ctx.Err() != nil {
			_ = rdb.Close()
			return nil, fmt.Errorf("Redis не отвечает: %w", err)
		}
		select {
		case <-ctx.Done():
			_ = rdb.Close()
			return nil, ctx.Err()
		case <-time.After(500 * time.Millisecond):
		}
	}
}
