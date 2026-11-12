# Windows native GUI acceptance — manual release gate

**Status:** not run for this release candidate. GitHub's cross-platform core tests do **not** exercise the interactive HMI or verify OPC UA operation.

Record tester, machine/OS/build, Windows display scaling/resolution, commit SHA, toolchain version, the exact `open62541` version/source, screenshots and results of each case.

## Clean-room build

1. Fresh clone with no untracked `gui/open62541.{c,h}` and no compiler objects.
2. Install documented MinGW-w64 gfortran, g++/gcc, `make`, `windres`, Python, curl; record version strings.
3. `make download-opcua` followed by `make gui`. Note/download failures; do not substitute a locally cached vendor file silently.
4. Ensure the `thermotwin-gui.exe` starts without missing DLLs and is not blocked by SmartScreen or antivirus; document machine and distribution method.

## Interactive functions (check each manually)

- [ ] Starts and closes cleanly; no crash at idle or after repeated navigation.
- [ ] All accessible screens render correctly, without clipped text at 100/125/150% DPI and common 1080p/1440p resolutions.
- [ ] Each slider/setting changes the intended live state; recheck extreme values, disabled states, and reset.
- [ ] Scenario load/step/replay/end behaves predictably across all 15 scenarios; compare core CLI outputs where applicable.
- [ ] Cycle, exergy and sensitivity readouts are finite, labeled with units and consistent with reference core calculations.
- [ ] Alarms and acknowledgment behaviors, history/traces, pause/resume, and export save to user-writable paths correctly.
- [ ] OPC UA endpoint `opc.tcp://localhost:4840` is reachable using UaExpert or a standards-compliant client; verify selected live tag values and update rates; confirm socket closure after application exit.
- [ ] No undocumented process crashes, console/runtime dependency surprises, unexpected network access or hidden download steps.

## Release decision

Mark Windows binary *not qualified* if any critical GUI/OPC UA/packaging item is untested or fails. A source-only DOI prerelease may still be published with that limitation clearly visible.


## Custom alarm annunciator acceptance (new additive enhancement)

- [ ] Verify original full blueprint HMI and all existing 16 analytical
  screens, themes, charts, controls, P&IDs, help and OPC UA remain intact.
- [ ] Trigger P1 underfrequency and P2 reserve alarms using actual simulated
  model state. Verify their different **original PCM tones** on a Windows
  audio device, not Windows system notifications; verify P1 priority and
  no sound when no standing unacknowledged alarm exists.
- [ ] Confirm SILENCE halts ongoing sound without setting ACK; new rising
  alarm rearms sound; ACK ALL removes sound while the condition continues
  visually and stays in the event list.
- [ ] Confirm P1 cannot be shelved via either bulk or row controls;
  P2 shelving logs its action, expires after 600 simulated seconds, and
  does not dismiss underlying fault physics.
- [ ] Confirm B toggles sound, V changes the output gain, and both persist
  through a normal clean shutdown and fresh launch.
- [ ] Disconnect audio output and verify alarm display continues without
  crashing or claiming audio was heard.
- [ ] Inspect original GUI screenshots at 1024×768, 1536×960, 1920×1080
  and 2560×1440. Verify no new collisions from extra alarm buttons,
  unchanged analytics, responsive layout and all active hotspots.
- [ ] Save signed manual test results; automatic waveform tests and
  compilation are not substitutes for speaker/mouse/OPC UA acceptance.


## Automated Windows acceptance and complete machine evidence (PR #62)

The separate workflow .github/workflows/gui-acceptance-report.yml builds the
actual offline native Win32 GUI on Windows GitHub Actions and launches it under
THERMOTWIN_GUI_VISUAL_QA=1. The original screenshot/behavior tests remain,
and the additional in-process matrix exercises **16 HMI screen renderers**,
**six slider keyboard handlers**, selected controls/themes/audio configuration,
and loads each of the **15 packaged scenarios** through one first model tick.

The test mode records the actual **simulated Fortran model state**:
- gui_telemetry.csv: every 125-ms native HMI timer sample; elapsed simulation
  time, selected screen, demand, renewable/storage/gas commands, ambient/TIT,
  frequency, power, supply/imbalance, SOC, GT phase and first-out.
