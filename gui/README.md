# ThermoTwin-F GUI

This folder contains the optional native Windows grid-balancing GUI.

> **Release qualification:** The GitHub CI now verifies a clean Windows
> **compilation** of this GUI after downloading the pinned open62541 source.
> This is not evidence that all interactive screens, exports, or OPC UA tags
> function correctly. Complete the manual [GUI acceptance checklist](../docs/GUI_ACCEPTANCE.md)
> before distributing a new Windows binary. The current source-only research
> beta should label the GUI experimental until then.

The GUI is a single native Windows executable. The application lifecycle and
solver integration are written in Fortran through `iso_c_binding`, and the
dashboard links to the existing ThermoTwin-F solver modules. It does not shell
out to `thermotwin.exe`; every timer tick calls `solve_cycle` in the GUI process
to estimate gas-turbine output from the current controls.

The drawing stack now uses a small C++/GDI+ helper linked into the same
`thermotwin-gui.exe`. That helper only handles anti-aliased rendering primitives
such as text, lines, and panel shapes; Fortran remains the owner of the plant
state, controls, and thermodynamic calculations.

The HMI launches as a borderless work-area console so it fills the usable
desktop without being hidden behind the Windows taskbar. The current skin is a
true OLED-black plant-console theme with beveled gauges, inset faceplates, and
high-contrast alarm colors.

## Additive annunciator: original alarm sounds (research simulator)

The original 16-screen blueprint HMI, thermodynamic charts, process mimics,
subsystem annunciator tiles, control panel and theme engine are **preserved**.
This enhancement does not replace the existing dashboard.

The eight existing simulator-derived alarms now drive two **original synthesized
PCM tones**, not generic Windows notification sounds. Each sound is a deliberately
restrained industrial-style annunciation cue with two distinct frequencies,
a silent gap and ramped edges. Sound is generated in
`gui/alarm_pcm.cpp`, queued asynchronously via Windows WinMM in
`gui/hmi_alarm_audio.cpp` and never downloaded from external sources.
No audio samples, music, third-party licensed recordings or OEM claims are used.

- **P1 critical:** stronger three-pulse 780/990/780 Hz pattern, repeating at
  most once every 8 s while a P1 event remains standing, unacknowledged and
  unshelved.
- **P2 warning:** softer two-pulse 560/640 Hz pattern, repeating at most every
  20 s. P1 always takes precedence over P2.
- **Silence** stops the currently sounding cue and prevents repetition but
  **never acknowledges** the active condition. A *new rising event* rearms audio.
- **Acknowledge** records the operator action while retaining the alarm until
  its underlying simulated state returns to normal. P1 cannot be shelved;
  P2 shelving expires automatically after 600 seconds of simulation time.
- Press **B** to enable/disable audible annunciation; **V** cycles the
  stored output level. The HMI records both preferences in its existing
  `thermotwin-hmi.ini`. The normal alarms screen retains its historical
  list and event-log layout with two added buttons for sound and silence.

To audition the exact synthesized sounds outside the HMI, use the portable
reference generator (no OS speakers are required by this test):

```sh
mkdir -p build/alarm-previews
g++ -std=c++17 -O2 -Igui gui/alarm_pcm.cpp scripts/test_alarm_pcm.cpp -o build/alarm-pcm-check
./build/alarm-pcm-check build/alarm-previews
```

The resulting `P1-critical-original.wav` and `P2-warning-original.wav` are
the same PCM profiles the Windows GUI queues, and can be opened in any player.
An automated CI job verifies the audio generator and preserves both preview
files as an artifact.

**No certification claim:** these are simulated-model alarms, not plant
field points or safety-related annunciation equipment. Human operator testing,
speaker output tests, alarm rationalization, failure handling, historical
event integrity and ISA-18.2/IEC 62682 qualification remain incomplete.

## Retaining the full original GUI at smaller display heights

The control strip retains all six sliders, dispatch actions, scenario
selection and CSV/PDF export. Rather than overlapping lower sliders at
768/960 px heights, it now has a native GDI+ clipped content viewport
and a visible cyan scrollbar. Move the mouse over the control strip and
scroll the **wheel**, press **Page Up/Page Down**, click its narrow scroll
rail or navigate by keyboard Tab (which reveals a focused control).
The plant graphics, colors, research plots and all 16 screen destinations
are unchanged. Header mode information is shortened only where needed
to avoid colliding with the title.

