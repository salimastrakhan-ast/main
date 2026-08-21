#!/bin/bash
# =============================================================================
#  Применяет к собранному серверу профиль рейтов, сетевые настройки и
#  адрес, который клиент получает для входа в мир.
#
#      ./scripts/configure.sh                     # профиль из .env
#      ./scripts/configure.sh --dry-run           # показать, что изменится
#      ./scripts/configure.sh --profile retail-x1
#
#  Скрипт идемпотентен: гоняй сколько угодно раз.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$ROOT/scripts/lib/detect.sh"

load_env "$ROOT/.env"

PROFILE="${L2_PROFILE:-x10-classic}"
DRY_RUN=0
EXTRA_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --profile) PROFILE="${2:?--profile требует имя}"; shift ;;
    --dry-run) DRY_RUN=1; EXTRA_ARGS+=("--dry-run") ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
  shift
done

PROFILE_FILE="$ROOT/config/profiles/$PROFILE.conf"
[ -f "$PROFILE_FILE" ] || die "нет профиля '$PROFILE'.
     Доступные: $(ls "$ROOT/config/profiles" | grep -v '^_' | grep '\.conf$' \
                   | sed 's/\.conf$//' | tr '\n' ' ')"

GAME_DIR="$(detect_game_dist "$ROOT/dist" || true)"
LOGIN_DIR="$(detect_login_dist "$ROOT/dist" || true)"
[ -n "$GAME_DIR" ] && [ -n "$LOGIN_DIR" ] \
  || die "сервер не собран — сначала ./scripts/build-server.sh"

require_cmd python3

apply() {
  python3 "$ROOT/scripts/apply-config.py" \
    --profile "$1" \
    --game-dir "$GAME_DIR" \
    --login-dir "$LOGIN_DIR" \
    "${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}"
}

# Сначала рейты, потом сеть: сетевой профиль применяется последним, чтобы
# его значения нельзя было случайно перебить профилем рейтов.
log "профиль рейтов: $PROFILE"
apply "$PROFILE_FILE" || die "профиль рейтов не применился"

log "сеть и база данных"
apply "$ROOT/config/profiles/_network.conf" || die "сетевой профиль не применился"

# --- Адрес для клиента -------------------------------------------------------
# Mobius задаёт его не ключом в .ini, а файлом ipconfig.xml: логин-сервер
# сопоставляет IP подключившегося клиента с подсетями и отдаёт тот адрес,
# по которому клиент реально достучится до игрового сервера.
#
# Тонкость Docker: клиент с этой же машины приходит через мост и выглядит
# как 172.x, поэтому эта подсеть тоже указывает на "внутренний" адрес.
write_ipconfig() {
  local ext="${L2_EXTERNAL_IP:-127.0.0.1}" int="${L2_INTERNAL_IP:-127.0.0.1}"

  if [ "$DRY_RUN" = "1" ]; then
    log "[dry-run] ipconfig.xml: внешний $ext, внутренний $int"
    return 0
  fi

  "$ROOT/scripts/write-ipconfig.sh" "$GAME_DIR" "$ext" "$int" \
    || die "не удалось записать ipconfig.xml"
  ok "ipconfig.xml: внешний адрес ${ext}, внутренний ${int}"
}

write_ipconfig

echo
ok "конфигурация применена"

if [ "${L2_EXTERNAL_IP:-127.0.0.1}" = "127.0.0.1" ]; then
  warn "L2_EXTERNAL_IP=127.0.0.1 — подключиться можно только с этой машины."
  warn "Для игры с других компьютеров укажи в .env реальный адрес"
  warn "и повтори:  make configure && make restart"
fi
