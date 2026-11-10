# ThermoTwin-F

[![CI](https://github.com/abhijith-sivaprasadan/thermotwin/actions/workflows/ci.yml/badge.svg)](https://github.com/abhijith-sivaprasadan/thermotwin/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Fortran 2008](https://img.shields.io/badge/Fortran-2008-blueviolet.svg)](https://fortran-lang.org)

**An inspectable gas-turbine, combined-cycle, and grid-operation simulator in Modern Fortran.**

ThermoTwin-F connects component thermodynamics to plant operation: establish a design point, study degradation and uncertainty, infer a synthetic fault, then replay plant and grid events with executable assertions. Use the command-line tools for repeatable engineering studies or the native Windows HMI for interactive exploration.

This is a research and educational model. Its tests provide numerical verification and software regression coverage; it has **not been calibrated or independently validated against a commercial engine or operating plant**. It does not establish compliance with ASME PTC 22, ISO 2314, or grid codes. Model assumptions and verification evidence are part of the deliverable, alongside the results.

[Quick start](#quick-start) · [Capabilities](#capabilities) · [CLI reference](#command-line-reference) · [Engineering guide](docs/ENGINEERING_GUIDE.md) · [Verification](docs/verification_matrix.md) · [Windows HMI](gui/README.md)

## Quick start

Run commands from the repository root, where `Makefile`, `src/`, and `cases/` live.

| Requirement | Purpose |
|---|---|
| GNU Fortran (`gfortran`) | Compile the Fortran 2008 engine; locally checked with **13.2.0** |
| GNU Make | Build dependency graph and verification commands |
| Python **3.10+** | Build helpers, test runner, and scenario runner; standard library only for these tasks |
| NumPy + Matplotlib | Optional plots and PDF report, specified in `requirements.txt` |
| GCC, G++, `windres` | Optional Windows HMI and its GDI+ drawing helper |

### Linux

On Debian/Ubuntu, install the core toolchain, then build and verify:

```bash
sudo apt-get update
sudo apt-get install gfortran make python3 python3-venv
make -j4
make check
make scenarios
./thermotwin run cases/design_point.csv
```

The result is `output/results_run.csv`. `make check` runs all Fortran test programs, the physics selftest, Python workflow tests, and CLI input/output regression checks. `make scenarios` runs every bundled `.scn` in a separate process.

### Windows

Use a MinGW-w64 toolchain containing `gfortran` and GNU Make, plus Python 3.10+. Put their executable directories on `PATH`, then run in PowerShell:

```powershell
mingw32-make -j4
mingw32-make check
mingw32-make scenarios
.\thermotwin.exe run cases/design_point.csv
```

If your toolchain exposes GNU Make as `make`, use that spelling. The core commands use native Python helpers and do not need WSL, Bash, `rm`, or `sed`. Keep the compiler runtime DLLs on `PATH` when running a locally built executable.

### First engineering study

The bundled design point uses 100 kg/s air flow, pressure ratio 15, TIT 1400 K, and the constant-property analysis model. With its inlet/exhaust losses, the fresh result is approximately:

| Quantity | Result |
|---|---:|
| Net electrical power | 29.875 MW |
| LHV thermal efficiency | 30.623% |
| Heat rate | 11,755.9 kJ/kWh |
| Exhaust temperature | 797.07 K |

`selftest` uses a **different, lossless inlet/exhaust reference**, giving about 30.41 MW. The live engine uses temperature-dependent properties and gives about 32.29 MW at its full-load reference. These are different model configurations; do not compare their outputs as if they were the same test.

## Capabilities

| Area | Implemented scope | Entry point |
|---|---|---|
| Cycle performance | Compressor, combustor with fuel-mass accounting, turbine, shaft/generator, station states and KPIs | `run`, `design` alias |
| Sensitivity and condition | CSV parameter sweeps; clean, mild, severe and washed degradation presets | `run`, `degradation` |
| Thermal response | Lumped metal temperature, startup/load-ramp/shutdown trajectories, Euler/RK4 library routines | `transient` |
| Uncertainty and diagnostics | Seeded Monte Carlo, sensor bias sensitivity, inverse recovery of synthetic degradation | `uncertainty`, `diagnostics` |
| Off-design operation | Corrected flow, IGV/firing-temperature scheduling, part-load heat rate and surrogate surge margin | Engine, scenarios, HMI |
| Combined cycle | Single-pressure HRSG, pinch/approach limits, steam bottoming and condenser correlation | `combined_cycle.scn`, HMI |
| Grid and fleet | Frequency dynamics, governor/BESS response, AGC, UFLS, renewable curtailment, fleet dispatch and unit commitment | Scenarios, HMI |
| Advanced studies | H2 blend, P2X electrolysis, CCS, GFM battery, tie line, MPC, forecast/advisory and surrogate modules | Engine, scenarios, HMI; experimental |
| Thermodynamic analysis | Exergy, uncertainty/Sobol analysis, thermodynamic limits, data reconciliation, scientific report exports | Fortran modules, HMI |
| Integration | Named simulation tags and optional open62541 OPC UA bridge | Windows HMI; opt-in build |

The core analysis and the live plant engine have separate state contracts: `InputCase` → `CycleResult` for thermodynamic cases, and `GridState` for dispatch, grid dynamics, economics, and HMI state. See the [architecture and assumptions](docs/ENGINEERING_GUIDE.md).

## Command-line reference

In Bash use `./thermotwin`; in PowerShell use `.\thermotwin.exe`.

```text
thermotwin --help
thermotwin run         <input.csv> [output.csv]
thermotwin design      <input.csv> [output.csv]
thermotwin degradation <baseline.csv>
thermotwin transient   <baseline.csv>
thermotwin uncertainty <baseline.csv>
thermotwin diagnostics <baseline.csv>
thermotwin selftest
thermotwin scenario run <file.scn> [--record output.csv]
```

- `run` evaluates **every row**. The four analysis modes use the **first row** as the baseline and generate their own study cases.
- CSV input has an exact 18-column schema. Headers, field counts, finite numeric cells and required labels are checked. Units and examples are in [cases/README.md](cases/README.md).
- `run` defaults to `output/results_run.csv`. Other analysis filenames are listed in the [engineering guide](docs/ENGINEERING_GUIDE.md#analysis-outputs).
- Set `THERMOTWIN_OUTPUT_DIR` to an **existing directory** to redirect default analysis outputs. An explicit output filename or `--record` path takes precedence. Parent directories for direct CLI outputs must already exist.
- Failures return a nonzero exit status, including malformed input, failed physical sanity checks, unknown scenario controls, failed assertions, and unavailable output files. Inspect the CSV `converged` and `status` columns before using results.

A recorded scenario:

```bash
./thermotwin scenario run cases/scenarios/load_step.scn --record output/load_step.csv
```

For all 15 bundled scenarios, including turbine trip, market replay, combined cycle, H2, CCS, P2X and MPC:

```bash
python scripts/run_scenarios.py --record-dir build/scenario-recordings
```

Use `python3` on Linux if `python` is not installed. See the [scenario format](cases/README.md#scripted-scenarios).

## Reproducible analysis and reports

Create a virtual environment and install the optional analysis dependencies:

```bash
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r requirements.txt
make pipeline PYTHON=python
```

On Windows, use `python -m venv .venv`, `.\.venv\Scripts\Activate.ps1`, the same pip command, and `mingw32-make pipeline`.

The pipeline verifies the executable, runs all nine analysis inputs, and writes fresh CSVs, six figures, a nine-page PDF, and **`run_manifest.json`** under `build/analysis/`. The manifest records the Git revision and dirty state, executable/input/output SHA-256 hashes, commands, platform, Python version, property mode, and Monte Carlo seed. A failed run does not retain a success manifest. Missing report inputs fail explicitly.

For a named study or CSV-only run:

```bash
python scripts/run_pipeline.py --output-dir build/studies/baseline
python scripts/run_pipeline.py --output-dir build/studies/csv-only --skip-report
```

The pipeline expects an already-built executable; `make pipeline` builds it first. Existing images and CSVs in `output/` are bundled examples, not evidence of the current checkout's test status. New run output is ignored by Git.

| Bundled example: design point | Bundled example: degradation |
|---|---|
| ![Design-point station temperatures and energy disposition](output/figures/design_point.png) | ![Power, efficiency and heat rate across degradation presets](output/figures/degradation.png) |

## Windows engineering HMI

```powershell
mingw32-make gui
.\thermotwin-gui.exe
```

The HMI has **16 views**, including overview, grid dispatch, turbine, combined cycle, markets, trends, alarms, diagnostics, day-ahead scheduling, fleet dispatch, DNN diagnostics, carbon, forecasting, advisory, scenario comparison and exergy. It includes themes, density settings, CSV exports, and scenario/report tools.

The default GUI build works **offline with OPC UA disabled**. To include the optional server, supply the open62541 source pair and build with `WITH_OPCUA=1`; see [GUI build, controls and integration details](gui/README.md). Interactive behavior and network integration require separate acceptance testing.

## Development and verification

```bash
make PROFILE=debug check scenarios    # bounds checks, backtraces and warnings
make BUILD=build/review check scenarios
make help
```

A custom `BUILD` automatically places the CLI and test programs under that directory. `EXE` can still override the CLI filename; `make check` uses exactly that executable. Release and debug builds use separate directories. For custom compiler/flag combinations, use a fresh `BUILD` directory.

The Bash scripts are thin compatibility wrappers around Make/Python. The `fpm.toml` manifest remains **experimental**: FPM is not covered by the supported build contract, and the GUI-only C bridge needs special handling. Use Make for reproducible builds.

| Path | Contents |
|---|---|
| `app/` | CLI dispatch and analysis workflows |
| `src/` | Thermodynamic components, types, properties and analysis |
| `src/engine/` | Live plant/grid engine and advanced modules |
| `gui/` | Native Win32 Fortran HMI, C++ drawing and optional OPC UA |
| `cases/` | Auditable CSV inputs and scenario fixtures |
| `test/` | Fortran test programs and shared assertions |
| `scripts/` | Portable build/test/analysis helpers |
| `python/` | CSV post-processing, figures and PDF assembly |
| `docs/` | Engineering guide, verification matrix, technical report and historical roadmaps |

Read [CONTRIBUTING.md](CONTRIBUTING.md) for the review checklist, [verification_matrix.md](docs/verification_matrix.md) for oracles and regression boundaries, and [SECURITY.md](SECURITY.md) for reporting vulnerabilities.

## Model scope and evidence

- The analysis CLI defaults to constant properties; `engine_init` selects the temperature-dependent model. The property selector is module-global, so embedded callers must manage that state explicitly.
- Variable gas properties use fixed-composition NASA polynomial correlations. The `if97_*` water/steam routines are compact correlations, **not a full IAPWS-IF97 implementation**.
- Maps, surge margins, grid protection, market profiles, dispatch/AI algorithms and process extensions are simplified engineering models. Scenario success is software regression evidence, not operational qualification.
- `diagnostics` reconstructs a synthetic fault; it is not a live plant-data ingestion command. Reconciliation and exergy are separate module/HMI workflows.
- Seeded stochastic studies replay within the same compiler/runtime. Cross-platform bitwise identity is not guaranteed. Historical `dnn_weights.txt` contains synthetic training output; training reproducibility and plant validation remain open work.
- The [technical report](docs/THERMOTWIN-F_TECHNICAL_REPORT.md) provides equations and assumptions. `REVAMP_*.md` and `COMMIT_REVIEW.md` are historical records and may describe older baselines or planned work; use the current source and verification matrix to establish implemented behavior.

## License and citation

MIT. See [LICENSE](LICENSE) and [CITATION.cff](CITATION.cff). Record the commit and study manifest when citing results; distinguish an internal reference calculation from independent validation data.


<!-- ci-workflow-coverage -->
## Continuous integration

GitHub Actions workflow: [`.github/workflows/ci.yml`](.github/workflows/ci.yml). It supports push, pull-request and manual runs with read-only repository permissions and bounded job times. A passing CI run demonstrates the checks in this workflow; it does not establish independent scientific validation.
