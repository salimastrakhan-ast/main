#!/bin/bash
# =============================================================================
#  Проверки самого репозитория.
#
#  Существуют из-за реального случая: шаблон "dist/" в .gitignore совпал не
#  только с каталогом сборки, но и с scripts/tests/fixtures/dist. Фикстуры
#  молча не попали в коммит, и у всех, кроме автора, тесты падали.
#  Здесь ловим такие вещи до пуша.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

PASS=0; FAIL=0

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mOK\033[0m   %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m %s\n       ожидалось: [%s]\n       получено:  [%s]\n' \
      "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

echo "=== Проверки репозитория ==="

if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
  echo "  (не git-репозиторий — пропускаю)"
  exit 0
fi

# Файлы, без которых тесты не смогут работать у другого человека.
required=(
  "scripts/tests/fixtures/dist/game/config/Rates.ini"
  "scripts/tests/fixtures/dist/game/config/Player.ini"
  "scripts/tests/fixtures/dist/game/config/Database.ini"
  "scripts/tests/fixtures/dist/game/config/Server.ini"
  "scripts/tests/fixtures/dist/game/java.cfg"
  "scripts/tests/fixtures/dist/game/GameServerTask.sh"
  "scripts/tests/fixtures/dist/login/config/Server.ini"
  "scripts/tests/fixtures/dist/login/LoginServerTask.sh"
  "scripts/tests/fixtures/dist/libs/GameServer.jar"
  "scripts/tests/fixtures/dist/game/data/xsd/ipconfig.xsd"
)

missing=0
for f in "${required[@]}"; do
  git -C "$ROOT" ls-files --error-unmatch "$f" >/dev/null 2>&1 || {
    printf '       не в репозитории: %s\n' "$f"
    missing=$((missing + 1))
  }
done
check "фикстуры под контролем версий" "0" "$missing"

# .gitignore не должен скрывать фикстуры.
ignored="$(git -C "$ROOT" check-ignore scripts/tests/fixtures/dist/game/config/Rates.ini 2>/dev/null | wc -l)"
check "фикстуры не под .gitignore" "0" "$ignored"

# Каталог сборки, наоборот, игнорироваться обязан.
not_ignored="$(git -C "$ROOT" check-ignore dist/ >/dev/null 2>&1 && echo 0 || echo 1)"
check "каталог сборки ./dist игнорируется" "0" "$not_ignored"

# .env с паролями не должен утечь в репозиторий.
env_tracked="$(git -C "$ROOT" ls-files --error-unmatch .env >/dev/null 2>&1 && echo 1 || echo 0)"
check ".env не в репозитории" "0" "$env_tracked"

echo
printf 'Итог репозитория: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
