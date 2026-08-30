!> @file test_thermo_limits.f90
!> @brief Revamp 7.0 P6 — theoretical efficiency limits / benchmarking.
!>
!> Checks the thermodynamic ordering: the achieved efficiency sits below the
!> Carnot ceiling, Curzon-Ahlborn and ideal-Brayton limits sit below Carnot, and
!> the fraction-of-Carnot is a sensible (0,1).
program test_thermo_limits
    use precision_kinds, only: dp
    use engine_core
    use thermo_limits, only: ThermoLimits, compute_thermo_limits
    implicit none

    integer :: failures
    failures = 0

    block
        type(GridState)    :: st
        type(ThermoLimits) :: r
        call engine_init(st)
        st%ambient_C      = 15.0_dp
        st%PR_op          = 15.0_dp
        st%TIT_actual_K   = 1400.0_dp
        st%exhaust_K      = 850.0_dp
        st%fuel_flow_kg_s = 1.5_dp
        st%h2_lhv_mj_kg   = 50.0_dp
        st%plant_power_MW = 33.0_dp
        call compute_thermo_limits(st, r)

        call expect_true("limits: Carnot in (0.70, 0.85)", &
            r%eta_carnot > 0.70_dp .and. r%eta_carnot < 0.85_dp, failures)
        call expect_true("limits: Curzon-Ahlborn below Carnot", &
            r%eta_curzon_ahlborn > 0.40_dp .and. r%eta_curzon_ahlborn < r%eta_carnot, failures)
        call expect_true("limits: ideal Brayton below Carnot", &
            r%eta_brayton_ideal > 0.0_dp .and. r%eta_brayton_ideal < r%eta_carnot, failures)
        call expect_true("limits: actual below Carnot ceiling", &
            r%eta_actual > 0.0_dp .and. r%eta_actual < r%eta_carnot, failures)
        call expect_true("limits: Carnot fraction in (0,1)", &
            r%carnot_fraction > 0.0_dp .and. r%carnot_fraction < 1.0_dp, failures)
    end block

    call finish("thermo_limits", failures)

contains

    include "test_assert.inc"

end program test_thermo_limits
