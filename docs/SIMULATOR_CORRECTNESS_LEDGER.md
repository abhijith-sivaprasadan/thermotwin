# Simulator correctness: engineering audit and trust ledger

**Your question:** Are the controls and results inside ThermoTwin-F correct?

**Verdict:** There is no universal yes/no. Some results reproduce coded conservation constraints and independent examples. Many other outcomes are simplified teaching models; some require physical measurements that do not exist in this repository. A successful compile or polished HMI is never evidence that a specific industrial gas turbine will behave the same way.

| Feature / user action | Evidence now supported | Remaining physical truth gap |
|---|---|---|
| Thermodynamic Brayton design solver | Unit/identity tests, explicit reference assumptions and independent comparisons | No matched OEM flange states, full fuel chemistry and calibrated component maps |
| Compressor surge margin | A reduced off-design map and ramp-based numerical proxy | No measured compressor surge trajectories or transient aerodynamics validation |
| Gas dispatch slider and AUTO | Deterministic, bounded AGC rules and grid balance checks | No commissioned governor, IGV actuator, combustion constraints or actual control tuning |
| GT TRIP and restart | Separate latched fuel/breaker state, first-out and independent regression | No measured speed rundown, verified fuel valve timing, purge/ignition feedback, generator breaker controls or OEM start permissives |
| Rotor speed, lube-oil pressure, bearing temp, combustion dynamics | Explicit NO DATA unless source-labeled TRAIN measurements entered | Missing coupled rotor dynamics, lubrication network, bearing model and dynamic-pressure time series |
| Exhaust temperature and temperature alarms | Modeled turbine outlet from cycle solver | No original exhaust thermocouple station/rake or thermal metal transient validation |
| Generator electrical alarms | Reduced grid-frequency deviation proxy | No AVR, voltage/current faults, generator relay discrimination or protection coordination |
| Grid frequency and UFLS | Integrated simplified swing equation, droop/BESS and staged shedding with code tests | No calibrated bulk-grid inertia, synchronous measurements or regional interconnection validation |
| BESS charge/discharge | Energy/SOC limits and efficiency bookkeeping | No inverter electrical, thermal and degradation test campaign |
| HRSG and bottoming cycle | Reduced thermodynamic and part-load models with reference tests | No pressure/level/transient boiler-metal/steam-turbine safety model |
| Trip rundown HRSG/GT speed | Explicit first-order or linear time constants | These are training assumptions, not validated gas/steam rundown dynamics |
| Fuel emissions and economics | Conditional algebra, source labels, price assumptions | Actual fuel composition, measurements, plant contracts and metering absent |
| AI/fault classification | Chronological UCI holdout and source-provenance analysis for a single turbine dataset | No independent industrial fault ground truth or multi-fleet field accuracy |
| ERA5 weather site studies | 672 reanalysis UTC hours and model-driven illustrative pressure-loss scenarios | Atmospheric reanalysis is not measured engine intake or equipment flange data |
| GUI priority alarm tones | Original PCM waveform tests and native Windows screen capture | No trained-operator acceptance, industrial alarm rationalization or certified annunciation |
| OPC UA | Software bus integration and Windows builds | No commissioned controller interoperability, real-time guarantees, or cybersecurity safety qualification |

## Actual bugs identified by source audit

- **Trip semantics**: the previous GT TRIP command reduced gas dispatch to the modeled minimum of 20% rather than disconnecting electric output. The new state-machine boundary corrects this educational behavior.
- **No persistent trip latch**: auto balance, manual gas controls and ordinary reset could undo a trip. Trip now overrides dispatch until explicit condition-dependent recovery.
- **Mass-basis specific work**: earlier audit fixed turbine hot-gas work versus compressor air-basis subtraction in the thermodynamic solver (see ENGINEERING_ACCEPTANCE_2026-11-11.md).
- **False validation readiness**: earlier audit fixed a measured-file readiness gate that treated a CSV containing headers but no valid rows as complete.
- **Sensor quality**: source-aware equipment monitors now explicitly distinguish MODEL, TRAIN and NO DATA rather than fabricating unknown bearing, shaft and lube readings.

## How to decide whether an internal action is credible

1. **Specify the state being manipulated**: air/gas mass flow, GT dispatch %, generator breaker, grid frequency, storage MW, thermal capacity, simulated sensor or a training override. They are not interchangeable.
2. **Check the equation**: explicit conservation identity, unit conversion, operational bound or declared approximation. The implementation does not automatically make a guessed parameter physically accurate.
3. **Check the observable**: numerical source, sensor/experiment with units, or illustrative exercise stimulus. Missing sensor data must remain NO DATA, never NORMAL.
4. **Check the coupling**: a trip must affect GT fuel, generator supply, remaining steam and grid frequency—not merely an alarm light. Tests enforce these connected outputs.
5. **Check independent evidence**: documented operating measurement with matching time, unit and equipment boundary. Without this, report a code-verified model or demonstration only.

## Open acceptance items

Real GT flange-state data, rotor speed and shutdown torque tests, electrical relay settings, purge flow measurements, vibration/oil/bearing sensors, HRSG thermal inertia, grid dynamic calibration, and trained human operator testing are all needed for an industrial-confidence claim. The current repository does not supply these items.

**Claims permitted**: reproducible numerical engineering research, bounded illustrative controls, original education-oriented HMI with explicitly marked proxies. **Claims not permitted**: demonstrated predictive performance on a real industrial GT, OEM-equivalent control, certified restart protection or standards compliance.
## Additional regression-discovered misconception

The old `turbine_trip.scn` and `gfm_bess_inertia.scn` assumed a full frequency return to 50 Hz after an event that *actually left the gas turbine producing at least 20%*. With the real modeled breaker/fuel trip, the reduced grid can remain short by 8–12 MW, settle below 49.5 Hz and invoke UFLS. Those old assertions were physically misleading and have been replaced with first-out, zero electric/fuel power, and sustained imbalance/frequency protection checks. The existence of a positive GFM synthesis term alone does **not** establish that GFM improves the nadir: that requires a matched counterfactual on/off experiment that is still missing.

- **Offline surge false positive**: when the GT trip boundary set dispatch and map surge margin to zero, the older alarm formula interpreted `0% margin` as an active compressor surge while the machine was stopped. The grid dynamics alarm is now gated on GT ONLINE state. This is a consistency fix, not an OEM surge-protection validation.
