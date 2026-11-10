"""Analytical tests only, never claimed as production-engine observations."""
import copy
import csv
import json
import math
import random
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.passoff_correction import (
    INPUT_SCHEMA, ORDER, compute_corrected, covariance_3x3, evaluate, load_site_result,
)

ZERO = [[0.0, 0.0, 0.0] for _ in range(3)]


def covariance():
    return {
        "variable_order": list(ORDER),
        # standard uncertainties: 0.1 MW, 0.01 kg/s, 0.25 MJ/kg
        "precision": [[0.01, 0, 0], [0, 0.0001, 0], [0, 0, 6.25e10]],
        "calibration": [[0.0004, 0, 0], [0, 0.000025, 0], [0, 0, 1e10]],
    }


def analytic_record():
    return {
        "schema": INPUT_SCHEMA,
        "source_class": "recorded_test_stand_measurements",
        "test_id": "ANALYTICAL-UNIT-TEST-NOT-A-MEASURED-ENGINE",
        "engine_id": "ANALYTICAL-UNIT-TEST",
        "measurement_source_identifier": "mathematical-fixture-not-real",
        "instrument_calibration_source_identifier": "mathematical-fixture-not-real",
        "steady_state_verified": True,
        "start_utc": "2026-01-01T00:00:00Z",
        "end_utc": "2026-01-01T00:10:00Z",
        "model_site_case": "mathematical-verification",
        "measured": {
            "net_power_MW": 30.0, "fuel_flow_kg_s": 2.0,
            "fuel_LHV_J_kg": 50e6, "ambient_T_K": 288.15,
            "ambient_P_Pa": 101325.0,
        },
        "covariance": covariance(),
    }


def analytic_model_row():
    # Mathematical identity checks, NOT calibrated Siemens power values.
    return {
        "case_name": "mathematical-verification", "valid": "1",
        "site_ambient_T_K": "288.15", "site_ambient_P_Pa": "101325",
        "site_fuel_LHV_J_kg": "50000000",
        "power_correction_ref_per_site": "1.05",
        "reference_net_power_MW": "31.5",
        "site_net_power_MW": "30",
        "heat_rate_correction_ref_per_site": "0.98",
        "reference_heat_rate_kJ_kWh": "11760",
        "site_heat_rate_kJ_kWh": "12000",
    }


