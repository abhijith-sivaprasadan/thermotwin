# ThermoTwin-F — Revamp 6.0 Roadmap  (UI-only overhaul)

> Status: **Launched** 2026-06-14 · Scope: **UI only** (no engine/feature changes) ·
> Direction: **Blueprint Technical** · Appetite: **Full overhaul**

6.0 is a pure visual/interaction overhaul. The engine, scenarios, and feature set are frozen;
every change is presentation, layout, motion, or theming. Goal: turn a capable simulator into a
flagship product console that reads as a *living engineering drawing* — schematic-first, precise,
and unmistakably designed. The aesthetic deliberately serves the KTH/research angle (rigour,
draughtsmanship) while staying a credible 24/7 operating console for the ABB angle.

## Design language — "Blueprint Technical"

The console looks like a backlit technical drawing: a fine drafting grid behind everything,
hairline strokes, dimension/callout motifs, title-block framed panels, line-art schematic
symbols, and monospace annotations.

**Surfaces & palette (Blueprint Dark, default).** Deep near-black CAD ground with a visible graph-paper
grid; panels are slightly lighter navy "sheets" framed like drawing title-blocks. Ink is a cool
blueprint white; lines are a desaturated cyan-navy. One drafting-orange marginalia accent for
callouts. Status green/amber/red retained for state only. A **Blueprint Paper** (light/drafting)
variant ships in the theme engine alongside the legacy Classic Dark/Light.

**Typography & numerics.** Technical grotesque for labels + a **monospace for every numeric
readout** (tabular figures — digits stop jittering as values update; also the authentic drafting
look). Type ramp: display → title → section → body → caption → mono-readout. Numbers right-
aligned, units muted.

**Grid & line system (the signature).** Persistent minor+major engineering grid with edge ruler
ticks and corner registration marks. Hairline (1px) strokes with selective 2px emphasis;
dimension-line motifs (ticks + arrowheads) for callouts. Panels = drawing frames with a corner
title-block (label / value / unit).

**Schematic-first.** The single-line plant becomes a proper P&ID-style line drawing with
standardised ISA/ISO symbols, flow arrows, and dimension callouts — the centrepiece artifact.

**Iconography.** A thin line-art icon set drawn with the GDI+ polyline/polygon prims: schematic
glyphs for subsystems (electrolyser, capture column, GFM inverter, tie-line, MPC, OU) and for nav
+ alarms. Retires the text chips.

**Components.** Cards → title-block frames; KPI cards → label + mono value + unit + sparkline;
gauges → technical dials (tick ramp, thin needle, mono digital readout); tables → ruled BOM/parts-
list style with row numbers; badges → stamped-label style.

**Motion (full overhaul).** Boot sequence where the schematic *draws itself* like a CAD plot;
"sheet-change" screen transitions; tweened numeric/bar values; slow breathing pulse on active
alarms; hover affordances on clickable tiles. Needs the repaint timer faster than today's 250 ms
plus a small easing layer.

**Theming engine.** `hmi_theme` ships seven live identities: Blueprint Dark (default),
Classic Dark, Classic Light, Blueprint Paper, Aurora, Holographic Glass, and High Contrast.
The `T` key cycles themes, Settings exposes the current choice, and a colour-blind-safe signal
palette can be layered over any theme.

## Phase plan (sequenced, each independently shippable)

| Phase | Scope | Exit criteria |
|-------|-------|---------------|
| **6.0-P1** | Theming engine + Blueprint Dark palette + engineering grid + title-block card frame; applied to flagship F1 | Blueprint renders; `T` cycles themes; flagship captured |
| 6.0-P2 | Typography & numerics — technical sans + monospace (init_fonts + `hmi_native_draw.cpp`), type ramp, all readouts → tabular mono | Numerics monospaced/aligned across screens |
| 6.0-P3 | Component & icon pass — cards/tables/gauges/badges in drawing language; line-art icon set; retire text chips | Consistent components; icons live |
| 6.0-P4 | Schematic-first — P&ID-style single-line with ISA symbols + dimension callouts | New schematic on F1/F3/F4 |
| 6.0-P5 | Motion — faster timer + easing; self-drawing boot; sheet transitions; value tweening; alarm pulse; hover | Smooth, animated console |
| 6.0-P6 | Theme-engine polish + full 15-screen rollout (Blueprint Dark + Paper) + final 2560×1600 audit | Every screen Blueprint-complete |

