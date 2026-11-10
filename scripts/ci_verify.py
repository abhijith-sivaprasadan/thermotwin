"""Build with a fresh profile directory; run existing tests without editing them."""

import argparse
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(command):
    subprocess.run(command, cwd=ROOT, check=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=["release", "debug"], default="release")
    parser.add_argument("--openmp", choices=["0", "1"], default="1")
    args = parser.parse_args()
    build = "build/ci-" + args.profile + "-omp" + args.openmp
    suffix = ".exe" if os.name == "nt" else ""
    options = ["FC=" + os.environ.get("FC", "gfortran"), "BUILD=" + build,
               "EXE=" + build + "/thermotwin" + suffix, "OPENMP=" + args.openmp]
    if args.profile == "debug":
        options.append("FFLAGS=-J " + build + " -I " + build +
                       " -ffree-line-length-none -std=f2008 -O0 -g -fcheck=all -fbacktrace -Wall -Wextra -fimplicit-none" +
                       (" -fopenmp" if args.openmp == "1" else ""))
    run(["make", "-j4", *options, "all", "tests"])
    run(["python", "scripts/run_tests.py", "--build-dir", build])
    run(["python", "scripts/test_run_tests.py"])
    run(["python", "scripts/test_csv_validation.py", "--executable",
         str(ROOT / build / ("thermotwin" + suffix))])
    run(["python", "scripts/test_site_pipeline.py", "--executable",
         str(ROOT / build / ("thermotwin" + suffix))])
    # Exercise all scenario fixtures and retain evidence about *every* failure.
    # One broken scenario must not hide other regression failures.
    failures = []
    for case in sorted((ROOT / "cases/scenarios").glob("*.scn")):
        try:
            run([str(ROOT / build / ("thermotwin" + suffix)), "scenario", "run", str(case)])
        except subprocess.CalledProcessError:
            failures.append(case.name)
    if failures:
        raise SystemExit("Failed scenarios: " + ", ".join(failures))
    run(["python", "scripts/test_scenario_validation.py", "--executable",
         str(ROOT / build / ("thermotwin" + suffix))])


if __name__ == "__main__":
    main()
