!> @file test_turbine.f90
!> @brief Unit tests for the turbine expansion model.
program test_turbine
    use precision_kinds, only: dp
    use turbine, only: solve_turbine
    use fluid_properties, only: set_property_model, PROP_CONSTANT
    implicit none
    real(dp) :: T4, wt
    integer :: failures
    failures = 0

    call set_property_model(PROP_CONSTANT)

    ! Canonical case: T3=1400 K expanding 1.474 MPa -> ~101 kPa, eta 0.89.
    call solve_turbine(1400.0_dp, 1.4743e6_dp, 101325.0_dp, 0.89_dp, T4, wt)
    call expect_near("T4 (canonical expansion)", T4, 792.0_dp, 6.0_dp, failures)
    call expect_true("turbine work positive", wt > 0.0_dp, failures)
    call expect_true("exhaust cooler than inlet", T4 < 1400.0_dp, failures)

    ! Ideal turbine (eta=1) extracts more work -> colder exhaust than real one.
    block
        real(dp) :: T4_ideal, wt_ideal
        call solve_turbine(1400.0_dp, 1.4743e6_dp, 101325.0_dp, 1.0_dp, T4_ideal, wt_ideal)
        call expect_true("ideal exhaust colder", T4_ideal < T4, failures)
        call expect_true("ideal work greater", wt_ideal > wt, failures)
    end block

    call finish("test_turbine", failures)
contains
    include "test_assert.inc"
end program test_turbine
