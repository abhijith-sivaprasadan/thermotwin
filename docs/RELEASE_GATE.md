# ThermoTwin-F — DOI release gate (working checklist)

Target: proposed `v2.0.0-beta.1`, **not yet released**. This checklist is intentionally independent of the historical Revamp 5/6/7 marketing and development notes.

## Must pass before tagging

- [ ] Zenodo Linked Accounts page shows GitHub + ORCID + OpenAIRE connected; **repository-specific Zenodo toggle is unverified** and needs account-owner action.
- [x] Preparation PR #4 merged into `main` as `f89d03bad5d3304ead88c7420f510494940e5654` after green CI. Tag must reference the final, newly checked main commit.
- [x] Metadata CI parses `CITATION.cff`, verifies author ORCID and version agreement with `fpm.toml`; DOI is not predeclared. Recheck exact tag before archive.
- [x] All six OS/profile matrix jobs (serial/OpenMP), full scenarios and supplemental jobs passed: [10/10 on merged `main` preparation commit](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40416209807). Repeat for the final release source commit.
- [x] Ran CoolProp IF97 comparison and recorded numerical discrepancy metrics in [benchmark documentation](INDEPENDENT_BENCHMARKS.md), with machine-readable JSON in CI artifacts. **[ ] Still preserve full JSON durably alongside the DOI record or supplement**; CI artifacts expire. It is not IF97 conformance.
- [ ] Review numerical claims (including full-cycle plant power/efficiency, exergy closure, UQ intervals), regenerate those that are included in release notes using this exact commit, and record parameters, toolchain versions and outputs. Exclude unverified historical claims.
- [ ] On Windows, verify clean `make download-opcua` + `make gui` with pinned open62541 version; verify DLL runtime requirements and third-party MPL-2.0 redistribution obligations.
- [ ] Run human GUI acceptance in `GUI_ACCEPTANCE.md`; do not claim visual/interactive certification on the basis of core CI or successful compilation alone.
- [ ] Validate the packaged Windows executable(s) on a clean Windows 10/11 machine (start, scenarios, export, OPC UA browse); include dependencies, license notices and SHA-256 checksums. If not completed, release source-only and mark GUI experimental.
- [x] Draft title, metadata, limitations, release notes and third-party notices reviewed for *source-only educational beta*. Final tag/source ZIP and archive still pending. Do not call it externally validated or industrially certified.

## After the tag

1. Publish a GitHub *release* for the exact tag. Zenodo's connected GitHub integration archives **new** releases; it does not automatically backfill old releases.
2. Confirm the Zenodo *version DOI* and *concept DOI*, exact version, author/ORCID, MIT license, archive files and record URL.
3. Only after the DOI exists: update README with a Zenodo badge, reference the DOI in the next metadata update, and link independent research outputs. Do **not** retroactively rewrite the tagged source snapshot merely to add a badge.
4. Look for subsequent OpenAIRE indexing; an OpenAIRE account alone does not automatically submit or certify this software.

## Release decision rule

Passing CI is necessary but not sufficient for a Windows GUI distribution. A citable **source-only educational beta** may proceed after accurate documentation, reproducible core checks and benchmark transparency; its limitations must be prominent. External plant-data validation and Cantera/TESPy multi-physics integration are valuable *post-DOI* research work, not prerequisites for an accurately labeled source snapshot.

## Links

- GitHub repository: https://github.com/abhijith-sivaprasadan/thermotwin
- Zenodo software metadata: https://help.zenodo.org/docs/github/describe-software/citation-file/
- Independent tests: [INDEPENDENT_BENCHMARKS.md](INDEPENDENT_BENCHMARKS.md)
- Third-party licensing: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
