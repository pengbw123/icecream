"""Repeatable DX7 FM A/B cases and digital-audio comparison.

The `core-reference` command compiles the user's unmodified Dexed/msfa FM
kernel sources. It deliberately holds operator gains constant: this is an
isolated test of algorithm routing, sine, gain and feedback, NOT a complete
ROM1A/Dexed voice renderer. `case` creates a fixed MIDI stimulus for comparing
a full Dexed voice against the FPGA after both have selected the same patch.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

TOOLS_DIR = Path(__file__).resolve().parents[1]
PROJECT_DIR = TOOLS_DIR.parent
sys.path.insert(0, str(TOOLS_DIR))


def _vlq(value: int) -> bytes:
    if value < 0:
        raise ValueError("MIDI delta time must be nonnegative")
    data = [value & 0x7F]
    value >>= 7
    while value:
        data.insert(0, 0x80 | (value & 0x7F))
        value >>= 7
    return bytes(data)


def make_test_midi(note: int, velocity: int, hold_ms: int,
                   tail_ms: int = 1500, preroll_ms: int = 250) -> bytes:
    """Type-0 SMF at 120 BPM; no patch-select CC that could affect Dexed."""
    if not (0 <= note <= 127 and 1 <= velocity <= 127 and
            hold_ms >= 1 and tail_ms >= 0 and preroll_ms >= 0):
        raise ValueError("invalid note, velocity, or duration")
    ticks = lambda ms: round(ms * 480 / 500)
    track = bytearray(b"\x00\xff\x51\x03\x07\xa1\x20")
    track += _vlq(ticks(preroll_ms)) + bytes((0x90, note, velocity))
    track += _vlq(ticks(hold_ms)) + bytes((0x80, note, 64))
    track += _vlq(ticks(tail_ms)) + b"\xff\x2f\x00"
    return (b"MThd" + struct.pack(">IHHH", 6, 0, 1, 480) +
            b"MTrk" + struct.pack(">I", len(track)) + bytes(track))


def _write_wav16(path: Path, samples: np.ndarray, sample_rate: int) -> None:
    pcm = np.clip(np.rint(samples * 32767.0), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(pcm.tobytes())


def _read_wav(path: Path) -> tuple[int, np.ndarray]:
    with wave.open(str(path), "rb") as source:
        if source.getcomptype() != "NONE":
            raise ValueError(f"{path}: only uncompressed PCM WAV is supported")
        channels, width, rate, frames = (source.getnchannels(),
                                         source.getsampwidth(),
                                         source.getframerate(),
                                         source.getnframes())
        raw = source.readframes(frames)
    if width == 2:
        values = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    elif width == 3:
        octets = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        values = octets[:, 0] | (octets[:, 1] << 8) | (octets[:, 2] << 16)
        values = ((values ^ 0x800000) - 0x800000).astype(np.float64) / 8388608.0
    elif width == 4:
        values = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    else:
        raise ValueError(f"{path}: use 16-, 24-, or 32-bit integer PCM WAV")
    if channels < 1 or values.size % channels:
        raise ValueError(f"{path}: invalid channel count")
    return rate, values.reshape(-1, channels).mean(axis=1)


def _rms(samples: np.ndarray) -> float:
    return float(np.sqrt(np.mean(samples * samples))) if samples.size else 0.0


def _onset(samples: np.ndarray, sample_rate: int) -> int:
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak < 1e-6:
        raise ValueError("audio is silent")
    # A 100 ms "noise" window can already contain the note when an audio
    # interface has only 20-40 ms latency; use a shorter pre-onset probe.
    noise = _rms(samples[:max(1, sample_rate // 100)])
    threshold = max(peak * 0.015, noise * 5.0, 0.0002)
    above = np.flatnonzero(np.abs(samples) > threshold)
    return int(above[0]) if above.size else 0


def _fine_align(reference: np.ndarray, actual: np.ndarray,
                sample_rate: int) -> tuple[np.ndarray, np.ndarray, int]:
    """Refine onset alignment by at most 10 ms; zero lag means onset-only."""
    size = min(len(reference), len(actual), sample_rate // 8)
    if size < 256:
        raise ValueError("recordings need at least 256 post-onset samples")
    max_lag = min(round(sample_rate * 0.01), size // 4)
    lag_samples, best_score = 0, -1.0
    for candidate in range(-max_lag, max_lag + 1):
        if candidate >= 0:
            a, b = reference[candidate:size], actual[:size - candidate]
        else:
            a, b = reference[:size + candidate], actual[-candidate:size]
        denom = float(np.linalg.norm(a) * np.linalg.norm(b))
        score = abs(float(np.dot(a, b))) / denom if denom else 0.0
        if score > best_score + 1e-12 or (
            abs(score - best_score) <= 1e-12 and abs(candidate) < abs(lag_samples)
        ):
            lag_samples, best_score = candidate, score
    if lag_samples >= 0:
        reference = reference[lag_samples:]
    else:
        actual = actual[-lag_samples:]
    count = min(len(reference), len(actual))
    return reference[:count], actual[:count], lag_samples


def compare_wavs(reference_path: Path, fpga_path: Path,
                 hold_ms: int | None = None) -> dict:
    reference_rate, reference = _read_wav(reference_path)
    fpga_rate, fpga = _read_wav(fpga_path)
    resampled = reference_rate != fpga_rate
    if resampled:
        # Diagnostic only. For a sample-exact claim, capture both digital
        # outputs at the SAME actual rate and avoid this linear resampling.
        positions = np.arange(round(len(fpga) * reference_rate / fpga_rate))
        fpga = np.interp(positions * fpga_rate / reference_rate,
                         np.arange(len(fpga)), fpga)
    reference_onset = _onset(reference, reference_rate)
    fpga_onset = _onset(fpga, reference_rate)
    reference, fpga, fine_lag = _fine_align(
        reference[reference_onset:], fpga[fpga_onset:], reference_rate)
    if _rms(reference) < 1e-7 or _rms(fpga) < 1e-7:
        raise ValueError("one post-onset signal is silent")
    regions = {"whole": (0, len(reference)),
               "attack_0_100ms": (0, round(reference_rate * 0.1))}
    if hold_ms is not None:
        hold = round(reference_rate * hold_ms / 1000)
        regions["held_after_100ms"] = (round(reference_rate * 0.1), hold)
        regions["release_first_500ms"] = (hold, hold + reference_rate // 2)
    results: dict[str, dict] = {}
    for name, (start, end) in regions.items():
        a = reference[start:min(end, len(reference))]
        b = fpga[start:min(end, len(fpga))]
        if len(a) < 128 or _rms(a) < 1e-8 or _rms(b) < 1e-8:
            continue
        ref_rms, fpga_rms = _rms(a), _rms(b)
        gain_fit = float(np.dot(a, b) / max(np.dot(b, b), 1e-30))
        residual = a - gain_fit * b
        correlation = float(np.dot(a, b) /
                            max(np.linalg.norm(a) * np.linalg.norm(b), 1e-30))
        fft_size = min(4096, 1 << (len(a).bit_length() - 1))
        spectrum_a = np.abs(np.fft.rfft(a[:fft_size] * np.hanning(fft_size)))
        spectrum_b = np.abs(np.fft.rfft(b[:fft_size] * np.hanning(fft_size)))
        frequencies = np.fft.rfftfreq(fft_size, 1 / reference_rate)
        band = (frequencies >= 80) & (frequencies <= min(8000, reference_rate / 2))
        spectral_error = float(np.median(np.abs(
            20 * np.log10(np.maximum(spectrum_a[band], 1e-8)) -
            20 * np.log10(np.maximum(abs(gain_fit) * spectrum_b[band], 1e-8)))))
        results[name] = {
            "reference_rms": ref_rms,
            "fpga_rms": fpga_rms,
            "fpga_vs_reference_db": 20 * math.log10(fpga_rms / ref_rms),
            "gain_fit_to_reference": gain_fit,
            "gain_aligned_correlation": correlation,
            "gain_aligned_residual_rms_percent": 100 * _rms(residual) / ref_rms,
            "median_80_8000hz_spectral_error_db": spectral_error,
        }
    return {
        "reference": str(reference_path), "fpga": str(fpga_path),
        "reference_rate_hz": reference_rate, "fpga_rate_hz": fpga_rate,
        "resampled_for_diagnostics": resampled,
        "reference_onset_ms": reference_onset * 1000 / reference_rate,
        "fpga_onset_ms": fpga_onset * 1000 / reference_rate,
        "fine_lag_samples": fine_lag,
        "compared_samples": len(reference), "regions": results,
        "warning": ("Resampling prevents sample-exact conclusions."
                    if resampled else "Waveform correlation still depends on phase and capture latency."),
    }


def _find_dexed_root(requested: Path | None) -> Path:
    candidates = ([requested] if requested else []) + [
        Path(r"D:\a_files\dexed-master\dexed-master"),
        Path(r"D:\a_files\dexed-master"),
    ]
    for root in candidates:
        if root and (root / "source" / "msfa" / "fm_core.cc").is_file():
            return root
    raise FileNotFoundError("Dexed source not found; provide --dexed-root")


def render_msfa_core(dexed_root: Path, samples: int, sample_rate: float,
                     algorithm: int, feedback: int,
                     frequencies: list[float], gains: list[float]) -> np.ndarray:
    msfa = dexed_root / "source" / "msfa"
    sources = [msfa / name for name in
               ("sin.cc", "exp2.cc", "fm_core.cc", "fm_op_kernel.cc")]
    adapter = TOOLS_DIR / "fm_validation" / "dexed_core_reference.cpp"
    compiler = shutil.which("g++")
    if not compiler:
        raise FileNotFoundError("g++ not found; install MinGW-w64 or provide it in PATH")
    with tempfile.TemporaryDirectory(prefix="fm_dx7_ref_") as folder:
        executable = Path(folder) / ("reference.exe" if sys.platform == "win32" else "reference")
        # fm_core.h includes controllers.h but the isolated FmCore uses none
        # of it. Its include guard avoids unrelated JUCE/UI dependencies.
        command = [compiler, "-std=c++17", "-O2", "-D__CONTROLLERS_H",
                   "-I", str(msfa), str(adapter), *map(str, sources),
                   "-o", str(executable)]
        subprocess.run(command, check=True, capture_output=True, text=True)
        result = subprocess.run(
            [str(executable), str(samples), str(sample_rate), str(algorithm),
             str(feedback), ",".join(map(str, frequencies)),
             ",".join(map(str, gains))], check=True, capture_output=True)
    if len(result.stdout) != samples * 4:
        raise ValueError("Dexed adapter returned an unexpected sample count")
    return np.frombuffer(result.stdout, dtype="<i4").copy()


def audit_algorithm_routes(dexed_root: Path) -> dict:
    """Compare all 32 shipped routing rows to the original msfa C++ table."""
    from core.fm_patch import ALGORITHM_FLAGS
    source = (dexed_root / "source" / "msfa" / "fm_core.cc").read_text(
        encoding="utf-8")
    start = source.index("FmCore::algorithms[32] = {")
    end = source.index("};", start)
    rows = re.findall(r"\{\s*\{([^{}]+)\}\s*\}", source[start:end])
    original = [tuple(int(value.strip(), 0) for value in row.split(","))
                for row in rows]
    if len(original) != 32 or any(len(row) != 6 for row in original):
        raise ValueError("could not parse all 32 six-operator msfa algorithms")
    mismatches = [index + 1 for index, (reference, fpga)
                  in enumerate(zip(original, ALGORITHM_FLAGS))
                  if reference != tuple(fpga)]
    return {"reference": str(dexed_root / "source" / "msfa" / "fm_core.cc"),
            "algorithm_count": len(original),
            "matched": 32 - len(mismatches),
            "mismatched_algorithms": mismatches}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    command = parser.add_subparsers(dest="command", required=True)
    case = command.add_parser("case", help="create a fixed MIDI note and manifest")
    case.add_argument("--out", type=Path, required=True)
    case.add_argument("--bank", type=Path)
    case.add_argument("--index", type=int, default=0)
    case.add_argument("--note", type=int, default=60)
    case.add_argument("--velocity", type=int, default=100)
    case.add_argument("--hold-ms", type=int, default=1000)
    case.add_argument("--tail-ms", type=int, default=1500)
    core = command.add_parser("core-reference", help="render isolated original msfa FM core")
    core.add_argument("--out", type=Path, required=True)
    core.add_argument("--dexed-root", type=Path)
    core.add_argument("--algorithm", type=int, default=32)
    core.add_argument("--feedback", type=int, default=0)
    core.add_argument("--sample-rate", type=float, default=48828.125)
    core.add_argument("--seconds", type=float, default=1.0)
    core.add_argument("--freqs", default="440,0,0,0,0,0",
                      help="six Hz values in DX7 operator order 6,5,4,3,2,1")
    core.add_argument("--gains", default="0.25,0,0,0,0,0",
                      help="six linear gains in DX7 operator order 6,5,4,3,2,1")
    audit = command.add_parser("audit", help="compare routing table to Dexed source")
    audit.add_argument("--dexed-root", type=Path)
    compare = command.add_parser("compare", help="compare two captured PCM WAV files")
    compare.add_argument("reference", type=Path)
    compare.add_argument("fpga", type=Path)
    compare.add_argument("--hold-ms", type=int)
    compare.add_argument("--json", type=Path)
    args = parser.parse_args(argv)

    if args.command == "case":
        args.out.mkdir(parents=True, exist_ok=True)
        midi = make_test_midi(args.note, args.velocity, args.hold_ms, args.tail_ms)
        (args.out / "test_note.mid").write_bytes(midi)
        manifest: dict = {"note": args.note, "velocity": args.velocity,
                          "hold_ms": args.hold_ms, "tail_ms": args.tail_ms,
                          "preroll_ms": 250}
        if args.bank:
            from core.fm_patch import load_syx
            patches = load_syx(args.bank)
            if not (0 <= args.index < len(patches)):
                raise ValueError("bank index out of range")
            manifest.update(bank=str(args.bank), preset_index=args.index,
                            preset_name=patches[args.index]["name"],
                            algorithm=patches[args.index]["algorithm"],
                            bank_sha256=hashlib.sha256(args.bank.read_bytes()).hexdigest())
        (args.out / "case.json").write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"Created {args.out / 'test_note.mid'} and case.json")
        return 0
    if args.command == "core-reference":
        frequencies = [float(value) for value in args.freqs.split(",")]
        gains = [float(value) for value in args.gains.split(",")]
        if len(frequencies) != 6 or len(gains) != 6 or args.seconds <= 0:
            raise ValueError("need six frequencies, six gains, and positive duration")
        dexed_root = _find_dexed_root(args.dexed_root)
        samples = round(args.seconds * args.sample_rate)
        internal = render_msfa_core(dexed_root, samples, args.sample_rate,
                                    args.algorithm, args.feedback,
                                    frequencies, gains)
        args.out.parent.mkdir(parents=True, exist_ok=True)
        # Preserve full 32-bit reference for later exact-stage comparisons.
        raw_path = args.out.with_suffix(".i32le")
        raw_path.write_bytes(internal.astype("<i4").tobytes())
        _write_wav16(args.out, internal.astype(np.float64) / (1 << 24),
                     round(args.sample_rate))
        manifest = {"scope": "constant-gain msfa core, NOT full DX7 voice",
                    "dexed_root": str(dexed_root), "algorithm": args.algorithm,
                    "feedback": args.feedback, "sample_rate_exact": args.sample_rate,
                    "wav_header_rate_integer": round(args.sample_rate),
                    "frequencies_op6_to_op1": frequencies,
                    "gains_op6_to_op1": gains, "samples": samples,
                    "msfa_source_sha256": {
                        name: hashlib.sha256((dexed_root / "source" / "msfa" / name)
                                             .read_bytes()).hexdigest()
                        for name in ("fm_core.cc", "fm_op_kernel.cc", "sin.cc", "exp2.cc")}}
        args.out.with_suffix(".json").write_text(
            json.dumps(manifest, indent=2), encoding="utf-8")
        print(f"Rendered {args.out} ({samples} samples); raw={raw_path}")
        return 0
    if args.command == "audit":
        report = audit_algorithm_routes(_find_dexed_root(args.dexed_root))
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0 if not report["mismatched_algorithms"] else 1
    report = compare_wavs(args.reference, args.fpga, args.hold_ms)
    encoded = json.dumps(report, indent=2, ensure_ascii=False)
    if args.json:
        args.json.parent.mkdir(parents=True, exist_ok=True)
        args.json.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (ValueError, FileNotFoundError, subprocess.CalledProcessError,
            wave.Error) as exc:
        print(f"FM validation failed: {exc}", file=sys.stderr)
        raise SystemExit(2)
