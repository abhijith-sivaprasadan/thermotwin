# ThermoTwin-F — Revamp 5.0 Roadmap

> Status: **Launched** 2026-06-14 · Owner: HMI/engine · Target: portfolio-grade digital-twin console
>
> Revamp 5.0 is a major version that advances the console on **all four fronts** at once:
> visual/UX, a new flagship landing screen, deeper engineering/ML, and interactivity/reporting.
> Each workstream ships in independent, verifiable increments so the app stays runnable throughout.

## Why now

The 4.x line reached functional completeness — 15 screens, combined-cycle + fleet dispatch,
day-ahead MINLP, DNN surrogate, anomaly/fault ML, P2X/CCS/GFM/tie-line/MPC subsystems,
H₂ co-firing, and a scenario engine with a regression test suite. A full-resolution
(2560×1600) visual audit confirmed the **layout is sound**, but the shell is dense, the header
is cluttered (latent overlap between transient badges and subsystem pills), and there is no
single "executive" view that ties the subsystems together. 5.0 turns a feature-complete
simulator into a polished, demonstrable product.

## Design principles

1. **8-px spacing grid.** All gaps, paddings, and offsets snap to multiples of 4/8 px.
2. **Typographic hierarchy.** Title → section → label → value, with consistent sizes/weights.
3. **Semantic color tokens.** Status (green/amber/red) reserved for state; accents (blue/cyan/
   lime) for data series; ink/muted/dim for text. No ad-hoc colors.
4. **One job per region.** Every panel answers one question; no region does double duty.
5. **Runnable at every commit.** No big-bang rewrite; each phase is independently shippable.

---

## Workstream A — Visual & UX modernization

Establishes the design foundation the other workstreams build on.

- **A1 · Shell & header redesign** *(first increment)* — restructure the 2-band header into a
  clean status bar; fix the transient-badge / subsystem-pill overlap; legible, vertically
  centered indicator chips; consistent left accent + status colors.
- **A2 · Design-token layer** — promote spacing/typography/elevation into named constants
  (`PAD_*`, `GAP_*`, font roles) used everywhere; retire magic numbers.
- **A3 · Component pass** — unify cards, section titles, bars, tables, and KPI tiles into a
  consistent set of primitives with shared padding/border/elevation.
- **A4 · Density & whitespace** — rebalance sparse screens (F7 alarms, F10 fleet) and dense
  ones (F8 diag, F15 scenario); align columns to the grid.

## Workstream B — Flagship landing screen

A new **F1 "Plant Health & Economics" executive view** (current F1 becomes the detailed
overview, shifted to a new slot):

- **B1** — single-line animated plant schematic as the hero (reuse the P&ID flow engine),
  with live power/heat/CO₂ flows.
- **B2** — at-a-glance health ring + top-3 KPIs (margin $/h, CO₂ g/kWh, reserve margin) and
  the live advisory headline.
- **B3** — subsystem status strip (the 6 modules) as first-class tiles, not header pills.

## Workstream C — Engineering / model depth

- **C1** — model validation harness: compare cycle solver + DNN surrogate against a reference
  dataset; surface MAE/bias on F11.
- **C2** — one new advanced capability (candidate: economic MPC horizon visualization, or a
  unit-commitment what-if comparator on F10).
- **C3** — physics fidelity: revisit HRSG pinch + part-load heat-rate curves against published
  GT performance maps.

## Workstream D — Interactivity & reporting

- **D1** — clickable KPI tiles → faceplate drill-downs (extend the existing faceplate popup to
  all screens).
- **D2** — scenario comparison: run two scenarios, overlay the trends.
- **D3** — richer reporting: branded PDF/CSV export with the active screen's data + advisory.

---

## Phase plan (sequenced)

| Phase | Scope | Exit criteria |
|-------|-------|---------------|
| **5.0-P1** | A1 shell/header redesign | Header decluttered, no overlap in any state, captured proof |
| 5.0-P2 | A2 tokens + A3 components | Primitives unified; screens visually consistent |
| 5.0-P3 | B1–B3 flagship screen | New executive landing view live |
| 5.0-P4 | D1 drill-downs + A4 density | Tiles clickable; sparse/dense screens rebalanced |
| 5.0-P5 | C1–C3 model depth | Validation view + one new capability |
| 5.0-P6 | D2–D3 comparison + reporting | Scenario overlay + branded export |

## Verification workflow

Visual changes are verified by capturing the live window at native 2560×1600 and inspecting
crops — **DPI-aware** capture is mandatory (`scripts/capture_tabs.ps1` run via `powershell.exe`,
not `pwsh`, with per-monitor DPI awareness) or the app's full-res render is clipped into a
virtualized bitmap. `scripts/crop.ps1` zooms regions for detail review.

## Changelog

- **2026-06-14** — Roadmap created. Pre-work landed: F14 advisory blank-panel fix, MANUAL-mode
  frequency support, new scenario suite, SOC-bar overlap fix.
