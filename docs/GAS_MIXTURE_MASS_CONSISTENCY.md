# Fixed combustion-product mixture: molecular-mass and gas-constant consistency

**Scope:** reduced-order, ideal-gas, *fixed-composition* hot-gas surrogate in the **variable-property** branch. This is a first-principles algebra/units repair, **not** a measurement-derived engine calibration or a new property standard.

## Original inconsistency

Earlier the variable-property mixture's molar heat capacity and sensible enthalpy were calculated from an assumed *molar* blend, then divided by a separately fixed molar mass of 0.03110 kg/mol. That fixed value does not correspond to the documented species fractions. The variable-property heat-capacity ratio also used the *constant-property* reference gas constant 287.80 J/(kg·K), making the implied molecular mass and ideal-gas relation inconsistent.

## Engineering model and derivation

The current four-species approximation uses \`x_N2=0.735\`, \`x_CO2=0.085\`, \`x_H2O=0.115\`, and \`x_O2=0.065\` (molar fractions; exactly sum to one). It is **a declared illustrative combustion-product composition, not a measured sample from a Siemens turbine**. Let each species molar mass be \`M_i\`; then:

\[
M_\mathrm{mix} = \sum_i x_i M_i =
0.028482338\ \mathrm{kg/mol},
\qquad
R_\mathrm{mix} = R_u/M_\mathrm{mix}.
\]

With the same species polynomial functions for molar \`c_p,i\` and molar sensible \`h_i\`:

\[
c_{p,\mathrm{mix}}(T)=\frac{\sum_i x_i c_{p,i}(T)}{M_\mathrm{mix}},
\quad
h_\mathrm{mix}(T)=\frac{\sum_i x_i h_i(T)}{M_\mathrm{mix}},
\quad
\gamma_\mathrm{mix}(T)=\frac{c_{p,\mathrm{mix}}}{c_{p,\mathrm{mix}}-R_\mathrm{mix}}.
\]

A separate mathematical test computes \`R_u/M_mix\` independently of the implementation and requires it to agree with \`c_p(1-1/gamma)\` at 1200 K. A centered finite-difference test checks that \`dh/dT=c_p\` away from the 1000 K correlation splice. The independent **constant-property** textbook/hand reference is intentionally unchanged.

## Consequences for reportable results

The correction changes hot-gas variable-property \`c_p\`, \`h\`, \`gamma\`, turbine-specific work, electrical output, and coupled plant/grid state. Numerical snapshots fitted to the earlier inconsistent property mixture must **not** be preserved as independent physical benchmarks; test new values against the governing equations and independently defined source boundaries, not by relabeling arbitrary empirical OEM performance. Part-load controls and artificial scenario stress cases remain software demonstrations.

The existing air-side 79/21 N2/O2 approximation uses a separate named nominal air molar mass and \`R_AIR\`; atmospheric argon and other species, humidity and varying product chemistry are not resolved here. Full thermo-chemical state matching would additionally require fuel composition, air/fuel ratio, product species balance, pressure-dependent properties where applicable, validated maps and OEM operating records.

As before, the steam-water helper functions are **not** an IAPWS-IF97 implementation. Nothing in this repair qualifies ThermoTwin-F for a contractual pass-off/guarantee, and regression tests alone cannot validate accuracy against an industrial gas turbine.
