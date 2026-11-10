# ThermoTwin-F — pass-off correction mathematics and conditional instrument uncertainty

**Status:** Implemented reproducible calculation method, not a completed production engine pass-off. 
**Dependency:** A traceable measured performance test and a reference-to-site physics model computed for the same engine, load, fuel basis, boundaries, and test state. No Siemens Energy manufacturing, contract or confidential measurement data are bundled.

## 1. Provenance and evidence boundary

The user requested physical equations and actual data wherever possible, **not invented test-stand results**. A real pass-off record must include observed net electric power, measured fuel mass flow and LHV, site atmospheric T/P, confirmed steady-state interval, real engine/test identity, original acquisition/source identifier and instrument calibration record. The public UCI #551 one-turbine dataset lacks the required fuel-flow/LHV/calibration/guarantee columns and is **not an eligible pass-off dataset**. Weather forecasts/ERA5 are atmospheric estimates and cannot substitute for test-stand instrumentation. Therefore this package does **not** ship an example pass-off "PASS" or "FAIL".

The calculator accepts **only operator-supplied JSON** and a \`thermotwin site\` model CSV generated from the fixed ISO-flange reference and matching test condition. The tool cannot independently authenticate an operator's source claim, verify a calibration certificate, or confer a contractual acceptance verdict.

## 2. Engineering equations

For one declared steady operating condition, let \(P_s\) be *observed* electrical output in MW, \(\dot m_f\) the *observed* fuel mass flow in kg/s, and \(LHV\) the measured lower heating value in J/kg. Fuel input and site heat rate are:

\[
\dot Q_{\rm fuel,MW}=\frac{\dot m_f LHV}{10^6},
\qquad
HR_s=\frac{3600\,\dot Q_{\rm fuel,MW}}{P_s}
\quad\left[\frac{\rm kJ}{\rm kWh}\right].
\]

With the same hardware calibration and operating mode, the Fortran model computes \(P_{r,m},P_{s,m}\) and \(HR_{r,m},HR_{s,m}\). **Correction factors are not assumed constants.** They are evaluated from two physical model calculations:

\[
C_P = \frac{P_{r,m}}{P_{s,m}},\quad
C_{HR} = \frac{HR_{r,m}}{HR_{s,m}},\quad
\widehat P_r=C_PP_s,\quad
\widehat{HR}_r=C_{HR}HR_s.
\]

Model site T/P and fuel LHV must match the reported physical test conditions; otherwise the tool fails closed and instructs regeneration of model inputs. The correction factors must reproduce the model reference/site ratios to numerical tolerance, and the site row must be marked valid. This **does not** establish the accuracy of the Fortran component maps for the actual engine.

## 3. Measurement covariance, analytical Jacobian, and scope

Let \(x=[P_s,\dot m_f,LHV]^T\). Supply *full*, explicitly ordered 3×3 covariance matrices for precision/short-term repeatability \(\Sigma_{\rm precision}\) and calibration/systematic uncertainty \(\Sigma_{\rm calibration}\) in the **squared units of each input channel**. The matrices must be symmetric, positive semidefinite, and physically finite; correlated terms are retained, not discarded.

With \(y=[\widehat P_r,\widehat{HR}_r]^T\), the Jacobian for **fixed** model correction factors is:

\[
J =
\begin{bmatrix}
 C_P & 0 & 0\\
 -\widehat{HR}_r/P_s & \widehat{HR}_r/\dot m_f & \widehat{HR}_r/LHV
\end{bmatrix},\qquad
\Sigma_y =
J(\Sigma_{\rm precision}+\Sigma_{\rm calibration})J^\top.
\]

The code computes both marginal standard uncertainties \(\sqrt{(\Sigma_y)_{ii}}\) and corrected-power/heat-rate covariance; it keeps separate precision and calibration variance contributions.

**Crucial limitation:** These are conditional **instrument-only** standard uncertainties. The algorithm does **not yet propagate** uncertainty of the correction factors, compressor/turbine maps, humidity modelling, ambient boundary identification, speed/IGV/firing effects, or changes in operating mode. Consequently these are *not complete ASME PTC 19.1 / PTC 22 budgets*, cannot be used as final guarantee risk bands and do not represent a validated Siemens product. This version intentionally omits a guarantee-acceptance test and always reports \`NOT ASSESSED — UNVALIDATED MODEL / NO VERIFIED CONTRACT GUARANTEE\`.

Future complete budgets must include \(C_P(x,\theta)\) and \(C_{HR}(x,\theta)\) derivatives with respect to measured site T/P/losses and correlated fitted engine parameters \(\theta\), plus appropriate uncertainty on the guarantee itself. Sensitivities can be obtained with controlled perturbations of the same fixed-reference Fortran model, retaining covariance and evaluating nonlinearity. Model-form and OEM calibration uncertainty cannot be obtained by assuming a small percentage.

## 4. Input contract and provenance

The measurement input is an operator-provided JSON document of schema \`thermotwin.passoff.measurements.v1\`. It must contain the following keys/structures (schema illustration **only**, no actual measurements or fixture numerical values):

- \`schema\`, \`source_class = "recorded_test_stand_measurements"\`, \`test_id\`, \`engine_id\`, \`steady_state_verified = true\`, \`measurement_source_identifier\`, \`instrument_calibration_source_identifier\`, \`start_utc\`, \`end_utc\`, and \`model_site_case\`.
- \`measured\` object: \`net_power_MW\`, \`fuel_flow_kg_s\`, \`fuel_LHV_J_kg\`, \`ambient_T_K\`, \`ambient_P_Pa\`; all recorded, finite and physically positive.
- \`covariance\` object: \`variable_order = ["net_power_MW","fuel_flow_kg_s","fuel_LHV_J_kg"]\`, \`precision\` = full 3×3 matrix, \`calibration\` = full 3×3 matrix. Diagonal terms are *variances*, not standard deviations. Off-diagonal covariance is in the product of corresponding units. Do not substitute arbitrary uncertainties.

The physical source must be independently reviewed; nonempty provenance identifiers cannot prove that the records are genuine. The calculation is restricted to one synchronized, stable test interval. If the actual engine’s recording cannot substantiate stationarity or calibration, do not run a production pass-off conclusion.

Input and model CSV are both hashed SHA-256 in the output report. A retained model result CSV can be generated using the Fortran \`site\` mode, but using the generic \`run\` mode at a fixed mass flow does not constitute correct off-design engine performance.

## 5. Run

\`\`\`bash
make
./thermotwin site cases/site_iso_flange_reference.csv <real_site_deck.csv> <model_results.csv>
python scripts/passoff_correction.py \
    --measurement-json <actual_test_record.json> \
    --site-result-csv <model_results.csv> \
    --output <conditional_instrument_report.json>
\`\`\`

Here the angle-bracketed paths stand for *user-provided real records*, not bundled artificial data. The software does **not** auto-generate such records.

## 6. Verification and pending experimental work

\`\`\`bash
python -m unittest scripts.test_passoff_correction -v
\`\`\`

The regression tests use **analytical mathematical fixtures only**. The first-order Jacobian is independently checked by central finite differences for all three input channels; diagonal-covariance standard uncertainties are compared to the sample dispersion of **seeded mathematical Monte Carlo perturbations**. The numerical draws test the propagation equations, **not the calibration specifications, measurement records, or uncertainty of any actual turbine**. They verify fuel-flow/LHV heat-input dimensional conversion; independent heat-rate correction; corrected-value Jacobian; positive semidefinite and correlated covariance; explicit rejection of changed model inputs; invalid steady-state and source identifiers; and prohibition of industrial guarantees. No test fixture is scientific evidence of a running engine.

Next: obtain a redistributable, actual pass-off dataset or consented test-stand records with calibration/guarantee information; then add corrected-factor derivative propagation, test-window QC, true standard uncertainty analysis, independent method verification and protocol-specific acceptance decisions. Do not claim ISO 2314 or ASME PTC 22 compliance on the strength of these analytical tests.

**Standard concepts:** ASME PTC 19.1 (measurement uncertainty), ASME PTC 22 (gas turbine thermal performance) and ISO 2314 (gas turbine acceptance tests). This open educational workflow is *informed by*, not certified against, those standards.
