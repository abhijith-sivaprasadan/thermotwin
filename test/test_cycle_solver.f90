!> @file test_cycle_solver.f90
!> @brief Integration tests for the full cycle solver, including an overall
!>        energy-balance check (fuel energy in = net work + losses + exhaust).
program test_cycle_solver
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult
    use cycle_solver, only: solve_cycle
    use fluid_properties, only: set_property_model, PROP_CONSTANT, &
        h_air_sensible_J_kg, h_gas_sensible_J_kg
    use constants, only: W_PER_MW
    implicit none
    type(InputCase) :: ic
    type(CycleResult) :: r
    integer :: failures
    failures = 0

    call set_property_model(PROP_CONSTANT)

    ! Lossless verification case (matches docs/verification.md hand calc).
    ic%inlet_pressure_loss = 0.0_dp
    ic%exhaust_pressure_loss = 0.0_dp
    r = solve_cycle(ic)

    call expect_true("solution converged", r%converged, failures)
    call expect_near("net power",  r%net_power_MW, 30.4_dp, 1.5_dp, failures)
    call expect_near("efficiency", r%thermal_efficiency, 0.312_dp, 0.010_dp, failures)
    call expect_near("T2", r%T2_K, 679.5_dp, 3.0_dp, failures)
    call expect_near("T4", r%T4_K, 792.0_dp, 6.0_dp, failures)

    ! Ordering of station temperatures must be physical.
    call expect_true("T1 < T2 < T3", (r%T1_K < r%T2_K) .and. (r%T2_K < r%T3_K), failures)
    call expect_true("T4 between ambient and T3", &
                     (r%T4_K > r%T1_K) .and. (r%T4_K < r%T3_K), failures)

    ! Turbine must out-produce the compressor (positive net shaft work).
    call expect_true("turbine power > compressor power", &
                     r%power_turbine_MW > r%power_compressor_MW, failures)

    ! Heat rate consistency: HR = 3600 / eta.
    call expect_near("heat-rate consistency", &
                     r%heat_rate_kJ_kWh, 3600.0_dp/r%thermal_efficiency, 1.0e-3_dp, failures)

    ! Global first-law closure (rates, W). All energy streams are summed
    ! independently on the "in" and "out" side of the plant boundary and the
    ! relative residual epsilon_E = (E_in - E_out)/E_in is required to be
    ! tiny -- this is an actual closure check, not just a plausibility band.
    !
    !   E_in  = mdot_air*h_air(T1) + mdot_fuel*LHV        (sensible air-in + fuel chemical energy)
    !   E_out = mdot_gas*h_gas(T4)                        (exhaust sensible energy)
    !         + (1-eta_combustor)*mdot_fuel*LHV           (combustor incomplete-combustion loss)
    !         + mechanical_loss + generator_loss + auxiliary_load   (shaft-train losses)
    !         + net_power                                 (useful electrical output)
    !
    ! The mechanical/generator/auxiliary split follows shaft_generator.f90's
    ! own definitions exactly (P_shaft = (P_turb-P_comp)*eta_mech, P_gross =
    ! P_shaft*eta_gen, P_net = P_gross*(1-aux_frac)), so this reproduces the
    ! plant's own accounting rather than an independent approximation. For
    ! the CONSTANT property model (used here) h_air/h_gas are exactly cp*T,
    ! matching the cp*(T2-T1)/(T3-T4) work formulas used by the compressor
    ! and turbine, so the balance should close to floating-point precision.
    block
        real(dp) :: e_in_W, e_out_W, epsilon_E
        real(dp) :: power_turb_W, power_comp_W, shaft_power_W, gross_power_W, net_power_W
        real(dp) :: mech_loss_W, gen_loss_W, aux_load_W, combustor_loss_W
        real(dp), parameter :: EPS_TOL = 1.0e-6_dp   ! tight closure tolerance (<< 1%)

        e_in_W = ic%mdot_air_kg_s * h_air_sensible_J_kg(r%T1_K) + r%fuel_flow_kg_s * ic%LHV_J_kg

        power_turb_W = r%power_turbine_MW * W_PER_MW
        power_comp_W = r%power_compressor_MW * W_PER_MW
        shaft_power_W = (power_turb_W - power_comp_W) * ic%eta_mechanical
        gross_power_W = shaft_power_W * ic%eta_generator
        net_power_W   = gross_power_W * (1.0_dp - ic%auxiliary_load_fraction)

        mech_loss_W      = (power_turb_W - power_comp_W) - shaft_power_W
        gen_loss_W       = shaft_power_W - gross_power_W
        aux_load_W       = gross_power_W - net_power_W
        combustor_loss_W = (1.0_dp - ic%eta_combustor) * r%fuel_flow_kg_s * ic%LHV_J_kg

        e_out_W = r%mdot_gas_kg_s * h_gas_sensible_J_kg(r%T4_K) + combustor_loss_W + &
                  mech_loss_W + gen_loss_W + aux_load_W + net_power_W

        epsilon_E = (e_in_W - e_out_W) / e_in_W

        call expect_true("net_power_W reproduces solver's net_power_MW", &
            abs(net_power_W - r%net_power_MW * W_PER_MW) < 1.0_dp, failures)
        call expect_true("first-law closure |epsilon_E| within tight tolerance", &
            abs(epsilon_E) < EPS_TOL, failures)
        write(*, '(A,ES12.4)') "  [info] energy-balance residual epsilon_E = ", epsilon_E
    end block

    call finish("test_cycle_solver", failures)
contains
    include "test_assert.inc"
end program test_cycle_solver
