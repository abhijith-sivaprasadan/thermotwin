# DRAFT — ThermoTwin-F v2.0.0-beta.1

**Do not publish or describe this as released.** The version is proposed; a release tag and DOI do not exist yet.

## Summary

An educational and experimental gas-turbine/combined-cycle simulation framework in Fortran, with optional native Windows HMI. Compared with the June v1.0.0 prerelease, the current source adds expanded plant/grid scenario engines, second-law and UQ analysis, data reconciliation, and measured OpenMP parallel batch evaluation.

## Distribution

**Source archive only.** Do not attach or promote the previously published
`v1.0.0` Windows executable as if it represents this prerelease. This version
does not include a new qualified Windows binary.

## Verification evidence

Cross-platform CI on Windows, Ubuntu and macOS exercises core tests, analytic selftest, all 15 scenario fixtures, and serial/OpenMP output equivalence. Independent CoolProp/IF97 *comparisons* are proposed as descriptive benchmark evidence, **not** claims of full IF97 fidelity or external plant validation. The merged release-preparation source commit is
[`f89d03bad5d3304ead88c7420f510494940e5654`](https://github.com/abhijith-sivaprasadan/thermotwin/commit/f89d03bad5d3304ead88c7420f510494940e5654).
Its [main-branch CI run 40416209807](https://github.com/abhijith-sivaprasadan/thermotwin/actions/runs/40416209807)
passed all ten jobs, including external CoolProp IF97 comparison, optional TESPy
reference run, Windows GUI **compilation**, and PDF generation smoke test.
The **final release tag's commit** must be checked separately after README changes.

Nine-point independent property comparison (CoolProp 8.0.0):

| Quantity | Mean absolute error | Maximum absolute error |
|---|---:|---:|
| Saturation temperature | 0.532 K | 1.240 K |
| Saturated liquid enthalpy | 85.0 kJ/kg | 293.0 kJ/kg |
| Saturated vapour enthalpy | 104.0 kJ/kg | 303.2 kJ/kg |
| Superheated enthalpy | 215.9 kJ/kg | 694.7 kJ/kg |

The superheat comparison reflects differences in each implementation's saturation
temperature definition, as well as the enthalpy approximation. Machine-readable
reference results are in the `independent-if97-comparison` CI artifact, which
needs durable preservation if quoted in a paper. The presence of a TESPy reference
example is **not** a matched plant-model comparison. See
[`docs/INDEPENDENT_BENCHMARKS.md`](INDEPENDENT_BENCHMARKS.md).

## Known limitations

- Uses NASA seven-coefficient gas cp terms and approximate water/steam correlations, **not** full NASA-9 or IAPWS-IF97.
- Illustrative thermodynamic cycle: no measured commercial-plant validation; not suitable for guaranteed equipment performance or safety-critical plant control.
- Grid/market/ML/chemistry extensions include synthetic/reduced-order assumptions and must be treated as demonstrations.
- Windows GUI/OPC UA requires separate build and manual interactive acceptance; source CI is not a GUI certification.
- Historical PDF/Revamp monograph numerical summaries must be reproduced before citing them as release-specific results.

## Citing

Cite the **specific Zenodo version DOI** after the integration successfully archives this release; before then cite the repository commit. Creator ORCID: https://orcid.org/0000-0003-0299-5745.
