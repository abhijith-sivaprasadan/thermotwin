# ThermoTwin-F — Revamp 7.0 Roadmap  (Pure Physics & Scientific Analysis)

> Status: **Launched** 2026-06-15 · Scope: **engine-deep** (physics + analysis + interpretation) ·
> Flagship: **all four** (exergy · fidelity · UQ · diagrams) · Rigor: **full research pipeline**

7.0 turns the digital twin from a credible simulator into a **research-grade thermodynamic
analysis instrument**. Where 5.0 added capability and 6.0 added polish, 7.0 adds *scientific
substance*: reference-grade physics, publishable analysis (exergy, uncertainty, sensitivity,
V&V), and interpretation that makes the science legible. This is the KTH-PhD centrepiece — it
demonstrates not just that the plant is simulated, but that it is *understood*.

Builds on the existing engine: `cycle_solver`, `fluid_properties`, `compressor`, `combustor`,
`turbine`, `hrsg`, `steam_cycle`, `uncertainty_analysis`, `sensitivity_driver`,
`model_validation`, `physics_fidelity`. New analysis screens are reachable via the 6.0 command
palette / nav rail, so we are not bound by the 15 F-key slots.

## Workstreams
- **A · Pure physics (fidelity).** Reference-grade thermophysical properties + component models.
- **B · Scientific analysis (methods).** Exergy/second-law, uncertainty quantification, global
  sensitivity, data reconciliation, verification & validation.
- **C · Interpretation (legibility).** Annotated thermodynamic diagrams, exergy Sankey, theoretical-
  limit benchmarking, causal interpretation, and publishable scientific reporting.

## Principles
1. **Conservation first** — every model closes mass / energy / exergy balances to a stated tolerance.
2. **Reference-grade** — IAPWS-IF97, NASA-9 polynomials, ε-NTU; the formulation is named and cited.
3. **Quantified uncertainty** — every reported number carries an error bar and its provenance.
4. **Falsifiable** — V&V residuals against reference data; assumptions stated explicitly.
5. **Legible** — every result has a diagram and a one-line physical interpretation.

## Phase plan (sequenced; each closes a balance + ships a test + a capture)

| Phase | Scope | Workstream |
|-------|-------|------------|
| **7.0-P1** | **Exergy & second-law engine + Grassmann diagram** — new `exergy` module: physical + chemical flow exergy per station, exergy destruction & rational (2nd-law) efficiency per component; new **Exergy Analysis** screen with a live Grassmann/Sankey + destruction waterfall | B (flagship 1) |
| **7.0-P2** | **Thermophysical fidelity** — IAPWS-IF97 water/steam for `steam_cycle`; NASA-9 real-gas combustion-product properties in `fluid_properties`/`cycle_solver`; ε-NTU multi-pressure HRSG with pinch/approach | A (flagship 2) |
| **7.0-P3** | **Combustion chemistry & component physics** — adiabatic flame temperature, Zeldovich thermal NOx + CO, H₂ co-firing (Wobbe, flame-temp shift, flashback margin); turbine cooling-air accounting, tip-clearance, polytropic-loss breakdown | A |
| **7.0-P4** | **Uncertainty quantification & sensitivity** — Monte-Carlo propagation of sensor/parameter uncertainty → error bars on every KPI; Sobol global sensitivity + tornado charts; new **UQ & Sensitivity** screen | B (flagship 3) |
| **7.0-P5** | **Data reconciliation & V&V** — constrained reconciliation of sensors against mass/energy balances, redundancy + gross-error detection, conservation-closure metrics, formal validation residuals (extends `model_validation`) | B |
| **7.0-P6** | **Thermodynamic diagram suite & interpretation** — annotated T-s (Brayton), h-s Mollier (steam), T-Q (have), exergy diagrams; theoretical-limit overlays (Carnot / ideal Brayton-Rankine / Curzon-Ahlborn); causal "why" interpretation of performance gaps | C (flagship 4) |
| **7.0-P7** | **Scientific reporting** — publishable report: derivations, assumptions, exergy tables, UQ error bars, V&V metrics, and diagrams (extends D3 / `generate_report.py`) | C |

