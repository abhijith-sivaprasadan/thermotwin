# ThermoTwin-F — Assumptions & Limitations

A simulator is only useful if its boundaries are stated as clearly as its
results. This document lists every significant modelling assumption and the
limitations that follow. None of these are accidental — each is a deliberate
scoping choice for a transparent educational/portfolio tool, and each is a
natural avenue for future extension.

---

## Thermodynamic modelling

- **Cycle topology.** Single-shaft, open/simple Brayton cycle. There is no
  regeneration (recuperator), intercooling, or reheat. Combined-cycle bottoming
  is not modelled (though the exhaust-energy KPI indicates how much is available
  for it).

- **Specific heats.** The default property model uses constant `cp` and `γ`,
  with one set for the cold side (air) and one for the hot side (combustion
  gas). This is the classic "cold-air-standard with a hot-gas correction"
  approach. Real gas `cp(T)` rises with temperature; the included
  `PROP_VARIABLE` model captures this trend with simple linear fits but is not
  the default, so that the verification hand calculation remains exactly
  reproducible.

- **Working fluid composition.** The hot-gas properties are representative
  averages for lean combustion products; they are not recomputed from the
  actual fuel/air composition or equivalence ratio at each operating point.

- **Combustion.** The combustor is a lumped energy balance with a combustion
  efficiency `η_b`. There is no detailed chemical kinetics, no dissociation at
  high firing temperature, and therefore no NOx / CO / UHC emissions model.

- **Pressure losses.** Inlet, combustor, and exhaust pressure losses are
  prescribed fractional values, not computed from duct/burner geometry or
  corrected for flow.

---

## Off-design and component behaviour

- **No compressor or turbine maps.** Off-design operation is represented by
  changing boundary conditions (ambient, TIT, mass flow) and component
  efficiencies — *not* by matching on compressor/turbine performance maps with
  speed lines and surge/choke limits. This means the tool captures *trends*
  with ambient temperature, pressure ratio, and firing temperature correctly,
  but does not reproduce true map-constrained part-load behaviour or
  rotational-speed effects.

- **No turbine cooling air.** The turbine-inlet temperature is treated as the
  gas temperature entering the turbine. Real engines bleed compressor air to
  cool the hot section, which reduces effective expansion mass flow and changes
  the work balance. This is omitted.

- **Single equivalent stage per turbomachine.** The compressor and turbine are
  each modelled as one equivalent process with a lumped isentropic efficiency,
  not stage-by-stage.

- **No mechanical detail.** Bearing, windage, and seal losses are folded into a
  single mechanical efficiency. There is no rotordynamic or shaft-speed model.

---

## Transient model

- **Lumped capacitance.** The transient hot-section model is a single
  zero-dimensional metal node (one temperature, one thermal mass, one gas-side
  conductance, one ambient-loss conductance). It captures the characteristic
  thermal time constant and the qualitative lag between gas and metal
  temperature, but it is **not** a spatially resolved thermal or finite-element
  model and produces no thermal-stress or low-cycle-fatigue information.

- **Gas-temperature drive is prescribed.** The startup/ramp/shutdown gas-
  temperature schedules are simple prescribed profiles anchored to the steady
  exhaust temperature, not the output of a coupled dynamic engine model.

---

## Uncertainty and diagnostics

- **Demonstrative, not certified.** The Monte Carlo propagation and the
  deterministic bias-sensitivity study illustrate how measurement error maps
  into KPI uncertainty. The chosen 1-σ values are representative, not
  instrument-specific, and the analysis is **not** a formal ASME PTC 19.1
  uncertainty budget.

- **Explicit, hand-chosen objective.** The diagnostics inverse problem uses an
  explicit weighted least-squares objective with hand-chosen weights (see
  `validation_and_uncertainty.md`). It is not a Bayesian estimator and produces
  a point estimate, not a posterior distribution or confidence region.

- **Parameter degeneracy.** Compressor fouling (efficiency loss) and reduced
  swallowing capacity (mass-flow loss) have partially overlapping signatures in
  the observable KPIs. The solver can therefore trade one against the other to a
  small degree; recovered values are accurate to a few thousandths in the
  demonstration but should not be over-interpreted as independently identifiable
  to arbitrary precision.

---

## Validation status

- **Verified, not validated.** The self-test confirms the code reproduces an
  independent closed-form hand calculation (verification). The model has **not**
  been calibrated or validated against measured data from any specific
  commercial engine, and it is **not** compliant with ASME PTC 22 or ISO 2314
  acceptance-test standards. Absolute numbers should be read as physically
  plausible illustrations, not as predictions for a particular machine.

---

## Suggested extensions (roadmap)

Each limitation above is a clean next step:

1. Real-gas / `cp(T)` properties enabled by default (the hook already exists).
2. Compressor and turbine performance maps with map-based off-design matching.
3. Turbine cooling-air extraction and its effect on the work balance.
4. A simple NOx correlation as a first emissions output.
5. A multi-node or 1-D transient thermal model with thermal-stress output.
6. A Bayesian / Kalman formulation of the diagnostics problem with uncertainty
   on the recovered degradation parameters.
7. Combined-cycle bottoming (HRSG + steam turbine) using the exhaust stream.

## Off-design maps (revamp Phase 2)

* The compressor/turbine map behaviour is **representative, not
  engine-specific**: quadratic efficiency penalties, a power-law surge line
  with a 20% design margin, and a constant choked-turbine flow parameter.
  Real maps have speed lines, beta lines, and Reynolds corrections; none of
  that detail is claimed here.
* The transient surge excursion is a phenomenological model (PR rising with
  dispatch slew rate, capped at +25%) standing in for the real over-fueling
  dynamics of the fuel system and combustor volume.
* Variable inlet guide vanes are modelled purely as a corrected-flow
  multiplier (1.00 down to 0.70) with an efficiency penalty; actual stage
  re-matching is not computed.
* The live engine runs the VARIABLE (temperature-dependent cp) property
  model; the CONSTANT model remains the default elsewhere so the verified
  hand calculation is reproduced exactly by `thermotwin selftest`.
