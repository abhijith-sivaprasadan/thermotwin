!> @file test_combined_cycle.f90
!> @brief Phase 3 checks for the HRSG and steam-bottoming cycle.
program test_combined_cycle
    use precision_kinds, only: dp
    use engine_core
    implicit none

    integer :: failures
    failures = 0

    ! --- Simple cycle remains the default and contributes no bottoming power. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%gas_dispatch_pct = 100.0_dp
        call refresh_model(st)
        call expect_true("simple cycle: CC mode disabled by default", .not. st%combined_cycle, failures)
        call expect_near("simple cycle: no steam power", st%steam_power_MW, 0.0_dp, 1.0e-9_dp, failures)
        call expect_near("simple cycle: plant power equals GT power", &
            st%plant_power_MW, st%gas_power_MW, 1.0e-9_dp, failures)
    end block

    ! --- Combined-cycle design point lands in the published 52-56% class. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%combined_cycle = .true.
        st%gas_dispatch_pct = 100.0_dp
        st%demand_MW = 50.0_dp
        call refresh_model(st)
        call expect_true("CC: steam turbine adds bottoming power", st%steam_power_MW > 15.0_dp, failures)
        call expect_true("CC: plant power exceeds GT power", st%plant_power_MW > st%gas_power_MW, failures)
        call expect_true("CC: efficiency in 52-56% validation band", &
            st%plant_efficiency >= 0.52_dp .and. st%plant_efficiency <= 0.56_dp, failures)
        call expect_true("CC: HRSG pinch respects minimum", st%hrsg_pinch_K >= 15.0_dp, failures)
        call expect_true("CC: stack temperature remains above wet-stack floor", &
            st%hrsg_stack_T_K > 360.0_dp, failures)
    end block

    ! --- Steam train is slower than the gas turbine under transient AGC. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%combined_cycle = .true.
        st%gas_dispatch_pct = 100.0_dp
        st%steam_power_MW = 0.0_dp
        call refresh_model(st, 0.25_dp)
        call expect_true("CC transient: target is above actual", &
            st%steam_power_target_MW > st%steam_power_MW, failures)
        call expect_near("CC transient: steam ramp limited", &
            st%steam_power_MW, 0.18_dp * 0.25_dp, 1.0e-9_dp, failures)
    end block

    call finish("combined_cycle", failures)

contains

    include "test_assert.inc"

end program test_combined_cycle
