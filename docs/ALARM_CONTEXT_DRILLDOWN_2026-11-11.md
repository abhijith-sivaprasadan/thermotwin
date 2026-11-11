# Alarm-context engineering drill-down — v0.1 (research console)

**Purpose:** Clicking any of the **eight original top annunciator tiles** or **15 alarm-row points** opens live context without dismissing or acknowledging a standing alarm. This extends the existing 16-screen native Win32 HMI; it does not replace its compressor maps, Brayton T-s plots, GT P&ID, plant diagram or alarm/event history.

## Mouse and keyboard contract

- Click a tile in the global eight-point annunciator strip or the body of an alarm row in **F7 → GRID/PLANT or EQUIPMENT**. The selected point opens a source-labelled modal showing **current value, actual alarm threshold, current alarm state, view-specific engineering context, a 250-ms sampled history (up to 240 samples ≈60 s), and operator response**.
- Clicking an alarm's row body does **not** acknowledge it. **ACK ALL** keeps its existing independent semantics; the last 86 px of each F7 row is the explicit ACK/shelve/clear affordance, with a visible action label. **ACK FIRST** in the separate trip panel remains distinct and cannot be bypassed through the alarm modal.
- **CLOSE X**, **Escape** or a click outside the overlay closes it; **OPEN ENGINEERING SCREEN** navigates to F2 grid, F3 turbine, F4 combined-cycle or F8 diagnostics, based on the alarm. Background plant controls, sliders and nav are blocked while the modal is open, preventing click-through.
- All values are computed from current `GridState` on repaint. A 240-sample circular buffer is recorded on the existing HMI 250-ms history cadence, including source availability for every sample. The plot uses only actual recorded samples with gaps for missing data; it has no synthetic sensor samples or reconstructed imaginary history.
- The alarm overlay uses a centered **engineering workspace across the canvas below the annunciator**, because the native 1024px main-content column is too narrow for both the real compressor map and a readable live trend. Underlying sliders and navigation remain unchanged but are temporarily covered and mouse-blocked; closing the overlay restores the original screen. Native 1024px and virtual 1536px screenshots are captured automatically, including **a real top-tile hit and a real equipment-row hit** through the Win32 mouse handler. Interactive human acceptance remains separate.

## The fifteen source-specific mappings

| Alarm | Live signal and modeled trigger | Visual / link | Operator context |
|---|---|---|---|
| Grid underfrequency | `frequency_Hz < f_nom−0.5 Hz` | Grid generator / electric bus P&ID, F2 | Power imbalance, ROCOF, BESS and UFLS; do not raise tripped GT dispatch |
| Grid overfrequency | `frequency_Hz > f_nom+0.5 Hz` | Grid P&ID, F2 | Surplus, LFSM-O, BESS charging and downward dispatch |
| Low reserve | `reserve_MW<2 MW`; fleet mode uses `fleet_reserve_requirement_MW` | Grid dispatch faceplate, F2 | Dispatch headroom and physically available assets |
| Low BESS SOC | `SOC<15%` | Battery→inverter P&ID, F2 | Actual MWh, reserve availability, inverter power |
| UFLS active | `UFLS_stage>=1` | Electrical bus context, F2 | Gross versus served load and stage latch |
| Turbine ceiling | `effective_gas_dispatch_pct>=99.5%` | Existing Brayton T-s turbine diagram, F3 | **This is a dispatch ceiling**, NOT a measured TIT or metal-temperature trip |
| Compressor surge margin | `surge_margin_pct<8%` in online single-GT mode | **Original compressor map** with live operation dot, surge curve and iso-speed lines, F3 | Current PR, IGV, dispatch ramp, map model limits |
| HRSG pinch | HRSG solver `pinch_ok=false`, including feasibility failure | Focused GT exhaust→HRSG→steam P&ID, F4 | Minimum model pinch 15 K; flag can also reflect other heat-balance feasibility conditions |
| Equipment compressor surge | Model-derived map margin, equipment threshold 6% | Original compressor map, F3 | Equipment-condition alarm is separate from earlier 8% plant warning |
| Rotor overspeed | Supplied **TRAINING** rotor-speed sample, 110% | Turbine diagram, F3 | Explicitly no independent OEM rotor-speed transducer or overspeed relay |
| GT exhaust high | Model-derived exhaust K, threshold 950 K | Brayton T-s, F3 | Not measured thermocouple proof |
| Combustion oscillation | **TRAINING** pressure oscillation sample, 4 kPa RMS | Compressor→combustor P&ID, F3 | No transducer/spectral combustion monitor |
| Low lube oil | **TRAINING** oil-header pressure, 1.2 bar | Equipment faceplate, F8 | No real pump/flow/switch reading |
| High bearing temperature | **TRAINING** temperature, 105 °C | Turbine diagram / equipment, F3 | No bearing-metal RTD or mechanical temperature model |
| Generator frequency deviation | Model electrical `abs(f−f_nom)` proxy, 1 Hz | Electrical bus/generator diagram, F2 | **Not** generator differential, voltage, frequency relay or current protection |

Equipment alarm clear/hysteresis thresholds are retained separately from activation thresholds in the engineering data layer. Names, physical units, inputs and quality states come from `equipment_protection`; none are guessed from the alarm text. Under-frequency limits follow 50/60-Hz profiles dynamically. The HRSG source is unavailable when the combined cycle is off; the compressor map is unavailable after a GT shutdown, so its plotted OP cannot be mistaken for a running measurement.

## Evidence and limitations

- `src/engine/alarm_drilldown.f90`: authoritative source/units/threshold/quality/controller-response mapping; actual 240-step ring history and shared mouse-hit geometry.
- `test/test_alarm_drilldown.f90`: checks dynamic 50/60-Hz thresholds, fleet reserve, dispatch-versus-TIT warning, model surge 8% / HRSG minimum, unavailable oil and training provenance, hysteresis, ring wrap, NO DATA segments and hit geometry.
- `gui/gui_win32.f90`: original map/Brayton functions reused directly; electrical and focused process P&IDs show **live** GT breaker, frequency/imbalance, BESS SOC/inverter power, HRSG pinch and steam MW. The modal continues to refresh during timer ticks; sensor quality loss changes to **NO DATA**.
- `scripts/gui_visual_qa.ps1`: captures eight original HMI views plus live drilldown examples (including native 1024px) for screenshot comparison.
- Full automatic CI and Windows screenshot QA must pass **on the exact head SHA**. Physical plant/OEM validation, measured turbines, actual protection relay setpoints and mouse/audio acceptance are *not* established by a green CI result. No automated response changes equipment setpoints.
- Global-header crowding at native 1024px remains tracked separately in [issue #52](https://github.com/abhijith-sivaprasadan/thermotwin/issues/52); this patch does not claim that independent UI defect is resolved.

**Scientific position:** this is an operational **teaching-model** drill-down. Field response actions must be based on validated plant instrumentation and qualified operating procedures, not on simulated tags.
