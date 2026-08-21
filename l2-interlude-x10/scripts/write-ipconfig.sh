#!/bin/bash
# =============================================================================
#  Пишет game/config/ipconfig.xml — файл, по которому логин-сервер решает,
#  какой адрес отдать клиенту для входа в мир.
#
#      ./scripts/write-ipconfig.sh <каталог game> <внешний адрес> <внутренний>
#
#  Тонкость Docker: клиент с этой же машины приходит через мост и выглядит
#  как 172.x, поэтому эта подсеть тоже указывает на внутренний адрес.
#
#  Формат проверяется схемой data/xsd/ipconfig.xsd: адрес — IPv4 или домен,
#  подсеть — IPv4 с маской. Ошибка здесь означает, что сервер не стартует.
# =============================================================================
set -euo pipefail

GAME_DIR="${1:?укажи каталог game}"
EXTERNAL="${2:?укажи внешний адрес}"
INTERNAL="${3:-$EXTERNAL}"

[ -d "$GAME_DIR/config" ] || { echo "нет каталога $GAME_DIR/config" >&2; exit 1; }

valid_address() {
  # IPv4 или доменное имя.
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0
  [[ "$1" =~ ^[A-Za-z0-9.-]+\.[A-Za-z]{2,63}$ ]] && return 0
  return 1
}

for addr in "$EXTERNAL" "$INTERNAL"; do
  valid_address "$addr" || {
    echo "адрес '$addr' не похож ни на IP, ни на домен — сервер его не примет" >&2
    exit 1
  }
done

cat > "$GAME_DIR/config/ipconfig.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<!-- Создан scripts/write-ipconfig.sh из значений .env. Правь .env, не этот файл. -->
<gameserver address="${EXTERNAL}" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="../data/xsd/ipconfig.xsd">
	<define subnet="127.0.0.0/8" address="${INTERNAL}" />
	<define subnet="10.0.0.0/8" address="${INTERNAL}" />
	<define subnet="172.16.0.0/12" address="${INTERNAL}" />
	<define subnet="192.168.0.0/16" address="${INTERNAL}" />
</gameserver>
XML
