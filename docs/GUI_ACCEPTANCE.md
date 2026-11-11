# Windows native GUI acceptance — manual release gate

**Status:** automated native Windows GUI launch and real-pixel screenshot
tests are available, but hands-on button/focus/audio/OPC UA acceptance is
**NOT complete**. A screenshot is only a visual smoke test, not a certified
operator acceptance test or independent engine validation.

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
- [ ] For each of the eight modeled alarms, trigger/return/acknowledge and
  inspect priorities, text states, logged events and visible counters.
- [ ] Verify native Windows P1/P2 audible cues: no idle beep; sound repeats
  only while a condition is standing, not acknowledged, and not shelved.
  Verify audible separation, OS volume/mute, and that pressing B toggles
  sound without disabling visual warnings.
- [ ] Verify SILENCE stops audio **without** setting ACK; ACK ALL stops
  repetition while retaining standing status; a newly arising alarm re-arms
  sound after silence. Clearing must not alter the simulator's plant state.
- [ ] Confirm P1 shelving is refused; P2 shelving expires after 600 simulation
  seconds; unshelve and return-to-normal behaviors are logged and understood.
- [ ] Confirm Grid/Engine/Event controls update precisely the visible setpoint,
  mouse hit-target corresponds to drawn target, keyboard focus works, and
  no actions occur for hidden controls.
- [ ] Validate history/traces, supported simulation pause/resume, and export
  to writable paths with actual operator-clicked actions.
- [ ] OPC UA endpoint `opc.tcp://localhost:4840` is reachable using UaExpert or a standards-compliant client; verify selected live tag values and update rates; confirm socket closure after application exit.
- [ ] No undocumented process crashes, console/runtime dependency surprises, unexpected network access or hidden download steps.

## Release decision

Mark Windows binary *not qualified* if any critical GUI/OPC UA/packaging item is untested or fails. A source-only DOI prerelease may still be published with that limitation clearly visible.


## Visual regression and interaction acceptance

- [ ] Review real Windows screenshots of Overview, Gas Turbine and Alarms at
  1024×768, 1920×1080, 2560×1440 and 100%, 125%, 150% Windows scaling.
  Check for clipping, zero-width plots, overlapping labels and offscreen
  buttons. GitHub hosted-runner resolution is **not** a substitute for all
  required local resolutions.
- [ ] Check left setpoint pages, four top main navigation tabs and all sixteen
  analytical screen rail icons. Verify no invisible or out-of-bounds hitboxes.
- [ ] Read all eight alarm rows at small widths; verify returned alarms remain
  visible until acknowledged. Confirm status is expressed in text and not
  only color or sound.
- [ ] Capture manual acceptance evidence: Windows and graphics driver details,
  source SHA, the binary SHA-256, screenshots, operator, physical audio result,
  OPC UA client logs and issue references.
