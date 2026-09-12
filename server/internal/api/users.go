package api

import (
	"context"

	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/media"
)

// publicUsers убирает телефоны из профилей и подписывает ссылки на аватары.
//
// Номер видит только владелец аккаунта. Исключение — ответ на синхронизацию
// контактов: там номера пришли от самого клиента, и по ним он сшивает
// найденных людей со своей адресной книгой.
//
// Подпись аватара делается здесь же не для красоты: ссылка живёт шесть
// часов, и её нельзя подписать заранее и сохранить. Пропустить вызов в одном
// месте из пяти — значит потерять аватары ровно там, и узнать об этом от
// человека, а не от теста.
func (s *Server) publicUsers(ctx context.Context, users []domain.User) []domain.User {
	out := make([]domain.User, len(users))
	for i, u := range users {
		out[i] = u.Public()
	}
	return media.ResolveUsers(ctx, s.media, out)
}

// withAvatar подписывает аватар одного профиля, телефон оставляя на месте:
// так профиль уходит своему же владельцу.
func (s *Server) withAvatar(ctx context.Context, user domain.User) domain.User {
	return media.ResolveUser(ctx, s.media, user)
}

// usersWithPhones — профили с номерами: только в ответе на синхронизацию
// контактов, где номера и так пришли от клиента.
func (s *Server) usersWithPhones(ctx context.Context, users []domain.User) []domain.User {
	return media.ResolveUsers(ctx, s.media, users)
}
