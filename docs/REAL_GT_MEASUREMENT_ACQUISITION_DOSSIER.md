# Actual turbine performance measurements — acquisition and evidence-control dossier (2026-11-12)

## Evidence status: AWAITING SOURCE OWNER ACCESS

This is an **acquisition plan**, not a numerical/physical validation result. Its purpose is to obtain a complete measured machine-specific dataset eligible for the existing `scripts/calibrate_gt_physics.py` frozen-source, development/independent-test protocol. Do not promote any source to "field-validated" until independently traceable instrument boundaries, measurements, and conditions are verified.

Two source-specific research enquiries were prepared as private, unsent correspondence on 2026-11-12. No operator data have been provided or authorised for publication.

### Leads and what they actually establish

| Priority | Candidate and citation | Already accessible | Outstanding barriers |
| --- | --- | --- | --- |
| 1 | Esan & Ehiaguina, *Data-set for Independent Gas turbine for Electricity Generation*, Mendeley Data v3 (2019), DOI [10.17632/6w3vy3ybhg.3](https://doi.org/10.17632/6w3vy3ybhg.3), CC BY 4.0 | Original 2017 5.68 MW turbine workbook, 317 day/night worksheets; source-hashed electrical real power, reported phase voltages/currents, PCD in **barg**, T1, T5, T7, gas fuel mass flow in kg/h, liquid fuel flow and electrical PF | No documented compressor air mass flow, matched compressor exit T2, true turbine firing/inlet T3, measured **fuel LHV/composition**, measured ambient absolute pressure, OEM map, generator power boundary or metrology covariance. T5/T7 names are **not** proof of Brayton stations |
| 2 | Lim et al., *Towards a Digital Twin for Gas Turbines: Thermodynamic Modeling, Critical Parameter Estimation, and Performance Optimization Using PINN and PSO*, *Energies* 18 (2025) 3721, DOI [10.3390/en18143721](https://doi.org/10.3390/en18143721) | Published sensor set/thermodynamic-modelling methodology, including CIT/COT, combustor pressure, fuel-gas flow, exhaust or blade-path temperatures, electrical load | Operator data are subject to confidentiality; actual per-point source values and machine-specific station/air-flow/fuel/uncertainty definitions must be obtained or operator-held blind-tested |
| 3 | UCI #551, SMART-GTPP and UCI #994 | Source-backed regressions, independent source examinations, and 3 kW microturbine open-loop measured-power prediction already in this repository | None qualifies as full industrial GT thermo-measurement acceptance. Different turbine machines cannot be combined or physically scaled as though one engine |

**Latest completed empirical evidence:** [original 5.68 MW turbine electrical consistency audit](ESAN_2017_REAL_TURBINE_FIELD_AUDIT.md), PR #59. Source-observed electrical readings obey a declared no-fit three-phase power identity to measurable residuals. This is **not a Brayton model prediction** or independent validation of source meter calibration.

## Minimum viable data-owner release (one machine; at least 10 steady operating points)

To calibrate/test the existing Fortran machine-specific model without fictional boundaries:

1. **Physical engine and test scope:** exact unit identity or pseudonymous stable ID, OEM model/configuration, control/IGV and shaft configuration, installed compressor/turbine maps or permitted map summary, mechanical and generator conversion boundaries, inlet/exhaust duct losses and test reference condition. Confirm `operating_mode=steady_full_load` and the actual gross/net meter boundary; other operating modes must use a separate model.
2. **Original time-matched station measurements:** UTC timestamps or documented clock offset/synchronisation, operating point identifier; ambient temperature **and absolute pressure**; compressor inlet flange T/P, compressor outlet **T2 and P2** measured at identified tapping locations, compressor pressure ratio **absolute-total or explicitly mapped**; separately metered air flow; measured turbine firing/TIT/T3 or OEM-equivalent proxy explicitly classified as estimate; exhaust T/P and tapping positions.
3. **Energy and power balance:** separately metered gas and any liquid fuel flow, fuel composition and independently sampled LHV in J/kg with dry/wet and net/gross basis, simultaneous electrical MW at a declared meter, generator/mechanical efficiencies from attributable source records, measured auxiliary loads.
4. **Measurement quality and rights:** original engineering units and gauge/absolute definitions, calibration certificates or traceable serial/instrument history, combined standard uncertainties (and relevant shared-bias/covariance), missing-data flags, any time-alignment/transient screening rules, consent/data ownership/restrictions and permission to publish only derived charts/statistics as appropriate.
5. **Pre-registration of independent test:** freeze **at least six development** and **four later untouched test points** across sufficiently varied compressor pressure ratio or firing temperature. Reserve holdout values before fitting; lock data and frozen model/parameter source IDs with SHA-256. If fewer points can be shared, report *feasibility-only*, not an independently tested calibration.

### Data reduction constraints

- Never convert the Mendeley source's `Compressor T5 average` into compressor exit `T2` without a station drawing, nor source `Turbine Exhaust T7` into the physical cycle's turbine exit `T4` without confirmed location and intervening heat recovery/mixing.
- PCD is published in **bar gauge**; conversion to absolute Pa requires **same-point measured ambient pressure** and verified tapping/basis. Do not infer station compressor ratio from PCD alone.
- `Gas fuel flow (kg/h)` is usable as mass rate after sensor verification, but **not** a fuel-energy input without actual heating value. Mixed gas/liquid operation needs either independently paired fuel energy or exclusion of those operating points.
- No calibration of turbine `eta_c` and `eta_t` is credible without independently observed, aligned station temperatures/pressure ratios. `TIT` may be OEM model-estimated; label it accordingly and assess correlated errors rather than pretending it is an independent instrument.
- Do not publish sensitive plant tags, maps, raw logs or internal equipment identifiers without owner authorisation. Keep all operator-supplied raw input outside the public repository unless rights expressly permit publication.

## Technical deliverable on receipt

Check the received data privately before executing model fitting:

1. Record original filename, source owner and rights, license or data-use terms, acquisition timestamp, file SHA-256 and machine/configuration ID. Reject ambiguous or synthetic/test-fixture data.
2. Make a read-only **column/station map** from the owner's original names and native units to `scripts/check_gt_validation_readiness.py` requirements. Reject guessed or combined measurements.
3. Run the readiness gate and create the explicit `thermotwin.gt_physics_measured_plan.v1` frozen metadata with unit, hardware/map IDs, source digest, source-linked fixed parameters, standard uncertainties and **predeclared RMSE criteria**. The gate is necessary but not proof of metrological validity.
4. Run the existing `scripts/calibrate_gt_physics.py` on *development rows only*. Compare separate untouched real T2, T4, electrical power, fuel rate and heat rate. Independently review uncertainty, station conventions, energy balance, solver-model form and generalisation limits.
5. If rights prohibit transferring records, send a **fixed source revision and locked evaluation container/script** for the owner to run and ask for owner-approved aggregate residual metrics, source-count/evidence checks and explicit independent reviewer signoff. Do not claim full traceability without the supporting attested original calibration documents.

## Current scientific claims allowed

- Real source-backed **generator electrical identity consistency**, independently measured industrial 5.68 MW dataset, with disclosed assumptions and held-out original-sheet comparison.
- Real source-backed **3 kW microturbine input-to-output dynamical power prediction** on independent experimental runs.
- Source-locked **physical calibration software** with mathematical-only Fortran verification, ready for suitable machine-specific measurements.

**Claim explicitly blocked:** independent industrial gas-turbine Brayton/GT physics predictive validation, OEM acceptance/pass-off, industrial protective interlocks, fault/life prediction or numerical power/heat-rate accuracy against an identified real industrial engine.
