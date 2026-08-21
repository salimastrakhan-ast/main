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
log "паузы GC (последние 20 записей игрового сервера)"
gc_log="$ROOT/dist/game/log/gc.log"
if [ -f "$gc_log" ]; then
  # Вытаскиваем длительности пауз и показываем максимум: всё, что выше
  # ~200 мс, игроки чувствуют как рывок.
  worst="$(grep -oE '[0-9]+[.,][0-9]+ms' "$gc_log" | tail -n 200 \
           | tr ',' '.' | sort -g | tail -n1)"
  if [ -n "$worst" ]; then
    ok "самая долгая пауза за последние записи: $worst"
    echo "    (нормально: < 50 мс. Больше 200 мс — игроки это чувствуют.)"
  else
    echo "    пока нечего показать"
  fi
else
  echo "    лога GC пока нет (сервер не запускался?)"
fi

echo
log "последние ошибки игрового сервера"
if [ -d "$ROOT/dist/game/log" ]; then
  grep -rhiE 'error|exception' "$ROOT/dist/game/log" 2>/dev/null | tail -5 \
    | sed 's/^/    /' || echo "    чисто"
else
  echo "    логов пока нет"
fi
echo
