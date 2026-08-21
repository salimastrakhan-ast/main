#!/bin/bash
# =============================================================================
#  Тесты определения структуры исходников и сборки (scripts/lib/detect.sh).
#  Проверяются на макетах и на фикстурах реальной раскладки Mobius.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURES="$HERE/fixtures/dist"
# shellcheck source=/dev/null
source "$ROOT/scripts/lib/detect.sh"

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

echo "=== Тесты detect.sh ==="

# --- Каталоги репозитория через git ------------------------------------------
# Важно: при частичной выкладке файлов на диске нет, поэтому список каталогов
# должен браться из дерева коммита, а не из ls.
setup
repo="$WORK/repo"
mkdir -p "$repo"
git -C "$repo" init -q 2>/dev/null
git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
for d in L2J_Mobius_CT_0_Interlude L2J_Mobius_C4_ScionsOfDestiny L2J_Mobius_Classic_1.0; do
  mkdir -p "$repo/$d"; : > "$repo/$d/build.xml"
done
git -C "$repo" add -A >/dev/null 2>&1
git -C "$repo" commit -qm init >/dev/null 2>&1

check "каталоги видны из дерева коммита" "3" "$(list_repo_dirs "$repo" | grep -c L2J)"

# Эмулируем частичную выкладку: файлов нет, дерево на месте.
rm -rf "$repo/L2J_Mobius_C4_ScionsOfDestiny" "$repo/L2J_Mobius_Classic_1.0"
check "список цел и без выложенных файлов" "3" "$(list_repo_dirs "$repo" | grep -c L2J)"

check "Interlude найден автоматически" "L2J_Mobius_CT_0_Interlude" \
  "$(detect_chronicle_dir "$repo" AUTO)"
check "явно заданная хроника уважается" "L2J_Mobius_Classic_1.0" \
  "$(detect_chronicle_dir "$repo" L2J_Mobius_Classic_1.0)"
detect_chronicle_dir "$repo" L2J_Mobius_Nope >/dev/null 2>&1
check "несуществующая хроника -> код 1" "1" "$?"
teardown

# Два кандидата Interlude -> нужен выбор пользователя.
setup
mkdir -p "$WORK/r2/Foo_Interlude" "$WORK/r2/Bar_Interlude"
detect_chronicle_dir "$WORK/r2" AUTO >/dev/null 2>&1
check "неоднозначность -> код 2" "2" "$?"
# Classic рядом с обычным Interlude не мешает.
mkdir -p "$WORK/r3/L2J_Mobius_CT_0_Interlude" "$WORK/r3/L2J_Mobius_Classic_Interlude"
check "Classic не перебивает обычный Interlude" "L2J_Mobius_CT_0_Interlude" \
  "$(detect_chronicle_dir "$WORK/r3" AUTO)"
teardown

# --- Система сборки ----------------------------------------------------------
setup
mkdir -p "$WORK/ant" "$WORK/mvn" "$WORK/none"
touch "$WORK/ant/build.xml" "$WORK/mvn/pom.xml"
check "ant по build.xml"   "ant"     "$(detect_build_system "$WORK/ant")"
check "maven по pom.xml"   "maven"   "$(detect_build_system "$WORK/mvn")"
check "неизвестная сборка" "unknown" "$(detect_build_system "$WORK/none")"
teardown

# --- Архив сборки: ant кладёт его на уровень выше хроники --------------------
setup
mkdir -p "$WORK/repo/build"
: > "$WORK/repo/build/L2J_Mobius_CT_0_Interlude.zip"
check "архив сборки найден" "$WORK/repo/build/L2J_Mobius_CT_0_Interlude.zip" \
  "$(detect_build_zip "$WORK/repo")"

# Старый архив (сутки+) не должен подхватываться как результат текущей сборки.
touch -d '3 days ago' "$WORK/repo/build/L2J_Mobius_CT_0_Interlude.zip"
check "устаревший архив игнорируется" "" "$(detect_build_zip "$WORK/repo")"
teardown

# --- Каталоги сборки на настоящей раскладке Mobius ---------------------------
setup
cp -r "$FIXTURES" "$WORK/dist"
check "игровой сервер найден" "$WORK/dist/game"  "$(detect_game_dist "$WORK/dist")"
check "логин-сервер найден"   "$WORK/dist/login" "$(detect_login_dist "$WORK/dist")"

# У логин-сервера Mobius нет LoginServer.ini, а Server.ini есть у обоих —
# поэтому определяем по стартовым скриптам, иначе роли перепутаются.
check "login не выдаёт себя за game" "$WORK/dist/game" "$(detect_game_dist "$WORK/dist")"

# Запасной признак: только у игрового сервера есть config/Rates.ini.
rm -f "$WORK/dist/game/GameServerTask.sh"
check "запасной признак по Rates.ini" "$WORK/dist/game" "$(detect_game_dist "$WORK/dist")"

# --- SQL ---------------------------------------------------------------------
check "sql логин-сервера"   "$WORK/dist/db_installer/sql/login" \
  "$(detect_sql_dir "$WORK/dist" login)"
check "sql игрового сервера" "$WORK/dist/db_installer/sql/game" \
  "$(detect_sql_dir "$WORK/dist" game)"

rm -f "$WORK/dist/db_installer/sql/game"/*.sql
detect_sql_dir "$WORK/dist" game >/dev/null 2>&1
check "каталог без .sql -> код 1" "1" "$?"
teardown

echo
printf 'Итог detect: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
