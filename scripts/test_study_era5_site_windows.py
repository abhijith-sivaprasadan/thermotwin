"""Mathematical/schema-only tests; none are field measurements or research results."""
from __future__ import annotations

import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.open_meteo_boundary import EXPECTED_UNITS
from scripts.study_era5_site_windows import verified_window


def make_fixture(start: str, count=3) -> dict:
    from scripts.study_era5_site_windows import times
    return {
        "latitude": 53.25, "longitude": -0.5, "utc_offset_seconds": 0,
        "hourly_units": {**EXPECTED_UNITS, "time": "iso8601"},
        "hourly": {
            "time": [z[:16] for z in times(start, count)],
            "temperature_2m": [12.0 + 0.5*(k % 12) for k in range(count)],
            "surface_pressure": [1013.0 + 0.1*k for k in range(count)],
            "relative_humidity_2m": [60.0 + (k % 10) for k in range(count)],
        },
    }


class WeatherStudyTests(unittest.TestCase):
    def test_utc_url_calendar_and_genuine_data_parser_contract(self):
        from scripts.study_era5_site_windows import source_url, times
        self.assertEqual(len(times("2025-01-15", 168)), 168)
        self.assertEqual(times("2025-01-15", 168)[-1], "2025-01-21T23:00:00Z")
        url = source_url("2025-01-15", 168)
        self.assertIn("models=era5", url)
        self.assertIn("end_date=2025-01-21", url)
        self.assertNotIn("pressure_msl", url)
        data = make_fixture("2025-01-15")
        values = verified_window(json.dumps(data).encode(), "2025-01-15", 3)
        self.assertEqual(len(values), 3)
        self.assertAlmostEqual(values[0]["temperature_K"], 285.15)
        self.assertAlmostEqual(values[0]["surface_pressure_Pa"], 101300)

    def test_reject_missing_duplicate_extra_and_reordered_hour(self):
        a = make_fixture("2025-01-15")
        for times in (
            a["hourly"]["time"][:-1],
            [a["hourly"]["time"][0]]*3,
            list(reversed(a["hourly"]["time"])),
            a["hourly"]["time"] + ["2025-01-15T03:00"],
        ):
            with self.subTest(times=times):
                d = make_fixture("2025-01-15")
                d["hourly"]["time"] = times
                with self.assertRaisesRegex(ValueError,"UTC hours|incomplete"):
                    verified_window(json.dumps(d).encode(),"2025-01-15",3)

    def test_fail_closed_on_nonfinite_missing_and_wrong_unit(self):
        d = make_fixture("2025-01-15")
        d["hourly"]["temperature_2m"][1] = None
        with self.assertRaises(ValueError):
            verified_window(json.dumps(d).encode(),"2025-01-15",3)
        d = make_fixture("2025-01-15")
        d["hourly_units"]["surface_pressure"] = "Pa"
        with self.assertRaisesRegex(ValueError,"units"):
            verified_window(json.dumps(d).encode(),"2025-01-15",3)
        d = make_fixture("2025-01-15")
        d["utc_offset_seconds"] = 3600
        with self.assertRaisesRegex(ValueError,"timezone"):
            verified_window(json.dumps(d).encode(),"2025-01-15",3)

    def test_algebraic_example_fixtures_are_not_published_evidence(self):
        from scripts.study_era5_site_windows import (
            WINDOWS, LOSSES, acquire, summarize, csv_rows, save_csv, digest
        )
        with TemporaryDirectory(prefix="not-empirical-era5-unit-test-") as tmp:
            root=Path(tmp)
            rawdir=root/"raw"
            rawdir.mkdir()
            for idx,(label,start) in enumerate(WINDOWS,1):
                p=rawdir/f"week_{idx:02d}_{label}_era5_raw.json"
                p.write_text(json.dumps(make_fixture(start,168)))
            ref=root/"reference.csv"
            # This is a test-only mathematical input deck, NOT an engine measurement.
            from scripts.open_meteo_boundary import ENGINE_FIELDS
            ref_row=dict(zip(ENGINE_FIELDS,(
                "iso","288.15","101325","0.60","0","100","15",".86",
                "1400",".98",".03","50000000",".89","0",".99",".985",".02","clean")))
            with ref.open("w",newline="") as f:
                f.write(",".join(ENGINE_FIELDS)+"\n")
                f.write(",".join(ref_row[x] for x in ENGINE_FIELDS)+"\n")
            out=root/"output"
            a=acquire(out,ref,rawdir)
            self.assertEqual(a["weather_hours"],672)
            self.assertEqual(a["model_cases"],2688)
            self.assertEqual(len(csv_rows(out/"site_cases.csv")),2688)
            # Fictitious algebraic rows test the report ledger only; they
            # MUST NEVER be described as turbine tests or uploaded to CI.
            cases=csv_rows(out/"site_cases.csv")
            fields=("case_name","site_ambient_T_K","site_ambient_P_Pa",
                "reference_net_power_MW","site_net_power_MW","power_derate_ratio",
                "power_correction_ref_per_site","reference_heat_rate_kJ_kWh",
                "site_heat_rate_kJ_kWh","heat_rate_correction_ref_per_site",
                "reference_exhaust_flow_kg_s","site_exhaust_flow_kg_s",
                "exhaust_flow_correction_ref_per_site","reference_exhaust_T_K",
                "site_exhaust_T_K","exhaust_T_additive_ref_minus_site_K","valid")
            results=[]
            for c in cases:
                t=float(c["ambient_T_K"])
                inlet=float(c["inlet_pressure_loss"])
                exhaust=float(c["exhaust_pressure_loss"])
                ratio=1+(288.15-t)*.001-inlet*.5-exhaust*.35
                p=30*ratio
                results.append(dict(zip(fields,(
                    c["case_name"],c["ambient_T_K"],c["ambient_P_Pa"],
                    30,p,ratio,30/p,11000,11000,1,100,100,1,790,790,0,1))))
            save_csv(out/"site_results.csv",fields,results)
            report=summarize(out,ref)
            self.assertEqual(report["model_cases"],2688)
            self.assertFalse(report["engine_specific_validation"])
            self.assertTrue(report["model_form_uncertainty_not_quantified"])
            self.assertTrue((out/"seasonal_era5_site_model.svg").exists())
            self.assertTrue((out/"hourly_site_model.svg").exists())
            self.assertEqual(len(csv_rows(out/"hourly_model_ratios.csv")), 672)
            self.assertNotIn("measured turbine", (out/"STUDY.md").read_text().lower().split("no matched real turbine power")[0])

    def test_analytical_solver_identity_guard(self):
        from scripts.study_era5_site_windows import close
        close(1.01, 101./100., "mathematical ratio")
        with self.assertRaisesRegex(ValueError,"identity mismatch"):
            close(1.3,1.01,"tampered synthetic math only")


if __name__=="__main__":
    unittest.main()
