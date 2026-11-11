# Turbine-specific physics calibration: measured-source protocol and independent holdout

**Stage 3 of the ThermoTwin-F measured-data roadmap. Status: calibration workflow implemented; full industrial turbine accuracy NOT established.**

## Why existing open datasets are insufficient

The UCI #551 turbine records (DOI 10.24432/C5WC95) have no verified metered fuel flow and matched station measurements, and TEY units/aggregation are unresolved. The SMART-GTPP observations (DOI 10.17632/6sk3mhm7hb.1) contain real electrical output, but source pressure units, station locations, fuel metering and component maps remain uncertain. UCI #994 (DOI 10.24432/C58S4T) contains 3 kW micro-gas-turbine command-voltage and power time series, and properly supports the separate dynamic-system forecasting use case; it **cannot validate the 30-MW-class thermodynamic Brayton model**.

The audit of the actual published original source schemas is reproducible:

    python -m scripts.calibrate_gt_physics --audit-public --output build/gt-physics/public_data_readiness.json

This report is deliberately **BLOCKED_NO_ELIGIBLE_MATCHED_PLANT_MEASUREMENTS**. It does not import pseudomeasurements, fabricate industrial records or claim real engine model accuracy.

## Physically identifiable experiment

Using a single independently instrumented turbine and a frozen component-model plan:

1. Before fitting, reserve at least four later UTC-stamped steady-state operating points as untouched test. Require at least six earlier development operating points with independently varying compressor pressure ratio or turbine firing temperature, a fixed unit ID and a fixed hardware-map identity.
2. Fit **only compressor and turbine isentropic efficiency** using recorded compressor outlet **T2** and turbine exhaust **T4** from development operating points. Standardize both by declared measured thermocouple standard uncertainty. The calibration is a three-stage, coarse-to-fine bounded grid, each candidate solved with the existing real Fortran cycle solver.
3. Never fit to measured electrical power, fuel flow or heat rate: those are independent performance targets. Never inspect untouched test outcomes while fitting the two efficiencies.
4. Freeze the fitted efficiencies and run the **untouched** test inputs through the real Fortran model. Compare net MW, fuel flow kg/s, T2/T4 in kelvin and heat rate kJ/kWh to actual measured counterparts. Report each RMSE, MAE, signed bias and individual residual.
5. Predeclare a numeric RMSE limit for each output in the recorded measurement plan. Passing these limits is only a **conditional numerical comparison**: independent map, instrument, calibration, covariance and model-form verification still remains outstanding, and there is no OEM/contractual acceptance verdict.

## Required actual measured CSV

The source CSV needs every column from scripts/check_gt_validation_readiness.py REQUIRED_MEASURED_FIELDS plus:

- compressor_discharge_T_K — an actual calibrated station-2 temperature (not calculated).
- split — either development or untouched_test, with the latter chronologically later.

The upstream columns include timestamp_utc (UTC and strictly increasing), operating_point_id, unit_id, operating_mode = steady_full_load, hardware_and_component_map_id, ambient_T_K and ambient_P_Pa, measured compressor flange T/P, turbine exhaust flange P, compressor air mass flow, fuel mass flow and LHV, independently metered net electrical MW, measured compressor pressure ratio, measured firing and exhaust temperatures, generator efficiency, measured inlet/exhaust fractional pressure losses, uncertainty profile ID and original fuel-composition test ID.

The importer blocks missing/nonfinite fields, duplicate operating points, inconsistent machines, mixed operating states, overlapping development/test dates and impossible thermodynamic station ordering. The pressure stations must satisfy the existing model conventions P1=Pambient*(1-inlet_loss) and P4=Pambient*(1+exhaust_loss) within a tight tolerance. Compressor inlet flange temperature and ambient model temperature must match within 0.75 K. If real instrument stations differ, stop and implement the appropriate engineering boundary model first; do not substitute invented flange measurements.

## Frozen calibration plan

A JSON document with schema thermotwin.gt_physics_measured_plan.v1 must supply:
- source_csv_sha256 — exact original measured CSV hash.
- unit_id, hardware_and_component_map_id and validation_plan_id.
- model_form_uncertainty_disclosure — substantive description of current solver gaps.
- fixed_model_parameters — exact keys eta_combustor, combustor_pressure_loss, eta_mechanical, auxiliary_load_fraction and relative_humidity. RH must explicitly be zero under the current dry-air approximation. Values must be established by external machine-specific evidence, never guessed from the generic reference.
- fixed_parameter_source_ids — one nonempty source ID for each fixed model parameter.
- measured_standard_uncertainties — positive standard uncertainties in native units for exactly T2_K, T4_K, net_power_MW, fuel_flow_kg_s and heat_rate_kJ_kWh.
- predeclared_test_RMSE_limits — positive upper RMSE limits for the exact same five output names.
- all independently supported, positively attested boolean prerequisites in REQUIRED_METADATA from scripts/check_gt_validation_readiness.py.

**Attesting true to a field is not independently verifying its instrumentation.** This program cannot authenticate calibration certificates or a machine's identity. Keep confidential OEM station maps, instrument certificates, site measurements and industrial test plans private unless the owner explicitly authorizes disclosure.

## Run on eligible actual turbine measurements

Windows PowerShell, from the root of a working ThermoTwin-F checkout:

    make -j4 all
    python -m scripts.calibrate_gt_physics --measurements "private_data\my_measured_gt.csv" --metadata "private_data\my_frozen_gt_plan.json" --solver ".\thermotwin.exe" --output "build\gt-physics\private-study"

Use ./thermotwin instead of the Windows EXE on Linux/macOS.

An actual eligible package produces gt_physical_calibration_report.json and independent_holdout_predictions.csv. The JSON captures source, metadata, and compiled solver hashes; fit history, independent target errors, and predeclared checks. If eligibility fails, a machine-readable BLOCKED report is generated, and the program exits with failure.

## Validation categories

1. **Implementation verification**: the CI job compiles the genuine Fortran solver and runs explicitly labelled artificial mathematical fixtures for source integrity, efficiency identification, station boundary matching and untouched-test separation. Synthetic fixture predictions are **not** archived as plant data or used in scientific accuracy claims.
2. **Conditional measured-data evaluation**: requires actual source-locked, instrumented, machine-specific data and is not currently completed on a real industrial turbine.
3. **Independent plant predictive validation**: requires external data-source authentication, physically mapped stations, uncertainty covariance propagation, verified component maps, accepted reference conditions, residual audits across operating regimes, and external acceptance review. This remains **NOT ESTABLISHED**.

The work does not infer real surge, shaft overspeed, combustion instability, generator protective actions or remaining life from the open data. Such claims require dedicated high-frequency fault-labelled measured campaigns and OEM-specific control models.
