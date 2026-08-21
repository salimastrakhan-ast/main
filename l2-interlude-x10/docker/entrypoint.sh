#!/bin/bash
# =============================================================================
#  Запуск LoginServer / GameServer внутри контейнера.
#
#  Что делает:
#    1. ждёт готовности MariaDB (иначе L2J падает на старте с SQLException);
#    2. определяет main-класс сборки (у разных форков он разный);
#    3. собирает команду java с нужным профилем GC;
#    4. корректно проксирует SIGTERM в JVM и обрабатывает
#       "перезапуск по требованию" (код выхода 2 у L2J = restart).
# =============================================================================
set -euo pipefail

ROLE="${1:-game}"
SERVER_DIR="/opt/l2/server"
JVM_DIR="/opt/l2/jvm"

log() { printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$ROLE" "$*"; }
die() { log "ОШИБКА: $*" >&2; exit 1; }

case "$ROLE" in
  login) OPTS_FILE="$JVM_DIR/loginserver.options" ;;
  game)  OPTS_FILE="$JVM_DIR/gameserver.options" ;;
  *)     die "неизвестная роль '$ROLE' (ожидается login или game)" ;;
esac

# --- 0. Сборка на месте? -----------------------------------------------------
if [ ! -d "$SERVER_DIR" ] || [ -z "$(ls -A "$SERVER_DIR" 2>/dev/null)" ]; then
  die "каталог сборки пуст: $SERVER_DIR
     Сначала собери сервер:  make build   (или ./scripts/build-server.sh)"
fi

cd "$SERVER_DIR"

# --- 1. Ждём базу ------------------------------------------------------------
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
WAIT_DB_TIMEOUT="${WAIT_DB_TIMEOUT:-120}"

log "жду MariaDB ${DB_HOST}:${DB_PORT} (таймаут ${WAIT_DB_TIMEOUT}s)"
deadline=$(( $(date +%s) + WAIT_DB_TIMEOUT ))
until mariadb-admin ping -h "$DB_HOST" -P "$DB_PORT" \
        -u "${DB_USER:-l2j}" -p"${DB_PASSWORD:-}" --silent >/dev/null 2>&1; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    die "база не поднялась за ${WAIT_DB_TIMEOUT}s — проверь docker compose logs db"
  fi
  sleep 2
done
log "база доступна"

