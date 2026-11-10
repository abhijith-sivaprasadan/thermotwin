# Siemens Energy Lincoln Performance Engineer 304533 — auditable ThermoTwin-F evidence

**Prepared:** 2026-11-10  |  **Scope:** Open educational engineering software and independent *real-source* gas-turbine operating-data analysis; not a job submission or industrial qualification.

ThermoTwin-F has a documented Fortran 2008 simple-cycle model, fixed-reference full-load site-correction workflow, real publicly available atmospheric inputs, and a separately quantified condition-adjustment study on real turbine measurements. This portfolio demonstrates transferable gas-turbine physics, numerical/statistical evaluation and engineering tooling. **It is not a specific Siemens Energy SGT model, a certified performance predictor, a customer bid or a production pass-off test.**

## 1. Evidence hierarchy — do not conflate the data types

| Deliverable | Evidence | What it establishes | What it does NOT establish |
|---|---|---|---|
| Simple-cycle and off-design model | Source under \`src/\`, regression tests and Fortran CLI | A reproducible reduced-order physics implementation | Manufacturer compressor/turbine map or validated gas turbine power |
| ISO-flange reference and site solver | [ISO flange reference repair PR #27](https://github.com/abhijith-sivaprasadan/thermotwin/pull/27), [11/11 passing jobs](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42778470584) | Station 1/4 pressure boundaries, fixed machine calibration, correction factors computed from two real solver evaluations | Industrial performance accuracy or standards compliance |
| Real site weather boundary | [Open-Meteo ERA5 workflow](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42778470584), original JSON SHA-256 | Physically located historical reanalysis T/P/RH input, provenance and unit conversion | On-site calibrated inlet/exhaust instrumentation |
| Real gas-turbine operational measurements | [UCI #551](https://archive.ics.uci.edu/dataset/551/gas+turbine+co+and+nox+emission+data+set), [source/analysis CI](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42777201516) | 36,733 measured operating records from **one** turbine with a fully separated chronological evaluation | Multi-unit production pass-off population or confirmed fault labels |
| Pass-off correction and UQ method | [Issue #14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14), [PR #28](https://github.com/abhijith-sivaprasadan/thermotwin/pull/28), [equations](PASSOFF_CORRECTION_METHOD.md) | Algebra and instrument-only covariance method proposed for actual traceable test data | A completed industrial pass-off, full model-form uncertainty or contractual guarantee decision |

For a numerical claim, distinguish a mathematical unit-test fixture from external measured observations. **No artificial 100-engine population is distributed.** The archived source-only beta DOI 10.5281/zenodo.23679426 remains immutable.

## 2. Physics and full-load ISO-to-site correction

The educational gas-turbine model solves compressor, combustor, turbine and shaft balances using one hardware definition. The corrected inlet mass-flow scaling at fixed corrected-flow setting is of the form

\[
\dot m_{\rm air,site} \propto \frac{p_{1,\rm site}}{\sqrt{T_{1,\rm site}}}
\]

relative to the fixed reference machine, and the compressor/turbine station states are solved anew. The reference deck \`cases/site_iso_flange_reference.csv\` uses **288.15 K and 101,325 Pa at the compressor intake** and **101,325 Pa at the turbine exhaust flange**, with zero model reference inlet/exhaust losses. This differs from the legacy \`cases/design_point.csv\` with 1% inlet/2% exhaust losses. The site model now rejects a nonzero-loss deck labelled ISO flange and tests actual solved P1/P4/T1. Relative humidity 60% is recorded but **humid-air properties are not implemented**.

For the same machine, full load and declared fuel basis, the Fortran code evaluates model outputs at reference and site states, not a hard-coded per-degree deration. Its KPI conventions are:

\[
D_P=\frac{P_{\mathrm{site,model}}}{P_{\mathrm{reference,model}}},\quad
C_P=1/D_P,\quad
C_{HR}=\frac{HR_{\mathrm{reference,model}}}{HR_{\mathrm{site,model}}},\quad
C_{\dot m}=\frac{\dot m_{\mathrm{exh,reference}}}{\dot m_{\mathrm{exh,site}}}
\]

with an *additive* exhaust-temperature correction. Input QC and 26 deterministic **mathematical verification cases** test reference identity, pressure/loss trends, combined-condition interactions, model-ratio round trips and unsupported inputs.

**Real-source integration:** [CI #42778470584](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42778470584) fetched Open-Meteo ERA5 reanalysis near Lincoln for 2025-10-01 12:00 UTC: **T=287.250 K**, **surface P=102,390 Pa**. It retained original model-data humidity in its source manifest and ran the Fortran model with an *explicit dry-air approximation*. The educational generic hardware prediction returned **site/reference power ratio 1.01597119** and **reference/site heat-rate multiplier 1.00188331**. The ratios are model outputs driven by externally sourced atmospheric inputs; they are **not measured engine power**, accurate OEM forecasts, or humidity-corrected Siemens data.

Reproduction:

~~~bash
make all tests
./thermotwin selftest
python scripts/generate_site_cases.py --output cases/site_sweep.csv
./thermotwin site cases/site_iso_flange_reference.csv cases/site_sweep.csv output/results_site.csv
python scripts/test_site_pipeline.py --executable ./thermotwin
python scripts/open_meteo_boundary.py \
  --source archive --model era5 --latitude 53.23 --longitude -0.54 \
  --valid-time 2025-10-01T12:00:00Z \
  --reference-case cases/site_iso_flange_reference.csv --dry-air-approximation \
  --output build/weather/lincoln_era5.csv --snapshot build/weather/era5_raw.json
./thermotwin site cases/site_iso_flange_reference.csv \
  build/weather/lincoln_era5_case.csv build/weather/lincoln_era5_site.csv
~~~

The archive API can update data; reproduce exactly by retaining the raw response snapshot/hash and source manifest. Full assumptions in [site guide](SITE_PERFORMANCE_v0.1.md) and [weather guide](REAL_WEATHER_BOUNDARY.md).

## 3. Real turbine data — measured operating trends, not an invented fleet

[UCI data #551](https://doi.org/10.24432/C5WC95) is a real turbine dataset with five annual source CSV files (2011–2015), **36,733** operating records. Import scripts preserve original ZIP/annual counts, byte-level hashes and relative within-year row order. No exact per-record UTC timestamp exists; none is fabricated. CDP pressure-channel units are ambiguous, and TEY is source-labelled MWh; neither is silently converted into unverified mechanical/electric power MW.

The condition-adjustment study derives physically interpretable features from available real sensor channels:

\[
F_{\rm inlet,avail}=\frac{p_{\rm amb}-\Delta p_{\rm filter}}{101325}
\sqrt{\frac{288.15}{T_{\rm amb,K}}},\quad
\zeta_f=\frac{\Delta p_{\rm filter}}{p_{\rm amb}},\quad
\delta_T=\frac{T_{\rm IT,K}-T_{\rm AT,K}}{T_{\rm IT,K}}.
\]

These are corrected-flow/pressure-loss and temperature-state proxies, not claims of measured engine mass flow or thermal efficiency. A transparent OLS residual baseline uses the **2011–2013** records for fitting and keeps **2014–2015** untouched. A source-backed CI run found **14,542 held-out recorded observations**, TEY **RMSE 4.4771 and MAE 4.1798 in its source-labelled units**, and an initial concatenated-year training residual lag-1 value **0.9156** (legacy diagnostic spanning artificial year-boundary pairs). The later corrected within-year, de-meaned lag-1 is **0.9151**; neither value establishes physical-hour spacing. This strong residual dependence prevents treating independent three-sigma flags as confirmed turbine faults. No engine maintenance/fault ground truth or production engine IDs are present.

Reproduce:

~~~bash
python -m pip install numpy==2.2.6
python scripts/fetch_uci_gt551.py --output-dir build/uci551
python -m unittest scripts.test_analyze_uci_gt551 -v
python scripts/analyze_uci_gt551.py \
  --data-dir build/uci551 \
  --output build/uci551/condition_residual_report.json
~~~

**Revised real-source validation audit ([UCI CI run 42798697940](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42798697940)):**
the **14,542** original held-out 2014–2015 measurements retain TEY
RMSE **4.4771** in source-reported units; the 2011–2013 **training-mean
baseline RMSE is 14.9756** in the same units. This is an out-of-sample
statistical fit comparison, **not** proof of accurately predicted turbine
net MW or calibrated plant conditions. The corrected within-year,
year-demeaned training residual lag-1 is **0.9151**; **4.2360%** of
held-out points fall outside at least one training marginal feature range.
A 64-consecutive-published-row moving-block resampling has a
**descriptive** RMSE percentile range **4.2814–4.6597**. These samples are
not independent events; missing exact timestamps and nonstationarity
preclude claiming formal 95% coverage or known physical faults. The
development-only forward-origin checks (2011→2012, 2011–2012→2013)
and three block lengths (32/64/128 rows) are generated from the real
original files with original annual boundaries preserved.

See [equations, results and limitations](UCI551_REAL_OPERATIONS.md); immutable original-data and computed-source artifacts in [UCI CI](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42777201516). **This is one turbine, not a production engine population.** These empirical residuals do not validate ThermoTwin-F's generic 30 MW-class physics against the observed plant.

## 4. Pass-off method — what is and is not supported

A separate correction and instrument-uncertainty method is implemented and CI-verified in merged [PR #28](https://github.com/abhijith-sivaprasadan/thermotwin/pull/28). It uses model-derived \`C_P,C_HR\` and actual measured fuel-flow/LHV/power inputs, with the dimensionally consistent heat-rate equation

\[
HR_s = \frac{3600\,\dot m_f LHV}{10^6 P_s}.
\]

For conditional **instrument-only** uncertainty, it propagates supplied precision and calibration covariance, including correlations, with \(\Sigma_y=J\Sigma_xJ^\top\), where \(J\) is the analytical Jacobian of corrected power and heat rate. Its mathematical regression suite additionally compares exact analytical derivatives with central finite differences and checks first-order covariance against seeded mathematical Monte Carlo; **none of these test values are measured engine records**. It requires recorded test/source ID, instrument calibration ID, UTC acquisition interval, physical operating-point match and steady-state confirmation. The software **does not supply** actual production test readings, fitted OEM-model uncertainty, or a contractual guarantee. It reports \`NOT ASSESSED\`, not an invented acceptance result. A complete pass-off workflow remains blocked on genuine releasable test/guarantee records and model-validation evidence.

## 5. Mapping to the actual Lincoln responsibilities

| Lincoln responsibility | Demonstrated evidence | Remaining gap |
|---|---|---|
| Predict installed site performance | Real weather inputs + fixed-hardware Fortran site model; equation-based power, heat rate and exhaust corrections | Actual OEM compressor/turbine maps, humidity physics and field validation for bid-grade prediction |
| Validate production pass-off and development tests | Instrument correction method, documented covariance/jacobian (PR #28) | Actual measured/test-stand data, sensor calibration, full uncertainty and contractual acceptance |
| Thermodynamics and R&D test validation | Existing Brayton/simple-cycle component modules, fixed-boundary audit, Fortran numerical regressions | Model-form uncertainty and independent measured-engine comparisons |
| Analyse large technical datasets | 36,733 **real** single-turbine observations; held-out 2014–2015 OLS vs training-mean baseline, source-adjacent dependence and covariate support (PR #31) | Engine-population records, uniform time stamps and confirmed fault/maintenance labels |
| Improve software and automate analysis | Fortran modules, Python data tools, source hashes, UTC/API validation and cross-platform CI | Industrial software integrations and production/test lab interfaces |
| Communicate technical results | Reproducible technical notes, limitation reports, measured vs modelled distinction | Customer-facing engineering guarantees require OEM review |

## 6. Application language (evidence-based)

Suitable project language for CV/cover letter **after confirming the referenced CI results**:

> Extended an open-source Fortran 2008 gas-turbine simulator with a fixed-reference full-load site-correction method and explicit intake/exhaust reference conditions; automated physically sourced ERA5 weather boundary ingestion and traceable correction-factor checks. Independently analyzed 36,733 real turbine operating records using dimensionless corrected-flow/temperature covariates and chronological held-out evaluation. Implemented analytical measurement-uncertainty method with covariance propagation; no OEM or field-test validation claimed.

Do **not** say “delivered validated Siemens SGT performance”, “completed pass-off test acceptance”, “certified ASME PTC 22 predictor”, “detected proven engine failures”, or “analyzed a production fleet” without the underlying genuine source evidence.

## Four-season ERA5 sensitivity expansion (new source-backed study)

The [predeclared seasonal model study](ERA5_SEASONAL_SITE_STUDY.md) acquires 672 original ERA5 reanalysis hours across four seven-day 2025 windows near Lincoln, and evaluates 2,688 fixed-machine model scenarios spanning 0/1% assumed inlet and 0/2% assumed exhaust losses. It archives four original raw responses, request URLs, SHA-256s, verified hourly T/P/RH, every input and model output row, descriptive summaries and an SVG visualization. These are **reanalysis model estimates** plus **model-derived calculations**, not a measured installation, OEM correction map, calibrated uncertainty budget, annual climatology, or real pass-off test. Engineering parametric spread **must not** be called a statistical interval.

## Independent real external turbine observations (additional experimental-evidence layer)

A separate public [SMART-GTPP measured operational dataset](INDEPENDENT_MEASURED_TURBINE_EVIDENCE.md), DOI [10.17632/6sk3mhm7hb.1](https://doi.org/10.17632/6sk3mhm7hb.1), provides **7,893 observed active electrical-power records** from one combined-cycle gas turbine. An exact original-source SHA256 and the observed measurement schema are verified; the actual recorded power/ambient relationship, measured compressor-ratio pressure-unit alternatives and *unrelated generic teaching-machine* Fortran ambient shape are independently analyzed. The actual measured AT-EP association is Pearson r=-0.9032, but it is **noncausal** and is NOT validation that ThermoTwin predicts that machine's power. With no original source-unit-labelled AP/CPD, authenticated UTC, metered fuel mass flow/LHV, component maps or actual fixed hardware reference, quantitative physical power/heat-rate accuracy, ISO pass-off and OEM acceptance remain **NOT ESTABLISHED**. The [measurement readiness code](../scripts/check_gt_validation_readiness.py) explicitly blocks a false validation verdict.

## 7. Remaining research tasks

- [#12](https://github.com/abhijith-sivaprasadan/thermotwin/issues/12): full model limitation/provenance and dataset-rights audit.
- [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13): more physical site boundary and fuel/humidity model coverage, accuracy and external validation, not fabricated coefficients.
- [#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14): complete pass-off test and model uncertainty if real records become available; this cannot be faked.
- [#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15): single-turbine condition diagnostics developed; actual multi-engine production-statistics remain blocked on unit-ID data.
- [#16](https://github.com/abhijith-sivaprasadan/thermotwin/issues/16): final integrated technical portfolio output and traceability QA.

The public repository evidence is separate from the applicant’s Siemens Energy thesis, education, or immigration/eligibility information, which must be accurately reflected in the actual application.
