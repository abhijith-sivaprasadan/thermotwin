# Native Windows engineering HMI

The HMI runs the Fortran plant/grid engine in-process. It does not shell out to the CLI for each tick. A small C++/GDI+ helper handles drawing; Fortran owns the controls, plant state and calculations.

## Build and run

Use Windows with a matching MinGW-w64 GCC/G++/gfortran toolchain, GNU Make, `windres`, and Python 3.10+. From the repository root:

```powershell
mingw32-make gui
.\thermotwin-gui.exe
```

If your GNU Make is named `make`, substitute that name. Python generates the icon without third-party packages. The build links GDI+, Win32 and compiler runtime libraries; keep the matching MinGW runtime DLLs on `PATH` or alongside a packaged executable.

The default build uses an offline OPC UA backend and reports the integration as inactive. No vendor downloads are required for `make gui`.

For a console and engine runtime checks:

```powershell
mingw32-make PROFILE=debug gui-debug
.\thermotwin-gui-debug.exe
```

The startup trace is `gui_debug.log`. Run from the repository root so scenario files, optional neural weights and report helpers can be found. Do not run an old root executable after building an isolated target: use the exact path emitted by Make.

## Views

| Views | Working context |
|---|---|
| Overview, Grid Dispatch, Gas Turbine, Combined Cycle | Demand/supply balance, storage, frequency, turbine and steam performance |
| Market, Trends, Alarms | Market profiles, live history and event/alarm context |
| Diagnostics, Day-Ahead MINLP, Fleet UC + Economic Dispatch | Condition, scheduling and fleet studies |
| DNN Diagnostics, Carbon & Sustainability | Synthetic surrogate behavior, hydrogen and process extensions |
| AI Forecast, Operator Advisory | Forecast and advisory model outputs |
| Scenario Builder, Exergy Analysis | Scenario comparison and thermodynamic analysis/reporting |

These are the 16 current views, not a future roadmap. They include experimental algorithms and illustrative economic/market inputs; screen labels do not establish standards compliance or external validation.

## Navigation and exports

- Use the navigation bar/rail; F1-F15 select the first 15 views. Select Exergy through navigation.
- `?` opens shortcuts, `H` opens the guided help, and `S` opens settings.
- `T` cycles themes, `D` cycles display density, and `C` toggles the color-blind-safe palette.
- `E` exports shift CSV data; `P` exports a screen image. Export files are local run artifacts.
- The scenario view supports replay/comparison; the standalone CLI is the repeatable regression entry point.

Test the actual display scale, window size, navigation, inputs and exported files when changing the HMI. A successful link or a headless scenario test does not verify every interactive path.

## Optional OPC UA

The real backend uses `gui/opcua_server.c`, `src/engine/opcua_bridge.f90`, and a matching open62541 amalgamation (`gui/open62541.c` and `.h`). These vendor files are intentionally not committed. The retained downloader requests the configured release assets and fails explicitly if unavailable:

```powershell
mingw32-make download-opcua
mingw32-make WITH_OPCUA=1 BUILD=build/opcua GUI_EXE=build/opcua/thermotwin-gui.exe gui
.\build\opcua\thermotwin-gui.exe
```

Use a separate build directory and executable when switching backends to avoid reusing a previously linked GUI. If the release does not supply matching Windows amalgamation assets, provide the source pair from an open62541 build configured for Windows; check compatibility before claiming support. The optional download and server integration are outside core CI.

When included, the GUI starts the minimal server on TCP port 4840. Tags are read-only Double nodes grouped by category under `Objects/ThermoTwin`; unit strings are stored as node descriptions. The current wrapper does not implement typed `EngineeringUnits` metadata, authentication policy, or certificate provisioning. Treat this as a laboratory integration and configure deployment/network security explicitly before connecting real systems.

## Engineering boundaries

The GUI selects temperature-dependent gas properties and simplified water/steam correlations. Its reference outputs differ from the constant-property CLI examples. Markets, forecasts, AI diagnostics, dispatch strategies and process extensions are engineering demonstrations. Review the [engineering guide](../docs/ENGINEERING_GUIDE.md) and [verification matrix](../docs/verification_matrix.md) before interpreting a result.
