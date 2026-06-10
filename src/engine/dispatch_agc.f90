!> @file dispatch_agc.f90
!> @brief Secondary dispatch (AGC), operator commands, and scenario events.
!>
!> Merit order implemented by tick_auto_balance (sign convention:
!> storage_MW > 0 = discharge, adds to supply):
!>   Shortage: restore renewable headroom -> BESS discharge -> turbine up.
!>   Surplus:  BESS charge -> residual renewable trim -> turbine down.
module dispatch_agc
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: tick_auto_balance, balance_now, reset_controls
    public :: ramp_renewable_curtailment_to, should_curtail_renewables
    public :: apply_load_step, apply_cloud_ramp, apply_turbine_trip

contains

    subroutine tick_auto_balance(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        real(dp) :: eff_renew, gap_MW, surplus_MW, target_curtail_MW
        real(dp) :: bess_target_MW, bess_step_MW
        real(dp) :: needed_gas_MW, gas_target_pct, gas_step_pct

        if (.not. st%auto_balance) return

        st%renewable_curtail_MW = clamp_real(st%renewable_curtail_MW, 0.0_dp, st%renewable_MW)

        ! Stage 1: renewable inverter active-power setpoint. It cannot exceed
        ! weather availability, but any curtailed headroom is restored first in a shortage.
        eff_renew = effective_renewable_MW(st)
        gap_MW = st%demand_MW - eff_renew - thermal_generation_MW(st) &
                 - limited_storage_power(st, st%storage_request_MW)
        if (gap_MW > 0.10_dp .and. st%renewable_curtail_MW > 0.0_dp) then
            target_curtail_MW = max(0.0_dp, st%renewable_curtail_MW - gap_MW)
            call ramp_renewable_curtailment_to(st, target_curtail_MW, dt_s)
        end if

        ! Stage 2: BESS covers the residual quickly while respecting SOC limits.
        eff_renew = effective_renewable_MW(st)
        bess_target_MW = clamp_real(st%demand_MW - eff_renew - thermal_generation_MW(st), &
                                    STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (st%fcr_hold) then
            if (bess_target_MW < -0.5_dp) bess_target_MW = max(bess_target_MW, 0.65_dp * bess_target_MW)
            bess_target_MW = clamp_real(bess_target_MW, STORAGE_MIN_MW + 5.0_dp, STORAGE_MAX_MW - 5.0_dp)
            if (abs(bess_target_MW) < 0.5_dp .and. st%battery_soc_pct < 45.0_dp) &
                bess_target_MW = -2.0_dp
            if (abs(bess_target_MW) < 0.5_dp .and. st%battery_soc_pct > 55.0_dp) &
                bess_target_MW = 2.0_dp
        end if
        if (st%fleet_mode .and. st%roi_dispatch .and. st%fuel_price_usd_gj > 12.0_dp .and. &
                st%battery_soc_pct > 45.0_dp) then
            bess_target_MW = max(bess_target_MW, &
                min(8.0_dp, max(0.0_dp, st%demand_MW - eff_renew)))
        end if
        if (bess_target_MW > 0.0_dp .and. st%battery_soc_pct < 5.0_dp) &
            bess_target_MW = 0.0_dp   ! no discharge when nearly empty
        if (bess_target_MW < 0.0_dp .and. st%battery_soc_pct > 95.0_dp) &
            bess_target_MW = 0.0_dp   ! no charge when nearly full
        bess_step_MW = BESS_RAMP_MW_PER_S * dt_s
        st%storage_request_MW = st%storage_request_MW + &
            clamp_real(bess_target_MW - st%storage_request_MW, -bess_step_MW, bess_step_MW)

        ! Stage 3: if BESS cannot absorb surplus fast enough, trim renewable injection.
        gap_MW = st%demand_MW - eff_renew - thermal_generation_MW(st) &
                 - limited_storage_power(st, st%storage_request_MW)
        if (gap_MW < -0.50_dp .and. should_curtail_renewables(st) .and. &
                .not. fleet_bess_displacing_thermal(st)) then
            surplus_MW = -gap_MW
            target_curtail_MW = min(st%renewable_MW, st%renewable_curtail_MW + surplus_MW)
            call ramp_renewable_curtailment_to(st, target_curtail_MW, dt_s)
        else if (abs(gap_MW) <= 0.50_dp .and. st%renewable_curtail_MW > 0.0_dp .and. &
                 st%renewable_reserve_value_usd_h < st%renewable_curtail_cost_usd_h) then
            call ramp_renewable_curtailment_to(st, 0.0_dp, dt_s)
        end if

        ! Stage 4: turbine follows the remaining steady dispatch requirement.
        eff_renew = effective_renewable_MW(st)
        if (st%fleet_mode) then
            st%fleet_load_target_MW = clamp_real(st%demand_MW - eff_renew - &
                limited_storage_power(st, st%storage_request_MW), 0.0_dp, st%fleet_online_capacity_MW)
            return
        end if
        needed_gas_MW = st%demand_MW - eff_renew - bottoming_power_MW(st) &
                        - limited_storage_power(st, st%storage_request_MW)
        if (st%gas_capacity_MW > 1.0e-6_dp) then
            gas_target_pct = 100.0_dp * needed_gas_MW / st%gas_capacity_MW
        else
            gas_target_pct = GAS_MAX_PCT
        end if
        gas_target_pct = clamp_real(gas_target_pct, GAS_MIN_PCT, GAS_MAX_PCT)
        gas_step_pct = GAS_RAMP_PCT_PER_S * dt_s
        st%gas_dispatch_pct = st%gas_dispatch_pct + &
            clamp_real(gas_target_pct - st%gas_dispatch_pct, -gas_step_pct, gas_step_pct)
    end subroutine tick_auto_balance

    !> One-shot balance: snap BESS and turbine to calculated setpoints.
    !> The AUTO/MANUAL latch is intentionally left unchanged.
    subroutine balance_now(st)
        type(GridState), intent(inout) :: st
        real(dp) :: bess_snap_MW, needed_gas_MW

        if (st%fleet_mode) then
            st%renewable_curtail_MW = 0.0_dp
            bess_snap_MW = clamp_real(st%demand_MW - st%renewable_MW - thermal_generation_MW(st), &
                                      STORAGE_MIN_MW, STORAGE_MAX_MW)
            if (st%fuel_price_usd_gj > 12.0_dp .and. st%battery_soc_pct > 45.0_dp) &
                bess_snap_MW = max(bess_snap_MW, min(8.0_dp, st%demand_MW - st%renewable_MW))
            if (bess_snap_MW > 0.0_dp .and. st%battery_soc_pct < 5.0_dp)  bess_snap_MW = 0.0_dp
            if (bess_snap_MW < 0.0_dp .and. st%battery_soc_pct > 95.0_dp) bess_snap_MW = 0.0_dp
            st%storage_request_MW = bess_snap_MW
            st%fleet_load_target_MW = clamp_real(st%demand_MW - st%renewable_MW - &
                limited_storage_power(st, st%storage_request_MW), 0.0_dp, st%fleet_online_capacity_MW)
            return
        end if

        if (st%gas_capacity_MW <= 1.0e-6_dp) return
        st%renewable_curtail_MW = 0.0_dp
        bess_snap_MW = clamp_real(st%demand_MW - st%renewable_MW - thermal_generation_MW(st), &
                                  STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (bess_snap_MW > 0.0_dp .and. st%battery_soc_pct < 5.0_dp)  bess_snap_MW = 0.0_dp
        if (bess_snap_MW < 0.0_dp .and. st%battery_soc_pct > 95.0_dp) bess_snap_MW = 0.0_dp
        st%storage_request_MW = bess_snap_MW
        needed_gas_MW = st%demand_MW - st%renewable_MW - bottoming_power_MW(st) &
                        - limited_storage_power(st, st%storage_request_MW)
        st%gas_dispatch_pct = clamp_real(100.0_dp * needed_gas_MW / st%gas_capacity_MW, &
                                         GAS_MIN_PCT, GAS_MAX_PCT)
    end subroutine balance_now

    !> Slew the curtailment setpoint toward a target at inverter ramp rate.
    subroutine ramp_renewable_curtailment_to(st, target_MW, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: target_MW, dt_s
        real(dp) :: target, step_MW

        target = clamp_real(target_MW, 0.0_dp, st%renewable_MW)
        step_MW = CURTAIL_RAMP_MW_PER_S * dt_s
        st%renewable_curtail_MW = st%renewable_curtail_MW + &
            clamp_real(target - st%renewable_curtail_MW, -step_MW, step_MW)
    end subroutine ramp_renewable_curtailment_to

    !> ROI-aware gate for spilling zero-marginal-cost energy.
    function should_curtail_renewables(st) result(allow)
        type(GridState), intent(in) :: st
        logical :: allow

        if (.not. st%roi_dispatch) then
            allow = .true.
        else if (st%fcr_hold) then
            allow = .true.
        else if (st%frequency_Hz > FREQ_NOMINAL_HZ + 0.08_dp) then
            allow = .true.
        else if (st%storage_request_MW <= STORAGE_MIN_MW + 0.25_dp) then
            allow = .true.
        else if (st%battery_soc_pct > 90.0_dp) then
            allow = .true.
        else
            allow = .false.
        end if
    end function should_curtail_renewables

    !> In fleet ROI mode, profitable BESS discharge should back down
    !> thermal dispatch before spilling zero-fuel renewable injection.
    function fleet_bess_displacing_thermal(st) result(displacing)
        type(GridState), intent(in) :: st
        logical :: displacing

        displacing = st%fleet_mode .and. st%roi_dispatch .and. &
            st%fuel_price_usd_gj > 12.0_dp .and. st%storage_request_MW > 0.25_dp .and. &
            st%battery_soc_pct > 45.0_dp
    end function fleet_bess_displacing_thermal

    ! --- Scenario event commands (operator buttons today, scripts in P1) ---

    subroutine apply_load_step(st)
        type(GridState), intent(inout) :: st
        st%demand_MW = clamp_real(st%demand_MW + 10.0_dp, DEMAND_MIN_MW, DEMAND_MAX_MW)
        st%auto_balance = .true.
    end subroutine apply_load_step

    subroutine apply_cloud_ramp(st)
        type(GridState), intent(inout) :: st
        st%renewable_MW = clamp_real(st%renewable_MW - 15.0_dp, 0.0_dp, RENEWABLE_MAX_MW)
        st%renewable_curtail_MW = min(st%renewable_curtail_MW, st%renewable_MW)
        st%auto_balance = .true.
    end subroutine apply_cloud_ramp

    subroutine apply_turbine_trip(st)
        type(GridState), intent(inout) :: st
        if (st%fleet_mode) then
            st%fleet_unit_online(FLEET_CC1) = .false.
            st%fleet_unit_setpoint_MW(FLEET_CC1) = 0.0_dp
            st%fleet_unit_actual_MW(FLEET_CC1) = 0.0_dp
            st%storage_request_MW = min(st%storage_request_MW + 8.0_dp, STORAGE_MAX_MW)
        else
            st%gas_dispatch_pct = GAS_MIN_PCT
            st%storage_request_MW = min(st%storage_request_MW + 8.0_dp, STORAGE_MAX_MW)
        end if
        st%auto_balance = .true.
    end subroutine apply_turbine_trip

    !> Restore the default operating point (RESET button / engine init).
    subroutine reset_controls(st)
        type(GridState), intent(inout) :: st

        st%auto_balance = .true.
        st%battery_energy_MWh = BATTERY_CAPACITY_MWH * BATTERY_INITIAL_SOC_PCT / 100.0_dp
        st%battery_soc_pct = BATTERY_INITIAL_SOC_PCT
        st%elapsed_s = 0.0_dp
        st%CO2_cumulative_t = 0.0_dp
        st%history_count = 0
        st%history_head = 0
        st%demand_MW = 35.0_dp
        st%renewable_MW = 12.0_dp
        st%storage_request_MW = 0.0_dp
        st%storage_MW = 0.0_dp
        st%gas_dispatch_pct = 82.0_dp
        st%ambient_C = 15.0_dp
        st%TIT_K = 1400.0_dp
        st%nominal_frequency_Hz = FREQ_NOMINAL_HZ
        st%frequency_Hz = st%nominal_frequency_Hz
        st%ROCOF_Hz_s = 0.0_dp
        st%governor_delta_MW = 0.0_dp
        st%BESS_primary_MW = 0.0_dp
        st%UFLS_shed_fraction = 0.0_dp
        st%ufls_thresh_1_Hz = UFLS_THRESH_1
        st%ufls_thresh_2_Hz = UFLS_THRESH_2
        st%ufls_thresh_3_Hz = UFLS_THRESH_3
        st%ufls_reset_Hz = UFLS_RESET
        st%lfsm_o_thresh_Hz = LFSM_O_THRESH_HZ
        st%UFLS_stage = 0
        st%renewable_curtail_MW = 0.0_dp
        st%renewable_lfsmo_MW = 0.0_dp
        st%roi_dispatch = .true.
        st%fcr_hold = .true.
        st%surge_margin_pct = 20.0_dp
        st%igv_pct = 100.0_dp
        st%flow_frac = 1.0_dp
        st%TIT_actual_K = st%TIT_K
        st%PR_op = 15.0_dp
        st%gas_ramp_pct_per_s = 0.0_dp
        st%prev_gas_dispatch_pct = st%gas_dispatch_pct
        st%combined_cycle = .false.
        st%plant_power_MW = 0.0_dp
        st%plant_capacity_MW = 0.0_dp
        st%steam_power_MW = 0.0_dp
        st%steam_power_target_MW = 0.0_dp
        st%steam_capacity_MW = 0.0_dp
        st%plant_efficiency = 0.0_dp
        st%gt_heat_rate_kJ_kWh = 0.0_dp
        st%gt_thermal_efficiency = 0.0_dp
        st%hrsg_recovered_heat_MW = 0.0_dp
        st%hrsg_stack_T_K = 0.0_dp
        st%hrsg_pinch_K = 0.0_dp
        st%hrsg_approach_K = 0.0_dp
        st%hrsg_steam_flow_kg_s = 0.0_dp
        st%hrsg_steam_T_K = 0.0_dp
        st%hrsg_steam_pressure_bar = 0.0_dp
        st%hrsg_effectiveness = 0.0_dp
        st%condenser_pressure_kPa = 0.0_dp
        st%alarm_hrsg_pinch = .false.
        st%fleet_mode = .false.
        st%fuel_price_usd_gj = FUEL_PRICE_USD_GJ
        st%power_price_usd_mwh = POWER_PRICE_USD_MWH
        st%fcr_reserve_price_usd_mw_h = FCR_RESERVE_PRICE_USD_MW_H
        st%bess_arbitrage_spread_usd_mwh = BESS_ARBITRAGE_SPREAD_USD_MWH
        st%renewable_reserve_price_usd_mw_h = RENEWABLE_RESERVE_PRICE_USD_MW_H
        st%carbon_price_usd_t = 0.0_dp
        st%co2_cost_usd_h = 0.0_dp
        st%fleet_load_target_MW = 0.0_dp
        st%fleet_unit_online = [.true., .true., .true.]
        st%fleet_unit_capacity_MW = [30.0_dp, 15.0_dp, 45.0_dp]
        st%fleet_unit_setpoint_MW = 0.0_dp
        st%fleet_unit_actual_MW = 0.0_dp
        st%fleet_unit_ramp_MW_s = [3.5_dp, 8.0_dp, 0.25_dp]
        st%fleet_unit_heat_rate_kJ_kWh = [11750.0_dp, 9800.0_dp, 6880.0_dp]
        st%fleet_unit_var_om_usd_MWh = [5.0_dp, 7.0_dp, 3.0_dp]
        st%fleet_unit_cost_usd_MWh = 0.0_dp
        st%fleet_unit_participation = 0.0_dp
        st%fleet_unit_inertia_MWs = [24.0_dp, 8.0_dp, 70.0_dp]
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
        st%market_profile_id = 1
        st%market_profile_name = "Default SE3"
        st%market_power_zone = "SE3"
        st%market_gas_hub = "TTF"
        st%market_source_code = 0
        st%market_weather_enabled = .false.
        st%market_load_replay_enabled = .false.
        st%market_latitude_deg = 59.33_dp
        st%market_longitude_deg = 18.07_dp
        st%market_replay_day_s = 300.0_dp
        st%market_hour = 12.0_dp
        st%market_last_update_s = 0.0_dp
        st%market_data_age_s = 0.0_dp
        st%renewable_scale_pct = 100.0_dp
        st%market_wind_capacity_MW = 28.0_dp
        st%market_pv_capacity_MW = 18.0_dp
        st%market_wind_speed_m_s = 0.0_dp
        st%market_solar_W_m2 = 0.0_dp
        st%market_wind_power_MW = 0.0_dp
        st%market_pv_power_MW = 0.0_dp
        st%market_base_demand_MW = 35.0_dp
        st%market_peak_demand_MW = 72.0_dp
        st%alarm_surge = .false.
        st%alarm_underfreq = .false.
        st%alarm_overfreq  = .false.
        st%alarm_low_reserve = .false.
        st%alarm_low_soc = .false.
        st%alarm_ufls_active = .false.
        st%alarm_turbine_max = .false.
    end subroutine reset_controls

end module dispatch_agc
