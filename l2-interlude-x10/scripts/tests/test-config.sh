#!/bin/bash
# =============================================================================
#  Тесты патчера конфигов. Гоняются на фикстурах, повторяющих раскладку
#  L2J_Mobius_CT_0_Interlude, — сам эмулятор для этого скачивать не нужно.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
APPLY="$ROOT/scripts/apply-config.py"
FIXTURES="$HERE/fixtures/dist"

PASS=0
FAIL=0
WORK=""

setup()    { WORK="$(mktemp -d)"; cp -r "$FIXTURES" "$WORK/dist"; }
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

run_apply() {
  local profile="$1"; shift
  python3 "$APPLY" --profile "$profile" \
      --game-dir "$WORK/dist/game" --login-dir "$WORK/dist/login" \
      --no-color "$@" 2>&1
}

value_of() { grep -iE "^\s*$2\s*=" "$1" | head -n1 | sed 's/^[^=]*=\s*//' | tr -d '\r'; }

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mOK\033[0m   %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m %s\n       ожидалось: [%s]\n       получено:  [%s]\n' \
      "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

echo "=== Тесты apply-config.py (раскладка Mobius Interlude) ==="

# --- 1. Профиль x10 на настоящих ключах Mobius -------------------------------
setup
export DB_PASSWORD="testpass" L2_EXTERNAL_IP="10.1.2.3" L2_INTERNAL_IP="10.1.2.3" \
       DB_HOST="db" DB_NAME="l2jmobius" DB_USER="l2j" TZ="Europe/Moscow"
run_apply "$ROOT/config/profiles/x10-classic.conf" >/dev/null
G="$WORK/dist/game/config"
check "RateXp = 10"                   "10" "$(value_of "$G/Rates.ini" RateXp)"
check "RateSp = 10"                   "10" "$(value_of "$G/Rates.ini" RateSp)"
check "DeathDropChanceMultiplier = 5" "5"  "$(value_of "$G/Rates.ini" DeathDropChanceMultiplier)"
check "SpoilDropChanceMultiplier = 5" "5"  "$(value_of "$G/Rates.ini" SpoilDropChanceMultiplier)"
check "RaidDropChanceMultiplier = 2"  "2"  "$(value_of "$G/Rates.ini" RaidDropChanceMultiplier)"
check "RateQuestRewardAdena = 10"     "10" "$(value_of "$G/Rates.ini" RateQuestRewardAdena)"

# Адена (id 57) x10, остальные предметы в списке не тронуты.
check "адена x10 через id 57" "57,10;6656,1;6657,1;6658,1;6659,1;6660,1;6661,1;6662,1;8191,1" \
  "$(value_of "$G/Rates.ini" DropAmountMultiplierByItemId)"

# Автолут и скиллы живут в Player.ini, а не в Character.ini.
check "AutoLoot выключен (классик)" "False" "$(value_of "$G/Player.ini" AutoLoot)"
check "AutoLootHerbs включён"       "True"  "$(value_of "$G/Player.ini" AutoLootHerbs)"
check "AutoLootRaids выключен"      "False" "$(value_of "$G/Player.ini" AutoLootRaids)"
check "AutoLearnSkills выключен"    "False" "$(value_of "$G/Player.ini" AutoLearnSkills)"
check "PathFinding = 2"             "2"     "$(value_of "$G/GeoEngine.ini" PathFinding)"
check "закомментированный RateXp цел" "1" "$(grep -c '^# RateXp = 999' "$G/Rates.ini")"

# --- 2. Профиль не должен ничего сломать в сетевых файлах --------------------
check "Server.ini не тронут профилем рейтов" "0.0.0.0" \
  "$(value_of "$G/Server.ini" GameserverHostname)"

# --- 3. Идемпотентность ------------------------------------------------------
out="$(run_apply "$ROOT/config/profiles/x10-classic.conf")"
check "повторный прогон: 0 изменений" "0" \
  "$(echo "$out" | grep -oP 'изменено ключей\s*:\s*\K\d+' | head -n1)"

# --- 4. Сетевой профиль ------------------------------------------------------
run_apply "$ROOT/config/profiles/_network.conf" >/dev/null
check "LoginHost -> контейнер login" "login" "$(value_of "$G/Server.ini" LoginHost)"
check "пароль БД подставлен (game)"  "testpass" "$(value_of "$G/Database.ini" Password)"
check "пароль БД подставлен (login)" "testpass" \
  "$(value_of "$WORK/dist/login/config/Database.ini" Password)"
check "URL ведёт на контейнер db"    "yes" \
  "$(grep -q 'jdbc:mysql://db:3306/l2jmobius' "$G/Database.ini" && echo yes || echo no)"
check "URL сохранил всё после '='"   "yes" \
  "$(grep -q 'rewriteBatchedStatements=true' "$G/Database.ini" && echo yes || echo no)"
check "логин слушает все интерфейсы" "0.0.0.0" \
  "$(value_of "$WORK/dist/login/config/Server.ini" LoginserverHostname)"
check "регистрация геймсервера разрешена" "True" \
  "$(value_of "$WORK/dist/login/config/Server.ini" AcceptNewGameServer)"
teardown

# --- 5. --dry-run ничего не пишет --------------------------------------------
setup
before="$(md5sum "$WORK/dist/game/config/Rates.ini" | cut -d' ' -f1)"
run_apply "$ROOT/config/profiles/x10-classic.conf" --dry-run >/dev/null
check "--dry-run не меняет файл" "$before" \
  "$(md5sum "$WORK/dist/game/config/Rates.ini" | cut -d' ' -f1)"
teardown

# --- 6. Обязательный ключ отсутствует = ошибка -------------------------------
setup
printf '[game]\nRates.ini : !ThisKeyDoesNotExist = 1\n' > "$WORK/bad.conf"
run_apply "$WORK/bad.conf" >/dev/null 2>&1
check "обязательный ключ отсутствует -> код 1" "1" "$?"
teardown

# --- 7. Незаданная переменная окружения = ошибка профиля ---------------------
setup
printf '[game]\nRates.ini : RateXp = ${TOTALLY_UNSET_VARIABLE}\n' > "$WORK/env.conf"
run_apply "$WORK/env.conf" >/dev/null 2>&1
check "незаданная переменная -> код 2" "2" "$?"
teardown

# --- 8. Значение по умолчанию ------------------------------------------------
setup
printf '[game]\nRates.ini : RateXp = ${ALSO_UNSET:-7}\n' > "$WORK/def.conf"
run_apply "$WORK/def.conf" >/dev/null
check "значение по умолчанию применилось" "7" \
  "$(value_of "$WORK/dist/game/config/Rates.ini" RateXp)"
teardown

# --- 9. Конфиг в подкаталоге (у Mobius есть config/Custom) -------------------
setup
mkdir -p "$WORK/dist/game/config/Custom"
printf 'SomeCustomKey = 1\n' > "$WORK/dist/game/config/Custom/Custom.ini"
printf '[game]\nCustom.ini : SomeCustomKey = 42\n' > "$WORK/sub.conf"
run_apply "$WORK/sub.conf" >/dev/null
check "конфиг найден в config/Custom" "42" \
  "$(value_of "$WORK/dist/game/config/Custom/Custom.ini" SomeCustomKey)"
teardown

# --- 10. CRLF ----------------------------------------------------------------
setup
printf 'RateXp = 1\r\nRateSp = 1\r\n' > "$WORK/dist/game/config/Rates.ini"
printf '[game]\nRates.ini : RateXp = 10\n' > "$WORK/crlf.conf"
run_apply "$WORK/crlf.conf" >/dev/null
check "CRLF сохранён" "2" "$(grep -c $'\r$' "$WORK/dist/game/config/Rates.ini")"
check "значение при CRLF применилось" "10" \
  "$(value_of "$WORK/dist/game/config/Rates.ini" RateXp)"
teardown

# --- 11. retail-x1 возвращает единицы ----------------------------------------
setup
run_apply "$ROOT/config/profiles/x10-classic.conf" >/dev/null
run_apply "$ROOT/config/profiles/retail-x1.conf" >/dev/null
check "retail-x1 вернул RateXp в 1" "1" \
  "$(value_of "$WORK/dist/game/config/Rates.ini" RateXp)"
check "retail-x1 вернул адену в 1" "57,1;6656,1;6657,1;6658,1;6659,1;6660,1;6661,1;6662,1;8191,1" \
  "$(value_of "$WORK/dist/game/config/Rates.ini" DropAmountMultiplierByItemId)"
teardown

# --- 12. Битый профиль -------------------------------------------------------
setup
printf '[game]\nэто не пара ключ-значение\n' > "$WORK/broken.conf"
run_apply "$WORK/broken.conf" >/dev/null 2>&1
check "битый профиль -> код 2" "2" "$?"
teardown

echo
printf 'Итог: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
