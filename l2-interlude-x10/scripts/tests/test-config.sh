#!/bin/bash
# =============================================================================
#  Тесты патчера конфигов. Гоняются на фикстурах, повторяющих структуру
#  конфигов Mobius, — сам эмулятор для этого не нужен.
#
#      ./scripts/tests/run-tests.sh
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
APPLY="$ROOT/scripts/apply-config.py"
FIXTURES="$HERE/fixtures"

PASS=0
FAIL=0
WORK=""

setup() {
  WORK="$(mktemp -d)"
  cp -r "$FIXTURES/game" "$WORK/game"
  cp -r "$FIXTURES/login" "$WORK/login"
}

teardown() {
  [ -n "$WORK" ] && rm -rf "$WORK"
}

run_apply() {
  local profile="$1"; shift
  python3 "$APPLY" --profile "$profile" \
      --game-dir "$WORK/game" --login-dir "$WORK/login" --no-color "$@" 2>&1
}

value_of() {
  # value_of <файл> <ключ>
  grep -iE "^\s*$2\s*=" "$1" | head -n1 | sed 's/^[^=]*=\s*//' | tr -d '\r'
}

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mOK\033[0m   %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m %s\n       ожидалось: [%s]\n       получено:  [%s]\n' \
      "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Тесты apply-config.py ==="

# --- 1. Профиль x10 действительно проставляет рейты ---------------------------
setup
export DB_PASSWORD="testpass" L2_EXTERNAL_IP="10.1.2.3" DB_HOST="db" \
       DB_GAME_NAME="l2jgs" DB_LOGIN_NAME="l2jls" DB_USER="l2j" TZ="Europe/Moscow"
run_apply "$ROOT/config/profiles/x10-classic.conf" >/dev/null
check "RateXp = 10"                    "10" "$(value_of "$WORK/game/config/Rates.ini" RateXp)"
check "RateSp = 10"                    "10" "$(value_of "$WORK/game/config/Rates.ini" RateSp)"
check "RateDropAdena = 10"             "10" "$(value_of "$WORK/game/config/Rates.ini" RateDropAdena)"
check "DeathDropChanceMultiplier = 5"  "5"  "$(value_of "$WORK/game/config/Rates.ini" DeathDropChanceMultiplier)"
check "RaidDropChanceMultiplier = 2"   "2"  "$(value_of "$WORK/game/config/Rates.ini" RaidDropChanceMultiplier)"
check "AutoLoot выключен (классик)"    "False" "$(value_of "$WORK/game/config/Character.ini" AutoLoot)"
check "AutoLootHerbs включён"          "True"  "$(value_of "$WORK/game/config/Character.ini" AutoLootHerbs)"
check "PathFinding = 2"                "2"  "$(value_of "$WORK/game/config/GeoEngine.ini" PathFinding)"

# --- 2. Закомментированные строки не трогаются --------------------------------
check "закомментированный RateXp цел" \
  "1" "$(grep -c '^# RateXp = 999\.' "$WORK/game/config/Rates.ini")"

# --- 3. Резервная копия создаётся --------------------------------------------
check "создан Rates.ini.orig" "yes" \
  "$([ -f "$WORK/game/config/Rates.ini.orig" ] && echo yes || echo no)"
check "в .orig лежит исходное значение" "1." \
  "$(value_of "$WORK/game/config/Rates.ini.orig" RateXp)"

# --- 4. Идемпотентность: повторный прогон ничего не меняет --------------------
out="$(run_apply "$ROOT/config/profiles/x10-classic.conf")"
check "повторный прогон: 0 изменений" "0" \
  "$(echo "$out" | grep -oP 'изменено ключей\s*:\s*\K\d+' | head -n1)"

# --- 5. Сетевой профиль: подстановка переменных окружения ---------------------
run_apply "$ROOT/config/profiles/_network.conf" >/dev/null
check "ExternalHostname из \$L2_EXTERNAL_IP" "10.1.2.3" \
  "$(value_of "$WORK/game/config/Server.ini" ExternalHostname)"
check "LoginHost указывает на контейнер login" "login" \
  "$(value_of "$WORK/game/config/Server.ini" LoginHost)"
check "пароль БД подставлен" "testpass" \
  "$(value_of "$WORK/game/config/Server.ini" Password)"
check "URL с параметрами сохранил всё после '='" "yes" \
  "$(grep -q 'rewriteBatchedStatements=true' "$WORK/game/config/Server.ini" && echo yes || echo no)"
check "URL указывает на базу из .env" "yes" \
  "$(grep -q 'jdbc:mysql://db:3306/l2jgs' "$WORK/game/config/Server.ini" && echo yes || echo no)"
check "логин-сервер: своя база" "yes" \
  "$(grep -q 'jdbc:mysql://db:3306/l2jls' "$WORK/login/config/LoginServer.ini" && echo yes || echo no)"
teardown

# --- 6. --dry-run ничего не пишет --------------------------------------------
setup
before="$(md5sum "$WORK/game/config/Rates.ini" | cut -d' ' -f1)"
run_apply "$ROOT/config/profiles/x10-classic.conf" --dry-run >/dev/null
after="$(md5sum "$WORK/game/config/Rates.ini" | cut -d' ' -f1)"
check "--dry-run не меняет файл" "$before" "$after"
check "--dry-run не создаёт .orig" "no" \
  "$([ -f "$WORK/game/config/Rates.ini.orig" ] && echo yes || echo no)"
teardown

# --- 7. Отсутствующий обязательный ключ = ошибка ------------------------------
setup
cat > "$WORK/bad.conf" <<'EOF'
[game]
Rates.ini : !ThisKeyDoesNotExist = 1
EOF
run_apply "$WORK/bad.conf" >/dev/null 2>&1
check "обязательный ключ отсутствует -> код 1" "1" "$?"
teardown

# --- 8. Незаданная переменная окружения = ошибка профиля ----------------------
setup
cat > "$WORK/env.conf" <<'EOF'
[game]
Rates.ini : RateXp = ${TOTALLY_UNSET_VARIABLE}
EOF
run_apply "$WORK/env.conf" >/dev/null 2>&1
check "незаданная переменная -> код 2" "2" "$?"
teardown

# --- 9. Переменная со значением по умолчанию ---------------------------------
setup
cat > "$WORK/def.conf" <<'EOF'
[game]
Rates.ini : RateXp = ${ALSO_UNSET:-7}
EOF
run_apply "$WORK/def.conf" >/dev/null
check "значение по умолчанию применилось" "7" \
  "$(value_of "$WORK/game/config/Rates.ini" RateXp)"
teardown

# --- 10. Файл в подкаталоге находится по имени -------------------------------
setup
mkdir -p "$WORK/game/config/Custom"
printf 'SomeCustomKey = 1\n' > "$WORK/game/config/Custom/Custom.ini"
cat > "$WORK/sub.conf" <<'EOF'
[game]
Custom.ini : SomeCustomKey = 42
EOF
run_apply "$WORK/sub.conf" >/dev/null
check "конфиг найден в подкаталоге" "42" \
  "$(value_of "$WORK/game/config/Custom/Custom.ini" SomeCustomKey)"
teardown

# --- 11. Windows-переводы строк не ломаются ----------------------------------
setup
printf 'RateXp = 1.\r\nRateSp = 1.\r\n' > "$WORK/game/config/Rates.ini"
cat > "$WORK/crlf.conf" <<'EOF'
[game]
Rates.ini : RateXp = 10
EOF
run_apply "$WORK/crlf.conf" >/dev/null
check "CRLF сохранён" "2" "$(grep -c $'\r$' "$WORK/game/config/Rates.ini")"
check "значение при CRLF применилось" "10" \
  "$(value_of "$WORK/game/config/Rates.ini" RateXp)"
teardown

# --- 12. Профиль retail-x1 возвращает единицы --------------------------------
setup
run_apply "$ROOT/config/profiles/x10-classic.conf" >/dev/null
run_apply "$ROOT/config/profiles/retail-x1.conf" >/dev/null
check "retail-x1 вернул RateXp в 1" "1" \
  "$(value_of "$WORK/game/config/Rates.ini" RateXp)"
teardown

# --- 13. Битая строка профиля ловится ----------------------------------------
setup
printf '[game]\nэто не пара ключ-значение\n' > "$WORK/broken.conf"
run_apply "$WORK/broken.conf" >/dev/null 2>&1
check "битый профиль -> код 2" "2" "$?"
teardown

echo
printf 'Итог: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then
  printf '\033[31m%d failed\033[0m\n' "$FAIL"
  exit 1
fi
printf '0 failed\n'
exit 0
