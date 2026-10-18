"""Arithmetic checks for the RTL DX7 EG and keyboard calibration constants.

These do not replace an RTL/board PCM comparison; they pin down the integer
rounding rules copied from Dexed/msfa before the tables are synthesized.
"""

import unittest
from pathlib import Path
from random import Random

from generators.generate_dx7_ams_attenuation import attenuation_q15
from generators.generate_dx7_eg_block_step import (
    SR_MULTIPLIER_Q24,
    step_q14,
)


def calibrated_velocity(raw: int, minimum: int = 0x00,
                        maximum: int = 0x5A) -> int:
    if raw <= minimum:
        return 0
    if raw >= maximum:
        return 127
    span = maximum - minimum
    slope_q8 = (127 * 256 + span // 2) // span
    return (((raw - minimum) * slope_q8 + 128) >> 8)


class Dx7EgAndVelocityArithmeticTests(unittest.TestCase):
    def test_eg_direct_stage_completion_matches_saturated_level(self) -> None:
        rng = Random(0xD77)
        for _ in range(5000):
            current = rng.randrange(0, (4095 << 14) + 1)
            target = rng.randrange(16 << 14, (4095 << 14) + 1)
            step = rng.randrange(0, 0xCA4F43 + 1)
            rising = target > current
            if rising:
                origin = max(current, 1716 << 14)
                factor = max(1, ((17 << 22) - origin) >> 22)
                wide = origin + step * factor
                next_level = min(wide, target)
                reached = wide >= target
            else:
                next_level = max(current - step, target)
                reached = current <= target + step
            self.assertEqual(reached, next_level == target)

    def test_ams_rom_is_complete_and_monotonic(self) -> None:
        rom = Path(__file__).resolve().parents[2] / \
            "src/generated/dx7_ams_attenuation_q15.mem"
        values = [int(line, 16) for line in rom.read_text(encoding="ascii").split()]
        self.assertEqual(len(values), 512)
        self.assertEqual(values, [attenuation_q15(s, d)
                                  for s in range(4) for d in range(128)])
        self.assertTrue(all(value == 0 for value in values[:128]))
        for sensitivity in range(1, 4):
            curve = values[sensitivity * 128:(sensitivity + 1) * 128]
            self.assertEqual(curve, sorted(curve))
            self.assertTrue(all(0 <= value <= 32768 for value in curve))

    def test_eg_qrate_matches_dexed_integer_order(self) -> None:
        for qrate in range(64):
            dexed_inc_q16 = (4 + (qrate & 3)) << (8 + (qrate >> 2))
            dexed_inc_q16 = (dexed_inc_q16 * SR_MULTIPLIER_Q24) >> 24
            self.assertEqual(step_q14(qrate), dexed_inc_q16 >> 2)

    def test_attack_factor_matches_dexed_fractional_rule(self) -> None:
        # Dexed: (((17 << 24) - level_q16) >> 24), with level >= 1716.
        for level_q14 in range(1716 << 14, (4095 << 14) + 1, 1009):
            expected = ((17 << 22) - level_q14) >> 22
            rtl = 16 - (level_q14 >> 22) + int((level_q14 & ((1 << 22) - 1)) == 0)
            self.assertEqual(rtl, expected)

    def test_keyboard_endpoints_and_monotonicity(self) -> None:
        for minimum, maximum in ((0x00, 0x5A), (0x18, 0x68), (0x01, 0x7F)):
            values = [calibrated_velocity(raw, minimum, maximum)
                      for raw in range(minimum, maximum + 1)]
            self.assertEqual(values[0], 0)
            self.assertEqual(values[-1], 127)
            self.assertEqual(values, sorted(values))
            self.assertTrue(all(0 <= value <= 127 for value in values))
        self.assertEqual(calibrated_velocity(0x20), 45)
        self.assertEqual(calibrated_velocity(0x5E), 127)


if __name__ == "__main__":
    unittest.main()
