import shutil
import tempfile
import unittest
from pathlib import Path

import numpy as np

from cli.fm_dx7_diff import (audit_algorithm_routes, _write_wav16,
                             compare_wavs, make_test_midi, render_msfa_core)


class FmDx7DiffTests(unittest.TestCase):
    def test_midi_stimulus_has_fixed_note_and_release(self):
        midi = make_test_midi(60, 100, 1000)
        self.assertTrue(midi.startswith(b"MThd"))
        self.assertIn(b"\x90\x3c\x64", midi)
        self.assertIn(b"\x80\x3c\x40", midi)
        self.assertTrue(midi.endswith(b"\xff\x2f\x00"))

    def test_identical_wav_has_zero_error(self):
        rate = 48000
        phase = np.arange(rate // 4) * (2 * np.pi * 440 / rate)
        tone = 0.2 * np.sin(phase)
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "same.wav"
            _write_wav16(source, tone, rate)
            report = compare_wavs(source, source, hold_ms=100)
        self.assertEqual(report["regions"]["whole"]["gain_aligned_residual_rms_percent"], 0)
        self.assertEqual(report["regions"]["whole"]["median_80_8000hz_spectral_error_db"], 0)

    def test_level_difference_is_reported_separately_from_timbre(self):
        rate = 48000
        phase = np.arange(rate // 4) * (2 * np.pi * 440 / rate)
        with tempfile.TemporaryDirectory() as directory:
            reference = Path(directory) / "reference.wav"
            board = Path(directory) / "board.wav"
            _write_wav16(reference, 0.4 * np.sin(phase), rate)
            _write_wav16(board, 0.2 * np.sin(phase), rate)
            report = compare_wavs(reference, board)
        whole = report["regions"]["whole"]
        self.assertAlmostEqual(whole["fpga_vs_reference_db"], -6.02, places=1)
        self.assertLess(whole["gain_aligned_residual_rms_percent"], 0.05)

    def test_capture_preroll_is_removed(self):
        rate = 48000
        phase = np.arange(rate // 4) * (2 * np.pi * 440 / rate)
        tone = 0.2 * np.sin(phase)
        with tempfile.TemporaryDirectory() as directory:
            reference = Path(directory) / "reference.wav"
            board = Path(directory) / "board.wav"
            _write_wav16(reference, tone, rate)
            _write_wav16(board, np.r_[np.zeros(rate * 30 // 1000), tone], rate)
            report = compare_wavs(reference, board)
        self.assertGreater(report["fpga_onset_ms"], 25)
        self.assertLess(report["regions"]["whole"]["gain_aligned_residual_rms_percent"],
                        0.1)

    @unittest.skipUnless(shutil.which("g++") and
                         Path(r"D:\a_files\dexed-master\dexed-master\source\msfa\fm_core.cc").is_file(),
                         "local Dexed source and g++ are required")
    def test_unmodified_msfa_core_compiles_and_renders(self):
        root = Path(r"D:\a_files\dexed-master\dexed-master")
        result = render_msfa_core(root, 256, 48828.125, 32, 0,
                                  [440, 0, 0, 0, 0, 0],
                                  [0.25, 0, 0, 0, 0, 0])
        self.assertEqual(result.shape, (256,))
        self.assertGreater(np.max(np.abs(result)), 0)

    @unittest.skipUnless(
        Path(r"D:\a_files\dexed-master\dexed-master\source\msfa\fm_core.cc").is_file(),
        "local Dexed source required")
    def test_all_32_routes_match_dexed_source(self):
        report = audit_algorithm_routes(Path(r"D:\a_files\dexed-master\dexed-master"))
        self.assertEqual(report["matched"], 32)
        self.assertEqual(report["mismatched_algorithms"], [])


if __name__ == "__main__":
    unittest.main()
