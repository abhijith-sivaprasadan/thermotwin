# ThermoTwin-F — Lincoln Performance Engineering work package

**Document ID:** TTF-PE-PMP-001  |  **Version:** 1.0 (proposed)
**Date:** 2026-11-10  |  **Role trace:** Siemens Energy Performance Engineer, Lincoln, Req. 304533 (posted 2026-11-09)
**Owner:** Abhijith Sivaprasadan  |  **Status:** Plan / not a claim of completed validation

## 0. Decision and rationale

Extend the existing `thermotwin` repository; do not create a last-minute separate portfolio repository. Reuse the Fortran 2008 cycle and off-design implementation, shared `InputCase` / `CycleResult`, tests, CI, reproducible CSV inputs, MIT license, and immutable v2 DOI baseline. Avoid expanding grid-control, GUI or unrelated research features until the performance-engineering workflow passes verification.

The completed frozen release `v2.0.0-beta.1` (commit `ee0461684dbad75c5ab28fe9a66a5f6b32317887`, Zenodo DOI `10.5281/zenodo.23679426`) must not be rewritten. New work lives on `main` via reviewed PRs and is not retroactively included in the archive.

**Deliverables, in order:**
1. P0: eliminate incorrect numerical claims, audit model validity, source-data paths, build/test reliability and assumptions.
2. P1: model-based reference-to-site GT correction and controlled site-sensitivity surfaces.
3. P1: pass-off measurement QC, reference-condition correction, uncertainty, and synthetic guarantee reporting.
4. P1: synthetic production-population trends, outliers and root-cause screening.
5. P1: concise recruiter-facing engineering case-study report and reproducibility pack.

## 1. Posting-to-code traceability

