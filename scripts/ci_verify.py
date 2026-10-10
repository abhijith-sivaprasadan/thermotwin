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
    # Exercise all existing scenario fixtures with the built profile executable.
    for case in sorted((ROOT / "cases/scenarios").glob("*.scn")):
        run([str(ROOT / build / ("thermotwin" + suffix)), "scenario", "run", str(case)])


if __name__ == "__main__":
    main()
