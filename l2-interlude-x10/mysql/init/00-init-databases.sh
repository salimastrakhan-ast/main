#!/bin/bash
# Создаёт логин-базу и раздаёт права. Запускается образом MariaDB один раз,
# при первой инициализации тома db-data.
set -euo pipefail

GAME_DB="${L2_DB_GAME:-l2jgs}"
LOGIN_DB="${L2_DB_LOGIN:-l2jls}"
DB_USER="${L2_DB_USER:-l2j}"

echo "[init] создаю базы ${GAME_DB} и ${LOGIN_DB} для пользователя ${DB_USER}"

mariadb --protocol=socket -uroot -p"${MARIADB_ROOT_PASSWORD}" <<SQL
CREATE DATABASE IF NOT EXISTS \`${GAME_DB}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE DATABASE IF NOT EXISTS \`${LOGIN_DB}\`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;

GRANT ALL PRIVILEGES ON \`${GAME_DB}\`.*  TO '${DB_USER}'@'%';
GRANT ALL PRIVILEGES ON \`${LOGIN_DB}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "[init] готово"
