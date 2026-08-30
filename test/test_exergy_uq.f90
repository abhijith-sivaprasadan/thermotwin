!> @file test_exergy_uq.f90
!> @brief Revamp 7.0 P4 — uncertainty quantification of the exergy analysis.
!>
!> Verifies that zero input uncertainty collapses to the deterministic result,
!> that realistic 1-sigma inputs produce a meaningful spread, that the 95%
!> interval brackets the mean, and that the Monte-Carlo mean stays near the
!> deterministic value (no large bias).
program test_exergy_uq
    use precision_kinds, only: dp
    use engine_core
    use exergy_uq, only: ExergyUQ, run_exergy_uq
    implicit none

    integer :: failures
    failures = 0

    block
        type(GridState) :: st
        type(ExergyUQ)  :: r0, r1
        call engine_init(st)
        st%ambient_C      = 15.0_dp
        st%PR_op          = 15.0_dp
        st%TIT_actual_K   = 1400.0_dp
        st%exhaust_K      = 850.0_dp
        st%fuel_flow_kg_s = 1.5_dp
        st%h2_lhv_mj_kg   = 50.0_dp
        st%gas_power_MW   = 18.0_dp
        st%steam_power_MW = 15.0_dp
        st%plant_power_MW = 33.0_dp
        st%combined_cycle = .true.
        st%hrsg_stack_T_K = 380.0_dp

        ! Zero input uncertainty -> deterministic (no spread)
        call run_exergy_uq(st, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 0.0_dp, 400, r0)
        call expect_true("UQ: zero sigma -> ~zero eta spread", r0%eta_II_std < 1.0e-6_dp, failures)
        call expect_true("UQ: deterministic eta physical", &
            r0%eta_II_mean > 0.30_dp .and. r0%eta_II_mean < 0.70_dp, failures)

        ! Realistic 1-sigma uncertainties -> meaningful spread
        call run_exergy_uq(st, 3.0_dp, 25.0_dp, 15.0_dp, 0.08_dp, 0.5_dp, 3000, r1)
        call expect_true("UQ: input uncertainty -> eta spread", r1%eta_II_std > 1.0e-4_dp, failures)
        call expect_true("UQ: 95% interval brackets the mean", &
            r1%eta_II_lo95 < r1%eta_II_mean .and. r1%eta_II_mean < r1%eta_II_hi95, failures)
        call expect_true("UQ: MC mean near deterministic", &
            abs(r1%eta_II_mean - r0%eta_II_mean) < 0.05_dp, failures)
        call expect_true("UQ: combustor destruction has spread", r1%dest_comb_std > 0.0_dp, failures)
        call expect_true("UQ: total destruction has spread", r1%dest_total_std > 0.0_dp, failures)
    end block

    call finish("exergy_uq", failures)

contains

    include "test_assert.inc"

end program test_exergy_uq
