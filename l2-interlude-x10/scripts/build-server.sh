#!/bin/bash
# =============================================================================
#  Скачивает исходники эмулятора и собирает их в ./dist.
#
#      ./scripts/build-server.sh              # обычная сборка
#      ./scripts/build-server.sh --update     # подтянуть свежие исходники
#      ./scripts/build-server.sh --local      # собирать инструментами хоста
#      ./scripts/build-server.sh --yes        # без вопросов
#
#  Про сборку Mobius, чтобы не было сюрпризов:
#    * компилируется с source/target 25 — нужен именно JDK 25;
#    * цель ant по умолчанию называется cleanup: она пакует результат в ZIP
#      и УДАЛЯЕТ build/dist. Поэтому готовую сборку берём из ZIP;
#    * ZIP лежит на уровень выше каталога хроники: <репозиторий>/build/*.zip.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"
# shellcheck source=lib/detect.sh
source "$ROOT/scripts/lib/detect.sh"

load_env "$ROOT/.env"

SOURCES_DIR="$ROOT/.sources"
REPO_DIR="$SOURCES_DIR/emulator"
DIST_DIR="$ROOT/dist"
MIN_FREE_GB="${MIN_FREE_GB:-6}"

DO_UPDATE=0
FORCE_LOCAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --update) DO_UPDATE=1 ;;
    --local)  FORCE_LOCAL=1 ;;
    --yes|-y) export ASSUME_YES=1 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
  shift
done

# --- 0. Место на диске -------------------------------------------------------
free_gb="$(df -BG --output=avail "$ROOT" | tail -n1 | tr -dc '0-9')"
log "свободно на диске: ${free_gb} ГБ"
if [ "${free_gb:-0}" -lt "$MIN_FREE_GB" ]; then
  warn "для сборки нужно хотя бы ${MIN_FREE_GB} ГБ, а свободно ${free_gb} ГБ."
  warn "Освободи место или собери на другом диске."
  confirm "Всё равно продолжить?" || die "отменено"
fi

# --- 1. Исходники ------------------------------------------------------------
if [ -n "${L2_SOURCE_LOCAL:-}" ]; then
  [ -d "$L2_SOURCE_LOCAL" ] || die "L2_SOURCE_LOCAL указывает в никуда: $L2_SOURCE_LOCAL"
  REPO_DIR="$L2_SOURCE_LOCAL"
  log "использую локальные исходники: $REPO_DIR"
else
  require_cmd git
  mkdir -p "$SOURCES_DIR"

  sparse_args=()
  if [ "${L2_SPARSE_CHECKOUT:-1}" = "1" ]; then
    # В репозитории 38 хроник. Без частичной выкладки на диск ляжет всё
    # сразу; с ней — только нужная. Разница в разы.
    sparse_args=(--filter=blob:none --sparse)
  fi

  if [ ! -d "$REPO_DIR/.git" ]; then
    log "клонирую $L2_SOURCE_REPO (ветка $L2_SOURCE_BRANCH)"
    git clone --depth 1 --single-branch "${sparse_args[@]}" \
        --branch "$L2_SOURCE_BRANCH" "$L2_SOURCE_REPO" "$REPO_DIR" \
      || die "не удалось клонировать. Проверь сеть и адрес L2_SOURCE_REPO"
  elif [ "$DO_UPDATE" = "1" ]; then
    log "обновляю исходники"
    git -C "$REPO_DIR" fetch --depth 1 origin "$L2_SOURCE_BRANCH"
    git -C "$REPO_DIR" reset --hard "origin/$L2_SOURCE_BRANCH"
  else
    log "исходники уже скачаны (--update чтобы обновить)"
  fi
fi

# --- 2. Какую хронику собираем ----------------------------------------------
set +e
CHRONICLE="$(detect_chronicle_dir "$REPO_DIR" "${L2_CHRONICLE:-AUTO}")"
detect_status=$?
set -e

case "$detect_status" in
  0) ;;
  2) printf '%s\n' "$CHRONICLE" | sed 's/^/    /'
     die "несколько подходящих хроник (см. выше). Укажи нужную в .env:
     L2_CHRONICLE=<имя каталога>" ;;
  *) die "не нашёл каталог хроники Interlude.
     Посмотри список:  git -C $REPO_DIR ls-tree -d --name-only HEAD
     и укажи явно в .env:  L2_CHRONICLE=<имя каталога>" ;;
esac
ok "хроника: $CHRONICLE"

# Выкладываем на диск только её.
if [ "${L2_SPARSE_CHECKOUT:-1}" = "1" ] && [ -d "$REPO_DIR/.git" ]; then
  log "выкладываю только $CHRONICLE (частичная выкладка)"
  git -C "$REPO_DIR" sparse-checkout set "$CHRONICLE" \
    || warn "частичная выкладка не удалась, работаю с тем, что есть"
fi

SRC="$REPO_DIR/$CHRONICLE"
[ -d "$SRC" ] || die "каталог $SRC не появился после выкладки"

BUILD_SYSTEM="$(detect_build_system "$SRC")"
[ "$BUILD_SYSTEM" = "ant" ] \
  || die "ожидался ant (build.xml), а найдено: $BUILD_SYSTEM.
     Стенд рассчитан на сборку Mobius; для другого эмулятора правь этот скрипт."

