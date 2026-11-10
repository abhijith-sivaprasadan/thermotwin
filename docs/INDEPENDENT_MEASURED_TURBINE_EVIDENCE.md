# Independent external gas-turbine operating evidence — measured-data checks

**Status:** Empirical source acquisition and exploratory physical consistency
checks implemented. **Absolute turbine-model predictive validation NOT
ESTABLISHED.** Neither a contractual pass-off nor an industrial acceptance
test is performed. This is more defensible than relabeling a statistical
correlation as an independently validated physics model.

## 1. Independent original observations

Ameen, Asaad Saber; Hamarash, Ibrahim Ismael (2026).
[SMART-GTPP Dataset, Mendeley Data V1](https://doi.org/10.17632/6sk3mhm7hb.1).
The original source contains **7,893 operating observations** from a single
combined-cycle plant gas turbine, with measured active electrical power
reported in MW (EP). It was not used to define ThermoTwin's generic hardware
reference or the earlier UCI #551 residual regression. License: **CC BY 4.0**.

The canonical original raw CSV is
[the source file published by Mendeley](https://data.mendeley.com/datasets/6sk3mhm7hb/1),
filename GTPP-DATASET.csv, with SHA-256:
bcfd39b0a5663add458e12cb6f7333436e1bd4206d8e79777d5878f596b0e9fa.

Verified source columns, all containing 7,893 finite numerical entries:

| Source column | Publisher meaning | Important limit |
|:--|:--|:--|
| AT | Ambient temperature | Unit not in raw CSV header; °C is an unverified hypothesis |
| AP | Atmospheric pressure | Unit not in header; inHg interpretation is a hypothesis |
| DF | Grid/electrical frequency | Not a shaft map, rpm or load demand record |
| CH | Humidity-related parameter | Exact physical basis/unit not verified; NOT mapped to solver RH |
| GP | Fuel-gas pressure | NOT fuel mass flow or calorific value |
| CPR | Compressor pressure ratio | Measured reported ratio; sensor station definition unverified |
| CPD | Compressor discharge pressure | Bar gauge/absolute convention NOT independently established |
| TTXM | Mean turbine exhaust temperature | Measurement station/units not verified for direct ThermoTwin mapping |
| EP | Active electrical power | Publisher reports MW, but electrical metering boundary uncertain |

The original CSV has **no verified UTC timestamp field, calibrated
measurement uncertainty/certificate IDs, metered fuel flow, fuel LHV or
compressor air mass flow**. Its exact row order cannot be used to claim a
chronological train/test split or hourly source sampling. These gaps preclude
an absolute comparison against a specific measured industrial engine.

## 2. Independent physics identity: exploratory pressure-unit alternatives

One physical relation can be tested without any turbine model calibration:
for compressor discharge pressure and ambient inlet pressure, the nominal
idealized pressure ratio should satisfy

    CPR_approx = P_discharge_absolute / P_inlet_absolute.

However, the publicly supplied raw source does not verify AP or CPD units
or CPD gauge-versus-absolute reference. We therefore report *both*
explicitly exploratory unit hypotheses rather than selecting one and
presenting it as a calibrated measurement result.

Assume AP is inches of mercury (1 inHg = 3386.38866667 Pa) and CPD is
bar (1 bar = 100,000 Pa). Under absolute-CPD, CPR is CPD_bar/Pamb_bar.
Under gauge-CPD, CPR is 1 + CPD_bar/Pamb_bar.

On all **7,893 actual original observation pairs**:

| Conditional pressure-unit hypothesis | CPR MAE | CPR RMSE |
|:--|--:|--:|
| CPD is bar gauge | 0.1932 | 0.2552 |
| CPD is bar absolute | 1.0210 | 1.0521 |

The gauge hypothesis is algebraically more consistent *under the assumed
unit conversion*, but neither hypothesis was preregistered and neither can
independently establish unit meaning, sensor calibration, station matching
or ThermoTwin component efficiency accuracy. This is an exploratory
observational physical-consistency **check**, not an industrial validation.

## 3. Compare measured environmental direction to frozen generic-model shape

A separate, unchanged **generic** 30-MW-class teaching reference is
evaluated in the current Fortran site code for all 7,893 observed ambient
AT/AP pairs (assuming AT in °C, AP in inHg). No turbine hardware map is
calibrated to EP, CPR, GP, CPD or TTXM; no source fuel quantity is invented.
The generic model holds the original fixed reference control, component
efficiencies, firing temperature and relative-humidity scalar at 0.60
(unsupported wet-air physics). Inlet and exhaust losses are held at zero,
because source installation losses are not available.

Each model source-input case and actual solver output is hashed/archived;
the CI job asserts **7,893/7,893 accepted** and checks identical reference
model power, source AT/AP to input/output units, site/reference power
correction and heat-rate mathematical identities.

Observed and modeled descriptive associations:

| Distinct evidence type | Pearson r |
|:--|--:|
| Real source ambient AT vs measured electrical EP | -0.9032 |
| Real source AT vs generic simulator modeled power ratio | -0.9925 |
| Measured EP vs *unrelated generic* modeled power ratio | +0.9043 |

The plotted shape curves are divided by **separate full-sample medians**
and are strictly descriptive. Such independent normalization **cannot**
prove matching absolute electrical power, heat rate, sensitivity magnitude
or actual operating-state prediction; it implicitly uses the observed
sample. The associations could be confounded by load, control, weather,
fuel, commissioning, outage selection or other operational factors.
There is no independently reserved chronological test period.

**Do not describe these results as validation of a Siemens SGT model or of
ThermoTwin predicting a measured gas turbine.**

## 4. Measurement and traceability gate

Use the [strict readiness checker](../scripts/check_gt_validation_readiness.py)
on an independent candidate test CSV. Its required physical fields include:

- Time-synchronized, station-defined intake and exhaust flange T/P;
  ambient humidity and compressor air mass flow;
- Fuel mass flow, measured fuel composition and LHV with precise basis;
- Independently metered electrical net power with agreed generator/auxiliary
  boundary, firing/control settings, compressor ratio and exhaust T;
- Fixed machine identity, compressor/turbine maps and supported operating
  envelope, pressure losses and instrument uncertainty/covariance profile;
- Source provenance, instrument certificates, an independently reserved
  test period, train/test no-leakage evidence and predeclared correction
  convention/acceptance criteria.

The gate writes a machine-readable **BLOCKED** report on the actual
SMART-GTPP columns; the missing measurements are never filled with generic
assumptions and described as observed. Even a complete checklist would
only make a dataset *eligible for evaluation*: it is not a passing model
accuracy or guarantee test by itself.

A true independent experiment should freeze the hardware map and fitting
choices on one machine/development period, then predeclare untouched
test windows and report raw and ISO-corrected absolute MW bias/RMSE,
heat-rate error, residual-vs-load/weather regimes, sensor uncertainty
propagation, model-form discrepancy and OOD flags. No contractual
acceptance decision is possible without actual contract terms.

## 5. Reproducibility

Every CI run downloads the original public CSV, rejects any SHA/column/row
mismatch, tests numerical and schema guards, builds the unchanged Fortran
solver, evaluates 7,893 separate source-based generic-model boundary
cases, verifies full output correspondence, generates descriptive
association and pressure-hypothesis diagnostics and publishes one
artifact, **smart-gtpp-original-measurements-provenance**.

Outputs include original source CSV, source_overview.json, source_and_assumptions.json,
model_input_cases.csv, model_site_results.csv, measured_partial_check.json,
EXTERNAL_MEASURED_EVIDENCE.md, measured_EP_vs_generic_model_shape.svg and
measurement_validation_readiness.json.

Tests use artificial algebraic fixtures **only** to verify code correctness,
never as publication/observational evidence. The actual results derive
exclusively from the original measured CSV and genuine Fortran calculation.

**Bottom line:** independently measured turbine *observations* have
supported a physical sensor-ratio plausibility examination and ambient
response consistency comparison. They do **not** supply the matched
instrument suite and turbine-specific model needed for independent
quantitative physical-performance validation.
