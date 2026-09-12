// Package migrations содержит SQL-миграции, вшитые в бинарник.
//
// Отдельного инструмента вроде golang-migrate тут нет намеренно: миграции
// применяются при старте сервера, а весь код умещается в store.Migrate.
package migrations

import "embed"

//go:embed *.sql
var FS embed.FS
