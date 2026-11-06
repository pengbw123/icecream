"""Generate the Dexed/msfa operator EG increment for a 64-sample block.

The EG state in fm_poly_synth is Q14; Dexed's Env::level_ is Q16. Dexed
truncates its sample-rate multiplier to Q24 before scaling each Q16 step.
Apply those truncations in the same order here.
"""

from pathlib import Path


SAMPLE_RATE = 50_000_000 / 1024
SR_MULTIPLIER_Q24 = int(44_100 / SAMPLE_RATE * (1 << 24))
OUTPUT = Path(__file__).resolve().parents[2] / "src/generated/dx7_eg_block_step_q14.mem"


def step_q14(qrate: int) -> int:
    block_increment_q16 = (4 + (qrate & 3)) << (8 + (qrate >> 2))
    return ((block_increment_q16 * SR_MULTIPLIER_Q24) >> 24) >> 2


def main() -> None:
    OUTPUT.write_text("\n".join(f"{step_q14(q):06X}" for q in range(64)) + "\n",
                      encoding="ascii")
    print(f"Wrote {OUTPUT} ({SAMPLE_RATE:g} Hz, multiplier={SR_MULTIPLIER_Q24})")


if __name__ == "__main__":
    main()
