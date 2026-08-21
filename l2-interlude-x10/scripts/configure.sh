#!/bin/bash
# =============================================================================
#  Применяет к собранному серверу сетевые настройки и профиль рейтов.
#
#      ./scripts/configure.sh                     # профиль из .env
#      ./scripts/configure.sh --dry-run           # показать, что изменится
#      ./scripts/configure.sh --profile retail-x1 # другой профиль
#
#  Скрипт можно гонять сколько угодно раз: он идемпотентен.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

load_env "$ROOT/.env"

PROFILE="${L2_PROFILE:-x10-classic}"
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile требует имя}"; shift ;;
    --dry-run) EXTRA_ARGS+=("--dry-run") ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
  shift
done

PROFILE_FILE="$ROOT/config/profiles/$PROFILE.conf"
[ -f "$PROFILE_FILE" ] || die "нет профиля '$PROFILE'.
     Доступные: $(ls "$ROOT/config/profiles" | grep -v '^_' | sed 's/\.conf$//' | tr '\n' ' ')"

[ -d "$ROOT/dist/game" ] || die "сервер не собран — сначала ./scripts/build-server.sh"

require_cmd python3

apply() {
  python3 "$ROOT/scripts/apply-config.py" \
    --profile "$1" \
    --game-dir "$ROOT/dist/game" \
    --login-dir "$ROOT/dist/login" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
}

# Порядок важен: сначала рейты, потом сеть. Сетевой профиль применяется
# последним, чтобы его значения нельзя было случайно перебить профилем рейтов.
log "профиль рейтов: $PROFILE"
apply "$PROFILE_FILE" || die "профиль рейтов не применился"

log "сеть и база данных"
apply "$ROOT/config/profiles/_network.conf" || die "сетевой профиль не применился"

echo
ok "конфигурация применена"

if [ "${L2_EXTERNAL_IP:-127.0.0.1}" = "127.0.0.1" ]; then
  warn "L2_EXTERNAL_IP=127.0.0.1 — подключиться сможешь только с этой машины."
  warn "Для игры с других компьютеров укажи в .env реальный IP и повтори configure.sh"
fi
