#!/usr/bin/env python3
"""Acquire real weather-model boundary data for ThermoTwin-F.

Sources: Open-Meteo ERA5 historical reanalysis or current forecast. These are
meteorological model estimates at approximately 2 m, NOT measured gas-turbine
compressor-flange conditions. No gas-turbine performance is calculated here.
Data attribution: Open-Meteo.com (CC BY 4.0). Free API: non-commercial use.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from hashlib import sha256
import json
import math
from pathlib import Path
from urllib.parse import urlencode
from urllib.request import Request, urlopen

HOURLY_FIELDS = ("temperature_2m", "surface_pressure", "relative_humidity_2m")
EXPECTED_UNITS = {
    "temperature_2m": "°C",
    "surface_pressure": "hPa",
    "relative_humidity_2m": "%",
}
FIELD_NAMES = [
    "valid_time_utc", "site_latitude_requested", "site_longitude_requested",
    "model_grid_latitude", "model_grid_longitude", "temperature_K",
    "surface_pressure_Pa", "relative_humidity_fraction", "source_type",
    "requested_model", "raw_sha256",
]
ENGINE_FIELDS = [
    "case_name", "ambient_T_K", "ambient_P_Pa", "relative_humidity",
    "inlet_pressure_loss", "mdot_air_kg_s", "pressure_ratio",
    "eta_compressor", "T_turbine_inlet_K", "eta_combustor",
    "combustor_pressure_loss", "LHV_J_kg", "eta_turbine",
    "exhaust_pressure_loss", "eta_mechanical", "eta_generator",
    "auxiliary_load_fraction", "degradation_mode",
]


def require_finite(name: str, value: object, low: float, high: float) -> float:
    if isinstance(value, bool) or value is None:
        raise ValueError(f"{name}: absent or invalid numeric value")
    try:
        x = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name}: not numeric") from exc
    if not math.isfinite(x) or not low <= x <= high:
        raise ValueError(f"{name}: nonfinite or outside [{low}, {high}]")
    return x


def utc_iso(s: str) -> str:
    if not isinstance(s, str):
        raise ValueError("Weather validity time must be a string")
    try:
        t = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError as exc:
        raise ValueError(f"Bad weather validity time: {s}") from exc
    # Open-Meteo returns offset-free ISO datetimes when timezone=GMT.
    if t.tzinfo is None:
        t = t.replace(tzinfo=timezone.utc)
    elif t.utcoffset().total_seconds() != 0:
        raise ValueError("Non-UTC weather response; require timezone=GMT")
    return t.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def build_url(source: str, latitude: float, longitude: float,
              valid_time: str | None, model: str) -> str:
    require_finite("latitude", latitude, -90.0, 90.0)
    require_finite("longitude", longitude, -180.0, 180.0)
    if source == "archive":
        if not valid_time:
            raise ValueError("--valid-time required for archive source")
        iso = utc_iso(valid_time)
        instant = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        if instant.minute or instant.second or instant.microsecond:
            raise ValueError("Archive requires an exact UTC hourly timestamp")
        day = iso[:10]
        params = {
            "latitude": latitude, "longitude": longitude,
            "start_date": day, "end_date": day, "hourly": ",".join(HOURLY_FIELDS),
            "models": model, "timezone": "GMT",
        }
        return "https://archive-api.open-meteo.com/v1/archive?" + urlencode(params)
    if source == "forecast-current":
        if valid_time:
            raise ValueError("--valid-time not applicable for forecast-current")
        if model != "best_match":
            raise ValueError("Forecast current currently supports model=best_match")
        params = {
            "latitude": latitude, "longitude": longitude,
            "current": ",".join(HOURLY_FIELDS), "timezone": "GMT",
        }
        return "https://api.open-meteo.com/v1/forecast?" + urlencode(params)
    raise ValueError("Unsupported source")


def parse_response(data: dict, source: str, valid_time: str | None,
                   latitude: float, longitude: float, model: str,
                   raw_sha: str) -> dict:
    if not isinstance(data, dict) or data.get("error"):
        raise ValueError("API error or invalid JSON envelope")
    if data.get("utc_offset_seconds") != 0:
        raise ValueError("Weather API timezone must be GMT (UTC offset 0)")
    grid_lat = require_finite("model grid latitude", data.get("latitude"), -90, 90)
    grid_lon = require_finite("model grid longitude", data.get("longitude"), -180, 180)
    if abs(grid_lat - latitude) > 2 or abs(grid_lon - longitude) > 2:
        raise ValueError("Weather grid point is too far from requested site")
    if source == "archive":
        obj = data.get("hourly")
        units = data.get("hourly_units")
        if not isinstance(obj, dict) or not isinstance(units, dict):
            raise ValueError("Missing archived hourly weather data or units")
        times = obj.get("time")
        if not isinstance(times, list) or not times:
            raise ValueError("Missing hourly time array")
        expected_time = utc_iso(valid_time)
        try:
            index = [utc_iso(t) for t in times].index(expected_time)
        except ValueError as exc:
            raise ValueError(f"Requested archive timestamp absent: {expected_time}") from exc
        values = {}
        for field in HOURLY_FIELDS:
            a = obj.get(field)
            if not isinstance(a, list) or len(a) != len(times):
                raise ValueError(f"Missing/incomplete hourly channel: {field}")
            if units.get(field) != EXPECTED_UNITS[field]:
                raise ValueError(f"Unsupported {field} units: {units.get(field)}")
            values[field] = a[index]
        timestamp = expected_time
    elif source == "forecast-current":
        obj = data.get("current")
        units = data.get("current_units")
        if not isinstance(obj, dict) or not isinstance(units, dict):
            raise ValueError("Missing current weather or units")
        for field in HOURLY_FIELDS:
            if units.get(field) != EXPECTED_UNITS[field] or field not in obj:
                raise ValueError(f"Missing {field} or unsupported units")
        values = {field: obj[field] for field in HOURLY_FIELDS}
        timestamp = utc_iso(obj.get("time"))
    else:
        raise ValueError(f"Unsupported source: {source}")

    temp_C = require_finite("temperature_2m °C", values["temperature_2m"], -80, 65)
    pressure_hpa = require_finite("surface_pressure hPa", values["surface_pressure"], 650, 1100)
    humidity_pct = require_finite("relative_humidity_2m %", values["relative_humidity_2m"], 0, 100)
    return {
        "valid_time_utc": timestamp,
        "site_latitude_requested": latitude,
        "site_longitude_requested": longitude,
        "model_grid_latitude": grid_lat,
        "model_grid_longitude": grid_lon,
        "temperature_K": temp_C + 273.15,
        "surface_pressure_Pa": pressure_hpa * 100.0,
        "relative_humidity_fraction": humidity_pct / 100.0,
        "source_type": source,
        "requested_model": model,
        "raw_sha256": raw_sha,
    }


def read_reference_case(path: Path) -> tuple[dict, str]:
    raw = path.read_bytes()
    text = raw.decode("utf-8")
    lines = [line for line in text.splitlines() if line.strip()
             and not line.lstrip().startswith(("#", "!"))]
    rows = list(csv.DictReader(lines))
    if len(rows) != 1 or not lines or lines[0].split(",") != ENGINE_FIELDS:
        raise ValueError("Reference case must contain one row with exact 18-field schema")
    row = rows[0]
    if set(row) != set(ENGINE_FIELDS) or any(v is None or not v.strip() for v in row.values()):
        raise ValueError("Incomplete reference machine deck")
    # This importer makes NO claim that the reference deck is independently validated.
    return row, sha256(raw).hexdigest()


def write_outputs(boundary: dict, args, url: str, retrieved: str, raw: bytes):
    path = args.output
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=FIELD_NAMES)
        writer.writeheader()
        writer.writerow(boundary)

    manifest = {
        "schema": "thermotwin.weather_boundary.v1",
        "observed_engine_measurement": False,
        "meteo_type": "reanalysis" if args.source == "archive" else "forecast_model_estimate",
        "flange_condition_measured": False,
        "weather_source": "Open-Meteo",
        "weather_license": "CC BY 4.0; weather data by Open-Meteo.com",
        "noncommercial_api_terms": "https://open-meteo.com/en/terms",
        "source_url": url, "retrieved_at_utc": retrieved,
        "valid_time_utc": boundary["valid_time_utc"],
        "raw_response_sha256": boundary["raw_sha256"],
        "requested_model": args.model,
        "requested_coordinates": [args.latitude, args.longitude],
        "returned_grid_coordinates": [
            boundary["model_grid_latitude"], boundary["model_grid_longitude"]
        ],
        "weather_boundary_csv": str(path),
        "units": {"temperature_K": "K", "surface_pressure_Pa": "Pa",
                  "relative_humidity_fraction": "fraction"},
        "humidity_used_in_thermotwin_physics": False,
        "temperature_is_2m_air_not_compressor_flange": True,
    }
    if args.reference_case is not None:
        reference, ref_sha = read_reference_case(args.reference_case)
        reference["case_name"] = "open_meteo_site_model"
        reference["ambient_T_K"] = format(boundary["temperature_K"], ".10g")
        reference["ambient_P_Pa"] = format(boundary["surface_pressure_Pa"], ".10g")
        reference["relative_humidity"] = format(boundary["relative_humidity_fraction"], ".10g")
        site_file = path.with_name(path.stem + "_case.csv")
        with site_file.open("w", encoding="utf-8", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=ENGINE_FIELDS)
            writer.writeheader()
            writer.writerow(reference)
        manifest["site_model_case_csv"] = str(site_file)
        manifest["hardware_deck_path"] = str(args.reference_case)
        manifest["hardware_deck_sha256"] = ref_sha
        manifest["hardware_calibration_not_verified_by_weather_data"] = True
    if args.snapshot is not None:
        args.snapshot.parent.mkdir(parents=True, exist_ok=True)
        args.snapshot.write_bytes(raw)
        manifest["raw_response_saved_at"] = str(args.snapshot)
    manifest_path = path.with_suffix(".manifest.json")
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest_path


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", choices=("archive", "forecast-current"), required=True)
    parser.add_argument("--latitude", type=float, required=True)
    parser.add_argument("--longitude", type=float, required=True)
    parser.add_argument("--valid-time", help="UTC timestamp (archive only)")
    parser.add_argument("--model", choices=("era5", "era5_land", "best_match"), required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference-case", type=Path, help="Existing, separately validated engine-input deck")
    parser.add_argument("--snapshot", type=Path, help="Optional exact raw HTTP response snapshot")
    parser.add_argument("--response-json", type=Path,
                        help="Replay a previously collected raw API response; never treated as live retrieval")
    args = parser.parse_args(argv)
    if args.source == "archive" and args.model == "best_match":
        parser.error("Archive must select explicit ERA5 or ERA5-Land")
    if args.source == "forecast-current" and args.model != "best_match":
        parser.error("Forecast-current requires model=best_match")
    url = build_url(args.source, args.latitude, args.longitude, args.valid_time, args.model)
    if args.response_json:
        raw = args.response_json.read_bytes()
        retrieved = "replay-from-supplied-snapshot-not-live"
    else:
        request = Request(url, headers={"User-Agent": "ThermoTwin-F-research-weather/1.0"})
        with urlopen(request, timeout=25) as response:
            if response.status != 200:
                raise ValueError(f"Weather API returned HTTP {response.status}")
            raw = response.read(2_000_001)
            if len(raw) > 2_000_000:
                raise ValueError("Weather response exceeds 2 MB safety limit")
        retrieved = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    data = json.loads(raw)
    digest = sha256(raw).hexdigest()
    boundary = parse_response(data, args.source, args.valid_time,
                              args.latitude, args.longitude, args.model, digest)
    manifest = write_outputs(boundary, args, url, retrieved, raw)
    print(f"Weather model: {args.source}, valid UTC {boundary['valid_time_utc']}")
    print(f"2m air T={boundary['temperature_K']:.3f} K; surface P={boundary['surface_pressure_Pa']:.1f} Pa")
    print(f"Boundary CSV: {args.output}; provenance manifest: {manifest}")
    print("Not a station or turbine measurement; humidity correction remains unsupported.")


if __name__ == "__main__":
    main()
