# Dimensional grid-frequency model and fixed-loss horizon — issue #49

**Research scope:** numerical verification of a low-order synchronous-area surrogate, **not** verified plant inertia, ENTSO-E compliance, grid islanding protection or measured operating dynamics. Stacked on PR #48 (actual GT/BESS MW and MWh reconciliation).

## 1. What changed mathematically

The former `ROCOF=imbalance_MW / INERTIA_MWs` divided MW by MW·s, which yields 1/s, not Hz/s. The replacement separates stored kinetic energy `E` [MW·s = MJ] and the frequency-equation coefficient `M` [MW·s/Hz]:

```
E_area = H_external * P_external,rated
       + sum(H_unit * P_unit,rated for online rotating units)     [MW*s]
M_area = 2 * E_area / f_nom                                      [MW*s/Hz]
P_static_served = demand_gross * (1 - UFLS_fraction)             [MW]
P_freq_dependent = max(-P_static_served, D * (f - f_nom))        [MW]
P_actual_served = P_static_served + P_freq_dependent             [MW]
P_net = P_actual_generated - P_actual_served                     [MW]
df/dt = P_net / M_area                                           [Hz/s]
f_next = clamp(f + dt * df/dt, f_nom - 3 Hz, f_nom + 3 Hz)        [Hz]
```

All MW are on the same electrical boundary established in PR #48. Positive `P_freq_dependent` is extra demand at overfrequency; negative is less demand at underfrequency. Frequency-sensitive demand is an **explicitly booked load adjustment**, not an unreported term in the ROCOF equation. UFLS shed MW is separate from frequency-dependent consumption.

The `±3 Hz` simulator frequency limiter is not physical; `grid_frequency_clamped` is provided so excursions beyond the model envelope are visible. `grid_model_valid=false` and zero ROCOF prevent invalid inertia, reference frequency or damping from silently progressing the frequency integrator. A failing numerical model is not treated as qualified plant protection.

## 2. Model assumptions (explicit and uncalibrated)

| Term | Assumed nominal value | Basis |
|---|---:|---|
| External synchronous-area inertia constant | `H_external=5.0 s` | Educational connected-area surrogate; external rotating assets are **not** modelled in the dispatch power ledger |
| External area rated-power equivalent | `105 MW` | Produces 525 MW·s external kinetic energy; not a measured system |
| Modelled GT inertia constant | `10/3 s` | 30 MW-rated unit with 100 MW·s kinetic energy |
| Online total kinetic energy | `625 MW·s` | Gives `M=25 MW·s/Hz` at 50 Hz, preserving approximate former numerical frequency scale while correcting units |
| GT tripped kinetic energy | `525 MW·s` | GT rotor disconnected; external assumed connected-area inertia remains |
| Demand damping | `D=0.50 MW/Hz` | Explicit model assumption; negative values rejected |
| Unit-level fleet kinetic energy | `[24,8,70] MW·s` | Existing illustrative inputs retained; only **online** units contribute; remove CC1 -> -70 MW·s |
| Prediction horizon | `5.0 s` | Fixed additional hypothetical generation loss, no controller response |
| Additional hypothetical loss | `10 MW` | Scenario parameter, not a qualified N-1 unit selection |

The external aggregate is an **inertia-bearing background system**, not a new energy source. It remains a model abstraction: there is no explicit voltage, rotor-angle, reactive-power, network fault or external area source model. In a physically isolated system with only one GT, keeping that external inertia would be incorrect. Fleet-unit H, generator MVA and actual H constants require equipment evidence before hardware comparison.

Because GFM is a limited-power inverter response, its synthetic power is already booked by PR #48. **Do not count arbitrary virtual inertia a second time as unlimited stored kinetic energy** in `M_area`.

## 3. Fixed additional-loss horizon minimum (not real nadir)

The old `freq_nadir_Hz` formula had no time horizon and divided mismatched quantities. It was not a true nadir. The field now means a **fixed-additional-loss minimum across a declared horizon**. From the snapshot:

```
P_fixed = P_net_snapshot + P_freq_dependent(snapshot) - P_hypothetical_loss
D > 0:
f(t) = f_nom + (f_now - f_nom)*exp(-D*t/M) +
       (P_fixed/D)*(1 - exp(-D*t/M))
D = 0:
f(t) = f_now + (P_fixed/M)*t
f_min_horizon = min(f_now, f(horizon))
```

This is an exact constant-coefficient analytical solution, independent of the live forward-Euler time integration. Its primary purpose is **verification and illustration**, not a calibrated real plant frequency nadir. It assumes constant inertia and damping, frozen generation dispatch, no dynamic BESS/GT governor response, no UFLS/LFSM-O actuation, and no second fault. A prediction outside the ±3 Hz simulator integration domain remains numerically visible but `nadir_forecast_valid=false`; no invented `47 Hz` floor hides the discrepancy.

Legacy `freq_nadir_Hz` is retained **only for internal ABI compatibility**, and is deliberately published as `GRID.FIXED_STEP_MIN_HZ` plus `GRID.FIXED_STEP_VALID` and `GRID.FIXED_STEP_HORIZON_S`; it must not be marketed as a validated protection threshold.

## 4. Evidence and acceptance

- `test/test_grid_frequency_physics.f90`: independent H·P kinetic-energy arithmetic at 50 and 60 Hz, loss of GT and fleet-unit kinetic energy, damping and UFLS-demand separation, exponential/zero-damping horizon cases, invalid inputs and model failure, numerical timestep convergence to the independently derived closed-form fixed-shortage trajectory.
- `test/test_grid_dynamics.f90` and `test/test_grid_primary_energy.f90`: verify the new dimensional coefficient, actual frequency-sensitive demand and full MW accounting rather than the former mismatched units.
- `scripts/test_grid_energy_replay.py`: independently derives `M=2E/f_nom` and verifies reported ROCOF from recorded MW and inertia, actual served demand, frequency integration, battery MWh and negative/tampered CSV cases. It is run in CI on simulated values from `grid_energy_replay.scn`, not independent turbine field data.
- Existing deterministic scenarios exercise the trip, GFM, UFLS, fleet and governor behavior; exact SHA of successful multi-OS release/debug CI is mandatory before merge.
- Windows GUI build is a **compile test, not an operator mouse/keyboard acceptance test**. Real GUI screen and drill-down verification remain a separate gate.

**Remaining engineering limitations:** no dynamic rotor-speed/shaft equation, controller dead time or plant-matched droop, calibrated H or damping, real grid measurements, angular stability, AVR, converter current-loop dynamics, measured turbine first-out trip logic or validated steady-state thermal/rotor coupling. A conservation audit and analytic proof establish correct mathematics for assumptions, not physical correctness of assumed parameters.

**Issue ownership:** [#49](https://github.com/abhijith-sivaprasadan/thermotwin/issues/49). PR #48 energy accounting must be accepted separately; this patch is stacked on it.
