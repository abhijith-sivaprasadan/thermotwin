# Gas turbine first-out trip and restart — research teaching model v0.1

**Purpose:** distinguish an actual software trip-latch from a reduced dispatch request. This is a deterministic research simulator, not a certified safety instrumented function, DCS, turbine controller or OEM control logic.

## Why the earlier TRIP button was wrong

In single-GT mode, the previous `apply_turbine_trip` only lowered `gas_dispatch_pct` to 20%, let AGC rebalance and left the generator producing power. The new logic uses a separate **GT operational state** and **fuel/breaker isolation**; it cannot be canceled by a dispatch slider, an AGC command, or a routine RESET button.

## Trip sequence and provenance

1. **Trigger**: manual GT TRIP, or an explicitly supplied, quality-tagged TRAINING rotor overspeed, low lube-pressure or combustor-pressure oscillation alarm. Model-only compressor surge margin or generator grid-frequency deviation cannot cause an unqualified automatic safety trip.
2. **First out**: first cause and simulation timestamp are latched, with event history. Subsequent conditions during the lockout do not overwrite the cause.
3. **Immediate boundary**: generator breaker OPEN; fuel valve SHUT; flame OFF; blow-off valve OPEN and lube support assumed available. Modeled GT electricity, fuel and heat input become zero. AGC remains free to rebalance BESS and renewable power but cannot re-enable GT output.
4. **Rundown**: an explicitly illustrative speed exponential `N(t)=N0 exp(-t/11 s)`, exhaust decay `T-Tamb=(T0-Tamb) exp(-t/45 s)`, and combined-cycle residual steam power rundown at 0.45 MW/s. No OEM speed/torsional or heat-transfer transient validation.
5. **Lockout**: after estimated rotor speed drops below 3%, simulated turning gear engages. Alarm ACK is required but distinct from reset; a standing protective condition blocks recovery.
6. **Reset permissives**: machine locked out, acknowledged, estimated rotor at rest, turning gear assumption, estimated exhaust below ambient + 200 K, no active equipment conditions, and usable required sensor data. With missing physical sensors, the operator must explicitly enable **TRAIN BYPASS** to demonstrate restart. This is educational, NOT permission to operate real machinery.
7. **Restart**: separate action; 12 s simulated purge timer, 4 s assumed ignition, 20 s estimated acceleration, 3 s assumed synchronizing. These are a finite-state exercise, not validated purge airflow, ignition detectors, acceleration dynamics or synchronoscope checks.
8. **Return online**: only after the simulation's synchronization stage does the generator breaker close and online gas dispatch return to the minimum operating request. First-out history remains available.

All durations and thresholds here are **exercise assumptions**. A genuine machine requires OEM/system-specific setpoints, rated-speed feedback, combustor purge air-flow confirmation, valve verification, and protective relay instrumentation. This model cannot establish any safe industrial start.

## Console controls and events

Open **F7 > TRIP SEQUENCE** without leaving the original HMI design. Use **ACK FIRST**, **RESET TRIP**, **SIM RESTART**, **TRAIN BYPASS**. The panel shows first-out cause/time, rotor **ESTIMATE ONLY**, breaker and fuel isolation, event sequence and the reason a reset was refused.

**Fleet mode:** the existing fleet-unit outage event is not the same as the new single-GT trip sequencer. Fleet-specific generator protection, load-transfer and fleet recovery are not yet modeled and must not be inferred from this single-GT workflow.

## Reproducibility and acceptance

```sh
make -j4 build/tests/test_gt_trip_sequence
./build/tests/test_gt_trip_sequence
make check
make -j4 gui-offline
```

Regression tests cover immediate breaker/fuel isolation, zero generation before simulated synchronization, non-bypass by manual/AGC commands, first-out ordering, ACK/reset separation, fail-unknown required sensor input, explicitly acknowledged bypass, blocked active alarms, estimated cooldown and staged re-energization. Windows CI also captures actual GUI pixels for the trip page.

**Not verified by software CI:** field-like mouse/keyboard operator use, physical loudspeaker alerts, OPC UA security and interoperability, actual plant dynamics, OEM safety procedures or a SIL-rated trip system.

## Relevant external context

Siemens Energy describes GT/ST/HRSG shutdown and trip/restart as topics for operator training; its public program does **not** validate ThermoTwin-F's thresholds, timer constants or safety logic:
https://power-academy.siemens-energy.com/en/product/chapter/EAAAKNB/course/QA3TT7U/description.do