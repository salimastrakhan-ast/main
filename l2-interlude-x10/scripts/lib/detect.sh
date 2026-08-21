# Определение структуры исходников и собранной сборки.
# Разные форки и ревизии раскладывают файлы по-разному, поэтому вместо
# зашитых путей ищем по характерным признакам.
# shellcheck shell=bash

# Каталоги верхнего уровня репозитория.
# Через git ls-tree, а не ls: при частичной выкладке (sparse checkout)
# файлов на диске ещё нет, но дерево коммита уже известно.
list_repo_dirs() {
  local repo="${1:?}"
  if [ -d "$repo/.git" ]; then
    git -C "$repo" ls-tree -d --name-only HEAD 2>/dev/null
  else
    find "$repo" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' 2>/dev/null
  fi
}

detect_chronicle_candidates() {
  list_repo_dirs "${1:?}" | grep -i 'interlude' | sort
}

# Выбирает каталог хроники. Код 2 = несколько кандидатов, нужен выбор.
detect_chronicle_dir() {
  local repo="${1:?}" preferred="${2:-AUTO}"

  if [ -n "$preferred" ] && [ "$preferred" != "AUTO" ]; then
    list_repo_dirs "$repo" | grep -qx "$preferred" || return 1
    printf '%s\n' "$preferred"
    return 0
  fi

  local candidates count
  candidates="$(detect_chronicle_candidates "$repo")"
  [ -z "$candidates" ] && return 1

  count="$(printf '%s\n' "$candidates" | grep -c .)"
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$candidates"
    return 0
  fi

  # Несколько вариантов: предпочитаем классический Interlude, а не Classic.
  local classic_free
  classic_free="$(printf '%s\n' "$candidates" | grep -vi 'classic' || true)"
  if [ "$(printf '%s\n' "$classic_free" | grep -c .)" -eq 1 ]; then
    printf '%s\n' "$classic_free"
    return 0
  fi

  printf '%s\n' "$candidates"
  return 2
}

# Система сборки: ant | maven | gradle | unknown
detect_build_system() {
  local dir="${1:?}"
  if   [ -f "$dir/build.xml" ];     then echo ant
  elif [ -f "$dir/gradlew" ];       then echo gradle
  elif [ -f "$dir/build.gradle" ];  then echo gradle
  elif [ -f "$dir/pom.xml" ];       then echo maven
  else echo unknown
  fi
}

# Архив, который оставляет после себя ant у Mobius: <репозиторий>/build/*.zip
# (свойство build указывает на ../build, то есть на уровень выше хроники).
detect_build_zip() {
  local repo="${1:?}"
  find "$repo/build" -maxdepth 1 -name '*.zip' -newermt '-1 day' 2>/dev/null \
    | sort | tail -n1
}

# Каталог собранного GameServer.
# Признак — стартовый скрипт: имена конфигов у разных хроник разъезжаются,
# а GameServerTask.sh лежит на месте уже много лет.
detect_game_dist() {
  local root="${1:?}" hit
  hit="$(find "$root" -maxdepth 3 -name 'GameServerTask.sh' 2>/dev/null | head -n1)"
  [ -n "$hit" ] && { dirname "$hit"; return 0; }

  # Запасной признак: только у игрового сервера есть config/Rates.ini.
  hit="$(find "$root" -maxdepth 4 -path '*/config/Rates.ini' 2>/dev/null | head -n1)"
  [ -n "$hit" ] && { printf '%s\n' "${hit%/config/Rates.ini}"; return 0; }
  return 1
}

# Каталог собранного LoginServer.
detect_login_dist() {
  local root="${1:?}" hit
  hit="$(find "$root" -maxdepth 3 -name 'LoginServerTask.sh' 2>/dev/null | head -n1)"
  [ -n "$hit" ] && { dirname "$hit"; return 0; }

  hit="$(find "$root" -maxdepth 3 -name 'LoginServer.jar' 2>/dev/null | head -n1)"
  [ -n "$hit" ] && { printf '%s\n' "$(dirname "$(dirname "$hit")")/login"; return 0; }
  return 1
}

# Каталог с .sql дампами. У Mobius это dist/db_installer/sql/{game,login}.
detect_sql_dir() {
  local root="${1:?}" name="${2:?}"
  local dir
  for dir in "$root/db_installer/sql/$name" "$root/sql/$name" "$root/sql" \
             "$root/tools/sql/$name"; do
    if [ -d "$dir" ] && compgen -G "$dir/*.sql" >/dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
  done

  dir="$(find "$root" -type d -name "$name" -path '*sql*' 2>/dev/null \
          | while IFS= read -r d; do
              compgen -G "$d/*.sql" >/dev/null 2>&1 && { printf '%s\n' "$d"; break; }
            done)"
  [ -n "$dir" ] && { printf '%s\n' "$dir"; return 0; }
  return 1
}

# Мажорная версия javac (например 25) или ничего.
# Берём номер только из строки вида "javac 25.0.3": JVM может допечатать
# в тот же поток посторонние строки (JAVA_TOOL_OPTIONS, предупреждения),
# и они содержат цифры, которые легко принять за версию.
javac_major() {
  command -v javac >/dev/null 2>&1 || return 1
  local line
  line="$(javac -version 2>&1 | grep -oE '^javac [0-9]+' | head -n1)"
  [ -n "$line" ] || return 1
  printf '%s\n' "${line#javac }"
}
