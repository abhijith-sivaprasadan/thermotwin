# Input Cases

This directory holds the CSV input files. Each row is one operating point of one
(optionally degraded) machine. Comment lines beginning with `#` or `!` and blank
lines are ignored. The first non-comment line is the header; every following
non-comment line is a data row.

## Column order (fixed)

The reader parses **by position** and checks the exact header. Every data row
must contain exactly 18 fields, with all numeric fields finite and nonempty;
missing values and altered column order cause a nonzero error exit rather
than being interpreted as zero or a different physical input. Fields are
plain unquoted CSV tokens (quoted CSV fields are not implemented). The
18 columns must appear in this exact order:

| # | Column | Unit | Notes |
|---|---|---|---|
| 1 | `case_name` | – | free text label |
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
| 18 | `degradation_mode` | – | label only (e.g. `clean`); presets live in code |

## Files

| File | Purpose | Used by mode |
|---|---|---|
| `design_point.csv` | legacy design operating point with modelled inlet/exhaust losses; **not** the ISO flange reference | `run` |
| `site_iso_flange_reference.csv` | fixed educational machine at ISO flange reference with zero inlet/exhaust boundary losses | `site` |
| `site_sweep.csv` | 26 equation-based regression scenarios around the ISO flange reference (not empirical measurements) | `site` |
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
