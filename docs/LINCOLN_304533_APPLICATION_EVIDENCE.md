# Performance Engineering evidence brief — Siemens Energy Lincoln (Job ID 304533)

**Date:** 2026-11-10  |  **Status:** Technical portfolio evidence, not a job submission or industrial qualification

This short guide links the demonstrable ThermoTwin-F work to the
Lincoln Performance Engineer role posted 9 November 2026. The source
implements *educational reduced-order gas turbine physics* and synthetic
engineering cases, not a model of a Siemens Energy SGT product. It also
identifies the work that must not be claimed as completed.

## Reproduce the strongest job-specific result

```bash
make all tests
./thermotwin selftest
python scripts/generate_site_cases.py --output cases/site_sweep.csv
./thermotwin site cases/design_point.csv cases/site_sweep.csv output/results_site.csv
python scripts/test_site_pipeline.py --executable ./thermotwin
```

The site workflow pairs the same Fortran machine hardware with a fixed ISO
reference and 26 deterministic site input scenarios. A numerical correction
shows net power derating, relative heat-rate and exhaust-flow correction and
exhaust temperature offset; explicit flags reject humidity changes,
different hardware, degraded cases and invalid input envelopes.

**Verification record:** [site PR #20](https://github.com/abhijith-sivaprasadan/thermotwin/pull/20)
merged with [10/10 GitHub Actions CI jobs passing](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42775129821)
across Ubuntu, Windows and macOS; serial and OpenMP builds. The 26-case
pipeline, ISO identity, reference immutability, correction round trip and
deliberate rejection cases are automated. See
[site methodology](SITE_PERFORMANCE_v0.1.md).

## Job requirement vs demonstrated evidence

| Lincoln responsibility | Evidence available to examine | Boundary |
|---|---|---|
| Thermodynamic cycle calculations and model improvement | Fortran Brayton-cycle solver, turbine/compressor models, off-design methods and unit tests | Representative component maps, not OEM engine data |
| Installed-site performance prediction and proposal input | `thermotwin site`, reference/site correction CSV, 26 synthetic cases and documented factors | Not yet a bid prediction or contract guarantee |
| Automation, tools and software | Cross-platform build, CI matrix, reference-code checks, CLI and reproducible fixtures | Windows GUI compile is not interactive acceptance |
| Production engine performance data | Existing uncertainty/diagnostics machinery and separate correction design in issues | No actual production pass-off test tool, or real engine measurements |
| Large data analysis, trends and anomalies | Existing anomaly and fleet-dispatch modules; population project specification | Dispatch fleet is NOT a population of tested engines; #15 is still open |
| Communication to sales, R&D and manufacturing | Traceable readme, uncertainty caveats, numerically reproducible site-performance documentation | An industrial performance assessment requires actual validated maps/test data |

## Suitable technical CV/project-language draft

> **ThermoTwin-F — Fortran gas-turbine performance simulator:** Extended an
> open-source Fortran 2008 cycle model with an ISO-reference-to-site
> performance correction prototype for power, heat rate and exhaust
> characteristics; built 26 fully synthetic scenario cases, explicit
> unsupported-input rejection and cross-platform numerical/CI regression
> tests. Educational model; no OEM performance or test-data validation claimed.

Avoid saying "performed production pass-off testing", "PTC 22 compliant",
"developed a Siemens small turbine performance model" or "validated against
installed fleet performance". This project does not currently substantiate
those assertions.

## Engineering interview points

1. **Physical boundary**: compressor inlet pressure reflects upstream
   ambient pressure and a lumped inlet loss; exhaust backpressure is
   represented as ambient pressure plus a lumped fraction. A true
   manufacturer correction must specify the test flange conditions.
2. **Fixed calibration**: a reference-to-site comparison must not
   retune the design choked-flow map each time ambient conditions or
   installation losses are changed. The implementation explicitly
   pins machine calibration to one reference input.
3. **Correction mathematics**: model reference/site ratios for power,
   heat rate and exhaust flow differ; exhaust temperature uses an
   additive offset. Correction of measured data and uncertainty budgets
   are the *next* step rather than implied by these ratios.
4. **Uncertainty and judgement**: ISO identity and monotonicity checks
   are internal verification only; production acceptance needs known
   sensor uncertainty, repeatability, correlation and a guarantee
   decision rule.
5. **Scientific restraint**: relative humidity is present in the
   input schema but not used in humid-air property physics. The v0.1
   site workflow refuses changed humidity instead of silently
   producing an unjustified correction factor.

## Remaining deliverables

- [#12](https://github.com/abhijith-sivaprasadan/thermotwin/issues/12):
  finish full model-validity/data-provenance audit.
- [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13):
  extend site corrections, benchmark the envelope and produce interpretable
  performance-sheet plots (v0.1 core now implemented).
- [#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14):
  synthetic pass-off QC, corrected test metrics, uncertainty propagation
  and indeterminate guarantee decisions.
- [#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15):
  synthetic production population and statistical control charts.
- [#16](https://github.com/abhijith-sivaprasadan/thermotwin/issues/16):
  final data-backed sales/test/production engineering case-study packet.

This brief does not include personal application information; adapt the CV
and cover letter separately using independently verifiable education and
industrial experience.