| Lincoln posting activity | Baseline asset | Deficit | Planned verification | Issue |
|---|---|---|---|---|
| Predict installed site power, heat rate, exhaust flow | `off_design`, `cycle_solver`, `ambient` | No explicit fixed-reference correction interface; humidity is inert | Reference identity, controlled one-factor sweeps, boundary tests, model-relative factors | [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13) |
| Assess production pass-off/development/site tests | `sensor_model`, `uncertainty_analysis` | No raw-test QC, model correction/guarantee decision | Unit tests, bad-channel rejection, uncertainty budget and synthetic test report | [#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14) |
| Thermodynamic calculations/models & R&D testing | `InputCase`, `CycleResult`, existing numerical tests | Unverified applicability and simplified steam/fuel models | Explicit limitations, numerical reference checks and traceability | [#12](https://github.com/abhijith-sivaprasadan/thermotwin/issues/12) |
| Large datasets / statistical investigations | `anomaly_detector`, `fleet_dispatch` | Grid-dispatch fleet ≠ production-engine population | Synthetic 100+ engines, stability controls, drift/outlier metrics | [#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15) |
| Develop and automate tools | Make, CLI, scripts, CI on three OSs | No end-to-end correction pipeline | Single-command examples, fixture schemas, gates in CI | [#16](https://github.com/abhijith-sivaprasadan/thermotwin/issues/16) |
| Communicate to Sales/Manufacturing/R&D | Existing report generator and README | No bid-style site sheet, pass-off memo or diagnostic summary | Reproducible memo and plots with assumptions and decision uncertainty | [#16](https://github.com/abhijith-sivaprasadan/thermotwin/issues/16) |

## 2. Scientific, standard and evidence boundary

**Reference context.** ISO 3977-2:2023 specifies reference conditions and ratings for gas turbines: at the compressor intake flange, total temperature 15 °C (288.15 K), total pressure 101.325 kPa and relative humidity 60%; the exhaust reference is defined at the turbine exhaust flange. ASME PTC 22-2023 concerns reporting and correcting gas-turbine thermal performance and its uncertainty, including power, heat rate and exhaust measures. ISO 2314:2009 concerns gas-turbine acceptance tests (a revision may be in development). These are **conceptual anchors** only; do not claim compliance or quote protected correction procedures as implemented.

References:
- https://www.sis.se/en/produkter/energy-and-heat-transfer-engineering/gas-and-steam-turbines-steam-engines/iso-3977-22023/
- https://www.asme.org/codes-standards/find-codes-standards/gas-turbines
- https://www.iso.org/standard/25523.html

**Core limitations in current source:**
- `InputCase.relative_humidity` is recorded but `src/ambient.f90` does not change thermophysical properties for it. Humidity correction is **not implemented**. Do not provide a numerical humidity sensitivity of zero while implying physical correctness.
- `InputCase.LHV_J_kg` changes fuel heating value, but no realistic gas-composition / Wobbe / emissions correction is established in the simple-cycle performance model. LHV what-if sensitivity is not gas-mixture acceptance analysis.
- `src/off_design.f90` currently calibrates its choked-turbine constant against ISO temperature/pressure by copying an input containing its own loss assumptions. A single hardware/reference definition must be frozen to prevent re-calibration when site losses change. Distinguish ambient static conditions from flange conditions.
- The burner, compressor and turbine component maps are representative textbook-level models, not Siemens Energy SGT product maps. There is no licensed OEM performance deck, confidential production data or independent field-test validation. Quantities are educational illustrations only.
- Historical `if97_*` steam helper functions are approximate, with documented enthalpy discrepancies against CoolProp; avoid using steam-cycle figures as gas-turbine pass-off evidence.
- Existing models are permitted to fail a validity check; no export should silently treat `converged = false`, nonfinite or out-of-bounds as acceptable results.

**Evidence order:** source code and specified physical inputs → numerical tests → independently reproduced run artifacts → plots/report with source SHA → external model comparisons → measured-engine validation (future, unavailable). Successful compilation and passing software tests never imply OEM guarantee-grade accuracy.

## 3. P0 repository audit and cleanup (issue #12)

### Required inventory
Create an authoritative feature-maturity table with `implemented/verified/externally compared/field validated` columns; inspect source vs README/older Revamp roadmaps; distinguish experimental GUI compilation from interactive acceptance. Audit all Markdown links and missing doc names, stale output screenshots, generator options, example case fields, failed-code paths and untested station-state flags. Preserve the historical beta artifacts intact.

### Current specific repaired defect
Issue #8 corrected the 10^6 error in TESPy standalone Rankine reference and was merged through PR #11. Pinned TESPy 0.11.2 in PR run 42771875293 re-executed and produced 12.987456 MW. This is NOT comparison against ThermoTwin: the reference cycle boundaries are unmatched. Do not rewrite the original DOI, paper evidence or old raw JSON.

### P0 acceptance gate
- `make check` / `scripts/ci_verify.py` reproducible; all applicable Ubuntu/Windows/macOS jobs green.
- Exact input version/units and failure reason for each new output; automated file-path and schema checks.
- No regression of design-point, map, transient, grid/scenario or output API; existing tests unchanged except deliberate fixes.
- No loose language such as “validated against Siemens”, “PTC 22 compliant”, or “humidity corrected” unless actual evidence exists.

## 4. P1 site performance correction (issue #13)

### 4.1 Reference and installation states
Use an immutable `ReferenceMachine` record (model inputs, base mass flow, component efficiencies, design firing schedule, pressure ratio, geometry/map surrogates and explicitly documented flange losses) and two distinct operating states: `ReferenceConditions` and `SiteConditions`. Reference is a definition, not a new machine fitted separately for every site. Specify whether inlet pressure is upstream or at the compressor flange, and whether exhaust pressure is flange static pressure or model ambient plus lumped loss; the current API exposes atmospheric pressure and fractional pressure-loss knobs.

Define `F(M, x)` as the Fortran off-design solution for fixed hardware M and conditions x at a declared load/control mode. For property q, `q_ref_model = F_q(M, x_ref)`, `q_site_model = F_q(M, x_site)`.

For positive extensive / ratio-corrected KPIs, use:
`C_q(site -> ref) = q_ref_model / q_site_model`.
Site derating `D_P = P_site_model / P_ref_model`; a test power corrected to reference is `P_test_ref = P_test_site * C_P`. For heat rate use an independently computed heat-rate ratio, not an inverse power assumption. For temperature use additive correction `Delta_T = T_ref_model - T_site_model` unless a justified non-linear protocol requires otherwise.

An identity case must yield `C_q = 1` and `Delta_T = 0` within numerical tolerance. Only use correction ratios when both solver runs are valid, within map domain and in the **same control mode**. Never multiply a series of one-at-a-time factors into a combined prediction without checking interactions against a single multi-variable solve.

### 4.2 First supported envelope
- Ambient dry-bulb temperature: e.g. -15 to 45 °C, bounded by numerical sanity.
- Site absolute pressure: e.g. 80 to 105 kPa (the direct input); altitude is optional approximate standard-atmosphere conversion, not a substitute for measured station pressure.
- Inlet and exhaust pressure losses: physically bounded as in current type and solver; define upstream/downstream pressure conventions.
- Fuel LHV: illustrative scalar sensitivity with explicitly fixed fuel chemistry assumptions.
- Humidity: **not supported** as a physical correction; keep the input for provenance but mark numerical effect unavailable. Explicit feature flag / QC result.
- Exhaust flow mass unit kg/s, temperature K/°C, heat rate kJ/kWh; distinguish fuel LHV basis from gross electric output.

### 4.3 Tests
ISO identity, warm-day loss in representative envelope, lower-pressure throughput, pressure-loss direction, monotonicity where physically expected, full-load/part-load mode invariance, combined-condition interactions, inverse correction round trip, finite outputs, and out-of-envelope refusal. Use at least 20 predetermined cases and a validation CSV with accepted/rejected statuses. Do not use Siemens product performance values.

## 5. P1 pass-off analysis, data QC and uncertainty (issue #14)

### 5.1 Dataset
Synthetic observations with `unit_id, run_id, timestamp_utc, operating_mode, ambient_T_K, ambient_P_Pa, inlet_loss, exhaust_loss, fuel_LHV_J_kg, measured_power_MW, measured_fuel_kg_s, measured_exhaust_T_K, measured_exhaust_flow_kg_s` and channel-specific calibration systematic + repeatability standard uncertainties. Include a recorded synthetic truth provenance and explicit metadata; do not suggest these are production measurements.

### 5.2 Pipeline
1. Validate CSV schema, units, ranges, timestamps, duplicate samples, missing sensors, transient/steady-state window and impossible power/fuel values.
2. Aggregate accepted steady-state samples and compute raw KPIs at test boundary. Reject insufficient windows, keeping a row-level rejection ledger.
3. Compute reference and test model points using **the same fixed machine**; calculate model-relative correction factors to reference and apply them to measured KPIs. Preserve both raw and corrected values.
4. Build measurement uncertainty from independently declared precision and bias components, and correction-model sensitivity, using `u_c^2 = J Sigma J^T` with a specified input covariance convention. If expanded uncertainty `U = k u_c` is reported, state the selected k and what it means; a 95% Monte Carlo percentile interval is a distinct statistic and must not be mislabeled “95% expanded uncertainty”.
5. Compare corrected power and heat rate with **fictional** contract guarantee and decision rules: pass, fail or indeterminate for an uncertainty-overlapping threshold. Never report a legal/contractual pass-off decision.

### 5.3 Tests
Hand-computable fixture for model correction, input unit scale checks, seeded Monte Carlo, zero-input uncertainty, correlated sensor propagation, QC negatives, guarantee borderline cases, rejection reasons and audit-trace JSON. Do not imply experimental validation.

## 6. P1 population statistical study (issue #15)

Generate synthetic 100+ engine IDs and three or more pass-off observations per engine (single reproducible seed). Simulate between-unit dispersion, ambient variation, small linear drift, abrupt shift, isolated gross outlier, one sensor bias episode, missing fields and duplicate rows. Create a separate sealed truth table for metric evaluation only, not training/detection.

Correct each accepted observation to the same reference conditions; detect drift in **performance residuals**, not in raw uncorrected ambient-correlated power. Implement an interpretable baseline: robust/OLS time trend with slope CI, fixed stable-subset mean/control variance and ±3 sigma Shewhart limits, plus grouped unit summaries. Document normality/autocorrelation assumptions and sensitivity to serial measurements. Evaluate false alarm rate, recall and detection delay on the injected anomalies; hold threshold selection independent of evaluation set.

Do not conflate grid dispatch and engine production population. No need to build a deep learning system.

## 7. Engineering outputs and recruiter-facing narrative (issue #16)

A single reproducible entry point shall produce:
- ISO-to-site prediction sheet with five KPIs, source SHA, scope and clear boundaries.
- Ambient/pressure/loss correction plots, including at least one multi-factor interaction and rejected-case evidence.
- Synthetic pass-off report with measured vs corrected output, uncertainties, guarantee band and rule-based decision.
- Synthetic production-population trend plot, control charts, suspected-anomaly ledger and confusion metrics.
- Short README “Performance engineer path” and a compact technical memo: requirements, method, result, checks, limitation and next validation requirement.

Figures should be generated from data in the checked CI run; avoid committing untraceable static images as definitive evidence. Provide command-line and report paths for each demonstration, even on systems without Windows GUI.

## 8. Proposed PR sequencing and exit gates

| PR | Work | Depends on | Gate |
|---|---|---|---|
| 0 (merged #11) | Correct TESPy W/MW, regression and CI reliability | None | All 10 CI jobs passed, frozen release preserved |
| 1 | P0 hygiene/model semantics inventory, doc links and baseline smoke tests | PR 0 | Clean three-OS CI and reviewable issue #12 evidence |
| 2 | Immutable-reference site solver API, 20+ fixture cases and CLI | PR 1 | Site identity, combined condition, boundary tests |
| 3 | Physical boundary/input coverage and unsupported correction flags | PR 2 | pressure/loss/fuel limitations evidenced; no fake humidity correction |
| 4 | Pass-off import/QC and model-ratio corrections | PR 2 | QC negative cases and hand-computable golden case |
| 5 | Uncertainty and synthetic guarantee decisions | PR 4 | independent UQ tests and decision-rule review |
| 6 | Synthetic population generator and trend/outlier metrics | PR 4 | ≥100 units, reproducible metrics and detection-negative controls |
| 7 | Integration reports, plotting, one-command examples and release review | PRs 2–6 | All deliverables source-backed, no speculative evidence |

**Stop condition:** a coherent site+pass-off demonstration with green CI and candid limitations is more valuable for the application than many loosely tested features. Scientific or external validation must remain a future stage unless genuine publicly releasable measurement evidence is available.

## 9. Verification matrix

| Gate | Requirement | Technique |
|---|---|---|
| V1 | Correct SI/MW/kJ/kWh units and sign | dimensional, hand-calculated and negative tests |
| V2 | Fixed reference across site curve | reference identity + altered site losses vs frozen map |
| V3 | Numerical physical plausibility | finite, convergence, domain and positive-balance checks |
| V4 | Reproducible processing | seed, source SHA, dependency version, full input provenance |
| V5 | Uncertainty traceability | precision/bias separation, covariance and Monte Carlo cross-check |
| V6 | Statistical credibility | baseline-only fitting, holdout evaluation, explicit FPR/recall |
| V7 | Communication | code-to-plot consistency and unambiguous synthetic watermark |
| V8 | Regression | CI on Ubuntu, Windows, macOS where applicable |

## 10. Risk register

- **R1: re-calibrating on site conditions masquerades as hardware correction** → immutable reference machine, identity and one-factor tests.
- **R2: unmodelled humidity/fuel composition creates misleading charts** → explicitly unsupported; no fabricated zero effect.
- **R3: numerical tests mistaken for OEM/plant validation** → machine- and study-specific disclaimers, no acceptance claims.
- **R4: optimistic pass-off decision with significant uncertainty** → indeterminate region and documented rule.
- **R5: synthetic anomalies look too easy** → negative controls, held-out truth and noise sensitivity.
- **R6: added scope destabilizes a broad codebase** → small isolated modules and PRs, existing regressions remain enforced.
- **R7: archival provenance corrupts a citable paper** → frozen tag/evidence unchanged, new commits and artifacts separately indexed.

## 11. Current status

- Repository baseline inspected 2026-11-10; main initially `d7cc0a3`.
- Historical numerical issue #8 resolved by CI-verified PR #11 (merged 2026-11-10) without modifying the DOI tag.
- PR #18 (merged 2026-11-10) added fail-closed CSV input validation and fixed stale documentation references, with 10/10 CI jobs passing.
- PR #20 (merged 2026-11-10, commit `8de141bb3b09d8e7e725ccbf9990df1f2eaa35ae`) implemented **site correction v0.1**: fixed hardware calibration, full-load reference-to-site ratios, 26 deterministic synthetic cases, CLI and out-of-envelope / unsupported-humidity rejection tests; 10/10 CI jobs passed. See [site performance guide](SITE_PERFORMANCE_v0.1.md). This does not close the full site-validation scope of issue #13.
- Pass-off correction / uncertainty (#14), statistical production-population analysis (#15), and integrated application-facing report (#16) remain **not implemented**. The full repository validity inventory (#12) also remains open. Their definitions of done are the acceptance gates above, not merely the creation of source files.
