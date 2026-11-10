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

## 0A. Data-evidence policy (user-approved change 2026-11-10)

**Real observations take priority over synthetic runs.** All new scientific claims must be derived from governing physical equations, independent published property formulations or traceable measurements. No illustrative fixed power/efficiency deration percentages, fabricated multi-unit production populations, fabricated pass-off evidence, manufactured "live" sensor feeds or unverified OEM map coefficients are acceptable as empirical outcomes. Analytic fixtures may be used to test software mathematics and must be labeled test fixtures, not evidence of plant accuracy.

**Evidence sources and intended use:**
1. **Weather boundary inputs:** [Open-Meteo historical archive](https://open-meteo.com/en/docs/historical-weather-api) (ERA5 / ERA5-Land, georeferenced model reanalysis) and [forecast API](https://open-meteo.com/en/docs) (current weather-model estimates, not an on-site station). Import temperature_2m °C, surface_pressure hPa and relative_humidity_2m %, record UTC validity time, retrieval time, latitude/longitude, elevation, model, units, URL and raw-response SHA-256. Compare ERA5 reanalysis vs independent local station observations if station data can be obtained. Weather-model humidity is a **recorded input**, not a calculated humidity correction until humid-air properties are implemented. Free API is non-commercial only with CC BY 4.0 attribution.
2. **Real turbine operation:** [UCI Gas Turbine CO and NOx emission dataset #551](https://archive.ics.uci.edu/dataset/551/gas+turbine+co+and+nox+emission+data+set), DOI [10.24432/C5WC95](https://doi.org/10.24432/C5WC95). 36,733 hourly records during 2011–2015 from **one** turbine; 11 operating channels (AT, AP, AH, AFDP, GTEP, TIT, TAT, TEY, CDP, CO, NOX). Analyse known channel and unit provenance before any derived thermodynamic variable. The published rows have no exact timestamps; do **not** manufacture exact per-record UTC times. Preserve original year and within-year order. The values are field operation, **not** production pass-off tests or a multi-engine fleet.
3. **Independent plant data:** [UCI Combined Cycle Power Plant #294](https://archive.ics.uci.edu/dataset/294/combined+cycle+power+plant), DOI [10.24432/C5002N](https://doi.org/10.24432/C5002N). 9,568 full-load observations from 2006–2011 with ambient T/P/RH, exhaust vacuum and **combined-cycle** plant net power. **Not** direct GT output or same time period as UCI #551; never join datasets by implied time or claim validation of the small GT model.
4. **Independent reference formulation:** use CoolProp where a suitable property model is supported; track version and inputs. Exact OEM maps or calibrated turbine parameters are unavailable publicly unless separately documented, so cycle predictions must retain *unvalidated illustrative hardware* status, even with true weather inputs.

**Unresolved data access:** pass-off/guarantee measurements of multiple identifiable small gas turbines with calibrated instrumentation are not currently verified available as openly redistributable data. Until such measurements exist, the pass-off module shall implement/test a physics-based correction algorithm but **must not** display an invented completed engine acceptance test or invented guarantee outcome. A true cross-unit production trend needs genuine unit IDs; replace the planned pseudo-fleet with a real-data **single turbine operating time trend** first. No timestamp invention or cross-engine claims.

**No fake physics:** Correction factors must be generated by a model at both conditions, not inserted manually. For real UCI data, do not assume exhaust pressure is a fractional loss, or TEY field is exactly electric MW, before checking original field definitions. Do not infer turbine fuel flow or heat rate from the UCI set where no corresponding measurements exist.

## 1. Posting-to-code traceability

| Lincoln posting activity | Baseline asset | Deficit | Planned verification | Issue |
|---|---|---|---|---|
| Predict installed site power, heat rate, exhaust flow | `off_design`, `cycle_solver`, `ambient` | No explicit fixed-reference correction interface; humidity is inert | Reference identity, controlled one-factor sweeps, boundary tests, model-relative factors | [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13) |
| Assess production pass-off/development/site tests | `sensor_model`, `uncertainty_analysis` | No raw-test QC, model correction/guarantee decision | Unit tests, bad-channel rejection, uncertainty budget and synthetic test report | [#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14) |
| Thermodynamic calculations/models & R&D testing | `InputCase`, `CycleResult`, existing numerical tests | Unverified applicability and simplified steam/fuel models | Explicit limitations, numerical reference checks and traceability | [#12](https://github.com/abhijith-sivaprasadan/thermotwin/issues/12) |
| Large datasets / statistical investigations | `anomaly_detector`, `fleet_dispatch` | Grid-dispatch fleet ≠ production-engine population | Real single-turbine UCI #551 annual records, physically interpreted residuals and chronological evaluation | [#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15) |
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
Synthetic observations with `unit_id, run_id, timestamp_utc, operating_mode, ambient_T_K, ambient_P_Pa, inlet_loss, exhaust_loss, fuel_LHV_J_kg, measured_power_MW, measured_fuel_kg_s, measured_exhaust_T_K, measured_exhaust_flow_kg_s` and channel-specific calibration systematic + repeatability standard uncertainties. Preserve source files and calibration sheets. Use non-empirical analytic fixtures to test code paths; do not assert test-stand performance, guarantee results or actual measurement uncertainty without original measured channels and instrument specifications.

### 5.2 Pipeline
1. Validate CSV schema, units, ranges, timestamps, duplicate samples, missing sensors, transient/steady-state window and impossible power/fuel values.
2. Aggregate accepted steady-state samples and compute raw KPIs at test boundary. Reject insufficient windows, keeping a row-level rejection ledger.
3. Compute reference and test model points using **the same fixed machine**; calculate model-relative correction factors to reference and apply them to measured KPIs. Preserve both raw and corrected values.
4. Build measurement uncertainty from independently declared precision and bias components, and correction-model sensitivity, using `u_c^2 = J Sigma J^T` with a specified input covariance convention. If expanded uncertainty `U = k u_c` is reported, state the selected k and what it means; a 95% Monte Carlo percentile interval is a distinct statistic and must not be mislabeled “95% expanded uncertainty”.
5. Compare corrected power and heat rate with an **actual, documented** guarantee when legally accessible. Otherwise provide a decision-rule implementation with analytical threshold tests only, label guarantee outcome **NOT ASSESSED — NO CONTRACT INPUT**, and never report a legal/contractual pass-off decision.

### 5.3 Tests
Hand-computable analytical fixtures for model correction, input unit scale checks, seeded Monte Carlo, zero-input uncertainty, correlated sensor propagation, QC negatives, guarantee borderline mathematics, rejection reasons and audit-trace JSON. Actual measurement-based claims remain gated on identified test records and uncertainty specifications.

## 6. P1 measured operational trends and anomalies (issue #15)

**Replace the simulated fleet study.** Download UCI #551 from its canonical repository, verify checksum and per-year record counts, preserve known 2011–2015 year membership and chronological ordering within each published file, retain the source license/attribution and original raw files outside the Git history where appropriate. Derive documented physical features only from genuinely present columns: corrected compressor pressure ratio if relevant pressures are verified to be compatible, temperature ratios with K conversion, ambient pressure-to-absolute normalization, air-filter pressure-loss effect, and measured TEY/operating-point residuals. Verify units of TEY and instrument variables against the dataset documentation first.

Detect **within-one-turbine** changes using transparent multivariate operating-condition correction / residual models, a 2011–2013 training period and untouched 2014–2015 test period, supplemented by blocked validation; no random shuffling across time. Test baseline, CUSUM/EWMA or Shewhart limits only after documenting stationarity/autocorrelation, normalization and uncertainty limits. Report observed drift, statistical significance and possible confounders; without maintenance/fault labels, **do not state inferred anomalies are confirmed defects**. Do not invent exact event dates from year-only data.

A production **multi-engine** trend study is separately blocked pending an external dataset with real engine IDs and test records. Mathematical unit tests may use controlled inputs but never form the study's headline evidence.

Do not conflate grid dispatch with production populations, or fit a black-box model without physical interpretation.

## 7. Engineering outputs and recruiter-facing narrative (issue #16)

A single reproducible entry point shall produce:
- ISO-to-site prediction sheet with five KPIs, source SHA, scope and clear boundaries.
- Ambient/pressure/loss correction plots, including at least one multi-factor interaction and rejected-case evidence.
- Demonstrated pass-off **method** with equations and analytical verification; show a measured-vs-corrected report and guarantee band **only if genuine data and terms exist**.
- Real UCI #551 single-turbine trend/residual plots with chronological evaluation and precise provenance; no multi-engine claims.
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
| 6 | UCI #551 ingestion with field/units audit and one-engine observed trend analysis | PR 1 | 36,733 source records / chronological split / interpretable residuals |
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
| V6 | Statistical credibility | chronological real-data holdout, calibration diagnostics, no claim of fault recall without labels |
| V7 | Communication | code-to-plot consistency and unambiguous synthetic watermark |
| V8 | Regression | CI on Ubuntu, Windows, macOS where applicable |

## 10. Risk register

- **R1: re-calibrating on site conditions masquerades as hardware correction** → immutable reference machine, identity and one-factor tests.
- **R2: unmodelled humidity/fuel composition creates misleading charts** → explicitly unsupported; no fabricated zero effect.
- **R3: numerical tests mistaken for OEM/plant validation** → machine- and study-specific disclaimers, no acceptance claims.
- **R4: optimistic pass-off decision with significant uncertainty** → indeterminate region and documented rule.
- **R5: real operating data have no confirmed fault labels** → report anomaly flags with causes unverified; blocked chronological holdout and physical covariates.
- **R6: added scope destabilizes a broad codebase** → small isolated modules and PRs, existing regressions remain enforced.
- **R7: archival provenance corrupts a citable paper** → frozen tag/evidence unchanged, new commits and artifacts separately indexed.

## 11. Current status

- Repository baseline inspected 2026-11-10; main initially `d7cc0a3`.
- Historical numerical issue #8 resolved by CI-verified PR #11 (merged 2026-11-10) without modifying the DOI tag.
- PR #18 (merged 2026-11-10) added fail-closed CSV input validation and fixed stale documentation references, with 10/10 CI jobs passing.
- PR #20 (merged 2026-11-10, commit `8de141bb3b09d8e7e725ccbf9990df1f2eaa35ae`) implemented **site correction v0.1**: fixed hardware calibration, full-load reference-to-site ratios, 26 deterministic synthetic cases, CLI and out-of-envelope / unsupported-humidity rejection tests; 10/10 CI jobs passed. See [site performance guide](SITE_PERFORMANCE_v0.1.md). This does not close the full site-validation scope of issue #13.
- Pass-off correction and uncertainty (#14), **multi-engine** production-population analysis, and final dossier integration (#16) remain incomplete. The full repository validity inventory (#12) also remains open. A single-turbine real-data workflow under #15 is in PR #24 (source-backed 36,733 UCI records and held-out measured residual analysis verified in CI); it must not be called a fleet study.
- Weather API ingestion and a documented optional dry-air approximation are in PR #21. The ERA5 source acquisition was verified in CI; an integrated power prediction must be checked after the fixed-reference site solver and importer co-exist on the same branch/main.
- The historical proposed 100-engine synthetic population is **not** permitted as portfolio evidence; mathematical test fixtures remain permitted solely for verification. Public reanalysis and empirical turbine records are separate evidence classes.
