# ThermoTwin-F — Full Revamp Plan

**Status:** approved direction, phased execution
**Goal:** evolve ThermoTwin-F from a single-shaft GT simulator with a grid-balancing HMI
into a research-grade, industrially-credible **combined-cycle plant digital twin** with
live market data, real grid replay, multi-unit dispatch, and an ISA-101 operator console —
impressive to both industrial recruiters and academic committees.

---

## 1. Target architecture

The single biggest structural change: **the simulation engine leaves the GUI.**
Today `gui/gui_win32.f90` (~2,650 lines) owns grid dynamics, AGC, economics, alarms,
*and* rendering. Everything below depends on breaking that apart.

```
┌─────────────────────────────────────────────────────────────────┐
│                        thermotwin-gui.exe                        │
│                                                                  │
│  ┌──────────── engine (pure Fortran, no Win32) ────────────────┐ │
│  │  cycle_solver ─ hrsg ─ steam_cycle ─ gas_properties ─ maps  │ │
│  │  grid_dynamics (swing, governor, UFLS, LFSM-O)              │ │
│  │  dispatch (economic dispatch, AGC, merit order)             │ │
│  │  market (fuel + power prices, location profiles)            │ │
│  │  scenario (script playback, assertions)                     │ │
│  │  emissions (NOx, CO2)                                       │ │
│  │            engine_step(dt) / tag database in-out            │ │
│  └───────────────────────────┬──────────────────────────────-──┘ │
│                              │ tag bus (name → value/quality/ts) │
│        ┌─────────────────────┼─────────────────────┐             │
│   native HMI (Win32/GDI+)   OPC UA server      CSV/replay logger │
│   multi-screen ISA-101      (open62541)                          │
└─────────────────────────────────────────────────────────────────┘
        external feeds: ENTSO-E API · EIA API · Open-Meteo API
```

**Key concepts**

- **Tag bus** — a flat dictionary of named process values (`GT1.POWER_MW`,
  `GRID.FREQ_HZ`, `MKT.GAS_EUR_MWH`, …) with value, engineering units, quality flag,
  and timestamp. The HMI, OPC UA server, logger, and scenario assertions all read the
  same tags. This is the standard industrial pattern and the spine of the revamp.
- **Engine step** — `call engine_step(state, dt)` advances physics + dispatch +
  economics with zero GUI knowledge. The Win32 timer becomes a thin caller.
- **HTTP access** — `http_client` module shells out to `curl.exe` (ships with
  Windows 10+) writing to a temp file; upgrade path to a WinHTTP C helper if needed.
  JSON parsed with the `json-fortran` fpm package.

---

## 2. Phases

### Phase 0 — Engine extraction (foundation, everything depends on this) ✅

Move all simulation state and logic out of `gui_win32.f90` into engine modules:

| New module | Contents (mostly moved, not rewritten) |
|---|---|
| `src/engine/grid_dynamics.f90` | swing equation, governor droop, BESS primary, UFLS, LFSM-O |
| `src/engine/dispatch.f90` | AGC merit order, curtailment, balance_now |
| `src/engine/plant_economics.f90` | revenue/fuel/penalty/ROI/CO2 accounting |
| `src/engine/tag_bus.f90` | tag registry: register/read/write, quality, timestamps |
| `src/engine/engine_core.f90` | `EngineState` type, `engine_init/step/reset` |

- GUI keeps only: window proc, layout, drawing, input handling.
- Unit tests for grid_dynamics and dispatch (step responses, UFLS latching,
  merit-order ordering) — these are currently untestable because they live in the GUI.
- **Done when:** GUI behaves identically, `fpm test` covers engine modules, CI green.

### Phase 1 — Scenario engine + replay (makes everything else verifiable) ✅

- ~~JSON scenario files~~ → **`.scn` line-based format** (implemented): timed
  events (`at 5.0 set demand_MW 45`, `at 5.0 command turbine_trip`,
  `at 25.0 assert_near frequency_Hz 50.0 0.10`), deterministic playback.
  *Deviation from plan:* JSON would have required json-fortran, which the
  fpm-free Makefile build can't absorb cheaply; the line format is
  zero-dependency in both build systems and easier to diff. Speed control
  (1×/10×) deferred to the HMI replay work in Phase 6 — headless runs always
  execute at max speed.
