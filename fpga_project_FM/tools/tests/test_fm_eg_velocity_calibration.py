"""Arithmetic checks for the RTL DX7 EG and keyboard calibration constants.

These do not replace an RTL/board PCM comparison; they pin down the integer
rounding rules copied from Dexed/msfa before the tables are synthesized.
"""

import unittest

from tools.generators.generate_dx7_eg_block_step import (
    SR_MULTIPLIER_Q24,
    step_q14,
)


def calibrated_velocity(raw: int, minimum: int = 0x20,
                        maximum: int = 0x5E) -> int:
    if raw <= minimum:
        return 1
    if raw >= maximum:
        return 127
    span = maximum - minimum
    slope_q8 = (126 * 256 + span // 2) // span
    return 1 + (((raw - minimum) * slope_q8 + 128) >> 8)


class Dx7EgAndVelocityArithmeticTests(unittest.TestCase):
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
        for minimum, maximum in ((0x20, 0x5E), (0x18, 0x68), (0x01, 0x7F)):
            values = [calibrated_velocity(raw, minimum, maximum)
                      for raw in range(minimum, maximum + 1)]
            self.assertEqual(values[0], 1)
            self.assertEqual(values[-1], 127)
            self.assertEqual(values, sorted(values))
            self.assertTrue(all(1 <= value <= 127 for value in values))


if __name__ == "__main__":
    unittest.main()
