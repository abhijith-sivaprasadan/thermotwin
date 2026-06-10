!> @file test_fleet_dispatch.f90
!> @brief Phase 4 checks for fleet economic dispatch, reserve, BESS merit, and inertia.
program test_fleet_dispatch
    use precision_kinds, only: dp
    use engine_core
    implicit none

    integer :: failures
    failures = 0

    ! --- Cheap gas: CC1 is the lowest-cost base-load unit. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%fleet_mode = .true.
        st%combined_cycle = .true.
        st%auto_balance = .false.
        st%demand_MW = 70.0_dp
        st%renewable_MW = 10.0_dp
        st%fuel_price_usd_gj = 6.0_dp
        st%fleet_load_target_MW = 60.0_dp
        call refresh_model(st)
        call expect_true("fleet: CC1 cheapest", &
            st%fleet_unit_cost_usd_MWh(FLEET_CC1) < st%fleet_unit_cost_usd_MWh(FLEET_GT2) .and. &
            st%fleet_unit_cost_usd_MWh(FLEET_GT2) < st%fleet_unit_cost_usd_MWh(FLEET_GT1), failures)
        call expect_true("fleet: CC1 carries base load", st%fleet_unit_setpoint_MW(FLEET_CC1) > 45.0_dp, failures)
        call expect_true("fleet: GT1 held back by merit order", st%fleet_unit_setpoint_MW(FLEET_GT1) < 0.1_dp, failures)
    end block

    ! --- Spinning reserve constraint limits dispatch below online capacity. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%fleet_mode = .true.
        st%combined_cycle = .true.
        st%auto_balance = .false.
        st%demand_MW = 100.0_dp
        st%renewable_MW = 0.0_dp
        st%fleet_load_target_MW = 96.0_dp
        call refresh_model(st)
        call expect_true("fleet: reserve constraint binds", st%fleet_reserve_binding, failures)
        call expect_true("fleet: unserved dispatch records reserve holdback", &
            st%fleet_unserved_dispatch_MW > 1.0_dp, failures)
        call expect_true("fleet: reserve remains at requirement", &
            st%fleet_reserve_MW >= st%fleet_reserve_requirement_MW - 1.0e-6_dp, failures)
    end block

    ! --- Expensive fuel: ROI controller leans on BESS before extra thermal MW. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%fleet_mode = .true.
        st%combined_cycle = .true.
        st%auto_balance = .true.
        st%demand_MW = 60.0_dp
        st%renewable_MW = 30.0_dp
        st%fuel_price_usd_gj = 18.0_dp
        st%battery_soc_pct = 70.0_dp
        st%battery_energy_MWh = BATTERY_CAPACITY_MWH * st%battery_soc_pct / 100.0_dp
        call refresh_model(st)
        call engine_step(st, 0.25_dp)
        call expect_true("fleet: high fuel price requests BESS discharge", &
            st%storage_request_MW > 0.0_dp, failures)
        call expect_true("fleet: BESS reduces thermal target", &
            st%fleet_load_target_MW < st%demand_MW - st%renewable_MW, failures)
    end block

    ! --- Online inertia is the sum of online units; tripping CC1 worsens it. ---
    block
        type(GridState) :: st
        real(dp) :: full_inertia
        call engine_init(st)
        st%fleet_mode = .true.
        st%combined_cycle = .true.
        st%fleet_load_target_MW = 50.0_dp
        call refresh_model(st)
        full_inertia = st%fleet_inertia_MWs
        st%fleet_unit_online(FLEET_CC1) = .false.
        call refresh_model(st)
        call expect_true("fleet: CC1 trip removes inertia", &
            st%fleet_inertia_MWs < full_inertia - 50.0_dp, failures)
    end block

    call finish("fleet_dispatch", failures)

contains

    include "test_assert.inc"

end program test_fleet_dispatch
