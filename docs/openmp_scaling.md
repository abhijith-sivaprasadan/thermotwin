# OpenMP batch operating-point scaling

The `sensitivity_driver.run_cases` loop calls the existing Brayton-cycle solver for independent operating points. Each iteration reads one input and writes one result. OpenMP uses `default(none)`, explicit shared/private variables and static scheduling. `solve_cycle` has no random-number draws or time-marching state; its call chain reads the property-model selector. The caller must not change that selector while the batch is running. Monte Carlo and transient loops are unchanged.

Enable with `make OPENMP=1`. The default remains a serial build. Use fresh build directories when changing compiler flags; existing objects are not automatically invalidated by Make. Cross-platform CI builds into separate directories for both modes.

Reproduce:

```sh
python -m pip install psutil
python scripts/benchmark_openmp.py --cases 500000 --repeats 3
```

The driver sweeps ambient temperature (273.15–313.15 K), pressure ratio (10–20) and turbine inlet temperature (1350–1500 K), using existing input fields. It times only the complete batch solve with a wall clock, excluding setup and verification. Every case is then checked against a direct serial solve, including all 25 numeric result fields, names, status and convergence. It compares with a relative tolerance of 1e-12; the measured maximum error was zero for every run. There is also a separately compiled binary with OpenMP directives disabled, which establishes the serial baseline.

## Local measurements

Measured 11 October 2026 on Windows, GNU Fortran 13.2.0, 8 physical cores. These are workstation measurements, not cluster evidence. Three trials per row; median shown, all raw trial values preserved in [openmp_benchmark.json](openmp_benchmark.json). Other workstation processes were not controlled; no affinity or dedicated-host scaling claim is made.

| Build | Threads | Wall time (s) | Speedup vs serial build | Ideal speedup |
| --- | ---: | ---: | ---: | ---: |
| serial | 1 | 0.343000 | 1.0000 | 1 |
| openmp | 1 | 0.328000 | 1.0457 | 1 |
| openmp | 2 | 0.203000 | 1.6897 | 2 |
| openmp | 4 | 0.141000 | 2.4326 | 4 |
| openmp | 8 | 0.078000 | 4.3974 | 8 |

The earlier 200,000-case pilot was noisier: serial 0.125 s; OpenMP 1/2/4/8 threads 0.203/0.109/0.063/0.047 s (speedups 0.6158/1.1468/1.9841/2.6596). In that pilot one OpenMP thread was slower than the serial binary. Larger workloads reduce timer/launch noise, but speedup is neither linear nor guaranteed. Per-case solve cost, allocation, memory bandwidth and scheduling overhead limit scaling.

## Verification scope

Existing Fortran verification/selftest suite and all 15 scenario regressions are run without changing their source or thresholds. Local release builds with and without OpenMP, and the OpenMP debug build, passed (29 checks including the selftest, plus 2 runner-completeness tests). CI repeats serial/OpenMP checks on Ubuntu, Windows and macOS in release/debug profiles and publishes its equivalence/timing artifact. A benchmark pass alone is not a complete scientific validation of the model.
