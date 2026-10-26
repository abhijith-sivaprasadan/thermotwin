# DRAFT — ThermoTwin-F v2.0.0-beta.1

**Do not publish or describe this as released.** The version is proposed; a release tag and DOI do not exist yet.

## Summary

An educational and experimental gas-turbine/combined-cycle simulation framework in Fortran, with optional native Windows HMI. Compared with the June v1.0.0 prerelease, the current source adds expanded plant/grid scenario engines, second-law and UQ analysis, data reconciliation, and measured OpenMP parallel batch evaluation.

## Verification evidence

Cross-platform CI on Windows, Ubuntu and macOS exercises core tests, analytic selftest, all 15 scenario fixtures, and serial/OpenMP output equivalence. Independent CoolProp/IF97 *comparisons* are proposed as descriptive benchmark evidence, **not** claims of full IF97 fidelity or external plant validation. Fill in an exact commit, GitHub Actions run URL, test outcomes, benchmark artifact hashes, and manual GUI status before release.

## Known limitations

- Uses NASA seven-coefficient gas cp terms and approximate water/steam correlations, **not** full NASA-9 or IAPWS-IF97.
- Illustrative thermodynamic cycle: no measured commercial-plant validation; not suitable for guaranteed equipment performance or safety-critical plant control.
- Grid/market/ML/chemistry extensions include synthetic/reduced-order assumptions and must be treated as demonstrations.
- Windows GUI/OPC UA requires separate build and manual interactive acceptance; source CI is not a GUI certification.
- Historical PDF/Revamp monograph numerical summaries must be reproduced before citing them as release-specific results.

## Citing

Cite the **specific Zenodo version DOI** after the integration successfully archives this release; before then cite the repository commit. Creator ORCID: https://orcid.org/0000-0003-0299-5745.
