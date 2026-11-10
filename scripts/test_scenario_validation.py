"""Black-box scenario failure-path regression on the *built* Fortran executable.

The inputs below are algebraic parser/logic fixtures, not measurements, and
the test does not claim physical validation of grid operations.
"""
from __future__ import annotations

import argparse
import csv
import subprocess
import tempfile
from pathlib import Path


def verify(exe: Path) -> None:
    cases = [
        ("valid control and assertion", "duration 1\ndt 0.25\nat 0.5 assert_above demand_MW 1", True),
        ("negative duration", "duration -1", False),
        ("zero time step", "duration 1\ndt 0", False),
        ("nonfinite step", "duration 1\ndt NaN", False),
        ("nonfinite duration", "duration Infinity", False),
        ("unbounded step count", "duration 1e14\ndt 1e-6", False),
        ("trailing invalid tokens", "duration 1 extra", False),
        ("event beyond duration", "duration 1\nat 2 assert_above demand_MW 0", False),
        ("negative event time", "duration 1\nat -1 set demand_MW 20", False),
        ("unreachable end-of-window set", "duration 1\nat 1 set demand_MW 20", False),
        ("negative assertion tolerance", "duration 1\nat 0.5 assert_near frequency_Hz 50 -0.1", False),
        ("unknown set target", "duration 1\nat 0 set demand_typo 40", False),
        ("unknown command", "duration 1\nat 0 command typo", False),
        ("failed assertion", "duration 1\nat 0.5 assert_above demand_MW 1000", False),
        ("partial final tick assertion evaluated", "duration 0.6\ndt 0.25\nat 0.6 assert_above demand_MW 1000", False),
    ]
    passed = 0
    with tempfile.TemporaryDirectory(prefix="thermotwin-scenario-qc-") as directory:
        root = Path(directory)
        for i, (name, text, expected_success) in enumerate(cases):
            f = root / f"case_{i}.scn"
            f.write_text(text + "\n", encoding="utf-8")
            result = subprocess.run([str(exe), "scenario", "run", str(f)],
                                    capture_output=True, text=True, timeout=40, cwd=root)
            ok = (result.returncode == 0) == expected_success
            print(f"{'PASS' if ok else 'FAIL'} scenario QC: {name}")
            if not ok:
                raise AssertionError(
                    f"Scenario {name} wrong exit code {result.returncode}:\n"
                    f"{result.stdout}\n{result.stderr}")
            passed += 1
        valid = root / "valid.scn"
        valid.write_text("duration 1\ndt 0.25\nat 0.5 assert_above demand_MW 1\n")
        rec = root / "trace.csv"
        ok = subprocess.run([str(exe), "scenario", "run", str(valid),
                             "--record", str(rec)],
                            capture_output=True, text=True, timeout=40, cwd=root)
        if ok.returncode != 0 or not rec.exists():
            raise AssertionError(f"Recorder failed: {ok.stdout}\n{ok.stderr}")
        with rec.open(newline="") as stream:
            rows = list(csv.DictReader(stream))
        if len(rows) != 4 or "frequency_Hz" not in rows[0]:
            raise AssertionError("Scenario recorder schema/count mismatch")
        passed += 1

        missing_parent = root / "missing" / "trace.csv"
        failed = subprocess.run([str(exe), "scenario", "run", str(valid),
                                 "--record", str(missing_parent)],
                                capture_output=True, text=True, timeout=40, cwd=root)
        if failed.returncode == 0:
            raise AssertionError("Missing recorder directory was silently accepted")
        passed += 1
    print(f"Scenario fail-closed QC: {passed}/{passed} mathematical checks passed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--executable", type=Path, required=True)
    args = parser.parse_args()
    exe = args.executable.resolve()
    if not exe.is_file():
        parser.error(f"Executable does not exist: {exe}")
    verify(exe)


if __name__ == "__main__":
    main()
