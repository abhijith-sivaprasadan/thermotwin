# Core verification matrix

Numerical/software oracles, not external engine validation or industrial acceptance limits.

| Quantity | Oracle | Absolute tolerance/check | Test |
|---|---|---|---|
| Compressor outlet | Hand reference, 679.5 K | 3 K | `test/test_cycle_solver.f90` |
| Net power | Hand reference, 30.4 MW | 1.5 MW | `test/test_cycle_solver.f90` |
| Efficiency | Hand reference, 0.312 | 0.010 | `test/test_cycle_solver.f90` |
| Heat rate | 3600 / efficiency | 1e-3 kJ/kWh | `test/test_cycle_solver.f90` |
| Net power plus exhaust | Energy accounting bound | 60–100% of fuel input; not a closed conservation residual | `test/test_cycle_solver.f90` |
| Lumped transient | T_inf + (T_initial - T_inf) exp(-t/tau), tau = C/(hA+UA) | Max trajectory error < 1e-4 K over 100 s, RK4 at 1 s | `test/test_transient_thermal.f90` |
| Inverse degradation | Noise-free synthetic parameter truth | 0.004 per parameter; objective < 1e-4 | `test/test_diagnostics.f90` |
| Seeded noise | Reseed and replay in same runtime | Exact repeated sequence | `test/test_sensor_model.f90` |
| Noise mean/sigma | Configured mean 50, sigma 2 | 0.1 each | `test/test_sensor_model.f90` |

Run `make check`. For an isolated directory, override both output variables:

```sh
make BUILD=build/review EXE=build/review/thermotwin all tests
python scripts/run_tests.py --build-dir build/review
```

Setting only `BUILD` leaves the CLI at the repository root; the runner needs it
inside the selected build directory for its physics selftest.

## Capability boundary

- Reference core: Make-built CLI and thermodynamic/sensor/transient/inverse tests.
- Experimental: grid, market, surrogate, P2X and advanced control scenarios. Passing
  regression cases does not establish operational suitability or external validation.
- Optional Windows GUI: separate integration; core CI does not certify interactive
  behaviour or OPC UA integration.
- FPM: retained for development; no verified build/test parity claim.
- Neural weights: historical training output is not validated plant data. Full
  dataset/weight hashing and reproducible-training checks remain release gates.

Do not describe this as a validated industrial digital twin.
