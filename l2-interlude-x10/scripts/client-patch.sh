#!/bin/bash
# =============================================================================
#  Собирает патч для клиента игры на другой машине (виртуалка, ноутбук друга).
#
#      ./scripts/client-patch.sh                 # адрес из .env
#      ./scripts/client-patch.sh 203.0.113.10    # адрес явно
#      ./scripts/client-patch.sh --out /tmp      # куда положить архив
#
#  На выходе — zip с bat-файлом: игрок распаковывает его в папку клиента,
#  запускает, и клиент начинает ходить на наш сервер. Файлы клиента архив
#  не содержит: клиент у игрока свой.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

TEMPLATES="$ROOT/scripts/templates/client-patch"
OUT_DIR="$ROOT/dist/patch"
ADDR=""

# .env читаем, только если он есть: адрес можно передать аргументом,
# и тогда генератор работает даже на машине без настроенного стенда.
[ -f "$ROOT/.env" ] && load_env "$ROOT/.env"

while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT_DIR="${2:?--out требует каталог}"; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) die "неизвестный аргумент: $1" ;;
    *) ADDR="$1" ;;
  esac
  shift
done

ADDR="${ADDR:-${L2_EXTERNAL_IP:-}}"
[ -n "$ADDR" ] || die "не задан адрес сервера.
     Укажи явно:  ./scripts/client-patch.sh 192.168.0.133
     или заполни L2_EXTERNAL_IP в .env"

LOGIN="${LOGIN_PORT:-2106}"
GAME="${GAME_PORT:-7777}"

require_cmd zip "Установи:  sudo apt install zip"

# 127.0.0.1 в патче — самая частая причина вечного "Connecting...":
# клиент на другой машине пойдёт искать сервер сам в себе.
case "$ADDR" in
  127.*|localhost)
    warn "адрес $ADDR годится только для клиента на этой же машине.
     Для виртуалки нужен адрес, видимый снаружи: поправь L2_EXTERNAL_IP
     в .env, сделай 'make configure && make restart' и собери патч заново." ;;
esac

# Экранируем то, что sed трактует как спецсимволы в правой части замены.
sed_safe() { printf '%s' "$1" | sed -e 's/[&|\]/\\&/g'; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

for file in setup-client.bat patch.ps1 README.txt; do
  [ -f "$TEMPLATES/$file" ] || die "нет шаблона $TEMPLATES/$file"
  # Windows читает эти файлы: переводы строк должны быть CRLF, иначе
  # cmd.exe спотыкается на метках, а Блокнот показывает всё одной строкой.
  sed -e "s|@ADDR@|$(sed_safe "$ADDR")|g" \
      -e "s|@LOGIN_PORT@|$(sed_safe "$LOGIN")|g" \
      -e "s|@GAME_PORT@|$(sed_safe "$GAME")|g" \
      "$TEMPLATES/$file" | sed -e 's/\r$//' -e 's/$/\r/' > "$STAGE/$file"
done

# BOM: без него Windows PowerShell 5.1 считает .ps1 однобайтовым, а Блокнот
# так же читает .txt — русский текст превращается в кракозябры. В .bat BOM,
# наоборот, недопустим (cmd.exe подавится первой строкой): там chcp.
for file in README.txt patch.ps1; do
  printf '\xef\xbb\xbf' | cat - "$STAGE/$file" > "$STAGE/$file.bom"
  mv "$STAGE/$file.bom" "$STAGE/$file"
done

mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/l2-patch-$ADDR.zip"
rm -f "$OUT"
(cd "$STAGE" && zip -X -q "$OUT" setup-client.bat patch.ps1 README.txt)

log "патч для клиента"
ok "адрес сервера: $ADDR (логин $LOGIN, игра $GAME)"
ok "архив: $OUT ($(du -h "$OUT" | cut -f1))"
printf '     Скинь архив на машину с клиентом, распакуй в папку клиента\n'
printf '     (там, где лежит system) и запусти setup-client.bat.\n'
