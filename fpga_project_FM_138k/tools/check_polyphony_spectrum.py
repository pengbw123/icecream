"""Prepare a known 32-tone FFT fixture or verify production RTL PCM capture."""
import argparse
import json
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
FS = 50_000_000 / 1024
NOTES = np.arange(96, 128)
FREQUENCIES = 440 * 2 ** ((NOTES - 69) / 12)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--generate", action="store_true")
    args = parser.parse_args()
    tmp = ROOT / "tmp"
    tmp.mkdir(exist_ok=True)
    if args.generate:
        phase = 2 * np.pi * np.arange(1024)[:, None] * FREQUENCIES[None, :] / FS
        samples = np.rint(700 * np.sin(phase).sum(axis=1)).astype(int)
        (tmp / "polyphony_fft_input.mem").write_text(
            "".join(f"{int(v) & 65535:04x}\n" for v in samples), encoding="ascii"
        )
        bins = np.rint(FREQUENCIES * 1024 / FS).astype(int)
        (tmp / "polyphony_expected_bins.mem").write_text(
            "".join(f"{int(v):03x}\n" for v in bins), encoding="ascii"
        )
        print("PASS generated 32-tone fixture: MIDI 96..127, no PCM recording")
        return

    pcm = np.loadtxt(tmp / "polyphony_pcm.txt")
    assert len(pcm) == 4096, "Incomplete production audio capture"
    peak = float(np.max(np.abs(pcm)))
    assert 2 < peak < 32767, "Silent or clipped production output"
    spectrum = np.abs(np.fft.rfft(pcm * np.hanning(len(pcm))))
    expected = np.rint(FREQUENCIES * len(pcm) / FS).astype(int)
    measured = []
    for note, frequency, center in zip(NOTES, FREQUENCIES, expected):
        found = int(center - 2 + np.argmax(spectrum[center - 2:center + 3]))
        assert abs(found - center) <= 1, f"Wrong frequency for note {note}"
        assert spectrum[found] >= 0.1 * np.max(spectrum), f"Missing note {note}"
        assert spectrum[found] > spectrum[found - 1] and spectrum[found] > spectrum[found + 1]
        measured.append({"note": int(note), "hz": float(frequency), "bin": found})
    assert len({v["bin"] for v in measured}) == 32
    report = {
        "sample_rate_hz": FS, "samples": len(pcm), "peak_pcm": peak,
        "independent_peaks": len(measured), "frequencies": measured,
        "evidence": "production FM32 RTL simulation PCM, sine patch configured by test",
        "physical_board_verified": False,
    }
    (tmp / "polyphony_spectrum_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(f"PASS production FM32 PCM: 32 independent peaks, no silence/clipping, Fs={FS} Hz")


if __name__ == "__main__":
    main()
