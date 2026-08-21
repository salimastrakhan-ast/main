#!/bin/bash
# =============================================================================
#  Наполняет базы схемой L2J из дампов, лежащих внутри собранной сборки.
#
#  ВНИМАНИЕ: операция разрушающая. Дампы L2J начинаются с DROP TABLE,
#  то есть персонажи, аккаунты и весь прогресс будут стёрты.
#  Запускается один раз при установке.
#
#      ./scripts/db-setup.sh          # с подтверждением
#      ./scripts/db-setup.sh --yes    # без вопросов (для автоматизации)
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
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
  shift
done

COMPOSE=(docker compose --project-directory "$ROOT")

# --- База должна быть поднята ------------------------------------------------
if ! "${COMPOSE[@]}" ps --status running --services 2>/dev/null | grep -qx db; then
  log "поднимаю контейнер базы"
  "${COMPOSE[@]}" up -d db
fi

log "жду готовности MariaDB"
for _ in $(seq 1 60); do
  if "${COMPOSE[@]}" exec -T db mariadb-admin ping \
       -uroot -p"$DB_ROOT_PASSWORD" --silent >/dev/null 2>&1; then
    break
  fi
  sleep 2
done
"${COMPOSE[@]}" exec -T db mariadb-admin ping -uroot -p"$DB_ROOT_PASSWORD" --silent \
  >/dev/null 2>&1 || die "база не отвечает. Смотри: docker compose logs db"
ok "база отвечает"

# --- Ищем дампы --------------------------------------------------------------
GAME_SQL="$(detect_sql_dir "$ROOT/dist/game" game || true)"
LOGIN_SQL="$(detect_sql_dir "$ROOT/dist/login" login || true)"

# У части сборок дампы лежат общей кучей рядом со сборкой, а не внутри неё.
[ -z "$GAME_SQL" ]  && GAME_SQL="$(detect_sql_dir "$ROOT/dist" game || true)"
[ -z "$LOGIN_SQL" ] && LOGIN_SQL="$(detect_sql_dir "$ROOT/dist" login || true)"

[ -n "$GAME_SQL" ]  || die "не нашёл .sql для игрового сервера в ./dist.
     Обычно это dist/game/sql/game. Покажи, где они: ls -R dist | grep -i sql"
[ -n "$LOGIN_SQL" ] || die "не нашёл .sql для логин-сервера в ./dist"

game_count=$(find "$GAME_SQL" -maxdepth 1 -name '*.sql' | wc -l)
login_count=$(find "$LOGIN_SQL" -maxdepth 1 -name '*.sql' | wc -l)
ok "дампы игрового сервера: $GAME_SQL ($game_count файлов)"
ok "дампы логин-сервера:    $LOGIN_SQL ($login_count файлов)"

echo
warn "Импорт УДАЛИТ существующие таблицы в базах $DB_GAME_NAME и $DB_LOGIN_NAME"
warn "вместе со всеми персонажами и аккаунтами."
confirm "Точно продолжаем?" || die "отменено"

# --- Импорт ------------------------------------------------------------------
import_dir() {
  local dir="$1" db="$2" label="$3"
  local total done_count=0 failed=0
  total=$(find "$dir" -maxdepth 1 -name '*.sql' | wc -l)

  log "импортирую $label -> $db ($total файлов)"
  local file name
  while IFS= read -r file; do
    name="$(basename "$file")"
    if "${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" \
         --default-character-set=utf8mb4 "$db" < "$file" 2>/tmp/l2-sql-err; then
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

  if [ "$failed" -gt 0 ]; then
    die "$failed файлов не импортировалось. База в неконсистентном состоянии —
     чини причину и запускай скрипт заново."
  fi
  ok "$label: импортировано $done_count файлов"
}

import_dir "$LOGIN_SQL" "$DB_LOGIN_NAME" "логин-сервер"
import_dir "$GAME_SQL"  "$DB_GAME_NAME"  "игровой сервер"

# --- Регистрация игрового сервера в списке -----------------------------------
# Строка в gameservers связывает hexid игрового сервера с номером в списке.
# AcceptNewGameServer=True позволяет серверу зарегистрироваться самому при
# первом запуске, поэтому здесь только проверяем, что таблица на месте.
if "${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" \
     -e "SELECT 1 FROM gameservers LIMIT 1" "$DB_LOGIN_NAME" >/dev/null 2>&1; then
  ok "таблица gameservers на месте — сервер зарегистрируется сам при старте"
else
  warn "таблицы gameservers нет. Регистрация сервера может потребовать
       ручного шага — см. docs/TROUBLESHOOTING.md"
fi

echo
ok "базы готовы"
log "дальше:  make up   — и заходи в игру, аккаунт создастся при первом входе"
