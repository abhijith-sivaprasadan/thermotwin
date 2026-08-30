!> @file test_exergy_sobol.f90
!> @brief Revamp 7.0 P4 — global (Sobol) sensitivity of the exergy KPIs.
!>
!> Rational efficiency depends only on fuel flow in the exergy accounting, so the
!> Sobol decomposition must isolate fuel flow as the dominant driver — a clean
!> ground-truth check on the variance attribution. Total destruction, driven by
!> several inputs, must give finite bounded indices.
program test_exergy_sobol
    use precision_kinds, only: dp
    use engine_core
    use exergy_sobol, only: SobolResult, run_exergy_sobol, SOBOL_NIN
    implicit none

    integer :: failures
    failures = 0

    block
        type(GridState)   :: st
        type(SobolResult) :: r
        real(dp) :: sig(SOBOL_NIN)
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
        sig = [3.0_dp, 25.0_dp, 15.0_dp, 0.08_dp, 0.5_dp]

        ! eta_II depends only on fuel flow (input 4) -> Sobol must isolate it
        call run_exergy_sobol(st, sig, 800, 1, r)
        call expect_true("Sobol: variance positive", r%var_Y > 0.0_dp, failures)
        call expect_true("Sobol: fuel flow dominates eta_II", r%dominant == 4, failures)
        call expect_true("Sobol: fuel total-effect index near 1", r%ST(4) > 0.8_dp, failures)
        call expect_true("Sobol: non-fuel inputs negligible for eta_II", &
            max(r%ST(1), r%ST(2), r%ST(3), r%ST(5)) < 0.2_dp, failures)

        ! total destruction is driven by several inputs -> finite, bounded indices
        call run_exergy_sobol(st, sig, 800, 2, r)
        call expect_true("Sobol: destruction variance positive", r%var_Y > 0.0_dp, failures)
        call expect_true("Sobol: indices finite and bounded", &
            minval(r%ST) > -0.2_dp .and. maxval(r%ST) < 1.3_dp, failures)
    end block

    call finish("exergy_sobol", failures)

contains

    include "test_assert.inc"

end program test_exergy_sobol
