# ThermoTwin-F

**A Modern Fortran gas-turbine performance simulator — design, degradation,
transient thermal response, measurement uncertainty, and inverse diagnostics.**

ThermoTwin-F models a single-shaft, open/simple Brayton-cycle gas turbine and
follows the real workflow of a performance engineer across an engine's life:

1. **Design** — establish the clean design point and its off-design sensitivities.
2. **Monitor** — quantify how fouling, erosion, and pressure losses degrade performance.
3. **Diagnose** — given noisy plant measurements, infer *where* an engine has degraded.

The whole project is built around a single shared data model — one `InputCase`
(machine + operating point) flows in, one `CycleResult` (every station state and
KPI) flows out — so the advanced modules compose coherently instead of being
independent scripts.

> **Honesty note.** This is a non-proprietary **educational** simulator built on
> standard textbook thermodynamics with representative property values. It is
> **verified** against an independent hand calculation (`thermotwin selftest`)
> but is **not validated** against any specific commercial engine and is **not**
> ASME PTC 22 / ISO 2314 compliant. Treat the numbers as physically plausible
> illustrations, not predictions for a particular machine. See
> [`docs/assumptions_limitations.md`](docs/assumptions_limitations.md).

---

## Quick start

You need a Fortran compiler (`gfortran` ≥ 9) and, for the plots, `python3` with
`numpy` and `matplotlib`.

### Option A — Fortran Package Manager (recommended)

```bash
fpm build
fpm run -- selftest                              # verify the physics
fpm run -- run cases/design_point.csv            # solve the design point
fpm test                                         # full unit-test suite
```

### Option B — no fpm (gfortran + scripts)

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

The repository also includes an early native Windows GUI written in Fortran. It
uses Win32 controls and GDI drawing through `iso_c_binding`, links directly to
the simulator modules, and lets you manipulate demand, renewables, storage, gas
dispatch, ambient temperature, and firing temperature while watching live grid
balance and frequency estimates.

```powershell
make gui
.\thermotwin-gui.exe
```

See [`gui/README.md`](gui/README.md) for scope and next steps.

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

Representative verified design-point results: **≈30 MW**, **≈31 % thermal
efficiency**, **≈11 800 kJ/kWh heat rate**, **≈797 K exhaust** — squarely in the
expected band for a simple-cycle machine.

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

### Source modules (dependency order)

`precision_kinds` → `constants` → `types` → `utilities` → `fluid_properties`
→ `ambient` → `compressor` → `combustor` → `turbine` → `shaft_generator`
→ `cycle_solver` → `degradation` → `transient_thermal` → `sensor_model`
→ `uncertainty_analysis` → `diagnostics_solver` → `csv_io` → `sensitivity_driver`.

---

## Documentation

| Document | Contents |
|---|---|
| [`docs/theory.md`](docs/theory.md) | physical background and the three-act design |
| [`docs/equations.md`](docs/equations.md) | every implemented equation, with units |
| [`docs/verification.md`](docs/verification.md) | the worked hand calculation the selftest reproduces |
| [`docs/validation_and_uncertainty.md`](docs/validation_and_uncertainty.md) | diagnostics objective, weighting, and why this is verification not validation |
| [`docs/assumptions_limitations.md`](docs/assumptions_limitations.md) | every modelling assumption and its consequence |
| [`docs/engineering_report.md`](docs/engineering_report.md) | the narrative report tying the modules together |
| [`cases/README.md`](cases/README.md) | input CSV column format |

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

## Roadmap

Natural extensions, each building on a stated limitation: real-gas properties by
default · compressor/turbine performance maps · turbine cooling-air bookkeeping ·
a first NOx correlation · a multi-node transient thermal model with stress
output · a Bayesian/Kalman diagnostics formulation · combined-cycle bottoming.

---

## License

MIT — see [`LICENSE`](LICENSE).