- **2026-06-14** — **5.0-P1 done (A1).** Header redesigned: the transient alert badges
  (RoCoF/DNN/redispatch) and the 6 subsystem chips previously both anchored at the right edge and
  overlapped whenever an alert was active — now a single right-to-left cursor chains them with no
  overlap. New reusable `draw_module_chip` primitive: centered label, legible muted text when
  inactive (was near-invisible `COL_DIM`), filled accent when active. Badge text decluttered
  (`+$931/h REDISP` → `+$931/h`, `RoCoF x.xx Hz/s` → `RoCoF x.xx`). Verified at 2560×1600.
  Next: 5.0-P2 (A2 design tokens + A3 component pass).
- **2026-06-14** — **5.0-P2 done (A2 + A3 first pass).** Added the native HMI design-token
  layer (`SP_*`, `PAD_*`, `GAP_*`, standard KPI/button/table dimensions, shared corner radii,
  font role constants). Introduced shared panel/card primitives (`draw_panel_box`,
  `draw_panel_box_deep`, `draw_accent_card`, `draw_kpi_card`, `draw_status_badge`) and routed the
  main KPI tiles, faceplates, control rail shell, dispatch table, alarms table/log, market cards,
  emissions panels, and header alert badges through them. The result is still native Fortran/Win32,
  but the visual system now has reusable components instead of one-off rectangles.
  Next: 5.0-P3 (B1-B3 flagship executive landing screen).
- **2026-06-14** — **5.0-B3 head-start (flagship).** F1 landing now surfaces the live operator-
  advisory lead line in the ROI panel's recommendation row, severity-colored (red ALERT /
  amber DIAGNOSIS·ANOMALY / cyan OPT), truncated to fit, with the ED/AGC/ROI heuristic as the
  STATUS-OK fallback — the twin's "brain" is now visible on the home screen. Re-audited all 15
  tabs after the P2 component refactor (incl. simple-cycle, CO₂ 680 g/kWh, heat-rate 12372,
  active DIAGNOSIS advisory): no overflow, clipping, or overlap on any screen. Alignment
  workstream confirmed complete; P2 primitives introduced no regressions.
- **2026-06-14** — **5.0-P3 done (B1+B2+B3) + 5.0-D1 (drill-downs).** F1 is now a
  dual-mode screen: a new **"Plant Health & Economics" executive flagship** (default) with a
  `FLAGSHIP | DETAIL` segmented toggle (and the F1 key) back to the original detailed overview —
  zero screen-renumbering, so all 15 F-keys are unchanged. The flagship ships all three B-phase
  pieces: **B1** the animated single-line plant schematic as a full-width hero (reuses
  `draw_plant_schematic`); **B2** a composite **plant-health ring** (new `plant_health_score`
  weakest-link index over frequency/alarms/surge/reserve/SoC, colored by the shared
  `health_color`), the top-3 KPI cards (net margin, carbon intensity, reserve margin) and the
  live severity-colored operator-advisory headline; **B3** the 6 subsystems (P2X/CCS/GFM/TIE/
  MPC/OU) as first-class status tiles with live metrics, not header pills. **D1**: the ring, all
  three KPI cards and all six subsystem tiles are click-through to faceplate drill-downs — new
  popups FP_HEALTH / FP_CO2 / FP_RESERVE + FP_SUB_* extend the existing faceplate framework, and
  geometry is cached in `fl_ring`/`fl_card`/`fl_tile` for `hit_test_flagship`. Verified at
  2560x1600: flagship + detail render clean, toggle + F1 switching work, CO2 and health-ring
  drill-downs captured live, detailed overview unchanged (no regression).
  Next: A3 component finish, A4 density rebalance, then D2 scenario comparison + D3 reporting.
- **2026-06-14** — **5.0-A4 done (density rebalance of the two sparse screens).**
  **F7 Alarms**: alarm-list rows were stretched to ~120 px each (content in the top third) and
  the right "Chronological log" was one tall empty panel. Rows are now a fixed comfortable
  48 px; the reclaimed space carries an **ISA-18.2 alarm-performance KPI strip** (standing /
  unack / shelved / by-priority), and the right column gains a live **alarm state summary**
  panel above the log. **F10 Fleet**: the lower ~60 % of the canvas was empty black. Added a
  full-width **merit-order supply curve** — the canonical market diagram: a step chart of
  cumulative capacity (x, MW) vs each unit's marginal cost (y, $/MWh), with the residual-demand
  cursor crossing the stack at the marginal unit and the system **LMP** drawn as a clearing-price
  marker — plus a fleet KPI row (committed cap / dispatched / reserve / utilisation). Both
  verified at 2560x1600; no overflow or collision. (Dense F8/F15 already pass the no-overflow
  audit; left as-is.)  Next: D3 reporting + D2 scenario comparison; A3 consistency sweep.
