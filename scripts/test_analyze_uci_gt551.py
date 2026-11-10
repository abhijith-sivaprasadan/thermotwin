"""Analytic regression tests, not fabricated real-data study results."""
import unittest
import numpy as np

from scripts.analyze_uci_gt551 import (
    COLUMNS, physics_features, fit_normalizer, predict, stats_by_year,
)


class PhysicalConditionsTests(unittest.TestCase):
    def test_reference_air_availability_and_temperature_drop(self):
        fields = {"AT": 15, "AP": 1013.25, "AFDP": 0,
                  "TIT": 1000, "TAT": 500}
        factor, loss, tit_ratio, drop = physics_features(fields)
        self.assertAlmostEqual(factor, 1.0)
        self.assertAlmostEqual(loss, 0.0)
        self.assertAlmostEqual(drop, 500.0 / 1273.15, places=10)
        self.assertAlmostEqual(tit_ratio, 1273.15 / 1400.0, places=10)

    def test_higher_filter_loss_reduces_available_corrected_flow(self):
        base = {"AT": 20, "AP": 1013.25, "AFDP": 0,
                "TIT": 1080, "TAT": 545}
        zero = physics_features(base)[0]
        base["AFDP"] = 5.0
        self.assertLess(physics_features(base)[0], zero)

    def test_inconsistent_thermodynamic_temperatures_rejected(self):
        with self.assertRaisesRegex(ValueError, "Inconsistent"):
            physics_features({"AT": 20, "AP": 1013, "AFDP": 4,
                              "TIT": 500, "TAT": 550})

    def test_empirical_fit_recovers_exact_known_equation(self):
        # This controlled equation verifies regression algebra, not plant truth.
        rng = np.random.default_rng(20261110)
        x = rng.normal(size=(100, len(COLUMNS)))
        y = 125.0 + x @ np.array([2.0, -3.0, 0.7, 1.4])
        mean, scale, beta = fit_normalizer(x, y)
        self.assertLess(float(np.max(np.abs(predict(x, mean, scale, beta)-y))), 1e-10)

    def test_constant_channel_rejected(self):
        x = np.ones((100, len(COLUMNS)))
        y = np.arange(100, dtype=float)
        with self.assertRaisesRegex(ValueError, "Insufficient variation"):
            fit_normalizer(x, y)

    def test_yearly_slope_is_per_original_row_not_fake_time(self):
        info = stats_by_year(np.linspace(0.0, 2.0, 2001), 2014, threshold=10)
        self.assertAlmostEqual(info["residual_slope_per_1000_published_rows"], 1.0, places=10)
        self.assertEqual(info["fraction_above_training_3sigma_in_absolute_residual"], 0.0)


if __name__ == "__main__":
    unittest.main()
