!> @file fleet_dispatch.f90
!> @brief Phase 4 multi-unit economic dispatch and AGC participation.
module fleet_dispatch
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: initialize_fleet, refresh_fleet_dispatch
    public :: trip_fleet_unit, restore_fleet_units

contains

    subroutine initialize_fleet(st)
        type(GridState), intent(inout) :: st

        st%fuel_price_usd_gj = FUEL_PRICE_USD_GJ
        st%fleet_load_target_MW = 0.0_dp
        st%fleet_unit_online = [.true., .true., .true.]
        st%fleet_unit_capacity_MW = [30.0_dp, 15.0_dp, 45.0_dp]
        st%fleet_unit_setpoint_MW = 0.0_dp
        st%fleet_unit_actual_MW = 0.0_dp
        st%fleet_unit_ramp_MW_s = [3.5_dp, 8.0_dp, 0.25_dp]
        st%fleet_unit_heat_rate_kJ_kWh = [11750.0_dp, 9800.0_dp, 6880.0_dp]
        st%fleet_unit_var_om_usd_MWh = [5.0_dp, 7.0_dp, 3.0_dp]
        st%fleet_unit_inertia_MWs = [24.0_dp, 8.0_dp, 70.0_dp]
        st%fleet_unit_cost_usd_MWh = 0.0_dp
        st%fleet_unit_participation = 0.0_dp
        st%fleet_total_MW = 0.0_dp
        st%fleet_capacity_MW = sum(st%fleet_unit_capacity_MW)
        st%fleet_online_capacity_MW = st%fleet_capacity_MW
        st%fleet_reserve_MW = 0.0_dp
        st%fleet_reserve_requirement_MW = 5.0_dp
        st%fleet_unserved_dispatch_MW = 0.0_dp
        st%fleet_inertia_MWs = sum(st%fleet_unit_inertia_MWs)
        st%fleet_lmp_usd_MWh = 0.0_dp
        st%fleet_agc_error_MW = 0.0_dp
        st%fleet_marginal_unit = 0
        st%fleet_reserve_binding = .false.
    end subroutine initialize_fleet

    subroutine refresh_fleet_dispatch(st, dt_s, gt1_capacity_MW, gt1_heat_rate_kJ_kWh, &
            cc_capacity_MW, cc_heat_rate_kJ_kWh)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s, gt1_capacity_MW, gt1_heat_rate_kJ_kWh
        real(dp), intent(in) :: cc_capacity_MW, cc_heat_rate_kJ_kWh
        real(dp) :: target_MW

        call update_unit_capabilities(st, gt1_capacity_MW, gt1_heat_rate_kJ_kWh, &
            cc_capacity_MW, cc_heat_rate_kJ_kWh)
        call update_unit_costs(st)

        if (.not. st%fleet_mode) return

        if (st%auto_balance) then
            st%fleet_load_target_MW = clamp_real(st%demand_MW - effective_renewable_MW(st) - &
                st%storage_MW, 0.0_dp, st%fleet_online_capacity_MW)
        else if (st%fleet_load_target_MW <= 1.0e-9_dp) then
            st%fleet_load_target_MW = max(0.0_dp, st%demand_MW - effective_renewable_MW(st) - st%storage_MW)
        end if
        st%fleet_reserve_requirement_MW = max(5.0_dp, 0.10_dp * st%demand_MW)
        target_MW = min(st%fleet_load_target_MW, &
            max(0.0_dp, st%fleet_online_capacity_MW - st%fleet_reserve_requirement_MW))
        st%fleet_reserve_binding = st%fleet_load_target_MW > target_MW + 1.0e-6_dp
        st%fleet_unserved_dispatch_MW = max(0.0_dp, st%fleet_load_target_MW - target_MW)

        call economic_dispatch(st, target_MW)
        call ramp_units(st, dt_s)
        call summarize_fleet(st)
    end subroutine refresh_fleet_dispatch

    subroutine update_unit_capabilities(st, gt1_capacity_MW, gt1_heat_rate_kJ_kWh, &
            cc_capacity_MW, cc_heat_rate_kJ_kWh)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: gt1_capacity_MW, gt1_heat_rate_kJ_kWh
        real(dp), intent(in) :: cc_capacity_MW, cc_heat_rate_kJ_kWh
        integer :: i

        st%fleet_unit_capacity_MW(FLEET_GT1) = max(0.0_dp, gt1_capacity_MW)
        if (gt1_heat_rate_kJ_kWh > 1.0_dp) st%fleet_unit_heat_rate_kJ_kWh(FLEET_GT1) = gt1_heat_rate_kJ_kWh
        st%fleet_unit_capacity_MW(FLEET_GT2) = 15.0_dp
        st%fleet_unit_heat_rate_kJ_kWh(FLEET_GT2) = 9800.0_dp
        st%fleet_unit_capacity_MW(FLEET_CC1) = max(0.0_dp, cc_capacity_MW)
        if (cc_heat_rate_kJ_kWh > 1.0_dp) st%fleet_unit_heat_rate_kJ_kWh(FLEET_CC1) = cc_heat_rate_kJ_kWh

        st%fleet_capacity_MW = sum(st%fleet_unit_capacity_MW)
        st%fleet_online_capacity_MW = 0.0_dp
        st%fleet_inertia_MWs = 0.0_dp
        do i = 1, FLEET_N
            if (st%fleet_unit_online(i)) then
                st%fleet_online_capacity_MW = st%fleet_online_capacity_MW + st%fleet_unit_capacity_MW(i)
                st%fleet_inertia_MWs = st%fleet_inertia_MWs + st%fleet_unit_inertia_MWs(i)
            end if
        end do
        st%fleet_inertia_MWs = max(8.0_dp, st%fleet_inertia_MWs)
    end subroutine update_unit_capabilities

    subroutine update_unit_costs(st)
        type(GridState), intent(inout) :: st
        integer :: i

        do i = 1, FLEET_N
            st%fleet_unit_cost_usd_MWh(i) = st%fleet_unit_heat_rate_kJ_kWh(i) / 1000.0_dp * &
                st%fuel_price_usd_gj + st%fleet_unit_var_om_usd_MWh(i)
        end do
    end subroutine update_unit_costs

    subroutine economic_dispatch(st, target_MW)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: target_MW
        logical :: used(FLEET_N)
        integer :: rank, i, best
        real(dp) :: remaining_MW, best_cost, take_MW

        used = .false.
        st%fleet_unit_setpoint_MW = 0.0_dp
        st%fleet_marginal_unit = 0
        st%fleet_lmp_usd_MWh = 0.0_dp
        remaining_MW = max(0.0_dp, target_MW)

        do rank = 1, FLEET_N
            best = 0
            best_cost = huge(1.0_dp)
            do i = 1, FLEET_N
                if (used(i) .or. .not. st%fleet_unit_online(i)) cycle
                if (st%fleet_unit_cost_usd_MWh(i) < best_cost) then
                    best = i
                    best_cost = st%fleet_unit_cost_usd_MWh(i)
                end if
            end do
            if (best == 0) exit
            used(best) = .true.
            if (remaining_MW <= 1.0e-9_dp) cycle
            take_MW = min(st%fleet_unit_capacity_MW(best), remaining_MW)
            st%fleet_unit_setpoint_MW(best) = take_MW
            remaining_MW = remaining_MW - take_MW
            st%fleet_marginal_unit = best
            st%fleet_lmp_usd_MWh = st%fleet_unit_cost_usd_MWh(best)
        end do
    end subroutine economic_dispatch

    subroutine ramp_units(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        integer :: i
        real(dp) :: step_MW

        do i = 1, FLEET_N
            if (.not. st%fleet_unit_online(i)) then
                st%fleet_unit_actual_MW(i) = 0.0_dp
                cycle
            end if
            if (dt_s > 0.0_dp) then
                step_MW = st%fleet_unit_ramp_MW_s(i) * dt_s
                st%fleet_unit_actual_MW(i) = st%fleet_unit_actual_MW(i) + &
                    clamp_real(st%fleet_unit_setpoint_MW(i) - st%fleet_unit_actual_MW(i), -step_MW, step_MW)
            else
                st%fleet_unit_actual_MW(i) = st%fleet_unit_setpoint_MW(i)
            end if
        end do
    end subroutine ramp_units

    subroutine summarize_fleet(st)
        type(GridState), intent(inout) :: st
        integer :: i
        real(dp) :: heat_input_MW, total_ramp

        st%fleet_total_MW = 0.0_dp
        heat_input_MW = 0.0_dp
        total_ramp = 0.0_dp
        do i = 1, FLEET_N
            if (.not. st%fleet_unit_online(i)) cycle
            st%fleet_total_MW = st%fleet_total_MW + st%fleet_unit_actual_MW(i)
            heat_input_MW = heat_input_MW + &
                st%fleet_unit_actual_MW(i) * st%fleet_unit_heat_rate_kJ_kWh(i) / 3600.0_dp
            if (st%fleet_unit_actual_MW(i) < st%fleet_unit_capacity_MW(i) - 1.0e-6_dp) &
                total_ramp = total_ramp + st%fleet_unit_ramp_MW_s(i)
        end do

        st%fleet_reserve_MW = max(0.0_dp, st%fleet_online_capacity_MW - st%fleet_total_MW)
        st%fleet_agc_error_MW = st%fleet_load_target_MW - st%fleet_total_MW
        st%plant_power_MW = st%fleet_total_MW
        st%plant_capacity_MW = st%fleet_online_capacity_MW
        st%heat_input_MW = heat_input_MW
        if (st%plant_power_MW > 1.0e-9_dp .and. heat_input_MW > 1.0e-9_dp) then
            st%plant_efficiency = st%plant_power_MW / heat_input_MW
            st%heat_rate_kJ_kWh = 3600.0_dp * heat_input_MW / st%plant_power_MW
        else
            st%plant_efficiency = 0.0_dp
            st%heat_rate_kJ_kWh = huge(1.0_dp)
        end if
        st%fuel_flow_kg_s = heat_input_MW * 1.0e6_dp / 50.0e6_dp
        st%reserve_MW = st%fleet_reserve_MW
        st%gas_power_MW = st%fleet_unit_actual_MW(FLEET_GT1)
        st%gas_capacity_MW = st%fleet_unit_capacity_MW(FLEET_GT1)
        st%steam_capacity_MW = st%fleet_unit_capacity_MW(FLEET_CC1) * 0.427_dp
        st%steam_power_MW = st%fleet_unit_actual_MW(FLEET_CC1) * 0.427_dp

        st%fleet_unit_participation = 0.0_dp
        if (total_ramp > 1.0e-9_dp) then
            do i = 1, FLEET_N
                if (st%fleet_unit_online(i) .and. &
                        st%fleet_unit_actual_MW(i) < st%fleet_unit_capacity_MW(i) - 1.0e-6_dp) then
                    st%fleet_unit_participation(i) = st%fleet_unit_ramp_MW_s(i) / total_ramp
                end if
            end do
        end if
    end subroutine summarize_fleet

    subroutine trip_fleet_unit(st, unit_id)
        type(GridState), intent(inout) :: st
        integer, intent(in) :: unit_id

        if (unit_id < 1 .or. unit_id > FLEET_N) return
        st%fleet_unit_online(unit_id) = .false.
        st%fleet_unit_setpoint_MW(unit_id) = 0.0_dp
        st%fleet_unit_actual_MW(unit_id) = 0.0_dp
    end subroutine trip_fleet_unit

    subroutine restore_fleet_units(st)
        type(GridState), intent(inout) :: st

        st%fleet_unit_online = [.true., .true., .true.]
    end subroutine restore_fleet_units

end module fleet_dispatch
