package auth

import "testing"

func TestNormalizePhone(t *testing.T) {
	// Все российские записи одного номера обязаны сойтись в одну строку,
	// иначе человек заведёт несколько аккаунтов на один телефон.
	same := []string{
		"+7 999 123-45-67",
		"8 (999) 123-45-67",
		"89991234567",
		"79991234567",
		"9991234567",
		"+7(999)123 45 67",
	}
	for _, raw := range same {
		got, err := NormalizePhone(raw)
		if err != nil {
			t.Fatalf("NormalizePhone(%q) вернул ошибку: %v", raw, err)
		}
		if got != "79991234567" {
			t.Errorf("NormalizePhone(%q) = %q, ожидалось 79991234567", raw, got)
		}
	}

	bad := []string{"", "12", "abc", "+7999123456", "+799912345678", "0123456789"}
	for _, raw := range bad {
		if got, err := NormalizePhone(raw); err == nil {
			t.Errorf("NormalizePhone(%q) = %q, ожидалась ошибка", raw, got)
		}
	}

	// Иностранные номера проходят как есть, лишь бы укладывались в E.164.
	foreign := map[string]string{
		"+1 202 555 0143": "12025550143",
		"+380671234567":   "380671234567",
	}
	for raw, want := range foreign {
		got, err := NormalizePhone(raw)
		if err != nil {
			t.Fatalf("NormalizePhone(%q) вернул ошибку: %v", raw, err)
		}
		if got != want {
			t.Errorf("NormalizePhone(%q) = %q, ожидалось %q", raw, got, want)
		}
	}
}
