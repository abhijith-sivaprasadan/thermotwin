# CI external-data separation — 11 November 2026

## Why this change exists

On 11 November 2026, the active stacked protection/HMI development chain experienced **non-deterministic live Open-Meteo API failures**. PR #45's ERA5 boundary integration exited on a read timeout; PR #46's seasonal request exited on HTTP 502, with its boundary integration also failing; PR #54's two ERA5 jobs timed out. Fortran/OpenMP regression matrices and the native offline GUI build were green in those runs. These failures do not constitute model-validation or model-defect evidence, but a status marked green must not imply that an unexecuted remote acquisition succeeded.

## What PR CI now means

For `push` and `pull_request` events, the `reference-metadata` job runs the deterministic `scripts.test_open_meteo_boundary` and `scripts.test_study_era5_site_windows` suites, in addition to the normal solver, trip and GUI tests. They verify UTC and unit parsing, mandatory fields, fail-closed incomplete-data behavior, mock-script/replay contract, input-boundary handling and regression behavior. The external ERA5 jobs and live-source dossier are **skipped** explicitly, not counted as data acquisition passes.

For `schedule` (Monday 05:43 UTC) and manually dispatched `CI`, the original *real* weather jobs still run. A failed, delayed or unavailable provider is reported as a failed live integration; no synthetic data are substituted, no source manifest is fabricated, and no 'real reanalysis reproduced today' claim is generated. A live run must contain original Open-Meteo JSON, source SHA-256, the exact time window, source-qualified derived case CSV and the computed Fortran output to support its own claims.

This is an intentional distinction between **reproducible offline code verification** and **external live data availability**. The change is not an excuse to treat mathematical fixtures as experimental weather evidence, and it does not establish any real-turbine predictive accuracy.

## Operational implications

- If PR CI is green, that means the deterministic offline test gates passed. Check scheduled/manual live-source runs separately before claiming source re-acquisition.
- On a live-source outage, inspect the provider HTTP result/timeouts, record it as *upstream unavailable*, and retry manually or with a separately authorized scheduled run. Never silently fill a missing ERA5 hour or switch the model type.
- If the source changes its response model, grid, UTC coverage or units, the strict parser should still fail: that is a meaningful provenance/data-quality failure, not a transient outage.
- The source-release beta and its DOI remain unchanged. No industrial turbine/plant validation is implied.
