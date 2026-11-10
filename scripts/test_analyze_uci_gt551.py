"""Analytic regression tests, not fabricated real-data study results."""
import unittest
import numpy as np

from scripts.analyze_uci_gt551 import (
    COLUMNS, physics_features, fit_normalizer, predict, stats_by_year,
    lag1_within_year, covariate_support, forward_year_backtests, moving_block_sensitivity,
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



    def test_adjacent_correlation_never_connects_year_boundary(self):
        # Mathematically controlled sequences, not imported physical observations.
        rows = {2011: np.arange(8., dtype=float),
                2012: np.arange(100., 108., dtype=float)}
        self.assertAlmostEqual(lag1_within_year(rows), 1.0, places=12)
        raw_joined = np.concatenate([rows[2011], rows[2012]])
        joined_corr = np.corrcoef(raw_joined[:-1], raw_joined[1:])[0, 1]
        self.assertLess(joined_corr, 0.98)

    def test_support_extrapolation_uses_train_only(self):
        training = np.array([[0., 0., 0., 0.], [1., 1., 1., 1.],
                             [2., 2., 2., 2.]])
        hold = np.array([[1., 1., 1., 1.], [3., 1., 1., 1.],
                         [1., -1., 1., 1.]])
        report = covariate_support(training, hold)
        self.assertAlmostEqual(report["heldout_fraction_outside_any_feature"], 2/3)
        self.assertAlmostEqual(
            report["heldout_fraction_outside_by_feature"][COLUMNS[0]], 1/3)

    def test_forward_development_checks_leave_final_years_untouched(self):
        rng = np.random.default_rng(1234)
        truth = np.array([1.0, -1.0, 2.0, 0.5])
        per_year = {}
        for year in range(2011, 2016):
            x = rng.normal(size=(70, len(COLUMNS)))
            # Fortran/unit-test algebra only, not manufactured study readings.
            y = 40 + x @ truth
            per_year[year] = (x, y)
        folds = forward_year_backtests(per_year)
        self.assertEqual(set(folds), {"2012", "2013"})
        self.assertEqual(folds["2012"]["fit_years"], [2011])
        self.assertEqual(folds["2013"]["fit_years"], [2011, 2012])
        self.assertLess(folds["2013"]["adjusted_rmse_source_TEY_units"], 1e-10)

    def test_block_resampling_preserves_constant_analytic_identity(self):
        # A constant mathematical identity has identical bias and RMSE under
        # all moving-block resamplings; tests numerical reproducibility only.
        data = {2014: np.full(130, 3.0), 2015: np.full(131, 3.0)}
        a = moving_block_sensitivity(data, block_lengths=(8, 16),
                                     replicates=20, seed=49)
        b = moving_block_sensitivity(data, block_lengths=(8, 16),
                                     replicates=20, seed=49)
        self.assertEqual(a, b)
        for row in a["sensitivity"].values():
            self.assertEqual(row["mean_bias_central_95pct_resampling_range"], [3., 3.])
            self.assertEqual(row["rmse_central_95pct_resampling_range"], [3., 3.])

    def test_block_resampling_rejects_invalid_specifications(self):
        with self.assertRaisesRegex(ValueError, "Insufficient"):
            moving_block_sensitivity({2014: np.ones(8)},
                                     block_lengths=(32,), replicates=20)


if __name__ == "__main__":
    unittest.main()
