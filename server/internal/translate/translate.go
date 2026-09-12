// Package translate — перевод переписки на язык читателя.
//
// Это главное, ради чего интерфейс клиента устроен так, как устроен:
// тумблер «живой перевод» в шапке чата и кнопка «оригинал» на каждом
// сообщении. Самого поставщика здесь нет — это отдельная работа с чужим
// API и его оплатой, — но интерфейс и точка вызова уже на месте, и
// подключение не потребует трогать ни клиент, ни маршруты.
//
// Ровно та же схема, что у пушей в internal/push: пустая реализация по
// умолчанию, настоящая подставляется в main.
package translate

import (
	"context"
	"errors"
	"log/slog"
)

// ErrNotConfigured — поставщик не настроен. Отдельная ошибка, а не общий
// отказ: клиент по ней говорит человеку «перевод не подключён» вместо
// пугающего «что-то пошло не так».
var ErrNotConfigured = errors.New("поставщик перевода не настроен")

// Item — одно сообщение на перевод. Идентификатор возвращается обратно,
// чтобы клиент разложил ответы по своим сообщениям, не полагаясь на порядок.
type Item struct {
	ID   string `json:"id"`
	Text string `json:"text"`
}

// Result — перевод одного сообщения.
type Result struct {
	ID string `json:"id"`
	// Text — переведённый текст.
	Text string `json:"text"`
	// From — язык оригинала, определённый поставщиком. Клиент показывает его
	// рядом с кнопкой «оригинал»: без этого непонятно, с чего переводили.
	From string `json:"from"`
}

type Translator interface {
	// Translate переводит пачку сообщений на targetLang.
	//
	// Именно пачкой: при включении тумблера переводить надо сразу всю
	// видимую ленту, а запрос на каждое сообщение — это полсотни запросов
	// подряд и оплата за каждый.
	Translate(ctx context.Context, items []Item, targetLang string) ([]Result, error)
}

// NoopTranslator отказывает, но внятно.
//
// Не возвращает исходный текст под видом перевода: неверный перевод в
// переписке хуже, чем его отсутствие — человек примет чужие слова за свои.
type NoopTranslator struct{ Logger *slog.Logger }

func (t NoopTranslator) Translate(_ context.Context, items []Item, targetLang string) ([]Result, error) {
	logger := t.Logger
	if logger == nil {
		logger = slog.Default()
	}
	logger.Debug("перевод (заглушка)", "сообщений", len(items), "язык", targetLang)
	return nil, ErrNotConfigured
}
