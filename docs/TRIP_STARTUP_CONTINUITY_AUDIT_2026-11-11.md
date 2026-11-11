# Simulator internal correctness audit — tranche A (2026-11-11)

**Base:** PR #45 (`e357d77e`). **Audit scope:** static source review and new regression coverage on a stacked draft branch. CI and manual acceptance must be checked against this branch's final SHA. **No field/OEM validation is claimed.**

## Immediate corrections in this branch

| Invariant / operator expectation | Prior gap | New guard or regression |
|---|---|---|
| A simulated start cannot continue after a required restart permissive is lost | Reset/start masks were checked at button press only; disabling TRAIN BYPASS or introducing a standing alarm during PURGE/IGNITION/ACCEL/SYNC did not necessarily inhibit a later breaker closure | Recheck the non-phase bits of the restart mask on every start advance, including the final synchronization tick. Abort to a new latched TRIPPED event, record its specific training cause where available, open breaker and shut simulated fuel |
| A cached training-source flag must not be mistaken for live instrumentation | A previous EQ_SRC_TRAINING label could remain trusted after its underlying sample went stale between monitor updates | Required TRAIN samples must be present, finite, nonnegative, within the defined 5 s freshness window, and actually labeled TRAIN; unless the explicit educational bypass is enabled |
| Operator recommendations must respect equipment state | The advisory's cache key and normal text omitted turbine phase, so it could say “STATUS OK” while the GT was isolated and advise increasing GT dispatch | Include GT phase in advisory cache, prepend SIM GT OFFLINE state information and avoid GT-dispatch advice during trip |
| Preserve fuel reference through aborts | Aborting a partially-fuelled simulated start could overwrite the original online fuel reference used for later educational restarts | Update pretrip fuel reference only on an ONLINE → TRIPPED transition |

The new interlock behavior is **deliberately educational**. The code still assumes purge, ignition, acceleration, oil service, rotation and synchronisation rather than measuring or validating them. Any bypass is **not** a turbine operation procedure.

## Unresolved high-priority physical consistency findings

### P0 — Grid primary power is not reconciled with the physical energy ledger

- `src/engine/grid_dynamics.f90` adds `governor_delta_MW` and `BESS_primary_MW` to `P_gen_eff` in the swing-frequency equation.
- `src/engine/engine_core.f90` obtains the reported `supply_MW` from thermal generation, renewable injection and `storage_MW`, **without** those two primary-response contributions.
- `update_battery_soc` debits/credits only `storage_MW`, not `BESS_primary_MW`. Therefore an additional primary response can change simulated frequency without corresponding battery energy change; the extra governor term is also not consistently represented in fuel/shaft generation.
- There is a risk of double-counting or exceeding the storage inverter limit when `storage_MW` and `BESS_primary_MW` are considered independently. A corrected model needs **one authoritative actual delivered BESS power**, an explicit governor mechanical-power response tied to GT limits/fuel/energy, timestep-aligned bookkeeping, and a reconciled grid/economics/historian boundary.
- The grid model is a **reduced-order educational response**, not an energy-conserving dynamic plant simulator in this respect. Do not cite its primary-control frequency traces as validated hardware response.

### P1 — The displayed N-1 “nadir predictor” is an illustrative heuristic, not a forecast validated by dynamic integration

In `engine_core.f90`, `freq_nadir_Hz` is calculated from an algebraic term proportional to `trip_MW * f0 / (2 * H * P_load)` without a time horizon. This resembles an initial inertial rate expression, **not** a proven nadir, and its `H` reference changes with simulated `gas_capacity_MW` (which is set to zero by a trip). It must be renamed/rederived, or calibrated against the actual integrated frequency trajectory with explicit assumptions, before being presented as a physically credible nadir.

### P1 — Other coupling questions still open

Verify engine stepping order around the trip instant, GFM response integration after frequency update, residual HRSG heat-to-steam conversion during rundown, emissions during synthetic start, and whether model/equipment alarms supply defensible operator response instructions. New algebraic tests alone do not establish OEM map, steam transient, valve, sensor or grid behavior.

## Operator trust rules

- **Equation checked:** mass, energy, units and algebraic identities reproduce implementation assumptions.
- **Software tested:** a command or state transition has passing deterministic regressions and target-platform builds.
- **Model assumption:** numerical behavior follows an explicitly defined simplified surrogate, not measured machinery.
- **Physically validated:** same equipment, matched time, boundary conditions and independent measurements with uncertainty and residual analysis. **This level is not achieved for ThermoTwin-F's GT trip/restart or grid dynamic controls.**

## Required acceptance before downstream HMI Step 3

1. Verify PR #43 → #44 → #45 dependency chain; do not merge this audit branch independently.
2. Obtain a green `make check` on the exact audit commit across Linux, macOS and Windows; inspect failures and warnings rather than inferring success from a green badge on a different commit.
3. On Windows, demonstrate loss-of-permissive during PURGE and just before SYNC, first-out, latched isolation, and the F7/ advisory screen under real mouse use.
4. Resolve the P0 energy-coupling defect using a single source-of-truth MW balance, inverter-power and SOC invariants, mechanical governor limits and traceable time integration.
5. Cross-compare a defined sequence (e.g. a 5 MW generation loss) with an independent reduced-order reference model; preserve fixed seeds/parameters, initial state, simulation dt, comparison metrics, and negative tests.

**Do not report** industrial correctness, certified restart protection, field accuracy or source-independent validation from any of these checks.