## Verification
Each phase must: (1) close its governing balance to tolerance with an in-engine check, (2) add a
unit test to `make check` validated against a textbook/reference point (cited), and (3) ship a live
2560×1600 capture of the new analysis surface.

## Changelog
- **2026-06-15** — Roadmap created. Flagship = all four (exergy / fidelity / UQ / diagrams),
  rigor = full research pipeline. Sequencing leads with the exergy/second-law engine because it is
  the signature analysis and computes from states the `cycle_solver` already produces.
- **2026-06-15** — **7.0-P1 engine + test done (verified).** New `src/engine/exergy.f90`
  (`compute_exergy`) computes the component availability balance — physical flow exergy per gas
  station + fuel chemical exergy → exergy destruction (compressor / combustor / turbine / HRSG-
  bottoming) + stack/condenser losses + rational η_II + a balance-closure residual (V&V). Added to
  the Makefile (`MODS` + dependency rule). `test/test_exergy.f90` checks, for combined- and simple-
  cycle points, that the balance closes (<2%), the **combustor dominates the destruction**,
  destructions are non-negative, and η_II is physical → `make check` **22 passed / 0 failed**.
  **Remaining P1:** the Exergy Analysis GUI screen (live Grassmann/Sankey + destruction waterfall),
  reachable via the 6.0 command palette. Then P2 (IAPWS-IF97 + NASA-9 + ε-NTU) onward.
- **2026-06-15** — **7.0-P1 GUI done.** Added **L3 Exergy Analysis** as screen 16, reachable through
  the nav rail/tabs and `Ctrl-K` command palette. The screen renders live fuel-exergy, useful-work,
  η_II, destruction, external-loss, and balance-closure KPIs; a Grassmann-style availability flow;
  component destruction waterfall; and a physical interpretation/V&V closure panel. Active-screen
  CSV export now includes the exergy table and dominant irreversibility. **Remaining:** P2+
  thermophysical fidelity and deeper methods screens.
- **2026-06-15** — **7.0-P2 thermophysical fidelity done (verified).** Replaced the live engine's
  teaching-property shortcuts with NASA-polynomial gas cp/enthalpy, IF97-style saturation/
  enthalpy/entropy helpers for water/steam, enthalpy-consistent compressor/combustor/turbine work,
  and an epsilon-NTU HP + LP/economizer HRSG. The calibrated CCGT design point now lands at
  **45.5 MW**, **15.2 MW** steam bottoming power, **52.8%** plant efficiency, **15 K** pinch, and a
  **379 K** stack temperature. Added `test/test_thermo_fidelity.f90`; `make check` reports
  **23 passed / 0 failed**, and all shipped scenario playbacks pass with thresholds aligned to the
  new physics.
- **2026-06-15** — **7.0-P3 combustion/component physics implemented.** Added
  `src/engine/combustion_physics.f90` for H2 blend mass/LHV/CO2/Wobbe, adiabatic flame-temperature
  shift, simplified Zeldovich thermal NOx, low-load CO slip, flashback margin, turbine cooling-air
  demand, tip-clearance loss, and compressor/turbine polytropic-loss breakdown. `refresh_model`
  now publishes those diagnostics into `GridState`, the tag bus, scenario assert targets, the flight
  recorder, F5 emissions KPIs, F12 Carbon/Sustainability, and CSV exports. Added
  `test/test_combustion_physics.f90` to verify H2 raises flame temperature/NOx, lowers CO2 factor,
  tightens flashback margin, raises Wobbe deviation, and that engine-state wiring is live.
