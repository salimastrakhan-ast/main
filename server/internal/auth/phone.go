package auth

import (
	"errors"
	"strings"
)

var ErrBadPhone = errors.New("некорректный номер телефона")

// NormalizePhone приводит номер к E.164 без плюса: 79991234567.
//
// Российские номера люди пишут как угодно — 8 (999) 123-45-67, +7 999…,
// 9991234567. Все эти формы должны вести в один аккаунт, иначе один и тот же
// человек заведёт три.
func NormalizePhone(raw string) (string, error) {
	digits := make([]byte, 0, len(raw))
	for i := 0; i < len(raw); i++ {
		if c := raw[i]; c >= '0' && c <= '9' {
			digits = append(digits, c)
		}
	}
	s := string(digits)
	hasPlus := strings.HasPrefix(strings.TrimSpace(raw), "+")

	switch {
	case len(s) == 11 && s[0] == '8':
		// 8XXXXXXXXXX — российская запись через восьмёрку.
		s = "7" + s[1:]
	case len(s) == 10 && !hasPlus && (s[0] == '9'):
		// 9XXXXXXXXX — номер без кода страны, мобильные в РФ начинаются с 9.
		s = "7" + s
	}

	if len(s) < 7 || len(s) > 15 {
		return "", ErrBadPhone
	}
	if s[0] == '0' {
		return "", ErrBadPhone
	}
	// Российский номер обязан быть ровно 11 цифр: 7 плюс десять.
	if s[0] == '7' && len(s) != 11 {
		return "", ErrBadPhone
	}
	return s, nil
}
