"""Generate Dexed/msfa-style AMS attenuation for the FPGA's Q8 LFO depth.

The ROM captures Dx7Note::compute's nonlinear exp() mapping and the four
ampmodsenstab values. The LFO depth index is the existing FPGA quantity
round(lfo_unipolar * patch_AMD * fade / 256**2), so its normalized Q24
equivalent is approximately depth/99. This remains an approximation to the
continuous msfa LFO, but removes the much larger linear-AMS error.
"""

import math
from pathlib import Path


OUTPUT = Path(__file__).resolve().parents[2] / "src/generated/dx7_ams_attenuation_q15.mem"
SENSITIVITY = (0, 4342338, 7171437, 16777216)


def attenuation_q15(sensitivity: int, depth: int) -> int:
    if sensitivity == 0:
        return 0
    amd_mod_q24 = (min(depth, 99) * (1 << 24) + 49) // 99
    sensamp = (amd_mod_q24 * SENSITIVITY[sensitivity]) >> 24
    pt = int(math.exp(sensamp / 262144.0 * 0.07 + 12.2))
    return min(32768, (pt + 256) >> 9)


def main() -> None:
    OUTPUT.write_text(
        "\n".join(f"{attenuation_q15(sens, depth):04X}"
                  for sens in range(4) for depth in range(128)) + "\n",
        encoding="ascii",
    )
    print(f"Wrote {OUTPUT} (4 sensitivities x 128 depth codes)")


if __name__ == "__main__":
    main()
