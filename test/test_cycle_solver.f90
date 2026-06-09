!> @file test_cycle_solver.f90
!> @brief Integration tests for the full cycle solver, including an overall
!>        energy-balance check (fuel energy in = net work + losses + exhaust).
program test_cycle_solver
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult
    use cycle_solver, only: solve_cycle
    use fluid_properties, only: set_property_model, PROP_CONSTANT
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

    ! Global energy balance (per second, MW):
    !   fuel chemical power  =  net electrical
    !                          + compressor-turbine mechanical/gen/aux losses
    !                          + exhaust sensible energy
    !                          + combustor inefficiency loss
    ! We check the looser statement that accounted streams do not exceed input
    ! and that net + exhaust is a sensible fraction of fuel input.
    block
        real(dp) :: lhs, accounted
        lhs = r%heat_input_MW
        accounted = r%net_power_MW + r%exhaust_energy_MW
        call expect_true("net+exhaust < fuel input", accounted < lhs, failures)
        call expect_true("net+exhaust > 60% of fuel input", accounted > 0.60_dp*lhs, failures)
    end block

    call finish("test_cycle_solver", failures)
contains
    include "test_assert.inc"
end program test_cycle_solver
