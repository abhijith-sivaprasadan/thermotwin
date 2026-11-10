"""Independent unit/physical-plausibility checks for the TESPy fixture.

These tests deliberately do not depend on TESPy being installed; the CI job
also runs the actual pinned solver separately.
"""
import math
import unittest

from scripts.tespy_rankine_reference import summarize_powers


class PowerConversionTests(unittest.TestCase):
    def test_correct_mw_to_w_and_net(self):
        data = summarize_powers(-13_211_041.39536, 223_585.220627, -13.21104139536, 0.223585220627)
        self.assertAlmostEqual(data["net_power_MW_magnitude"], 12.987456174733, places=8)
        self.assertAlmostEqual(data["net_power_W_magnitude"], 12_987_456.174733, places=3)

    def test_original_bug_rejected(self):
        # The old script treated these values as W although configured as MW.
        with self.assertRaisesRegex(ValueError, "W/MW discrepancy"):
            summarize_powers(-13.21104139536, 0.223585220627, -13.21104139536, 0.223585220627)

    def test_wrong_scale_rejected(self):
        with self.assertRaisesRegex(ValueError, "Implausible"):
            summarize_powers(-13.21104139536, 0.223585220627, -13.21104139536e-6, 0.223585220627e-6)

    def test_reversed_sign_rejected(self):
        with self.assertRaisesRegex(ValueError, "sign convention"):
            summarize_powers(13_000_000, -200_000, 13.0, -0.2)

    def test_non_finite_rejected(self):
        with self.assertRaisesRegex(ValueError, "non-finite"):
            summarize_powers(math.nan, 200_000, math.nan, 0.2)


if __name__ == "__main__":
    unittest.main()
