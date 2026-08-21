# Определение структуры исходников и собранной сборки.
# Разные форки и ревизии раскладывают файлы по-разному, поэтому вместо
# зашитых путей ищем по характерным признакам.
# shellcheck shell=bash

# Каталог хроники внутри репозитория эмулятора.
# Признак: каталог верхнего уровня, в имени которого есть Interlude.
# Печатает всех кандидатов, по одному на строку.
detect_chronicle_candidates() {
  local repo="${1:?}"
  find "$repo" -maxdepth 1 -mindepth 1 -type d -iname '*interlude*' \
    -printf '%f\n' 2>/dev/null | sort
}

# Выбирает единственного кандидата. При нескольких — возвращает 2,
# чтобы вызывающий показал список и попросил уточнить.
detect_chronicle_dir() {
  local repo="${1:?}" preferred="${2:-AUTO}"

  if [ -n "$preferred" ] && [ "$preferred" != "AUTO" ]; then
    [ -d "$repo/$preferred" ] || return 1
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

  # Несколько вариантов: предпочитаем "чистый" C6 Interlude, а не Classic.
  local classic_free
  classic_free="$(printf '%s\n' "$candidates" | grep -vi 'classic' || true)"
  if [ "$(printf '%s\n' "$classic_free" | grep -c .)" -eq 1 ]; then
    printf '%s\n' "$classic_free"
    return 0
  fi

  printf '%s\n' "$candidates"
  return 2
}

# Система сборки проекта: ant | maven | gradle | unknown
detect_build_system() {
  local dir="${1:?}"
  if   [ -f "$dir/build.xml" ];     then echo ant
  elif [ -f "$dir/gradlew" ];       then echo gradle
  elif [ -f "$dir/build.gradle" ];  then echo gradle
  elif [ -f "$dir/pom.xml" ];       then echo maven
  else echo unknown
  fi
}

# Каталог собранного LoginServer: содержит config/LoginServer.ini.
detect_login_dist() {
  local root="${1:?}"
  find "$root" -type f -name 'LoginServer.ini' -path '*/config/*' 2>/dev/null \
    | head -n1 | sed 's#/config/.*##'
}

# Каталог собранного GameServer: содержит config/Server.ini.
# Отсеиваем совпадение с логин-сервером — у него тоже бывает Server.ini.
detect_game_dist() {
  local root="${1:?}"
  local candidate
  while IFS= read -r candidate; do
    [ -z "$candidate" ] && continue
    [ -f "$candidate/config/LoginServer.ini" ] && continue
    printf '%s\n' "$candidate"
    return 0
  done < <(find "$root" -type f -name 'Server.ini' -path '*/config/*' 2>/dev/null \
             | sed 's#/config/.*##' | sort -u)
  return 1
}

# Каталог с .sql дампами внутри сборки.
detect_sql_dir() {
  local root="${1:?}" name="${2:?}"   # name: game | login
  local dir
  for dir in "$root/sql/$name" "$root/sql" "$root/db_installer/sql/$name" \
             "$root/tools/sql/$name" "$root/dist/sql/$name"; do
    if [ -d "$dir" ] && compgen -G "$dir/*.sql" >/dev/null 2>&1; then
      printf '%s\n' "$dir"
      return 0
    fi
  done
  # Последняя попытка: любой каталог с .sql внутри, в имени которого есть роль.
  dir="$(find "$root" -type d -iname "*$name*" -exec sh -c \
        'ls "$1"/*.sql >/dev/null 2>&1' _ {} \; -print 2>/dev/null | head -n1)"
  [ -n "$dir" ] && { printf '%s\n' "$dir"; return 0; }
  return 1
}
