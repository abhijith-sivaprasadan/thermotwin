!> @file test_compressor.f90
!> @brief Unit tests for the compressor model.
!>
!> Verifies the isentropic limit, the efficiency penalty, and the analytic
!> outlet temperature for the canonical PR=15 case. Uses `error stop` on
!> failure so `fpm test` (or build.sh --tests) reports a non-zero exit code.
program test_compressor
    use precision_kinds, only: dp
    use compressor, only: solve_compressor
    use fluid_properties, only: set_property_model, PROP_CONSTANT
    implicit none
    real(dp) :: T2, P2, wc
    integer :: failures
    failures = 0

    call set_property_model(PROP_CONSTANT)

    ! Canonical case: 288.15 K, 1 atm, PR 15, eta 0.86 -> T2 ~ 679.5 K.
    call solve_compressor(288.15_dp, 101325.0_dp, 15.0_dp, 0.86_dp, T2, P2, wc)
    call expect_near("T2 (PR15, eta0.86)", T2, 679.5_dp, 2.0_dp, failures)
    call expect_near("P2 = P1*PR", P2, 101325.0_dp*15.0_dp, 1.0_dp, failures)
    call expect_true("compressor work positive", wc > 0.0_dp, failures)

    ! Ideal compressor (eta = 1) must give a lower outlet temperature than a
    ! real one for the same pressure ratio.
    block
        real(dp) :: T2_ideal, P2i, wci
        call solve_compressor(288.15_dp, 101325.0_dp, 15.0_dp, 1.0_dp, T2_ideal, P2i, wci)
        call expect_true("ideal T2 < real T2", T2_ideal < T2, failures)
    end block

    call finish("test_compressor", failures)
contains
    include "test_assert.inc"
end program test_compressor
