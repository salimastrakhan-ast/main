# Общие функции. Подключается через source, самостоятельно не запускается.
# shellcheck shell=bash

C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
C_BLUE=$'\033[34m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'

log()  { printf '%s==>%s %s\n' "$C_BLUE" "$C_OFF" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$*"; }
warn() { printf '%s  !!%s %s\n' "$C_YELLOW" "$C_OFF" "$*" >&2; }
die()  { printf '%sОШИБКА:%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

require_cmd() {
  local cmd="$1" hint="${2:-}"
  command -v "$cmd" >/dev/null 2>&1 \
    || die "не найдена команда '$cmd'.${hint:+ $hint}"
}

# Загружает .env в окружение. Пустые строки и комментарии игнорируются,
# значения не подвергаются повторному раскрытию (никаких сюрпризов с $).
load_env() {
  local env_file="${1:?}"
  [ -f "$env_file" ] || die "нет файла $env_file — скопируй .env.example в .env"

  local line key value
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"
    case "$line" in ''|'#'*) continue ;; esac
    [[ "$line" != *=* ]] && continue

    key="${line%%=*}"
    value="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    value="${value%"${value##*[![:space:]]}"}"
    # Снимаем обрамляющие кавычки, если есть.
    if [[ "$value" == \"*\" || "$value" == \'*\' ]]; then
      value="${value:1:${#value}-2}"
    fi
    export "$key=$value"
  done < "$env_file"
}

confirm() {
  local prompt="$1"
  if [ "${ASSUME_YES:-0}" = "1" ]; then return 0; fi
  read -r -p "$prompt [y/N] " answer
  [[ "$answer" =~ ^[YyДд]$ ]]
}
