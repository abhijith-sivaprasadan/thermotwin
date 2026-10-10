"""Compile serial/OpenMP batch drivers, verify every result and measure wall time."""

import argparse
import json
import os
import platform
import shutil
import statistics
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULES = [
    "precision_kinds", "constants", "types", "utilities", "fluid_properties",
    "ambient", "compressor", "combustor", "turbine", "shaft_generator",
    "cycle_solver", "sensitivity_driver",
]


def compile_driver(folder, openmp, compiler):
    folder.mkdir(parents=True, exist_ok=True)
    exe = folder / ("benchmark.exe" if os.name == "nt" else "benchmark")
    command = [compiler, "-O2", "-std=f2008", "-ffree-line-length-none",
               "-J", str(folder), "-I", str(folder)]
    if openmp:
        command.append("-fopenmp")
    command += [str(ROOT / "src" / (name + ".f90")) for name in MODULES]
    command += [str(ROOT / "scripts/benchmark_cases.f90"), "-o", str(exe)]
    subprocess.run(command, check=True)
    return exe


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=int, default=500000)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--output", type=Path, default=ROOT / "docs/openmp_benchmark.json")
    parser.add_argument("--compiler", default="gfortran")
    args = parser.parse_args()
    if args.cases < 1 or args.repeats < 1:
        parser.error("cases and repeats must be positive")
    try:
        import psutil
        cores = psutil.cpu_count(logical=False)
        core_basis = "physical cores (psutil)"
    except ImportError:
        cores = os.cpu_count()
        core_basis = "logical CPUs (physical count unavailable)"
    cores = cores or 1
    compiler = shutil.which(args.compiler)
    if not compiler:
        parser.error("gfortran is required")
    build = ROOT / "build/openmp-benchmark"
    serial = compile_driver(build / "serial", False, compiler)
    parallel = compile_driver(build / "parallel", True, compiler)
    rows = []
    for mode, threads, exe in [("serial", 1, serial)] + [
        ("openmp", n, parallel) for n in (1, 2, 4, 8) if n <= cores
    ]:
        times = []
        errors = []
        env = dict(os.environ, OMP_NUM_THREADS=str(threads), OMP_DYNAMIC="FALSE")
        for _ in range(args.repeats):
            output = subprocess.check_output([str(exe), str(args.cases)], env=env, text=True)
            result = dict(line.split("=", 1) for line in output.splitlines() if "=" in line)
            if int(result["threads"]) != threads:
                raise RuntimeError("runtime did not use the requested thread count")
            if int(result["cases_verified"]) != args.cases:
                raise RuntimeError("incomplete verification")
            times.append(float(result["wall_seconds"]))
            errors.append(float(result["max_relative_error"]))
        if min(times) <= 0:
            raise RuntimeError("workload too small for timer resolution; increase --cases")
        rows.append({"mode": mode, "threads": threads, "seconds": times,
                     "median_seconds": statistics.median(times), "max_relative_error": max(errors)})
    baseline = rows[0]["median_seconds"]
    for row in rows:
        row["speedup"] = baseline / row["median_seconds"]
        row["ideal_speedup"] = row["threads"]
    report = {"platform": platform.platform(), "processor": platform.processor(),
              "compiler": subprocess.check_output([compiler, "--version"], text=True).splitlines()[0],
              "core_count": cores, "core_basis": core_basis, "cases": args.cases,
              "repeats": args.repeats, "timing_scope": "run_cases only; setup and full serial verification excluded",
              "rows": rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("mode threads median_wall_s speedup ideal_speedup max_relative_error")
    for row in rows:
        print(f"{row['mode']} {row['threads']} {row['median_seconds']:.6f} "
              f"{row['speedup']:.4f} {row['ideal_speedup']} {row['max_relative_error']:.3g}")


if __name__ == "__main__":
    main()
