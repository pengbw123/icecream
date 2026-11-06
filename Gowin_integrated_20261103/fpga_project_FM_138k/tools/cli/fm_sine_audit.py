"""Compare the current RTL sine lookup with the actual Dexed/msfa source.

This isolates the oscillator lookup only. It does not assert complete voice or
PCM equivalence, because gain, feedback, envelopes and output scaling differ.
"""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from fm_dx7_diff import _compiler_runtime_flags


PROJECT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_DEXED = Path(r"D:\a_files\dexed-master\dexed-master")


def fpga_sine_q24(phase_q32: int, quarter_table: list[int]) -> int:
    """Mirror the current issue_sine_address/p1_sine RTL, before operator gain."""
    quadrant = (phase_q32 >> 30) & 3
    index = (phase_q32 >> 21) & 511
    address = 511 - index if quadrant & 1 else index
    value = quarter_table[address]
    return (-value if quadrant & 2 else value) << 9


def interpolated_sine_q24(phase_q32: int, quarter_table: list[int]) -> int:
    """Model the proposed packed base/delta ROM and 11-bit interpolation."""
    quadrant = (phase_q32 >> 30) & 3
    index = (phase_q32 >> 21) & 511
    address = 511 - index if quadrant & 1 else index
    base = quarter_table[address]
    following = quarter_table[address + 1] if address < 511 else 32767
    delta = following - base
    fraction = (phase_q32 >> 10) & 2047
    value = (base + delta - ((delta * fraction) >> 11)
             if quadrant & 1 else base + ((delta * fraction) >> 11))
    return (-value if quadrant & 2 else value) << 9


def dexed_sine_values(dexed_root: Path, phases_q32: list[int]) -> list[int]:
    msfa = dexed_root / "source" / "msfa"
    compiler = shutil.which("g++")
    if not compiler:
        raise FileNotFoundError("g++ is required to build the Dexed sine adapter")
    if not (msfa / "sin.cc").is_file():
        raise FileNotFoundError(f"Dexed source not found: {msfa / 'sin.cc'}")
    adapter = PROJECT_DIR / "tools/fm_validation/dexed_sine_reference.cpp"
    with tempfile.TemporaryDirectory(prefix="fm_sine_audit_") as directory:
        executable = Path(directory) / ("reference.exe" if sys.platform == "win32"
                                        else "reference")
        command = [compiler, *_compiler_runtime_flags(compiler), "-std=c++17",
                   "-O2", "-I", str(msfa), str(adapter), str(msfa / "sin.cc"),
                   "-o", str(executable)]
        built = subprocess.run(command, capture_output=True, text=True)
        if built.returncode:
            raise RuntimeError(built.stderr.strip() or built.stdout.strip())
        phase_bytes = struct.pack(f"<{len(phases_q32)}I", *phases_q32)
        result = subprocess.run([str(executable)], input=phase_bytes,
                                capture_output=True, check=True)
    if len(result.stdout) != len(phases_q32) * 4:
        raise ValueError("Dexed sine adapter returned an unexpected byte count")
    return list(struct.unpack(f"<{len(phases_q32)}i", result.stdout))


def audit_sine(dexed_root: Path = DEFAULT_DEXED, samples: int = 16384) -> dict:
    if samples < 1024 or samples > 262144 or samples & (samples - 1):
        raise ValueError("samples must be a power of two in [1024, 262144]")
    rom = PROJECT_DIR / "src/generated/additive_sine_quarter_512.mem"
    quarter_table = [int(line, 16) for line in rom.read_text("ascii").split()]
    if len(quarter_table) != 512:
        raise ValueError("expected exactly 512 quarter-wave ROM entries")
    phases = [index * (1 << 32) // samples for index in range(samples)]
    reference = dexed_sine_values(dexed_root, phases)
    errors = [fpga_sine_q24(phase, quarter_table) - expected
              for phase, expected in zip(phases, reference)]
    interpolated_errors = [interpolated_sine_q24(phase, quarter_table) - expected
                           for phase, expected in zip(phases, reference)]
    worst = max(range(samples), key=lambda index: abs(errors[index]))
    return {
        "samples": samples,
        "reference": str(dexed_root / "source/msfa/sin.cc"),
        "rtl_rom": str(rom),
        "max_error_q24": abs(errors[worst]),
        "max_error_percent_of_full_scale": round(
            100 * abs(errors[worst]) / (1 << 24), 6),
        "rms_error_percent_of_full_scale": round(
            100 * math.sqrt(sum(error * error for error in errors) / samples)
            / (1 << 24), 6),
        "worst_phase_q32": f"0x{phases[worst]:08X}",
        "worst_reference_q24": reference[worst],
        "worst_rtl_q24": fpga_sine_q24(phases[worst], quarter_table),
        "interpolated_max_error_percent_of_full_scale": round(
            100 * max(map(abs, interpolated_errors)) / (1 << 24), 6),
        "interpolated_rms_error_percent_of_full_scale": round(
            100 * math.sqrt(sum(error * error for error in interpolated_errors)
                            / samples) / (1 << 24), 6),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dexed", type=Path, default=DEFAULT_DEXED)
    parser.add_argument("--samples", type=int, default=16384)
    args = parser.parse_args()
    print(json.dumps(audit_sine(args.dexed, args.samples),
                     ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
