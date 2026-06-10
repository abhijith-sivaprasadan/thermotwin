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
