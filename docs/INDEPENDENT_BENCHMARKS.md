# Independent benchmarks — methodology and scope

ThermoTwin-F is an educational, reduced-order gas-turbine/combined-cycle simulator. Internal unit tests and cross-implementation comparisons are **verification**, not validation with measurements.

## Implemented: CoolProp IF97 property comparison

The legacy `if97_*` routines in `src/fluid_properties.f90` use Antoine-type saturation calculations, simplified heat capacities, and approximate latent heats. They are **not IAPWS-IF97 implementations**. We keep these functions to avoid breaking the educational engine while making their errors measurable.

Independent reference: [CoolProp IF97::Water](https://coolprop.org/fluid_properties/IF97.html).

```bash
python -m pip install CoolProp==8.0.0 PyYAML==6.0.3
make property-reference-grid
python scripts/benchmark_if97.py --output build/if97_benchmark.json
python scripts/check_release_metadata.py
```

The sampler evaluates nine pressure values (0.1 to 200 bar) and exports saturation temperature, liquid/vapor enthalpy and entropy, and superheated enthalpy. Reference pressure, quality and temperature are passed to CoolProp using documented SI inputs. The superheat comparison is 50 K above **each implementation's own** saturation temperature, intentionally measuring an end-to-end state-definition discrepancy; it does not isolate a single enthalpy formula's error.

Output: a JSON file containing exact input pressures, reference values, approximate values, signed errors, MAE, maximum absolute errors, the source commit and the reference version. The benchmark CI job verifies that it runs and records its outputs; it does **not** impose a scientific-accuracy threshold or claim full IF97 compliance. Before a paper, specify application-driven thresholds and evaluate a larger grid including near-critical and superheated states.

## Separate benchmark fixture: TESPy Rankine study

The optional `scripts/tespy_rankine_reference.py` reproduces a **separate, specified** Rankine-cycle reference problem following TESPy's documented example (150 bar, 600°C, 10 kg/s, condenser at 0.1 bar, turbine isentropic efficiency 0.9, pump 0.75). Run with:

```bash
python -m pip install tespy==0.11.2
python scripts/tespy_rankine_reference.py --output build/tespy_rankine_reference.json
```

It is deliberately **not** claimed as a numerical validation of ThermoTwin's combined-cycle model. A publishable head-to-head comparison requires matching flow boundaries, HRSG configuration, cooling-system boundary conditions, pressure losses and efficiency definitions. Review its reference artifact separately before use in manuscripts.

## Next experimental studies (not incorporated)

Cantera for fuel/combustion consistency checks; ExerPy for exergy balances; independently published measurements for external validation. Do not combine unrelated models or copy third-party code without reviewing the exact license, attribution, and physical assumptions. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Evidence hierarchy

1. Analytic and internal code verification.
2. Independent reference-code comparison with published deviations.
3. Experimental or field-data validation with measured uncertainty.
4. Standards certification and industrial acceptance (not supported here).

Cross-code agreement can reveal implementation errors but does not establish performance prediction for a particular machine.
