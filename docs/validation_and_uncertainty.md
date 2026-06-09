# Validation, Uncertainty and Diagnostics

This document is deliberately candid about what ThermoTwin-F does and does not
establish, and it makes the uncertainty and diagnostics choices explicit rather
than burying them in code.

## 1. Verification vs validation

- **Verification** (done — see `verification.md`): the code correctly solves its
  governing equations, confirmed against an independent hand calculation and a
  unit-test suite.
- **Validation** (NOT done, NOT claimed): the governing equations have *not*
  been compared against measured data from any specific physical engine.

ThermoTwin-F is therefore a **verified but unvalidated** model. It is suitable
for teaching, methodology demonstration, trade studies, and portfolio work. It
is **not** suitable for guaranteeing the performance of real hardware, and it is
**not** compliant with:

- **ASME PTC 22** (Gas Turbines performance test code), or
- **ISO 2314** (Gas turbines — acceptance tests).

Those codes prescribe instrumentation, correction curves, and uncertainty
budgets far beyond a zero-dimensional cycle deck. Where this project borrows
their *spirit* (e.g. uncertainty propagation), it says so without claiming
their authority.

## 2. Uncertainty analysis

Two complementary methods are implemented (`uncertainty_analysis.f90`).

### 2.1 Monte Carlo propagation

The dominant boundary conditions are treated as uncertain, each with a 1-σ
instrument uncertainty:

| Boundary input | 1-σ (default) | Rationale |
|----------------|--------------:|-----------|
| Ambient temperature | 1.0 K | RTD/thermocouple class |
| Ambient pressure | 200 Pa | barometric transducer |
| Air mass flow | 1.0% (fractional) | inlet flow measurement is hard |
| Turbine-inlet temperature | 8.0 K | TIT is inferred, not directly measured |

The cycle is re-solved `N = 5000` times with independent Gaussian draws; the
reported KPI distributions (mean, σ, 95% interval) capture how measurement
scatter propagates to net power, efficiency and heat rate. The RNG is seeded
deterministically (`seed = 20240601`) so a given study is exactly reproducible.

> These σ values are **illustrative defaults**, not a metrology statement for any
> particular site. They are trivially editable in `app/main.f90`.

### 2.2 Deterministic bias sensitivity

Random noise averages out; *systematic* bias does not. For each channel the tool
applies a `±bias` and records the symmetric finite-difference effect on each
KPI. The result is a tornado-style ranking of which measurement most strongly
biases the answer. In the default case, ambient temperature and TIT dominate the
power sensitivity — which is exactly why field test codes obsess over those two
measurements.

## 3. Inverse diagnostics

### 3.1 The problem

*Forward* problem: given the machine state, predict the performance.
*Inverse* problem: given measured performance, infer the (hidden) machine state
— specifically, how much each degradation mechanism has advanced.

### 3.2 The objective function (made explicit)

The estimate minimises a weighted sum of squared **fractional** residuals
between modelled and measured quantities:

```
J(d) = w_P  * ((P_model  - P_meas ) / P_meas )^2
     + w_T4 * ((T4_model - T4_meas) / T4_meas)^2
     + w_mf * ((mf_model - mf_meas) / mf_meas)^2
     + w_T2 * ((T2_model - T2_meas) / T2_meas)^2
```

Fractional residuals make the terms dimensionless, so a 1% error in power and a
1% error in temperature contribute comparably regardless of their absolute
magnitudes.

### 3.3 The weights (and why)

The default weights (`default_weights()`):

| Term | Weight | Reasoning |
|------|-------:|-----------|
| net power `w_P` | 1.0 | the headline quantity; usually well measured |
| exhaust temperature `w_T4` | 1.0 | sensitive to turbine health; well measured |
| fuel flow `w_mf` | 1.0 | strong constraint on energy input |
| compressor-out temp `w_T2` | 0.5 | informative but typically noisier, so down-weighted |

These are **modelling choices**, not physical constants. Re-weighting changes
which mechanism the fit favours when the data are ambiguous, and that is a
legitimate subject for study with this tool.

### 3.4 The optimiser

A coarse 4-D grid search (robust, derivative-free, immune to local minima at the
grid scale) locates the basin, then coordinate descent with geometric step
reduction refines the estimate. This is intentionally simple and transparent; a
gradient or Levenberg–Marquardt method would be faster but less legible.

### 3.5 Demonstrated performance

With noise-free synthetic observations from a known "truth" degradation, the
solver recovers each parameter to within a few thousandths (see
`output/results_diagnostics.csv` and the parity plot in the report):

| Parameter | True | Estimated |
|-----------|-----:|----------:|
| compressor fouling `Δη_c` | 0.018 | ~0.019 |
| mass-flow loss `Δṁ/ṁ` | 0.010 | ~0.0095 |
| turbine erosion `Δη_t` | 0.012 | ~0.0117 |
| combustor `ΔP` rise | 0.003 | ~0.0033 |

### 3.6 Identifiability caveat

Compressor fouling and inlet mass-flow loss have **partially overlapping
signatures** on the observable KPIs, so they trade off slightly in the fit (note
the compressor term is recovered a touch high while the mass-flow term comes in
a touch low). This is a real, well-known feature of gas-turbine diagnostics, not
a bug: with a limited measurement set, some mechanisms are only *jointly*
identifiable. Adding measurements (e.g. inter-stage pressures) or priors would
sharpen the separation — another natural extension.

## 4. Summary

ThermoTwin-F demonstrates a complete, honest performance-engineering workflow:
a verified forward model, transparent uncertainty propagation, and an inverse
diagnostic with an explicit, defensible objective. It stops short of — and never
claims — validation against real hardware or compliance with industry test
codes.
