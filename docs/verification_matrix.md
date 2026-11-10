# Verification matrix

Numerical/software oracles are distinct from external engine validation or industrial acceptance limits. Run the current suite to establish the state of your checkout; bundled result files are examples.

## Current checks

| Quantity or behavior | Oracle | Tolerance/check | Evidence |
|---|---|---|---|
| Constant-property compressor outlet | Hand reference 679.5 K | 3 K | `test/test_cycle_solver.f90` |
| Constant-property net power | Hand reference 30.4 MW, inlet/exhaust losses removed | 1.5 MW | `test/test_cycle_solver.f90`, CLI `selftest` |
| Constant-property efficiency | Hand reference 0.312 | 0.010 | `test/test_cycle_solver.f90` |
| Heat rate | 3600 / efficiency | 1e-3 kJ/kWh | `test/test_cycle_solver.f90` |
| First-law closure | Air sensible energy + fuel chemical input versus exhaust + electrical output + combustor/shaft/generator/auxiliary losses | Relative residual below 1e-6; constant properties | `test/test_cycle_solver.f90` |
| Lumped transient | Analytic exponential, tau = C/(hA+UA) | Max error below 1e-4 K over 100 s, RK4 at 1 s | `test/test_transient_thermal.f90` |
| Inverse degradation | Noise-free synthetic parameter truth | 0.004 per parameter; objective below 1e-4 | `test/test_diagnostics.f90` |
| Seeded noise | Reseed and replay in the same runtime | Exact repeated sequence | `test/test_sensor_model.f90` |
| Noise mean/sigma | Mean 50, sigma 2 | 0.1 each | `test/test_sensor_model.f90` |
| Off-design full load | Recovery of direct cycle with the same property model | 0.01 MW; separate 32.2876 MW software reference ±0.05 MW | `test/test_off_design.f90` |
| Combined cycle | GT + steam accounting, pinch/stack limits and software efficiency reference | Power sum within 1e-9 MW; efficiency 0.5012 ±0.001 | `test/test_combined_cycle.f90` |
| Plant/grid scenarios | Event timing and explicit physical/behavioral assertions | Defined in 15 bundled `.scn` files | `make scenarios` |
| Input/output contract | Valid batches/recordings; malformed or non-finite input, unknown actions and unwritable outputs | Exit status, schema and row checks | `scripts/check_cli.py` |
| Runner and cleanup | Incomplete builds, executable selection, process/timeout failure, cleanup boundary | Python unit tests | `scripts/test_*.py` |

The remaining Fortran programs cover components, degradation, processes, controls, dispatch, reconciliation, exergy/UQ, limits and surrogate behavior. Discovery is automatic; the runner requires a binary for every `test/test_*.f90` source.

## Run the checks

```bash
make check scenarios
make PROFILE=debug check scenarios
make BUILD=build/review check scenarios
```

On Windows, GNU Make may be named `mingw32-make`. A custom `BUILD` now places both the CLI and tests in that directory. `make check` forwards the selected `BUILD` and `EXE` to the runner; no second output override is required. To test an explicitly named executable:

```bash
python scripts/run_tests.py --build-dir build/review --exe build/review/thermotwin
```

Append `.exe` on Windows. Use `python3` where needed. `make pipeline` verifies the analysis/report path using optional `requirements.txt` dependencies.

## September 2026 baseline reconciliation

The existing working-tree property correction derives hot-gas molecular mass from its species fractions rather than an unrelated hard-coded mass. This changes variable-property heat capacities, gas constant, GT capacity, fuel input and downstream combined-cycle/grid results. Constant-property hand references remain separate.

The previous full-load 28-32 MW and combined-cycle 52-56% bounds were stale and described a synthetic efficiency band as validation. Current tests retain full-load recovery, power accounting, pinch, stack-temperature, part-load and monotonicity checks alongside explicitly labeled regression snapshots:

| Scenario quantity | Current software reference | Absolute tolerance |
|---|---:|---:|
| Combined-cycle efficiency at 1 s | 0.5012 | 0.001 |
| Combined-cycle efficiency at 28 s | 0.4759 | 0.001 |
| Fleet CO2 intensity, 15% H2, at 15 s | 386.4652 g/kWh | 1 g/kWh |
| Fleet CO2 intensity, NG, at 22 s | 395.0255 g/kWh | 1 g/kWh |
| Load-step dispatch at 40 s | 84.4101% | 1 percentage point |

The UFLS stress fixture now requests 100 MW instead of 80 MW. With corrected capacity, the old disturbance allowed frequency recovery and relay reset before the purported latching assertion. The larger sustained deficit exercises the intended latch and later recovery; the relay model and assertions were retained.

These snapshots detect future changes; they are not independently derived physical accuracy bounds. Review model changes against independent or conservation-based checks before updating them again.

## Audit evidence and limits

Local verification on Windows with GNU Fortran 13.2.0 and Python 3.10 completed release and debug builds: 28 Fortran test programs plus the CLI physics selftest, all 15 scenarios, 44 CLI regression cases and 8 Python workflow tests. The offline native GUI linked successfully. The analysis pipeline generated CSVs, six figures, PDF and manifest; report layout was visually checked. This describes a local audit, not a claim that remote CI or every GUI interaction ran.

- Reference path: GNU Make, the CLI and the automated verification commands above.
- Experimental: grid, market, forecasting, AI/surrogate, P2X and advanced control models. Passing regression does not establish operational suitability.
- Optional Windows HMI: compilation is checked separately from interactive behavior. No end-to-end OPC UA server acceptance is claimed.
- FPM: retained for development; build/test parity remains unverified.
- Neural weights: historical synthetic training output, not measured plant data. Dataset/weight provenance and reproducible-training checks remain open release work.
- Water/steam correlations with `if97_*` names are not a complete IAPWS-IF97 property implementation.

Do not describe ThermoTwin-F as a validated industrial digital twin.