class PassoffPhysicsTests(unittest.TestCase):
    def test_heat_input_and_heat_rate_from_measured_fuel(self):
        result = compute_corrected(analytic_record()["measured"], 1.05, 0.98,
                                   covariance()["precision"], covariance()["calibration"])
        self.assertAlmostEqual(result["observed_site_power_MW"], 30)
        self.assertAlmostEqual(result["observed_site_heat_rate_kJ_kWh"], 12000)
        self.assertAlmostEqual(result["corrected_reference_power_MW"], 31.5)
        self.assertAlmostEqual(result["corrected_reference_heat_rate_kJ_kWh"], 11760)
        self.assertIn("UNVALIDATED MODEL", result["reference_guarantee_decision"])

    def test_zero_uncertainty_is_zero(self):
        result = compute_corrected(analytic_record()["measured"], 1, 1, ZERO, ZERO)
        u = result["conditional_instrument_standard_uncertainty"]
        self.assertEqual(u["corrected_power_MW"], 0)
        self.assertEqual(u["corrected_heat_rate_kJ_kWh"], 0)

    def test_covariance_decomposition_and_analytic_jacobian(self):
        data = analytic_record()["measured"]
        result = compute_corrected(data, 1.05, 0.98,
                                   covariance()["precision"], covariance()["calibration"])
        u = result["conditional_instrument_standard_uncertainty"]
        h = 11760.0
        analytical_uhr = math.sqrt(
            (h/30.0)**2 * (0.01 + 0.0004) +
            (h/2.0)**2 * (0.0001 + 0.000025) +
            (h/50e6)**2 * (6.25e10 + 1e10)
        )
        self.assertAlmostEqual(u["corrected_heat_rate_kJ_kWh"], analytical_uhr, places=8)
        self.assertAlmostEqual(u["corrected_power_MW"],
                               1.05*math.sqrt(0.0104), places=10)
        self.assertLess(u["power_heat_rate_covariance_MW_times_kJ_kWh"], 0)

    def test_first_order_jacobian_agrees_with_central_differences(self):
        # Instrument sensitivities are derivatives of exact equations; no
        # invented gas-turbine performance observations enter this test.
        data = analytic_record()["measured"]
        result = compute_corrected(data, 1.05, 0.98, ZERO, ZERO)
        u = result["conditional_instrument_standard_uncertainty"]
        for i, name in enumerate(ORDER):
            value = data[name]
            step = abs(value) * 1e-5
            plus, minus = dict(data), dict(data)
            plus[name], minus[name] = value + step, value - step
            yp = compute_corrected(plus, 1.05, 0.98, ZERO, ZERO)
            ym = compute_corrected(minus, 1.05, 0.98, ZERO, ZERO)
            for key, expected in (
                ("corrected_reference_power_MW", u["jacobian_power_MW"][i]),
                ("corrected_reference_heat_rate_kJ_kWh", u["jacobian_heat_rate_kJ_kWh"][i]),
            ):
                numerical = (yp[key] - ym[key]) / (2 * step)
                self.assertAlmostEqual(numerical, expected,
                                       delta=max(1e-10, abs(expected)*1e-7))

    def test_first_order_uq_matches_small_noise_monte_carlo_identity(self):
        # Seeded mathematical covariance calculation; these draws are NOT
        # purported fuel meters, engine recordings, or scientific field data.
        data = analytic_record()["measured"]
        calculated = compute_corrected(data, 1.05, 0.98,
                                       covariance()["precision"], covariance()["calibration"])
        diag = [covariance()["precision"][i][i] +
                covariance()["calibration"][i][i] for i in range(3)]
        rng = random.Random(88116)
        n = 5000
        powers, heats = [], []
        for _ in range(n):
            sampled = {key: data[key] + math.sqrt(diag[i])*rng.gauss(0, 1)
                       for i, key in enumerate(ORDER)}
            result = compute_corrected(sampled, 1.05, 0.98, ZERO, ZERO)
            powers.append(result["corrected_reference_power_MW"])
            heats.append(result["corrected_reference_heat_rate_kJ_kWh"])
        for samples, key in (
            (powers, "corrected_power_MW"),
            (heats, "corrected_heat_rate_kJ_kWh"),
        ):
            mean = sum(samples)/n
            sample_std = math.sqrt(sum((z-mean)**2 for z in samples)/(n-1))
            analytic_std = calculated["conditional_instrument_standard_uncertainty"][key]
            self.assertLess(abs(sample_std/analytic_std - 1.0), 0.08)

    def test_covariance_correlated_terms_propagate(self):
        p = covariance()["precision"]
        # Correlated power/fuel flow measurements are physically possible.
        p[0][1] = p[1][0] = 0.0005
        u0 = compute_corrected(analytic_record()["measured"], 1, 1,
                               covariance()["precision"], ZERO)
        u1 = compute_corrected(analytic_record()["measured"], 1, 1, p, ZERO)
        self.assertNotEqual(
            u0["conditional_instrument_standard_uncertainty"]["corrected_heat_rate_kJ_kWh"],
            u1["conditional_instrument_standard_uncertainty"]["corrected_heat_rate_kJ_kWh"]
        )

    def test_impossible_covariance_rejected(self):
        bad = [[1, 2, 0], [2, 1, 0], [0, 0, 1]]
        with self.assertRaisesRegex(ValueError, "correlation"):
            covariance_3x3("invalid", bad)

    def test_3d_covariance_not_positive_semidefinite(self):
        bad = [[1, -0.8, -0.8], [-0.8, 1, -0.8], [-0.8, -0.8, 1]]
        with self.assertRaisesRegex(ValueError, "determinant"):
            covariance_3x3("invalid", bad)

    def test_reference_factor_import_identity(self):
        with TemporaryDirectory() as temp:
            path = Path(temp) / "model.csv"
            row = analytic_model_row()
            with path.open("w", newline="") as file:
                w = csv.DictWriter(file, fieldnames=list(row))
                w.writeheader()
                w.writerow(row)
            parsed, cp, ch = load_site_result(path, row["case_name"])
            self.assertEqual(cp, 1.05)
            self.assertEqual(ch, 0.98)
            self.assertEqual(parsed["valid"], "1")

    def test_fake_model_factor_mismatch_rejected(self):
        with TemporaryDirectory() as temp:
            path = Path(temp) / "model.csv"
            row = analytic_model_row()
            row["power_correction_ref_per_site"] = "1.3"
            with path.open("w", newline="") as file:
                w = csv.DictWriter(file, fieldnames=list(row))
                w.writeheader()
                w.writerow(row)
            with self.assertRaisesRegex(ValueError, "factor identity"):
                load_site_result(path, row["case_name"])

    def test_station_boundary_mismatch_rejected(self):
        data = analytic_record()
        data["measured"]["ambient_T_K"] = 310
        with self.assertRaisesRegex(ValueError, "regenerate site case"):
            evaluate(data, analytic_model_row(), (1.05, 0.98), "x", "y")

    def test_no_steady_state_rejected(self):
        data = analytic_record()
        data["steady_state_verified"] = False
        with self.assertRaisesRegex(ValueError, "Steady state"):
            evaluate(data, analytic_model_row(), (1.05, 0.98), "x", "y")

    def test_missing_calibration_source_rejected(self):
        data = analytic_record()
        data["instrument_calibration_source_identifier"] = ""
        with self.assertRaisesRegex(ValueError, "provenance"):
            evaluate(data, analytic_model_row(), (1.05, 0.98), "x", "y")

    def test_correct_test_math_never_returns_industrial_guarantee(self):
        data = analytic_record()
        result = evaluate(data, analytic_model_row(), (1.05, 0.98), "x", "y")
        self.assertEqual(result["source_class"],
                         "operator_provided_measurement_not_independently_authenticated")
        self.assertIn("NOT ASSESSED", result["computation"]["reference_guarantee_decision"])
        self.assertNotIn("PASS", result["computation"]["reference_guarantee_decision"])


if __name__ == "__main__":
    unittest.main()