# --- 2. Ищем main-класс ------------------------------------------------------
# Приоритет: явный MAIN_CLASS -> разбор стартовых скриптов сборки -> known-list.
find_main_class() {
  if [ -n "${MAIN_CLASS:-}" ]; then
    echo "$MAIN_CLASS"; return 0
  fi

  # Стартовые скрипты сборки (*.sh/*.bat) содержат имя класса — это самый
  # надёжный источник: работает и на Mobius, и на aCis, и на старом L2J.
  local pattern
  case "$ROLE" in
    login) pattern='[A-Za-z0-9_.]*[Ll]oginserver\.[A-Za-z0-9_]*LoginServer' ;;
    game)  pattern='[A-Za-z0-9_.]*gameserver\.[A-Za-z0-9_]*GameServer' ;;
  esac

  local found
  found="$(grep -rhoE "(org|com|net)\.${pattern}" \
            --include='*.sh' --include='*.bat' . 2>/dev/null | head -n1 || true)"
  if [ -n "$found" ]; then
    echo "$found"; return 0
  fi

  # Фолбэк: перебираем известные варианты и проверяем, что класс реально
  # присутствует в classpath.
  local candidates
  case "$ROLE" in
    login) candidates="org.l2jmobius.loginserver.LoginServer
                       net.sf.l2j.loginserver.LoginServer
                       com.l2jserver.loginserver.L2LoginServer
                       org.l2jserver.loginserver.LoginServer" ;;
    game)  candidates="org.l2jmobius.gameserver.GameServer
                       net.sf.l2j.gameserver.GameServer
                       com.l2jserver.gameserver.GameServer
                       org.l2jserver.gameserver.GameServer" ;;
  esac

  # Проверяем наличие класса, не запуская его: имена файлов внутри jar
  # лежат в центральном каталоге архива открытым текстом, поэтому grep по
  # бинарнику даёт надёжный ответ и не требует JDK в рантайме.
  local c entry jar
  for c in $candidates; do
    entry="${c//./\/}.class"
    for jar in ./libs/*.jar ./lib/*.jar ./*.jar; do
      [ -f "$jar" ] || continue
      if grep -qa "$entry" "$jar" 2>/dev/null; then
        echo "$c"; return 0
      fi
    done
  done
  return 1
}

build_classpath() {
  # Порядок важен: сначала jar самой сборки, затем библиотеки.
  local cp="."
  [ -d ./libs ]      && cp="$cp:./libs/*"
  [ -d ./lib ]       && cp="$cp:./lib/*"
  cp="$cp:./*"
  echo "$cp"
}

CLASSPATH_STR="$(build_classpath)"

if ! MAIN="$(find_main_class)"; then
  die "не удалось определить main-класс сборки.
     Задай его явно, например:
       docker compose run -e MAIN_CLASS=org.l2jmobius.gameserver.GameServer game"
fi
log "main-класс: $MAIN"

# --- 3. Опции JVM ------------------------------------------------------------
JVM_ARGS=()

HEAP="${JVM_HEAP:-2G}"
JVM_ARGS+=("-Xms${HEAP}" "-Xmx${HEAP}")

case "${JVM_PROFILE:-zgc}" in
  zgc)
    # Generational ZGC: паузы в доли миллисекунды независимо от размера кучи.
    # Именно паузы Stop-The-World дают классический "фриз раз в пару минут"
    # на сборках L2 с большим онлайном.
    JVM_ARGS+=("-XX:+UseZGC" "-XX:+ZGenerational")
    ;;
  g1)
    JVM_ARGS+=("-XX:+UseG1GC" "-XX:MaxGCPauseMillis=50" "-XX:G1HeapRegionSize=8m")
    ;;
  *)
    log "неизвестный JVM_PROFILE='${JVM_PROFILE}', беру g1"
    JVM_ARGS+=("-XX:+UseG1GC" "-XX:MaxGCPauseMillis=50")
    ;;
esac

# Флаги из файла профиля (комментарии и пустые строки игнорируем).
if [ -f "$OPTS_FILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] && JVM_ARGS+=("$line")
  done < "$OPTS_FILE"
  log "подключён профиль JVM: $OPTS_FILE"
fi

# Разовые флаги через окружение.
if [ -n "${JVM_EXTRA_OPTS:-}" ]; then
  read -r -a extra <<< "$JVM_EXTRA_OPTS"
  JVM_ARGS+=("${extra[@]}")
fi

# --- 4. Запуск с корректным завершением -------------------------------------
JAVA_PID=""
shutdown() {
  if [ -n "$JAVA_PID" ] && kill -0 "$JAVA_PID" 2>/dev/null; then
    log "получен сигнал остановки — гашу сервер (сохранение персонажей)"
    kill -TERM "$JAVA_PID" 2>/dev/null || true
    wait "$JAVA_PID" 2>/dev/null || true
  fi
  exit 0
}
trap shutdown TERM INT

while true; do
  log "старт: java ${JVM_ARGS[*]} -cp <classpath> $MAIN"
  set +e
  java "${JVM_ARGS[@]}" -cp "$CLASSPATH_STR" "$MAIN" &
  JAVA_PID=$!
  wait "$JAVA_PID"
  code=$?
  set -e

  # Соглашение L2J: 2 — рестарт по команде админа, 0/1 — штатное выключение.
  if [ "$code" -eq 2 ]; then
    log "запрошен рестарт (код 2) — поднимаю заново"
    sleep 2
    continue
  fi

  log "процесс завершился с кодом $code"
  exit "$code"
done
