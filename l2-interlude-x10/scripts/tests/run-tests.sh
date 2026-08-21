#!/bin/bash
# Прогоняет все тесты стенда.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

status=0
for suite in "$HERE"/test-*.sh; do
  "$suite" || status=1
  echo
done

if [ "$status" -eq 0 ]; then
  printf '\033[32mВсе тесты пройдены.\033[0m\n'
else
  printf '\033[31mЕсть падающие тесты.\033[0m\n'
fi
exit "$status"
