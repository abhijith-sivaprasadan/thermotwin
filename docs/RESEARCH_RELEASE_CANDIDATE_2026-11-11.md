# ThermoTwin-F — untagged research source-release candidate plan

**Prepared 11 November 2026. Not published. No release version or DOI is reserved by this document.**

## Proposed release class

A future **source-only, reproducible educational research revision**, separate from historical [v2.0.0-beta.1](https://github.com/abhijith-sivaprasadan/thermotwin/releases/tag/v2.0.0-beta.1) and its immutable [Zenodo DOI](https://doi.org/10.5281/zenodo.23679426). Do not move the old tag, change the archived ZIP, issue a binary promise, or describe this as an industrial predictor. Choose a new semver identifier only at release authorization after exact source acceptance.

## Automated candidate material

Every successful CI run for a candidate commit now checks [the machine-readable capability inventory](capability_evidence.json) and creates an evidence JSON with repository SHA, GitHub run ID, pinned predecessor baseline, source-inventory SHA-256, evidence-link counts and explicit non-validation flags. Retrieve the **research-release-candidate-audit** artifact from that same run.

Also preserve from that exact same run: original UCI #551 source + evaluation, single-hour ERA5 source + Fortran run, 672-hour seasonal ERA5 study, independent 7893-record SMART-GTPP observed/model check, original-source engineering dossier, external reference comparison and all test results. Keep the historical source license notices and provenance. CI artifact retention expires; durable archival requires a separate rights/redistribution review and immutable hashes.

## Release decision checklist

- [ ] Fix any failing candidate PR or main CI jobs; record exact full SHA, run link, compiler/library versions and changed-file review.
- [ ] Inspect independent source-derived figures and ledgers for correct units, labels, original-source hashes, separation of observation versus model, and no clipping or swapped test years.
- [ ] Review model and empirical claims against [the acceptance audit](ENGINEERING_ACCEPTANCE_2026-11-11.md), including unsupported humidity/fuel chemistry and uncertain SMART-GTPP source units.
- [ ] Verify third-party source redistribution permissions and Open-Meteo API terms; do not blindly put re-downloaded original data into a GitHub release or Zenodo archive.
- [ ] Check README, CITATION.cff, version metadata, release notes, ORCID, licensing and historical-beta references as a consistent exact candidate snapshot.
- [ ] Decide GUI scope: the safer candidate is **source-only with GUI explicitly experimental** until documented manual Windows GUI, OPC UA and redistributable dependency acceptance.
- [ ] Record reproducible build/test commands, exact source state, accepted known deficiencies, and DOI metadata before publishing a new immutable tag.
- [ ] Only then publish a new GitHub tag and verify the separate Zenodo deposition and DOI; external archive success is not guaranteed by a green CI build.

## Still blocked regardless of source-release readiness

Absolute turbine power/heat-rate predictive error, OEM-calibrated component maps, real field fault-detection metrics, instrument-certified pass-off, ISO 2314/ASME PTC 22 qualification and industrial guarantee decisions are **NOT ESTABLISHED**. They are external experimental prerequisites, not numerical regression checks that can be “closed” by more self-generated model cases.

This document authorizes no new release and makes no prospective promises of industrial accuracy.
