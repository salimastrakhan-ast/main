package api

import "github.com/salimastrakhan-ast/main/server/internal/domain"

// publicUsers убирает телефоны из профилей.
//
// Номер видит только владелец аккаунта. Исключение — ответ на синхронизацию
// контактов: там номера пришли от самого клиента, и по ним он сшивает
// найденных людей со своей адресной книгой.
func publicUsers(users []domain.User) []domain.User {
	out := make([]domain.User, len(users))
	for i, u := range users {
		out[i] = u.Public()
	}
	return out
}
