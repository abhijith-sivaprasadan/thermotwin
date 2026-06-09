# Theory

This document explains the physical model behind ThermoTwin-F: what is being
simulated, the assumptions, and why each part exists. It is written to be read
top-to-bottom by someone with an undergraduate thermodynamics background.

## 1. The machine

ThermoTwin-F models a **single-shaft, open (simple) Brayton-cycle gas turbine**
— the thermodynamic core of an industrial gas turbine used for power
generation. Air is drawn in, compressed, mixed with fuel and burned, then
expanded through a turbine that drives both the compressor and an electrical
generator on a common shaft.

```
                 fuel
                  |
   air  ->  [Compressor] ==shaft== [Turbine]  ->  exhaust
   (1)         (2)   ->  [Combustor]  ->   (3)        (4)
                                  generator
```

Four thermodynamic **stations** are tracked:

| Station | Location                  |
|--------:|---------------------------|
| 1       | compressor inlet (ambient after the inlet duct) |
| 2       | compressor outlet         |
| 3       | turbine inlet (combustor outlet) — the firing temperature / TIT |
| 4       | turbine outlet (exhaust)  |

## 2. Modelling philosophy

The model is **zero-dimensional and steady** at its core: each component is a
control volume with inlet and outlet states, related by an energy balance and a
component efficiency. This is the standard "cycle deck" level of fidelity used
for first-order performance work, teaching, and feasibility studies.

Three deliberate choices shape the design:

1. **One data model.** A single `InputCase` describes a machine and an operating
   point; a single `CycleResult` holds every computed quantity. Every advanced
   feature (degradation, sensors, uncertainty, diagnostics) reads and writes
   these same structures, so the whole tool composes coherently instead of being
   a pile of disconnected scripts.

2. **Efficiencies, not maps.** Real compressors and turbines are characterised by
   performance *maps* (pressure ratio and efficiency as functions of corrected
   speed and mass flow). ThermoTwin-F instead uses isentropic efficiencies and
   prescribed boundary conditions. This is simpler, fully transparent, and
   adequate for the questions the tool asks; map-based matching is a documented
   future extension.

3. **Honesty about fidelity.** Constant specific heats, no cooling air, no real
   combustion chemistry. These are stated plainly (see
   `assumptions_limitations.md`) rather than hidden behind tuning factors.

## 3. The three "acts"

The features map onto the real workflow of a performance engineer across a
machine's life:

### Act 1 — Clean engine: design and off-design
What *should* the engine do? The cycle solver computes the design point, and the
sweep capability shows how power, efficiency, heat rate and exhaust temperature
respond to ambient temperature, pressure ratio, firing temperature and component
efficiencies. This is the baseline truth.

### Act 2 — Real engine: degraded and operated
What does the engine *actually* do after thousands of hours? The degradation
module applies four interpretable mechanisms — compressor fouling, mass-flow
reduction, turbine erosion, and combustor pressure-loss growth — and quantifies
the drift from baseline. The transient thermal module captures how hot-section
metal temperature lags the gas during starts, ramps and shutdowns.

### Act 3 — Measured engine: uncertain and diagnosed
What does the *instrumentation* tell us, and how confident can we be? The sensor
model corrupts the truth with bias, noise and drift. The uncertainty module
propagates measurement error into KPI uncertainty (Monte Carlo) and ranks which
measurement dominates (bias sensitivity). Finally, the diagnostics module solves
the **inverse problem**: given imperfect measurements of a degraded engine,
estimate *where* the degradation is.

## 4. Component models in brief

- **Compressor / Turbine** — isentropic temperature change from the pressure
  ratio and the ratio of specific heats, scaled by an isentropic efficiency.
- **Combustor** — fuel-air ratio from a mass-and-energy balance that conserves
  the fuel mass added to the stream, plus a fractional pressure loss.
- **Shaft / generator** — turbine power minus compressor power, reduced by
  mechanical, generator and auxiliary-load efficiencies to give net electrical
  output.

The exact equations, with every symbol defined, are in `equations.md`. A fully
worked numerical example that the code reproduces is in `verification.md`.

## 5. What the outputs mean

The headline KPIs are:

- **Net power [MW]** — electrical power exported at the generator terminals
  after auxiliaries.
- **Thermal efficiency [-]** — net electrical power divided by fuel chemical
  power (LHV basis).
- **Heat rate [kJ/kWh]** — fuel energy needed per unit of electricity; simply
  `3600 / efficiency`. Lower is better. This is the unit the power industry
  actually quotes.
- **Exhaust temperature [K]** — a key monitoring signal; degraded engines
  generally run hotter for the same load.

These are exactly the quantities a plant performance engineer tracks, which is
why they sit at the centre of the data model.