- Flight recorder (implemented): `--record out.csv` dumps the full tag bus
  every tick.
- 5 reference scenarios (implemented): load step, cloud ramp, turbine trip,
  over-frequency LFSM-O, UFLS cascade — 31 assertions total.
- CI runs every scenario headless after the unit tests (implemented).
- **Done:** `thermotwin scenario run cases/scenarios/load_step.scn` passes in CI.

### Phase 2 — Physics depth, part A: real gas + component maps ✅

- Temperature-dependent cp/γ/h as the default path (keep constant-property mode
  for the verified hand calculation).
- Compressor map (corrected mass flow / pressure ratio / efficiency vs speed lines,
  surge margin tag + alarm) and turbine map (choked flow, efficiency vs PR).
  Use representative published maps; cite sources (Saravanamuttoo et al.;
  Walsh & Fletcher).
- Off-design matching: solve operating point from map intersection instead of
  prescribed mass-flow fraction.
- **Done when:** part-load heat rate curve reproduces the expected real-engine shape
  (rising sharply below ~60% load) and surge margin alarms during fast ramps.

### Phase 3 — Physics depth, part B: combined cycle (the thermal showcase)

- `hrsg.f90`: single-pressure HRSG with pinch-point + approach-temperature analysis,
  effectiveness-NTU sections (superheater/evaporator/economizer), stack temperature.
- `steam_cycle.f90`: drum, steam turbine expansion with isentropic efficiency,
  condenser back-pressure vs ambient; bottoming power output.
- Plant modes: simple cycle / combined cycle toggle; CC plant efficiency target
  ~52–56% (validate against Kehlhofer, *Combined-Cycle Gas & Steam Turbine Power
  Plants*).
- Transient: drum thermal inertia (lumped), steam turbine ramp limits — the HRSG
  is why CC plants ramp slower; this couples directly into AGC realism.
- New HMI screen: heat-balance diagram (Sankey-style GT → HRSG → ST → stack).
- **Done when:** CC design point within published range with cited comparison table
  in `docs/validation.md`; HRSG pinch ≥ design minimum across the load range.

### Phase 4 — Multi-unit grid + economic dispatch (the power-systems showcase)

- Fleet: GT1 (30 MW simple cycle), GT2 (15 MW aero-derivative, fast), CC1
  (45 MW combined cycle, slow but efficient), BESS, renewables, grid intertie (optional).
