// Package push — доставка уведомлений на устройства, которых нет в сети.
//
// Реализации пока нет по существу: у российских пользователей на новых Android
// нет сервисов Google, поэтому FCM для них не работает, и связка получается
// из RuStore Push для Android и APNs для iOS. Это отдельная работа с
// аккаунтами у провайдеров, а до неё интерфейс и точка вызова уже стоят на
// месте — подключение не потребует менять логику рассылки.
package push

import (
	"context"
	"log/slog"

	"github.com/google/uuid"
)

// Notification — то, что увидит человек на заблокированном экране.
type Notification struct {
	UserID uuid.UUID
	ChatID uuid.UUID
	Title  string
	Body   string
	Badge  int64
	Tokens []string
}

type Pusher interface {
	Push(ctx context.Context, n Notification) error
}

// NoopPusher пишет уведомление в лог вместо отправки.
type NoopPusher struct{ Logger *slog.Logger }

func (p NoopPusher) Push(_ context.Context, n Notification) error {
	logger := p.Logger
	if logger == nil {
		logger = slog.Default()
	}
	logger.Debug("push (заглушка)",
		"user", n.UserID, "chat", n.ChatID, "title", n.Title, "badge", n.Badge,
		"tokens", len(n.Tokens))
	return nil
}
