"""Generate the effect parameter tables used by src/audio_fx.v.

  fx_filter_f.mem    100 x signed 16-bit, f = 2*sin(pi*fc/fs) in Q1.14
  fx_filter_q.mem    100 x signed 16-bit, q = 1/Q in Q2.14
  fx_tone_coeff.mem  100 x unsigned 16-bit, one-pole LP coefficient in Q1.15
  fx_level_gain.mem  100 x unsigned 16-bit, 0..1 in Q1.15
  fx_dist_gain.mem   100 x unsigned 8-bit, integer pre-gain 1..32
"""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GEN = ROOT / 'src/generated'
FS = 48828.125
N = 100


def clamp(v, lo, hi):
    return max(lo, min(hi, v))


def hx16(v):
    return f'{v & 0xFFFF:04X}'


def hx8(v):
    return f'{v & 0xFF:02X}'


# Cutoff: 30 Hz .. 8 kHz (Chamberlin SVF must stay below fs/6 for stability)
cut_hz = [30.0 * (8000.0 / 30.0) ** (i / (N - 1)) for i in range(N)]
f_tab = [clamp(round(2.0 * math.sin(math.pi * f / FS) * 16384.0), 1, 32767) for f in cut_hz]

# Q: 0.5 .. 12, k = 1/Q in Q2.14
q_tab = []
for i in range(N):
    q = 0.5 * (24.0 ** (i / (N - 1)))
    q_tab.append(clamp(round((1.0 / q) * 16384.0), 32, 32767))

# Tone one-pole: 500 Hz .. 12 kHz, a = 1 - exp(-2*pi*fc/fs)
tone_tab = []
for i in range(N):
    f = 500.0 * (12000.0 / 500.0) ** (i / (N - 1))
    a = 1.0 - math.exp(-2.0 * math.pi * f / FS)
    tone_tab.append(clamp(round(a * 32768.0), 1, 32767))

level_tab = [clamp(round(i / (N - 1) * 32767.0), 0, 32767) for i in range(N)]
gain_tab = [clamp(1 + round(i * 31.0 / (N - 1)), 1, 32) for i in range(N)]

(GEN / 'fx_filter_f.mem').write_text('\n'.join(hx16(v) for v in f_tab) + '\n')
(GEN / 'fx_filter_q.mem').write_text('\n'.join(hx16(v) for v in q_tab) + '\n')
(GEN / 'fx_tone_coeff.mem').write_text('\n'.join(hx16(v) for v in tone_tab) + '\n')
(GEN / 'fx_level_gain.mem').write_text('\n'.join(hx16(v) for v in level_tab) + '\n')
(GEN / 'fx_dist_gain.mem').write_text('\n'.join(hx8(v) for v in gain_tab) + '\n')

# LFO phase increments: inc = round(freq * 2^32 / fs)
def lfo_inc(freq):
    return int(round(freq * 4294967296.0 / FS)) & 0xFFFFFFFF

chorus_hz = [0.05 * (6.0 / 0.05) ** (i / (N - 1)) for i in range(N)]
phaser_hz = [0.05 * (3.0 / 0.05) ** (i / (N - 1)) for i in range(N)]
(GEN / 'fx_chorus_inc.mem').write_text('\n'.join(f'{lfo_inc(f):08X}' for f in chorus_hz) + '\n')
(GEN / 'fx_phaser_inc.mem').write_text('\n'.join(f'{lfo_inc(f):08X}' for f in phaser_hz) + '\n')
print('generated fx tables:', [p.name for p in GEN.glob('fx_*.mem')])
