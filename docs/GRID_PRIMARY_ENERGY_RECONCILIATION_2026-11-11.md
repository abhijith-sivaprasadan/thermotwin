# Grid primary-response energy ledger — issue #47 (educational model)

**Status:** proposed source-level correction, not field validation. **Dependency:** PR #47's work is stacked on audit PR #46, trip PR #45, equipment alarms PR #44 and HMI PR #43. The implementation changes the meaning of several numeric telemetry tags; old scenario outputs are NOT directly comparable.

## Single-source active-power accounting

For each engine timestep, one delivered BESS power `storage_MW` and one off-design physical GT power `gas_power_MW` enter both the reported power balance and the swing equation.

```text
Operator/AGC GT request [%]
   + bounded 5% droop offset [%] (ramped by illustrative 8 %-point/s)
   -> off-design gas-turbine solve -> actual GT MW + fuel kg/s + exhaust state
                                 -> governor_delta_MW is a solved difference,
                                    NEVER a second added source of grid power

BESS operator/AGC baseline request MW
   -> inverter + timestep energy limit
   -> conventional frequency response (dead-band + power gain)
   -> same inverter + timestep energy limit
   -> optional GFM request (droop + previous-tick ROCOF surrogate)
   -> same inverter + timestep energy limit
   -> ONE delivered storage_MW
   -> battery MWh accounting and the grid equation
```

At any instant in the reduced electrical model:

- `P_grid_supply = P_thermal_actual + max(0, P_RE_available - P_curtail - P_LFSMO) + P_BESS_actual` [MW].
- `P_served = P_demand_gross (1 - UFLS_shed_fraction)` [MW].
- `P_imbalance = P_grid_supply - P_served` [MW].
- `df/dt = P_imbalance / M_eff` [Hz/s], where `M_eff` is the existing illustrative MWs/Hz normalization. **This is a reduced-order toy-grid equation, not a calibrated synchronous-area swing model.**
- Discharge: `E_next = E_now - P_BESS * Δt / (3600 η)` [MWh] for positive delivered MW.
- Charge: `E_next = E_now - P_BESS * Δt η / 3600` [MWh] for negative delivered MW.
- The **maximum delivered MW in this specific tick** is limited by both inverter rating and energy available to reach 0 or full charge without clamping away energy after delivery.

**Priority** when conflicting power requests saturate a BESS inverter: existing base dispatch first, then conventional FCR, then GFM. Individual `BESS_primary_MW` and `gfm_synth_MW` are *delivered increments*. Neither is an additional injection on top of `storage_MW`.

## Operational constraints and negative cases

1. A disconnected GT has zero governor power; turbine dispatch remains isolated by the trip state machine.
2. Fleet mode continues to have **no qualified unit-level governor** in this single-GT solver. The earlier fleet-wide primary MW term has deliberately been removed rather than presented as fuel-backed generation.
3. GT droop changes actual off-design load and resulting fuel/shaft state, not a free `governor_delta_MW` summand. The offset is bounded by GAS_MIN/GAS_MAX and an illustrative setpoint ramp. It does not resolve real actuator dynamics.
4. BESS state-of-charge energy caps apply across arbitrated base/FCR/GFM power, even for a long step with almost empty/full battery.
5. GFM response is calculated from the prior timestep's frequency/ROCOF; it no longer accumulates into an operator BESS request. It remains a simplified sample-response model.
6. UFLS stage logic continues to use instantaneous illustrative thresholds, but reported demand is separated into gross and served demand. LFSM-O renewable power is subtracted in both supply and frequency response.

## Changed tag/interpretation contract

| Tag/state | Meaning after this change |
|---|---|
| `GT1.DISPATCH_PCT` | Base operator/AGC request |
| `GT1.EFFECTIVE_DISPATCH_PCT` | Request including rate-limited governor offset that enters off-design solve |
| `GT1.GOVERNOR_MW` | Change in solved GT electric MW from the same model evaluated without governor offset, **already included in actual GT MW** |
| `GT1.POWER_MW` / `GT1.FUEL_KG_S` | Off-design turbine electrical output and fuel at effective operating point |
| `BESS.REQUEST_MW` | Base operator/AGC request, not total delivered power |
| `BESS.POWER_MW` | **Single** actual BESS inverter injection, includes FCR/GFM |
| `BESS.PRIMARY_MW` | Incremental delivered conventional frequency-response part included in BESS.POWER_MW |
| `BESS.GFM_DELIVERED_MW` | Incremental delivered GFM part included in BESS.POWER_MW |
| `GRID.DEMAND_MW` | Gross load command before UFLS |
| `GRID.SERVED_MW` | Actually served load after UFLS fraction |
| `GRID.UFLS_SHED_MW` | Load removed from demand by UFLS |
| `GRID.SUPPLY_MW` / `GRID.IMBALANCE_MW` | Net actual MW source/sink and difference vs served load |

## Regression scope and evidence boundary

- `test/test_grid_primary_energy.f90`: solved fuel/power governor coupling, no extra frequency MW, real BESS energy debit, charge/discharge near energy limit, repeated GFM no-accumulation, combined inverter ceiling, UFLS/LFSM-O accounting, timestep subdivision and trip exclusions.
- `test/test_grid_dynamics.f90`: existing analytical frequency, UFLS and renewable regulation tests, updated primary-control semantics.
- `test/test_gt_trip_sequence.f90`: GT trip isolation and restart preconditions retained.
- `make check` + cross-platform CI required on the **exact SHA**; code changes alone are not acceptance.

## Scientific and industrial limitations that still apply

**Numerical consistency is NOT experimental validation.** The off-design GT map and control-law constants are representative assumptions. No measured fuel-to-governor transient, rotor speed, generator inertia, GFM converter current control, governor stroke limits, station load-shedding relay settings or plant field responses have been calibrated here. The simplified grid inertia constant `INERTIA_MWs` and its unit labeling need independent dimensional derivation; a physically scaled inertial simulation should derive an energy-conserving network swing equation from rated MVA/inertia and damping, not claim true ENTSO-E performance from this toy-grid.

Other independent coupling questions remain open, including the post-grid-update P2X/tie-line scheduling order, HRSG transient inertia, fleet dispatch measurement semantics and operator/HMI acceptance. Do not describe this patch as complete industrial plant validation.
