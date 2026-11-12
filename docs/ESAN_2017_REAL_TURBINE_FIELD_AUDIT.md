# Real 5.68 MW gas turbine: source audit and generator measurement-consistency study

**Evidence classification:** Real industrial-turbine operating measurements; measured-electrical-consistency analysis only. **Not** industrial Brayton-cycle predictive validation.

## Source and identity

[Esan & Ehiaguina, *Data-set for Independent Gas turbine for Electricity Generation*, Mendeley Data v3](https://data.mendeley.com/datasets/6w3vy3ybhg/3), DOI [10.17632/6w3vy3ybhg.3](https://doi.org/10.17632/6w3vy3ybhg.3), licensed CC BY 4.0. Nameplate 5.68 MW; raw measurements are labelled 2017 and uploaded in 2019.

The original **Raw 6months reading of Gas turbine..xlsx**, and **not** the revised filtered workbook, is locked to the publisher's original SHA-256:

    09b8ba80991998a370b6f8124450792a5150103383c0eff41f8f00b54d3e3bf9

The original workbook has **317 day/night worksheets** with up to twelve nominal hourly slots each (3,804 possible slots), with raw sensor labels in rows and observation values in columns B–M. The importer verifies the hash, original sheet structure, all required sensor names and units, and retains each observation's sheet number, sheet label and source column. Sheet order and time fractions **must not** be interpreted as authenticated synchronized UTC timestamps.

## What the original measured channels actually support

| Publisher's raw instrument label | Valid inference |
| --- | --- |
| Compressor inlet air temp. (T1) (oC) | Reported T1; outliers still need quality assessment |
| Compressor T5 average (oC) | Source's T5 only; **not** proof of Brayton T2 or turbine inlet T3 |
| Compressor outlet air pressure (PCD) (barg) | **Gauge** discharge pressure; not compressor absolute pressure ratio |
| Turbine Exhaust temperature T7 (Average) (oC) | Reported exhaust-temperature sensor; station equivalence to model T4 unproven |
| Gas fuel flow (kg/h) | Measured gas fuel mass rate; **not** thermal input without LHV |
| Liquid fuel flow (kg/min) | Reported other fuel mode; dual-fuel mixing is unresolved |
| Voltage (Vac), Current A/B/C (A) | Generator electrical measurements |
| Real power (kW), Apparent power (kVA), Reactive power (kVAR), Power factor (None) | Generator meter values; may be from one instrumentation system |

Missing/unverified for a genuine thermodynamic cycle calibration: compressor air mass flow, fuel lower heating value/composition, absolute ambient pressure, true turbine-inlet firing temperature, mapped compressor/turbine station definitions, specific OEM component maps, electrical metering boundary, calibration certificates and instrument uncertainty covariance.

Therefore the current **full-physics calibration gate remains BLOCKED**. Substituting invented air mass flow/LHV or assuming that T5 means T3 is not acceptable.

## Real measured-data electrical identity

The first-principles 3-phase relation used is:

    P_estimated_kW = sqrt(3) * measured_voltage_Vac * mean(current_A, current_B, current_C)_A * measured_PF / 1000.

Assumptions: reported Vac represents line-to-line RMS voltage, the mean current represents the balanced machine, and the reported PF applies to the same timestamp. None has been independently certified. No measured power is used to fit this equation.

The calculated power is compared directly with the actual source-reported "Real power (kW)" using RMSE, MAE, signed bias and individual residuals. The last 30% of accepted worksheet-ordered data are reported separately, **not** called a verified UTC test period. Electricity-meter channels may share a metering system, so this is internal instrument consistency **not** independent electrical metrology and not Brayton-cycle validation.

Predeclared numerical quality exclusions are visible in the JSON and are applied without reference to the size of the model error: source-real power >0 and <=5,680 kW; voltage 9,000–12,000 Vac; each phase current >0 and <450 A; power factor 0.60–1.00; all required electrical inputs finite. Shutdown strings, missing readings and violations are counted by first applicable reason. This retained subset is not identical to the original publication's other 2,946-row processed dataset.

## Reproduction

From the repository root (Python standard library only):

    python -m unittest scripts.test_audit_real_esan_gt2017 -v
    python -m scripts.audit_real_esan_gt2017 --out build/real-esan-gt2017

Offline:

    python -m scripts.audit_real_esan_gt2017 --original-xlsx "Raw 6months reading of Gas turbine..xlsx" --out build/real-esan-gt2017

The dedicated CI workflow downloads the exact licensed source file, verifies its original SHA-256, parses all 317 sheets, rejects inconsistent source labels and writes:

- original_2019_raw_shift_workbook.xlsx — the unmodified, source-hashed licensed workbook.
- real_turbine_electrical_identity.csv — actual generator readings, reconstructed electrical power, individual residuals, source position, compressor pressure, gas fuel flow and inlet/exhaust thermometry.
- readiness_and_electrical_consistency.json — source digest, all exclusions, measured-data statistics, and explicit flags that both generator-meter independent accuracy and Brayton solver physical accuracy remain **unverified**.

This is a verifiable real-world field use case with a scientifically bounded scope, not a claim that the generic 30 MW Fortran turbine accurately predicts a 5.68 MW operating machine.

## Next evidence needed

A machine-matched performance-test package containing measured air flow, fuel composition/LHV, compressor and turbine inlet/outlet station pressures and temperatures, generator efficiency/boundary, uncertainty and known hardware maps is needed before the source can pass the existing source-locked physical calibration and independent holdout protocol (docs/GT_PHYSICAL_CALIBRATION_PROTOCOL.md). Actual field records from the 5.68 MW machine must **not** be silently combined with the unrelated 3 kW UCI microturbine or the 30 MW generic demonstration model.
