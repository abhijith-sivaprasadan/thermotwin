# Verification

**Verification** answers the question *"does the code correctly solve the
equations it claims to solve?"* It is distinct from **validation** (*"do those
equations match a real engine?"*), which this project does **not** claim — see
`validation_and_uncertainty.md`.

The verification strategy here is an **independent hand calculation**: the
design point is worked out by hand below, and the `selftest` mode reproduces
those numbers to tight tolerances. The unit tests add component-level and
property-level checks on top.

## Verification case

A representative ~30 MW-class simple-cycle machine, with inlet and exhaust
pressure losses set to zero so the arithmetic is clean and independently
checkable:

| Input | Value |
|-------|-------|
| Ambient temperature `T1` | 288.15 K |
| Ambient pressure `P1` | 101 325 Pa |
| Pressure ratio `PR` | 15 |
| Compressor efficiency `eta_c` | 0.86 |
| Turbine-inlet temperature `T3` | 1400 K |
| Combustion efficiency `eta_b` | 0.98 |
| Combustor pressure loss `k_cc` | 0.03 |
| Fuel LHV | 50 × 10⁶ J/kg |
| Turbine efficiency `eta_t` | 0.89 |
| Mechanical efficiency | 0.99 |
| Generator efficiency | 0.985 |
| Auxiliary load fraction | 0.02 |
| Air mass flow | 100 kg/s |
| `cp_a`, `γ_a` | 1004.5 J/(kg·K), 1.40 |
| `cp_g`, `γ_g` | 1148 J/(kg·K), 1.333 |

## Step-by-step hand calculation

**Compressor.** Exponent `m_a = (1.4 − 1)/1.4 = 0.2857`.

```
PR^m_a = 15^0.2857 = 2.168
T2s    = 288.15 * 2.168       = 624.7 K
T2     = 288.15 + (624.7 - 288.15)/0.86 = 679.5 K
w_c    = 1004.5 * (679.5 - 288.15)      = 393.1 kJ/kg
```

**Combustor.** Using the rigorous fuel-air balance:

```
cp_g*T3 = 1148 * 1400 = 1 607 200
cp_a*T2 = 1004.5 * 679.5 = 682 558
eta_b*LHV = 0.98 * 50e6 = 49 000 000

f = (1 607 200 - 682 558) / (49 000 000 - 1 607 200)
  = 924 642 / 47 392 800
  = 0.0195
```

**Turbine.** With zero exhaust loss, `P4 = 101 325 Pa`;
`P3 = 15 * 101 325 * (1 − 0.03) = 1.4743 × 10⁶ Pa`.
Exponent `m_g = (1.333 − 1)/1.333 = 0.2498`.

```
P4/P3   = 101 325 / 1 474 290 = 0.0687
(P4/P3)^m_g = 0.0687^0.2498   = 0.512
T4s     = 1400 * 0.512        = 716.8 K
T4      = 1400 - 0.89*(1400 - 716.8) = 792.0 K
w_t     = 1148 * (1400 - 792.0)      = 698.0 kJ/kg
```

**Powers.** `mdot_g = 100 * (1 + 0.0195) = 101.95 kg/s`.

```
P_compressor = 100   * 393.1 kJ/kg = 39.31 MW
P_turbine    = 101.95 * 698.0 kJ/kg = 71.16 MW
P_shaft = (71.16 - 39.31) * 0.99    = 31.53 MW
P_gross = 31.53 * 0.985             = 31.06 MW
P_net   = 31.06 * (1 - 0.02)        = 30.4 MW
```

**Efficiency and heat rate.**

```
mdot_f = 0.0195 * 100 = 1.95 kg/s
Q_fuel = 1.95 * 50e6  = 97.5 MW
eta_th = 30.4 / 97.5  = 0.312   (31.2%)
HR     = 3600 / 0.312 = 11 538 kJ/kWh
```

## Expected vs computed

Running `./thermotwin selftest` (or `fpm run -- selftest`) produces:

| Quantity | Hand calc | Code | Tolerance | Status |
|----------|----------:|-----:|----------:|:------:|
| `T2` [K] | 679.5 | 679.4 | ±3 | PASS |
| `T4` [K] | 792.0 | 792.3 | ±5 | PASS |
| fuel-air ratio | 0.0195 | 0.0195 | ±0.0010 | PASS |
| net power [MW] | 30.4 | 30.4 | ±1.5 | PASS |
| thermal efficiency | 0.312 | 0.3117 | ±0.010 | PASS |
| heat rate [kJ/kWh] | 11 538 | 11 549 | — | consistent |

The small residuals come from rounding in the hand calc (e.g. carrying
`15^0.2857` to four figures). The agreement confirms the solver implements the
equations in `equations.md` correctly.

## Sanity checks (physical plausibility)

The design point also passes the "does this look like a real simple-cycle gas
turbine?" smell test:

- **Thermal efficiency ~31%** sits squarely in the 30–40% band for simple-cycle
  industrial machines.
- **Exhaust temperature ~519 °C** is typical and high enough that bottoming a
  steam cycle (combined cycle) would make sense — consistent with reality.
- **Compressor absorbs ~55% of turbine output**, the well-known "back-work
  ratio" of gas turbines.

## Reproducing verification

```bash
./scripts/build.sh           # or: fpm build
./thermotwin selftest        # or: fpm run -- selftest
./scripts/run_tests.sh       # full unit-test suite + selftest
```

A non-zero exit code from any of these indicates a verification failure.
