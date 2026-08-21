#!/bin/bash
# =============================================================================
#  Резервная копия обеих баз.
#
#      ./scripts/backup.sh              # снять копию
#      ./scripts/backup.sh --restore backups/l2-20260101-030000.sql.gz
#
#  Делать копии на живом сервере безопасно: --single-transaction снимает
#  консистентный снимок InnoDB, не блокируя игроков.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

load_env "$ROOT/.env"
require_cmd docker

BACKUP_DIR="$ROOT/backups"
KEEP="${BACKUP_KEEP:-14}"
COMPOSE=(docker compose --project-directory "$ROOT")

if [ "${1:-}" = "--restore" ]; then
  file="${2:?укажи файл копии}"
  [ -f "$file" ] || die "нет файла $file"

  warn "Восстановление ПЕРЕЗАПИШЕТ текущие базы целиком."
  warn "Всё, что произошло на сервере после снятия копии, будет потеряно."
  confirm "Продолжаем?" || die "отменено"

  log "останавливаю игровой и логин-сервер"
  "${COMPOSE[@]}" stop game login >/dev/null

  log "восстанавливаю из $file"
  gunzip -c "$file" | "${COMPOSE[@]}" exec -T db \
    mariadb -uroot -p"$DB_ROOT_PASSWORD" --default-character-set=utf8mb4 \
    || die "восстановление не удалось"

  ok "готово, поднимаю сервер"
  "${COMPOSE[@]}" start login game >/dev/null
  exit 0
fi

mkdir -p "$BACKUP_DIR"
stamp="$(date +%Y%m%d-%H%M%S)"
target="$BACKUP_DIR/l2-$stamp.sql.gz"

log "снимаю копию баз $DB_GAME_NAME и $DB_LOGIN_NAME"
"${COMPOSE[@]}" exec -T db mariadb-dump \
    -uroot -p"$DB_ROOT_PASSWORD" \
    --single-transaction --quick --routines --events \
    --default-character-set=utf8mb4 \
    --databases "$DB_GAME_NAME" "$DB_LOGIN_NAME" \
  | gzip -6 > "$target" \
  || { rm -f "$target"; die "не удалось снять копию"; }

size="$(du -h "$target" | cut -f1)"
ok "готово: $target ($size)"

# Чистим старые копии.
mapfile -t old < <(find "$BACKUP_DIR" -maxdepth 1 -name 'l2-*.sql.gz' \
                     -printf '%T@ %p\n' | sort -rn | tail -n +$((KEEP + 1)) | cut -d' ' -f2-)
if [ "${#old[@]}" -gt 0 ]; then
  log "удаляю копии старше последних $KEEP штук (${#old[@]})"
  printf '%s\n' "${old[@]}" | xargs -r rm -f
fi
