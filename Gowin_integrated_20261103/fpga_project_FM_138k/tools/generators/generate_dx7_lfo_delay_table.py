"""Generate Dexed/msfa LFO-delay increments for the FPGA audio rate."""

from __future__ import annotations

from pathlib import Path

SAMPLE_RATE = 48_828.125
BLOCK_SAMPLES = 64
OUTPUT_DIR = Path(__file__).resolve().parents[2] / "src" / "generated"


def increments_for_setting(setting: int) -> tuple[int, int]:
    """Port of msfa Lfo::reset(), preserving unsigned 32-bit wraparound."""
    if not 0 <= setting <= 99:
        raise ValueError("DX7 LFO delay setting must be in the range 0..99")
    unit = int(BLOCK_SAMPLES * 25_190_424 / SAMPLE_RATE + 0.5)
    value = 99 - setting
    if value == 99:
        return 0xFFFFFFFF, 0xFFFFFFFF
    value = (16 + (value & 15)) << (1 + (value >> 4))
    first = (unit * value) & 0xFFFFFFFF
    value &= 0xFF80
    value = max(0x80, value)
    second = (unit * value) & 0xFFFFFFFF
    return first, second


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    first = [increments_for_setting(value)[0] for value in range(100)]
    second = [increments_for_setting(value)[1] for value in range(100)]
    (OUTPUT_DIR / "dx7_lfo_delay_inc.mem").write_text(
        "".join(f"{value:08x}\n" for value in first), encoding="ascii")
    (OUTPUT_DIR / "dx7_lfo_delay_inc2.mem").write_text(
        "".join(f"{value:08x}\n" for value in second), encoding="ascii")
    print(f"Generated 100-entry delay ROMs in {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
