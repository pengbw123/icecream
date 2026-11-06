"""Deterministic fixed-point tables for the RTL 1024-point spectrum analyzer."""
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / 'src' / 'generated'


def write(name, values, width):
    (ROOT / name).write_text(''.join(format(v, '0{}x'.format(width)) + '\n' for v in values), encoding='ascii')


def q15(value):
    return max(-32768, min(32767, round(value * 32768))) & 65535


if __name__ == '__main__':
    # Periodic Hann: coherent gain 1/2, FFT normalized by 1/N.
    write('spectrum_hann.mem', [q15(0.5 - 0.5 * math.cos(2 * math.pi * n / 1024)) for n in range(1024)], 4)
    write('spectrum_twiddle.mem', [(q15(math.cos(2 * math.pi * n / 1024)) << 16) |
                                 q15(math.sin(2 * math.pi * n / 1024)) for n in range(512)], 8)
    # 64 log bands, one FFT bin (~47.68 Hz) through Nyquist (~24.414 kHz).
    # Repeated low-frequency bins deliberately span adjacent columns: the
    # underlying resolution remains Fs/1024; no invented interpolated detail.
    edges = [max(1, min(512, round(2 ** (9 * n / 64)))) for n in range(65)]
    write('spectrum_bands.mem', [(min(511, edges[n]) << 10) |
                               min(511, max(edges[n], edges[n + 1] - 1)) for n in range(64)], 5)
    print('Generated Hann, twiddle and 64 logarithmic band tables')
