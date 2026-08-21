#!/usr/bin/env python3
"""
Применяет профиль настроек к конфигам собранного сервера.

Зачем не просто положить готовые Rates.ini поверх сборки:
у каждой ревизии эмулятора свой набор ключей. Файл, скопированный целиком,
затирает новые опции и молча ломает сервер после обновления. Здесь правятся
только конкретные ключи, а про отсутствующие честно сообщается.

Формат профиля (config/profiles/*.conf):

    [game]                          # к какой части сборки применять
    Rates.ini : RateXp        = 10  # обычный ключ: нет в сборке -> предупреждение
    Rates.ini : !RateSp       = 10  # '!' обязательный: нет в сборке -> ошибка
    Rates.ini : ?RateDropItems= 10  # '?' необязательный: нет -> тихо пропустить
    Server.ini: URL = jdbc:mysql://${DB_HOST}/${DB_NAME}   # подстановка из env

Подстановка: ${VAR} и ${VAR:-значение по умолчанию}.
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from dataclasses import dataclass, field
from pathlib import Path

RESET = "\033[0m"
RED = "\033[31m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
DIM = "\033[2m"


def colorize(text: str, color: str, enabled: bool) -> str:
    return f"{color}{text}{RESET}" if enabled else text


class ProfileError(Exception):
    """Ошибка в самом файле профиля — чинится правкой профиля, не сборки."""


@dataclass
class Setting:
    section: str          # game | login
    filename: str         # Rates.ini, Custom/Foo.ini
    key: str
    value: str
    requirement: str      # required | normal | optional
    lineno: int


@dataclass
class Report:
    changed: list[str] = field(default_factory=list)
    already: list[str] = field(default_factory=list)
    missing_files: list[str] = field(default_factory=list)
    missing_keys: list[str] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)


ENV_PATTERN = re.compile(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::-([^}]*))?\}")
LINE_PATTERN = re.compile(r"^(?P<file>[^:\[\]]+?)\s*:\s*(?P<key>[^=]+?)\s*=\s*(?P<value>.*)$")


def expand_env(value: str, lineno: int) -> str:
    """Подставляет ${VAR} / ${VAR:-default}; неизвестная переменная — ошибка."""

    def replace(match: re.Match[str]) -> str:
        name, default = match.group(1), match.group(2)
        env_value = os.environ.get(name)
        if env_value is not None and env_value != "":
            return env_value
        if default is not None:
            return default
        raise ProfileError(
            f"строка {lineno}: переменная окружения {name} не задана "
            f"и у неё нет значения по умолчанию"
        )

    return ENV_PATTERN.sub(replace, value)


def parse_profile(path: Path) -> list[Setting]:
    settings: list[Setting] = []
    section = "game"

    for lineno, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue

        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            if section not in ("game", "login"):
                raise ProfileError(
                    f"строка {lineno}: неизвестная секция [{section}], "
                    f"допустимы [game] и [login]"
                )
            continue

        match = LINE_PATTERN.match(line)
        if not match:
            raise ProfileError(
                f"строка {lineno}: не разобрать «{line}». "
                f"Ожидается «Файл.ini : Ключ = значение»"
            )

        key = match.group("key").strip()
        requirement = "normal"
        if key.startswith("!"):
            requirement, key = "required", key[1:].strip()
        elif key.startswith("?"):
            requirement, key = "optional", key[1:].strip()

        if not key:
            raise ProfileError(f"строка {lineno}: пустое имя ключа")

        settings.append(
            Setting(
                section=section,
                filename=match.group("file").strip(),
                key=key,
                value=expand_env(match.group("value").strip(), lineno),
                requirement=requirement,
                lineno=lineno,
            )
        )

    return settings


def locate_config(root: Path, filename: str) -> Path | None:
    """Ищет конфиг: сначала по точному пути, потом по имени во всём config/.

    Разные ревизии раскладывают файлы по подкаталогам (config/Custom, config/main),
    поэтому поиск по basename спасает профиль от привязки к одной версии.
    """
    direct = root / "config" / filename
    if direct.is_file():
        return direct

    basename = Path(filename).name
    matches = sorted((root / "config").rglob(basename)) if (root / "config").is_dir() else []
    return matches[0] if matches else None


def patch_file(path: Path, items: list[Setting], report: Report, *,
               dry_run: bool, color: bool) -> None:
    # newline="" обязателен: без него Python превращает \r\n в \n при чтении,
    # и файл, пришедший из репозитория с windows-переводами строк, целиком
    # переписывается в unix-переводы. Diff распухает, а на Windows конфиг
    # открывается одной строкой.
    with path.open(encoding="utf-8", errors="surrogateescape", newline="") as handle:
        original = handle.read()
    lines = original.splitlines(keepends=True)
    remaining = {s.key.lower(): s for s in items}

    for index, line in enumerate(lines):
        stripped = line.lstrip()
        if stripped.startswith(("#", ";")) or "=" not in line:
            continue

        raw_key = line.split("=", 1)[0]
        setting = remaining.get(raw_key.strip().lower())
        if setting is None:
            continue

        newline = ""
        body = line
        if body.endswith("\r\n"):
            newline, body = "\r\n", body[:-2]
        elif body.endswith("\n"):
            newline, body = "\n", body[:-1]

        current = body.split("=", 1)[1].strip()
        label = f"{path.name}: {setting.key}"

        if current == setting.value:
            report.already.append(label)
        else:
            report.changed.append(f"{label} = {current or '(пусто)'} -> {setting.value}")
            lines[index] = f"{raw_key}= {setting.value}{newline}"

        del remaining[setting.key.lower()]

    for setting in remaining.values():
        label = f"{setting.filename}: {setting.key}"
        if setting.requirement == "required":
            report.errors.append(
                f"{label} — обязательный ключ отсутствует в сборке "
                f"(профиль, строка {setting.lineno})"
            )
        elif setting.requirement == "normal":
            report.missing_keys.append(f"{label} (профиль, строка {setting.lineno})")

    updated = "".join(lines)
    if updated == original:
        return

    if dry_run:
        return

    backup = path.with_suffix(path.suffix + ".orig")
    if not backup.exists():
        shutil.copy2(path, backup)

    tmp = path.with_suffix(path.suffix + ".tmp")
    with tmp.open("w", encoding="utf-8", errors="surrogateescape", newline="") as handle:
        handle.write(updated)
    tmp.replace(path)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Применяет профиль настроек к конфигам сервера L2."
    )
    parser.add_argument("--profile", required=True, help="путь к .conf профилю")
    parser.add_argument("--game-dir", default="dist/game", help="каталог GameServer")
    parser.add_argument("--login-dir", default="dist/login", help="каталог LoginServer")
    parser.add_argument("--dry-run", action="store_true",
                        help="показать изменения, ничего не записывая")
    parser.add_argument("--no-color", action="store_true")
    args = parser.parse_args()

    color = not args.no_color and sys.stdout.isatty()

    profile_path = Path(args.profile)
    if not profile_path.is_file():
        print(colorize(f"Профиль не найден: {profile_path}", RED, color), file=sys.stderr)
        return 2

    try:
        settings = parse_profile(profile_path)
    except ProfileError as exc:
        print(colorize(f"Ошибка в профиле {profile_path}: {exc}", RED, color), file=sys.stderr)
        return 2

    roots = {"game": Path(args.game_dir), "login": Path(args.login_dir)}
    report = Report()

    # Группируем по (секция, файл), чтобы каждый файл читать и писать один раз.
    grouped: dict[tuple[str, str], list[Setting]] = {}
    for setting in settings:
        grouped.setdefault((setting.section, setting.filename), []).append(setting)

    for (section, filename), items in sorted(grouped.items()):
        root = roots[section]
        if not root.is_dir():
            print(colorize(
                f"Каталог {section} не найден: {root} — сначала собери сервер",
                RED, color), file=sys.stderr)
            return 2

        config_path = locate_config(root, filename)
        if config_path is None:
            required = [s for s in items if s.requirement == "required"]
            if required:
                report.errors.append(
                    f"{section}/{filename} — файл отсутствует, "
                    f"а в нём есть обязательные ключи"
                )
            elif any(s.requirement == "normal" for s in items):
                report.missing_files.append(f"{section}/{filename}")
            continue

        patch_file(config_path, items, report, dry_run=args.dry_run, color=color)

    prefix = "[dry-run] " if args.dry_run else ""
    print(f"\n{prefix}Профиль: {profile_path}")
    print(f"  изменено ключей : {len(report.changed)}")
    print(f"  уже совпадало   : {len(report.already)}")

    for line in report.changed:
        print(colorize(f"    ~ {line}", GREEN, color))

    if report.missing_keys:
        print(colorize(f"\n  Ключи, которых нет в этой сборке ({len(report.missing_keys)}):",
                       YELLOW, color))
        for line in report.missing_keys:
            print(colorize(f"    ? {line}", DIM, color))
        print(colorize(
            "    Это нормально, если сборка новее профиля: ключ переименовали.\n"
            "    Сверься с config/profiles/README.md.", DIM, color))

    if report.missing_files:
        print(colorize(f"\n  Файлы, которых нет в сборке ({len(report.missing_files)}):",
                       YELLOW, color))
        for line in report.missing_files:
            print(colorize(f"    ? {line}", DIM, color))

    if report.errors:
        print(colorize(f"\n  ОШИБКИ ({len(report.errors)}):", RED, color))
        for line in report.errors:
            print(colorize(f"    ! {line}", RED, color))
        print(colorize(
            "\n  Обязательные ключи не найдены — профиль не подходит к этой сборке.\n"
            "  Сервер НЕ настроен корректно.", RED, color))
        return 1

    if args.dry_run:
        print("\nНичего не записано (--dry-run).")
    else:
        print(colorize("\nГотово. Резервные копии — рядом, с расширением .orig", GREEN, color))
    return 0


if __name__ == "__main__":
    sys.exit(main())
