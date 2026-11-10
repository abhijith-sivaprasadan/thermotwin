#!/usr/bin/env python3
"""Acquire and audit the original UCI #551 gas-turbine operational dataset.

Source: https://archive.ics.uci.edu/dataset/551/
DOI: 10.24432/C5WC95. CC BY 4.0; original data contain one turbine,
with within-year chronological records and NO exact per-record timestamps.
This importer creates no manufactured engine IDs or measurements.
"""
from __future__ import annotations

import argparse
import csv
from datetime import datetime, timezone
from hashlib import sha256
import io
import json
import math
from pathlib import Path
from urllib.request import Request, urlopen
import zipfile

UCI_URL = "https://archive.ics.uci.edu/static/public/551/gas+turbine+co+and+nox+emission+data+set.zip"
SOURCE = "https://archive.ics.uci.edu/dataset/551/gas+turbine+co+and+nox+emission+data+set"
YEAR_COUNTS = {2011: 7411, 2012: 7628, 2013: 7152, 2014: 7158, 2015: 7384}
VARIABLES = ("AT", "AP", "AH", "AFDP", "GTEP", "TIT", "TAT",
             "TEY", "CDP", "CO", "NOX")
SOURCE_UNITS = {
    "AT": "degC", "AP": "mbar", "AH": "%",
    "AFDP": "mbar", "GTEP": "mbar", "TIT": "degC",
    "TAT": "degC", "TEY": "MWh (source label; hour-aggregation meaning review required)",
    "CDP": "mbar (source label; physically ambiguous, DO NOT derive compressor ratio)",
    "CO": "mg/m3", "NOX": "mg/m3",
}
# Broad quality limits only for rejecting corrupt parses, not control limits.
RANGES = {
    "AT": (-60, 80), "AP": (850, 1150), "AH": (0, 110),
    "AFDP": (0, 25), "GTEP": (0, 75), "TIT": (700, 1300),
    "TAT": (300, 800), "TEY": (0, 300), "CDP": (0, 50),
    "CO": (0, 200), "NOX": (0, 300),
}


def parse_annual_csv(raw: bytes, year: int) -> tuple[list[dict], str]:
    if year not in YEAR_COUNTS:
        raise ValueError("Unknown year in UCI #551")
    content = raw.decode("utf-8-sig")
    sample = content[:4096]
    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=",;\t")
    except csv.Error:
        dialect = csv.excel
    reader = csv.DictReader(io.StringIO(content), dialect=dialect)
    if reader.fieldnames is None:
        raise ValueError(f"Missing header for UCI {year}")
    names = [name.strip() for name in reader.fieldnames]
    if len(names) != len(VARIABLES) or set(names) != set(VARIABLES):
        raise ValueError(f"Unexpected {year} UCI field schema: {names}")
    rows = []
    for i, row in enumerate(reader, start=1):
        if None in row or any(v is None or not str(v).strip() for v in row.values()):
            raise ValueError(f"{year} row {i}: missing/extra fields")
        clean = {}
        for name in VARIABLES:
            try:
                x = float(row[name])
            except (ValueError, TypeError) as exc:
                raise ValueError(f"{year} row {i}: bad {name}") from exc
            lo, hi = RANGES[name]
            if not math.isfinite(x) or not lo <= x <= hi:
                raise ValueError(f"{year} row {i}: invalid {name}={x}")
            clean[name] = x
        rows.append(clean)
    expected = YEAR_COUNTS[year]
    if len(rows) != expected:
        raise ValueError(f"{year}: {len(rows)} rows, expected {expected}")
    return rows, sha256(raw).hexdigest()


