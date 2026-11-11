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

The HMI launches as a borderless work-area console. Its default **operator
workstation** is now a graphite-gray, deliberately subdued interface with
four primary pages (Overview, Dispatch, Gas Turbine, Alarms), numerically
labeled KPIs, explicit alarm priorities, and real data-linked trends. The
other twelve exploratory screens remain accessible from the 16-screen rail.
The source behind these values is the **simulation**, not a physical plant.

The setpoint panel has three independently clickable **Grid / Engine / Event**
pages to eliminate the previous slider/button overlaps at narrow sizes. Alarm
audio uses native Windows system sounds. P1 unacknowledged standing alarms
repeat at about 3 simulated timer seconds, P2 at about 6; sound is rate-limited
and never plays in screenshot CI. **Silence does not acknowledge**. P1 cannot
be shelved; P2 may be shelved for at most 600 simulated seconds; new alarms
re-arm audible notification. Press **B** to toggle sound (setting persisted).
F7 opens the alarm page. Neither these controls nor the visuals establish
ISA-18.2/IEC-62682 conformance or process-safety suitability.

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


## Actual native screenshot QA

The separate [Windows visual QA workflow](../.github/workflows/gui-visual-qa.yml)
builds the *offline* executable and launches the real Win32 program on a
Windows runner with the environment variable THERMOTWIN_GUI_VISUAL_QA=1. It
captures native client pixels for overview, turbine and alarm pages as PNG
files. It also verifies the files are present and each image has at least
1024×720 resolution. The workflow artifact is named
**native-win32-gui-visual-qa**; review its PNG files, not mockups.

This is a compile/render smoke test. It does **not** click buttons, measure
audio output, test a client's OPC UA connection, or qualify binary
redistribution. See [manual acceptance](../docs/GUI_ACCEPTANCE.md) and
[operator design and findings](../docs/HMI_OPERATOR_DESIGN_2026-11-11.md).
