#!/bin/bash
# =============================================================================
#  Тесты определения структуры исходников и сборки (scripts/lib/detect.sh).
#  Проверяются на макетах деревьев каталогов — эмулятор скачивать не нужно.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/detect.sh"

PASS=0
FAIL=0
WORK=""

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

echo "=== Тесты detect.sh ==="

# --- Выбор каталога хроники --------------------------------------------------
setup
mkdir -p "$WORK/repo/L2J_Mobius_C6_Interlude" \
         "$WORK/repo/L2J_Mobius_C4_ScionsOfDestiny" \
         "$WORK/repo/L2J_Mobius_Essence_1.0"
check "единственный Interlude найден" "L2J_Mobius_C6_Interlude" \
  "$(detect_chronicle_dir "$WORK/repo" AUTO)"

# Добавляем Classic Interlude — кандидатов становится два.
mkdir -p "$WORK/repo/L2J_Mobius_Classic_Interlude"
check "при Classic рядом выбирается обычный Interlude" "L2J_Mobius_C6_Interlude" \
  "$(detect_chronicle_dir "$WORK/repo" AUTO)"

# Явно заданная хроника перевешивает автоопределение.
check "явно заданная хроника уважается" "L2J_Mobius_Classic_Interlude" \
  "$(detect_chronicle_dir "$WORK/repo" L2J_Mobius_Classic_Interlude)"

# Несуществующая — ошибка.
detect_chronicle_dir "$WORK/repo" L2J_Mobius_Nonexistent >/dev/null 2>&1
check "несуществующая хроника -> код 1" "1" "$?"

# Два неотличимых кандидата -> код 2 и список.
mkdir -p "$WORK/repo2/Foo_Interlude" "$WORK/repo2/Bar_Interlude"
detect_chronicle_dir "$WORK/repo2" AUTO >/dev/null 2>&1
check "неоднозначность -> код 2" "2" "$?"
check "в списке оба кандидата" "2" \
  "$(detect_chronicle_dir "$WORK/repo2" AUTO 2>/dev/null | grep -c Interlude)"

# Совсем нет Interlude -> код 1.
mkdir -p "$WORK/repo3/L2J_Mobius_Classic_3.0"
detect_chronicle_dir "$WORK/repo3" AUTO >/dev/null 2>&1
check "нет кандидатов -> код 1" "1" "$?"
teardown

# --- Система сборки ----------------------------------------------------------
setup
mkdir -p "$WORK/ant" "$WORK/mvn" "$WORK/gradle" "$WORK/nothing"
touch "$WORK/ant/build.xml" "$WORK/mvn/pom.xml" "$WORK/gradle/gradlew"
check "ant по build.xml"        "ant"     "$(detect_build_system "$WORK/ant")"
check "maven по pom.xml"        "maven"   "$(detect_build_system "$WORK/mvn")"
check "gradle по gradlew"       "gradle"  "$(detect_build_system "$WORK/gradle")"
check "неизвестная сборка"      "unknown" "$(detect_build_system "$WORK/nothing")"

# build.xml имеет приоритет: у Mobius лежат оба файла, рабочий — ant.
touch "$WORK/ant/pom.xml"
check "build.xml важнее pom.xml" "ant" "$(detect_build_system "$WORK/ant")"
teardown

# --- Каталоги собранной сборки -----------------------------------------------
setup
mkdir -p "$WORK/build/dist/game/config" "$WORK/build/dist/login/config"
touch "$WORK/build/dist/login/config/LoginServer.ini" \
      "$WORK/build/dist/login/config/Server.ini" \
      "$WORK/build/dist/game/config/Server.ini"
check "login найден по LoginServer.ini" "$WORK/build/dist/login" \
  "$(detect_login_dist "$WORK/build")"
check "game не путается с login" "$WORK/build/dist/game" \
  "$(detect_game_dist "$WORK/build")"

# Раскладка старого L2J: gameserver вместо game.
setup
mkdir -p "$WORK/build/dist/gameserver/config" "$WORK/build/dist/login/config"
touch "$WORK/build/dist/login/config/LoginServer.ini" \
      "$WORK/build/dist/gameserver/config/Server.ini"
check "старая раскладка gameserver/" "$WORK/build/dist/gameserver" \
  "$(detect_game_dist "$WORK/build")"
teardown

# --- Каталог SQL -------------------------------------------------------------
setup
mkdir -p "$WORK/dist/sql/game" "$WORK/dist/sql/login"
touch "$WORK/dist/sql/game/characters.sql" "$WORK/dist/sql/login/accounts.sql"
check "sql/game найден" "$WORK/dist/sql/game" "$(detect_sql_dir "$WORK/dist" game)"
check "sql/login найден" "$WORK/dist/sql/login" "$(detect_sql_dir "$WORK/dist" login)"

# Пустой каталог без .sql не должен приниматься за нужный.
setup
mkdir -p "$WORK/dist/sql/game"
detect_sql_dir "$WORK/dist" game >/dev/null 2>&1
check "каталог без .sql -> код 1" "1" "$?"
teardown

echo
printf 'Итог detect: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
