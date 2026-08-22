#!/bin/bash
# =============================================================================
#  Тесты сборки патча для клиента на другой машине.
#
#  Патч уезжает к человеку, который сервер не видит и починить ничего не
#  сможет: любая ошибка здесь превращается в "у меня не работает" без шансов
#  на диагностику. Поэтому проверяем и подстановку адреса, и то, что файлы
#  доедут до Windows читаемыми — кодировку и переводы строк.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

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

# Копия стенда во временном каталоге: чтобы проверять чтение .env, не трогая
# настоящий .env разработчика.
fake_root() {
  local root="$WORK/proj"
  mkdir -p "$root"
  cp -r "$ROOT/scripts" "$root/scripts"
  printf '%s\n' "$@" > "$root/.env"
  printf '%s\n' "$root"
}

build() { "$1/scripts/client-patch.sh" --out "$WORK/out" "${@:2}"; }

# Содержимое файла из архива.
inside() { unzip -p "$1" "$2"; }

echo "=== Тесты патча для клиента ==="

if ! command -v zip >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
  printf '  \033[33mПРОПУЩЕНО\033[0m нет zip/unzip\n'
  exit 0
fi

# --- Адрес из аргумента ------------------------------------------------------
setup
proj="$(fake_root 'L2_EXTERNAL_IP=127.0.0.1' 'LOGIN_PORT=2106' 'GAME_PORT=7777')"
build "$proj" 203.0.113.10 >/dev/null 2>&1
zipfile="$WORK/out/l2-patch-203.0.113.10.zip"

check "архив создан" "yes" "$([ -f "$zipfile" ] && echo yes || echo no)"
check "в архиве три файла" "3" "$(unzip -Z1 "$zipfile" | wc -l)"
check "аргумент важнее .env" "1" \
  "$(inside "$zipfile" patch.ps1 | grep -c '^\$Addr  = "203\.0\.113\.10"')"
check "адрес попал в bat" "yes" \
  "$(inside "$zipfile" setup-client.bat | grep -q '203\.0\.113\.10' && echo yes || echo no)"
check "адрес попал в README" "1" "$(inside "$zipfile" README.txt | grep -c 'Патч клиента для сервера 203\.0\.113\.10')"

# Незаменённый плейсхолдер = клиент пойдёт в никуда, а человек этого
# не заметит до самого входа в игру.
check "плейсхолдеров не осталось" "0" \
  "$(unzip -p "$zipfile" | grep -c '@ADDR@\|@LOGIN_PORT@\|@GAME_PORT@')"
teardown

# --- Адрес и порты из .env ---------------------------------------------------
setup
proj="$(fake_root 'L2_EXTERNAL_IP=192.168.0.133' 'LOGIN_PORT=2107' 'GAME_PORT=7778')"
build "$proj" >/dev/null 2>&1
zipfile="$WORK/out/l2-patch-192.168.0.133.zip"

check "адрес взят из .env" "yes" "$([ -f "$zipfile" ] && echo yes || echo no)"
check "нестандартный порт логина подставлен" "1" \
  "$(inside "$zipfile" patch.ps1 | grep -c '^\$Login = \[int\]"2107"')"
check "нестандартный порт игры подставлен" "1" \
  "$(inside "$zipfile" patch.ps1 | grep -c '^\$Game  = \[int\]"7778"')"

# Пересборка не должна падать на уже существующем архиве.
build "$proj" >/dev/null 2>&1
check "повторная сборка проходит" "0" "$?"
teardown

# --- Windows-специфика: кодировка и переводы строк ----------------------------
# Без BOM PowerShell 5.1 читает .ps1 как ANSI, и русские сообщения
# превращаются в кракозябры; в .bat BOM, наоборот, ломает первую строку.
setup
proj="$(fake_root 'L2_EXTERNAL_IP=192.168.0.133')"
build "$proj" >/dev/null 2>&1
mkdir -p "$WORK/unpacked"
unzip -q -d "$WORK/unpacked" "$WORK/out/l2-patch-192.168.0.133.zip"

