# ThermoTwin-F: An Educational Modern-Fortran Simulator for Gas-Turbine and Combined-Cycle Thermodynamic Analysis

**A technical report and project monograph**

| | |
|---|---|
| **Author** | Abhijith Sivaprasadan |
| **Document type** | Self-initiated portfolio monograph / technical report |
| **Document scope** | Revamp 7.0 implementation draft; not a tagged software release |
| **Date** | 17 June 2026 |
| **Code base** | Modern Fortran (2008) · C++17 (GDI+) · C99 (OPC UA) · Python 3 (post-processing) |
| **License** | MIT |

> **Evidence boundary.** This is a historical technical draft, not an automatically regenerated validation report. Numerical summaries and roadmap language below require case-specific reproduction before external use. Current build/test evidence and unverified areas are recorded in `COMMIT_REVIEW.md`. Passing internal checks is not external validation or certification.

---

## Abstract

**ThermoTwin-F** is a self-contained digital twin of a single-shaft gas turbine and its combined-cycle (CCGT) extension, implemented in Modern Fortran (2008) with a custom native-Windows human–machine interface (HMI) and a research-grade scientific-analysis layer. The project began as a textbook-faithful Brayton-cycle performance simulator and evolved, across seven major revisions, into an interactive operating console and a *thermodynamic analysis instrument*. The current release couples (i) a station-by-station cycle solver with switchable constant- and variable-property thermophysics (NASA-polynomial gas properties, IAPWS-IF97-style water/steam, ε-NTU multi-pressure heat-recovery), (ii) a plant- and grid-level layer (automatic generation control, day-ahead unit commitment, fleet dispatch, hydrogen co-firing, carbon capture, power-to-X, grid-forming storage), (iii) a machine-learning and optimisation tier (a deep-neural-network surrogate, anomaly/fault classifiers, a MINLP day-ahead optimiser), and (iv) a **second-law analysis suite**: component exergy accounting, Monte-Carlo uncertainty quantification, Saltelli/Jansen Sobol global sensitivity, weighted-least-squares data reconciliation with χ² gross-error detection, theoretical-limit benchmarking (Carnot / Curzon–Ahlborn / ideal Brayton), and an auto-generated scientific report. The software comprises roughly **21,700 lines of Fortran across ~54 engine modules and a ~11,000-line native GUI**, plus a C++/GDI+ rendering backend and a Python post-processing pipeline. Correctness is enforced by **28 unit-test programs plus an analytic self-test oracle**, all green, and every reported number carries a stated balance-closure residual or confidence interval. At its calibrated combined-cycle design point the model produces **≈60.7 MW net (45.5 MW gas + 15.2 MW steam) at 52.8 % plant efficiency**, a **15 K HRSG pinch** and a **379 K stack**, with a **rational (second-law) efficiency η_II ≈ 0.50 ± 0.03 (95 % CI)** and a closed exergy balance. The project is positioned explicitly as a *verified, educational, non-proprietary* instrument — verified against an independent hand calculation, but not validated against any specific commercial machine and not claimed to be ASME PTC 22 / ISO 2314 compliant.

**Keywords:** digital twin · gas turbine · combined cycle · exergy analysis · second-law efficiency · uncertainty quantification · Sobol sensitivity · data reconciliation · Modern Fortran · human–machine interface

---

## 1. Introduction

### 1.1 Motivation

A *digital twin* of a thermal power plant is a living computational model that mirrors the physical asset closely enough to support design, monitoring, diagnosis, and decision-making across the asset's life. In the gas-turbine and combined-cycle domain this is industrially significant: these machines supply dispatchable, increasingly hydrogen-capable power, and their operators must continuously trade thermodynamic efficiency, emissions, mechanical life, and market economics against one another in real time.

ThermoTwin-F was conceived as a single artifact that demonstrates competence across the full stack such a twin requires — rigorous thermodynamics at the bottom, a coherent software architecture in the middle, and a credible, legible operating console on top — while remaining completely non-proprietary and reproducible. It is deliberately *not* a thin GUI over a black-box solver: the physics, the analysis methods, and the interpretation layer are all open, named, and tested.

### 1.2 Design philosophy

Five principles, inherited and sharpened across the project's revisions, govern the codebase:

