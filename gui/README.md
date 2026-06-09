# ThermoTwin-F GUI

This folder contains the optional native Windows grid-balancing GUI.

The GUI is written in Fortran, creates Win32 controls directly through
`iso_c_binding`, and links to the existing ThermoTwin-F solver modules. It does
not shell out to `thermotwin.exe`; every timer tick calls `solve_cycle` in the
GUI process to estimate gas-turbine output from the current controls.

## Build

From the repository root on Windows with MinGW/gfortran:

```powershell
make gui
```

The Makefile links the GUI against the existing solver object files and the
needed Win32 libraries (`user32`, `gdi32`, `comctl32`, `kernel32`).

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
- Balance, frequency, reserve, battery SOC, power-flow and KPI visuals drawn
  with Win32 GDI.
- Rolling live traces for frequency, demand and gas dispatch.
- Double-buffered dashboard repainting to avoid timer flicker.
- ROI/economics panel with revenue, fuel cost, storage cycling cost, imbalance
  penalty, net margin, heat input, fuel flow, heat rate, and a simple battery
  payback estimate.

## Likely next steps

- Add load-shed/curtailment actions and event logging.
- Add multiple generators with unit commitment constraints.
- Add CSV export for time-series scenarios.
- Add operator presets for stress events such as renewable drop, demand spike
  and generator trip.
