# Four-season historical ERA5 site-performance sensitivity — reproducible study

**Status:** Source-backed software/model investigation, not measured-engine validation.
**Location:** illustrative coordinate 53.23 N, 0.54 W near Lincoln, UK, NOT a documented
Siemens manufacturing test site or a specific operating turbine installation.

## Registered study design before looking at API outputs

The study acquires four equal-length, *predeclared* seven-day windows from
historical Open-Meteo ERA5 reanalysis in **2025**:

| Season label | First UTC hour | Last UTC hour |
|:--|:--|:--|
| Winter | 2025-01-15 00:00 | 2025-01-21 23:00 |
| Spring | 2025-04-15 00:00 | 2025-04-21 23:00 |
| Summer | 2025-07-15 00:00 | 2025-07-21 23:00 |
| Autumn | 2025-10-15 00:00 | 2025-10-21 23:00 |

Exactly **672 original UTC model hours** are required; each is compared with
the source raw JSON. No interpolation, missing-hour filling, case filtering or
post-hoc weather-hour selection is allowed. Any missing/malformed hour,
unit mismatch, duplicate UTC, inconsistent grid point or invalid model output
fails the job.

Source: [Open-Meteo Historical Weather API](https://open-meteo.com/en/docs/historical-weather-api),
explicit **models=era5**, **timezone=GMT**, temperature_2m in degrees C,
surface_pressure in hPa (NOT pressure_msl) and relative_humidity_2m in percent.
The importer converts T to kelvin, surface pressure to pascal and RH to
fraction; it archives original raw JSON, request URLs, returned ERA5 grid
location, UTC times and original-response SHA-256. Historical ERA5 is an
atmospheric **reanalysis estimate**, not an actual measurement from a gas
turbine inlet, exhaust flange, or test stand. Credit: weather by
[Open-Meteo.com](https://open-meteo.com/), CC BY 4.0;
review [API usage terms](https://open-meteo.com/en/terms).

## Fixed physical model, versus explicitly assumed boundary conditions

The same generic Fortran 2008 model and exact
[ISO-flange reference deck](../cases/site_iso_flange_reference.csv)
are evaluated at every historical weather hour: 288.15 K and 101325 Pa at
the model compressor intake flange, 101325 Pa at the turbine exhaust flange,
zero reference flange pressure losses, identical compressor/turbine geometry,
component efficiency, firing-temperature setpoint, generator/shaft settings,
fuel LHV and model control. Nothing is calibrated to any manufacturer's
compressor map, turbine design, plant fuel analysis or measured operation.

For every hour, four **a priori deterministic loss assumptions** are applied:

| Case | Upstream inlet loss fraction | Downstream exhaust loss fraction | Origin |
|:--|--:|--:|:--|
| z | 0% | 0% | hypothetical zero-loss boundary |
| i | 1% | 0% | hypothetical inlet-loss boundary |
| e | 0% | 2% | hypothetical exhaust-loss boundary |
| b | 1% | 2% | hypothetical combined-loss boundary |

These are *engineering parameters*, not weather observations or measured
installation dP. In the simplified model, p1 = p_ambient (1 - L_inlet) and
p4 = p_ambient (1 + L_exhaust). For each of 672 weather hours, the same Fortran
off-design solver evaluates four actual input decks, **2688 real model
calculations**, plus the unmodified ISO reference. Normalised power, corrected
heat rate, exhaust mass flow and temperature offset follow the physics
implementation (docs/SITE_PERFORMANCE_v0.1.md), not a fitted degree-Celsius
deration curve.

The weather source RH is preserved separately for each hour, while the
dry-air approximation keeps the model's original fixed RH **scalar = 0.60**.
This is NOT 60% RH physically corrected wet air. Atmospheric humidity,
composition, thermodynamic wet-air response and compressor-flange correction
remain **unimplemented**.

## Statistical reporting: distinguish *distribution* from *uncertainty*

The report contains source T/P/RH minima/maxima; observed distribution of
**modelled** normalized power ratios (min, median, max) by season and pressure
loss assumption; and median within-hour model-output spread among four
declared loss scenarios.

- **Not a confidence interval:** hourly min/max/median are descriptive
  summaries of the chosen 28 historical reanalysis days. They are not
  a climatological or population confidence interval and cannot establish
  annual-average turbine performance.
- **Not an uncertainty budget:** range across four assumed loss cases
  quantifies deterministic *boundary sensitivity*, **not** random error,
  sensor uncertainty, forecast/reanalysis error, or OEM model-form
  uncertainty. The real uncertainty of gas properties, maps, controls,
  fouling, site losses and humidity is **not quantified**.
- **Not engine validation:** no time-matched real turbine output, fuel
  mass flow/LHV, compressor inlet temperature, flange static pressure,
  serial numbers or maintenance/fault ground truth are available.
  These results cannot be used for customer bid predictions, test acceptance,
  emissions guarantees, industrial certification or contractual pass-off.

This is a seasonality/sensitivity **study of an educational simulator driven
by externally sourced atmospheric model inputs**, not a measured plant
performance study.

## Reproducibility and audit gates

After a successful CI run, download the artifact named
**era5-four-seasons-source-backed-site-study** from
[Actions CI runs](https://github.com/abhijith-sivaprasadan/thermotwin/actions/workflows/ci.yml).
It contains original per-week HTTP JSON, verified source manifest,
672-hour weather CSV, **2688 Fortran input and output case rows**, the derived
study_report.json and seasonal_summary.csv, a four-season SVG graph and the
recruiter-readable STUDY.md.

From the repository root, replay existing original JSON (NO live API needed)
by running:

~~~sh
python -m unittest scripts.test_study_era5_site_windows -v
python -m scripts.study_era5_site_windows acquire \
  --out build/era5-seasonal-replay \
  --reference cases/site_iso_flange_reference.csv \
  --replay-dir build/era5-seasonal-original
make -j4
./thermotwin site cases/site_iso_flange_reference.csv \
  build/era5-seasonal-replay/site_cases.csv \
  build/era5-seasonal-replay/site_results.csv
python -m scripts.study_era5_site_windows summarize \
  --out build/era5-seasonal-replay \
  --reference cases/site_iso_flange_reference.csv
~~~

The replay acquires **only the original source JSON snapshots** supplied by
the user. Both original API retrieval and offline replay mode are labelled
in the source manifest. The analysis also cross-checks each quoted weather
T/P/RH directly against the exact retained raw JSON, every case name and UTC
sequence, the model reference power, and the power/heat-rate/exhaust mass
flow/exhaust temperature correction identities.

**The tests themselves use mathematical, explicitly fictitious schema
fixtures only** to exercise the validation software. These numbers are
never included as measurements or results in the genuine CI artifact.
