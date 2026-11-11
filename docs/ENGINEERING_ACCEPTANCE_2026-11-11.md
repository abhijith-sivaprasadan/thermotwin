# ThermoTwin-F — engineering acceptance audit (11 November 2026)

**Decision: CONDITIONALLY ACCEPT as reproducible educational research software; NOT ACCEPTED as a physically validated or industry-qualified engine predictor.**

**Scope:** targeted independent reading of the core Brayton/site/pass-off contracts, canonical evidence documents, repository tree, six open-issue acceptance criteria, and the completed 16-job main CI run at [a7a7b5d3](https://github.com/abhijith-sivaprasadan/thermotwin/commit/a7a7b5d3c7da2d1637e407aa7e2fa68cf843434b). This is not an equation-by-equation review of every simulator module or an executed external engine test. New code changes must pass their own subsequent CI before this audit can be treated as accepted for the new source revision.

## Audited, independently traceable evidence hierarchy

1. **Equation-derived generic model.** The simple Brayton solver uses compressor mass flow for compressor work, gas-plus-fuel flow for turbine work, heat input from fuel mass flow times scalar LHV, and net efficiency from electric net power divided by fuel energy rate. Its heat-rate identity is 3600/eta in kJ/kWh. These equations can be checked numerically, but are not measurements.
2. **Corrected reference/site model.** ISO flange deck fixes 288.15 K and 101325 Pa at the compressor inlet and 101325 Pa at exhaust; reference pressure losses are zero. Site calculation uses the identical reference hardware, with ambient temperature/pressure and explicitly assumed inlet/exhaust losses varied. Power and heat-rate reference/site correction factors are distinct. Humidity physics and fuel chemistry are not available.
3. **Weather-model evidence.** Four predefined ERA5 weeks, 672 hourly reanalysis inputs and 2688 modeled loss-scenario outputs. Reanalysis is not a flange sensor. Those scenario differences do not quantify model-form uncertainty or represent annual seasonal means.
4. **Actual observations, different physical turbines.** UCI #551 contains 36733 measured records from one turbine; the held-out TEY regression is an empirical statistical workflow. The separate SMART-GTPP source contains 7893 measured observations; conditional pressure-unit and temperature/power comparisons are exploratory observational consistency checks. Neither provides a turbine-identical calibrated comparison of absolute net power and heat rate.
5. **Pass-off mathematics.** A conditional fuel-power correction with analytic/cross-checked instrument covariance Jacobian is software/numerical evidence only. No real measured pass-off or guarantee conclusion is available.
6. **GUI and extended modules.** Windows compilation is checked. Human interaction, export quality, clean-machine runtime and live OPC UA acceptance are not.

The machine-readable, CI-checked authoritative capability inventory is [capability_evidence.json](capability_evidence.json), including each evidence type, exact source path, test, CI evidence, outstanding issue and limitation. A passing inventory check only establishes these declared links and safety boundaries, not scientific accuracy.

## Concrete source audit findings

- The core solver computes turbine work from gas mass flow but compressor work from air mass flow. Its convenience field w_net_specific_J_kg is simply w_t - w_c; it must not be interpreted as electrical specific work on a single common mass basis, because turbine and compressor mass rates differ. Electrical specific power is calculated separately from net shaft/generator power divided by compressor inlet air flow. Consider deprecating/renaming this ambiguous diagnostic after a call-site review.
- The off-design treatment uses representative constant corrected-flow, quadratic map-efficiency penalties and heuristic surge/run-line parameters. These are model assumptions, not identified OEM maps; agreement of output ratios with their own identities is not independent map validation.
- A static local Markdown link scan already exists but does not check heading anchors, external URLs, rendered HTML/layout or figures. This audit does not claim those have been manually accepted.
- The previous measurement-readiness checker accepted complete headers as a “minimal complete measurement bundle” without reading any rows. This PR changes the gate to require nonempty, structurally valid required-field values with elementary numeric/time validation. It still NEVER grants physical validation merely from a plausible CSV or metadata flags.
- Historical checked-in output and neural weight files need source-to-figure and training-lineage review before citation. Existing CI evidence artifacts expire: obtain immutable, rights-cleared preservation for publication claims, and avoid treating a downloadable CI artifact as permanent archival.
- The previously released Zenodo beta DOI identifies its immutable October source snapshot; later main-branch scientific workflows cannot be retroactively attributed to the archived beta.

## Issue-by-issue acceptance reconciliation

| Issue | Evidence now present | Conditions still open | Decision |
|---|---|---|---|
| [#12 P0](https://github.com/abhijith-sivaprasadan/thermotwin/issues/12) | Feature-status inventory, local link checker, targeted source contracts, regression CI | Full module-wide model and output-figure inspection, source/weight lineage, GUI interaction and physical validity | OPEN |
| [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13) | Fixed ISO flange, core ratio/identity tests, real reanalysis boundary and 672-hour study | Matched equipment-specific measured flange/power/fuel data, map and humidity model, quantified form/boundary uncertainty | OPEN |
| [#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14) | Conditional Jacobian/precision/bias covariance tests | Genuine calibrated test windows, correction-factor uncertainty, contract/guarantee criteria | OPEN |
| [#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15) | 36733-row one-turbine UCI dataset and untouched 2014–15 statistical holdout | Ground-truth faults/maintenance and actual multi-engine population, exact time spacing and industrial detector calibration | OPEN |
| [#16](https://github.com/abhijith-sivaprasadan/thermotwin/issues/16) | CI dossier, two independent research artifacts, seasonal curves, source-ledger, declared limitations | Integrate final report references and permanent artifact snapshots; turbine-identical physical validation still missing | OPEN |
| [#19](https://github.com/abhijith-sivaprasadan/thermotwin/issues/19) | Open-Meteo source/model/units/UTC/replay tests and ERA5 windows | Independent site station CSV feed/coverage, live forecast current end-to-end acceptance, legal usage review | OPEN |

We deliberately leave all six open: checking software paths or preserving a research artifact does not satisfy missing measured-field requirements. No checkbox is treated as complete without matching code, CI results and provenance.

## Release-readiness boundary

See [the untagged research release candidate](RESEARCH_RELEASE_CANDIDATE_2026-11-11.md). The dated acceptance manifest is itself generated as a GitHub Actions artifact using the exact source revision and the checked machine-readable inventory. This is **not a release**, DOI, plant calibration, certification, GUI distribution or contractual assessment.

## How to reproduce the audit

From the root of the exact target commit:

~~~sh
python -m unittest scripts.test_check_gt_validation_readiness scripts.test_capability_evidence -v
python scripts/check_repository_links.py
python scripts/check_capability_evidence.py --output build/release-readiness/research_release_evidence.json
~~~

Obtain the actual source-backed UCI, ERA5, SMART-GTPP and dossier outputs from the **same successful Actions run**; never substitute the synthetic unit-test fixtures for observations. Consult [the source-backed engineering dossier](REPRODUCIBLE_ENGINEERING_DOSSIER.md), [original measured-turbine audit](INDEPENDENT_MEASURED_TURBINE_EVIDENCE.md) and [release gate](RELEASE_GATE.md).
