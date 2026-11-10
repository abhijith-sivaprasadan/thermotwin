# Reproducible performance engineering dossier — CI deliverable

For technical reviewers and the Siemens Energy Lincoln Performance Engineer
application (304533).

The latest engineering evidence package is **generated from original-data
artifacts**, not a static report with manually entered results. Every
successful full CI run has a dependent job named **Recruiter evidence dossier
from UCI + ERA5 source artifacts**. Its prerequisites are both source jobs:

1. **Real UCI-551 turbine measurements and chronological holdout**,
   original UCI #551 dataset DOI: https://doi.org/10.24432/C5WC95,
   from one measured turbine. Artifact name:
   real-uci551-source-and-evaluation.
2. **Real ERA5 weather boundary integration**, using original gridded
   Open-Meteo historical reanalysis and a separate Fortran educational
   site-model output. Artifact name: real-era5-boundary-and-source.

## Open the actual package

Visit https://github.com/abhijith-sivaprasadan/thermotwin/actions/workflows/ci.yml

Select a **successful CI run for the exact commit being reviewed**. Download
the artifact named **lincoln-source-backed-engineering-dossier**. It contains
four files:

| File | Evidence | Important limitation |
|---|---|---|
| ENGINEERING_DOSSIER.md | Generated one-page technical summary | Actual source observations and model simulations are separately labelled |
| 01_uci_measured_holdout.svg | Regression on real UCI turbine TEY observations | Not independent physical gas-turbine model validation |
| 02_era5_model_site.svg | Historical ERA5 input driving the generic Fortran site-correction model | Both power values are MODEL predictions, not measured Siemens performance |
| source_ledger.json | Input original-source digests, exact code revision, output SHA-256 | Checks integrity, not model-form predictive accuracy |

The artifact is built **only when both upstream source jobs passed** and the
generator successfully verifies their outputs. Its checks cover the
original UCI ZIP SHA-256, audited annual source CSV digests and five-year
identity, the untouched training/evaluation years, original ERA5 raw JSON
SHA-256, valid weather UTC, the explicit dry-air approximation, the unchanged
fixed-reference hardware deck SHA-256, and agreement between the weather
boundary, Fortran input and site-model output. Ratio and correction
equations are independently cross-checked.

## Reproduce

Retain the original audited source outputs in build/uci551/ and
build/weather/, including their manifest JSON files and original raw
archive/response. They can be downloaded from the two prerequisite
CI artifacts from the SAME successful workflow run.

Run the following commands from the repository root:

1. python -m unittest scripts.test_build_lincoln_dossier -v
2. python scripts/build_lincoln_dossier.py --uci-dir build/uci551 --weather-dir build/weather --reference-case cases/site_iso_flange_reference.csv --output-dir build/lincoln-dossier

The local tests use **mathematical/schema fixtures only**, which are not
experimental observations and are never included in the publication dossier.
The actual-source CI job downloads genuine UCI and Open-Meteo artifacts.

## Strict engineering and publication limits

- UCI records are genuine single-turbine operating observations.
  The original TEY units remain source-labelled; they are not re-labelled
  as independently verified net electric MW. There are **no genuine engine
  fault/maintenance labels** or true multi-unit fleet IDs. Exact per-record
  UTC timestamps do not exist. Block resampling ranges are descriptive
  sensitivity checks, NOT calibrated statistical confidence intervals.
- Open-Meteo ERA5 is reanalysis weather **model output**, NOT a calibrated
  inlet/exhaust flange sensor. Humidity values are archived but not
  corrected in the dry-air turbine model. Source license, attribution and
  API terms are recorded in weather manifests.
- ThermoTwin-F calculates generic teaching-machine power, corrected ratios
  and exhaust states. It is NOT a Siemens Energy-specific or OEM-calibrated
  performance predictor. Neither the original model power nor a
  reanalysis-driven output is a measured engine test result.
- The pass-off heat-rate/uncertainty equations are independently tested,
  but actual permissioned test-stand power/fuel/LHV, instrument certificates,
  OEM calibration and contractual guarantees are not supplied.
  Guarantee decision: **NOT ASSESSED**.
- A passing CI run verifies data/software reproducibility and numerical
  identities, not independent engine validation or PTC 22 / ISO 2314
  compliance.

See [the role-specific evidence brief](LINCOLN_304533_APPLICATION_EVIDENCE.md),
[real UCI source study](UCI551_REAL_OPERATIONS.md),
[site performance physics](SITE_PERFORMANCE_v0.1.md), and
[pass-off equations](PASSOFF_CORRECTION_METHOD.md).
