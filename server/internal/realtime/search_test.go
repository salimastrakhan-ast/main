package realtime_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/salimastrakhan-ast/main/server/internal/auth"
	"github.com/salimastrakhan-ast/main/server/internal/domain"
	"github.com/salimastrakhan-ast/main/server/internal/store"
)

func userName(name string) store.UserPatch {
	return store.UserPatch{DisplayName: &name}
}

func contains(users []domain.User, id string) bool {
	for _, u := range users {
		if u.ID.String() == id {
			return true
		}
	}
	return false
}

// Поиск людей — то, с чего начинается любая переписка. Пока он ищет только
// по имени, человек, записавший знакомого в телефонную книгу, не находит его
// в мессенджере вовсе и справедливо считает, что всё сломано.
func TestПоискПоНомеруТелефона(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()

	phone := fmt.Sprintf("7905%07d", 1234567)
	target, _ := e.newUser(phone)
	if _, err := e.store.UpdateUser(ctx, target.ID, userName("Пётр Иванов")); err != nil {
		t.Fatalf("имя: %v", err)
	}

	// В адресной книге номер записан как угодно — с плюсом, через восьмёрку,
	// со скобками и пробелами. Все записи обязаны приводить к одному человеку.
	for _, written := range []string{
		"+7 905 123-45-67",
		"8 (905) 123-45-67",
		"79051234567",
		"+79051234567",
	} {
		normalized, err := auth.NormalizePhone(written)
		if err != nil {
			t.Fatalf("нормализация %q: %v", written, err)
		}
		found, err := e.store.SearchUsers(ctx, written, normalized, 10)
		if err != nil {
			t.Fatalf("поиск %q: %v", written, err)
		}
		if !contains(found, target.ID.String()) {
			t.Errorf("по записи %q человека не нашли", written)
		}
	}
}

func TestПоискПоЧастиНомераНеРаботает(t *testing.T) {
	// Намеренно: поиск по подстроке номера позволил бы перебрать базу и
	// выяснить, кто вообще зарегистрирован. Номер целиком человек и так
	// знает, раз вводит его.
	e := newEnv(t)
	ctx := context.Background()

	phone := fmt.Sprintf("7905%07d", 7654321)
	target, _ := e.newUser(phone)

	found, err := e.store.SearchUsers(ctx, "790576", "", 10)
	if err != nil {
		t.Fatalf("поиск: %v", err)
	}
	if contains(found, target.ID.String()) {
		t.Error("по куску номера человек нашёлся — базу можно перебрать")
	}
}

func TestПоискПоИмениРаботаетКакПрежде(t *testing.T) {
	e := newEnv(t)
	ctx := context.Background()

	target, _ := e.newUser(fmt.Sprintf("7905%07d", 2222222))
	if _, err := e.store.UpdateUser(ctx, target.ID, userName("Аня Соколова")); err != nil {
		t.Fatalf("имя: %v", err)
	}

	found, err := e.store.SearchUsers(ctx, "Соколов", "", 10)
	if err != nil {
		t.Fatalf("поиск: %v", err)
	}
	if !contains(found, target.ID.String()) {
		t.Error("по части имени человека не нашли")
	}
}
