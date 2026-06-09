# ThermoTwin-F — Engineering Report

This narrative report ties the modules together into the story they are designed
to tell: how a performance engineer would **design**, **monitor**, and
**diagnose** a gas turbine across its operating life. All numbers below are
produced by the code in this repository and can be regenerated with
`./scripts/run_pipeline.sh`. A formatted PDF version with all figures is written
to `output/ThermoTwin-F_report.pdf` by `python/report_generator.py`.

> **Scope note.** ThermoTwin-F is a non-proprietary educational simulator built
> on standard textbook thermodynamics with representative property values. It is
> verified against an independent hand calculation but is **not** validated
> against any specific commercial engine and is **not** ASME PTC 22 / ISO 2314
> compliant. Read the results as physically plausible illustrations.

---

## 1. The machine

The reference case is a ~30 MW-class single-shaft simple-cycle gas turbine:

| Parameter | Value |
|---|---|
| Pressure ratio | 15 |
| Turbine-inlet temperature (TIT) | 1400 K |
| Air mass flow | 100 kg/s |
| Compressor isentropic efficiency | 0.86 |
| Turbine isentropic efficiency | 0.89 |
| Combustion efficiency | 0.98 |
| Fuel LHV | 50 MJ/kg |

---

## 2. Act I — Design point and off-design

**Design point (with realistic inlet and exhaust losses):**

| Quantity | Value |
|---|---|
| Net electrical power | 29.9 MW |
| Thermal efficiency | 30.6 % |
| Heat rate | 11 756 kJ/kWh |
| Exhaust temperature | 797 K (≈ 524 °C) |

The compressor absorbs roughly 55 % of the turbine's gross output — the
characteristic high "back-work ratio" of gas turbines, and the reason
compressor and turbine efficiency matter so much.

**Off-design sensitivities** (figure `sensitivity.png`) reproduce the textbook
trends a reviewer would expect:

- **Power falls with ambient temperature.** Hotter inlet air is less dense, so
  for a fixed machine the mass flow and output drop — the well-known summer
  derate of gas turbines.
- **Efficiency rises with pressure ratio, then rolls over.** There is an
  efficiency-optimal pressure ratio for a given TIT; beyond it the rising
  compressor work outweighs the cycle gain.
- **Heat rate improves (drops) as TIT rises.** Higher firing temperature is the
  single biggest lever on efficiency — and the reason hot-section materials and
  cooling dominate engine development.
- **Exhaust temperature falls as turbine efficiency rises**, because a better
  turbine extracts more of the available enthalpy as work.

---

## 3. Act II — Degradation over operating life

Real engines drift from their clean baseline. The degradation module applies
four interpretable mechanisms and re-solves the cycle (figure
`degradation.png`):

| State | Net power [MW] | Efficiency [%] | Heat rate [kJ/kWh] | Exhaust T [K] |
|---|---|---|---|---|
| Clean | 29.9 | 30.6 | 11 756 | 797 |
| Mild | 28.6 | 29.6 | 12 141 | 803 |
| Severe | 26.9 | 28.3 | 12 711 | 810 |
| Washed | 28.2 | 29.0 | 12 400 | 810 |

Two results worth highlighting:

1. **Degraded engines run a hotter exhaust** for less power — exactly the
   monitoring signature operators watch for. Rising exhaust temperature at
   constant load is a classic early indicator of degradation.

2. **Water washing recovers the compressor but not the turbine.** The "washed"
   state restores most of the compressor fouling (efficiency and mass flow) but
   leaves turbine erosion untouched, so it lands *between* mild and severe
   rather than back at clean. This asymmetry falls naturally out of the model
   and mirrors real maintenance experience.

---

## 4. Act III — Measurement, uncertainty, and diagnosis

A performance engineer never sees the "true" cycle — only instrument readings
with noise, bias, and drift. Two analyses close the loop.

**Uncertainty propagation** (figure `uncertainty.png`). Propagating
representative instrument uncertainties (±1 K ambient, ±200 Pa pressure, ±1 %
mass flow, ±8 K TIT) through 5000 Monte Carlo re-solves gives:

| KPI | Mean ± 1σ |
|---|---|
| Net power | 29.9 ± 0.5 MW |
| Thermal efficiency | 0.306 ± 0.001 |

The accompanying tornado chart shows TIT and mass-flow measurement dominate the
power uncertainty — telling you where better instrumentation would pay off.

**Inverse diagnostics** (figure `diagnostics.png`). Given the measured KPIs of a
degraded engine, the solver infers *which* mechanisms degraded by minimising a
weighted least-squares residual. On a synthetic ground-truth case it recovers
all four degradation parameters closely:

| Mechanism | True | Estimated |
|---|---|---|
| Compressor fouling (Δη) | 0.018 | 0.019 |
| Mass-flow loss (Δṁ/ṁ) | 0.010 | 0.010 |
| Turbine erosion (Δη) | 0.012 | 0.012 |
| Combustor ΔP rise | 0.003 | 0.003 |

This is the heart of condition monitoring: turning a handful of plant
measurements into an actionable picture of *where* an engine has degraded, so
maintenance can be targeted rather than guessed.

---

## 5. What the three acts add up to

Design → monitor → diagnose is the real workflow of a gas-turbine performance
engineer, and the modules are built to compose along exactly that arc on a
single shared data model (`InputCase` → `CycleResult`). The transient module
links the cycle's exhaust temperature to hot-section metal response, so a load
schedule feeds directly into thermal behaviour — the modules are coupled, not
independent scripts.

Every figure and number here is reproducible from source, the physics is
verified against an independent hand calculation, and the assumptions are stated
plainly in `assumptions_limitations.md`. That combination — correct,
reproducible, and honest about its boundaries — is the point of the project.
