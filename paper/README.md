# ThermoTwin-F research paper workspace (v0.1)

This workspace accompanies **ThermoTwin-F `v2.0.0-beta.1`**, Zenodo DOI <https://doi.org/10.5281/zenodo.23679426>, exact frozen source commit `ee0461684dbad75c5ab28fe9a66a5f6b32317887`.

- [`manuscript.md`](manuscript.md) is a working software-verification and benchmarking paper, not a finished journal submission.
- `evidence/raw/` contains unchanged exported JSON artifacts from the GitHub Actions run at <https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40424474706>, plus a **separate** `tespy_unit_audit.json` clearly marked as interpretation.
- `evidence/manifest.json` maps evidence to GitHub CI artifact IDs and SHA-256 file digests.
- `evidence/report/` in the separate downloadable preservation bundle includes the CI-generated PDF and original figures as a *functional smoke-test record*, not peer-reviewed numeric results. The repository tracks only compact raw JSON, provenance and generated SVG figures.
- `evidence/figures/` holds manuscript visualization derived exclusively from the archived CoolProp comparison JSON.
- [`build_figures.py`](build_figures.py) is a paper-only plotting script, not a change to the released simulator.

## Release freeze

**Do not rewrite the Zenodo v2 archive, GitHub tag or tagged source commit.** Later documentation-only changes to `main` must not be confused with the DOI-frozen source. Future physics improvements are candidates for new version tags.

## Not suitable for journal submission yet

1. Resolve the TESPy fixture's units and independently rerun it; do not report original power numbers as verified results.
2. Have the human author review every source-level method and statement, then reconstruct evidence from the exact tag using controlled workflows.
3. Derive sensitivity of whole-cycle KPIs to steam-property errors at matched state points and define physically justified acceptance thresholds.
4. Establish genuine novelty, comparative research application and external use or a defensible research case study.
5. Supply figure-by-figure numerical audit, scientific limitations, meaningful references and ethics/AI disclosure appropriate to the chosen venue.
6. Check venue scope and, for JOSS, the public-history and research-impact gates. The GitHub repository started in June 2026, so October 2026 is less than six months.
7. Publish the evidence package as an immutable Zenodo supplemental research record before relying on the hosted CI artifacts beyond their retention period.

## Status of evidence

Property error measurements are a valid **cross-implementation difference report**. They do not establish an independently validated plant. The CI workload uses one timing repeat and cannot establish repeatable speedup. The GUI is compile-tested only. The test report PDF is not yet numerically audited. Treat the manuscript as a transparent baseline, not a demonstration of industrial-grade accuracy.
