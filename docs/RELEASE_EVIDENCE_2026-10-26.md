# Release-candidate verification evidence — 26 October 2026

This is a **dated, commit-scoped evidence note**, not a claim that an official release or DOI already exists.

- Branch candidate (prior to this note): `da222a7eb9a8b970e80440f2d27b70a32c386c6a`.
- Main baseline: `d9b9cd90ba8fc15a2a2f5a47347ab6a94d8e4837`.
- GitHub Actions [CI run 40412132403](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40412132403): **8/8 jobs successful**, including six Ubuntu/Windows/macOS release/debug core jobs, independent CoolProp IF97 comparison, and a Windows GUI **compile-only** job.
- Reference benchmark: nine pressure points using `CoolProp==8.0.0`, see [INDEPENDENT_BENCHMARKS.md](INDEPENDENT_BENCHMARKS.md) for numerical errors.
- Exact source/outputs for current planned version remain subject to final release-tag checks; do not reuse this dated run as proof of a later modified commit.

**Not established:** full property-model fidelity, independent field validation, GUI control functionality, OPC UA handshake/update-rate behavior on a clean machine, third-party license compliance of a distributed binary, or full reproducibility of the old PDF technical report.

**Required handoff:** retain the complete CI artifact JSON and report regenerate outputs with the eventual DOI release materials, with checksums. Use the version DOI only after Zenodo has actually issued it.
