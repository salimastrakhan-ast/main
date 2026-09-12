package store

import (
	"errors"

	"github.com/jackc/pgx/v5/pgconn"
)

// Коды ошибок Postgres, которые различает бизнес-логика.
const (
	pgUniqueViolation     = "23505"
	pgForeignKeyViolation = "23503"
)

func pgCode(err error) string {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code
	}
	return ""
}

func isUniqueViolation(err error) bool { return pgCode(err) == pgUniqueViolation }

func isForeignKeyViolation(err error) bool { return pgCode(err) == pgForeignKeyViolation }
