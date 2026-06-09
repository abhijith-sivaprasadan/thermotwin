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

## Current scope

- Live demand slider.
- Live renewable supply slider.
- Signed storage slider for charge/discharge.
- Gas-turbine dispatch slider.
- Ambient-temperature and firing-temperature sliders.
- Auto-balance mode that ramps gas dispatch toward supply/demand balance.
- Balance, frequency, reserve, power-flow and KPI visuals drawn with Win32 GDI.

## Likely next steps

- Add battery state-of-charge and storage energy limits.
- Add load-shed/curtailment actions and event logging.
- Add multiple generators with unit commitment constraints.
- Add CSV export for time-series scenarios.
- Add a plot panel for live traces of frequency, demand and dispatch.
