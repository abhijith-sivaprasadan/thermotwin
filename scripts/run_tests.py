#!/usr/bin/env python3
"""Run ThermoTwin-F unit tests and the application selftest.

This mirrors scripts/run_tests.sh but avoids relying on WSL-backed bash on
Windows, where Codex and MinGW builds commonly run.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


def run_binary(path: Path) -> tuple[bool, str]:
    completed = subprocess.run(
        [str(path)],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    return completed.returncode == 0, completed.stdout


ROOT = Path(__file__).resolve().parents[1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-dir", type=Path, default=ROOT / "build")
    args = parser.parse_args(argv)
    build_dir = args.build_dir.resolve()
    print("Running unit tests")
    print("==================")
    passed = 0
    failed = 0

    suffix = ".exe" if os.name == "nt" else ""
    sources = sorted((ROOT / "test").glob("test_*.f90"))
    tests = [build_dir / "tests" / (source.stem + suffix) for source in sources]
    missing = [path for path in tests if not path.is_file()]
    if not sources or missing:
        print("FAIL: unit-test suite is missing or incomplete. Build all test targets first.")
        for path in missing:
            print(f"  Missing {path}")
        return 1
    for test in tests:
        ok, output = run_binary(test)
        name = test.name
        if ok:
            print(f"  PASS  {name}")
            passed += 1
        else:
            print(f"  FAIL  {name}")
            for line in output.splitlines():
                print(f"        {line}")
            failed += 1

    print()
    print("Also running application selftest (physics verification)...")
    exe = build_dir / ("thermotwin" + suffix)
    if build_dir == ROOT / "build":
        exe = ROOT / ("thermotwin" + suffix)
    if exe.exists():
        completed = subprocess.run(
            [str(exe), "selftest"],
            cwd=ROOT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if completed.returncode == 0:
            print("  PASS  selftest")
            passed += 1
        else:
            print("  FAIL  selftest")
            for line in completed.stdout.splitlines():
                print(f"        {line}")
            failed += 1
    else:
        print("  FAIL  selftest")
        print(f"        Missing {exe.name}")
        failed += 1

    print()
    print(f"SUMMARY: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
