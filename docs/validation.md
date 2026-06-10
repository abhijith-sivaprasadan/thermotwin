# ThermoTwin-F Validation Notes

This file records the compact validation targets used by each physics revamp
phase. The values below are representative model checks, not a vendor guarantee.

## Phase 3: Combined-Cycle Bottoming Cycle

Reference target from `docs/REVAMP_PLAN.md`: a modern combined-cycle plant should
land in the approximate 52-56% lower-heating-value efficiency class for the
published comparison range cited there from Kehlhofer, *Combined-Cycle Gas &
Steam Turbine Power Plants*.

Validation case:

- Ambient: 15 C
- GT firing temperature: 1400 K
- GT dispatch: 100%
- Renewable/BESS contribution: 0 MW
- Mode: combined cycle
- HRSG: single-pressure, 35 bar, 15 K pinch, 8 K approach

| Quantity | ThermoTwin-F Phase 3 | Validation Target |
|---|---:|---:|
| GT net power | 30.32 MW | 30 MW-class machine |
| Steam turbine net power | 22.63 MW | Positive bottoming contribution |
| Plant net thermal output | 52.95 MW | GT + ST |
| Plant LHV efficiency | 52.33% | 52-56% |
| Plant heat rate | 6,880 kJ/kWh | Consistent with efficiency band |
| HRSG recovered heat | 47.06 MW | Below available exhaust heat |
| HRSG stack temperature | 376.1 K | Above wet-stack floor |
| HRSG pinch | 15.0 K | >= 15.0 K |
| Steam flow | 16.24 kg/s | Positive, tied to HRSG duty |
| Condenser back-pressure | 6.0 kPa | 15 C reference ambient |

Transient check:

| Quantity | ThermoTwin-F Phase 3 | Acceptance |
|---|---:|---:|
| Steam ramp limit | 0.18 MW/s | Steam train slower than GT AGC |
| 0.25 s steam response from cold target | 0.045 MW | Equals ramp limit x dt |

The validation is enforced by `test/test_combined_cycle.f90` and the full suite
passes through `make check`.

## Phase 4: Multi-Unit Fleet Dispatch

Reference target from `docs/REVAMP_PLAN.md`: Phase 4 should behave like a
plant-level operator dispatch stack, with multiple online units, economic
dispatch from heat rate and live fuel price, a spinning-reserve holdback, BESS
economic displacement, and online-unit inertia visible to grid dynamics.

Validation cases:

- Fleet mode: GT1 simple-cycle, GT2 fast-start aero unit, CC1 combined-cycle
- BESS: 30 MWh, 20 MW discharge/charge limit
- Reserve requirement: max(5 MW, 10% of demand)
- Fuel price: live `fuel_price_usd_gj`

| Check | ThermoTwin-F Phase 4 | Acceptance |
|---|---:|---:|
| Cheap fuel, 60 MW thermal target | CC1 SP 52.95 MW, GT2 fills ~7.05 MW, GT1 0 MW | Efficient CC1 is base-load unit |
| Cheap fuel reserve | 38.27 MW reserve at 70 MW load / 10 MW renewables | Above 5 MW requirement |
| High target reserve binding | 96 MW request limited to ~88.27 MW dispatch | Holds 10 MW reserve |
| High fuel BESS dispatch | BESS request reaches 8 MW in fleet scenario | Battery offsets expensive thermal MW |
| Fleet inertia online | 102 MWs | Sum of GT1, GT2, and CC1 inertia |
| CC1 trip inertia | 32 MWs | CC1 trip removes 70 MWs and worsens ROCOF |

Control interaction check:

| Quantity | ThermoTwin-F Phase 4 | Acceptance |
|---|---:|---:|
| High fuel, 60 MW demand, 30 MW renewables, 0.25 s tick | BESS request > 0 MW and thermal target < 30 MW | BESS displaces thermal dispatch before renewable curtailment |

The validation is enforced by `test/test_fleet_dispatch.f90`,
`cases/scenarios/fleet_dispatch.scn`, and the full suite passes through
`make check`.

## Phase 5: Market, Location, Weather, and Replay Inputs

Reference target from `docs/REVAMP_PLAN.md`: location selection should change
market prices, gas hub assumptions, ambient/weather conditions, and 50/60 Hz
grid standards live. Market and weather values should land on the tag bus and
be consumed by dispatch/economics without making the native executable depend
on a browser.

Implemented data boundary:

- Bundled offline profiles: Stockholm SE3, Germany DE-LU, Texas ERCOT,
  Louisiana Henry Hub
- External API alignment: EIA-style price cache fields, Open-Meteo-style
  weather variables (`temperature_2m`, wind speed, shortwave radiation)
- Weather fallback: deterministic wind/PV model from profile latitude,
  wind resource, irradiance, and installed capacity
- Replay fallback: deterministic 24-hour load/price shape compressed into a
  configurable scenario duration

| Check | ThermoTwin-F Phase 5 | Acceptance |
|---|---:|---:|
| Texas ERCOT profile | Nominal frequency 60.0 Hz | Location can switch grid standard |
| ERCOT fuel profile | 3.8 USD/GJ | Live fuel price below default TTF-style gas |
| Germany midday replay | Solar irradiance > 500 W/m2, PV > 10 MW | Weather drives renewable ceiling |
| Stockholm replay | Evening load exceeds night load by > 12 MW | Diurnal demand replay is active |
| Live power price | Revenue = demand served x `power_price_usd_mwh` | Economics consumes market tags |
| Live carbon price | Carbon cost = CO2 t/h x `carbon_price_usd_t` | Carbon price enters margin |
| Scenario replay | ERCOT reaches 60 Hz, >750 W/m2 solar, >70 MW evening demand | Full-day replay drives the engine |

The validation is enforced by `test/test_market_data.f90`,
`cases/scenarios/market_replay.scn`, and the full suite passes through
`make check`.

## Phase 6: Multi-Screen Native HMI Console

Reference target from `docs/REVAMP_PLAN.md`: the native executable should behave
like a control-room console, not a browser shell or single crowded dashboard.

Implemented HMI checks:

| Check | ThermoTwin-F Phase 6 | Acceptance |
|---|---|---|
| Screen navigation | Overview, Grid Dispatch, Gas Turbine, Combined Cycle, Market, Trends, Alarms | One nav click or F1-F7 |
| Faceplates | Overview KPI tiles open detailed faceplates | KPI detail available without changing screen |
| Alarm workflow | UNACK, ACK, RTN, log, shelve/unshelve | Raise -> ack -> return/clear supported |
| Persistence | `thermotwin.ini` stores screen, location, window mode, units, API placeholders, operating latches | Next launch restores HMI context |
| Location frequency | Frequency color/meter use `nominal_frequency_Hz` | 50 Hz and 60 Hz profiles render consistently |

Verification run:

- `make gui` builds `thermotwin-gui.exe`
- `make check` passes 15 unit-test programs plus the application selftest
