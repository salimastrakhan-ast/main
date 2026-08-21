#!/bin/bash
# =============================================================================
#  Тесты запуска сервера (docker/entrypoint.sh).
#
#  Проверяется то, что решает, стартует ли игра вообще: правильный jar,
#  правильный рабочий каталог, корректный набор опций JVM и обработка
#  кода выхода 2 (перезапуск по команде админа).
#
#  Контейнер не нужен: java подменяется заглушкой, база — обычным
#  TCP-слушателем.
# =============================================================================
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
FIXTURES="$HERE/fixtures/dist"
ENTRY="$ROOT/docker/entrypoint.sh"

PASS=0; FAIL=0; WORK=""; DB_PID=""; DB_PORT=""

check() {
  local name="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf '  \033[32mOK\033[0m   %s\n' "$name"; PASS=$((PASS + 1))
  else
    printf '  \033[31mFAIL\033[0m %s\n       ожидалось: [%s]\n       получено:  [%s]\n' \
      "$name" "$expected" "$actual"; FAIL=$((FAIL + 1))
  fi
}

start_db_stub() {
  DB_PORT="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
  python3 -m http.server "$DB_PORT" --bind 127.0.0.1 >/dev/null 2>&1 &
  DB_PID=$!
  for _ in $(seq 1 50); do
    (exec 3<>"/dev/tcp/127.0.0.1/$DB_PORT") 2>/dev/null && return 0
    sleep 0.1
  done
  echo "не удалось поднять заглушку базы" >&2; return 1
}

setup() {
  WORK="$(mktemp -d)"
  cp -r "$FIXTURES" "$WORK/dist"
  mkdir -p "$WORK/bin"
  # Заглушка java: записывает аргументы и рабочий каталог, затем выходит.
  cat > "$WORK/bin/java" <<'JAVA'
#!/bin/bash
echo "$@" >> "$JAVA_ARGS_FILE"
pwd >> "$JAVA_CWD_FILE"
exit "${JAVA_EXIT_CODE:-0}"
JAVA
  chmod +x "$WORK/bin/java"
  export JAVA_ARGS_FILE="$WORK/java-args.txt" JAVA_CWD_FILE="$WORK/java-cwd.txt"
  : > "$JAVA_ARGS_FILE"; : > "$JAVA_CWD_FILE"
}

# Заглушка базы живёт до конца набора: она общая для всех случаев.
teardown() { [ -n "$WORK" ] && rm -rf "$WORK"; }

run_entry() {
  local role="$1"
  PATH="$WORK/bin:$PATH" \
  L2_DIST="$WORK/dist" L2_JVM_DIR="$ROOT/jvm" \
  DB_HOST=127.0.0.1 DB_PORT="$DB_PORT" WAIT_DB_TIMEOUT=10 \
  JVM_HEAP="${JVM_HEAP_TEST:-1G}" JVM_PROFILE="${JVM_PROFILE_TEST:-zgc}" \
  JAVA_EXIT_CODE="${JAVA_EXIT_CODE:-0}" \
  timeout 60 bash "$ENTRY" "$role" >"$WORK/out.txt" 2>&1
}

echo "=== Тесты entrypoint.sh ==="

start_db_stub || exit 1

# --- Игровой сервер ----------------------------------------------------------
setup
run_entry game
code=$?
args="$(cat "$JAVA_ARGS_FILE")"
check "игровой сервер стартовал (код 0)" "0" "$code"
check "запущен GameServer.jar" "yes" \
  "$(grep -q -- '-jar ../libs/GameServer.jar' <<<"$args" && echo yes || echo no)"
check "рабочий каталог — game/" "$WORK/dist/game" "$(head -n1 "$JAVA_CWD_FILE")"
check "куча задана из JVM_HEAP" "yes" \
  "$(grep -q -- '-Xms1G' <<<"$args" && grep -q -- '-Xmx1G' <<<"$args" && echo yes || echo no)"
check "включён ZGC" "yes" \
  "$(grep -q -- '-XX:+UseZGC' <<<"$args" && echo yes || echo no)"

