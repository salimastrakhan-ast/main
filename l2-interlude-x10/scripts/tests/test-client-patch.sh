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
  run_ps_out() {
    docker run --rm -v "$WORK:/w" -w /w "$PS_IMAGE" \
      pwsh -NoProfile -File /w/patch.ps1 -ClientDir "/w/$1" 2>&1
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

  # Ровно тот случай, на котором патч однажды угробил клиент: UTF-16 без BOM.
  run_ps utf16
  check "UTF-16 без BOM: адрес прописан" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/utf16/system/l2.ini" | grep -c 'ServerAddr=192\.168\.0\.133')"
  check "UTF-16 без BOM: BOM не приписан" "no" \
    "$([ "$(first_bytes "$WORK/utf16/system/l2.ini")" = "fffe" ] && echo yes || echo no)"
  check "UTF-16 без BOM: файл остался UTF-16" "yes" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/utf16/system/l2.ini" >/dev/null 2>&1 && echo yes || echo no)"

  # --- Ремонт клиента, испорченного прежней версией патча --------------------
  # Та версия дописывала [Server] однобайтовыми буквами внутрь UTF-16.
  damaged_ini() {
    mkdir -p "$WORK/$1/system"
    printf '[Server]\r\nServerAddr=127.0.0.1\r\nServerPort=2106\r\n' \
      | iconv -f UTF-8 -t UTF-16LE > "$WORK/$1/system/l2.ini"
    printf '\r\n[Server]\r\nServerAddr=192.168.0.133\r\n' >> "$WORK/$1/system/l2.ini"
  }
  # Однобайтовый "[Server]" внутри файла = мусор от прежней версии.
  has_foreign_tail() {
    python3 -c "import sys; sys.exit(0 if open(sys.argv[1],'rb').read().find(b'[Server]') >= 0 else 1)" "$1" \
      && echo yes || echo no
  }

  # С резервной копией: возвращаем её целиком.
  damaged_ini repair
  printf '[Server]\r\nServerAddr=127.0.0.1\r\nServerPort=2106\r\n' \
    | iconv -f UTF-8 -t UTF-16LE > "$WORK/repair/system/l2.ini.orig"
  run_ps repair
  check "ремонт из .orig: мусор убран" "no" "$(has_foreign_tail "$WORK/repair/system/l2.ini")"
  check "ремонт из .orig: адрес прописан" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/repair/system/l2.ini" | grep -c 'ServerAddr=192\.168\.0\.133')"
  check "ремонт из .orig: ServerPort уцелел" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/repair/system/l2.ini" | grep -c 'ServerPort=2106')"

  # Без резервной копии: отрезаем чужой хвост.
  damaged_ini repair2
  run_ps repair2
  check "ремонт без .orig: мусор убран" "no" "$(has_foreign_tail "$WORK/repair2/system/l2.ini")"
  check "ремонт без .orig: адрес прописан" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/repair2/system/l2.ini" | grep -c 'ServerAddr=192\.168\.0\.133')"
  check "ремонт без .orig: ServerPort уцелел" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/repair2/system/l2.ini" | grep -c 'ServerPort=2106')"
  teardown

  # --- Версия патча видна в выводе ------------------------------------------
  # По пересланному скриншоту иначе не понять, какая версия у человека на
  # руках: чинишь то, что уже починено.
  setup
  proj="$(fake_root 'L2_EXTERNAL_IP=192.168.0.133')"
  build "$proj" >/dev/null 2>&1
  unzip -q -d "$WORK" "$WORK/out/l2-patch-192.168.0.133.zip"
  mkdir -p "$WORK/stamp/system"
  printf '[Server]\r\nServerAddr=127.0.0.1\r\n' > "$WORK/stamp/system/l2.ini"

  out="$(run_ps_out stamp)"
  check "штамп версии напечатан" "1" "$(printf '%s' "$out" | grep -c "патч от $(date +%Y-%m-%d)")"

  # Кодировка не опознана — вывод должен нести байты для диагностики.
  mkdir -p "$WORK/utf32/system"
  printf '[Server]\nServerAddr=127.0.0.1\n' | iconv -f UTF-8 -t UTF-32LE > "$WORK/utf32/system/l2.ini"
  cp "$WORK/utf32/system/l2.ini" "$WORK/utf32-before.ini"
  out="$(run_ps_out utf32)"
  check "при отказе показаны байты" "1" "$(printf '%s' "$out" | grep -c 'байты: 5b 00 00 00')"
  check "при отказе файл не тронут" "yes" \
    "$(cmp -s "$WORK/utf32-before.ini" "$WORK/utf32/system/l2.ini" && echo yes || echo no)"
  teardown

  # --- Репак: адрес живёт мимо l2.ini ---------------------------------------
  # Сборки с чужих серверов держат адрес во втором конфиге или переписывают
  # l2.ini лаунчером. Патч отрабатывает честно, а игрок попадает не туда —
  # ровно это и случилось у первого живого пользователя.
  setup
  proj="$(fake_root 'L2_EXTERNAL_IP=192.168.0.133')"
  build "$proj" >/dev/null 2>&1
  unzip -q -d "$WORK" "$WORK/out/l2-patch-192.168.0.133.zip"

  mkdir -p "$WORK/repack/system"
  printf '[Server]\r\nServerAddr=127.0.0.1\r\n' > "$WORK/repack/system/l2.ini"
  printf '[Server]\r\nServerAddr=45.132.17.9\r\n' > "$WORK/repack/system/l2server.ini"
  printf '[Server]\r\nServerAddr=play.someserver.ru\r\n' \
    | iconv -f UTF-8 -t UTF-16LE > "$WORK/repack/system/options.ini"
  : > "$WORK/repack/L2Launcher.exe"
  : > "$WORK/repack/system/l2.exe"

  out="$(printf 'д\n' | docker run --rm -i -v "$WORK:/w" -w /w "$PS_IMAGE" \
        pwsh -NoProfile -File /w/patch.ps1 -ClientDir /w/repack 2>&1)"

  check "чужой адрес в другом .ini найден" "1" \
    "$(printf '%s' "$out" | grep -c '45\.132\.17\.9')"
  check "чужой адрес в UTF-16 .ini найден" "1" \
    "$(printf '%s' "$out" | grep -c 'play\.someserver\.ru')"
  check "лаунчер сборки замечен" "1" \
    "$(printf '%s' "$out" | grep -c 'L2Launcher\.exe')"
  check "второй .ini поправлен" "1" \
    "$(grep -c '^ServerAddr=192\.168\.0\.133' "$WORK/repack/system/l2server.ini")"
  # Номер группы в подстановке однажды съел адрес и записал "$1192.168.0.133".
  check "мусора от подстановки нет" "0" \
    "$(grep -c '\$1' "$WORK/repack/system/l2server.ini")"
  check "UTF-16 .ini поправлен и остался UTF-16" "1" \
    "$(iconv -f UTF-16LE -t UTF-8 "$WORK/repack/system/options.ini" | grep -c '^ServerAddr=192\.168\.0\.133')"
  check "копия второго .ini создана" "yes" \
    "$([ -f "$WORK/repack/system/l2server.ini.orig" ] && echo yes || echo no)"
  teardown

  # --- Отличаем живой L2 от просто открытого порта --------------------------
  # "Порт отвечает" вводит в заблуждение: слушать там может что угодно, а
  # игрок видит молчание клиента после ввода пароля. Логин-сервер L2
  # здоровается первым, на этом и ловим.
  setup
  port_login=25106; port_game=27777
  proj="$(fake_root 'L2_EXTERNAL_IP=127.0.0.1' "LOGIN_PORT=$port_login" "GAME_PORT=$port_game")"
  build "$proj" >/dev/null 2>&1
  unzip -q -d "$WORK" "$WORK/out/l2-patch-127.0.0.1.zip"
  mkdir -p "$WORK/probe/system"
  printf '[Server]\r\nServerAddr=1.2.3.4\r\n' > "$WORK/probe/system/l2.ini"

  # Заглушка: шлёт правдоподобный заголовок пакета либо молчит.
  fake_server() {
    python3 -c "
import socket, sys, threading
mode, port = sys.argv[1], int(sys.argv[2])
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port)); s.listen(8)
def serve():
    while True:
        try: c, _ = s.accept()
        except OSError: return
        if mode == 'l2': c.sendall(bytes([194, 0]) + b'\x00' * 192)
        threading.Timer(2.0, c.close).start()
