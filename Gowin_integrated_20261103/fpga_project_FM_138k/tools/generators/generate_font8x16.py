"""Generate the 8x16 UI font ROM.

The original file was produced by thresholding a 12 px anti-aliased TTF, which
left every glyph only 8 rows tall inside a 16-row cell and broke thin strokes
into isolated pixels.  On the real panel those isolated pixels read as "messy,
disconnected" text.

This generator renders the same monospace face at 15 px (10-row capitals, ~2 px
stems), pins the baseline to row 12 so descenders use rows 13..15, and only
squeezes glyphs wider than the 8 px cell.  Units match the RTL font ROM:
2048 lines, one byte per glyph row, MSB = leftmost pixel,
index = char_code * 16 + row.

Run from anywhere:
    python tools/generators/generate_font8x16.py [--check]
"""
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

FONT_PATH = 'C:/Windows/Fonts/consola.ttf'
FONT_SIZE = 15
THRESHOLD = 90      # 0..255, applied to the anti-aliased mask
BASELINE_ROW = 12   # glyph baseline inside the 16-row cell
CELL_W = 8
CELL_H = 16

ROOT = Path(__file__).resolve().parents[2]


def render_glyph(font, ascent, ch):
    """Return the 16 row bytes of one character cell."""
    canvas = Image.new('L', (32, 32), 0)
    ImageDraw.Draw(canvas).text((0, 0), ch, font=font, fill=255)
    box = canvas.getbbox()
    if box is None:
        return [0] * CELL_H
    glyph = canvas.crop(box)
    if glyph.width > CELL_W:
        glyph = glyph.resize((CELL_W, glyph.height), Image.LANCZOS)
    # box[1] is measured from the top of the line box; the baseline sits at
    # `ascent` from there.  Mapping the baseline to BASELINE_ROW keeps every
    # glyph on one shared scale.
    left = max(0, min(CELL_W - glyph.width, box[0]))
    top = BASELINE_ROW - ascent + box[1]
    cell = Image.new('L', (CELL_W, CELL_H), 0)
    cell.paste(glyph, (left, max(0, min(CELL_H - glyph.height, top))))
    rows = []
    for y in range(CELL_H):
        value = 0
        for x in range(CELL_W):
            if cell.getpixel((x, y)) >= THRESHOLD:
                value |= 1 << (7 - x)
        rows.append(value)
    return rows


def main():
    font = ImageFont.truetype(FONT_PATH, FONT_SIZE)
    ascent, descent = font.getmetrics()
    data = []
    for code in range(128):
        ch = chr(code) if code >= 32 else ' '
        data.extend(render_glyph(font, ascent, ch))
    assert len(data) == 128 * CELL_H
    out = ROOT / 'src/generated/font8x16.mem'
    out.write_text(''.join('%02X\n' % v for v in data), encoding='ascii')
    filled = sum(1 for v in data if v)
    print('Generated 8x16 font: %d bytes, %d non-blank rows -> %s' % (len(data), filled, out))
    if '--check' in sys.argv:
        for ch in 'FM SYNTH ACG720 E.PIANO 1 PRESET VOLUME XY DELAY AUTO ON':
            if ch == ' ':
                continue
            rows = data[ord(ch) * 16:(ord(ch) + 1) * 16]
            print('--- %r' % ch)
            for r in rows:
                print('   ' + ''.join('#' if (r >> (7 - b)) & 1 else '.' for b in range(8)))


if __name__ == '__main__':
    main()
