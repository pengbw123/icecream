"""Render the real firmware's character/palette/graph write logs (not a mock).

Run tb_touch_ui first, then pass --time in simulation ns, --page 0..8 and
--out. Page 8 is the pitch-EG viewport; page 3 is six operator envelopes.
Requires Pillow. Live scope/keys are verified separately by tb_rgb_visualizer.
"""
import argparse
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def records(name, limit):
    path = ROOT / 'tmp' / name
    if path.exists():
        for line in path.read_text().splitlines():
            fields = line.split()
            if len(fields) == 3:
                address, value, time = map(int, fields)
                if limit is None or time <= limit:
                    yield address, value


def render(limit, page, prefix=''):
    def capture(name):
        return records(prefix + name, limit)
    palette = dict(capture('menu_palette.txt'))
    if len(palette) != 16:
        raise ValueError('Need all 16 palette writes from the real firmware')
    # Match the panel's RGB565 output quantization.
    def color(index):
        value = palette[index]
        r, g, b = (value >> 16) & 255, (value >> 8) & 255, value & 255
        return (r & 248) | (r >> 5), (g & 252) | (g >> 6), (b & 248) | (b >> 5)
    image = Image.new('RGB', (800, 480), color(0))
    px = image.load()
    if page == 1:
        for address, value in dict(capture('algo_map.txt')).items():
            for k in range(4):
                x, y = (address * 4 + k) % 512, (address * 4 + k) // 512
                cls = (value >> (k * 2)) & 3
                if cls and y < 256:
                    px[272+x, 144+y] = color({1:14, 2:5, 3:1}[cls])
    if page == 3:
        levels = dict(capture('eg6_panels.txt'))
        for panel in range(6):
            x0, y0 = 16 + (panel % 3)*256, 208 + (panel // 3)*112
            for x in range(240):
                lx = min(127, x*17//32)
                top = 6 + (255-levels.get(panel*128+lx, 0))*64//256
                for y in range(80):
                    cls = 2 if y == top or y == top+1 else 0
                    if x in (0,1,238,239) or y in (0,1,79):
                        cls = 1
                    if cls:
                        px[x0+x,y0+y] = color(2 if cls == 1 else 4)
                    elif lx % 32 == 0 or y-6 in (0,22,44,66,88):
                        px[x0+x,y0+y] = color(11)
    if page == 8:
        levels = dict(capture('eg_curve.txt'))
        for x in range(512):
            top = (255-levels.get(x//2, 0))*207//256
            for y in range(208):
                if abs(y-top) <= 1:
                    px[272+x,192+y] = color(4)
                elif ((x//2)%64 == 0 or y in (0,128,207)):
                    px[272+x,192+y] = color(11)
    font = [int(v,16) for v in (ROOT/'src/generated/font8x16.mem').read_text().split()]
    for address, data in dict(capture('menu_cells.txt')).items():
        row, col = address >> 7, address & 127
        if row >= 30 or col >= 100:
            continue
        attr, pal, ch = (data >> 12)&15, (data >> 8)&15, data&127
        for y in range(16):
            for x in range(8):
                on = (font[ch*16+y] >> (7-x))&1 or bool(attr&2 and y >= 14)
                if attr&8:
                    ink = color(9 if attr&1 else 1) if on else color(pal)
                elif attr&4:
                    ink = color(pal)
                elif attr&1:
                    ink = color(0) if on else color(pal)
                elif on:
                    ink = color(pal)
                else:
                    continue
                px[col*8+x,row*16+y] = ink
    return image


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--time', type=int)
    parser.add_argument('--page', type=int, required=True)
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--prefix', default='', help='Capture file prefix, e.g. arp_ or seq_')
    args = parser.parse_args()
    render(args.time, args.page, args.prefix).save(args.out)
    print(args.out)