threading.Thread(target=serve, daemon=True).start()
import time; time.sleep(25)
" "$1" "$2" &
    sleep 1
  }

  fake_server l2 "$port_login";   l2_pid=$!
  fake_server mute "$port_game";  mute_pid=$!

  out="$(docker run --rm --network host -v "$WORK:/w" -w /w "$PS_IMAGE" \
        pwsh -NoProfile -File /w/patch.ps1 -ClientDir /w/probe 2>&1)"
  check "живой L2 опознан" "1" "$(printf '%s' "$out" | grep -c 'настоящий логин-сервер L2')"

  # Теперь наоборот: на порту логина молчаливая заглушка.
  kill "$l2_pid" "$mute_pid" 2>/dev/null; wait "$l2_pid" "$mute_pid" 2>/dev/null
  fake_server mute "$port_login"; mute2_pid=$!
  out="$(docker run --rm --network host -v "$WORK:/w" -w /w "$PS_IMAGE" \
        pwsh -NoProfile -File /w/patch.ps1 -ClientDir /w/probe 2>&1)"
  check "молчащий порт не принят за L2" "1" \
    "$(printf '%s' "$out" | grep -c 'по-русски L2 оттуда не отвечают')"
  kill "$mute2_pid" 2>/dev/null; wait "$mute2_pid" 2>/dev/null
  teardown
else
  printf '  \033[33mПРОПУЩЕНО\033[0m прогон patch.ps1: нет образа %s\n' "$PS_IMAGE"
fi

echo
printf 'Итог патча клиента: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
