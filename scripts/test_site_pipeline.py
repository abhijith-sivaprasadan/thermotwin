#!/usr/bin/env python3
"""End-to-end site-case regression, including synthetic fixture reproducibility."""
from __future__ import annotations
import argparse
import csv
import math
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REFERENCE = ROOT / "cases" / "design_point.csv"
SWEEP = ROOT / "cases" / "site_sweep.csv"


def execute(exe: Path, inputs: Path, result_path: Path):
    return subprocess.run(
        [str(exe), "site", str(REFERENCE), str(inputs), str(result_path)],
        cwd=ROOT, capture_output=True, text=True, check=False,
    )


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--executable", type=Path, required=True)
    args = ap.parse_args()
    exe = args.executable.resolve()
    with tempfile.TemporaryDirectory(prefix="ttf-site-") as work:
        work = Path(work)
        generated = work / "regenerated.csv"
        subprocess.run([sys.executable, str(ROOT / "scripts/generate_site_cases.py"),
                        "--output", str(generated)], cwd=ROOT, check=True)
        # Git can check out text files with CRLF on Windows. Compare logical
        # CSV content rather than platform-specific newline bytes.
        if (generated.read_text(encoding="utf-8").splitlines() !=
                SWEEP.read_text(encoding="utf-8").splitlines()):
            raise AssertionError("checked-in synthetic site fixture is not reproducible")

        result = work / "results.csv"
        proc = execute(exe, SWEEP, result)
        if proc.returncode:
            raise AssertionError(f"site CLI failed: {proc.stdout[-1500:]} {proc.stderr[-1500:]}")

        with result.open(newline="", encoding="utf-8") as file:
            rows = list(csv.DictReader(file))
        if len(rows) != 26 or any(row["valid"] != "1" for row in rows):
            raise AssertionError("expected all 26 synthetic site cases to be accepted")

        by_name = {row["case_name"]: row for row in rows}
        iso = by_name["ISO_identity"]
        for key in ("power_derate_ratio", "power_correction_ref_per_site",
                    "heat_rate_correction_ref_per_site",
                    "exhaust_flow_correction_ref_per_site"):
            if not math.isclose(float(iso[key]), 1.0, abs_tol=1e-8, rel_tol=1e-8):
                raise AssertionError(f"ISO identity failed: {key}: {iso[key]}")
        if abs(float(iso["exhaust_T_additive_ref_minus_site_K"])) > 1e-7:
            raise AssertionError("ISO exhaust temperature correction must be zero")

        reference_power = float(iso["reference_net_power_MW"])
        for row in rows:
            if not math.isclose(float(row["reference_net_power_MW"]), reference_power,
                                rel_tol=1e-8, abs_tol=1e-6):
                raise AssertionError("reference machine recalibrated on site conditions")
            factor = float(row["power_correction_ref_per_site"])
            site_power = float(row["site_net_power_MW"])
            if not math.isclose(site_power*factor, reference_power,
                                rel_tol=1e-7, abs_tol=1e-5):
                raise AssertionError(f"site correction round-trip fails for {row['case_name']}")
        for name in ("site_inlet_loss", "site_exhaust_loss", "site_combined",
                     "site_T4_P0"):
            if float(by_name[name]["power_derate_ratio"]) >= 1.0:
                raise AssertionError(f"expected site derating for {name}")

        # A changed humidity cannot silently get a valid correction factor.
        bad = dict(iso)
        input_rows = list(csv.DictReader(SWEEP.open(newline="", encoding="utf-8")))
        header = input_rows[0].keys()
        for field, value, label in (
            ("relative_humidity", "0.85", "unsupported humidity"),
            ("eta_compressor", "0.75", "changed hardware"),
            ("ambient_P_Pa", "60000", "out-of-envelope pressure"),
        ):
            changed = dict(input_rows[0])
            changed[field] = value
            bad_case = work / "invalid.csv"
            with bad_case.open("w", newline="", encoding="utf-8") as output:
                writer = csv.DictWriter(output, fieldnames=header, lineterminator="\n")
                writer.writeheader()
                writer.writerow(changed)
            bad_output = work / "invalid_results.csv"
            proc = execute(exe, bad_case, bad_output)
            if proc.returncode == 0 or not bad_output.exists():
                raise AssertionError(f"invalid {label} unexpectedly accepted or not logged")
            with bad_output.open(newline="", encoding="utf-8") as file:
                rejected = list(csv.DictReader(file))
            if len(rejected) != 1 or rejected[0]["valid"] != "0":
                raise AssertionError(f"invalid {label} did not get a rejection status")
        print("PASS site: 26 deterministic cases, ISO identity, fixed hardware, "
              "round trips and 3 invalid-input ledger tests")


if __name__ == "__main__":
    main()