- Economic dispatch: lambda iteration over unit incremental-cost curves
  (from each unit's actual heat rate × *live fuel price*), spinning-reserve
  constraint, min up/down times (simplified unit commitment).
- AGC layer distributes regulation by participation factors on top of ED setpoints —
  the textbook two-layer structure (ED every 5 min sim-time, AGC every tick).
- Inertia becomes Σ(H·S) of online units — tripping CC1 visibly worsens ROCOF.
- HMI: unit dispatch table (SP / actual / limits / status per unit), unit trip buttons.
- **Done when:** dispatch order flips when fuel price changes (cheap gas → CC base
  load; expensive gas → renewables + BESS first), reserve constraint visibly binds.

### Phase 5 — Market & environment integrations

- `market_data.f90` + location profiles menu:
  - **Plant location selector** (Settings screen): e.g. Stockholm SE3, Germany DE-LU,
    Texas ERCOT, Louisiana Henry Hub. Sets: power price zone, gas hub, 50/60 Hz,
    ambient climate defaults.
  - **EIA Open Data API** (free key): Henry Hub gas spot, US power prices.
  - **ENTSO-E Transparency API** (free token): EU day-ahead power prices, plus
    actual load curves for replay ("dispatch against yesterday's German grid").
  - EU gas (TTF): bundled monthly reference table, refreshable manually — no free
    official API; document the limitation honestly.
  - All prices land on the tag bus → economics module consumes them live;
    cached to disk with timestamps; graceful offline fallback to bundled defaults.
- **Open-Meteo API** (free, no key): wind speed + irradiance for the chosen location →
  wind power curve (cut-in/rated/cut-out) + PV model → renewable availability becomes
  physical; the slider becomes a scaling factor on installed capacity.
- 60 Hz support falls out: `FREQ_NOMINAL` becomes location-driven (ENTSO-E vs NERC
  UFLS thresholds per region).
- **Done when:** switching location changes prices/weather/frequency standard live,
  and a replayed ENTSO-E day drives demand through a full diurnal cycle.

### Phase 6 — HMI/UX revamp: multi-screen ISA-101 console ✅

- **Screen hierarchy with navigation bar** (implemented):
  - L1 **Overview** — current dashboard, decluttered to KPIs + alarms + mini-trends
  - L2 **Grid Dispatch** — unit table, AGC controls, merit order, frequency detail
  - L2 **Gas Turbine** — station conditions, maps with operating point, surge margin
  - L2 **Combined Cycle** — HRSG heat balance, steam cycle, drum level
  - L2 **Market** — live prices, location selector, cost curves, replay controls
  - L2 **Trends** — multi-pen trends with time cursors, pause/zoom, pen picker
  - L2 **Alarms** — ISA-18.2 alarm list: priority, state (UNACK/ACK/RTN), ack buttons,
    chronological log, shelving
- Faceplate popups: click any KPI tile → detail faceplate with limits and live context.
- Config persistence (`thermotwin.ini`): API key placeholders, location, window state,
  units, and HMI operating mode.
- Keyboard navigation (F1–F7 screens, Esc back) — control-room muscle memory.
- ISA-18.2-style alarm workflow: active/unacknowledged alarms, ACK, RTN, chronological
  event log, and shelving controls.
- **Done:** all screens are reachable from the native executable through one nav click
  or F1–F7; alarm raise → ACK → RTN/clear workflow is implemented in the HMI state
  machine; `make gui` and `make check` pass.

### Phase 7 — OPC UA server (the industrial credential)

- Bind **open62541** (single-file C amalgamation, MPL-2.0 — compiles into the exe
  like `hmi_native_draw.cpp`) via `iso_c_binding`.
- Expose the tag bus as an OPC UA address space (folder per unit, analog items with
  EUInfo); server runs on a background thread, read-only first, writable setpoints
  behind a build flag.
- Demo: UaExpert (free client) browsing live tags — screenshot for README.
- **Done when:** UaExpert connects, browses `ThermoTwin/GT1/POWER_MW`, values tick.

### Cross-cutting (every phase)

- **Validation & citations** (`docs/validation.md`): comparison tables against
  published data per physics phase; uncertainty quantification extended to CC.
- **Emissions rigour:** NOx via Zeldovich-form correlation vs firing temperature and
  load (cite correlation source); emissions tags + optional CO2-price term in dispatch
  costs (EU ETS style, price from location profile). *Small enough to ride along with
  Phases 3–4 rather than being its own phase.*
- **Tests + CI:** every engine module gets a test program; scenario suite in CI;
  add a Windows GUI build job (MSYS2 gfortran) so the exe build is also gated.
- **Docs:** theory.md and equations.md grow with each physics phase; README gets a
  screen-tour section with fresh screenshots.

---

## 3. Sequencing & effort

```
P0 engine extraction   ████          (prereq for all)
P1 scenario engine       ███         (prereq for physics verification)
P2 real gas + maps         ████
P3 combined cycle            ██████  (depends on P2)
P4 multi-unit dispatch          █████ (depends on P0; better after P3)
P5 market + weather      ███ can start after P0, lands fully after P4
P6 HMI multi-screen        ██████   incremental alongside P2–P5
P7 OPC UA                        ███ last; depends only on P0 tag bus
```

Rough relative effort: P0≈P1≈P5≈P7 each one solid session; P2≈P4 one to two;
P3≈P6 the big ones, two to three sessions each. **Total: a 10–15 session program.**

**Recommended order:** P0 → P1 → P2 → P3 → P4 → P5 → P6 polish → P7.
P5 (market) can be pulled earlier for demo value since it only needs P0's tag bus
and makes every later demo more impressive.

## 4. Risks & honest limits

- **TTF gas prices:** no free official API — bundled reference table, documented.
- **open62541 on MinGW/gfortran:** known to work but expect linker friction; fallback
  is a read-only CSV/TCP tag stream and OPC UA in a later pass.
- **Map data:** public-domain performance maps are representative, not engine-specific —
  state this in assumptions (same honesty policy as today's README).
- **Scope discipline:** each phase lands green (build + tests + scenario suite) before
  the next starts; the plan is a queue, not a parallel front.
