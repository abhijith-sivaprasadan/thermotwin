# External software, references and attribution

ThermoTwin-F core source is MIT licensed (see root `LICENSE`). This does not change the licenses of libraries distributed alongside it.

| Project | Usage | License / obligation | Source |
|---|---|---|---|
| open62541 (pinned via `Makefile` as `v1.5.4`) | Optional OPC UA C library for Windows GUI; downloaded into ignored `gui/open62541.{c,h}` during build; may be linked into distributed GUI binaries | **MPL-2.0**: preserve notices and satisfy MPL source-availability obligations for any redistributed covered source/binary | https://github.com/open62541/open62541 |
| CoolProp (optional) | **External test oracle** for water/steam IF97 properties; not copied into ThermoTwin, not linked to production CLI | MIT-style licensing (verify at selected version); cite project when publishing scientific results | https://github.com/CoolProp/CoolProp |
| TESPy (optional) | Independent Rankine-cycle reference study; not included in ThermoTwin production engine | MIT (verify selected version); credit package and associated paper/software DOI | https://github.com/oemof/tespy |
| Cantera (future optional study) | Candidate independent chemical-kinetics reference; **not integrated or redistributed** | BSD-3-Clause (verify selected version before use) | https://github.com/Cantera/cantera |

This file records planned **external** benchmarking tools; it does *not* assert copied code, independent test success, or endorsement by those projects. All results derived from their outputs require versions, citations, inputs, tolerances and enough scripts to reproduce.

For a future packaged Windows GUI, include the applicable open62541 MPL-2.0 license text and source availability information; review the actual upstream artifact before distribution. An MIT license on the main project does not convert MPL-2.0-covered code into MIT code.
