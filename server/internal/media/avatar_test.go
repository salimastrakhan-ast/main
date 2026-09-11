package media_test

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"testing"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/media"
)

// countingResolver выдаёт каждый раз новую ссылку — так ведёт себя настоящее
// хранилище: подпись включает момент выдачи и живёт шесть часов.
type countingResolver struct {
	calls int
	fail  bool
}

func (r *countingResolver) Resolve(_ context.Context, a []domain.Attachment) []domain.Attachment {
	return a
}

func (r *countingResolver) Link(_ context.Context, key string) (string, error) {
	if r.fail {
		return "", errors.New("хранилище недоступно")
	}
	r.calls++
	return fmt.Sprintf("https://example/%s?sig=%d", key, r.calls), nil
}

func TestАватарПодписываетсяЗаново(t *testing.T) {
	// Главная опасность аватара: если ссылку подписать один раз и сохранить
	// в базе, она умрёт через шесть часов — у всех сразу и без ошибок в
	// логах. Поэтому в базе лежит ключ, а ссылка выдаётся при каждом чтении.
	r := &countingResolver{}
	ctx := context.Background()

	first := media.ResolveUser(ctx, r, domain.User{AvatarKey: "u/1.jpg"})
	second := media.ResolveUser(ctx, r, domain.User{AvatarKey: "u/1.jpg"})

	if first.AvatarURL == "" || second.AvatarURL == "" {
		t.Fatal("ссылка на аватар не проставлена")
	}
	if first.AvatarURL == second.AvatarURL {
		t.Errorf("ссылка одна и та же (%s) — значит, она сохраняется, а не подписывается заново",
			first.AvatarURL)
	}
}

func TestБезАватараПрофильНеТрогаем(t *testing.T) {
	r := &countingResolver{}
	user := media.ResolveUser(context.Background(), r, domain.User{DisplayName: "Аня"})

	if user.AvatarURL != "" {
		t.Errorf("пустому ключу выдали ссылку %q", user.AvatarURL)
	}
	if r.calls != 0 {
		t.Errorf("хранилище дёрнули %d раз без единого аватара", r.calls)
	}
}

func TestОтказХранилищаНеЛомаетПрофиль(t *testing.T) {
	// Хранилище может не ответить. Профиль при этом обязан дойти: клиент
	// покажет буквы вместо картинки, а не пустую строку списка.
	r := &countingResolver{fail: true}
	user := media.ResolveUser(context.Background(), r,
		domain.User{DisplayName: "Аня", AvatarKey: "u/1.jpg"})

	if user.DisplayName != "Аня" {
		t.Error("профиль потерялся из-за недоступного хранилища")
	}
	if user.AvatarURL != "" {
		t.Errorf("при отказе выдали ссылку %q", user.AvatarURL)
	}
}

func TestКлючНеУезжаетКлиенту(t *testing.T) {
	// Ключ объекта — внутреннее имя файла в хранилище. Клиенту он не нужен,
	// а по нему видно устройство бакета: чей файл и сколько их.
	user := domain.User{DisplayName: "Аня", AvatarKey: "8f3e/secret.jpg"}

	encoded, err := json.Marshal(user)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(encoded), "secret.jpg") {
		t.Errorf("ключ попал в ответ клиенту: %s", encoded)
	}
}
