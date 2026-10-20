"""Generate the 32-entry DX7 algorithm-routing ROM.

The UART 0x67 payload is six little-endian bytes, OP6 first:
    payload[47:0] = {flags[5], ..., flags[0]}
This ROM has the same layout so command 0x60 (algorithm select) can install
the routing flags atomically instead of relying on a following 0x67 packet.
"""
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from core.fm_patch import ALGORITHM_FLAGS  # noqa: E402


def main():
    assert len(ALGORITHM_FLAGS) == 32, len(ALGORITHM_FLAGS)
    lines = []
    for flags in ALGORITHM_FLAGS:
        assert len(flags) == 6, len(flags)
        word = 0
        for index, value in enumerate(flags):
            assert 0 <= value <= 0xFF
            word |= int(value) << (8 * index)
        lines.append('%012X\n' % word)
    out = ROOT / 'src/generated/fm_algorithm_flags.mem'
    out.write_text(''.join(lines), encoding='ascii', newline='\n')
    print('Wrote %d algorithm rows -> %s' % (len(lines), out))


if __name__ == '__main__':
    main()
