#!/bin/bash
# =============================================================================
#  Тесты генератора ipconfig.xml.
#
#  Этот файл решает, какой адрес получит клиент для входа в мир, и проверяется
#  сервером по схеме data/xsd/ipconfig.xsd. Ошибка в нём = "вечное Connecting..."
#  или отказ сервера стартовать, поэтому результат сверяется с настоящей схемой
#  из сборки Mobius.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURES="$HERE/fixtures/dist"
WRITE="$ROOT/scripts/write-ipconfig.sh"

PASS=0; FAIL=0; WORK=""
setup()    { WORK="$(mktemp -d)"; cp -r "$FIXTURES" "$WORK/dist"; }
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

# Проверка по настоящей схеме сервера: вытаскиваем из неё регулярки
# и применяем к нашему файлу.
validate_against_xsd() {
  python3 - "$1" "$2" <<'PY'
import re, sys, xml.etree.ElementTree as ET

xml_path, xsd_path = sys.argv[1], sys.argv[2]
xsd = open(xsd_path, encoding='utf-8').read()
patterns = re.findall(r'<xs:pattern value="(.*?)" />', xsd)
if len(patterns) < 3:
    print("нет паттернов в схеме"); sys.exit(1)
addr_pat, subnet_pat, root_addr_pat = patterns[0], patterns[1], patterns[2]

root = ET.parse(xml_path).getroot()
if root.tag != 'gameserver':
    print("корневой тег не gameserver"); sys.exit(1)
if not re.fullmatch(root_addr_pat, root.get('address') or ''):
    print("адрес сервера не проходит схему"); sys.exit(1)

defines = root.findall('define')
if not defines:
    print("нет ни одного define"); sys.exit(1)
for d in defines:
    if not re.fullmatch(subnet_pat, d.get('subnet') or ''):
        print("подсеть не проходит схему:", d.get('subnet')); sys.exit(1)
    if not re.fullmatch(addr_pat, d.get('address') or ''):
        print("адрес define не проходит схему:", d.get('address')); sys.exit(1)
print("ok")
PY
}

echo "=== Тесты ipconfig.xml ==="

XSD_REL="game/data/xsd/ipconfig.xsd"

# --- Локальная установка -----------------------------------------------------
setup
"$WRITE" "$WORK/dist/game" 127.0.0.1 127.0.0.1 >/dev/null 2>&1
check "файл создан" "yes" \
  "$([ -f "$WORK/dist/game/config/ipconfig.xml" ] && echo yes || echo no)"
check "проходит настоящую схему сервера" "ok" \
  "$(validate_against_xsd "$WORK/dist/game/config/ipconfig.xml" "$WORK/dist/$XSD_REL")"
check "адрес подставлен" "127.0.0.1" \
  "$(grep -oP '<gameserver address="\K[^"]+' "$WORK/dist/game/config/ipconfig.xml")"
teardown

# --- Игра по локальной сети --------------------------------------------------
setup
"$WRITE" "$WORK/dist/game" 192.168.1.50 192.168.1.50 >/dev/null 2>&1
check "LAN-адрес проходит схему" "ok" \
  "$(validate_against_xsd "$WORK/dist/game/config/ipconfig.xml" "$WORK/dist/$XSD_REL")"

# Подсеть docker-моста обязана быть описана: клиент с этой же машины
# приходит через неё, иначе он получит внешний адрес и не подключится.
check "подсеть docker-моста описана" "1" \
  "$(grep -c 'subnet="172.16.0.0/12"' "$WORK/dist/game/config/ipconfig.xml")"
teardown

# --- Домен вместо IP ---------------------------------------------------------
setup
"$WRITE" "$WORK/dist/game" l2.example.com 192.168.1.50 >/dev/null 2>&1
check "доменное имя принято" "ok" \
  "$(validate_against_xsd "$WORK/dist/game/config/ipconfig.xml" "$WORK/dist/$XSD_REL")"
check "внешний адрес — домен" "l2.example.com" \
  "$(grep -oP '<gameserver address="\K[^"]+' "$WORK/dist/game/config/ipconfig.xml")"
check "внутренний остался IP" "192.168.1.50" \
  "$(grep -oP 'subnet="10.0.0.0/8" address="\K[^"]+' "$WORK/dist/game/config/ipconfig.xml")"
teardown

# --- Мусор на входе не должен попасть в конфиг -------------------------------
setup
"$WRITE" "$WORK/dist/game" 'не адрес' 127.0.0.1 >/dev/null 2>&1
check "мусорный адрес отвергнут" "1" "$?"
check "файл не создан" "no" \
  "$([ -f "$WORK/dist/game/config/ipconfig.xml" ] && echo yes || echo no)"
teardown

# --- Нет каталога сборки -----------------------------------------------------
setup
"$WRITE" "$WORK/nonexistent" 127.0.0.1 127.0.0.1 >/dev/null 2>&1
check "без каталога game -> ошибка" "1" "$?"
teardown

echo
printf 'Итог ipconfig: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
