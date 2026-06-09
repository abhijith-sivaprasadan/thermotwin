# ThermoTwin-F GUI

This folder contains the optional native Windows GUI launcher.

The first GUI is deliberately thin: it is written in Fortran, creates Win32
controls directly through `iso_c_binding`, runs `thermotwin.exe` in the selected
mode, and displays the captured command output. The cycle solver, CSV parsing,
degradation logic, uncertainty logic, and diagnostics all remain in the existing
CLI application.

## Build

From the repository root on Windows with MinGW/gfortran:

```powershell
make gui
```

Or compile directly:

```powershell
gfortran -ffree-line-length-none gui\gui_win32.f90 -o thermotwin-gui.exe -mwindows -luser32 -lkernel32
```

Run `thermotwin-gui.exe` from the repository root so it can find
`thermotwin.exe`, `cases\`, and `output\`.

## Current scope

- Run `selftest`.
- Run the design-point case with a selectable output CSV.
- Run degradation, transient, uncertainty, and diagnostics modes against the
  bundled baseline CSVs.
- Show captured stdout/stderr in the GUI.

## Likely next steps

- Add file pickers for input and output CSVs.
- Parse result CSVs and show KPI tables directly in the GUI.
- Add a simple plot panel for sweeps and transient outputs.
- Move shared command construction into a testable Fortran module.