The screenshot QA includes both true native 1024×768 window frames and
native 1536×960 offscreen HMI renders (not scaled screenshots), plus a
scroll-bottom frame documenting scenario/export reachability.

## Equipment-specific alarm conditions (v0.1)

The original eight grid and plant alarm points remain under **GRID / PLANT**
on the existing F7 alarm-management screen. **EQUIPMENT** now provides seven
additional condition-monitor channels for compressor surge margin, rotor
overspeed, high turbine exhaust temperature, combustion dynamics, low lube
oil pressure, bearing temperature and modeled generator grid-frequency
deviation. Model-derived conditions are explicitly tagged **MODEL** and
the four unavailable physical sensor categories display **NO DATA**, not
false healthy values. Later instructor tests can supply explicit **TRAIN**
readings; no fake sensor values are generated during normal operation.

Threshold values are pedagogical and deliberately *not* OEM calibration.
See the [equipment alarm engineering basis](../docs/EQUIPMENT_PROTECTION_v0.1.md)
for source quality, precise thresholds, hysteresis, timer logic, unit tests,
known limitations and the boundary to future trip sequencing.

## GT first-out trip and explicitly simulated restart (v0.1)

The single-unit **GT TRIP** now disconnects generator output and isolates
simulated fuel rather than merely dropping dispatch to 20%.
Open **F7 > TRIP SEQUENCE** to inspect the first-out event, turbine state,
rundown estimate and reset block reasons. ACK, RESET and SIM RESTART are
separate actions. Missing sensors require explicit **TRAIN BYPASS** for
an educational restart, and bypass cannot ignore standing conditions.

Read [trip sequence](../docs/GT_TRIP_SEQUENCE_v0.1.md) and the
[simulator correctness ledger](../docs/SIMULATOR_CORRECTNESS_LEDGER.md).

## Build

From the repository root on Windows with MinGW/gfortran:

```powershell
make gui
```

The Makefile links the GUI against the existing solver object files, compiles
the native drawing helper, generates the application icon, compiles the icon
resource with `windres`, and links the needed Win32 libraries (`gdiplus`,
`user32`, `gdi32`, `comctl32`, `kernel32`).

Run `thermotwin-gui.exe` from the repository root.

To compile a **separate fully offline GUI** without downloading or exposing
the OPC UA server, use:

```powershell
make gui-offline
.\thermotwin-gui-offline.exe
```

The offline executable uses `gui/opcua_stub.c`, reports its OPC UA status
as **inactive**, and does not open a telemetry endpoint. The regular
`make gui` target **still links real pinned open62541**; its behavior is
unchanged. Neither CI compile proves the GUI's interactive acceptance;
follow [the GUI acceptance checklist](../docs/GUI_ACCEPTANCE.md).

If the GUI closes immediately, build the console-attached diagnostic version:

```powershell
make gui-debug
.\thermotwin-gui-debug.exe
```

The GUI also writes a short startup trace to `gui_debug.log`.

## Current scope

- Live demand slider.
- Live renewable supply slider.
- Signed storage slider for charge/discharge.
- Battery energy state with capacity, round-trip efficiency and state of charge.
- Gas-turbine dispatch slider.
- Ambient-temperature and firing-temperature sliders.
- Auto-balance mode that ramps gas dispatch toward supply/demand balance.
- Balance, frequency, reserve, battery SOC, power-flow and KPI visuals drawn as
  one custom native HMI surface.
- C++/GDI+ rendering assist for smoother text, lines, and panel shapes while
  still producing a single `.exe`.
- Custom-drawn controls instead of native trackbars, so the full UI paints as
  one stable instrument panel.
- Rolling live traces for frequency, demand and gas dispatch.
- Double-buffered dashboard repainting to avoid timer flicker.
- ROI/economics panel with revenue, fuel cost, storage cycling cost, imbalance
  penalty, net margin, heat input, fuel flow, heat rate, and a simple battery
  payback estimate.
- Generated Windows icon embedded into `thermotwin-gui.exe`.

## Likely next steps

- Add load-shed/curtailment actions and event logging.
- Add multiple generators with unit commitment constraints.
- Add CSV export for time-series scenarios.
- Add operator presets for stress events such as renewable drop, demand spike
  and generator trip.
