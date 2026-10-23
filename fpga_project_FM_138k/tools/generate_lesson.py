"""Generate a small, public-domain melody as shared RTL score and reference MIDI.

Time unit: 16 ms; quarter note: 32 units (117.1875 BPM). Two-second lead-in.
No external MIDI packages are needed. Re-run from any directory.
"""
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
PHRASES = [
    [(60,1),(60,1),(67,1),(67,1),(69,1),(69,1),(67,2)],
    [(65,1),(65,1),(64,1),(64,1),(62,1),(62,1),(60,2)],
    [(67,1),(67,1),(65,1),(65,1),(64,1),(64,1),(62,2)],
    [(67,1),(67,1),(65,1),(65,1),(64,1),(64,1),(62,2)],
    [(60,1),(60,1),(67,1),(67,1),(69,1),(69,1),(67,2)],
    [(65,1),(65,1),(64,1),(64,1),(62,1),(62,1),(60,2)],
]

def vlq(n):
    out = [n & 127]
    while n >> 7:
        n >>= 7
        out.insert(0, (n & 127) | 128)
    return bytes(out)

def main():
    score = [n for p in PHRASES for n in p]
    t = 128
    words = []
    midi = b'\x00\xff\x51\x03' + (512000).to_bytes(3, 'big')
    for i, (note, beats) in enumerate(score):
        gate = beats * 32 - 4
        words.append((t << 16) | (gate << 7) | note)
        midi += vlq(128 if i == 0 else 4) + bytes([0x90, note, 96])
        midi += vlq(gate) + bytes([0x80, note, 0])
        t += beats * 32
    (ROOT / 'src/generated/lesson_score.mem').write_text(''.join('%08x\n'%w for w in words+[0]*(128-len(words))),encoding='ascii')
    midi += b'\x00\xff\x2f\x00'
    data = b'MThd' + struct.pack('>IHHH', 6, 0, 1, 32) + b'MTrk' + struct.pack('>I', len(midi)) + midi
    (ROOT / 'docs/lesson_twinkle.mid').write_bytes(data)
    print('%d notes; %.3f s including lead-in' % (len(score), t * .016))

if __name__ == '__main__':
    main()
