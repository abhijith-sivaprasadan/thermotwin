"""Source-derived CLI argument and physical-status negative regression tests.

Values are derived from bundled teaching cases and are not actual engine data.
"""
from __future__ import annotations

import argparse
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def check(exe: Path):
    source = ROOT / "cases" / "design_point.csv"
    rows = [s for s in source.read_text(encoding="utf-8").splitlines()
            if s.strip() and not s.lstrip().startswith(("#", "!"))]
    header, row = rows[0], rows[1]
    # Assemble controlled negative-input mathematical fixtures, not telemetry.
    columns = row.split(",")
    columns[8] = "750"  # TIT below compressor exit -> nonphysical, non-converged
    with tempfile.TemporaryDirectory(prefix="thermotwin-cli-guard-") as work:
        root = Path(work)
        invalid_case = root / "invalid.csv"
        invalid_case.write_text(header + "\n" + ",".join(columns) + "\n")
        valid_out = root / "valid.csv"
        invalid_out = root / "invalid-results.csv"
        scenario = ROOT / "cases/scenarios/load_step.scn"
        cases = [
            ("help", ["--help"], True),
            ("normal run", ["run", str(source), str(valid_out)], True),
            ("missing arguments", ["run"], False),
            ("extra run arguments", ["run", str(source), str(valid_out), "extra"], False),
            ("extra site arguments", ["site", str(source), str(source), "x.csv", "extra"], False),
            ("empty input filename", ["run", ""], False),
            ("overlong input filename", ["run", "x" * 1100], False),
            ("extra selftest argument", ["selftest", "extra"], False),
            ("extra degradation argument", ["degradation", str(source), "extra"], False),
            ("duplicate scenario recorder", ["scenario", "run", str(scenario),
                                             "--record", str(root / "r1.csv"),
                                             "--record", str(root / "r2.csv")], False),
            ("invalid physical run exits nonzero",
             ["run", str(invalid_case), str(invalid_out)], False),
        ]
        passed = 0
        for name, args, expected_success in cases:
            result = subprocess.run([str(exe), *args], cwd=root, text=True,
                                    capture_output=True, timeout=50)
            ok = (result.returncode == 0) == expected_success
            print(f"{'PASS' if ok else 'FAIL'} CLI guard: {name}")
            if not ok:
                raise AssertionError(
                    f"{name}: status={result.returncode}\n"
                    f"{result.stdout}\n{result.stderr}")
            passed += 1
        if not valid_out.is_file() or not invalid_out.is_file():
            raise AssertionError("Must preserve both converged and rejected CSV outputs")
        if "converged" not in invalid_out.read_text(encoding="utf-8"):
            raise AssertionError("Rejected run lacks status columns")
        print(f"CLI guard: {passed}/{passed} source-derived negative/identity checks passed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    args = parser.parse_args()
    exe = args.executable.resolve()
    if not exe.is_file():
        parser.error(f"Missing compiled executable: {exe}")
    check(exe)