- native_qa_results.csv: original PASS/FAIL assertions executed inside the
  native Win32 GUI; no mocked browser.
- native_qa_measurements.csv: simulated numeric states after each control,
  screen and scenario check.
- Original native GUI export shift_data_t*.csv, native/virtual screenshots,
  compiler log, Windows harness log and gui_debug.log.

After execution, including when it fails, run:

~~~powershell
python scripts/gui_acceptance_report.py --source build/gui-visual-qa --out build/gui-acceptance --repo . --debug-log gui_debug.log --qa-exit-code 0 --build-exit-code 0
~~~

Provide the actual nonzero exit codes when either the build or native test
failed. Never pass zero to create a false green local run. The collector emits
build/gui-acceptance/report.pdf, test_results.csv, test_results.json,
evidence_sha256.csv, and thermotwin-gui-acceptance.zip. The ZIP contains the
PDF and **all source-level CSVs, screenshots and logs**; the PDF provides
the summary, assertion ledger, simulator numerical min/max/mean ranges and
failure excerpts. GitHub Actions uploads the report and archive even when
native test execution fails. Download from the Native Windows GUI acceptance
PDF and evidence ZIP workflow run's Artifacts section. Action artifacts
expire after 30 days; preserve the ZIP separately if permanent evidence is needed.

**Scope honesty:** a PASS is limited to the named assertion. Native screen
images are not human visual readability approval. One scenario step is not
a full scenario replay. A software audio-toggle test does not prove speaker
sound. The offline executable cannot validate a real OPC UA endpoint.
DPI 125/150%, the existing HMI PDF button, full distribution and independently
metered industrial plant performance remain NOT_TESTED. This evidence is not
a certified protection system, production pass-off, or OEM/ASME/ISO qualification.

### Open visual defects and export coverage

The known-defect ledger at [GUI_VISUAL_DEFECTS.json](GUI_VISUAL_DEFECTS.json)
records actual screenshot-confirmed text collisions in the 1024x768 overview
and 1536x960 instrument/status layouts. The report collector marks each
unresolved issue as **FAIL**, even when screenshot encoding and automated
navigation tests pass. This is a reviewed release gate, not a claim that
all visual collisions can be detected algorithmically.

The acceptance runner also triggers the native screen-PNG export and
validates its output. It runs the original operations PDF generator against
the actual native shift-export CSV using NumPy/Matplotlib; that operations
PDF is placed in the raw ZIP. The existing in-GUI asynchronous PDF-button
process itself remains **NOT_TESTED** and requires a separate GUI action
verification. Neither operations PDF nor acceptance PDF is evidence of
actual plant instrumentation.


### 1024px native engineering viewport regression (VIS-004)

On 1024×768, the native 16-screen GUI keeps the 14 dense engineering screens
at their readable **950×930 internal drawing geometry** inside a clipped main
viewport rather than shrinking multi-column process/optimization charts until
their legends become illegible. The control strip, alarm annunciator, navigation
and fixed header remain in place. Use the four visible **PAN** buttons to move
left/right/up/down, or move the mouse over the engineering panel and use the
wheel vertically (**Shift+wheel** horizontally). Screen changes reset the
viewport to the origin. Both scroll directions and actual pointer mapping
to the F7 alarm-audio and F15 instructor-tab controls are regression tested.

The Windows runner captures original / far-right / bottom-of-canvas views
of every one of those 14 pages, plus baseline 1024 native and 1536 native
screens for all 16 views. The collector fails missing PNGs, invalid geometry,
missing native pointer assertions or unchanged pixels across pan captures.
Day-Ahead F9 separates the schedule legend from headings and bounds the
economics and Pareto axis labels. Full engineering details remain in the
natively scrollable canvas; they are **not** replaced with static images.

Automated results certify executed operations and changed native pixels,
not readability at every zoom/display scaling or independent human-factors
sign-off. The resolved visual defect register is explicitly **NOT_TESTED**
in the PDF until that independent review. The remaining offline vs OPC-UA,
speaker, full replay and industrial hardware qualification exclusions still apply.
