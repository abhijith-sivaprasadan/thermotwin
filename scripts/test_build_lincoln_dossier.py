"""Unit tests for evidence provenance gates.

These are deliberately *synthetic mathematical/schema fixtures only*: no
fixtures from this test are plant measurements or publication evidence.
"""
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from scripts.build_lincoln_dossier import audit, generate, digest


def put_json(path: Path, value: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


def one_csv(path: Path, row: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(row), lineterminator="\n")
        writer.writeheader()
        writer.writerow(row)


def fake_inputs(root: Path):
    uci = root / "uci"
    weather = root / "weather"
    uci.mkdir()
    weather.mkdir()
    z = uci / "uci551_original.zip"
    z.write_bytes(b"unit-test-fixture-NOT-UCI")
    zh = digest(z)
    counts = [7411, 7628, 7152, 7158, 7384]
    entries = {}
    for year, n in zip(range(2011, 2016), counts):
        path = uci / f"{year}.csv"
        path.write_text("synthetic-schema-test; not original data\n")
        entries[str(year)] = {"rows": n, "audited_csv": path.name,
                              "audited_csv_sha256": digest(path)}
    put_json(uci / "manifest.json", {
        "doi": "10.24432/C5WC95", "number_of_turbines": 1,
        "total_rows": 36733, "original_zip_sha256": zh, "years": entries
    })
    put_json(uci / "condition_residual_report.json", {
        "doi": "10.24432/C5WC95", "source_zip_sha256": zh,
        "measured_observations": 36733, "turbine_count": 1,
        "fit_years": [2011, 2012, 2013],
        "untouched_evaluation_years": [2014, 2015],
        "measured_gt_power_MW_claimed": False,
        "not_a_pass_off_or_known_fault_dataset": True,
        "holdout": {
            "rows": 14542, "rmse_source_TEY_units": 4,
            "training_mean_baseline_rmse_source_TEY_units": 10
        },
        "condition_adjustment": {"training_residual_lag1_within_year_demeaned": .9},
        "heldout_covariate_support": {
            "heldout_fraction_outside_any_feature": .04},
        "heldout_adjacent_row_resampling_sensitivity": {
            "block_lengths_published_rows": [32, 64, 128],
            "sensitivity": {"64": {"rmse_central_95pct_resampling_range": [3.6, 4.4]}}}
    })
    raw = weather / "lincoln_era5_raw.json"
    raw.write_bytes(b'{"unit_test_only":true}')
    wh = digest(raw)
    valid = "2025-10-01T12:00:00Z"
    reference = root / "hardware.csv"
    reference.write_text("synthetic-teaching-deck\n")
    common = {
        "raw_response_sha256": wh, "weather_source": "Open-Meteo",
        "meteo_type": "reanalysis", "observed_engine_measurement": False,
        "flange_condition_measured": False,
        "humidity_used_in_thermotwin_physics": False, "valid_time_utc": valid
    }
    put_json(weather / "lincoln_era5_boundary.manifest.json", common)
    put_json(weather / "lincoln_era5_model_boundary.manifest.json", {
        **common, "humidity_mode": "dry_air_approximation_requested_by_operator",
        "humidity_correction_performed": False,
        "hardware_deck_sha256": digest(reference),
        "hardware_calibration_not_verified_by_weather_data": True,
        "actual_weather_relative_humidity_fraction": .45,
        "model_input_relative_humidity_fraction": .6
    })
    one_csv(weather / "lincoln_era5_boundary.csv", {
        "valid_time_utc": valid, "temperature_K": 287.25,
        "surface_pressure_Pa": 102390, "relative_humidity_fraction": .45,
        "raw_sha256": wh
    })
    one_csv(weather / "lincoln_era5_model_boundary_case.csv", {
        "ambient_T_K": 287.25, "ambient_P_Pa": 102390, "relative_humidity": .6
    })
    one_csv(weather / "lincoln_era5_site_model.csv", {
        "valid": 1, "site_ambient_T_K": 287.25,
        "site_ambient_P_Pa": 102390, "reference_net_power_MW": 30,
        "site_net_power_MW": 30.6, "power_derate_ratio": 1.02,
        "power_correction_ref_per_site": 30/30.6,
        "reference_heat_rate_kJ_kWh": 12000,
        "site_heat_rate_kJ_kWh": 11900,
        "heat_rate_correction_ref_per_site": 12000/11900,
        "reference_exhaust_flow_kg_s": 100,
        "site_exhaust_flow_kg_s": 102,
        "exhaust_flow_correction_ref_per_site": 100/102,
        "reference_exhaust_T_K": 780,
        "site_exhaust_T_K": 782,
        "exhaust_T_additive_ref_minus_site_K": -2
    })
    return uci, weather, reference


class EvidenceDossierTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dossier-mathematical-fixture-")
        self.root = Path(self.tmp.name)
        self.uci, self.weather, self.reference = fake_inputs(self.root)

    def tearDown(self):
        self.tmp.cleanup()

    def test_valid_mathematical_schema_and_readable_svg(self):
        a = audit(self.uci, self.weather, self.reference)
        out = self.root / "generated"
        ledger = generate(a, out, "test-fixture-no-publication", "local")
        self.assertEqual(ledger["source_data"]["original_turbines"], 1)
        self.assertFalse(ledger["disclosures"]["measured_engine_power_claimed"])
        self.assertEqual(set(ledger["outputs_sha256"]), {
            "ENGINEERING_DOSSIER.md", "01_uci_measured_holdout.svg",
            "02_era5_model_site.svg"})
        for svg in out.glob("*.svg"):
            s = svg.read_text()
            self.assertIn("http://www.w3.org/2000/svg", s)
            self.assertIn("not", s.lower())  # explicit limitations
        self.assertIn("NOT measured turbine performance",
                      (out / "ENGINEERING_DOSSIER.md").read_text())

    def test_rejects_tampered_original_uci_zip(self):
        (self.uci / "uci551_original.zip").write_bytes(b"different")
        with self.assertRaisesRegex(ValueError, "UCI source"):
            audit(self.uci, self.weather, self.reference)

    def test_rejects_unverified_engine_power_claim(self):
        path = self.uci / "condition_residual_report.json"
        obj = json.loads(path.read_text())
        obj["measured_gt_power_MW_claimed"] = True
        put_json(path, obj)
        with self.assertRaisesRegex(ValueError, "UCI source"):
            audit(self.uci, self.weather, self.reference)

    def test_rejects_real_weather_relabelled_as_engine_measurement(self):
        path = self.weather / "lincoln_era5_boundary.manifest.json"
        obj = json.loads(path.read_text())
        obj["observed_engine_measurement"] = True
        put_json(path, obj)
        with self.assertRaisesRegex(ValueError, "Weather source"):
            audit(self.uci, self.weather, self.reference)

    def test_rejects_wrong_hardware_reference(self):
        self.reference.write_text("altered")
        with self.assertRaisesRegex(ValueError, "Weather replay"):
            audit(self.uci, self.weather, self.reference)

    def test_rejects_fortran_site_ratio_inconsistency(self):
        path = self.weather / "lincoln_era5_site_model.csv"
        row = next(csv.DictReader(path.open(newline="")))
        row["power_derate_ratio"] = "1.4"
        one_csv(path, row)
        with self.assertRaisesRegex(ValueError, "site power"):
            audit(self.uci, self.weather, self.reference)

    def test_rejects_wrong_model_boundary_temperature(self):
        path = self.weather / "lincoln_era5_model_boundary_case.csv"
        row = next(csv.DictReader(path.open(newline="")))
        row["ambient_T_K"] = "299"
        one_csv(path, row)
        with self.assertRaisesRegex(ValueError, "weather/model T"):
            audit(self.uci, self.weather, self.reference)

    def test_rejects_annual_source_hash_change(self):
        (self.uci / "2015.csv").write_text("tampered")
        with self.assertRaisesRegex(ValueError, "annual CSV source digest"):
            audit(self.uci, self.weather, self.reference)


if __name__ == "__main__":
    unittest.main()
