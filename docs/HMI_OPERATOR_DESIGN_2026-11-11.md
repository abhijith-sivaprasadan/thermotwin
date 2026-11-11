# Operator workstation redesign and audit, 11 November 2026

## Evidence basis: real screenshots, not rendered mockups

The native Windows workflow built and ran the real offline Win32 Fortran
executable, captured its GDI+ client pixels, and uploaded original PNGs.

Baseline screenshots captured at 1024 x 768 showed substantial defects:
the all-in-one control stack overlapped slider labels with command buttons;
the 16-item top navigation clipped labels; title/status text collided; KPI
labels and the single-line mimic were truncated. These were actual on-screen
defects, not an aesthetic judgment based on source inspection.

The revised operator workstation uses a muted graphite control-room palette,
with saturated red and amber reserved for abnormal conditions; a persistent
priority alarm strip; four primary views; a 16-screen secondary rail; and
three paged setpoint groups. It shows actual *model state*, never purported
measured industrial process telemetry. The old flashing blueprint grid,
bright normal-state indicators, mock relief/shadow widgets, and gauges have
been removed from the four principal operations views.

## Screen organization

1. Overview: modeled frequency, supply/demand imbalance, reserve, signed
   power-balance bars, and genuinely updated simulator trend.
2. Dispatch: modeled generation/renewables/battery mix and dispatch traces.
3. Turbine: generic-model output, surge margin, efficiency, compressor
   pressure ratio, IGV, firing and exhaust temperature, fuel flow and heat rate.
4. Alarms: alarm severity (P1/P2), condition, acknowledged versus standing,
   sheltered and returned status, operator actions and chronological simulation
   event log.

Other analysis and scenario screens remain reachable via the navigation rail;
their research-level claims and manual UI acceptance are not upgraded by the
shell redraw.

## Audible alarm and event behavior

Native Windows user32 MessageBeep uses the operating system's existing
system sounds rather than shipped music files. Unacknowledged active unshelved
P1 alarms sound about every 3 simulation timer seconds and P2 about every 6.
The timer is 125 ms. No alarm means silence; screenshot CI disables all sound.

SILENCE is **not** acknowledgment: visual indications and the event history
stay active. A new rising event re-arms audio. P1 alarms cannot be shelved.
P2 alarms can be shelved for no more than 600 simulation elapsed seconds,
then automatically unshelve, with event logging. B toggles audio enabled,
persisted in the local INI file. There is no assertion of certified
risk classification, alarm rationalization, audit-trail integrity, historian
retention, IEC 62682 or ISA-18.2 compliance.

The alarm time axis is simulation elapsed seconds, not synchronized process
UTC. Windows acoustic settings and physical playback are not checked by CI.

## Build and visual test

Use the workflow in .github/workflows/gui-visual-qa.yml. It builds the actual
thermotwin-gui-offline.exe, launches it with visual-QA-only auto-navigation,
captures Overview / GT / Alarms at the actual Windows display resolution
and exits. It verifies the presence and pixel dimensions, and uploads the
original PNG files. Review the exact images at the PR commit.

Human acceptance remains defined in docs/GUI_ACCEPTANCE.md and requires
multi-resolution, DPI, keyboard, mouse, audible verification, CSV/PDF exports
and independently exercised real OPC UA connectivity. These have **not**
been accepted simply because the screenshot and compiler jobs succeed.
