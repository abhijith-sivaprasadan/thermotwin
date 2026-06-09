!> @file test_combustor.f90
!> @brief Unit tests for the combustor energy balance and pressure loss.
program test_combustor
    use precision_kinds, only: dp
    use combustor, only: solve_combustor
    use fluid_properties, only: set_property_model, PROP_CONSTANT, cp_air_at, cp_gas_at
    implicit none
    real(dp) :: P3, f, q_air
    integer :: failures
    failures = 0

    call set_property_model(PROP_CONSTANT)

    ! Canonical case: T2 ~ 679.5 K, T3 = 1400 K, eta 0.98, LHV 50 MJ/kg.
    call solve_combustor(679.5_dp, 1.50e6_dp, 1400.0_dp, 0.98_dp, 0.03_dp, 50.0e6_dp, &
                         P3, f, q_air)
    call expect_near("fuel-air ratio", f, 0.0195_dp, 0.0010_dp, failures)
    call expect_near("combustor dP applied", P3, 1.50e6_dp*0.97_dp, 1.0_dp, failures)
    call expect_true("fuel-air ratio positive", f > 0.0_dp, failures)

    ! Energy-balance closure: reconstruct f from the rigorous balance and check
    ! it matches the model's f to tight tolerance.
    block
        real(dp) :: cp_a, cp_g, f_check
        cp_a = cp_air_at(679.5_dp)
        cp_g = cp_gas_at(1400.0_dp)
        f_check = (cp_g*1400.0_dp - cp_a*679.5_dp) / (0.98_dp*50.0e6_dp - cp_g*1400.0_dp)
        call expect_near("energy-balance closure", f, f_check, 1.0e-9_dp, failures)
    end block

    ! Hotter firing temperature must require more fuel.
    block
        real(dp) :: P3b, fb, qb
        call solve_combustor(679.5_dp, 1.50e6_dp, 1500.0_dp, 0.98_dp, 0.03_dp, 50.0e6_dp, &
                             P3b, fb, qb)
        call expect_true("higher TIT -> more fuel", fb > f, failures)
    end block

    call finish("test_combustor", failures)
contains
    include "test_assert.inc"
end program test_combustor
