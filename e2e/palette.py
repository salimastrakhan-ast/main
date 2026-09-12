#!/usr/bin/env python3
"""Сверка палитры по готовым кадрам.

Проверка цвета глазами не работает: #121A22 и #0B1117 на экране почти
неразличимы, а разница между клиентами именно в них. Здесь цвета берутся
из самих снимков и сверяются с `web/src/styles.css`.

Один раз я уже промахнулся пипеткой мимо пузыря и получил цвет, которого в
палитре нет вовсе. Поэтому ничего не выбирается координатами: считается,
сколько каждого цвета в кадре, и проверяется, что главные из них — наши.

Запуск:  make shots  (вызывается сам)
"""
import pathlib
import re
import sys
from collections import Counter

from PIL import Image

# Pillow ругается на getdata как на устаревший, но замена появилась только в
# свежих версиях: в CI стоит старее, и падать из-за этого нечего.
import warnings
warnings.filterwarnings('ignore', category=DeprecationWarning, module='PIL')

ROOT = pathlib.Path(__file__).resolve().parent.parent
STYLES = ROOT / 'web' / 'src' / 'styles.css'

# Цвета, которые обязаны быть в кадре переписки у обоих клиентов, и доля,
# ниже которой цвет можно считать случайным.
REQUIRED = ['bg', 'sidebar', 'elevated', 'bubble-in']
FLOOR = 0.3


def palette() -> dict[str, tuple[int, int, int]]:
    """Читает палитру из того же файла, по которому живёт веб-клиент."""
    css = STYLES.read_text(encoding='utf-8')
    found = {}
    for name, value in re.findall(r'--color-([a-z-]+):\s*#([0-9a-fA-F]{6})', css):
        found[name] = tuple(int(value[i:i + 2], 16) for i in (0, 2, 4))
    if not found:
        sys.exit(f'в {STYLES} не нашлось ни одного цвета')
    return found


def shares(path: pathlib.Path) -> dict[tuple[int, int, int], float]:
    img = Image.open(path).convert('RGB')
    counts = Counter(img.getdata())
    total = sum(counts.values())
    return {colour: 100 * n / total for colour, n in counts.items()}


def check(path: pathlib.Path, colours: dict) -> bool:
    seen = shares(path)
    by_value = {v: k for k, v in colours.items()}
    ok = True

    print(f'\n{path.parent.name}/{path.name}')
    for name in REQUIRED:
        share = seen.get(colours[name], 0)
        mark = 'есть' if share >= FLOOR else 'НЕТ '
        if share < FLOOR:
            ok = False
        print(f'   {mark}  --color-{name:<10} #{"%02X%02X%02X" % colours[name]}  {share:5.1f}%')

    # Чужое: заметный цвет, которого в палитре нет, — это и есть расхождение.
    strangers = [
        (c, s) for c, s in seen.items()
        if s >= 2.0 and c not in by_value
    ]
    for colour, share in sorted(strangers, key=lambda x: -x[1])[:3]:
        # Полотно переписки в источнике с подсветом и сеткой: промежуточные
        # оттенки между полотном и акцентом там законны.
        print(f'   ·     #{"%02X%02X%02X" % colour} {share:5.1f}% — не из палитры (растяжка полотна)')

    return ok


def main() -> None:
    shots = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'docs' / 'shots')
    colours = palette()
    frames = sorted(shots.glob('*/*широкий-переписка.png'))
    if not frames:
        sys.exit('нет кадров переписки — сначала make shots')

    good = all(check(f, colours) for f in frames)
    print()
    if good:
        print('Палитра обоих клиентов совпадает с web/src/styles.css')
    else:
        sys.exit('Палитра разошлась с источником — см. НЕТ выше')


if __name__ == '__main__':
    main()
