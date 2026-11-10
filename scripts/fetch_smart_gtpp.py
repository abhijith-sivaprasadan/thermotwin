#!/usr/bin/env python3
"""Fetch original SMART-GTPP measured turbine records and inspect their schema.

Provenance-only. Does not claim a thermodynamic or OEM engine validation.
Original source DOI 10.17632/6sk3mhm7hb.1, CC BY 4.0, 2026.
"""
from __future__ import annotations
import argparse
import csv
from hashlib import sha256
import io
import json
import math
from pathlib import Path
from urllib.request import Request, urlopen

DOI = "10.17632/6sk3mhm7hb.1"
URL = ("https://data.mendeley.com/public-files/datasets/6sk3mhm7hb/files/"
       "1b4d93cf-964d-4680-bd58-d9c5a5e5fe09/file_downloaded")
FIELDS = ("AT", "AP", "DF", "CH", "GP", "CPR", "CPD", "TTXM", "EP")
ORIGINAL_SHA256 = "bcfd39b0a5663add458e12cb6f7333436e1bd4206d8e79777d5878f596b0e9fa"
ORIGINAL_RECORDS = 7893


def acquire(out: Path, original: Path | None = None):
    out.mkdir(parents=True, exist_ok=True)
    if original is None:
        with urlopen(Request(URL, headers={"User-Agent":"ThermoTwin-F-scientific-research/1.0"}),
                     timeout=35) as f:
            raw = f.read(5_000_001)
    else:
        raw = original.read_bytes()
    if not 300 < len(raw) <= 5_000_000:
        raise ValueError("Original dataset unexpected size or truncated")
    if b"\x00" in raw:
        raise ValueError("Source is not plain CSV (null byte)")
    text = raw.decode("utf-8-sig")
    data = csv.DictReader(io.StringIO(text))
    if data.fieldnames is None:
        raise ValueError("No source CSV columns")
    columns = list(data.fieldnames)
    if len(columns) != len(set(columns)):
        raise ValueError("Duplicate source column headings")
    rows = list(data)
    if not rows or any(None in r or None in r.values() for r in rows):
        raise ValueError("Truncated or incomplete original dataset CSV")
    digest = sha256(raw).hexdigest()
    if digest != ORIGINAL_SHA256:
        raise ValueError("Original SMART-GTPP fixed-version checksum mismatch; refuse changed upstream bytes")
    if columns != list(FIELDS) or len(rows) != ORIGINAL_RECORDS:
        raise ValueError("Original SMART-GTPP fixed-version column and row identity mismatch")
    for row in rows:
        for field in FIELDS:
            try:
                value = float(row[field])
            except (TypeError, ValueError) as exc:
                raise ValueError(f"Original measured source has missing/nonnumeric field: {field}") from exc
            if not math.isfinite(value):
                raise ValueError(f"Original measured source has nonfinite field: {field}")
    (out/"smart_gtpp_original.csv").write_bytes(raw)
    summary = {"source_doi":DOI, "original_url":URL,
       "source_file_sha256":digest, "byte_length":len(raw),
       "records":len(rows), "raw_source_columns":columns,
       "license":"CC BY 4.0; Ameen and Hamarash, 2026",
       "observational_dataset_not_physics_calibration":True,
       "source_utc_timestamp_field_verified":False,
       "air_mass_flow_available":False,"fuel_mass_flow_available":False,
       "fuel_LHV_available":False,"OEM_hardware_maps_available":False,
       "turbine_model_absolute_power_validation":False}
    for col in columns:
        vals=[]
        for row in rows:
            try:
                v=float(row[col])
            except (ValueError, TypeError):
                continue
            if math.isfinite(v): vals.append(v)
        summary.setdefault("source_column_finite_counts",{})[col]=len(vals)
        if vals:
            summary.setdefault("source_column_range_unverified_units",{})[col]=[min(vals),max(vals)]
    (out/"source_overview.json").write_text(json.dumps(summary,indent=2,sort_keys=True)+"\n")
    print("SMART-GTPP source columns:",columns)
    print("original rows",len(rows),"SHA256",digest)
    print("No absolute physical model validity claim: fuel-flow, LHV and OEM maps absent.")
    return summary


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--out",type=Path,required=True)
    p.add_argument("--original",type=Path)
    args=p.parse_args()
    acquire(args.out,args.original)