- **2026-06-15** — **7.0-P4 (UQ engine + test) done.** New self-contained
  `src/engine/exergy_uq.f90` (`run_exergy_uq`) Monte-Carlo-propagates 1-sigma input uncertainty
  (ambient, TIT, exhaust, fuel flow, pressure ratio) through the exergy accounting → mean ± std and
  a 95% interval on rational efficiency and on combustor/total exergy destruction (deterministic
  seed, Box-Muller normals). This puts defensible error bars on the headline second-law numbers.
  `test/test_exergy_uq.f90` checks zero-sigma collapse, spread under realistic sigmas, 95%-interval
  bracketing, and low Monte-Carlo bias → `make check` **25 passed / 0 failed**. Built on P1's
  `compute_exergy`, so it sits clear of the parallel P2/P3 physics. **Remaining P4:** surface the
  UQ readout on the Exergy screen (η_II ± CI) and add a Sobol global-sensitivity / tornado view.
- **2026-06-15** — **7.0 P4–P7 analysis layer done (engine + tests).** Four new self-contained
  modules, all verified — `make check` now **29 passed / 0 failed**:
  - `exergy_sobol` (P4) — Saltelli sampling + Jansen estimators for first-order & total-effect
    Sobol indices of η_II / total destruction, with the dominant input identified (test: fuel flow
    correctly isolated as the sole driver of η_II).
  - `thermo_limits` (P6) — Carnot, Curzon-Ahlborn, ideal-Brayton limits + fraction-of-Carnot
    (test: thermodynamic ordering; actual sits below the Carnot ceiling).
  - `data_reconciliation` (P5) — single-constraint weighted-least-squares reconciliation +
    chi-square(1) gross-error detection on the plant power balance (test: balance closes exactly;
    a faulty sensor is flagged).
  - `scientific_report` (P7) — aggregates exergy + UQ + Sobol + limits + reconciliation into one
    report written to any unit (test: full pipeline runs, multi-section output).
  All build on P1's `compute_exergy`; zero overlap with the parallel P2/P3 physics. **Remaining is
  GUI surfacing (user's domain):** UQ error bars + Sobol tornado on the Exergy / a UQ&Sensitivity
  screen, theoretical-limit overlays on the thermo diagrams, and embedding `write_scientific_report`
  in the CSV/PDF export.
- **2026-06-15** — **7.0 P4-P7 GUI/report wiring done (verified live).** (1) The CSV/report export
  now embeds a full `[SCIENTIFIC_ANALYSIS]` section via `write_scientific_report` — exergy balance,
  Monte-Carlo UQ (η_II ± CI), Sobol sensitivity, theoretical limits, and reconciliation V&V.
  Verified on the running app: exported `shift_data_t27.csv` shows η_II 0.500, combustor-dominated
  destruction, closure −0.0000, η_II = 0.502 ± 0.027 (95% CI 0.450–0.554), fuel flow as the sole
  Sobol driver. (2) The Exergy screen gained an analysis line — η_II ± 95% CI (UQ), Carnot % and
  fraction-achieved (limits, computed every frame, cheap), and the dominant sensitivity input —
  with the Monte-Carlo UQ/Sobol **drift-cached** (recomputed only when fuel/TIT move) so it never
  runs per frame. `make gui` clean. **Remaining (optional polish):** theoretical-limit reference
  lines drawn directly on the F3/F4 T-s / T-Q diagrams, and a full Sobol tornado chart (vs the
  current one-line summary).
- **2026-06-15** — **7.0 final polish done.** (1) **Carnot envelope** overlay on the F3 Brayton
  T-s diagram — an amber isotherm rectangle between TIT (T3) and ambient (T1) over the heat-addition
  entropy span, i.e. the theoretical-limit box the real cycle sits inside (verified on F3:
  ambient 284 K floor, TIT ceiling, cycle nested within). (2) **Sobol tornado** on the Exergy
  screen — total-effect ST bars per input with the dominant driver highlighted, drawn from the
  drift-cached Sobol result (replaces the one-line summary). `make gui` clean. Note: the T-Q ideal
  limit is degenerate (zero-pinch), so the limit overlay lives on the T-s where it's meaningful.
  **Revamp 7.0 complete** — P1-P7 engine + tests (29 green) + full GUI/report surfacing.
