"""Unit/schema regression tests only: input objects are analytic test fixtures.

No fixture is real weather evidence. Live API evidence requires original
Open-Meteo JSON, request parameters and SHA-256 recorded by the importer.
"""
import csv
import json
from pathlib import Path
from tempfile import TemporaryDirectory
import unittest

from scripts.open_meteo_boundary import (
    EXPECTED_UNITS, build_url, main, parse_response, utc_iso,
)


def archive_fixture():
    return {
        "latitude": 53.25, "longitude": -0.5, "utc_offset_seconds": 0,
        "hourly_units": {**EXPECTED_UNITS, "time": "iso8601"},
        "hourly": {
            "time": ["2025-10-01T12:00", "2025-10-01T13:00"],
            "temperature_2m": [15.0, 15.5],
            "surface_pressure": [1005.0, 1004.5],
            "relative_humidity_2m": [60.0, 62.0],
        },
    }


class WeatherBoundaryTests(unittest.TestCase):
    def test_archive_units_and_exact_hour(self):
        value = parse_response(
            archive_fixture(), "archive", "2025-10-01T12:00Z",
            53.23, -0.54, "era5", "a" * 64
        )
        self.assertAlmostEqual(value["temperature_K"], 288.15)
        self.assertAlmostEqual(value["surface_pressure_Pa"], 100500.0)
        self.assertAlmostEqual(value["relative_humidity_fraction"], 0.6)
        self.assertEqual(value["valid_time_utc"], "2025-10-01T12:00:00Z")

    def test_archive_requires_timestamp_present(self):
        with self.assertRaisesRegex(ValueError, "timestamp absent"):
            parse_response(archive_fixture(), "archive", "2025-10-01T17:00Z",
                           53.23, -0.54, "era5", "x")

    def test_forecast_current_parsing(self):
        data = {
            "latitude": 53.25, "longitude": -0.5, "utc_offset_seconds": 0,
            "current_units": {**EXPECTED_UNITS, "time": "iso8601"},
            "current": {"time": "2026-11-10T07:15", "temperature_2m": 2.5,
                        "surface_pressure": 1010.8, "relative_humidity_2m": 87},
        }
        value = parse_response(data, "forecast-current", None, 53.23, -0.54,
                               "best_match", "b" * 64)
        self.assertEqual(value["valid_time_utc"], "2026-11-10T07:15:00Z")
        self.assertAlmostEqual(value["surface_pressure_Pa"], 101080.0)
        self.assertAlmostEqual(value["relative_humidity_fraction"], 0.87)

    def test_missing_surface_pressure_never_uses_sea_level_pressure(self):
        d = archive_fixture()
        d["hourly"]["pressure_msl"] = [1030, 1030]
        del d["hourly"]["surface_pressure"]
        with self.assertRaisesRegex(ValueError, "surface_pressure"):
            parse_response(d, "archive", "2025-10-01T12:00Z", 53.23, -0.54, "era5", "x")

    def test_unit_mismatch_rejected(self):
        d = archive_fixture()
        d["hourly_units"]["surface_pressure"] = "Pa"
        with self.assertRaisesRegex(ValueError, "units"):
            parse_response(d, "archive", "2025-10-01T12:00Z", 53.23, -0.54, "era5", "x")

    def test_missing_sample_rejected(self):
        d = archive_fixture()
        d["hourly"]["temperature_2m"][0] = None
        with self.assertRaisesRegex(ValueError, "absent"):
            parse_response(d, "archive", "2025-10-01T12:00Z", 53.23, -0.54, "era5", "x")

    def test_incomplete_channel_rejected(self):
        d = archive_fixture()
        d["hourly"]["temperature_2m"] = [15.0]
        with self.assertRaisesRegex(ValueError, "incomplete"):
            parse_response(d, "archive", "2025-10-01T12:00Z", 53.23, -0.54, "era5", "x")

    def test_timezone_mismatch_rejected(self):
        d = archive_fixture()
        d["utc_offset_seconds"] = 3600
        with self.assertRaisesRegex(ValueError, "timezone"):
            parse_response(d, "archive", "2025-10-01T12:00Z", 53.23, -0.54, "era5", "x")

    def test_bad_site_location_rejected(self):
        with self.assertRaisesRegex(ValueError, "latitude"):
            build_url("archive", 133.0, -0.54, "2025-10-01T12:00Z", "era5")

    def test_forecast_disallows_historical_timestamp(self):
        with self.assertRaisesRegex(ValueError, "not applicable"):
            build_url("forecast-current", 53.23, -0.54, "2025-10-01T12:00Z",
                      "best_match")

    def test_gmt_iso_parsing(self):
        self.assertEqual(utc_iso("2025-10-01T12:00"), "2025-10-01T12:00:00Z")
        with self.assertRaisesRegex(ValueError, "Non-UTC"):
            utc_iso("2025-10-01T12:00:00+02:00")

    def test_replay_files_and_no_live_claim(self):
        with TemporaryDirectory() as temp:
            tmp = Path(temp)
            snapshot = tmp / "source_response.json"
            snapshot.write_text(json.dumps(archive_fixture()), encoding="utf-8")
            out = tmp / "boundary.csv"
            main([
                "--source", "archive", "--model", "era5",
                "--latitude", "53.23", "--longitude", "-0.54",
                "--valid-time", "2025-10-01T12:00Z",
                "--response-json", str(snapshot),
                "--output", str(out),
            ])
            manifest = json.loads(out.with_suffix(".manifest.json").read_text())
            rows = list(csv.DictReader(out.open()))
            self.assertEqual(len(rows), 1)
            self.assertEqual(manifest["retrieved_at_utc"], "replay-from-supplied-snapshot-not-live")
            self.assertEqual(manifest["meteo_type"], "reanalysis")
            self.assertFalse(manifest["observed_engine_measurement"])
            self.assertFalse(manifest["flange_condition_measured"])


if __name__ == "__main__":
    unittest.main()