## Extension — P7–P10 (still UI-only, no engine changes)

| Phase | Scope | Why it matters |
|-------|-------|----------------|
| **6.0-P7** | **Navigation & shell** — collapsible icon nav rail (P3 glyphs), `Ctrl-K` command palette, persistent L1/L2/L3 grouping, keyboard command execution | Makes it feel like a product shell, not 15 stacked screens |
| **6.0-P8** | **Chart system & live inspection** — shared chart crosshair/tooltip layer, live history inspection, heat-rate-map inspection, scenario plot inspection, KPI-card sparklines | Biggest "interactive instrument" upgrade after drill-downs |
| **6.0-P9** | **Accessibility, density & ergonomics** — compact/comfortable/presentation density, colour-blind-safe signal palette, high-contrast theme, UI-scale control, keyboard focus rings, consolidated Settings overlay | Real HMI/accessibility credibility (strong ABB signal) |
| **6.0-P10** | **Presentation & demo mode** — animated boot/splash, auto-tour with captions, coach-mark guided tour, `Ctrl-P` active-screen PNG export, Aurora/Glass identities | Turns the app into a self-running portfolio showpiece |

## Backend touch-points (`gui/hmi_native_draw.cpp`)
- Monospace + technical font support for native text (currently single family).
- Hairline anti-aliased line helper; optional arrowhead/tick helpers (most doable in Fortran).
- Faster animation timer + per-element easing state (P5).
- GDI+ active-window PNG export helper for one-key presentation capture (P10).
- (Blueprint is flatter than the glass option, so gradients are optional/minimal.)

## Verification
Same DPI-aware workflow as 5.0: capture the live window at native 2560×1600 via
`scripts/capture_tabs.ps1` (run with `powershell.exe`), inspect crops with `scripts/crop_src.ps1`.

## Changelog
- **2026-06-14** — Roadmap created. Direction = Blueprint Technical, scope = full overhaul,
  chosen after a three-way brainstorm (Aurora console / Holographic glass / Blueprint technical).
- **2026-06-14** — **6.0-P1 done.** Theming engine (`hmi_theme` ∈ Blueprint / Classic Dark /
  Classic Light; `T` cycles; `apply_theme` now called at launch) + drafting grid (fine minor +
  stronger major lines). Palette tuned to **deep near-black** (user preference over navy): cool
  CAD ground, subtle grid, cyan accents. Verified on flagship + F8.
- **2026-06-14** — **6.0-P2 (numerics) done.** Monospace support added to the native text backend
  (`hmi_native_draw.cpp` selects Consolas when weight ≥ 10000); every prominent numeric readout
  now routes through new `draw_mono`/`draw_mono_title` helpers — KPI cards, faceplates,
  value-pairs, drill-down popups, and the flagship health ring render tabular figures that no
  longer jitter as values change. Verified at 2560×1600. **Remaining P2:** title-block card frames.
  Next: P3 line-art icons, P4 P&ID schematic, P5 motion, P6 15-screen rollout.
- **2026-06-14** — **6.0-P3 (subsystem icons) first pass.** New `draw_subsystem_icon` draws thin
  line-art glyphs from pure line/box primitives — electrolyser cell (P2X), capture column (CCS),
  inverter symbol (GFM), tie-line nodes (TIE), prediction horizon (MPC), network (OU) — derived
  from each tile's label and rendered on the flagship's six status tiles (accent when active,
  muted when off). Verified at 2560×1600.
- **2026-06-14** — **6.0-P3 complete.** Nav-bar glyphs are now wired into every F-key tab,
  shared panel/card primitives render title-block registration frames, and alarm annunciator tiles
  include compact line-art alarm symbols. Verified with `make gui`, `make check`, and live F1/F7
  captures in `output/rev6_p3_capture`. Next: P4 P&ID schematic, P5 motion, P6 rollout.
