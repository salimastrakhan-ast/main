#!/bin/bash
# =============================================================================
#  Настройка и запуск клиента игры.
#
#      ./scripts/client.sh setup ~/l2-client   # прописать адрес сервера
#      ./scripts/client.sh run                 # запустить через Wine
#
#  Путь запоминается в .env (L2_CLIENT_DIR), поэтому второй раз указывать
#  его не нужно.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

load_env "$ROOT/.env"

WINE_PREFIX="${L2_WINE_PREFIX:-$HOME/.wine-l2}"

# Каталог клиента: аргумент, затем .env. Принимаем и корень клиента,
# и папку system внутри него — люди указывают то одно, то другое.
resolve_client_dir() {
  local candidate="${1:-${L2_CLIENT_DIR:-}}"
  [ -n "$candidate" ] || return 1
  candidate="${candidate%/}"

  if [ -f "$candidate/system/l2.exe" ] || [ -f "$candidate/system/L2.exe" ]; then
    printf '%s\n' "$candidate"; return 0
  fi
  if [ -f "$candidate/l2.exe" ] || [ -f "$candidate/L2.exe" ]; then
    printf '%s\n' "$(dirname "$candidate")"; return 0
  fi
  return 1
}

client_exe() {
  local system="$1/system"
  [ -f "$system/l2.exe" ] && { printf 'l2.exe\n'; return 0; }
  [ -f "$system/L2.exe" ] && { printf 'L2.exe\n'; return 0; }
  return 1
}

remember_client_dir() {
  local dir="$1"
  if grep -q '^L2_CLIENT_DIR=' "$ROOT/.env" 2>/dev/null; then
    sed -i "s|^L2_CLIENT_DIR=.*|L2_CLIENT_DIR=$dir|" "$ROOT/.env"
  else
    printf '\n# Каталог клиента игры (заполняется scripts/client.sh)\nL2_CLIENT_DIR=%s\n' \
      "$dir" >> "$ROOT/.env"
  fi
}

cmd="${1:-help}"
case "$cmd" in
  setup)
    dir="$(resolve_client_dir "${2:-}")" || die "не похоже на клиент Lineage 2.
     Укажи каталог, внутри которого лежит system/l2.exe:
       ./scripts/client.sh setup ~/l2-client"

    ini="$dir/system/l2.ini"
    [ -f "$ini" ] || die "нет файла $ini — клиент распакован не полностью?"

    addr="${L2_EXTERNAL_IP:-127.0.0.1}"
    log "клиент: $dir"
    python3 "$ROOT/scripts/set-client-addr.py" "$ini" "$addr" \
      || die "не удалось прописать адрес"
    remember_client_dir "$dir"
    ok "готово. Запуск:  ./scripts/client.sh run"
    ;;

  run)
    dir="$(resolve_client_dir "${2:-}")" || die "каталог клиента неизвестен.
     Сначала:  ./scripts/client.sh setup <каталог клиента>"
    exe="$(client_exe "$dir")" || die "в $dir/system нет l2.exe"

    require_cmd wine "Установи:  sudo apt install wine64 wine32"

    # Клиент 32-битный и требует запуска именно из каталога system:
    # относительные пути к ресурсам считаются от рабочего каталога.
    log "запускаю $exe (префикс $WINE_PREFIX)"
    cd "$dir/system"
    WINEPREFIX="$WINE_PREFIX" WINEDEBUG="${WINEDEBUG:--all}" wine "$exe"
    ;;

  *)
    sed -n '2,12p' "$0"
    ;;
esac
