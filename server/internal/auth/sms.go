package auth

import (
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// SMSSender доставляет код подтверждения. Провайдер меняется одной строкой в
// main — остальной код о нём не знает.
type SMSSender interface {
	Send(ctx context.Context, phone, code string) error
}

// LogSender печатает код в лог вместо отправки. Нужен для разработки и
// тестов: поднимать SMS-провайдера ради локального запуска не надо.
type LogSender struct{ Logger *slog.Logger }

func (s LogSender) Send(_ context.Context, phone, code string) error {
	logger := s.Logger
	if logger == nil {
		logger = slog.Default()
	}
	logger.Info("код подтверждения (dev)", "phone", phone, "code", code)
	return nil
}

// SMSRuSender — отправка через sms.ru, один из российских провайдеров.
//
// Российские номера через зарубежные шлюзы доходят плохо и дорого, поэтому
// провайдер тут локальный. SMSC подключается так же — меняется только URL и
// имена параметров.
type SMSRuSender struct {
	APIKey string
	From   string
	Client *http.Client
}

func (s SMSRuSender) Send(ctx context.Context, phone, code string) error {
	client := s.Client
	if client == nil {
		client = &http.Client{Timeout: 10 * time.Second}
	}

	form := url.Values{
		"api_id": {s.APIKey},
		"to":     {phone},
		"msg":    {fmt.Sprintf("Код входа: %s", code)},
		"json":   {"1"},
	}
	if s.From != "" {
		form.Set("from", s.From)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost,
		"https://sms.ru/sms/send", strings.NewReader(form.Encode()))
	if err != nil {
		return fmt.Errorf("запрос к sms.ru: %w", err)
	}
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")

	resp, err := client.Do(req)
	if err != nil {
		return fmt.Errorf("отправка SMS: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(io.LimitReader(resp.Body, 4<<10))
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("sms.ru ответил %d: %s", resp.StatusCode, body)
	}
	// Провайдер отдаёт HTTP 200 и на отказ, статус лежит внутри тела.
	if !strings.Contains(string(body), `"status":"OK"`) {
		return fmt.Errorf("sms.ru отказал: %s", body)
	}
	return nil
}