- **2026-06-14** — **6.0-P4 complete.** The live plant schematic is now a reusable
  P&ID-style single-line with tagged equipment symbols, directional process arrows, dimension
  lines, instrument callouts, a frequency bus/load endpoint, and conditional HRSG/ST, BESS, RES,
  P2X/H2, and CCS branches. F1 uses it as the flagship/detail plant schematic, F3 adds a compact
  GT train P&ID strip, and F4 replaces the heat-balance box with the GT-HRSG P&ID overview.
  Verified with `make gui`, `make check`, and live F1/F3/F4 captures in
  `output/rev6_p4_capture`. Next: P5 motion/easing, then P6 full-screen rollout audit.
- **2026-06-14** — **6.0-P5 (motion) done.** Repaint timer 250 → 60 ms (engine `dt` scales with
  it, so real-time is preserved) for smooth flow; `anim_tick` animation clock advanced each tick;
  **self-drawing boot sequence** (`draw_boot_overlay` — the drafting grid plots itself in left-to-
  right behind a centred title, crosshair, and progress bar over ~1.4 s, gated by `boot_ticks`);
  breathing alpha pulse on the nav alarm badge. Verified at 2560×1600: boot captured mid-draw (92%)
  and clean hand-off to the console. **Deferred (low ROI in GDI immediate-mode):** per-value
  tweening and sheet-change transitions.
- **2026-06-14** — **6.0-P6 (Paper variant + audit) done.** Added **Blueprint Paper** as a 4th
  theme (`T` now cycles Blueprint Dark → Classic Dark → Classic Light → Blueprint Paper) — a light
  parchment drafting sheet with navy ink and a blue grid. Full-screen audit at 2560×1600: Blueprint
  renders consistently with no overflow or breakage (spot-checked F1/F4/F7/F8/F10/F11 + F15; Paper
  verified on F15). **Revamp 6.0 (P1–P6) complete.** Optional future polish: value tweening,
  sheet transitions, and per-theme accent tuning for the Paper variant.

### Extension changelog
- **2026-06-14** — **6.0-P9/P10 (theme expansion) done.** The theming engine now ships **seven
  live identities** (`T` cycles): Blueprint Dark, Classic Dark, Classic Light, Blueprint Paper,
  plus new **Aurora** (graphite + teal — P10), **Holographic Glass** (indigo + violet/cyan — P10),
  and **High-contrast** control room (pure black/white — P9). `apply_theme` now seeds a default
  signal/accent palette first so themes can override accents (Aurora teal, Glass violet) and reset
  cleanly on switch; `theme_name()` shows the active theme on the shortcuts card. Verified at
  2560×1600 (Aurora / Glass / High-contrast captured). **Remaining:** P7 nav rail + command
  palette, P8 chart toolkit + hover inspection + sparklines, rest of P9 (density / UI-scale /
  keyboard nav / Settings screen), P10 attract-tour / coach-marks / screen export.
- **2026-06-15** — **6.0-P7–P10 complete.** P7 adds the product shell: a collapsible left icon
  rail with visible L1/L2/L3 grouping, rail hit-testing, persisted rail state, and `Ctrl-K`
  command palette commands for screen jumps, toggles, scenarios, Settings, demo, export, and reset.
  P8 adds shared live inspection: a reusable crosshair/tooltip layer now appears on history traces,
  GT heat-rate map, and scenario comparison plots; faceplate KPI cards include inline sparklines.
  P9 adds Settings (`S`/`Ctrl-S`), density modes, UI-scale, colour-blind-safe signal palette,
  high-contrast route, keyboard focus traversal with Tab/Enter/Left/Right, and visible focus rings.
  P10 adds `Ctrl-M` auto-tour with captions, `H` coach marks, and `Ctrl-P` active-screen PNG export
  through the GDI+ native renderer. Verified with `make gui` and `make check` (21 unit tests +
  selftest passing).
