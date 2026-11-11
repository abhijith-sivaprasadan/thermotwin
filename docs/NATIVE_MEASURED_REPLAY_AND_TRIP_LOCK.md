# Native HMI measured turbine replay and trip-locked controls (v0.1)

This is the first integration of original measured UCI #551 observations into the **native Windows Fortran HMI**. It does not change the plant solver, protective interlocks or fuel/breaker commands.

## Access

1. Generate the audited source-backed replay (from repository root):
   - `python scripts/fetch_uci_gt551.py --output-dir build/uci551`
   - `python -m scripts.replay_uci_gt551 --data-dir build/uci551 --out build/uci551/replay`
2. Build: `make -j4 gui-offline` and launch `.\thermotwin-gui-offline.exe`.
3. **Ctrl+U** opens F15's historical measured-data tab. Alternatively open **F15 Scenarios** and click **MEASURED [U]**.
4. Click **LOAD CSV**. Browse previous/next 1 or 100 rows or use Left/Right when F15 measured is selected. The graph compares UCI source-observed TEY with same-record conditional model estimate and a dynamic cursor.
5. Change tabs using **SCENARIOS** or **INSTRUCTOR** in F15; original instructor exercises and A/B comparisons remain available.
6. This is a **read-only reference surface**. Source values are never assigned to `GridState`, simulated thermodynamic stations, fuel, breaker, grid dispatch or OPC UA.

## Provenance gate

- The Python producer verifies original UCI ZIP and per-year audited CSV hashes and preserves UCI-supplied year/row IDs. The Fortran importer validates strict exact expected header, finite physical-range inputs, contiguous 2014 (7,158 rows) followed by 2015 (7,384 rows), 14,542 total source records, and the residual identity.
- The Windows binary **does not independently verify SHA-256** or cryptographically attest to the downloaded CSV. It therefore labels the view **LOCAL CSV / HASH NOT VERIFIED IN GUI**. For research source integrity inspect `build/uci551/replay/replay_report.json` and use the original Python producer/CI artifact.
- If the file is missing, malformed or incomplete, the native HMI displays **NO DATA / REJECTED** and does not silently render demonstration data.
- The UCI original per-record UTC timestamps are missing; x-axis uses **source row order** only. TEY labelled MWh by publisher, not verified as direct plant MW. Model used same-record TIT and TAT, so this is *not* an advance power forecast or OEM gas-turbine physics validation.
- Fortran `test_measured_turbine_replay` uses explicitly synthetic **software-I/O fixtures**; not empirical performance evidence.

## Trip lock state

- After a protective GT trip or during simulated rundown/restart phases, turbine dispatch remains physically locked and the slider is visibly dimmed with **TRIP LOCK**.
- Clicking the locked gas slider no longer begins mouse capture/drag and provides an explicit **F7 TRIP SEQUENCE** recovery message.
- The independent load, renewable, battery, ambient and TIT controls remain separate model commands except under instructor FREEZE, whose model-clock hold is unchanged.
- The original F7 ACK/reset/restart permissives are not weakened or bypassed by this UI change. A trip cannot be cleared by dragging turbine dispatch or clicking generic RESET controls.

## Acceptance gaps

Automated compilation, numeric parser tests and native screenshot smoke tests do **not** establish hands-on Windows mouse acceptance at 100/125/150% DPI, OS scaling, every F15 subplot and a real mouse drag. Actual interactive Windows acceptance is still required. The imported original UCI historical rows should **never** be described as a live 2026 turbine telemetry feed.
