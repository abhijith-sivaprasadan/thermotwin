# ThermoTwin-F GUI

This folder contains the optional native Windows grid-balancing GUI.

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
