#!/bin/bash
# =============================================================================
#  Наполняет базу схемой из дампов, лежащих внутри собранной сборки.
#
#  У Mobius Interlude логин-сервер и игровой работают с ОДНОЙ базой, поэтому
#  дампы db_installer/sql/login и db_installer/sql/game заливаются в неё же.
#
#  ВНИМАНИЕ: операция разрушающая — дампы начинаются с DROP TABLE, то есть
#  персонажи, аккаунты и весь прогресс будут стёрты. Запускается при установке.
#
#      ./scripts/db-setup.sh          # с подтверждением
#      ./scripts/db-setup.sh --yes    # без вопросов
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$ROOT/scripts/lib/detect.sh"

load_env "$ROOT/.env"
require_cmd docker

while [ $# -gt 0 ]; do
  case "$1" in
    --yes|-y) export ASSUME_YES=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
  shift
done

COMPOSE=(docker compose -f "$ROOT/docker-compose.yml" --project-directory "$ROOT")
DB="${DB_NAME:-l2jmobius}"

# --- База должна быть поднята ------------------------------------------------
if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx db; then
  log "поднимаю контейнер базы"
  "${COMPOSE[@]}" up -d db
fi

log "жду готовности MariaDB"
for _ in $(seq 1 60); do
  "${COMPOSE[@]}" exec -T db mariadb-admin ping -uroot -p"$DB_ROOT_PASSWORD" --silent \
    >/dev/null 2>&1 && break
  sleep 2
done
"${COMPOSE[@]}" exec -T db mariadb-admin ping -uroot -p"$DB_ROOT_PASSWORD" --silent \
  >/dev/null 2>&1 || die "база не отвечает. Смотри: docker compose logs db"
ok "база отвечает"

# --- Ищем дампы --------------------------------------------------------------
LOGIN_SQL="$(detect_sql_dir "$ROOT/dist" login || true)"
GAME_SQL="$(detect_sql_dir "$ROOT/dist" game || true)"

[ -n "$LOGIN_SQL" ] || die "не нашёл .sql логин-сервера.
     Обычно это dist/db_installer/sql/login. Проверь:  ls -R dist | grep -i sql"
[ -n "$GAME_SQL" ] || die "не нашёл .sql игрового сервера в ./dist"

login_count=$(find "$LOGIN_SQL" -maxdepth 1 -name '*.sql' | wc -l)
game_count=$(find "$GAME_SQL" -maxdepth 1 -name '*.sql' | wc -l)
ok "дампы логин-сервера:    ${LOGIN_SQL#$ROOT/} ($login_count файлов)"
ok "дампы игрового сервера: ${GAME_SQL#$ROOT/} ($game_count файлов)"

echo
warn "Импорт УДАЛИТ существующие таблицы в базе '$DB'"
warn "вместе со всеми персонажами и аккаунтами."
confirm "Точно продолжаем?" || die "отменено"

# --- Импорт ------------------------------------------------------------------
import_dir() {
  local dir="$1" label="$2"
  local total done_count=0 failed=0 file name
  total=$(find "$dir" -maxdepth 1 -name '*.sql' | wc -l)

  log "импортирую $label -> $DB ($total файлов)"
  while IFS= read -r file; do
    name="$(basename "$file")"
    if "${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" \
         --default-character-set=utf8mb4 "$DB" < "$file" 2>/tmp/l2-sql-err; then
      done_count=$((done_count + 1))
      printf '\r    %s/%s  %-45s' "$done_count" "$total" "$name"
    else
      failed=$((failed + 1))
      printf '\n'
      warn "не импортировался: $name"
      sed 's/^/        /' /tmp/l2-sql-err | head -3 >&2
    fi
  done < <(find "$dir" -maxdepth 1 -name '*.sql' | sort)
  printf '\n'
  rm -f /tmp/l2-sql-err

  [ "$failed" -gt 0 ] && die "$failed файлов не импортировалось — база в неполном
     состоянии. Устрани причину и запусти скрипт заново."
  ok "$label: импортировано $done_count файлов"
}

import_dir "$LOGIN_SQL" "логин-сервер"
import_dir "$GAME_SQL"  "игровой сервер"

# --- Проверка ----------------------------------------------------------------
tables="$("${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" -N -B \
  -e "SELECT COUNT(*) FROM information_schema.TABLES WHERE TABLE_SCHEMA='$DB';" \
  2>/dev/null | tr -d '\r')"
ok "таблиц в базе: ${tables:-?}"

if "${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" \
     -e "SELECT 1 FROM gameservers LIMIT 1" "$DB" >/dev/null 2>&1; then
  ok "таблица gameservers на месте — сервер зарегистрируется сам при старте"
else
  warn "таблицы gameservers нет: регистрация может потребовать ручного шага,
       см. docs/TROUBLESHOOTING.md"
fi

echo
ok "база готова"
log "дальше:  make up   — аккаунт создастся при первом входе в игру"
