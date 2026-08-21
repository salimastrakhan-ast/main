#!/bin/bash
# =============================================================================
#  Запуск LoginServer / GameServer внутри контейнера.
#
#  Сборка Mobius устроена так: jar-ы лежат в общем каталоге libs/, а рабочим
#  каталогом служит game/ или login/ — оттуда сервер читает config/ и data/.
#  Запуск: java <опции> -jar ../libs/GameServer.jar
#
#  Что делает скрипт:
#    1. ждёт готовности базы (иначе сервер падает на старте с SQLException);
#    2. собирает опции JVM: наши (куча, GC) + -D из штатного java.cfg сборки;
#    3. корректно проксирует SIGTERM в JVM;
#    4. обрабатывает код выхода 2 — у Mobius это «перезапуск по требованию».
# =============================================================================
set -euo pipefail

ROLE="${1:-${L2_ROLE:-game}}"
# Пути вынесены в переменные, чтобы логику запуска можно было прогонять
# тестами на хосте, без контейнера.
DIST="${L2_DIST:-/opt/l2/server}"
JVM_DIR="${L2_JVM_DIR:-/opt/l2/jvm}"

log() { printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$ROLE" "$*"; }
die() { log "ОШИБКА: $*" >&2; exit 1; }

case "$ROLE" in
  login) WORKDIR="$DIST/login"; JAR="../libs/LoginServer.jar"; OPTS_FILE="$JVM_DIR/loginserver.options" ;;
  game)  WORKDIR="$DIST/game";  JAR="../libs/GameServer.jar";  OPTS_FILE="$JVM_DIR/gameserver.options" ;;
  *)     die "неизвестная роль '$ROLE' (ожидается login или game)" ;;
esac

# --- 0. Сборка на месте? -----------------------------------------------------
[ -d "$WORKDIR" ] || die "нет каталога $WORKDIR.
     Сервер не собран. Выполни на хосте:  make build"

cd "$WORKDIR"

[ -f "$JAR" ] || die "не найден $JAR (рабочий каталог $WORKDIR).
     Похоже, сборка распакована не полностью — повтори make build"

# --- 1. Ждём базу ------------------------------------------------------------
# Проверяем именно TCP-порт: так рантайму не нужен клиент MariaDB, и образ
# остаётся стандартным JRE без единого доустановленного пакета.
DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
WAIT_DB_TIMEOUT="${WAIT_DB_TIMEOUT:-180}"

log "жду базу ${DB_HOST}:${DB_PORT} (таймаут ${WAIT_DB_TIMEOUT}s)"
deadline=$(( $(date +%s) + WAIT_DB_TIMEOUT ))
until (exec 3<>"/dev/tcp/${DB_HOST}/${DB_PORT}") 2>/dev/null; do
  if [ "$(date +%s)" -ge "$deadline" ]; then
    die "база не поднялась за ${WAIT_DB_TIMEOUT}s — смотри: docker compose logs db"
  fi
  sleep 2
done
log "база доступна"

# --- 2. Опции JVM ------------------------------------------------------------
JVM_ARGS=()

HEAP="${JVM_HEAP:-2G}"
JVM_ARGS+=("-Xms${HEAP}" "-Xmx${HEAP}")

case "${JVM_PROFILE:-zgc}" in
  zgc)
    # Начиная с JDK 23 ZGC поколенческий по умолчанию, а флаг ZGenerational
    # убран — на JDK 25 он бы уронил запуск. Поэтому только UseZGC.
    JVM_ARGS+=("-XX:+UseZGC")
    ;;
  g1)
    JVM_ARGS+=("-XX:+UseG1GC" "-XX:MaxGCPauseMillis=50" "-XX:G1HeapRegionSize=8m")
    ;;
  *)
    log "неизвестный JVM_PROFILE='${JVM_PROFILE}', беру g1"
    JVM_ARGS+=("-XX:+UseG1GC" "-XX:MaxGCPauseMillis=50")
    ;;
esac

# Системные свойства из штатного java.cfg сборки. Там лежит, в частности,
# java.util.logging.manager — без него логирование сервера не инициализируется.
# Куча и GC оттуда не берутся: ими управляем мы.
if [ -f java.cfg ]; then
  for token in $(cat java.cfg); do
    case "$token" in
      -D*) JVM_ARGS+=("$token") ;;
    esac
  done
  log "системные свойства подхвачены из java.cfg"
fi

# Наш профиль флагов.
if [ -f "$OPTS_FILE" ]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(echo "$line" | xargs || true)"
    [ -n "$line" ] && JVM_ARGS+=("$line")
  done < "$OPTS_FILE"
  log "подключён профиль JVM: $(basename "$OPTS_FILE")"
fi

if [ -n "${JVM_EXTRA_OPTS:-}" ]; then
  read -r -a extra <<< "$JVM_EXTRA_OPTS"
  JVM_ARGS+=("${extra[@]}")
fi

mkdir -p log

# --- 3. Запуск с корректным завершением -------------------------------------
JAVA_PID=""
shutdown() {
  if [ -n "$JAVA_PID" ] && kill -0 "$JAVA_PID" 2>/dev/null; then
    log "сигнал остановки — гашу сервер (идёт сохранение персонажей)"
    kill -TERM "$JAVA_PID" 2>/dev/null || true
    wait "$JAVA_PID" 2>/dev/null || true
  fi
  exit 0
}
trap shutdown TERM INT

while true; do
  log "старт: java ${JVM_ARGS[*]} -jar $JAR"
  set +e
  java "${JVM_ARGS[@]}" -jar "$JAR" &
  JAVA_PID=$!
  wait "$JAVA_PID"
  code=$?
  set -e

  # У Mobius код 2 означает «перезапустись» (команда админа //restart).
  if [ "$code" -eq 2 ]; then
    log "запрошен рестарт (код 2) — поднимаю заново"
    sleep 3
    continue
  fi

  log "процесс завершился с кодом $code"
  exit "$code"
done
