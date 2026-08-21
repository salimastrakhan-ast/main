#!/bin/bash
# =============================================================================
#  Управление аккаунтами и персонажами.
#
#      ./scripts/account.sh gm MyChar        # выдать права ГМ персонажу
#      ./scripts/account.sh gm MyChar 0      # снять права
#      ./scripts/account.sh ban  login       # забанить аккаунт
#      ./scripts/account.sh unban login
#      ./scripts/account.sh online           # кто в игре
#      ./scripts/account.sh accounts         # список аккаунтов
#
#  Отдельной команды "создать аккаунт" нет намеренно: при
#  AutoCreateAccounts=True аккаунт заводится сам при первом входе, и пароль
#  хэшируется тем же алгоритмом, что использует сборка. Вставлять хэш руками —
#  верный способ получить "неверный пароль" на ровном месте.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$ROOT/scripts/lib/common.sh"

load_env "$ROOT/.env"
require_cmd docker

COMPOSE=(docker compose -f "$ROOT/docker-compose.yml" --project-directory "$ROOT")

# У Mobius Interlude аккаунты и персонажи лежат в одной базе.
DB="${DB_NAME:-l2jmobius}"
sql_game()  { "${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" \
                --default-character-set=utf8mb4 -N -B "$DB" -e "$1"; }
sql_login() { sql_game "$1"; }

# Имя колонки различается между ревизиями (accesslevel / accessLevel /
# access_level). Спрашиваем у самой базы вместо того, чтобы гадать.
column_of() {
  local db="$1" table="$2" like="$3" result
  result="$("${COMPOSE[@]}" exec -T db mariadb -uroot -p"$DB_ROOT_PASSWORD" -N -B \
    -e "SELECT COLUMN_NAME FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA='$db' AND TABLE_NAME='$table'
          AND REPLACE(LOWER(COLUMN_NAME),'_','') = '$like' LIMIT 1;" 2>/dev/null | tr -d '\r')"
  [ -n "$result" ] || return 1
  printf '%s\n' "$result"
}

# Экранирование для MySQL: сначала обратный слэш, потом кавычка —
# в обратном порядке экранирование само себя съест.
escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/'"'"'/'"'"''"'"'/g'; }

cmd="${1:-help}"
case "$cmd" in
  gm)
    char="${2:?укажи имя персонажа}"
    level="${3:-8}"
    col="$(column_of "$DB" characters accesslevel)" \
      || die "в таблице characters нет колонки уровня доступа — сборка нестандартная"

    affected="$(sql_game "UPDATE characters SET \`$col\` = $level
                          WHERE char_name = '$(escape "$char")';
                          SELECT ROW_COUNT();" | tail -n1)"
    [ "$affected" = "0" ] && die "персонаж '$char' не найден (регистр важен)"

    if [ "$level" = "0" ]; then
      ok "права сняты: $char"
    else
      ok "уровень доступа $level выдан персонажу $char"
      log "Перезайди персонажем, чтобы права применились."
      log "Уровень должен быть описан в dist/game/config/AccessLevels.xml —"
      log "по умолчанию 8 = Head Game Master (команды //admin, //gmlist)."
    fi
    ;;

  ban|unban)
    login="${2:?укажи логин аккаунта}"
    col="$(column_of "$DB" accounts accesslevel)" \
      || die "в таблице accounts нет колонки уровня доступа"
    if [ "$cmd" = "ban" ]; then value="-100"; else value="0"; fi

    affected="$(sql_login "UPDATE accounts SET \`$col\` = $value
                           WHERE login = '$(escape "$login")';
                           SELECT ROW_COUNT();" | tail -n1)"
    [ "$affected" = "0" ] && die "аккаунт '$login' не найден"
    [ "$cmd" = "ban" ] && ok "аккаунт $login забанен" || ok "аккаунт $login разбанен"
    ;;

  online)
    log "персонажи в игре:"
    sql_game "SELECT char_name, level, online FROM characters
              WHERE online > 0 ORDER BY char_name;" \
      | awk 'BEGIN{n=0} {printf "    %-20s ур. %s\n", $1, $2; n++}
             END{ if(n==0) print "    (никого)"; else printf "\n    всего: %d\n", n }'
    ;;

  accounts)
    log "аккаунты:"
    sql_login "SELECT login, lastactive FROM accounts ORDER BY login;" \
      | awk 'BEGIN{n=0} {printf "    %-20s\n", $1; n++}
             END{ if(n==0) print "    (пусто)"; else printf "\n    всего: %d\n", n }'
    ;;

  *)
    sed -n '2,17p' "$0"
    ;;
esac
