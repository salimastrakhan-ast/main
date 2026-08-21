#!/usr/bin/env python3
"""
Прописывает адрес сервера в system/l2.ini клиента.

Отдельным файлом, а не строчкой в скрипте, чтобы это можно было покрыть
тестами: ошибка здесь = клиент стучится не туда, а выглядит это как
"сервер не работает".
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path


def patch(path: Path, address: str) -> str:
    with path.open(encoding="utf-8", errors="surrogateescape", newline="") as handle:
        original = handle.read()

    newline = "\r\n" if "\r\n" in original else "\n"
    lines = original.splitlines(keepends=True)

    for index, line in enumerate(lines):
        if re.match(r"^\s*ServerAddr\s*=", line, re.IGNORECASE):
            ending = "\r\n" if line.endswith("\r\n") else ("\n" if line.endswith("\n") else "")
            lines[index] = f"ServerAddr={address}{ending}"
            updated = "".join(lines)
            action = "обновлён"
            break
    else:
        # Ключа нет: дописываем в секцию [Server], создав её при необходимости.
        section = next(
            (i for i, l in enumerate(lines) if l.strip().lower() == "[server]"), None
        )
        if section is None:
            tail = "" if not lines or lines[-1].endswith(("\n", "\r\n")) else newline
            updated = "".join(lines) + f"{tail}[Server]{newline}ServerAddr={address}{newline}"
            action = "создан вместе с секцией [Server]"
        else:
            lines.insert(section + 1, f"ServerAddr={address}{newline}")
            updated = "".join(lines)
            action = "добавлен в секцию [Server]"

    backup = path.with_suffix(path.suffix + ".orig")
    if not backup.exists():
        shutil.copy2(path, backup)

    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", errors="surrogateescape", newline="") as handle:
        handle.write(updated)
    tmp.replace(path)
    return action


def main() -> int:
    if len(sys.argv) != 3:
        print("использование: set-client-addr.py <путь к l2.ini> <адрес>", file=sys.stderr)
        return 2

    path, address = Path(sys.argv[1]), sys.argv[2].strip()
    if not path.is_file():
        print(f"не найден файл {path}", file=sys.stderr)
        return 1
    if not address:
        print("пустой адрес", file=sys.stderr)
        return 2

    print(f"ServerAddr {patch(path, address)}: {address}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
