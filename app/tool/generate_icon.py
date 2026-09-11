#!/usr/bin/env python3
"""Отрисовка знака приложения.

Цвета знак берёт из lib/ui/tokens.dart, шрифт — из assets/fonts. Поэтому
иконка не может разойтись с приложением: поменяется акцент в токенах —
перерисуется и знак.

Сначала пробовал рисовать это самим Flutter, чтобы не заводить лишний
инструмент. Не вышло: в headless-тестах кодирование PNG недоступно, и
отрисовка просто висит. Pillow делает то же самое за секунду.

Запуск:  make app-icon
"""
import pathlib
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
SIZE = 1024
LETTER = 'T'


def token(name: str) -> tuple[int, int, int]:
    """Цвет из токенов — чтобы не держать его в двух местах."""
    tokens = (ROOT / 'lib' / 'ui' / 'tokens.dart').read_text()
    m = re.search(rf"{name} = Color\(0xFF([0-9A-Fa-f]{{6}})\)", tokens)
    if not m:
        sys.exit(f'не нашёл {name} в lib/ui/tokens.dart')
    h = m.group(1)
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def brand_color() -> tuple[int, int, int]:
    return token('accent')


def ink_color() -> tuple[int, int, int]:
    return token('onAccent')


def draw_mark(background: bool, letter_scale: float) -> Image.Image:
    accent, ink = brand_color(), ink_color()
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    if background:
        # Скругление как у знака на экране входа, только в масштабе.
        draw.rounded_rectangle(
            [(0, 0), (SIZE - 1, SIZE - 1)],
            radius=int(SIZE * 0.22),
            fill=accent + (255,),
        )

    font = ImageFont.truetype(
        str(ROOT / 'assets' / 'fonts' / 'Roboto-Bold.ttf'),
        int(SIZE * letter_scale),
    )
    box = draw.textbbox((0, 0), LETTER, font=font)
    draw.text(
        ((SIZE - (box[2] - box[0])) / 2 - box[0],
         (SIZE - (box[3] - box[1])) / 2 - box[1]),
        LETTER,
        font=font,
        fill=(ink if background else accent) + (255,),
    )
    return img


def main() -> None:
    out = ROOT / 'assets' / 'icon'
    out.mkdir(parents=True, exist_ok=True)

    targets = [
        # Знак целиком: iOS, веб, обычная иконка Android.
        ('app_icon.png', True, 0.52),
        # Адаптивная иконка Android: систему сама обрезает края и накладывает
        # маску, поэтому буква меньше, а фон рисует лаунчер.
        ('app_icon_foreground.png', False, 0.34),
    ]
    for name, background, scale in targets:
        path = out / name
        draw_mark(background, scale).save(path)
        print(f'{path.relative_to(ROOT)} — {path.stat().st_size} байт')


if __name__ == '__main__':
    main()
