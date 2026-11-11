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
