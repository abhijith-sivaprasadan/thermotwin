#!/usr/bin/env python3
"""Deterministically generate a synthetic reference-to-site GT study.

No manufacturer-specific map, measured data or customer guarantee is used.
The fixed hardware is cases/design_point.csv; relative humidity is held at
the unsupported model's fixed-reference assumption, not physically corrected.
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "cases" / "design_point.csv"


def build_rows():
    lines = [
        line for line in REFERENCE.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith(("#", "!"))
    ]
    original = list(csv.DictReader(lines))
    if len(original) != 1:
        raise ValueError("expected one fixed reference machine")
    baseline = original[0]
    fieldnames = list(baseline)
    cases = []

    def add(name, **change):
        row = baseline.copy()
        row["case_name"] = name
        row.update(change)
        cases.append(row)

    add("ISO_identity")
    temperatures = ["258.15", "273.15", "288.15", "303.15", "318.15"]
    pressures = ["80000", "90000", "101325", "105000"]
    for ti, temperature in enumerate(temperatures):
        for pi, pressure in enumerate(pressures):
            add(f"site_T{ti}_P{pi}", ambient_T_K=temperature, ambient_P_Pa=pressure)

    add("site_inlet_loss", inlet_pressure_loss="0.035")
    add("site_exhaust_loss", exhaust_pressure_loss="0.055")
    add("site_both_losses", inlet_pressure_loss="0.035", exhaust_pressure_loss="0.055")
    add("site_LHV_sensitivity", LHV_J_kg="45.0e6")
    add("site_combined", ambient_T_K="308.15", ambient_P_Pa="85000",
        inlet_pressure_loss="0.035", exhaust_pressure_loss="0.055")
    return fieldnames, cases


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", type=Path, default=ROOT / "cases" / "site_sweep.csv")
    opts = ap.parse_args()
    fields, rows = build_rows()
    opts.output.parent.mkdir(parents=True, exist_ok=True)
    with opts.output.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)
    print(f"Generated {len(rows)} synthetic site cases: {opts.output}")


if __name__ == "__main__":
    main()
