# Measured-turbine conditional replay v0.1 — actual observations and predictions

**Status:** first source-backed practical use case, proposed draft PR. It is **not** a physics-calibrated gas-turbine digital twin, next-hour forecasting, industrial fault diagnosis, or an OEM performance guarantee.

## The operational question

Given the turbine's **current measured** inlet/ambient conditions and turbine temperatures, can a model trained only on past observations estimate that record's source-labelled turbine energy yield (TEY)? What does the model miss when evaluated on a chronologically later year, and how often do its input features leave the original development range?

This is a **same-record soft-sensor/condition-adjusted prediction**. It is useful for explaining measured-vs-expected residuals and data-quality boundaries, not for independently predicting power from a planned dispatch or future weather.

## Provenance

- Original: Gas Turbine CO and NOx Emission Data Set, UCI #551, DOI https://doi.org/10.24432/C5WC95; CC BY 4.0.
- 36,733 hourly aggregated records, **one** measured gas turbine, reported 2011–2015.
- Source annual CSV files are validated and SHA-256-locked by the existing scripts/fetch_uci_gt551.py importer.
- **Development:** 2011, 2012 and 2013 (22,191 records). **Untouched test:** 2014 and 2015 (14,542 records).
- Original observations are in their published intra-year order, **not** actual UTC-stamped or uniformly spaced samples. Never invent a 1-hour sampled timeline or join year boundaries into a continuous elapsed-time axis.
- Original TEY is labelled MWh; its exact hourly aggregation/physical measurement boundary is not verified. Do not relabel output as measured turbine MW or heat rate.
- Source CDP units are ambiguous, and so are intentionally excluded from this model. There are no fuel mass flow, complete component maps, known fault labels or independently defined duty schedules.

## Method

The same four preexisting physically motivated covariates from scripts/analyze_uci_gt551.py are retained without pretending they are direct measured air mass flow or turbine work:

1. Intake flow **availability factor**, from measured ambient pressure minus air-filter pressure loss, corrected for ambient temperature.
2. Measured air-filter pressure-loss fraction.
3. Temperature ratio from same-record measured TIT.
4. Turbine expansion temperature-drop fraction from same-record measured TIT/TAT.

Fit a four-feature, standardized ordinary least squares model on **2011–2013 only**. Freeze its coefficients, means, training-feature min/max and its descriptive residual standard deviation. Apply it to each original **2014–2015** record. Exclude TEY, CO and NOx entirely from the feature matrix. Even with a later-year holdout, measured TIT and TAT are recorded **simultaneously** with the target; this is not next-hour or multiday forecasting.

Report source-unit RMSE, MAE and signed bias against the source-measured TEY, plus a naive **2011–2013 TEY mean** baseline; show separate 2014 and 2015 metrics. Mark observations outside any marginal training-feature range; these indicate extrapolation but are **not fault labels**. Flag large residuals versus 3 times *training* residual sigma as descriptive only; no statistically calibrated coverage or confirmed failure may be inferred.

## Reproduce locally (Windows PowerShell, from the repository root)

Prerequisite: Python 3.11+ and NumPy compatible with your installation. The repository's CI pins NumPy 2.2.6.

~~~powershell
python -m pip install numpy==2.2.6
python -m unittest scripts.test_replay_uci_gt551 -v

# Fetch original UCI data once, verify its source, year counts, units and hashes
python scripts/fetch_uci_gt551.py --output-dir build/uci551

# Fit on original 2011-2013 data and replay 2014-2015 observations
python -m scripts.replay_uci_gt551 --data-dir build/uci551 --out build/uci551/replay

# Open the original-observation comparison in your normal web browser
Start-Process .\build\uci551\replay\measured_turbine_replay.html
~~~

To replay offline when you already possess the original downloaded ZIP:

~~~powershell
python scripts/fetch_uci_gt551.py --original-zip build/uci551/uci551_original.zip --output-dir build/uci551
python -m scripts.replay_uci_gt551 --data-dir build/uci551 --out build/uci551/replay
~~~

## Outputs

- measured_vs_predicted_2014_2015.csv — all 14,542 original later-year observations with source year/within-year index, recorded ambient/temperature inputs, model prediction, source TEY, signed residual, training-mean baseline, out-of-range and large-residual indicators.
- replay_report.json — fitted coefficients, frozen training quantities, annual and aggregate errors, source ZIP SHA, audited manifest SHA, prediction CSV/viewer SHA and explicit evidence/validation limitations.
- measured_turbine_replay.html — **offline, self-contained interactive viewer**: scroll the published measured records, inspect measured-vs-predicted TEY, signed residual, ambient/TIT readouts and model operating-range flag. The x-axis is source record index, not fabricated UTC.
- Existing UCI-source CI artifact now includes the generated replay for the same workflow run and pinned code commit.

The original source ZIP and audited annual CSVs are retained in build/uci551 (CI artifact), not silently substituted with synthetic data. The test suite does use explicitly marked **mathematical** fixtures to check software behavior; fixture outputs are not presented as turbine performance results.

## Next data-to-simulator integration

1. Import this **source-qualified replay CSV** as a new read-only HMI mode, with an always-visible badge **MEASURED REPLAY / UCI 551**. Never feed a measured historical TEY directly into the turbine fuel valve or protective interlocks as if it were a live plant state.
2. Visualize measured sensor values and predicted residuals alongside the original ThermoTwin-F physics predictions, **separated**, with distinct units/source roles and a linked operating envelope.
3. Add a truly **prospective** forecast (e.g., 1-hour-ahead turbine TEY) only when raw timestamps, valid lead-time input availability, target definition, nonleaky load/dispatch controls and prospective time-split evidence support it; the present dataset does **not** prove that task.
4. Calibrate and validate the physical model only with a machine-identifiable, station-matched dataset containing T/P at defined boundaries, fuel flow/LHV, measured electrical output, speed/controls, hardware map references and uncertainty/quality records.

**Acceptance criterion for v0.1:** exact source hashes and record counts; no missing or synthetic held-out readings; no target leakage; unchanged test-year predictions when only test-year TEY is perturbed in mathematical fixtures; a useful interactive evidence viewer; CI artifact independently regenerable; no unsupported industrial predictive-accuracy claim.
