!> @file test_exergy.f90
!> @brief Revamp 7.0 P1 — exergy / second-law balance checks.
!>
!> Verifies the availability balance closes, that exergy destruction is dominated
!> by the combustor (combustion irreversibility — the canonical second-law result),
!> and that the rational efficiency lands in physically sensible bands for both
!> combined- and simple-cycle operation.
program test_exergy
    use precision_kinds, only: dp
    use engine_core
    use exergy, only: ExergyResult, compute_exergy
    implicit none

    integer :: failures
    failures = 0

    ! --- Combined-cycle steady point (consistent: plant = gas + steam) ---
    block
        type(GridState)    :: st
        type(ExergyResult) :: r
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
        call compute_exergy(st, r)

        call expect_true("exergy: fuel exergy positive", r%ex_fuel > 1.0e4_dp, failures)
        call expect_true("exergy: all destructions non-negative", &
            r%dest_comp >= 0.0_dp .and. r%dest_comb >= 0.0_dp .and. &
            r%dest_turb >= 0.0_dp .and. r%dest_hrsg >= 0.0_dp, failures)
        call expect_true("exergy: combustor dominates destruction", &
            r%dest_comb > r%dest_comp .and. r%dest_comb > r%dest_turb .and. &
            r%dest_comb > r%dest_hrsg, failures)
        call expect_true("exergy: rational efficiency in plausible CCGT band", &
            r%eta_II > 0.30_dp .and. r%eta_II < 0.70_dp, failures)
        call expect_true("exergy: availability balance closes (<2%)", &
            abs(r%closure) < 0.02_dp, failures)
        call expect_true("exergy: total destruction positive", r%dest_total > 0.0_dp, failures)
    end block

    ! --- Simple-cycle point: exhaust leaves as stack loss, no bottoming term ---
    block
        type(GridState)    :: st
        type(ExergyResult) :: r
        call engine_init(st)
        st%ambient_C      = 15.0_dp
        st%PR_op          = 15.0_dp
        st%TIT_actual_K   = 1400.0_dp
        st%exhaust_K      = 850.0_dp
        st%fuel_flow_kg_s = 1.5_dp
        st%h2_lhv_mj_kg   = 50.0_dp
        st%gas_power_MW   = 18.0_dp
        st%steam_power_MW = 0.0_dp
        st%plant_power_MW = 18.0_dp
        st%combined_cycle = .false.
        call compute_exergy(st, r)

        call expect_true("exergy SC: no bottoming destruction", r%dest_hrsg == 0.0_dp, failures)
        call expect_true("exergy SC: stack carries exhaust exergy", r%ex_stack > 1.0e3_dp, failures)
        call expect_true("exergy SC: rational efficiency below combined cycle", &
            r%eta_II > 0.15_dp .and. r%eta_II < 0.45_dp, failures)
        call expect_true("exergy SC: availability balance closes (<2%)", &
            abs(r%closure) < 0.02_dp, failures)
    end block

    call finish("exergy", failures)

contains

    include "test_assert.inc"

end program test_exergy
