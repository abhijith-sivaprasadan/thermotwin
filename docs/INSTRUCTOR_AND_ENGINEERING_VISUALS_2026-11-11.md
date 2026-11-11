# ThermoTwin-F — Instructor console and engineering visual integrity
**Engineering implementation and acceptance plan · 11 November 2026 · draft PR #54**

## Scope and provenance

This change is an **educational, offline training implementation**, stacked on the alarm-drilldown PR #53 and the unmerged protection/energy-model branch chain. It is *not* a turbine OEM control emulator, a calibrated fault signature model, an industrial P&ID, a DCS access-control system, or a certified operator-training simulator.

It introduces a distinct **F15 Instructor** interface, not a new plant/PLC control channel. Existing **F15 Scenario comparison**, F7 trip/first-out/operator ACK workflow, original compressor map, and original Brayton T–s diagram remain in place. Operator and instructor surfaces run over the same `GridState`; the UI role split is a **training workflow distinction**, not user authentication/authorization.

The only manipulated conditions are explicit low-dimensional model boundary values or *TRAINING*-identified sensor injections. All existing source-qualified NO DATA behavior, confirmation windows, trip latching, restart permissives, modeled inertia, and resource accounting are retained.

## Operator/instructor workflow

On the Windows offline HMI:

1. Open F15. Click **INSTRUCTOR [I]** at upper right (or press **I**) to switch to the instructor console. F15 Scenario Comparison remains intact.
2. Click **SAVE SNAPSHOT** at a known stable point. This stores the complete `GridState` in memory, including GT trip state, timestamps, model histories, battery energy, grid state, alarm/protection state, and accumulated emissions. The HMI also checkpoints the current scripted scenario's event queue and playback flag, so running scenario exercises can resume at the saved cursor.
3. Use **FREEZE** to stop advancement of the model clock, scenario events, equipment-monitor samples and trend buffers. The HMI remains responsive. Use **RESUME** or the Space key on F15 Instructor to continue.
4. Inject at most one qualified training condition at a time:
   - **OIL 0.7 bar** — low-oil-pressure training input (illustrative alarm threshold 1.2 bar; ~1 s confirmation).
   - **SPEED 115%** — synthetic overspeed training input (110% illustrative trigger; 0.25 s confirmation).
   - **COMB 7 kPa** — synthetic dynamic combustion-pressure RMS (4 kPa illustrative alarm; 1 s confirmation).
   - **BEARING 115 C** — synthetic bearing-temperature value (105 C illustrative alarm; 2 s confirmation).
5. Use **CLEAR INPUT** to remove a training sensor value. Absent values must appear as **NO DATA**, not healthy or zero. Clearing does **not** automatically unlatch any trip.
6. Apply the supported boundary disturbances (**LOAD +10 MW**, **LOAD -10 MW**, **WIND -8 MW**, **AMB +5 C**) while the model clock is running. Solver state changes on the following engine tick. Values are clamped to the simulator's bounds.
7. Use the existing **F7** operating workflow to acknowledge, reset, and restart, respecting its state machine and interlocks. The instructor log records accepted/denied requests; there is no instructor override for reset permissives.
8. **RESTORE** an existing snapshot. This restores GridState and the scripted scenario's saved event cursor/playback state, resets the current training rubric, resynchronizes the visible alarm buffer, and leaves the engine **FROZEN** until explicit resume. If a scenario was playing at capture it resumes from that cursor, without replaying already applied directives.

Training input freshness is not bypassed: while an injection is active and the simulation runs, the instructor session periodically re-stamps the explicit input using the already-existing `set_equipment_training_input` API; the underlying monitor still rejects absent or stale inputs. Model-derived map quantities (e.g. compressor surge margin or exhaust) cannot be replaced by invented sensor measurements through this interface.

The score, currently up to 100, is a simple transparent **training rubric**: observed trip +20, accepted ACK +30, accepted reset +30, accepted restart +20, and -5 per denied request. It is **not** certification of an operator's competence. The event record is short-lived in-memory session state, not a tamper-evident historian. A simulator that has never observed a trip must not earn trip/restart score.

## Engineering-visual changes

- **Plant schematic/PFD:** flow dots are driven by `grid%elapsed_s` and only appear on the synthetic GT train while the GT is ONLINE and fuel-flow state is positive. They no longer depict delivery through a tripped engine or continue animating during freeze. A generator breaker blade shows OPEN/CLOSED using `gt_breaker_closed`. Generator status colors also track breaker position. The compact drawing exposes `gt_fuel_valve_open` and breaker state with explicit labels.
- **Compressor map:** the original three iso-speed curves, red surge boundary, margin arrow, pressure ratio and flow axes are preserved. While the GT is not online, no live operating-point dot is drawn. Hovering inside the original map adds a cursor crosshair and interpolated flow/pressure-ratio **diagram coordinates**; these coordinates are *not* another modeled observation.
- **Brayton T–s diagram:** the original live station-point approximation and Carnot envelope remain. A small dot traverses the existing 1→2→3→4 links when online as a **cycle illustration** synchronized with model time. It is not a physically predicted Lagrangian flow path, propagation speed or separate thermodynamic solution.
- **Trends and alarm drilldown:** original 60-s source-qualified alarm drill-down ring buffer and original engineering screen trends remain available. Missing sensor histories are not filled in with zero.

### Visual correctness gate

Prefer making a visual **less lively** rather than displaying a factually incorrect instrument or process motion. Drawing logic must reflect *existing* `GridState` flags and tags. Historical model values and training-only assumptions must be labelled as such. No fictitious lube flow transmitter, starter current, breaker auxiliary feedback, verified purge, combustor instrumentation or plant safety-system permission is implied.

## Reproducibility and checks

For the stacked development branch:

```powershell
git fetch origin
git switch -c instructor-preview origin/gui/instructor-engineering-visuals-20261111
make -j4 tests
python scripts/run_tests.py
make -j4 gui-offline
.\thermotwin-gui-offline.exe
```

- `test/test_instructor_console.f90` checks the qualified oil and overspeed first-out path, full modeled-state snapshot restore, refusal of frozen-session mutations, rejection of map-valued fabricated sensor data, NO DATA on injection clearing, and accepted vs denied-action scoring.
- The native Windows visual-QA harness covers the original 11 screenshots and adds actual mouse-hit paths and screenshots for instructor **running**, **frozen**, **qualified oil trip**, and **restored** states at desktop and virtual 1536-pixel widths.
- The existing cross-platform scientific/numerical test suite and independent power-balance replay must remain green.

### Not yet accepted without explicit evidence

- Native Windows hands-on interaction: actual click/keyboard alignment, legibility, resize/1024/1536 layout, cursor readouts, no overlap, lack of hidden controls.
- GUI-specific annunciator acknowledgment/overlay state on snapshot restore is reset to match the restored model rather than necessarily preserving every pre-capture GUI presentation flag. A full UI/historian checkpoint is future work; current claim is **full `GridState` restore**, not total desktop-state replay.
- Snapshot durability across application restarts is unsupported (in-memory only). No file save/load of instructor sessions exists.
- No role/login separation, multiuser remote instructor station, live OPC UA write authorization, third-party scenario authoring UI, or production historian is included.
- No calibration with industrial pressure, vibration, lube pressure, GT speed, actuator proof, burner stability or OEM map data is established.

**Merge policy:** draft until required CI success, branch-chain integration, operator acceptance and graphical QA. Even once merged, training model claims must remain limited to demonstrable code, numerical checks and disclosed assumptions.
