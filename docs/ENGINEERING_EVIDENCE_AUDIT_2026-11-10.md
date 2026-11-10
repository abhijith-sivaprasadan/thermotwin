# ThermoTwin-F engineering evidence and model-validity audit — 2026-11-10

**Status:** Scoped, source/CI-based audit. This is not a full code-level model validation or a product qualification. The authoritative open follow-ups remain [#12](https://github.com/abhijith-sivaprasadan/thermotwin/issues/12), [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13), [#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14), [#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15), and [#16](https://github.com/abhijith-sivaprasadan/thermotwin/issues/16).

## 1. Audited baseline and what the green check establishes

At the beginning of this audit, branch main was commit
[ee0e0d3f877724d292c138563639472a92f46fad](https://github.com/abhijith-sivaprasadan/thermotwin/commit/ee0e0d3f877724d292c138563639472a92f46fad).
The [full CI run 42794474194](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42794474194)
completed with **13/13 jobs successful**. The independent
[UCI source workflow 42794474201](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42794474201)
also succeeded on that commit.

This establishes successful execution of the configured software and numerical gates at that **specific commit**. Individual OS-inapplicable workflow steps are expected to be skipped; the historical one-off beta source-publication workflow is not intended to publish on ordinary commits. Feature/PR CI runs from superseded intermediate commits may be canceled. None of these statuses should be described as successful field validation.

## 2. Feature maturity — separate implementation, numerical verification, external comparisons and field evidence

| Capability | Implementation | Internal verification | Independent/external evidence | Field/OEM validation |
|---|---|---|---|---|
| Open Brayton/simple-cycle component model | Fortran energy balances, reduced-order off-design and station-state equations | Self-test, three-OS release/debug and serial/OpenMP CI | No matched actual engine/operating-point comparison established | **Not established** |
| Fixed-ISO-flange site correction | Reference deck separates compressor intake and turbine exhaust flanges; ratios from paired solutions | Identity, boundary, dimensional and 26 mathematical test cases | Real-source **ERA5 reanalysis** feeds model T/P; that is weather **model output**, not an engine observation | **Not established** |
| Environmental fidelity | Dry-air T/P/pressure-loss workflow; relative humidity recorded | Fail-closed humidity input and domain tests | ERA5 grid-cell provenance and original response digest | **Humidity physics / OEM mapping not established** |
| Measured operating data and condition adjustment | UCI #551 intake and Python OLS physical-covariate analysis | Original source ZIP/per-year SHA-256, 36,733 rows, held-out 2014–2015; source-backed CI | **Actual one-turbine observations**, published by UCI, separated from generic Fortran engine | **No direct validation of ThermoTwin's engine**; no fault truth or multi-engine IDs |
| Statistical monitoring | Annual/holdout residual summaries, row-order slopes; additional blocked sensitivity in PR #31 | Mathematical tests, real UCI re-execution CI | Observed regression residuals, **not** independently recorded faults | **No evaluated detection sensitivity/specificity or causal degradation claim** |
| Pass-off correction and uncertainty | Fuel input balance, model ratio correction and 3×3 precision/calibration covariance with analytical Jacobian | Mathematical tests and negative-input rejection; no fabricated measured test cases | No source-authorized actual test-stand readings, validated uncertainty of correction factors or contract | **NOT ASSESSED**, no guarantee decision |
| Steam/water property functions | Approximate steam/property model and HRSG | Basic numerical/scenario checks | CoolProp discrepancy study and **standalone** TESPy Rankine reference, not matched-boundary ThermoTwin validation | **Not established; do not claim IF97 conformance** |
| Native Windows GUI / optional OPC UA | Windows build route and GDI dashboard code | Windows GUI **compile** workflow | No independently completed GUI visual/user acceptance and OPC UA operational commissioning | **Not established** |
| Extended scenario/grid/dispatch and surrogate modules | Exploratory Fortran components and demos | Parts covered by existing suite and scenario smoke checks | No independent field evidence asserted by this audit | **Not established** |
| Research release | Archival source-only beta v2.0.0-beta.1 | Release metadata, pinned reference tools, source audit, CI | Citable immutable Zenodo record for **historical beta source** | **Not an industrial software release** |

## 3. Audit changes and reproducibility gates

- Local Markdown link targets are checked by a versioned static verifier, not merely visually assumed to exist. It does **not** verify external links, rendered layout, document headings, or accessibility.
- The original annual UCI files have **unknown exact per-row timestamps**. A pooled adjacent-row autocorrelation that joined year boundaries was a methodological defect. PR #31 retains the legacy number only for traceability, adds a within-year de-meaned statistic and year-specific adjacent-row values.
- Forward-origin development folds use **2011 → 2012** and **2011–2012 → 2013**. The final **2014–2015 evaluation remains unfitted**. Its score is compared to the training-mean baseline rather than automatically described as an improvement.
- For the actual held-out residuals, the new report calculates year-stratified moving-block resampling at **32/64/128 consecutive published rows**, with a documented seed and 400 numerical resamples per block size. These are **descriptive sensitivity bands**, not nominally calibrated confidence intervals: original row gaps and local stationarity remain unverified.
- The report also measures actual held-out covariates outside the *training-only* observed feature ranges. This is an extrapolation warning, not a confirmed anomaly or statistically calibrated OOD detector.

Reproduce the source-linked checks:

~~~sh
python scripts/check_repository_links.py
python -m unittest scripts.test_analyze_uci_gt551 -v
python scripts/fetch_uci_gt551.py --output-dir build/uci551
python scripts/analyze_uci_gt551.py \
  --data-dir build/uci551 \
  --output build/uci551/condition_residual_report.json
~~~

The real source file set should be acquired through the canonical UCI #551 importer in the CI workflow, never recreated as an artificial surrogate. Mathematical tests use controlled numbers to check algebra; their numbers are **not** empirical turbine findings.

## 4. Open validity and research gates

1. **P0 audit #12 remains open:** independent equation-by-equation code review, model form validity, station thermodynamics, saturation/parameter bounds, provenance and dataset licensing; audit of downstream PDF figures and manual GUI acceptance is not completed here.
2. **Site model #13:** identify an actual compatible engine, matched intake/exhaust boundary and fixed control mode, actual validated component maps/fuel chemistry/humid-air properties and externally measured operating data before making performance-accuracy claims.
3. **Pass-off #14:** obtain consented genuine synchronized test windows, sensor certificates, original fuel LHV and manufacturer-relevant correction uncertainties. The existing instrument-only Jacobian cannot supply model-form uncertainty by assumption. Guarantee decisions remain unavailable.
4. **Operational statistics #15:** resolve UCI original instrument units and nonuniform sampling, evaluate remaining confounders and deployment drift, and obtain real fault/maintenance labels for failure detection. This dataset contains one turbine; a real production **multi-engine** population requires actual unit-ID data.
5. **Recruiter dossier #16:** add genuinely generated figures/report artifacts with exact source/job/commit provenance; proofread all numerical claims against the matching CI report. Avoid adding hypothetical customer results or mock test observations.

## 5. Safe engineering disclosure

A defensible statement is: **implemented and automatically tested reduced-order gas-turbine site physics, verified real-weather model boundary ingestion, audited one-turbine measured UCI records with separated evaluation, and mathematically verified conditional instrument uncertainty propagation**.

Do not say: independently calibrated Siemens turbine maps; measured site derating from ERA5; completed production pass-off; full ASME PTC 22 / ISO 2314 compliance; validated diagnostic detection of faults; or fleet statistics computed from one machine.