def load_package(zip_bytes: bytes) -> dict[int, tuple[list[dict], str, str]]:
    if len(zip_bytes) > 25_000_000:
        raise ValueError("UCI original archive unexpectedly large")
    try:
        archive = zipfile.ZipFile(io.BytesIO(zip_bytes))
    except zipfile.BadZipFile as exc:
        raise ValueError("Source dataset is not a valid ZIP") from exc
    entries = {}
    for info in archive.infolist():
        if info.is_dir():
            continue
        for year in YEAR_COUNTS:
            if Path(info.filename).name.lower() == f"gt_{year}.csv":
                if year in entries:
                    raise ValueError(f"Duplicate year {year} in original dataset")
                if info.file_size > 4_000_000:
                    raise ValueError(f"Too-large year CSV: {year}")
                rows, digest = parse_annual_csv(archive.read(info), year)
                entries[year] = (rows, digest, info.filename)
    if set(entries) != set(YEAR_COUNTS):
        raise ValueError(f"Original UCI ZIP missing annual CSVs; found {sorted(entries)}")
    if sum(len(item[0]) for item in entries.values()) != 36733:
        raise ValueError("Unexpected total UCI count")
    return entries


def execute(argv=None) -> dict:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--original-zip", type=Path,
                        help="Read an archived original ZIP without a network call")
    args = parser.parse_args(argv)
    if args.original_zip:
        raw = args.original_zip.read_bytes()
        retrieval = "replay-from-archive-not-live"
    else:
        request = Request(UCI_URL, headers={"User-Agent": "ThermoTwin-F-research-data/1.0"})
        with urlopen(request, timeout=40) as response:
            if response.status != 200:
                raise ValueError(f"UCI returned HTTP {response.status}")
            raw = response.read(25_000_001)
        if len(raw) > 25_000_000:
            raise ValueError("ZIP exceeds 25 MB limit")
        retrieval = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    entries = load_package(raw)
    out = args.output_dir
    out.mkdir(parents=True, exist_ok=True)
    (out / "uci551_original.zip").write_bytes(raw)
    annual = {}
    for year in sorted(entries):
        rows, original_hash, path = entries[year]
        output = out / f"gt_{year}_audited.csv"
        with output.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=("year", "within_year_row", *VARIABLES))
            writer.writeheader()
            for i, row in enumerate(rows, start=1):
                writer.writerow({"year": year, "within_year_row": i, **row})
        annual[str(year)] = {
            "source_archive_member": path,
            "original_csv_sha256": original_hash,
            "rows": len(rows),
            "audited_csv": output.name,
            "audited_csv_sha256": sha256(output.read_bytes()).hexdigest(),
        }
    manifest = {
        "schema": "thermotwin.uci551.source_audit.v1",
        "source": SOURCE, "source_download": UCI_URL,
        "doi": "10.24432/C5WC95", "license": "CC BY 4.0",
        "original_zip_sha256": sha256(raw).hexdigest(),
        "retrieved_at_utc": retrieval, "years": annual,
        "total_rows": sum(k["rows"] for k in annual.values()),
        "number_of_turbines": 1,
        "actual_utc_timestamps_present": False,
        "intra_year_order": "as published; do not manufacture timestamps",
        "source_field_units": SOURCE_UNITS,
        "unresolved_units": ["CDP: source says mbar despite physically suspicious scale",
                             "TEY: source says MWH; precise hourly time-aggregation conventions"],
        "test_policy": {"development": [2011, 2012, 2013], "untouched_test": [2014, 2015]},
        "is_production_engine_population": False,
        "is_passoff_test_dataset": False,
        "is_si_turbine_model_validation": False,
        "attribution": "Gas Turbine CO and NOx Emission Data Set (2019). UCI Machine Learning Repository. DOI 10.24432/C5WC95.",
    }
    (out / "manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(f"UCI #551: {manifest['total_rows']} real hourly records, {len(annual)} annual files")
    print(f"Original ZIP SHA-256: {manifest['original_zip_sha256']}")
    print("One turbine only; no confirmed engine-fault labels, exact timestamps or pass-off data.")
    return manifest


if __name__ == "__main__":
    execute()