bom_of() { head -c3 "$1" | od -An -tx1 | tr -d ' \n'; }
for file in patch.ps1 README.txt; do
  check "$file с BOM" "efbbbf" "$(bom_of "$WORK/unpacked/$file")"
done
check "setup-client.bat без BOM" "no" \
  "$([ "$(bom_of "$WORK/unpacked/setup-client.bat")" = "efbbbf" ] && echo yes || echo no)"

for file in patch.ps1 README.txt setup-client.bat; do
  check "$file с CRLF" "0" \
    "$(grep -c $'[^\r]$' "$WORK/unpacked/$file")"
done
teardown

# --- Без адреса вообще -------------------------------------------------------
# Молча собранный архив с пустым адресом хуже отказа: он выглядит рабочим.
setup
proj="$WORK/noenv"
mkdir -p "$proj"
cp -r "$ROOT/scripts" "$proj/scripts"
build "$proj" >/dev/null 2>&1
check "без .env и без аргумента — отказ" "1" "$?"
teardown

# --- Сам patch.ps1 под настоящим PowerShell ----------------------------------
# Гоняется, только если образ уже скачан: тянуть его ради тестов не станем.
# Проверяем кодировки l2.ini — на них скрипт однажды уже испортил клиент,
# прочитав UTF-16 как однобайтовый текст и записав обратно мусор.
PS_IMAGE=mcr.microsoft.com/powershell:latest
if command -v docker >/dev/null 2>&1 && docker image inspect "$PS_IMAGE" >/dev/null 2>&1; then
  setup
  proj="$(fake_root 'L2_EXTERNAL_IP=192.168.0.133')"
  build "$proj" >/dev/null 2>&1
  unzip -q -d "$WORK" "$WORK/out/l2-patch-192.168.0.133.zip"

  ini_body=$'[Server]\r\nServerAddr=127.0.0.1\r\nServerPort=2106\r\n'
  make_ini() { mkdir -p "$WORK/$1/system"; printf '%s' "$ini_body" | iconv -f UTF-8 -t "$2" > "$WORK/$1/system/l2.ini"; }

  make_ini ansi CP1251
  make_ini utf16 UTF-16LE
  mkdir -p "$WORK/utf16bom/system"
  { printf '\xff\xfe'; cat "$WORK/utf16/system/l2.ini"; } > "$WORK/utf16bom/system/l2.ini"

  run_ps() {
    docker run --rm -v "$WORK:/w" -w /w "$PS_IMAGE" \
      pwsh -NoProfile -File /w/patch.ps1 -ClientDir "/w/$1" >/dev/null 2>&1
  }
  addr_in() { grep -a -c 'ServerAddr=192\.168\.0\.133' "$1"; }
  first_bytes() { head -c2 "$1" | od -An -tx1 | tr -d ' \n'; }

  run_ps ansi
  check "ANSI: адрес прописан" "1" "$(addr_in "$WORK/ansi/system/l2.ini")"
  check "ANSI: нулевых байтов не появилось" "0" \
    "$(tr -dc '\000' < "$WORK/ansi/system/l2.ini" | wc -c)"

  run_ps utf16bom
  check "UTF-16 с BOM: адрес прописан" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/utf16bom/system/l2.ini" | grep -c 'ServerAddr=192\.168\.0\.133')"
  check "UTF-16 с BOM: кодировка сохранена" "fffe" \
    "$(first_bytes "$WORK/utf16bom/system/l2.ini")"

  # Кодировку не опознали — файл должен остаться нетронутым, а не испорченным.
  cp "$WORK/utf16/system/l2.ini" "$WORK/utf16-before.ini"
  run_ps utf16
  check "UTF-16 без BOM: отказ, файл не тронут" "yes" \
    "$(cmp -s "$WORK/utf16-before.ini" "$WORK/utf16/system/l2.ini" && echo yes || echo no)"
  check "UTF-16 без BOM: копия .orig не создана" "no" \
    "$([ -f "$WORK/utf16/system/l2.ini.orig" ] && echo yes || echo no)"
  teardown
else
  printf '  \033[33mПРОПУЩЕНО\033[0m прогон patch.ps1: нет образа %s\n' "$PS_IMAGE"
fi

echo
printf 'Итог патча клиента: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
