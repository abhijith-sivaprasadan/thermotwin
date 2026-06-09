# Governing Equations

Every equation implemented in the solver, with symbols defined. Station numbers
follow `theory.md`: 1 = compressor inlet, 2 = compressor outlet, 3 = turbine
inlet, 4 = exhaust. SI units throughout (K, Pa, kg/s, J, W) unless noted.

## Nomenclature

| Symbol | Meaning | Unit |
|--------|---------|------|
| `T`, `P` | temperature, pressure | K, Pa |
| `cp` | specific heat at constant pressure | J/(kg·K) |
| `gamma` (γ) | ratio of specific heats `cp/cv` | – |
| `R` | specific gas constant | J/(kg·K) |
| `PR` | compressor pressure ratio | – |
| `eta_c`, `eta_t` | compressor, turbine isentropic efficiency | – |
| `eta_b` | combustion efficiency | – |
| `eta_mech`, `eta_gen` | mechanical, generator efficiency | – |
| `f` | fuel-air ratio `mdot_fuel / mdot_air` | – |
| `LHV` | fuel lower heating value | J/kg |
| `mdot_a`, `mdot_g`, `mdot_f` | air, gas, fuel mass flow | kg/s |
| `w` | specific work | J/kg |
| subscript `s` | isentropic (ideal) value | – |

Air-side properties (`cp_a`, `γ_a`) are used through the compressor; hot-gas
properties (`cp_g`, `γ_g`) are used through the combustor and turbine.

## 1. Inlet (station 1)

The inlet duct/filter is adiabatic (no total-temperature change) and imposes a
fractional total-pressure loss `k_in`:

```
T1 = T_ambient
P1 = P_ambient * (1 - k_in)
```

## 2. Compressor (1 → 2)

Isentropic exponent `m_a = (γ_a - 1) / γ_a`. Ideal (isentropic) outlet
temperature for pressure ratio `PR`:

```
T2s = T1 * PR^(m_a)
```

Actual outlet temperature using the isentropic efficiency (the real machine
needs more temperature rise than the ideal for the same pressure rise):

```
T2 = T1 + (T2s - T1) / eta_c
P2 = P1 * PR
```

Specific work absorbed by the compressor (per kg of air):

```
w_c = cp_a * (T2 - T1)
```

## 3. Combustor (2 → 3)

The fuel-air ratio follows from a combined mass-and-energy balance on the
combustor control volume. Conserving energy while adding fuel mass `mdot_f`:

```
mdot_a * cp_a * T2  +  mdot_f * eta_b * LHV  =  (mdot_a + mdot_f) * cp_g * T3
```

Dividing through by `mdot_a` and writing `f = mdot_f / mdot_a`:

```
cp_a * T2 + f * eta_b * LHV = (1 + f) * cp_g * T3
```

Solving for `f`:

```
        cp_g * T3  -  cp_a * T2
f  =  ---------------------------
       eta_b * LHV  -  cp_g * T3
```

This **rigorous form** (rather than the common `q = cp·(T3 − T2)` shortcut)
correctly accounts for the fuel mass that subsequently flows through the
turbine. The combustor imposes a fractional pressure loss `k_cc`:

```
P3 = P2 * (1 - k_cc)
```

`T3` is the turbine-inlet temperature (firing temperature, TIT) and is a
prescribed input.

## 4. Turbine (3 → 4)

The turbine expands from `P3` to the exhaust pressure `P4`. For a simple cycle
exhausting to atmosphere through a diffuser/stack with back-pressure loss
`k_ex`:

```
P4 = P_ambient * (1 + k_ex)
```

Isentropic exponent `m_g = (γ_g - 1) / γ_g`. Ideal exhaust temperature:

```
T4s = T3 * (P4 / P3)^(m_g)        (note P4/P3 < 1, so T4s < T3)
```

Actual exhaust temperature using turbine isentropic efficiency (the real machine
extracts less work, so it runs hotter than ideal):

```
T4 = T3 - eta_t * (T3 - T4s)
```

Specific work delivered by the turbine (per kg of gas):

```
w_t = cp_g * (T3 - T4)
```

## 5. Mass flows

The compressor handles air only; the turbine handles air plus fuel:

```
mdot_f = mdot_a * f
mdot_g = mdot_a * (1 + f)
```

## 6. Shaft, generator and plant power

Component powers:

```
P_compressor = mdot_a * w_c
P_turbine    = mdot_g * w_t
```

Net shaft power after mechanical (bearing/windage) losses, then generator
conversion, then auxiliary loads (fraction `k_aux`):

```
P_shaft = (P_turbine - P_compressor) * eta_mech
P_gross = P_shaft * eta_gen
P_net   = P_gross * (1 - k_aux)
```

## 7. Heat input, efficiency, heat rate

Fuel chemical power (LHV basis), thermal efficiency, and heat rate:

```
Q_fuel       = mdot_f * LHV
eta_thermal  = P_net / Q_fuel
heat_rate    = 3600 / eta_thermal          [kJ/kWh]    (1 kWh = 3600 kJ)
```

## 8. Exhaust energy

Sensible energy in the exhaust above the ISO reference temperature
`T_ref = 288.15 K`, evaluated with hot-gas `cp`:

```
Q_exhaust = mdot_g * cp_g * (T4 - T_ref)
```

## 9. Degradation mapping

A degradation set perturbs the clean inputs (see `degradation.f90`):

```
eta_c'      = eta_c  - delta_eta_compressor
mdot_a'     = mdot_a * (1 - delta_mdot_fraction)
eta_t'      = eta_t  - delta_eta_turbine
k_cc'       = k_cc   + delta_dP_combustor
```

The cycle is then re-solved with the primed inputs.

## 10. Transient thermal (lumped capacitance)

A single hot-section metal node of thermal mass `m·cp` (`C`), gas-side
conductance `hA`, and ambient-loss conductance `UA`:

```
C * dT_metal/dt = hA * (T_gas - T_metal) - UA * (T_metal - T_ambient)
```

Integrated with explicit Euler or classical RK4. The analytic steady state
(used as a unit-test oracle) is the conductance-weighted mean:

```
T_metal(infinity) = (hA * T_gas + UA * T_ambient) / (hA + UA)
```

## 11. Sensor (measurement) model

For a true value `x_true`, a channel with bias `b`, drift rate `d` (per hour),
elapsed time `h` hours, and noise standard deviation `sigma`:

```
x_measured = x_true + b + d * h + N(0, sigma)
```

`N(0, sigma)` is a zero-mean Gaussian sample (Box–Muller).

## 12. Uncertainty propagation

**Monte Carlo.** Draw `N` realisations of the boundary conditions from their
sensor distributions, re-solve the cycle each time, and report the sample mean,
standard deviation, and 2.5 / 97.5 percentiles of each KPI.

**Bias sensitivity.** For a channel perturbed by `±b`, the symmetric
finite-difference sensitivity of a KPI `y` is:

```
dy ≈ 0.5 * ( y(x + b) - y(x - b) )
```

## 13. Inverse diagnostics

Given measured observations, find the degradation set `d` minimising a weighted
sum of squared **fractional** residuals (fractional, so unit scales do not bias
the fit):

```
J(d) = w_P  * ((P_model  - P_meas ) / P_meas )^2
     + w_T4 * ((T4_model - T4_meas) / T4_meas)^2
     + w_mf * ((mf_model - mf_meas) / mf_meas)^2
     + w_T2 * ((T2_model - T2_meas) / T2_meas)^2
```

minimised by a coarse 4-D grid search followed by coordinate-descent
refinement. The choice of weights is discussed in
`validation_and_uncertainty.md`.
