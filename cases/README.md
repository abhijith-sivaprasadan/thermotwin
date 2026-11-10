# Input Cases

This directory holds the CSV input files. Each row is one operating point of one
(optionally degraded) machine. Comment lines beginning with `#` or `!` and blank
lines are ignored. The first non-comment line is the header; every following
non-comment line is a data row.

## Column order (fixed)

The reader parses **by position** and validates the header, so all 18 columns must appear with these names in this exact order:

| # | Column | Unit | Notes |
|---|---|---|---|
| 1 | `case_name` | – | required unquoted label, at most 64 characters; no commas |
| 2 | `ambient_T_K` | K | ambient/inlet temperature |
| 3 | `ambient_P_Pa` | Pa | ambient pressure |
| 4 | `relative_humidity` | – | 0–1 (carried, not yet applied to properties) |
| 5 | `inlet_pressure_loss` | – | fractional inlet/filter ΔP |
| 6 | `mdot_air_kg_s` | kg/s | air mass flow |
| 7 | `pressure_ratio` | – | compressor total pressure ratio |
| 8 | `eta_compressor` | – | compressor isentropic efficiency |
| 9 | `T_turbine_inlet_K` | K | firing temperature (TIT) |
| 10 | `eta_combustor` | – | combustion efficiency |
| 11 | `combustor_pressure_loss` | – | fractional combustor ΔP |
| 12 | `LHV_J_kg` | J/kg | fuel lower heating value |
| 13 | `eta_turbine` | – | turbine isentropic efficiency |
| 14 | `exhaust_pressure_loss` | – | fractional exhaust/diffuser back-pressure |
| 15 | `eta_mechanical` | – | mechanical (bearing/windage) efficiency |
| 16 | `eta_generator` | – | generator electrical efficiency |
| 17 | `auxiliary_load_fraction` | – | fraction of gross power for auxiliaries |
| 18 | `degradation_mode` | – | required unquoted label, at most 32 characters (e.g. `clean`); presets live in code |

## Files

| File | Purpose | Used by mode |
|---|---|---|
| `design_point.csv` | single reference operating point | `run` |
| `ambient_sweep.csv` | ambient temperature −20 °C → +45 °C | `run` |
| `pressure_ratio_sweep.csv` | pressure ratio 6 → 30 | `run` |
| `TIT_sweep.csv` | firing temperature 1200 → 1600 K | `run` |
| `efficiency_sweep.csv` | turbine efficiency 0.80 → 0.92 | `run` |
| `degradation_cases.csv` | baseline machine (row 1) | `degradation` |
| `transient_baseline.csv` | baseline machine (row 1) | `transient` |
| `uncertainty_baseline.csv` | baseline machine (row 1) | `uncertainty` |
| `diagnostics_baseline.csv` | baseline machine (row 1) | `diagnostics` |

The `run` mode evaluates **every** row of its input file — a single design point
and a 30-row sweep are handled identically. The scenario modes
(`degradation`, `transient`, `uncertainty`, `diagnostics`) take the **first row**
of their file as the baseline machine and generate their own scenarios from it.

## Adding your own case

Copy `design_point.csv`, keep the header, and add rows. For a custom sweep,
generate rows however you like (a spreadsheet or a few lines of Python) as long
as the 18-column order is preserved, then run:

```bash
./thermotwin run cases/my_cases.csv output/results_my_cases.csv
```

Numeric cells are required and must be finite. Use a decimal point and optional `e`/`E`/`d`/`D` exponents; blank cells, NaN, infinity, extra columns, and quoted CSV fields are rejected. Whitespace around cells is allowed. Column order cannot be inferred from a spreadsheet export. `degradation_mode` is a label in `run`; it does not apply a degradation preset automatically.

## Scripted scenarios

`scenarios/*.scn` drive the live plant/grid engine, which uses temperature-dependent properties. They are separate from the analysis-mode baseline CSVs.

```text
name     load_change
duration 5
dt       0.25
at 0.0   set auto_balance 1
at 1.0   set demand_MW 40
at 4.0   assert_above gas_capacity_MW 5
at 5.0   assert_near demand_MW 40 0.001
```

```bash
./thermotwin scenario run cases/scenarios/load_step.scn --record output/load_step.csv
```

- `#` starts an inline comment. Blank lines and tabs are accepted; an optional `end` terminates the file.
- `name` is one token. `duration` is positive seconds; `dt` defaults to 0.25 s and must exceed 1e-6 s. The parser caps the run at 10 million ticks.
- At most 96 events are accepted. Event times and values must be finite; times must be nonnegative and within the run, and assertion tolerances must be nonnegative. Extra tokens are rejected.
- `set <field> <value>` and `command <name>` run at the start of the first tick whose start time reaches the event. Inputs must be reachable before the last tick. Boolean controls use numeric 0/1.
- `assert_near <field> <value> <absolute tolerance>`, `assert_above <field> <value>` and `assert_below <field> <value>` evaluate after the tick reaching the event. The inequality checks are strict. The final tick may extend beyond `duration` when it is not divisible by `dt`.
- Failed assertions, unknown controls/commands and failed recorder creation return nonzero status. A scenario with no assertions is a playback, not verification evidence.
- The recorder writes one row per tick with unit-bearing column names. It records a selected engineering signal set, not every internal `GridState` field.

Use bundled scenarios as examples of supported controls. The authoritative names are the `set_state_field`, `run_command` and `get_state_value` dispatch tables in [`src/engine/scenario_runner.f90`](../src/engine/scenario_runner.f90). Scenario spelling is case-sensitive.
