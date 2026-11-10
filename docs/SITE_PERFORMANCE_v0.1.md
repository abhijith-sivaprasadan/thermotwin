# Site performance correction — first implemented research demonstration

**Status:** Experimental research method, with ISO 3977-2 flange-reference boundary repaired after initial release (not an OEM predictor).
**Scope:** Simple-cycle, **full-load** ISO-to-site correction using one fixed
reference hardware calibration. This is a modest subset of
[TTF-PE-PMP-001](TTF_PE_MASTER_PLAN_v1.0.md), issue [#13](https://github.com/abhijith-sivaprasadan/thermotwin/issues/13).

## Usage

Build `make` then run:

```bash
python scripts/generate_site_cases.py --output cases/site_sweep.csv
./thermotwin site cases/site_iso_flange_reference.csv cases/site_sweep.csv output/results_site.csv
python scripts/test_site_pipeline.py --executable ./thermotwin
```

All 26 cases are **synthetic** representative examples and do not describe any
Siemens Energy turbine, its compressor map, reference guarantees, actual
operating data, or installed customer site. Existing core `InputCase` values
are demonstration constants; the base case is a roughly 30 MW-class machine
without a licensed performance map.

The reference is the single row in `cases/site_iso_flange_reference.csv`: 288.15 K,
101325 Pa, zero reference inlet/exhaust pressure losses and 60% RH (the latter is stored but **not physically modelled**). This establishes **compressor-inlet flange total pressure P1 = 101325 Pa** and **turbine-exhaust flange static pressure P4 = 101325 Pa** within the simplified pressure-boundary model.
`site_sweep.csv` varies ambient temperature, absolute pressure, filter/inlet
losses, exhaust backpressure and an illustrative scalar LHV. It does not
calculate altitude independently, gas mixture physics or humidity response.

## Numerical correction convention

Let `q_ref` and `q_site` denote outputs from the same off-design solver
with the **same turbine reference flow constant**, base mass-flow geometry,
fixed compressor/turbine component settings and firing setpoint:

- Power derating `D = P_site/P_ref`.
- Power reference correction `C_P = P_ref/P_site = 1/D`.
- Heat-rate correction `C_HR = HR_ref/HR_site` (**not** presumed to equal `C_P`).
- Exhaust mass-flow correction `C_m = m_ref/m_site`.
- Exhaust temperature offset `Delta_T = T_exh_ref - T_exh_site` in K.

These are model-derived **ratios/offsets**, not empirical engine-family
correction maps. No measurement data or contractual guarantee is involved.

The ISO reference deck uses zero inlet and exhaust losses **at the defined intake and exhaust flanges**. A site case separately applies its actual or assumed upstream inlet-loss fraction and exhaust backpressure using the simplified model: `P1 = ambient_P_Pa × (1 - inlet_loss)` and `P4 = ambient_P_Pa × (1 + exhaust_loss)`. Site loss values must come from documented test/engineering conditions; weather API alone does not supply them. The old baseline `cases/design_point.csv` retains 1% inlet and 2% exhaust losses for historical educational cycle verification but is now explicitly **rejected as an ISO flange reference**. A correct reference boundary is not evidence of an industrially calibrated compressor map or test-code compliance.

## Input and validity

- All site inputs use the current strict 18-column `InputCase` schema.
- Reference CSV must hold exactly one `clean` ISO machine.
- Site rows may vary ambient temperature (250 to 325 K), pressure
  (75 to 110 kPa), inlet and exhaust fractional losses (0–0.20),
  and LHV scalar (35–60 MJ/kg), within an illustrative envelope.
- Component efficiencies, machine base air flow, pressure ratio, firing
  temperature, combustor pressure loss and shaft settings must match the
  reference machine. Numerical ratios cannot be used to disguise a changed
  hardware reference.
- Site RH must equal the reference 0.60 assumed value; if it changes, the
  solver rejects the correction because wet-air physics is not implemented.
  This **does not** mean that 60% relative humidity is equivalent to dry air.
- Invalid cases are recorded as `valid=0` with a reason; the CLI returns
  a nonzero exit if any case is invalid. The invalid row's numeric fields
  must not be used.

The output CSV exposes reference and site power, heat rate, exhaust mass flow,
exhaust temperature, correction factors and status. Units are embedded in
column names; all rows are generated from a deterministic source fixture.

## Verification and boundaries

`test/test_site_performance.f90` and `scripts/test_site_pipeline.py`
cover ISO identity; ambient-pressure and hot-day trends; extra inlet
and exhaust losses; fixed reference outputs across site sweeps; correction
round trips; 26 scenario cases; and rejections for modified humidity,
hardware and pressure out of the declared envelope.

**Not verified:** manufacturer-specific performance, atmospheric moisture,
detailed composition, real compressor/turbine maps, test-stand correction,
test uncertainty, and any contract guarantee or standards compliance.
Gas-turbine performance correction is informed by concepts from
ISO 3977-2:2023 and ASME PTC 22-2023 but this educational prototype is
not compliant with or validated to either standard.

This initial module is the prerequisite, not a substitute, for the
pass-off-test and production-population workstreams tracked by issues
[#14](https://github.com/abhijith-sivaprasadan/thermotwin/issues/14) and
[#15](https://github.com/abhijith-sivaprasadan/thermotwin/issues/15).