# --- 3. Чем собирать ---------------------------------------------------------
# Mobius требует JDK 25. На хосте его обычно нет, поэтому по умолчанию
# компилируем в контейнере с готовым JDK 25, а ant подкладываем с хоста —
# он на чистой Java и прекрасно работает откуда угодно. Так не нужен ни
# свой Dockerfile, ни buildx.
JDK_IMAGE="${JDK_IMAGE:-eclipse-temurin:25-jdk-noble}"
BUILDER=""

host_java_ok() {
  local v; v="$(javac_major 2>/dev/null || true)"
  [ -n "$v" ] && [ "$v" -ge 25 ]
}

if [ "$FORCE_LOCAL" = "1" ]; then
  require_cmd ant "Установи:  sudo apt install ant"
  host_java_ok || die "нужен JDK 25, а на хосте javac $(javac_major 2>/dev/null || echo 'не найден').
     Убери --local, и сборка пойдёт в контейнере с готовым JDK 25."
  BUILDER=local
elif command -v ant >/dev/null 2>&1 && host_java_ok; then
  BUILDER=local
elif command -v docker >/dev/null 2>&1; then
  BUILDER=docker
else
  die "нечем собирать: нужен либо Docker, либо ant вместе с JDK 25 на хосте."
fi

ANT_HOME_HOST=""
if [ "$BUILDER" = "docker" ]; then
  for candidate in "${ANT_HOME:-}" /usr/share/ant /opt/ant; do
    [ -n "$candidate" ] && [ -f "$candidate/bin/ant" ] && { ANT_HOME_HOST="$candidate"; break; }
  done
  [ -n "$ANT_HOME_HOST" ] \
    || die "для сборки в контейнере нужен ant на хосте (он подкладывается внутрь).
     Установи:  sudo apt install ant"
fi

log "собираю через: $BUILDER (ant, JDK 25). Первый раз это 5-15 минут."

if [ "$BUILDER" = "local" ]; then
  ( cd "$SRC" && ant ) || die "сборка не удалась — смотри вывод выше"
else
  docker run --rm \
    -v "$REPO_DIR:/work/src" \
    -v "$ANT_HOME_HOST:/opt/ant:ro" \
    -v /usr/share/java:/usr/share/java:ro \
    -w "/work/src/$CHRONICLE" \
    -e ANT_HOME=/opt/ant \
    -u "$(id -u):$(id -g)" \
    "$JDK_IMAGE" \
    /opt/ant/bin/ant \
    || die "сборка в контейнере не удалась — смотри вывод выше"
fi
ok "компиляция завершена"

# --- 4. Достаём результат из архива -----------------------------------------
ZIP="$(detect_build_zip "$REPO_DIR" || true)"
[ -n "$ZIP" ] || die "ant отработал, но архив сборки не найден в $REPO_DIR/build.
     Загляни туда:  ls -la $REPO_DIR/build"
ok "архив сборки: $(basename "$ZIP") ($(du -h "$ZIP" | cut -f1))"

require_cmd unzip "Установи:  sudo apt install unzip"

if [ -d "$DIST_DIR/game" ] || [ -d "$DIST_DIR/login" ]; then
  warn "в ./dist уже есть сборка — она будет заменена."
  warn "Правки, сделанные руками в ./dist/*/config, потеряются: настройки"
  warn "должны жить в config/profiles/*.conf, тогда их вернёт make configure."
  confirm "Продолжить?" || die "отменено"

  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT/backups/config-$stamp"
  log "сохраняю прежние конфиги в backups/config-$stamp"
  for part in game login; do
    [ -d "$DIST_DIR/$part/config" ] \
      && cp -r "$DIST_DIR/$part/config" "$ROOT/backups/config-$stamp/$part"
  done
  rm -rf "$DIST_DIR"
fi

mkdir -p "$DIST_DIR"
log "распаковываю сборку в ./dist"
unzip -q -o "$ZIP" -d "$DIST_DIR" || die "не удалось распаковать $ZIP"

# --- 5. Проверяем, что получилось -------------------------------------------
GAME_DIST="$(detect_game_dist "$DIST_DIR" || true)"
LOGIN_DIST="$(detect_login_dist "$DIST_DIR" || true)"

[ -n "$GAME_DIST" ]  || die "в распакованной сборке нет игрового сервера"
[ -n "$LOGIN_DIST" ] || die "в распакованной сборке нет логин-сервера"
[ -f "$DIST_DIR/libs/GameServer.jar" ]  || die "нет dist/libs/GameServer.jar"
[ -f "$DIST_DIR/libs/LoginServer.jar" ] || die "нет dist/libs/LoginServer.jar"

chmod -R u+rwX "$DIST_DIR"
mkdir -p "$DIST_DIR/game/log" "$DIST_DIR/login/log"

ok "игровой сервер: ${GAME_DIST#$ROOT/}"
ok "логин-сервер:   ${LOGIN_DIST#$ROOT/}"
ok "сборка готова: $DIST_DIR"

echo
log "дальше:"
echo "    make configure   # применить профиль x10 и сетевые настройки"
echo "    make db-init     # создать и наполнить базу"
echo "    make up          # запустить"
