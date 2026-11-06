"""Validate the ALGO page layout: safe margins, wider gap, feedback loop
inside the canvas and not overlapping neighbouring boxes."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
flags = []
for line in (ROOT / 'src/generated/fm_algorithm_flags.mem').read_text().splitlines():
    line = line.strip()
    if len(line) == 12:
        flags.append(bytes.fromhex(line)[::-1])
assert len(flags) == 32

GREEN = (54, 208, 122)
BLUE = (58, 123, 255)
WHITE = (242, 242, 242)
BG = (11, 11, 12)
W, H = 44, 28
LEFT, RIGHT = 26, 440
MIN_GAP = 76


def graph(fs):
    info = []
    for i, f in enumerate(fs):
        info.append({'op': i, 'num': 6 - i, 'in': (f >> 4) & 3,
                     'dest': f & 3, 'add': (f >> 2) & 1,
                     'fb': ((f >> 6) & 3) == 3})
    bus1, bus2 = set(), set()
    edges = []
    for o in info:
        ins = bus1 if o['in'] == 1 else bus2 if o['in'] == 2 else set()
        for src in ins:
            edges.append((src, o['op']))
        if o['dest'] == 1:
            bus1 = (bus1 | {o['op']}) if o['add'] else {o['op']}
        elif o['dest'] == 2:
            bus2 = (bus2 | {o['op']}) if o['add'] else {o['op']}
    carriers = [o['op'] for o in info if o['dest'] == 0]
    return info, edges, carriers


def layout(fs):
    info, edges, carriers = graph(fs)
    depth = {c: 0 for c in carriers}
    for op in range(6):
        depth.setdefault(op, 0)
    for _ in range(8):
        for s, d in edges:
            depth[s] = max(depth[s], depth[d] + 1)
    for o in info:
        if o['dest'] != 0 and depth[o['op']] == 0:
            depth[o['op']] = 1
    pos = {}
    bottom = 206
    cs = sorted(carriers, key=lambda op: 6 - op)
    n = len(cs)
    if n == 1:
        xs = [233]
    else:
        gap = min(92, (RIGHT - LEFT) // (n - 1))
        total = gap * (n - 1)
        x0 = LEFT + (RIGHT - LEFT - total) // 2
        xs = [x0 + i * gap for i in range(n)]
    for op, x in zip(cs, xs):
        pos[op] = [x, bottom]
    for d in range(1, 4):
        ops = [op for op in depth if depth[op] == d]
        if not ops:
            continue
        for op in ops:
            tg = [pos[t][0] for s, t in edges if s == op and t in pos]
            pos[op] = [sum(tg) // len(tg) if tg else 233, bottom - d * 44]
        ops.sort(key=lambda op: (pos[op][0], 6 - op))
        minx = LEFT
        for op in ops:
            pos[op][0] = max(pos[op][0], minx)
            minx = pos[op][0] + MIN_GAP
        lo = min(pos[op][0] for op in ops)
        hi = max(pos[op][0] for op in ops)
        shift = 0
        if hi > RIGHT:
            shift = RIGHT - hi
        if lo + shift < LEFT:
            shift = LEFT - lo
        for op in ops:
            pos[op][0] += shift
    return info, edges, pos, depth


def check(fs, idx):
    info, edges, pos, depth = layout(fs)
    boxes = {}
    for o in info:
        x, y = pos[o['op']]
        boxes[o['op']] = (x - W // 2, y - H // 2, x + W // 2, y + H // 2)
        if boxes[o['op']][0] < 0 or boxes[o['op']][2] > 511:
            return f'algo{idx} box out of canvas: {boxes[o["op"]]}'
        if boxes[o['op']][1] < 0 or boxes[o['op']][3] > 255:
            return f'algo{idx} box vertical out: {boxes[o["op"]]}'
    for o in info:
        if not o['fb']:
            continue
        x, y = pos[o['op']]
        loop = (x + 22, y - 16, x + 46, y + 12)
        if loop[2] > 511 or loop[0] < 0:
            return f'algo{idx} feedback clipped: {loop}'
        for o2 in info:
            if o2['op'] == o['op']:
                continue
            b = boxes[o2['op']]
            if loop[0] < b[2] and loop[2] > b[0] and loop[1] < b[3] and loop[3] > b[1]:
                return f'algo{idx} feedback {o["op"]} overlaps op{o2["op"]}'
    if not [o for o in info if o['dest'] == 0]:
        return f'algo{idx} no carrier'
    return None


errors = []
for i, fs in enumerate(flags, 1):
    err = check(fs, i)
    if err:
        errors.append(err)
print('checked 32 algorithms; errors:', len(errors))
for e in errors[:20]:
    print(' ', e)
