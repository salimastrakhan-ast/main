#!/usr/bin/env python3
"""Контактный лист: все кадры одного клиента одной картинкой.

Двадцать отдельных файлов подряд смотреть невозможно — глаз теряет, что с
чем сравнивать. Лист ставит экраны в ряд и подписывает каждый, а два листа
рядом показывают, совпадают клиенты или нет.

Кадры выравниваются по высоте, а не по ширине. Сначала было наоборот, и
лист получился дырявым: телефонный кадр вдвое выше настольного, строка
тянулась по самому высокому, и половина листа уходила в пустоту.

Запуск:  make shots  (вызывается сам)
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
FONT = ROOT / 'app' / 'assets' / 'fonts' / 'Manrope-SemiBold.ttf'

# Цвета листа — из той же палитры, что и приложение: лист не должен спорить
# с тем, что на нём лежит.
PAPER = (11, 17, 23)
INK = (232, 240, 246)
DIM = (138, 155, 176)
LINE = (36, 48, 60)

ROW = 620           # высота кадра на листе
GAP = 26
PAD = 40
LABEL = 32          # строка подписи под кадром
SHEET = 2600        # ширина листа, к которой подгоняются ряды
HEAD = 70


def load(path: pathlib.Path) -> Image.Image:
    img = Image.open(path).convert('RGB')
    scale = ROW / img.height
    return img.resize((max(1, round(img.width * scale)), ROW), Image.LANCZOS)


def caption(name: str) -> str:
    """«04-широкий-переписка» → «широкий · переписка»."""
    parts = name.split('-')
    if parts and parts[0].isdigit():
        parts = parts[1:]
    return ' · '.join(parts)


def pack(frames, limit):
    """Раскладывает кадры по рядам, пока ряд влезает в ширину листа."""
    rows, row, width = [], [], 0
    for frame in frames:
        extra = frame[0].width + (GAP if row else 0)
        if row and width + extra > limit:
            rows.append(row)
            row, width = [], 0
            extra = frame[0].width
        row.append(frame)
        width += extra
    if row:
        rows.append(row)
    return rows


def sheet(client_dir: pathlib.Path, out: pathlib.Path) -> None:
    files = sorted(client_dir.glob('*.png'))
    if not files:
        print(f'в {client_dir} кадров нет')
        return

    frames = [(load(p), caption(p.stem)) for p in files]
    limit = SHEET - PAD * 2
    rows = pack(frames, limit)

    width = SHEET
    height = PAD * 2 + HEAD + len(rows) * (ROW + LABEL) + GAP * (len(rows) - 1)

    canvas = Image.new('RGB', (width, height), PAPER)
    draw = ImageDraw.Draw(canvas)

    title_font = ImageFont.truetype(str(FONT), 34)
    label_font = ImageFont.truetype(str(FONT), 19)

    draw.text((PAD, PAD - 8), client_dir.name, font=title_font, fill=INK)
    draw.text((PAD, PAD + 32), f'{len(frames)} экранов', font=label_font, fill=DIM)

    y = PAD + HEAD
    for row in rows:
        x = PAD
        for img, text in row:
            canvas.paste(img, (x, y))
            draw.rectangle([x, y, x + img.width - 1, y + ROW - 1], outline=LINE, width=1)
            draw.text((x + 2, y + ROW + 8), text, font=label_font, fill=DIM)
            x += img.width + GAP
        y += ROW + LABEL + GAP

    out.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(out)
    print(f'{out} — {width}×{height}, {len(frames)} кадров')


def main() -> None:
    shots = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ROOT / 'docs' / 'shots')
    if not shots.exists():
        sys.exit(f'нет папки {shots} — сначала make shots')
    for client in sorted(p for p in shots.iterdir() if p.is_dir()):
        sheet(client, shots / f'лист-{client.name}.png')


if __name__ == '__main__':
    main()
