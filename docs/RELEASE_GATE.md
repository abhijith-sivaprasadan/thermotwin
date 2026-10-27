# ThermoTwin-F — DOI release gate (working checklist)

**Post-publication status (27 October 2026):** [GitHub `v2.0.0-beta.1` prerelease](https://github.com/abhijith-sivaprasadan/thermotwin/releases/tag/v2.0.0-beta.1) is **published**, source-only, from verified commit `ee0461684dbad75c5ab28fe9a66a5f6b32317887`. [CI run 40424474706](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40424474706) passed 10/10 jobs; [one-time publishing workflow 40424777919](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40424777919) succeeded. Zenodo archival is enabled for this repository and v1.0.0 was archived as DOI `10.5281/zenodo.23679257`; **the v2 version DOI still requires independent confirmation**. This checklist preserves the pre-tag evidence boundaries and does not imply industrial validation.

## Pre-tag release gates (historical review record)

- [x] Zenodo linked accounts and repository-specific archival were confirmed active on the account's ThermoTwin repository settings page; existing v1.0.0 DOI `10.5281/zenodo.23679257` was shown.
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

1. **Complete:** GitHub [source-only prerelease v2.0.0-beta.1](https://github.com/abhijith-sivaprasadan/thermotwin/releases/tag/v2.0.0-beta.1) published for exact CI-tested source commit. Zenodo's connected GitHub integration should archive new releases, but the DOI must be verified separately.
2. **Pending verification:** Confirm the Zenodo *v2 version DOI* and *concept DOI*, exact version, creator/ORCID, MIT license, archive ZIP, and record URL. Do not mistake the old v1.0.0 DOI for the new prerelease.
3. Only after the DOI exists: update README with a Zenodo badge, reference the DOI in the next metadata update, and link independent research outputs. Do **not** retroactively rewrite the tagged source snapshot merely to add a badge.
4. Look for subsequent OpenAIRE indexing; an OpenAIRE account alone does not automatically submit or certify this software.

## Release decision rule

Passing CI is necessary but not sufficient for a Windows GUI distribution. A citable **source-only educational beta** may proceed after accurate documentation, reproducible core checks and benchmark transparency; its limitations must be prominent. External plant-data validation and Cantera/TESPy multi-physics integration are valuable *post-DOI* research work, not prerequisites for an accurately labeled source snapshot.

## Links

- GitHub repository: https://github.com/abhijith-sivaprasadan/thermotwin
- Zenodo software metadata: https://help.zenodo.org/docs/github/describe-software/citation-file/
- Independent tests: [INDEPENDENT_BENCHMARKS.md](INDEPENDENT_BENCHMARKS.md)
- Third-party licensing: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)
