#!/bin/bash
# =============================================================================
#  Тесты настройки клиента: правка system/l2.ini и разбор пути к клиенту.
#
#  Ошибка здесь выглядит как "сервер не работает": клиент молча стучится
#  не туда. Поэтому проверяем все варианты, которые встречаются в реальных
#  сборках клиента — с ключом, без ключа, без секции, с CRLF.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
PATCH="$ROOT/scripts/set-client-addr.py"

PASS=0; FAIL=0; WORK=""
setup()    { WORK="$(mktemp -d)"; }
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mOK\033[0m   %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m %s\n       ожидалось: [%s]\n       получено:  [%s]\n' \
      "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

addr_of() { grep -iE '^\s*ServerAddr\s*=' "$1" | head -n1 | sed 's/^[^=]*=\s*//' | tr -d '\r'; }

# Готовит макет клиента: system/l2.exe + system/l2.ini с заданным содержимым.
make_client() {
  local dir="$1"; shift
  mkdir -p "$dir/system"
  : > "$dir/system/l2.exe"
  printf '%s' "$1" > "$dir/system/l2.ini"
}

echo "=== Тесты настройки клиента ==="

# --- Ключ уже есть -----------------------------------------------------------
setup
make_client "$WORK/client" '[Server]
ServerAddr=127.0.0.1
ServerPort=2106
'
python3 "$PATCH" "$WORK/client/system/l2.ini" 192.168.0.133 >/dev/null
check "существующий ServerAddr заменён" "192.168.0.133" \
  "$(addr_of "$WORK/client/system/l2.ini")"
check "соседние ключи не тронуты" "1" \
  "$(grep -c '^ServerPort=2106' "$WORK/client/system/l2.ini")"
check "создана резервная копия" "yes" \
  "$([ -f "$WORK/client/system/l2.ini.orig" ] && echo yes || echo no)"
check "в копии прежний адрес" "127.0.0.1" \
  "$(addr_of "$WORK/client/system/l2.ini.orig")"

# Повторный прогон не должен плодить дубли.
python3 "$PATCH" "$WORK/client/system/l2.ini" 192.168.0.133 >/dev/null
check "повторный прогон не дублирует ключ" "1" \
  "$(grep -ci '^ServerAddr=' "$WORK/client/system/l2.ini")"
teardown

# --- Секция есть, ключа нет --------------------------------------------------
setup
make_client "$WORK/client" '[Server]
ServerPort=2106
'
python3 "$PATCH" "$WORK/client/system/l2.ini" 10.0.0.5 >/dev/null
check "ключ добавлен в существующую секцию" "10.0.0.5" \
  "$(addr_of "$WORK/client/system/l2.ini")"
check "секция не продублирована" "1" \
  "$(grep -ci '^\[Server\]' "$WORK/client/system/l2.ini")"
teardown

# --- Нет ни ключа, ни секции -------------------------------------------------
setup
make_client "$WORK/client" '[Options]
Foo=1
'
python3 "$PATCH" "$WORK/client/system/l2.ini" l2.example.com >/dev/null
check "секция [Server] создана" "1" \
  "$(grep -ci '^\[Server\]' "$WORK/client/system/l2.ini")"
check "адрес записан" "l2.example.com" "$(addr_of "$WORK/client/system/l2.ini")"
check "прежняя секция цела" "1" "$(grep -c '^\[Options\]' "$WORK/client/system/l2.ini")"
teardown

# --- CRLF: файлы клиента приходят из Windows ---------------------------------
setup
mkdir -p "$WORK/client/system"; : > "$WORK/client/system/l2.exe"
printf '[Server]\r\nServerAddr=127.0.0.1\r\n' > "$WORK/client/system/l2.ini"
python3 "$PATCH" "$WORK/client/system/l2.ini" 192.168.0.133 >/dev/null
check "CRLF сохранён" "2" "$(grep -c $'\r$' "$WORK/client/system/l2.ini")"
check "адрес при CRLF применён" "192.168.0.133" \
  "$(addr_of "$WORK/client/system/l2.ini")"
teardown

# --- Плохие входные данные ---------------------------------------------------
setup
make_client "$WORK/client" '[Server]
ServerAddr=127.0.0.1
'
python3 "$PATCH" "$WORK/client/system/l2.ini" "" >/dev/null 2>&1
check "пустой адрес -> код 2" "2" "$?"
python3 "$PATCH" "$WORK/nope/l2.ini" 1.2.3.4 >/dev/null 2>&1
check "нет файла -> код 1" "1" "$?"
teardown

# --- client.sh: разбор пути и подстановка адреса из .env ---------------------
setup
proj="$WORK/proj"
mkdir -p "$proj/scripts/lib"
cp "$ROOT/scripts/client.sh" "$ROOT/scripts/set-client-addr.py" "$proj/scripts/"
cp "$ROOT/scripts/lib/common.sh" "$proj/scripts/lib/"
printf 'DB_PASSWORD=x\nL2_EXTERNAL_IP=192.168.0.133\n' > "$proj/.env"
make_client "$WORK/client" '[Server]
ServerAddr=127.0.0.1
'

ASSUME_YES=1 "$proj/scripts/client.sh" setup "$WORK/client" >/dev/null 2>&1
check "адрес взят из .env" "192.168.0.133" "$(addr_of "$WORK/client/system/l2.ini")"
check "путь к клиенту запомнен" "1" \
  "$(grep -c "^L2_CLIENT_DIR=$WORK/client$" "$proj/.env")"

# Указали папку system вместо корня — тоже должно работать.
printf '[Server]\nServerAddr=127.0.0.1\n' > "$WORK/client/system/l2.ini"
ASSUME_YES=1 "$proj/scripts/client.sh" setup "$WORK/client/system" >/dev/null 2>&1
check "путь к папке system принят" "192.168.0.133" \
  "$(addr_of "$WORK/client/system/l2.ini")"

# Повторный setup не должен плодить строки в .env.
ASSUME_YES=1 "$proj/scripts/client.sh" setup "$WORK/client" >/dev/null 2>&1
check "L2_CLIENT_DIR не дублируется" "1" "$(grep -c '^L2_CLIENT_DIR=' "$proj/.env")"

# Каталог, который не является клиентом.
mkdir -p "$WORK/notclient"
ASSUME_YES=1 "$proj/scripts/client.sh" setup "$WORK/notclient" >/dev/null 2>&1
check "чужой каталог отвергнут" "1" "$?"
teardown

echo
printf 'Итог клиента: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
