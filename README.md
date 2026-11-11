# ThermoTwin-F

[![CI](https://github.com/abhijith-sivaprasadan/thermotwin/actions/workflows/ci.yml/badge.svg)](https://github.com/abhijith-sivaprasadan/thermotwin/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Fortran 2008](https://img.shields.io/badge/Fortran-2008-blueviolet.svg)](https://fortran-lang.org)
[![Latest release](https://img.shields.io/github/v/release/abhijith-sivaprasadan/thermotwin?include_prereleases&label=GitHub%20release)](https://github.com/abhijith-sivaprasadan/thermotwin/releases)
[![Zenodo DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.23679426.svg)](https://doi.org/10.5281/zenodo.23679426)

> **Archived and citable:** [ThermoTwin-F v2.0.0-beta.1 on Zenodo](https://doi.org/10.5281/zenodo.23679426) — **DOI: 10.5281/zenodo.23679426**. This is the archived source-only research beta, not validated industrial software. See [`CITATION.cff`](CITATION.cff) and the [release notes](docs/RELEASE_NOTES_v2.0.0-beta.1.md).

**A Modern Fortran gas-turbine and combined-cycle performance simulator —
design, degradation, transient thermal response, measurement uncertainty,
inverse diagnostics, data reconciliation, and OPC UA integration.**

ThermoTwin-F models a single-shaft, open/simple Brayton-cycle gas turbine —
with an optional combined-cycle extension (HRSG + steam bottoming) — and
follows the real workflow of a performance engineer across an engine's life:

1. **Design** — establish the clean design point and its off-design sensitivities.
2. **Monitor** — quantify how fouling, erosion, and pressure losses degrade performance.
3. **Diagnose** — given noisy plant measurements, infer *where* an engine has degraded.

The whole project is built around a single shared data model — one `InputCase`
(machine + operating point) flows in, one `CycleResult` (every station state and
KPI) flows out — so the advanced modules compose coherently instead of being
independent scripts.

## Current main-branch research acceptance (11 November 2026)

The [independent evidence and acceptance audit](docs/ENGINEERING_ACCEPTANCE_2026-11-11.md) and [machine-readable capability inventory](docs/capability_evidence.json) distinguish implemented numerical models, external reanalysis, actual unrelated-turbine observations, mathematical pass-off methods, unsupported features, and **absent industrial validation**. The [untagged source-release candidate checklist](docs/RESEARCH_RELEASE_CANDIDATE_2026-11-11.md) explicitly does NOT publish a new version or DOI. CI generates a source-commit-pinned claim audit artifact; it does not perform measured-engine certification or GUI user acceptance.

## Practical measured-turbine prediction use case (v0.1)

The [UCI #551 measured-turbine replay](docs/MEASURED_TURBINE_REPLAY_V01.md)
trains a transparent condition-adjusted regression on actual 2011–2013
measurements from one turbine, and generates **2014–2015 held-out
measured-versus-predicted TEY** records and a self-contained interactive
offline viewer. The prediction is conditional on same-record **measured**
ambient/filter/TIT/TAT quantities; it is **not** a next-hour power forecast,
real fault classifier, physical OEM turbine calibration, or simulated trip
reconstruction. The UCI TEY unit/aggregation interpretation remains uncertain.

Run: `python scripts/fetch_uci_gt551.py --output-dir build/uci551` then
`python -m scripts.replay_uci_gt551 --data-dir build/uci551 --out build/uci551/replay`.
Open `build/uci551/replay/measured_turbine_replay.html`.

## Real measured microturbine dynamic prediction (3 kW, original time in seconds)

The [UCI #994 measured dynamic forecast](docs/UCI994_MEASURED_DYNAMIC_FORECAST.md)
uses actual ~1-second voltage-command and electrical-power observations
(71,225 samples, eight experiments) from a **3 kW commercial micro gas
turbine**, with experiments 1/9/20/21/23/24 for identification and 4/22
reserved untouched. It predicts **future output under a supplied command
trajectory** with an explicit bounded first-order response and independent
static baseline. This is **not** the generic 30 MW physical Brayton model, an
industrial turbine forecast or fault diagnosis. The first measured sample is
an explicitly declared starting state, never a scored prediction.

Reproduce with `python scripts/fetch_uci994_microgt.py --output-dir build/uci994`
then `python -m scripts.forecast_uci994_microgt --data-dir build/uci994 --out build/uci994/forecast`.

## Performance-engineering research workflows (November 2026)

The [live, same-run source-backed engineering dossier](docs/REPRODUCIBLE_ENGINEERING_DOSSIER.md), [Lincoln master plan](docs/TTF_PE_MASTER_PLAN_v1.0.md), [evidence-maturity audit](docs/ENGINEERING_EVIDENCE_AUDIT_2026-11-10.md), and [role-specific evidence brief](docs/LINCOLN_304533_APPLICATION_EVIDENCE.md) distinguish **equation-based models**, external weather-model inputs, **real turbine measurements**, and mathematical regression fixtures. These data types are not interchangeable. The frozen v2 beta/DOI remains unchanged; features below are later `main` development.

- **Variable hot-gas property consistency (equation-based correction):** the reduced-order fixed-species molar mixture now derives both specific heat/enthalpy and variable-property gas constant from its declared molecular mass; [derivation and remaining model limitations](docs/GAS_MIXTURE_MASS_CONSISTENCY.md). It is not measured turbine combustion chemistry or OEM calibration.
- **Site-performance prediction (implemented, educational):** a fixed-hardware full-load Fortran off-design calculation with a corrected ISO compressor-inlet/exhaust-flange reference, power/heat-rate/exhaust correction factors, documented assumptions and invalid-input rejection. See [site methodology](docs/SITE_PERFORMANCE_v0.1.md) and [ISO flange fix #27](https://github.com/abhijith-sivaprasadan/thermotwin/pull/27).
- **Source-backed seasonal ERA5 site sensitivity (research expansion):** four predeclared seven-day windows in 2025 (672 original reanalysis-model hours) drive 2,688 equation-based Fortran site cases across four explicitly assumed pressure-loss boundaries. [Reproducibility protocol, sources and limitations](docs/ERA5_SEASONAL_SITE_STUDY.md). These are not measured Siemens turbine output or a calibrated model uncertainty interval.
- **Actual atmospheric inputs (implemented):** live Open-Meteo forecast / historical ERA5 ingestion records original response, model, UTC time, coordinates, unit conversions and SHA-256. Real weather-model *reanalysis* is not measured turbine telemetry; humidity effects remain unsupported. See [weather evidence](docs/REAL_WEATHER_BOUNDARY.md).
- **Independent external measured turbine consistency study (implemented, NOT physically calibrated):** [SMART-GTPP source-verified original 7,893 measured electrical-power records](docs/INDEPENDENT_MEASURED_TURBINE_EVIDENCE.md) were evaluated against a pressure-ratio source-unit hypothesis and 7,893 actual Fortran computations of the *unrelated generic* ISO reference using measured ambient conditions. This explores observational/physics consistency, but source pressure units, timestamps, fuel mass flow/LHV and OEM component maps are missing; quantitative engine power/heat-rate predictive validation is **NOT ESTABLISHED**. An explicit measured-data readiness gate fails closed on those gaps.
- **Real turbine operating-data analysis (implemented):** UCI #551 original CC BY 4.0 dataset, **36,733 measured records from one turbine**, physically interpretable covariates, 2011–2013 fitting and untouched 2014–2015 evaluation. Added leakage-free forward-year checks, train-only feature-support flags and within-year autocorrelation-aware block-resampling sensitivity. The [original-data CI run](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42798697940) reports held-out source-labelled TEY RMSE 4.4771 versus 14.9756 for a training-mean baseline, with train residual lag-1 of 0.9151 after correcting artificial year adjacency. This is an empirical regression, **not an OEM engine model validation, confirmed fault study, or production-engine fleet**. See [UCI equations and results](docs/UCI551_REAL_OPERATIONS.md).
- **Pass-off correction mathematics (implemented method, not an industrial pass-off):** measured fuel-flow/LHV/power heat-rate equations and full precision/calibration covariance propagation with analytical Jacobian, checked against central differences and seeded **mathematical-only** Monte Carlo. Actual traceable test data, OEM calibration, correction-factor model uncertainty and guarantee terms are not provided; the method cannot issue an industrial acceptance verdict. See [measurement-method specification](docs/PASSOFF_CORRECTION_METHOD.md).

To reproduce the controlled **numerical verification** cases for the ISO-flange reference (not empirical engine measurements):

```bash
make all tests
python scripts/generate_site_cases.py --output cases/site_sweep.csv
./thermotwin site cases/site_iso_flange_reference.csv cases/site_sweep.csv output/results_site.csv
python scripts/test_site_pipeline.py --executable ./thermotwin
```

For external-data commands and exact output provenance use the linked guides. **None of the models is OEM-certified, ISO 2314 / ASME PTC 22 compliant, or validated for Siemens Energy SGT guarantees.**

## Software release and citation

ThermoTwin-F is **open research software** (MIT licensed). The published `v2.0.0-beta.1`
edition is an **educational source-code prerelease**, not a qualified
industrial performance predictor. The native Windows GUI is **experimental**:
its compilation is covered by CI, but end-to-end interaction, OPC UA operation
and binary redistribution are not yet accepted. No new GUI executable is
included in the source-only prerelease.

**Published source beta:** [ThermoTwin-F v2.0.0-beta.1](https://github.com/abhijith-sivaprasadan/thermotwin/releases/tag/v2.0.0-beta.1)
(27 October 2026; frozen release commit
[`ee0461684dbad75c5ab28fe9a66a5f6b32317887`](https://github.com/abhijith-sivaprasadan/thermotwin/commit/ee0461684dbad75c5ab28fe9a66a5f6b32317887)).
This is a **source-only prerelease** and does not include a Windows binary.
[Release CI](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40424474706)
passed all 10 jobs; the publishing workflow also
[succeeded](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40424777919).

**Zenodo archival:** The
[v2.0.0-beta.1 archive](https://zenodo.org/records/23679426) is published
as [DOI 10.5281/zenodo.23679426](https://doi.org/10.5281/zenodo.23679426),
with MIT licensing and a 1.8 MB source ZIP.
The [v1.0.0 DOI 10.5281/zenodo.23679257](https://doi.org/10.5281/zenodo.23679257)
continues to identify the earlier version.
Use the [concept DOI 10.5281/zenodo.23679256](https://doi.org/10.5281/zenodo.23679256)
when referencing the evolving software across versions.

**Creator:** Abhijith Sivaprasadan ·
[ORCID 0009-0009-8429-1266](https://orcid.org/0009-0009-8429-1266)

**Metadata correction (2 November 2026):** The creator's correct ORCID is listed above and in the current `CITATION.cff`. The previously published source tag and Zenodo ZIP are retained unchanged for provenance. Published Zenodo creator metadata and the GitHub release description must be checked and corrected separately where necessary.

**How to cite this beta:** Cite the **version-specific DOI**, not the concept DOI:

> Sivaprasadan, A. (2026). *ThermoTwin-F: An Educational Gas-Turbine and
> Combined-Cycle Simulation Framework* (Version v2.0.0-beta.1)
> [Computer software]. Zenodo. https://doi.org/10.5281/zenodo.23679426

The version DOI identifies the published source snapshot, whereas the concept
DOI identifies the software family and resolves to the latest Zenodo version.
The archived release corresponds to GitHub tag
[`v2.0.0-beta.1`](https://github.com/abhijith-sivaprasadan/thermotwin/releases/tag/v2.0.0-beta.1)
(commit `ee0461684dbad75c5ab28fe9a66a5f6b32317887`). Subsequent README
and citation changes on `main` do **not** alter the archived release.
The DOI records a software version; it does not imply peer review,
measured-plant validation, or certification.

**Version evidence:** [release verification run](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40424474706)
(10/10 CI jobs passed on exact prerelease commit `ee0461684dbad75c5ab28fe9a66a5f6b32317887`),
[release acceptance gates](docs/RELEASE_GATE.md),
[independent reference comparisons](docs/INDEPENDENT_BENCHMARKS.md),
and [release notes](docs/RELEASE_NOTES_v2.0.0-beta.1.md).
The checks above correspond to the **exact tagged source commit**. Scientific verification is not measured-plant validation.

## Results at a glance

*Illustrative figures from tracked example outputs, not experimentally validated
plant measurements or independently audited release-version results.*

<table>
<tr>
<td align="center"><b>Design-point cycle</b><br><img src="output/figures/design_point.png" alt="Design-point summary — station temperatures and fuel energy disposition" width="480"></td>
<td align="center"><b>Degradation impact</b><br><img src="output/figures/degradation.png" alt="Clean / mild / severe / washed KPI comparison" width="480"></td>
</tr>
<tr>
<td align="center"><b>Inverse diagnostics</b><br><img src="output/figures/diagnostics.png" alt="Recovered vs true degradation parameters" width="480"></td>
<td align="center"><b>Measurement uncertainty</b><br><img src="output/figures/uncertainty.png" alt="Monte Carlo KPI uncertainty and bias-sensitivity tornado" width="480"></td>
</tr>
</table>

---

> **Honesty note.** This is a non-proprietary **educational** simulator built on
> standard textbook thermodynamics with representative property values. It is
> **verified** against an independent hand calculation (`thermotwin selftest`)
> but is **not validated** against any specific commercial engine and is **not**
> ASME PTC 22 / ISO 2314 compliant. Treat the numbers as physically plausible
> illustrations, not predictions for a particular machine. See
> [the consolidated technical report](docs/THERMOTWIN-F_TECHNICAL_REPORT.md).

---

## Quick start

You need a Fortran compiler (`gfortran` ≥ 9) and, for the plots, `python3` with
`numpy` and `matplotlib`.

### Reference path — gfortran + Make

```bash
make
make check
```

See the [verification matrix](docs/verification_matrix.md) for numerical oracles,
tolerances and the stable/experimental boundary.

### Experimental alternative — Fortran Package Manager (unverified)

FPM is not a supported primary path until the expanded engine passes build/test
parity. The retained manifest and commands below are development candidates only.

```bash
fpm build
fpm test
```

The primary supported build/test path is still `make` and `make check`.
The compatibility build wrapper now delegates to the Makefile, and the
`run_pipeline.sh` report-regeneration path has passed a CI smoke test.
This establishes that the pipeline executes, **not** that every plotted value
has been independently benchmarked.

```bash
./scripts/build.sh            # build ./thermotwin
./scripts/run_tests.sh        # build + run all unit tests + selftest
./scripts/run_pipeline.sh     # build, run every mode, make figures + PDF report
```

A `Makefile` is also provided (`make`, `make check`, `make run`, `make debug`).

### See everything at once

```bash
./scripts/run_pipeline.sh
```

This produces all result CSVs in `output/`, six figures in `output/figures/`,
and a multi-page report at `output/ThermoTwin-F_report.pdf`.

### Optional Windows grid-balancing GUI

The repository also includes an optional native Windows GUI written in Fortran. It
uses a custom-drawn Win32/GDI dashboard through `iso_c_binding`, links directly
to the simulator modules, and lets you manipulate demand, renewables, storage,
gas dispatch, ambient temperature, and firing temperature while watching live
grid balance, battery state of charge, frequency estimates, reserves, and
rolling time-series traces. The dashboard also includes basic operating
economics and battery ROI estimates, uses buffered GDI rendering to keep timer
updates smooth, and embeds a generated Windows icon for the executable.

```powershell
make download-opcua   # pinned open62541; requires network access
make gui
.\thermotwin-gui.exe
```

**Current draft development only:** F15 now has a separate Instructor tab (I toggles it), allowing declared training sensor injections, bounded disturbances, an in-memory freeze/snapshot/restore workflow, and a simple F7 operator-action exercise rubric. The original F15 A/B scenarios, F3 compressor map/Brayton T-s diagram, and F7 alarm/protection screens remain. The PFD and maps now use model-derived component states and cursor/tracer cues. These features are in [unmerged draft PR #54](https://github.com/abhijith-sivaprasadan/thermotwin/pull/54), not the frozen source beta. See the [instructor and engineering-visual acceptance plan](docs/INSTRUCTOR_AND_ENGINEERING_VISUALS_2026-11-11.md) for explicit model/measurement provenance and outstanding checks.

See [`gui/README.md`](gui/README.md) for scope and
[the GUI acceptance protocol](docs/GUI_ACCEPTANCE.md). The GitHub Actions
Windows job only **compiles** the GUI; the source-code prerelease must not
be advertised as a qualified binary distribution.

---

## Command-line modes

```
thermotwin run         <input.csv> [output.csv]   solve every row of a case file
thermotwin degradation <baseline.csv>             clean/mild/severe/washed comparison
thermotwin transient   <baseline.csv>             startup/load-ramp/shutdown metal heating
thermotwin uncertainty <baseline.csv>             Monte Carlo + bias-sensitivity study
thermotwin diagnostics <baseline.csv>             recover a known degradation by inversion
thermotwin selftest                               verify against the hand calculation
```

`run` evaluates every operating point in the file (a single design point and a
30-row parameter sweep are handled identically). The scenario modes take the
first row of their file as the baseline machine.

---

## What it computes

- **Cycle solver** — full station-by-station solution (compressor, combustor,
  turbine, shaft/generator) with a rigorous fuel-mass-conserving combustor
  energy balance; outputs power, thermal efficiency, heat rate, exhaust
  temperature and energy, specific power, and a converged/sanity flag.
- **Degradation** — four interpretable knobs (compressor fouling, mass-flow
  loss, turbine erosion, combustor ΔP rise) applied to the clean case and
  re-solved, so all KPI changes are emergent.
- **Transient thermal** — lumped-capacitance metal node driven by the cycle's
  exhaust temperature, integrated with Euler and RK4.
- **Sensor + uncertainty** — bias/noise/drift measurement model, Monte Carlo
  KPI uncertainty, and a deterministic bias-sensitivity tornado.
- **Inverse diagnostics** — weighted least-squares estimation of the degradation
  state from observed KPIs (grid search + coordinate-descent refinement).
- **Combined-cycle bottoming** — single-pressure HRSG (pinch/approach-limited
  0-D heat balance) driving a steam bottoming cycle with a condenser
  back-pressure correlation against ambient temperature.
- **Data reconciliation** — single-constraint weighted least-squares
  reconciliation of redundant noisy measurements, with a chi-square(1) global
  test for gross-error detection.
- **OPC UA integration** — an `iso_c_binding` bridge to `open62541` that writes
  named tag values with engineering units to an OPC UA address space; this is
  an optional GUI-side integration, not covered by core CI (see the
  [verification matrix](docs/verification_matrix.md)).

Historical example simple-cycle design-point outputs include **≈30 MW** and
**≈31% thermal efficiency**. These numbers are illustrative model outputs,
**not** a measured industrial baseline or revalidated performance guarantee.

---

## Repository layout

```
thermotwin-f/
├── app/main.f90              CLI driver (all modes)
├── src/                      simulation modules (see below)
├── test/                     unit tests (one program per module) + shared asserts
├── cases/                    CSV inputs + format documentation
├── python/                   matplotlib post-processing + PDF report generator
├── docs/                     theory, equations, verification, limitations, report
├── scripts/                  build.sh, run_tests.sh, run_pipeline.sh
├── output/                   generated CSVs, figures, and the PDF report
├── fpm.toml                  Fortran Package Manager build
├── Makefile                  gfortran build (fpm-free)
└── LICENSE                   MIT
```

### Source modules

The original thermodynamic core includes `fluid_properties`, `compressor`,
`combustor`, `turbine`, `cycle_solver`, `hrsg`, `steam_cycle`,
`degradation`, and `diagnostics_solver`. Newer modules also cover exergy,
reconciliation, sensitivity and Monte Carlo analysis, transient behaviour,
grid/fleet scenarios and demonstrator machine-learning models. Consult the
**current** `Makefile` source inventory rather than an old partial module
list when extending the dependency graph.

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/THERMOTWIN-F_TECHNICAL_REPORT.md`](docs/THERMOTWIN-F_TECHNICAL_REPORT.md) | consolidated equations, assumptions, analysis and verification discussion |
| [`docs/REVAMP_7.0.md`](docs/REVAMP_7.0.md) | implementation history; roadmap aspirations are not independent validation |
| [`docs/COMMIT_REVIEW.md`](docs/COMMIT_REVIEW.md) | current checks and remaining verification boundaries |
| [`docs/ENGINEERING_EVIDENCE_AUDIT_2026-11-10.md`](docs/ENGINEERING_EVIDENCE_AUDIT_2026-11-10.md) | implementation/verification/real-source/field-evidence maturity matrix and open validation gaps |
| [`cases/README.md`](cases/README.md) | input CSV column format |
| [`docs/INDEPENDENT_BENCHMARKS.md`](docs/INDEPENDENT_BENCHMARKS.md) | external CoolProp IF97 accuracy comparison and standalone TESPy Rankine reference |
| [`docs/RELEASE_EVIDENCE_2026-10-26.md`](docs/RELEASE_EVIDENCE_2026-10-26.md) | commit-scoped CI and numerical benchmark evidence |
| [`docs/RELEASE_GATE.md`](docs/RELEASE_GATE.md) | source prerelease criteria and Zenodo steps |
| [`docs/GUI_ACCEPTANCE.md`](docs/GUI_ACCEPTANCE.md) | Windows GUI/OPC UA manual acceptance cases |
| [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md) | optional reference packages and OPC UA licensing obligations |

---

## Design choices worth noting

- **Modern Fortran (2008):** free-form, `implicit none` everywhere, modules and
  derived types, descriptive unit-suffixed variable names, doc comments.
- **One data model:** `InputCase` and `CycleResult` are the contract every
  module speaks, which is what lets degradation/sensors/uncertainty/diagnostics
  interoperate.
- **Switchable fluid properties:** constant `cp`/`γ` by default (so the hand
  calculation is exactly reproducible), with a temperature-dependent option
  behind the same interface.
- **Reproducibility:** the RNG is explicitly seeded, so Monte Carlo studies
  repeat exactly.
- **Tested physics, not just syntax:** unit tests check energy balance,
  monotonic degradation, transient steady-state limits against an analytic
  oracle, and recovery of a known degradation by the inverse solver.

---

## Scientific scope and independent benchmarking

The variable-property mode uses NASA seven-coefficient gas heat-capacity terms
and **approximate** water/steam correlations (the legacy `if97_*` function names
are not a claim of IAPWS-IF97 compliance). These are useful engineering teaching
models, not a substitute for a certified property package. See
[the scientific accuracy and benchmarking protocol](docs/INDEPENDENT_BENCHMARKS.md)
and [the release gates](docs/RELEASE_GATE.md). An optional external comparison
uses CoolProp's actual IF97 backend without copying its source code.
At nine benchmark pressures the approximate saturation temperature had a
**0.53 K mean absolute error**, while saturated-vapour enthalpy showed a
**104 kJ/kg mean absolute error** and superheated enthalpy a **216 kJ/kg mean
absolute error** (the latter includes differences in state definitions).
See the complete [benchmark report](docs/INDEPENDENT_BENCHMARKS.md).
A completed benchmark is not evidence of full IAPWS-IF97 conformity.

The advanced grid, ML, emissions and dispatch demonstrations use representative
and/or synthetic inputs; passing scenario tests is not experimental validation.
The historical technical monograph must not be represented as independently
validated results from the DOI release. The PDF-report generation pipeline
has passed a functional smoke test, but that does not constitute a full
numerical reproduction and uncertainty audit.

## Roadmap

Prioritize independent thermophysical and whole-cycle benchmarks, numerical
sensitivity and conservation audits, verified GUI/OPC UA acceptance, and
reproducible scientific reports before further expanding the model.

---

## License

Optional neural-surrogate weights are loaded from `dnn_weights.txt`. Regenerate them
with `python train_dnn.py` (NumPy required). Training targets are synthetic model
outputs, not measured plant observations; surrogate agreement is not external validation.

MIT — see [`LICENSE`](LICENSE).

## Parallel execution and CI

Optional OpenMP batch operating-point evaluation with serial equivalence checks and measured workstation scaling. See [docs/openmp_scaling.md](docs/openmp_scaling.md).

CI runs on Ubuntu, Windows and macOS. ThermoTwin-F uses release/debug profiles and serial/OpenMP builds. Weekly runs check dependency drift. Hosted run status is available in the repository’s Actions tab; documented local measurements are separate from hosted verification.