1. **One data model.** A single shared contract (an `InputCase` / `CycleResult` pair in the CLI engine, and a `GridState` derived type in the live engine) is the lingua franca every module speaks. Advanced modules *compose* on this contract rather than existing as independent scripts.
2. **Conservation first.** Every model closes its governing mass / energy / exergy balance to a stated tolerance, and the residual is reported, not hidden.
3. **Reference-grade where it counts.** Property formulations and analysis methods are named and citable (IAPWS-IF97, NASA-9 polynomials, ε-NTU, Sobol', Jansen, Curzon–Ahlborn).
4. **Quantified uncertainty.** Headline numbers carry error bars with explicit provenance, produced by Monte-Carlo propagation rather than asserted.
5. **Verified, and honest about it.** The simulator is verified against an independent analytic hand calculation, and the documentation states plainly where verification ends and (absent) validation would begin.

### 1.3 Contributions

This report documents a system that contributes, as an integrated whole:

- A **modular Modern-Fortran thermodynamic engine** (~54 modules) spanning component models, a combined-cycle bottoming plant, grid dynamics, and decarbonisation subsystems, all sharing one state contract.
- A **second-law analysis layer** that turns the simulator into a research instrument: exergy destruction accounting, uncertainty quantification, global sensitivity, data reconciliation, and theoretical-limit benchmarking, each shipped with a balance check and a citable method.
- A **native, dependency-light HMI** ("Blueprint Technical" design language) rendered through a custom Win32/GDI+ backend, with sixteen analysis screens, seven live themes, a P&ID schematic engine, a command palette, and one-key scientific reporting.
- A **disciplined verification regime**: 28 unit-test programs plus an analytic self-test, deterministic seeding for reproducibility, and a DPI-aware visual-capture workflow.

### 1.4 Provenance — how the project came to be

ThermoTwin-F is a **self-initiated portfolio project**, built from scratch as a centrepiece for graduate-engineering applications (an industrial R&D track and a doctoral track in energy/turbomachinery). It was not derived from any employer's or institution's proprietary code; all physics is standard textbook thermodynamics with representative, openly-stated property values, and all third-party code is clearly delimited (only the vendored OPC UA stack, see §3.6).

Development was **iterative and version-controlled**, proceeding through a sequence of numbered releases (§9). Early versions (1.x–4.x) established functional completeness — the cycle solver, degradation and diagnostics, the combined-cycle and fleet layers, the ML/optimisation tier, and a scenario-driven regression suite. The three most recent releases were scoped deliberately: **5.0** turned a feature-complete simulator into a polished product console; **6.0** re-skinned it into a coherent "living engineering drawing"; and **7.0** added the scientific-analysis substance that distinguishes a twin that is *simulated* from one that is *understood*. The work was carried out with **AI-assisted pair-programming under continuous human direction and review**: architecture, physics choices, calibration targets, and acceptance criteria were author-owned; the assistant accelerated implementation and verification. This is disclosed in the same spirit as the project's standing "honesty note" about verification versus validation.

---

## 2. Background and related work

**Digital twins of thermal plant.** A digital twin is distinguished from a one-off simulation by its persistent, shared state and its role across the asset life-cycle. ThermoTwin-F realises this through its single `GridState` contract and a real-time engine loop that the HMI drives, rather than a batch script per study.

**Gas-turbine and combined-cycle modelling.** The simple (open) Brayton cycle and its Rankine bottoming extension are standard (Moran *et al.*; Çengel & Boles). The contribution here is not new cycle theory but a faithful, fully-open, switchable-fidelity implementation that closes its balances and exposes every assumption.

**Exergy / second-law analysis.** Exergy (availability) analysis localises *where* thermodynamic potential is destroyed, which the first law cannot (Bejan, *Advanced Engineering Thermodynamics*; Kotas, *The Exergy Method of Thermal Plant Analysis*; Szargut, chemical exergy). In CCGTs the combustor reliably dominates irreversibility (~25–30 % of fuel exergy) because of the large temperature gap across combustion — a result the engine reproduces and uses as a verification check.

**Uncertainty quantification and global sensitivity.** Monte-Carlo propagation yields distributions, not point estimates, for every KPI; variance-based **Sobol' indices** (first-order `S1` and total-effect `ST`) attribute output variance to inputs, estimated efficiently via **Saltelli** sampling with **Jansen**'s estimator (Saltelli *et al.*, *Global Sensitivity Analysis: The Primer*).

**Data reconciliation and V&V.** When redundant measurements over-determine a balance, weighted-least-squares **data reconciliation** produces the maximum-likelihood adjustment consistent with conservation, and the reconciled residual supports **gross-error detection** via a χ² test (Narasimhan & Jordache, *Data Reconciliation and Gross Error Detection*).

**Theoretical limits.** The **Carnot** efficiency bounds any heat engine between two reservoirs; the **Curzon–Ahlborn** efficiency at maximum power, `1 − √(T₀/T_src)` (Curzon & Ahlborn, *Am. J. Phys.* 1975), is a more operationally honest yardstick; the **ideal air-standard Brayton** efficiency `1 − PR^{−(γ−1)/γ}` bounds the topping cycle.

**Standards context.** Acceptance testing of real machines is governed by ASME PTC 22 and ISO 2314. ThermoTwin-F is explicitly *not* presented as compliant with these; it is an educational instrument, and the documentation says so.

---

## 3. System architecture

### 3.1 Overview and scale

The system is organised into four tiers sharing one state contract:

```
              ┌─────────────────────────────────────────────────────────┐
   HMI tier   │  gui_win32.f90  (~11,000 lines)  ·  16 screens          │
              │  Win32 window + message loop, P&ID engine, theming,     │
              │  command palette, charts, faceplates, demo mode         │
              │            │  draws via                                  │
              │            ▼                                             │
              │  hmi_native_draw.cpp (C++17 / GDI+)  ·  one-Graphics-    │
              │  per-frame batched renderer + PNG export                │
              └────────────┬────────────────────────────────────────────┘
                           │ iso_c_binding   ▲ GridState
   Orchestration   ┌───────▼─────────────────┴───────────────────────────┐
   tier            │  engine_core (845)  ·  scenario_runner (735)        │
                   └───────┬─────────────────────────────────────────────┘
                           │ operates on  GridState (engine_state, 495)
   Analysis &      ┌───────▼─────────────────────────────────────────────┐
   subsystem       │  exergy · exergy_uq · exergy_sobol · thermo_limits  │
   tier            │  data_reconciliation · scientific_report            │
                   │  dispatch_agc · mpc_agc · minlp_dayahead · fleet_uc │
                   │  p2x_electrolyser · ccs_model · gfm_bess · tie_line │
                   │  dnn_surrogate · anomaly_detector · fault_classifier│
                   │  forecast_engine · rl_dispatch · model_validation   │
                   └───────┬─────────────────────────────────────────────┘
                           │ builds on
   Physics core    ┌───────▼─────────────────────────────────────────────┐
                   │  cycle_solver · compressor · combustor · turbine    │
                   │  shaft_generator · fluid_properties · hrsg          │
                   │  steam_cycle · combustion_physics · off_design      │
                   │  degradation · transient_thermal · sensor_model     │
                   │  uncertainty_analysis · diagnostics_solver          │
                   │  precision_kinds · constants · types · utilities    │
                   └─────────────────────────────────────────────────────┘
```

**Quantitative footprint (release 7.0, source only, build artefacts excluded):**

| Component | Files | Lines |
|---|---:|---:|
| Fortran — engine (`src/`) | 54 | 8,263 |
| Fortran — native GUI (`gui/gui_win32.f90`) | 1 | 11,005 |
| Fortran — CLI driver (`app/main.f90`) | 1 | 462 |
| Fortran — unit tests (`test/`) | 28 | ~1,934 |
| **Fortran — total** | **84** | **≈21,664** |
| C++ — GDI+ render backend (`hmi_native_draw.cpp`) | 1 | 362 |
| C — OPC UA wrapper (`opcua_server.c`) | 1 | ~250 |
| Python — post-processing / report / DNN / icon | 12 | 1,760 |
| PowerShell — DPI-aware capture tooling | 7 | 322 |
| Scenario definitions (`*.scn`) | 15 | — |
| CLI case files (`*.csv`) | ~9 | — |

(The vendored OPC UA amalgamation `open62541.c/.h`, ~19.5 MB of third-party C, is excluded from all counts; it is a build-time dependency of the GUI only.)

### 3.2 The shared state contract

The live engine revolves around one large derived type, `GridState` (in `engine_state.f90`, 495 lines), which carries every operating input, every computed station state, every KPI, and every subsystem diagnostic. `engine_core` advances this state each tick; every analysis and subsystem module reads (and a few write back into) the same object. This is the architectural decision that lets ~50 modules interoperate coherently: exergy analysis, Sobol sensitivity, the DNN surrogate, and the P&ID renderer all consume the *same* `GridState`, so they cannot silently disagree about the plant's condition.

The CLI engine uses the analogous, lighter `InputCase → CycleResult` contract (`types.f90`) so that the degradation, sensor, uncertainty, and diagnostics modules likewise compose.

### 3.3 Module taxonomy

The ~54 engine modules fall into seven families:

- **Numerical foundation:** `precision_kinds` (a single `dp` kind), `constants`, `types`, `utilities`.
- **Component thermophysics:** `fluid_properties`, `ambient`, `compressor`, `combustor`, `turbine`, `shaft_generator`, `cycle_solver`, `off_design`, `hrsg`, `steam_cycle`, `combustion_physics`.
- **Asset-life analysis (CLI heritage):** `degradation`, `transient_thermal`, `sensor_model`, `uncertainty_analysis`, `diagnostics_solver`, `sensitivity_driver`, `csv_io`.
- **Second-law / scientific analysis (release 7.0):** `exergy`, `exergy_uq`, `exergy_sobol`, `thermo_limits`, `data_reconciliation`, `scientific_report`.
- **Plant & grid:** `engine_state`, `tag_bus`, `physics_fidelity`, `market_data`, `fleet_dispatch`, `grid_dynamics`, `dispatch_agc`, `mpc_agc`, `plant_economics`.
- **ML & optimisation:** `dnn_surrogate`, `model_validation`, `minlp_dayahead`, `gt_optimizer`, `fleet_uc`, `anomaly_detector`, `rl_dispatch`, `fault_classifier`, `forecast_engine`.
- **Decarbonisation & power systems:** `h2_blend`, `p2x_electrolyser`, `ccs_model`, `gfm_bess`, `tie_line`, `opcua_bridge`.
- **Orchestration:** `engine_core`, `scenario_runner`.

### 3.4 Build system

Two redundant build paths are maintained: the **Fortran Package Manager** (`fpm.toml`) for portability, and a hand-written **`Makefile`** for an fpm-free `gfortran` build. The Makefile encodes the **strict inter-module dependency graph explicitly** (each `.o` lists its prerequisite `.o`s), so parallel `make -j` remains correct. Build flags are `-std=f2008 -ffree-line-length-none`, with `-O2` for release and a `-fcheck=all -fbacktrace -Wall -Wextra` debug profile. Targets: `make` (CLI), `make check` (tests + selftest), `make gui` (native console), `make debug`.

### 3.5 Native HMI and rendering backend

The HMI is a single Fortran translation unit (`gui_win32.f90`, ~11,005 lines) that owns a real Win32 window, message loop, and timer, calling the Windows API directly through `iso_c_binding`. All drawing is delegated to a compact **C++17/GDI+ backend** (`hmi_native_draw.cpp`) exposed as `extern "C"` primitives (text, lines, polylines, polygons, filled boxes, arcs). A key performance characteristic (see §6.3) is that the backend reuses **one `Graphics` object per frame** (`hmi_begin_frame` / `hmi_end_frame`) rather than constructing one per primitive, and batches polylines through a single `DrawLines` call. The result is a fluid, buffered console with **no GUI framework dependency** beyond the OS itself.

### 3.6 Industrial connectivity (OPC UA)

For realism the GUI optionally exposes plant tags over **OPC UA**, the dominant industrial-automation protocol, via the open-source `open62541` stack (vendored, MIT/EUPL, built once at `-O1`). A thin Fortran `opcua_bridge` and a C `opcua_server` wrapper publish the tag bus. This is GUI-only and is *not* linked into the CLI or the test binaries, keeping the core engine free of third-party dependencies.

---

## 4. Physical and numerical models

### 4.1 Cycle solver

The core solves the single-shaft open Brayton cycle station by station: intake → compressor → combustor → expander → shaft/generator, with a **fuel-mass-conserving combustor energy balance** (the products mass flow includes the added fuel). Outputs are net power, thermal efficiency, heat rate, exhaust temperature and energy, specific power, and converged/sanity flags. Switchable fluid properties (§4.2) allow the solver to run in an exactly-reproducible constant-property mode or a higher-fidelity variable-property mode behind one interface.

Representative **simple-cycle** design-point output (constant-property, verified against the hand calculation): **≈30 MW, ≈31 % thermal efficiency, ≈11,800 kJ/kWh heat rate, ≈797 K exhaust** — squarely within the expected band for a machine of this class.

### 4.2 Thermophysical fidelity (release 7.0-P2)

The teaching-grade constant-`cp` shortcuts were replaced, behind the same interfaces, with:

- **NASA-polynomial (NASA-9) gas properties** for temperature-dependent `cp(T)` and enthalpy of combustion products (McBride, Zehe & Gordon, NASA Glenn coefficients);
- **IAPWS-IF97-style** saturation, enthalpy, and entropy helpers for the water/steam side;
- enthalpy-consistent compressor / combustor / turbine work; and
- an **ε-NTU multi-pressure HRSG** (HP evaporator + LP/economiser) that enforces the **pinch** as a heat-transfer limit rather than displaying a fixed number.

After this upgrade the calibrated **combined-cycle** design point lands at **45.5 MW gas + 15.2 MW steam = 60.7 MW net, 52.8 % plant efficiency, 15 K pinch, 379 K stack** — a modern CCGT operating point.

### 4.3 Combustion chemistry and component physics (release 7.0-P3)

`combustion_physics` adds: adiabatic flame-temperature shift, a simplified **Zeldovich thermal-NOx** correlation, low-load **CO slip**, and **hydrogen co-firing** effects (blend LHV / CO₂ factor / **Wobbe** index deviation, flame-temperature rise, and **flashback margin**). On the machine side it accounts for **turbine cooling-air demand**, **tip-clearance loss**, and a compressor/turbine **polytropic-loss breakdown**. These diagnostics are published into `GridState` and surface on the emissions, carbon, and sustainability screens and in exports.

### 4.4 Asset-life models (CLI heritage)

- **Degradation:** four interpretable knobs — compressor fouling, mass-flow loss, turbine erosion, combustor ΔP rise — applied to a clean case and re-solved, so all KPI shifts are *emergent*.
- **Transient thermal:** a lumped-capacitance metal node driven by exhaust temperature, integrated with both Euler and RK4 (the latter validated against an analytic steady-state oracle).
- **Sensors & uncertainty:** a bias/noise/drift measurement model, Monte-Carlo KPI uncertainty, and a deterministic bias-sensitivity tornado.
- **Inverse diagnostics:** weighted-least-squares recovery of the degradation state from noisy KPIs (grid search + coordinate-descent refinement) — the "act 3" that closes the design → monitor → diagnose loop.

---

## 5. The scientific-analysis layer (release 7.0)

This is the release that distinguishes ThermoTwin-F from a credible simulator: a falsifiable, citable analysis stack, each piece of which closes a balance and ships a unit test. All six modules build only on the live `GridState` and the exergy core, so they are independent of (and cannot clobber) the parallel physics work.

### 5.1 Exergy / second-law engine (`exergy.f90`)

Exergy is the maximum useful work obtainable as a stream is brought reversibly to the dead state `(T₀, P₀)`; its *destruction* in a component is the irreversibility `T₀·Ṡ_gen` and is where real plants lose potential. The module computes the **physical (thermomechanical) specific exergy** of an ideal-gas stream,

$$
e_{\mathrm{ph}}(T,P) = c_p\,(T - T_0) - T_0\!\left[c_p \ln\!\frac{T}{T_0} - R\,\ln\!\frac{P}{P_0}\right],
$$

and the **fuel chemical exergy** as `Ex_fuel = φ · ṁ_fuel · LHV` with `φ = 1.04` for natural gas. Gas-side mass flow is inferred from the gas-turbine energy balance,

$$
\dot m_{\mathrm gas} = \frac{\dot Q_f - \dot W_{\mathrm{GT}}}{c_{p,\mathrm gas}\,(T_{\mathrm{exh}} - T_0)},
$$

the compressor discharge from an isentropic estimate corrected by `η_c = 0.87`, and per-component destruction by differencing inlet and outlet exergy (with `max(0,·)` physical-realisability clamps):

| Component | Exergy destruction |
|---|---|
| Compressor | `Ẇ_comp − ṁ_air·e_air,2` |
| Combustor | `Ex_fuel + ṁ_air·e_air,2 − ṁ_gas·e_gas,TIT` |
| Expander | `ṁ_gas·e_gas,TIT − (Ẇ_GT+Ẇ_comp) − ṁ_gas·e_gas,exh` |
| HRSG + steam (lumped, P1) | `Ex_to_bottom − Ẇ_ST − Ex_cond` |

The whole accounting is held to a **governing balance**

$$
\mathrm{Ex_{fuel}} = \dot W_{\mathrm{net}} + \!\!\sum_{\text{components}}\!\! \dot D_i + \mathrm{Ex_{stack}} + \mathrm{Ex_{cond}},
$$

whose normalised residual `closure = (Ex_fuel − Ẇ_net − ΣD − Ex_stack − Ex_cond)/Ex_fuel` is reported as a built-in verification metric, and a **rational (second-law) efficiency** `η_II = Ẇ_net / Ex_fuel`. Dead-state defaults are `T₀ = ambient + 273.15 K`, `P₀ = 101.325 kPa`; property constants (`c_p,air = 1.005`, `c_p,gas = 1.150`, `R_air = 0.287`, `R_gas = 0.290 kJ/kg·K`, `γ_air = 1.4`) are named parameters in the module header.

**Verification.** `test_exergy.f90` asserts, for both simple- and combined-cycle points, that the balance closes (<2 %), that destructions are non-negative, that **the combustor dominates** the irreversibility, and that `η_II` is physical.

### 5.2 Uncertainty quantification (`exergy_uq.f90`)

`run_exergy_uq` Monte-Carlo-propagates 1-σ input uncertainty in **five** quantities — ambient temperature, turbine-inlet temperature (TIT), exhaust temperature, fuel flow, and pressure ratio — through the exergy accounting, drawing Gaussian perturbations via the **Box–Muller** transform from a **deterministically seeded** RNG (so studies repeat exactly). It returns mean ± standard deviation and a **95 % interval** on `η_II` and on combustor / total exergy destruction. `test_exergy_uq.f90` checks zero-σ collapse, spread under realistic σ, 95 %-interval bracketing, and low Monte-Carlo bias.

### 5.3 Global sensitivity (`exergy_sobol.f90`)

`run_exergy_sobol` computes variance-based **Sobol' indices** — first-order `S1` and total-effect `ST` — for a chosen KPI (`η_II` or total destruction) over the same five inputs, using **Saltelli** A/B sampling and the **Jansen** estimator, and identifies the dominant input. The test confirms the method correctly isolates **fuel flow** as the sole driver of `η_II` (`ST ≈ 1.1`, others ≈ 0). On the HMI this is rendered as a **total-effect tornado** with the dominant input highlighted.

### 5.4 Data reconciliation & V&V (`data_reconciliation.f90`)

For the redundant plant power balance (`gas + steam − plant = 0`) the module performs a **single-constraint weighted-least-squares reconciliation** in closed form (Lagrange multiplier `λ = imbalance / Σσᵢ²aᵢ²`, adjustment `xᵢ = yᵢ − σᵢ²aᵢλ`), guaranteeing the reconciled balance closes exactly, and flags a **gross error** when the reconciled test statistic exceeds a **χ²(1)** critical value (10.83, i.e. the 99.9 % level). `test_data_reconciliation.f90` verifies that a noisy-but-consistent balance reconciles without flagging, and that a faulty sensor (a deliberately corrupted plant reading) *is* flagged.

### 5.5 Theoretical limits (`thermo_limits.f90`)

`compute_thermo_limits` reports, against the live source/sink temperatures, the **Carnot** ceiling `1 − T₀/T_src`, the **Curzon–Ahlborn** efficiency at maximum power `1 − √(T₀/T_src)`, the **ideal air-standard Brayton** efficiency `1 − PR^{−(γ−1)/γ}`, and the **fraction of Carnot** the plant actually achieves. The test asserts the correct thermodynamic ordering (actual ≤ Curzon–Ahlborn ≤ Carnot). On the HMI a **Carnot envelope** is overlaid directly on the Brayton T–s diagram — an isotherm box between TIT and ambient over the heat-addition entropy span — so the realised cycle is seen nested inside its theoretical limit.

### 5.6 Scientific report (`scientific_report.f90`)

`write_scientific_report` aggregates the entire stack — exergy balance, Monte-Carlo UQ with confidence intervals, Sobol sensitivity, theoretical limits, and reconciliation V&V — into a single multi-section report written to any Fortran unit. It is embedded in the HMI's CSV/report export as a `[SCIENTIFIC_ANALYSIS]` block, so a one-key shift export from the live console carries a publishable analysis appendix. `test_scientific_report.f90` runs the full pipeline and asserts substantial multi-section output.

---

## 6. Software engineering and verification

### 6.1 Test-driven physics

Correctness is enforced by **28 unit-test programs** (`test/test_*.f90`) exercised by `make check`, plus an analytic **self-test oracle** (`thermotwin selftest`) that reproduces an independent hand calculation of the design point. Tests check *physics, not syntax*: energy-balance closure, monotonicity of degradation, the transient steady-state limit against an analytic solution, recovery of a known degradation by the inverse solver, exergy-balance closure with combustor dominance, UQ interval bracketing, Sobol driver isolation, reconciliation gross-error detection, and theoretical-limit ordering. The suite has grown in lock-step with capability (19 → 21 → 23 → 25 → 27 → **29** green checks across recent releases, counting the analytic selftest) and is **all-green at release 7.0**.

### 6.2 Reproducibility

Every stochastic study seeds its RNG explicitly, so Monte-Carlo uncertainty and Sobol results repeat bit-for-bit. Fluid properties default to the constant-`cp` mode precisely so the hand-calculation oracle is exactly reproducible; the higher-fidelity formulation is opt-in behind the same interface.

### 6.3 Performance engineering

A dedicated optimisation pass removed live-console sluggishness by attacking four causes: (i) the GDI+ backend was constructing a new `Graphics` object (and re-enabling anti-aliasing) *per primitive* — fixed by reusing one `Graphics` per frame; (ii) live traces were drawn segment-by-segment — replaced with batched `DrawLines` polylines; (iii) `WM_MOUSEMOVE` triggered a full repaint on every mouse move — gated to only fire while a control is being dragged; and (iv) the Monte-Carlo UQ/Sobol on the exergy screen was **drift-cached** (recomputed only when fuel flow or TIT move materially) so it never runs per frame. The console now repaints on a 60 ms timer (with the engine `dt` scaled to preserve real-time) with a smooth, responsive cursor.

### 6.4 Visual verification

UI changes are verified by capturing the live window at native **2560 × 1600** through a **DPI-aware** PowerShell workflow (`scripts/capture_tabs.ps1`, run via `powershell.exe` with per-monitor DPI awareness and `PrintWindow`/`PW_RENDERFULLCONTENT`), then inspecting cropped regions. This is how every screen-level claim in the release changelogs was substantiated.

---

## 7. The human–machine interface

### 7.1 Design language — "Blueprint Technical"

Release 6.0 unified the console under a single design language: a backlit **technical drawing**. A fine drafting grid sits behind everything; panels are framed like drawing title-blocks; strokes are hairline with selective emphasis; every **numeric readout is monospace** (tabular figures, so digits stop jittering as values update); and the single-line plant is a proper **P&ID** with standardised ISA/ISO symbols, flow arrows, and dimension callouts. The palette is a deep near-black CAD ground with cool blueprint ink and a drafting-orange callout accent, with status green/amber/red reserved strictly for state.

### 7.2 Screens

Sixteen analysis surfaces are reachable through fifteen function keys plus a command palette, including: the **flagship Plant Health & Economics** executive view (animated P&ID hero, a weakest-link health ring, top-3 KPI cards, and the live operator advisory); detailed plant overview; **GT performance** and **heat-balance** screens with T–s and T–Q diagrams (the Carnot envelope overlay lives on the T–s); emissions and **carbon/sustainability**; **alarms** with an ISA-18.2 performance KPI strip; **fleet dispatch** with a merit-order supply curve and system LMP; **day-ahead** MINLP; **DNN diagnostics** with a model-validation panel; **scenario comparison** (A/B overlay); and the **L3 Exergy Analysis** screen — a live Grassmann/Sankey availability flow, a component-destruction waterfall, the `η_II ± 95 % CI` readout, the Carnot fraction, and the Sobol tornado.

### 7.3 Shell, themes, and presentation

A collapsible icon **nav rail** with L1/L2/L3 grouping and a **`Ctrl-K` command palette** make it read as a product shell rather than fifteen stacked screens. The **theming engine** ships **seven live identities** (Blueprint Dark, Classic Dark, Classic Light, Blueprint Paper, Aurora, Holographic Glass, High-Contrast), cycled with the `T` key, with a colour-blind-safe signal palette layerable over any theme. Accessibility features include density modes, UI-scale, keyboard focus traversal with visible focus rings, and a consolidated Settings overlay. Presentation features include a self-drawing CAD **boot sequence**, a `Ctrl-M` auto-tour with captions, `H` coach marks, and **`Ctrl-P` active-screen PNG export** through the GDI+ backend.

---

## 8. Results

### 8.1 Design-point performance

| Quantity | Simple cycle | Combined cycle (calibrated) |
|---|---:|---:|
| Gas-turbine net power | ≈30 MW | 45.5 MW |
| Steam-turbine power | — | 15.2 MW |
| **Plant net power** | **≈30 MW** | **≈60.7 MW** |
| Thermal / plant efficiency | ≈31 % | **52.8 %** |
| Heat rate | ≈11,800 kJ/kWh | — |
| Exhaust / stack temperature | ≈797 K | 379 K stack |
| HRSG pinch | — | 15 K |

These sit squarely in the expected bands for machines of each class (a simple-cycle industrial GT, and a modern single-shaft CCGT).

### 8.2 Second-law analysis (verified live)

Exported from the running console (`shift_data_t27.csv`, `[SCIENTIFIC_ANALYSIS]` block):

| Metric | Value |
|---|---|
| Rational efficiency `η_II` | **0.500** |
| `η_II` with Monte-Carlo UQ | **0.502 ± 0.027 (95 % CI 0.450 – 0.554)** |
| Dominant irreversibility | **Combustor** (largest exergy destruction) |
| Exergy-balance closure residual | **−0.0000** (machine-zero) |
| Dominant Sobol driver of `η_II` | **Fuel flow** (`ST ≈ 1.1`, others ≈ 0) |

The closed balance (residual at machine zero), the combustor dominance, and the clean single-driver Sobol decomposition are exactly what second-law theory predicts for this plant — the analysis reproduces known physics rather than asserting numbers.

### 8.3 Verification status

- **28 unit-test programs + analytic selftest — all passing** at release 7.0.
- Every analysis module ships a test tied to a textbook expectation (combustor dominance, interval bracketing, Sobol driver isolation, gross-error detection, Carnot ordering).
- Every reported headline number carries either a balance-closure residual or a confidence interval.

---

## 9. Development history

| Release | Theme | What it added |
|---|---|---|
| **1.x – 4.x** | Capability | Cycle solver; degradation, transient, sensor/uncertainty, inverse diagnostics; combined-cycle + fleet dispatch; day-ahead MINLP; DNN surrogate; anomaly/fault ML; P2X/CCS/GFM/tie-line/MPC; H₂ co-firing; scenario engine + regression suite — 15 screens, functionally complete. |
| **5.0** | Product polish | Header/shell redesign; design-token + component layer; a flagship executive landing screen with health ring and click-through faceplates; density rebalance; model-validation harness; economic-MPC horizon view; physics-fidelity overlays; scenario comparison; branded PDF/CSV reporting. |
| **6.0** | "Blueprint Technical" UI | Seven-theme engine; monospace numerics; line-art icon set; full P&ID schematic engine; motion (self-drawing boot, alarm pulse); product shell (nav rail + `Ctrl-K` palette); shared chart crosshair/tooltip + sparklines; accessibility (density, UI-scale, colour-blind-safe, focus rings); demo/auto-tour + one-key PNG export. |
| **7.0** | Pure physics & scientific analysis | Exergy/second-law engine + live Grassmann screen; thermophysical fidelity (NASA-9 gas, IAPWS-IF97 steam, ε-NTU HRSG); combustion chemistry (Zeldovich NOx, CO, H₂/Wobbe/flashback, cooling-air, tip-clearance); Monte-Carlo UQ; Saltelli/Jansen Sobol + tornado; WLS data reconciliation + χ² gross-error detection; Carnot/Curzon–Ahlborn/Brayton limits + T–s envelope; aggregated scientific report embedded in every export. |

Each release proceeded in independently-shippable phases, with the application runnable at every commit and each phase closing a balance, shipping a test, and (for UI work) a 2560×1600 capture.

---

## 10. Discussion

### 10.1 What the project demonstrates

ThermoTwin-F is intended to evidence, in one artifact, the competencies a thermal-systems engineer or doctoral researcher should hold: **(i)** thermodynamic rigour — closed mass/energy/exergy balances, named reference formulations, theoretical-limit benchmarking; **(ii)** numerical and software-engineering maturity — a clean modular architecture in Modern Fortran, an explicit dependency graph, a real test suite, and deterministic reproducibility; **(iii)** uncertainty literacy — error bars and variance attribution rather than point estimates; and **(iv)** the ability to make complex systems *legible*, through a designed, accessible operating console. The combination — physics that is *understood* and *interpreted*, not merely *simulated* — is the deliberate centrepiece.

### 10.2 Limitations (stated plainly)

Consistent with the project's standing honesty note: this is a **non-proprietary, educational** simulator built on textbook thermodynamics with representative property values. It is **verified** against an independent hand calculation but **not validated** against any specific commercial engine, and it is **not** ASME PTC 22 / ISO 2314 compliant — the numbers are physically plausible illustrations, not predictions for a particular machine. Specific modelling simplifications include: a lumped (rather than station-resolved) bottoming-cycle exergy in the P1 accounting; single-constraint data reconciliation (vs a full multi-constraint network); simplified Zeldovich NOx and CO correlations; a reduced-order island-frequency response in the MPC; and a surrogate DNN trained against a dispatch-label formula rather than measured data. Each is documented where it occurs.

### 10.3 Threats to interpretation

Because property values are representative and the plant is generic, absolute KPIs should be read comparatively (clean vs degraded, scenario A vs B, actual vs limit) rather than as machine-specific truth. The verification regime guards against *internal* inconsistency (balances must close, tests must pass) but cannot substitute for validation against field data, which would require a specific instrumented asset.

---

## 11. Conclusions and future work

ThermoTwin-F integrates a faithful, switchable-fidelity gas-turbine/CCGT engine, a plant-and-grid operating layer, an ML/optimisation tier, and a research-grade second-law analysis suite under one shared state contract and one designed console — roughly 21,700 lines of tested Modern Fortran with a dependency-light native HMI. At its calibrated CCGT design point it produces a physically credible ≈60.7 MW / 52.8 % operating point with a closed exergy balance, a combustor-dominated irreversibility, and a rational efficiency of `η_II ≈ 0.50 ± 0.03`, all verified and reproducible.

Natural extensions, each building on a stated limitation: **station-resolved IAPWS-IF97 exergy** for the bottoming cycle (replacing the P1 lump); a **multi-constraint reconciliation network** with full redundancy analysis; compressor/turbine **performance maps** and cooling-air bookkeeping in the core; a **Bayesian/Kalman** diagnostics formulation; a **multi-node transient thermal model with stress output**; and validation against a published reference engine to convert "verified" into "validated."

---

## Appendix A — Engine module inventory (dependency order)

`precision_kinds` → `constants` → `types` → `utilities` → `fluid_properties` → `ambient` → `compressor` → `combustor` → `turbine` → `shaft_generator` → `cycle_solver` → `degradation` → `transient_thermal` → `sensor_model` → `uncertainty_analysis` → `diagnostics_solver` → `csv_io` → `sensitivity_driver` → `off_design` → `hrsg` → `steam_cycle` → `tag_bus` → `h2_blend` → `combustion_physics` → `engine_state` → `physics_fidelity` → **`exergy` → `exergy_uq` → `exergy_sobol` → `thermo_limits` → `data_reconciliation` → `scientific_report`** → `market_data` → `fleet_dispatch` → `grid_dynamics` → `dispatch_agc` → `plant_economics` → `dnn_surrogate` → `model_validation` → `minlp_dayahead` → `gt_optimizer` → `fleet_uc` → `anomaly_detector` → `rl_dispatch` → `fault_classifier` → `forecast_engine` → `p2x_electrolyser` → `ccs_model` → `gfm_bess` → `tie_line` → `mpc_agc` → `engine_core` → `scenario_runner` (+ `opcua_bridge`, GUI-only).

## Appendix B — Key governing equations

| # | Quantity | Expression |
|---|---|---|
| B.1 | Physical specific exergy | `e_ph = c_p(T−T₀) − T₀[c_p ln(T/T₀) − R ln(P/P₀)]` |
| B.2 | Fuel chemical exergy | `Ex_fuel = φ · ṁ_fuel · LHV`, `φ=1.04` |
| B.3 | Gas mass flow (GT balance) | `ṁ_gas = (Q̇_f − Ẇ_GT)/[c_p,gas(T_exh − T₀)]` |
| B.4 | Exergy balance | `Ex_fuel = Ẇ_net + ΣD_i + Ex_stack + Ex_cond` |
| B.5 | Rational efficiency | `η_II = Ẇ_net / Ex_fuel` |
| B.6 | Closure residual (V&V) | `(Ex_fuel − Ẇ_net − ΣD − Ex_stack − Ex_cond)/Ex_fuel` |
| B.7 | Carnot limit | `η_Carnot = 1 − T₀/T_src` |
| B.8 | Curzon–Ahlborn (max power) | `η_CA = 1 − √(T₀/T_src)` |
| B.9 | Ideal Brayton | `η_Brayton = 1 − PR^{−(γ−1)/γ}` |
| B.10 | WLS reconciliation (single constraint) | `λ = imbalance/Σσᵢ²aᵢ²`, `xᵢ = yᵢ − σᵢ²aᵢλ` |
| B.11 | Gross-error test | flag if χ²-statistic > 10.83 (χ²(1), 99.9 %) |

## Appendix C — Repository layout

```
thermotwin-f/
├── app/main.f90              CLI driver (run / degradation / transient / uncertainty / diagnostics / selftest)
├── src/                      core component & asset-life modules
│   └── engine/               plant, grid, ML, decarbonisation, and 7.0 analysis modules
├── gui/                      gui_win32.f90 (HMI) · hmi_native_draw.cpp (GDI+) · OPC UA bridge
├── test/                     28 unit-test programs + shared assert include
├── cases/                    CLI CSV inputs + scenarios/ (15 .scn) + format docs
├── python/                   matplotlib post-processing + PDF report generator
├── docs/                     theory, equations, verification, limitations, REVAMP_5/6/7 roadmaps, this report
├── scripts/                  build / test / pipeline / DPI-aware capture tooling
├── output/                   generated CSVs, figures, PDF reports
├── fpm.toml · Makefile       dual build (fpm + gfortran)
└── LICENSE                   MIT
```

## Appendix D — Selected references

1. M. J. Moran, H. N. Shapiro, D. D. Boettner, M. B. Bailey. *Fundamentals of Engineering Thermodynamics.* Wiley.
2. Y. A. Çengel, M. A. Boles. *Thermodynamics: An Engineering Approach.* McGraw-Hill.
3. A. Bejan. *Advanced Engineering Thermodynamics.* Wiley.
4. T. J. Kotas. *The Exergy Method of Thermal Plant Analysis.* Butterworths.
5. J. Szargut, D. R. Morris, F. R. Steward. *Exergy Analysis of Thermal, Chemical, and Metallurgical Processes.*
6. The International Association for the Properties of Water and Steam. *IAPWS Industrial Formulation 1997 (IF97).*
7. B. J. McBride, M. J. Zehe, S. Gordon. *NASA Glenn Coefficients for Calculating Thermodynamic Properties of Individual Species.* NASA/TP-2002-211556.
8. A. Saltelli *et al.* *Global Sensitivity Analysis: The Primer.* Wiley. (Sobol' indices; Saltelli sampling.)
9. M. J. W. Jansen. "Analysis of variance designs for model output." *Computer Physics Communications,* 1999. (Jansen estimator.)
10. F. L. Curzon, B. Ahlborn. "Efficiency of a Carnot engine at maximum power output." *American Journal of Physics,* 43(1), 1975.
11. S. Narasimhan, C. Jordache. *Data Reconciliation and Gross Error Detection.* Gulf Publishing.
12. ASME PTC 22 — *Gas Turbines* (performance test code). ISO 2314 — *Gas turbines — Acceptance tests.*

---

*Generated for release 7.0 of ThermoTwin-F. All quantitative figures in this report are drawn from the repository's source, test suite, and verified live exports; modelling assumptions and the verification-vs-validation boundary are stated explicitly throughout.*
