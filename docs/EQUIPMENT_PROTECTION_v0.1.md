# Equipment-specific condition alarms — research implementation v0.1

**Scope:** detection, source quality, priority and operator notification **only**. This is not a turbine protection controller. There is no automatic trip, first-out record, shutdown rundown, permissive logic, restart, electrical relay or certified field sensor. Those belong to later project stages.

## Measured, modeled and training signals are not interchangeable

The seven new condition points are evaluated in `src/engine/equipment_protection.f90`, with state in `GridState`. They run after each dynamic model tick. Each point carries its source classification: **MODEL** (numerical plant/grid output), **TRAIN** (explicit injected test signal) or **NO DATA** (unavailable). The GUI preserves the existing eight grid/plant alarms on their original page and adds a second **EQUIPMENT** page with all seven points. Nothing is labeled a real plant measurement.

| Condition / equipment | Model input or required source | Alarm ON | Clear / hysteresis | Qualifier |
|---|---|---:|---:|---|
| Compressor low surge margin | Modeled off-design `surge_margin_pct` | ≤6% for 0.50 s | ≥9% for 1.0 s | Physics-model **proxy**, not measured compressor instability or OEM map |
| Rotor overspeed | Training input: actual rotor speed as % rated | ≥110% for 0.25 s | ≤106% for 1.0 s | **NO DATA** by default; grid frequency is explicitly NOT a shaft-speed measurement |
| Turbine exhaust high temperature | Modeled `exhaust_K` | ≥950 K for 2.0 s | ≤925 K for 2.0 s | Temperature model, not thermocouple spread/metal-limit certification |
| Combustion dynamics / instability | Training input: combustor fluctuating pressure, kPa RMS | ≥4 kPa for 1.0 s | ≤2 kPa for 2.0 s | **NO DATA** by default; modeled pattern factor or lambda is not dynamic pressure |
| Low lubricating-oil pressure | Training input: lube header bar | ≤1.2 bar for 1.0 s | ≥1.8 bar for 2.0 s | **NO DATA** by default; absent lubrication network and actual transmitter |
| High bearing temperature | Training input: bearing temperature °C | ≥105°C for 2.0 s | ≤95°C for 3.0 s | **NO DATA** by default; absent bearing thermal/damage model |
| Generator grid-frequency deviation | Modeled |Δf| from `frequency_Hz` and `nominal_frequency_Hz` | ≥1.0 Hz for 0.50 s | ≤0.5 Hz for 1.0 s | **Grid-frequency proxy only**; not generator voltage/current, differential or excitation protection |

**The listed limits are illustrative software exercise settings, not manufacturer settings, plant limits, OEM trip constants or standards-derived acceptance thresholds.** Confirmation/release times are in simulation elapsed seconds. An alarm is a persistent condition report; no limits are used to command an automatic trip.

## Robustness / state contract

- Each condition maintains independent onset dwell, exit dwell and hysteresis.
- Model channels are finite/range checked, and absent or invalid sensor channels are **NO DATA**, never silently reported normal.
- Synthetic training values are accepted only for rotor, combustor dynamics, lube pressure and bearing temperature, with explicit source identity, finite/physical plausibility checks and a 5 s **simulated** freshness deadline.
- Training channel values must be supplied explicitly through `set_equipment_training_input(st,id,value,ok)`; nothing is synthesized by the engine. There is **no GUI instructor-injection control yet**. Such controls belong to the separate step-4 instructor interface.
- Source loss cancels the pending dwell and does not silently retain a standing numerical threshold violation. The existing alarm workflow logs **BADQ** (data quality lost), displays **BAD DATA**, and logs restoration separately. It must not misreport data loss as a physically verified return to normal.
- P1/P2 priority and existing original synthesized annunciator sounds apply only to **active, unacknowledged and unshelved** points with source data. Acknowledgement and manual silence never change simulated plant physics. P1 cannot be shelved; P2 shelving follows the preexisting 600-s simulated-duration policy.

## Reproduction and tests

```bash
make -j4 build/tests/test_equipment_protection
./build/tests/test_equipment_protection
make check
make gui-offline
```

The Fortran tests cover missing inputs, 60 Hz frequency deviation, normal/rising/clearing state, debounce, hysteresis, non-finite inputs, training input provenance, stale expiration, forbidden model override and reset isolation. Windows CI builds and captures native GUI screenshots, including the new second alarm page.

## Limitations and next stages

This is not an engineered equipment protection safety function. Specifically absent: independent rotor-shaft dynamics, compressor active surge cycle and dynamics, combustor acoustic model, lubricating-oil circuit, bearing thermal/rotordynamics, synchronous-generator relay measurement, sensor failure redundancy, SIL analysis, OEM alarm rationalization, time-synchronised real measurements, and qualified trip/permissive logic. No safety or industrial deployment claim follows from green tests. Item 2 (first-out trip sequence and reset/restart) must not be described as implemented by this item-1 work.