- **2026-06-14** — **5.0-C1 done (model validation harness).** Added a self-contained
  `model_validation` engine module with an 8-point deterministic operating envelope covering
  part-load, ambient temperature, TIT, and fouling. The harness reports cycle-solver power
  MAE/bias against a calibrated GT performance-map reference, cycle heat-rate MAE/bias against
  the same map, and DNN heat-rate MAE/bias/max-error against the `train_dnn.py` dispatch-label
  formula. `engine_init` and the AI cadence refresh the metrics into `GridState`; F11 now shows a
  dedicated validation panel in the DNN diagnostics faceplate, and CSV export includes both
  scalar summary fields and a `[MODEL_VALIDATION]` block for reporting. Added
  `test_model_validation.f90`; verified with `make gui` and `make check` (19 tests + selftest
  passing). Also adjusted the shared left-rail "Dispatch controls" heading spacing after a live
  F11 capture showed it crowding the TIT slider tick labels. Next: C2 economic MPC /
  unit-commitment what-if depth, then D2 scenario comparison and D3 branded reporting.
- **2026-06-14** — **5.0-C2 done (economic MPC horizon visualization).** Promoted the MPC from
  a hidden scalar setpoint into a visible receding-horizon feature. `GridState` now carries a
  5-point preview contract: predicted time, frequency, GT MW, setpoint, MW imbalance, chosen cost
  index, hold-current-setpoint baseline, and benefit index. `mpc_agc` now fills those arrays using
  a bounded reduced-order island-frequency response, compares every candidate against the hold
  baseline, and resets stale preview data when MPC is off. F2 Dispatch now shows an **Economic MPC
  horizon** panel with 49.8/50.0/50.2 Hz guard bands, predicted frequency markers, chosen GT
  preview bar, and terminal MW error. CSV export includes scalar MPC fields plus a `[MPC_HORIZON]`
  table. Added `test_mpc_agc.f90`; verified with `make gui`, `make check` (20 tests + selftest
  passing), and live F2 capture with MPC toggled on. Next: C3 physics-fidelity overlays, then
  D2 scenario comparison and D3 branded reporting.
- **2026-06-14** — **5.0-C3 done (physics fidelity overlays).** Added a shared
  `physics_fidelity` reference layer for GT part-load heat-rate and HRSG HP-pinch/LP-recovery
  targets. The HRSG solver now enforces pinch as a heat-transfer limit instead of displaying a
  fixed number, while preserving modern CCGT efficiency through lower-pressure recovery. The
  reference envelopes are wired into `GridState`, tag publication, F1/F3/F4 charts, and CSV export
  via a `[PHYSICS_FIDELITY]` table. Added `test_physics_fidelity.f90` and extended the
  combined-cycle test to check live pinch against the reference envelope. Verified with
  `make gui` and `make check` (21 tests + selftest passing). Live screenshot capture is still
  pending because the local GUI-launch approval was blocked by the environment usage limit.
- **2026-06-14** — **5.0-D2 done (scenario comparison overlay).** Added a reusable
  `ScenarioTrace` / `ScenarioComparison` contract to `scenario_runner`: two scenarios now run from
  the same deterministic initial point and record bounded time-series for frequency, demand,
  supply, plant MW, BESS MW, imbalance, margin, and CO2 intensity, plus B-A summary deltas. F15
  is now the **Scenario Comparison** screen with A/B selectors, a KPI delta strip, and overlaid
  frequency + supply-demand imbalance plots. The GUI selector now includes all 15 shipped scenario
  files, including P2X, CCS, GFM, MPC, H2 co-firing, and manual-frequency cases. Added
  `test_scenario_runner` coverage for trace sampling, sample caps, final timestamps, and finite
  deltas. Verified with `make gui` and `make check` (21 tests + selftest passing). Live screenshot
  capture remains pending under the same GUI-launch approval limit. Next: D3 branded PDF/CSV
  export.
- **2026-06-14** — **5.0-D3 done (branded active-screen reporting).** The HMI CSV export now
  writes structured `[REPORT_META]`, `[ADVISORY]`, and `[ACTIVE_SCREEN]` sections ahead of the
  full engineering data. Metadata captures the active F-screen, zone/profile, dispatch mode, plant
  mode, generation timestamp, and advisory severity; advisory text is line-preserved but
  CSV-safe; active-screen rows are tailored per tab, including F15 scenario A/B deltas when a
  comparison is ready. `generate_report.py` now reads those sections and turns page 1 into a
  branded **Plant Operations Report** cover with active-screen context, severity-colored advisory,
  KPI tiles, and an active-screen data table while keeping the detailed DA/fleet/GT/ROI/history
  pages. Verified with `make gui`, `make check` (21 tests + selftest passing),
  `python -m py_compile generate_report.py`, and a smoke run on `shift_data_t3215.csv`.
- **2026-06-14** — **Fix: FLAGSHIP/DETAIL toggle was invisible in detail mode.** The detailed-
  overview gauges panel repaints the entire header band, erasing the toggle, which was only drawn
  inside `draw_flagship_screen`. Once in detail view the control vanished, so clicking its
  remembered position just re-selected DETAIL — trapping the user in the detailed view.
  `draw_dashboard` now redraws the toggle at the end of the detail path (on top of the gauges
  band); the F1 key still toggles from either mode. Verified at 2560x1600: toggle is visible and
  labelled in both modes (FLAGSHIP muted / DETAIL cyan when in detail) and round-trips correctly.
