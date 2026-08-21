#!/bin/bash
# =============================================================================
#  Скачивает исходники эмулятора и собирает их в ./dist/{game,login}.
#
#  Сборка идёт в контейнере, поэтому на хосте не нужны ни JDK, ни Ant, ни
#  Maven — только Docker. Ключ --local соберёт локальными инструментами.
#
#      ./scripts/build-server.sh              # обычная сборка
#      ./scripts/build-server.sh --update     # подтянуть свежие исходники
#      ./scripts/build-server.sh --local      # собирать без Docker
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
BUILDER_IMAGE="l2-interlude-builder:21"

DO_UPDATE=0
USE_DOCKER=1
while [ $# -gt 0 ]; do
  case "$1" in
    --update) DO_UPDATE=1 ;;
    --local)  USE_DOCKER=0 ;;
    --yes|-y) export ASSUME_YES=1 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "неизвестный аргумент: $1" ;;
  esac
  shift
done

# --- 1. Исходники ------------------------------------------------------------
if [ -n "${L2_SOURCE_LOCAL:-}" ]; then
  [ -d "$L2_SOURCE_LOCAL" ] || die "L2_SOURCE_LOCAL указывает в никуда: $L2_SOURCE_LOCAL"
  REPO_DIR="$L2_SOURCE_LOCAL"
  log "использую локальные исходники: $REPO_DIR"
else
  require_cmd git
  mkdir -p "$SOURCES_DIR"

  if [ ! -d "$REPO_DIR/.git" ]; then
    log "клонирую $L2_SOURCE_REPO (ветка $L2_SOURCE_BRANCH)"
    warn "репозиторий большой — первая загрузка займёт время и несколько ГБ"
    # --filter=blob:none: история без содержимого файлов, скачивается
    # в разы быстрее и весит меньше, чем полный клон.
    git clone --depth 1 --single-branch --filter=blob:none \
        --branch "$L2_SOURCE_BRANCH" "$L2_SOURCE_REPO" "$REPO_DIR" \
      || die "не удалось клонировать репозиторий. Проверь сеть и адрес L2_SOURCE_REPO"
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
  2)
    printf '%s\n' "$CHRONICLE" | sed 's/^/    /'
    die "найдено несколько подходящих хроник (список выше).
     Впиши нужную в .env:  L2_CHRONICLE=<имя каталога>"
    ;;
  *)
    die "не нашёл каталог хроники Interlude в $REPO_DIR.
     Посмотри, что там есть:  ls $REPO_DIR
     и укажи явно:  L2_CHRONICLE=<имя каталога> в .env"
    ;;
esac

SRC="$REPO_DIR/$CHRONICLE"
ok "хроника: $CHRONICLE"

BUILD_SYSTEM="$(detect_build_system "$SRC")"
[ "$BUILD_SYSTEM" = "unknown" ] \
  && die "в $SRC нет ни build.xml, ни pom.xml, ни gradlew — нечем собирать"
ok "система сборки: $BUILD_SYSTEM"

# --- 3. Сборка ---------------------------------------------------------------
build_command() {
  case "$BUILD_SYSTEM" in
    ant)    echo "ant -f build.xml" ;;
    maven)  echo "mvn -B -DskipTests package" ;;
    gradle) echo "sh -c 'chmod +x ./gradlew 2>/dev/null; ./gradlew build -x test'" ;;
  esac
}

log "собираю ($BUILD_SYSTEM). Первый раз это 5-15 минут."
if [ "$USE_DOCKER" = "1" ]; then
  require_cmd docker "Установи Docker или собери локально: --local"

  if ! docker image inspect "$BUILDER_IMAGE" >/dev/null 2>&1; then
    log "готовлю образ-сборщик"
    docker build -q -t "$BUILDER_IMAGE" -f "$ROOT/docker/build.Dockerfile" "$ROOT/docker" >/dev/null
  fi

  # Кэш зависимостей между сборками, иначе Maven/Gradle качают всё заново.
  mkdir -p "$SOURCES_DIR/cache-m2" "$SOURCES_DIR/cache-gradle"

  docker run --rm \
    -v "$REPO_DIR:/work/src" \
    -v "$SOURCES_DIR/cache-m2:/root/.m2" \
    -v "$SOURCES_DIR/cache-gradle:/root/.gradle" \
    -w "/work/src/$CHRONICLE" \
    -e HOME=/root \
    "$BUILDER_IMAGE" \
    bash -lc "$(build_command)" \
    || die "сборка не удалась — смотри вывод выше"
else
  case "$BUILD_SYSTEM" in
    ant)    require_cmd ant ;;
    maven)  require_cmd mvn ;;
    gradle) : ;;
  esac
  ( cd "$SRC" && eval "$(build_command)" ) || die "сборка не удалась"
fi
ok "компиляция завершена"

# --- 4. Раскладываем результат ----------------------------------------------
LOGIN_SRC="$(detect_login_dist "$SRC")"
GAME_SRC="$(detect_game_dist "$SRC" || true)"

[ -n "$LOGIN_SRC" ] || die "не нашёл собранный LoginServer (config/LoginServer.ini) в $SRC"
[ -n "$GAME_SRC" ]  || die "не нашёл собранный GameServer (config/Server.ini) в $SRC"
ok "login: ${LOGIN_SRC#$SRC/}"
ok "game:  ${GAME_SRC#$SRC/}"

if [ -d "$DIST_DIR/game" ] || [ -d "$DIST_DIR/login" ]; then
  warn "в ./dist уже есть сборка. Она будет заменена."
  warn "Правки, сделанные руками в ./dist/*/config, потеряются —"
  warn "именно поэтому настройки живут в config/profiles/*.conf."
  confirm "Продолжить?" || die "отменено"

  stamp="$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$ROOT/backups"
  log "сохраняю прежние конфиги в backups/config-$stamp"
  mkdir -p "$ROOT/backups/config-$stamp"
  for part in game login; do
    [ -d "$DIST_DIR/$part/config" ] \
      && cp -r "$DIST_DIR/$part/config" "$ROOT/backups/config-$stamp/$part"
  done
  rm -rf "$DIST_DIR/game" "$DIST_DIR/login"
fi

mkdir -p "$DIST_DIR"
log "копирую сборку в ./dist"
cp -r "$GAME_SRC"  "$DIST_DIR/game"
cp -r "$LOGIN_SRC" "$DIST_DIR/login"
mkdir -p "$DIST_DIR/game/log" "$DIST_DIR/login/log" "$ROOT/logs/game" "$ROOT/logs/login"

# Стартовые .sh из сборки не нужны — запуском управляет entrypoint контейнера,
# но оставляем их: из них entrypoint читает имя main-класса.
chmod -R u+rwX "$DIST_DIR"

ok "сборка готова: $DIST_DIR"
echo
log "дальше:"
echo "    ./scripts/configure.sh      # применить профиль x10"
echo "    ./scripts/db-setup.sh       # создать и наполнить базы"
echo "    make up                     # запустить сервер"
