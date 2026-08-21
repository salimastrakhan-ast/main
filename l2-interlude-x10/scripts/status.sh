#!/bin/bash
# =============================================================================
#  Состояние сервера одним взглядом: контейнеры, порты, онлайн, память, GC.
#  Первое, что стоит запустить, когда игроки пишут "лагает".
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

load_env "$ROOT/.env"
COMPOSE=(docker compose -f "$ROOT/docker-compose.yml" --project-directory "$ROOT")

echo
log "контейнеры"
"${COMPOSE[@]}" ps --format 'table {{.Service}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null \
  | sed 's/^/    /' || warn "docker compose недоступен"

echo
log "порты"
for entry in "логин:${LOGIN_PORT:-2106}" "игра:${GAME_PORT:-7777}"; do
  name="${entry%%:*}"; port="${entry##*:}"
  if (echo >"/dev/tcp/127.0.0.1/$port") >/dev/null 2>&1; then
    ok "$name ($port) слушается"
  else
    warn "$name ($port) НЕ отвечает"
  fi
done

echo
log "онлайн"
online="$("${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" -N -B \
  "${DB_NAME:-l2jmobius}" -e "SELECT COUNT(*) FROM characters WHERE online > 0;" 2>/dev/null | tr -d '\r')"
if [ -n "$online" ]; then
  ok "персонажей в игре: $online"
else
  warn "не удалось спросить базу"
fi

echo
log "ресурсы"
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' \
  l2-game l2-login l2-db 2>/dev/null | sed 's/^/    /' \
  || warn "статистика недоступна"

echo
log "паузы GC (игровой сервер)"
gc_log="$ROOT/dist/game/log/gc.log"
if [ -f "$gc_log" ]; then
  # Считаем ТОЛЬКО строки с Pause: у ZGC в лог попадает ещё и длительность
  # конкурентных циклов, во время которых сервер продолжает работать.
  # Если брать любое число с "ms", получаются пугающие секунды на ровном месте.
  worst="$(grep -h 'Pause' "$gc_log" 2>/dev/null | tail -n 500 \
           | grep -oE '[0-9]+([.,][0-9]+)?ms' | tr ',' '.' \
           | sed 's/ms$//' | sort -g | tail -n1)"
  pauses="$(grep -hc 'Pause' "$gc_log" 2>/dev/null || echo 0)"

  if [ -n "$worst" ]; then
    ok "самая долгая пауза из последних: ${worst} мс (всего пауз в логе: $pauses)"
    echo "    (нормально: ZGC — доли миллисекунды, G1 — до 50 мс."
    echo "     Больше 200 мс игроки чувствуют как рывок.)"
  else
    echo "    пауз ещё не было — сервер только запустился"
  fi

  cycles="$(grep -hc 'Garbage Collection' "$gc_log" 2>/dev/null || echo 0)"
  echo "    циклов сборки мусора: $cycles"
else
  echo "    лога GC пока нет (сервер не запускался?)"
fi

echo
log "последние ошибки игрового сервера"
if [ -d "$ROOT/dist/game/log" ]; then
  # Ищем уровни логирования как отдельные слова и исключения, иначе в выборку
  # попадают безобидные строки вроде "Loaded 462 spawns, 0 errors".
  found="$(grep -rhE '\b(ERROR|SEVERE|WARNING)\b|Exception' "$ROOT/dist/game/log" 2>/dev/null \
           | grep -vE '\b0 errors\b' | tail -5)"
  if [ -n "$found" ]; then
    printf '%s\n' "$found" | cut -c1-160 | sed 's/^/    /'
  else
    echo "    чисто"
  fi
else
  echo "    логов пока нет"
fi
echo