# На JDK 25 флага ZGenerational больше нет: если он просочится, JVM не стартует.
check "нет удалённого флага ZGenerational" "no" \
  "$(grep -q -- 'ZGenerational' <<<"$args" && echo yes || echo no)"

# Без этого свойства логирование Mobius не инициализируется.
check "подхвачен logging.manager из java.cfg" "yes" \
  "$(grep -q -- '-Djava.util.logging.manager=org.l2jmobius.log.ServerLogManager' <<<"$args" \
     && echo yes || echo no)"

# Куча из java.cfg (-Xmx4g) не должна перебивать нашу.
check "куча из java.cfg не подхвачена" "no" \
  "$(grep -q -- '-Xmx4g' <<<"$args" && echo yes || echo no)"
check "флаги профиля JVM подключены" "yes" \
  "$(grep -q -- '-XX:+AlwaysPreTouch' <<<"$args" && echo yes || echo no)"
teardown

# --- Логин-сервер ------------------------------------------------------------
setup
run_entry login
args="$(cat "$JAVA_ARGS_FILE")"
check "запущен LoginServer.jar" "yes" \
  "$(grep -q -- '-jar ../libs/LoginServer.jar' <<<"$args" && echo yes || echo no)"
check "рабочий каталог — login/" "$WORK/dist/login" "$(head -n1 "$JAVA_CWD_FILE")"
teardown

# --- Профиль G1 --------------------------------------------------------------
setup
JVM_PROFILE_TEST=g1 run_entry game
args="$(cat "$JAVA_ARGS_FILE")"
check "профиль g1 включает G1GC" "yes" \
  "$(grep -q -- '-XX:+UseG1GC' <<<"$args" && echo yes || echo no)"
check "профиль g1 не включает ZGC" "no" \
  "$(grep -q -- '-XX:+UseZGC' <<<"$args" && echo yes || echo no)"
teardown

# --- Код выхода 2 = перезапуск ----------------------------------------------
setup
# Заглушка: первый запуск возвращает 2 (рестарт), второй — 0.
cat > "$WORK/bin/java" <<'JAVA'
#!/bin/bash
echo "$@" >> "$JAVA_ARGS_FILE"
count=$(wc -l < "$JAVA_ARGS_FILE")
[ "$count" -eq 1 ] && exit 2
exit 0
JAVA
chmod +x "$WORK/bin/java"
run_entry game
code=$?
check "после кода 2 сервер поднялся заново" "2" "$(wc -l < "$JAVA_ARGS_FILE")"
check "итоговый код выхода 0" "0" "$code"
teardown

# --- Нет сборки = понятная ошибка -------------------------------------------
setup
rm -rf "$WORK/dist/game"
run_entry game
code=$?
check "без сборки -> ненулевой код" "1" "$code"
check "сообщение подсказывает make build" "yes" \
  "$(grep -q 'make build' "$WORK/out.txt" && echo yes || echo no)"
teardown

# --- Недоступная база = внятный таймаут -------------------------------------
setup
dead_port="$(python3 -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()')"
PATH="$WORK/bin:$PATH" L2_DIST="$WORK/dist" L2_JVM_DIR="$ROOT/jvm" \
  DB_HOST=127.0.0.1 DB_PORT="$dead_port" WAIT_DB_TIMEOUT=3 JVM_HEAP=1G \
  timeout 40 bash "$ENTRY" game >"$WORK/out.txt" 2>&1
check "без базы -> ненулевой код" "1" "$?"
check "java не запускался" "0" "$(wc -l < "$JAVA_ARGS_FILE")"
check "сообщение про логи базы" "yes" \
  "$(grep -q 'logs db' "$WORK/out.txt" && echo yes || echo no)"
teardown

[ -n "$DB_PID" ] && kill "$DB_PID" 2>/dev/null

echo
printf 'Итог entrypoint: \033[32m%d passed\033[0m, ' "$PASS"
if [ "$FAIL" -gt 0 ]; then printf '\033[31m%d failed\033[0m\n' "$FAIL"; exit 1; fi
printf '0 failed\n'
exit 0
