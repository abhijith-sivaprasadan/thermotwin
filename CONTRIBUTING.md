# Contributing to ThermoTwin-F

Contributions should improve a reproducible engineering workflow: a clear input, a stated assumption, an observable result, and evidence that the change works.

## Local workflow

1. Read the [README](README.md), [engineering guide](docs/ENGINEERING_GUIDE.md), and [verification matrix](docs/verification_matrix.md).
2. Make a focused change. Document changes to units, CSV schemas, scenario timing, or model defaults.
3. Run `make check scenarios`. For numerical or state changes, also run `make PROFILE=debug check scenarios`.
4. For report changes, install `requirements.txt`, run `make pipeline`, and inspect the figures and PDF. For HMI changes, build `make gui` on Windows and exercise the affected screens, resizing, navigation, and exports.
5. Include the command, compiler/runtime versions, results, and limitations in the pull request.

Use `mingw32-make` if that is your GNU Make executable on Windows. `make BUILD=build/review check scenarios` creates an isolated build. Use another build directory when changing compilers or custom flags.

## Numerical changes

Tests should check a physical invariant, an independent calculation, or an explicitly named regression baseline. Explain tolerances. When the model changes, record affected baselines and the reason in the verification matrix; do not widen thresholds merely to obtain a pass. An internally generated synthetic reference is not hardware validation.

Add a regression for changed numerical or failure behavior. The test runner discovers `test/test_*.f90` and refuses an incomplete suite. New modules must be added to `MODS` and their `use` dependencies to the Makefile. Update examples and documentation in the same change.

## Repository conventions

- Fortran 2008, explicit interfaces, `implicit none`, named precision kinds, and unit-bearing variable names.
- Python 3.10+ for portable workflows; avoid platform-specific shell commands in core Make targets.
- Keep module and file names consistent. Shared assertions live in `test/test_assert.inc`.
- Keep generated runs under `build/` or `output/`; do not commit binaries, DLLs, local settings or private plant data.
- `requirements.txt` lists optional reporting dependencies. Record the actual environment when publishing results.
- Follow `.editorconfig`; shell scripts use LF line endings.

## Reporting a problem

Provide the Git revision, dirty state, operating system, `gfortran --version`, Python version, exact command, smallest reproducing CSV/scenario, and expected/actual behavior. Include failure output and `run_manifest.json` where available. Remove credentials and proprietary plant data before sharing.

For private vulnerability reports, follow [SECURITY.md](SECURITY.md).
