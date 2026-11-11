"""Mathematical fixture tests ONLY; no fixture is passed off as a turbine observation."""
from __future__ import annotations

import csv
import math
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

import numpy as np

from scripts.replay_uci_gt551 import (
    FIELDS, TRAIN_YEARS, TEST_YEARS,
    make_viewer, measured_holdout_rows, replay_arrays,
)


def algebraic_fixture(holdout_bias: float = 0.0, out_of_range: bool = False):
    rng = np.random.default_rng(20261111)
    per_year = {}
    for year in range(2011, 2016):
        x = rng.normal(size=(100, 4))
        if year == 2015 and out_of_range:
            x[0, 0] = 1000.0
        target = 130.0 + x @ np.array([4.0, -2.0, 1.5, 3.0])
        if year in TEST_YEARS:
            target = target + holdout_bias
        per_year[year] = (x, target)
    return per_year


class ReplayContract(unittest.TestCase):
    def test_train_is_only_2011_2013_and_holdout_has_no_target_leakage(self):
        original, evaluated = replay_arrays(algebraic_fixture())
        changed, shifted = replay_arrays(algebraic_fixture(holdout_bias=7.0))
        self.assertEqual(original["train_years"], list(TRAIN_YEARS))
        self.assertEqual(original["test_years"], list(TEST_YEARS))
        self.assertEqual(original["train_rows"], 300)
        self.assertEqual(original["test_rows"], 200)
        self.assertFalse(original["is_next_step_forecast"])
        self.assertFalse(original["is_independent_physics_model_validation"])
        self.assertLess(original["heldout_rmse_source_TEY_units"], 1e-9)
        self.assertAlmostEqual(changed["heldout_rmse_source_TEY_units"], 7.0, places=6)
        for year in TEST_YEARS:
            np.testing.assert_allclose(
                evaluated[year]["prediction"], shifted[year]["prediction"], atol=1e-10
            )
        self.assertTrue(
            changed["heldout_training_mean_baseline_rmse_source_TEY_units"] >= 7.0
        )

    def test_outside_training_range_flag_not_diagnosed_fault(self):
        report, evaluation = replay_arrays(algebraic_fixture(out_of_range=True))
        self.assertTrue(bool(evaluation[2015]["outside"][0]))
        self.assertFalse(report["residual_3sigma_flags_are_confirmed_faults"])
        self.assertGreater(
            report["annual_holdout_metrics"]["2015"][
                "outside_training_feature_ranges_fraction"
            ], 0.0
        )

    def test_reject_missing_year_nonfinite_bad_dimension(self):
        f = algebraic_fixture()
        del f[2015]
        with self.assertRaisesRegex(ValueError, "five annual"):
            replay_arrays(f)
        f = algebraic_fixture()
        f[2014][0][0, 0] = float("nan")
        with self.assertRaisesRegex(ValueError, "Malformed finite"):
            replay_arrays(f)
        f = algebraic_fixture()
        f[2014] = (np.ones((100, 3)), np.ones(100))
        with self.assertRaisesRegex(ValueError, "Malformed finite"):
            replay_arrays(f)

    def test_source_row_alignment_and_no_fabricated_timestamps(self):
        columns = (
            "year", "within_year_row", "AT", "AP", "AH", "AFDP", "GTEP",
            "TIT", "TAT", "TEY", "CDP", "CO", "NOX",
        )
        with TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = {"years": {}}
            result = {}
            for year in TEST_YEARS:
                p = root / ("gt_" + str(year) + ".csv")
                with p.open("w", newline="", encoding="utf-8") as h:
                    writer = csv.DictWriter(h, fieldnames=columns)
                    writer.writeheader()
                    for i in range(1, 3):
                        writer.writerow({
                            "year": year, "within_year_row": i, "AT": 20.0,
                            "AP": 1013.0, "AH": 40, "AFDP": 3,
                            "GTEP": 25, "TIT": 1080, "TAT": 530, "TEY": 130+i,
                            "CDP": 12, "CO": 2, "NOX": 65,
                        })
                manifest["years"][str(year)] = {"audited_csv": p.name, "rows": 2}
                result[year] = {
                    "actual": np.array([131.0, 132.0]),
                    "prediction": np.array([130.0, 130.0]),
                    "residual": np.array([1.0, 2.0]),
                    "outside": np.array([False, True]),
                    "flags": np.array([False, True]),
                }
            rows = list(measured_holdout_rows(root, manifest, result, baseline=125.0))
            self.assertEqual(len(rows), 4)
            self.assertEqual(tuple(rows[0]), FIELDS)
            self.assertEqual(rows[0]["within_year_row"], 1)
            self.assertEqual(rows[0]["measured_TEY_source_units"], 131.0)
            self.assertNotIn("timestamp", rows[0])
            self.assertEqual(rows[-1]["outside_training_feature_ranges"], 1)
            result[2014]["actual"][0] = 900
            with self.assertRaisesRegex(ValueError, "alignment"):
                list(measured_holdout_rows(root, manifest, result, 125.0))

    def test_local_interactive_viewer_rejects_incomplete_data(self):
        report, _ = replay_arrays(algebraic_fixture())
        with self.assertRaisesRegex(ValueError, "incomplete"):
            make_viewer([], report)
        examples = []
        for year in TEST_YEARS:
            for rownum in range(1, 101):
                examples.append({
                    "year": year, "within_year_row": rownum,
                    "measured_TEY_source_units": 130.0,
                    "predicted_TEY_source_units": 129.5,
                    "outside_training_feature_ranges": 0,
                    "observed_AT_degC": 20,
                    "observed_TIT_degC": 1080,
                })
        html = make_viewer(examples, report)
        self.assertIn("2014", html)
        self.assertIn("Observed TEY", html)
        self.assertIn("NOT a calibrated time axis", html)
        self.assertNotIn('src="http', html)
        self.assertNotIn("__DATA_JSON__", html)


if __name__ == "__main__":
    unittest.main()
