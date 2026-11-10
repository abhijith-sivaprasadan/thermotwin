# ThermoTwin-F — real turbine operating-condition study (UCI #551)

**Status:** First real-data ingestion and physics-informed regression implemented; **not a measured-engine validation of ThermoTwin-F**, not Siemens Energy data, not a production pass-off or multi-engine fleet result.

## Evidence source

[UCI Gas Turbine CO and NOx Emission Data Set](https://archive.ics.uci.edu/dataset/551/gas+turbine+co+and+nox+emission+data+set), dataset DOI [10.24432/C5WC95](https://doi.org/10.24432/C5WC95), CC BY 4.0.

- One turbine in Turkey; 36,733 actual hourly-aggregated observations spanning 2011–2015.
- Original separate annual CSV files: 7411 / 7628 / 7152 / 7158 / 7384 rows. Source chronology retained **within each year**. **Exact per-row timestamps are not provided.** We do not manufacture dates or time intervals.
- Original fields AT, AP, AH, AFDP, GTEP, TIT, TAT, TEY, CDP, CO, NOX. Source label for TEY is **MWH**; this study keeps the original reported unit rather than silently calling it average electrical MW.
- CDP is labelled mbar in the source despite numerical magnitudes around 10–15. Do not blindly treat it as absolute compressor discharge pressure divided by 1000 mbar ambient. CDP and gas-turbine exhaust pressure are excluded from the current physics covariates pending validation of instrument definitions/units.
- This is **not** a fleet; it cannot demonstrate genuine production engine-to-engine variance or guarantee acceptance.

To acquire exactly the original data and record source hashes:

~~~sh
python scripts/fetch_uci_gt551.py --output-dir build/uci551
~~~

The tool keeps the original ZIP, writes audited annual tables with the original relative row order, and records SHA-256 and licensing metadata.

## Physical assumptions and equations

The analysis uses physical features calculable from measured channels, not hard-coded expected power curves. Let ambient and filter-differential pressures be \(p_a\) and \(\Delta p_f\) (mbar to Pa) and dry-bulb temperature be \(T_a\) (°C to K). Under a *fixed* compressor corrected-flow operating assumption, atmospheric throughput availability scales with inlet total pressure divided by square root of temperature:

\[
p_{1,\mathrm{est}} = p_a-\Delta p_f,\qquad
F_{\mathrm{avail}}=\frac{p_{1,\mathrm{est}}}{p_{\mathrm{ISO}}}
\sqrt{\frac{T_{\mathrm{ISO}}}{T_{a}}},
\]
where \(p_{\mathrm{ISO}}=101325\,\mathrm{Pa}\) and \(T_{\mathrm{ISO}}=288.15\,\mathrm{K}\).

This feature is an **estimated nondimensional ambient-corrected throughput availability**, not a measured mass flow or a guarantee that the unknown actual turbine followed constant corrected flow. The published AFDP must represent pressure drop across the inlet filter for the expression to be used; actual flange flow and geometry remain unknown.

Additional measured, nondimensional terms:

\[
\zeta_f=\frac{\Delta p_f}{p_a}, \qquad
\theta_3=\frac{T_{\mathrm{IT,K}}}{1400\,\mathrm{K}}, \qquad
\delta_T=\frac{T_{\mathrm{IT,K}}-T_{\mathrm{AT,K}}}{T_{\mathrm{IT,K}}}.
\]

Here \(T_{\mathrm{IT}}\) is reported turbine inlet temperature; \(T_{\mathrm{AT}}\) denotes reported turbine-after temperature (TAT, **not** ambient AT). A temperature drop is related to simplified turbine specific work \(w_t\approx c_p(T_{\mathrm{IT}}-T_{\mathrm{AT}})\) for an adiabatic stage. Without mass flow, measured fuel flow, and composition, **no turbine mechanical power, efficiency or heat rate can be deduced** from these terms. The 1400 K divisor simply nondimensionalizes the covariate and is not a measured OEM design firing temperature.

## Condition-normalized operational residuals

Fit a transparent empirical OLS baseline to original reported \(\mathrm{TEY}\):

\[
\widehat{\mathrm{TEY}}_i=\beta_0+\sum_{j=1}^{4}\beta_j
\frac{x_{ij}-\overline{x}_{j,\mathrm{train}}}
{s_{j,\mathrm{train}}},\qquad
r_i=\mathrm{TEY}_i-\widehat{\mathrm{TEY}}_i.
\]

This is a *statistical adjustment conditioned on physically motivated variables*, not the Fortran Brayton cycle's performance prediction. It does not invent component efficiencies or fuel input. Only 2011–2013 observations determine coefficients, means, scales and diagnostic standard deviation; 2014–2015 is untouched evaluation.

The study exports per-year residual mean, MAE, RMSE, median, descriptive sequential-row slope and a \(|r|>3s_{\rm train}\) descriptive exceedance. **Those exceedances are not confirmed engine faults.** Serial autocorrelation and unobserved operator setpoints can make classic independent-sample control-limit interpretations invalid. No fault-detection sensitivity/specificity can be estimated without actual labels.

Reproduce:

~~~sh
python -m pip install numpy==2.2.6
python -m unittest scripts.test_analyze_uci_gt551 -v
python scripts/analyze_uci_gt551.py \
  --data-dir build/uci551 \
  --output build/uci551/condition_residual_report.json
~~~

## Executed source-backed CI results — 10 November 2026

The first successful [original-data analysis job](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42776869594) fetched and audited all 36,733 real rows and executed 10 mathematical/source tests. The **untouched** 2014–2015 portion has **14,542** observations; the initial physical-covariate OLS baseline produced **RMSE 4.4771 and MAE 4.1798 in the original reported TEY units**. The training residual lag-1 correlation was **0.9156**, showing strong adjacent-row dependence: unadjusted Shewhart flags should *not* be marketed as a fault detector. The source-backed report, original files and SHA-256 metadata are in the [CI artifact](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/42776869594/artifacts/13743329998).

These preliminary numbers measure how an empirical conditional baseline generalizes across years in one real recorded turbine, not the numerical accuracy of ThermoTwin-F's original 30 MW example engine. A scientific follow-up should inspect residual distribution shift, physically unexplained modes, original instrument definitions and possible autocorrelation-aware monitoring, without overclaiming causal degradation.

## Dependence/holdout audit (PR #31)

The initial version calculated an adjacent-row training correlation from annual
arrays joined end-to-start. This inadvertently introduced **two artificial
year-boundary pairs**. The revised output preserves that initial statistic
under a clearly named legacy key, and instead reports a **within-year,
year-demeaned pooled lag-1 correlation** plus individual within-year estimates.
Neither is a calibrated physical-hour autocorrelation: the original records
have no exact interval/timestamp sequence.

The revised real-data report also includes:

- Development-only **forward-origin evaluation**: train on 2011, test on
  2012; then train on 2011–2012, test on 2013. The final 2014–2015
  observations cannot influence model fitting, standardization or this
  development comparison.
- Actual 2014–2015 **OLS versus training-mean baseline** RMSE and MAE.
  A low error has value only relative to baseline and operating-state drift.
  Do not imply condition adjustment improved prediction before comparing
  the numerical outputs.
- Fractions of held-out measured points outside the **2011–2013 observed
  min/max** of each dimensionless physical covariate and outside *any*
  training marginal range. This warns about extrapolation; it is not a
  confirmed fault or multivariate OOD probability.
- **Year-stratified moving-block resampling** of actual held-out residuals.
  For each of 32/64/128 **published consecutive rows** and 400 numerical
  draws, the algorithm samples blocks strictly inside each original annual
  file, preserving that file's record count, then calculates mean error and
  RMSE. The 2.5–97.5th resampling percentiles are reported as
  **dependence-sensitive descriptive ranges**, **not** formally calibrated
  95% confidence intervals. Unknown sampling gaps, regime changes and
  nonstationarity may invalidate even their nominal interpretation. The
  fixed PRNG seed controls reproducible resampling *of genuine records*;
  it does not fabricate engine observations.

The checked CI source artifact contains the complete new report; the
initial numerical results in the preceding section remain labelled as the
**initial source-backed baseline** rather than silently changing values.
See the [evidence maturity audit](ENGINEERING_EVIDENCE_AUDIT_2026-11-10.md)
for what has and has not been verified.

## Limitations and next evidence steps

1. No instrument-level calibration/uncertainty budget, pass-off conditions, fuel rate, inlet-air mass flow, turbine mechanical power or OEM component maps are supplied.
2. No confirmed maintenance/fault or true engine-unit identifiers are available; *one* turbine only.
3. Published TEY is labelled MWH; do not reinterpret as MW merely because rows are hourly aggregates without documenting the acquisition interval and source definitions.
4. Missing exact UTC timestamps prevents event timing and proper irregular-sampling analyses; row index is a sequence, not elapsed hours.
5. The model is deliberately simple and transparent to establish provenance/validity. Residual patterns may reflect omitted operating controls, environmental factors, aging or instrument effects. None is causally established.

**Next:** independent column-unit audit with the dataset's original publication; residual distribution and covariate-shift diagnostic; compare physically interpreted trends to a fixed-component ThermoTwin off-design calculation only if the hardware/operating boundary is actually matchable. Do not claim ISO/ASME pass-off or Siemens-specific model calibration.
