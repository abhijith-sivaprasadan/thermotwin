!> @file engine_core.f90
!> @brief Engine facade and per-tick orchestration.
!>
!> `engine_step(st, dt)` advances one simulation tick: secondary AGC, the
!> gas-turbine cycle solution, battery SOC, fast frequency dynamics, CO2
!> accounting, trend history, and the tag-bus publication. The GUI timer
!> (and later the scenario runner / OPC UA server) is a thin caller.
!>
!> The module also re-exports the engine API so front-ends need a single
!> `use engine_core` line.
module engine_core
    use precision_kinds, only: dp
    use constants, only: KELVIN_OFFSET
    use types, only: InputCase, CycleResult
    use cycle_solver, only: solve_cycle
    use fluid_properties, only: set_property_model, PROP_VARIABLE
    use off_design, only: OffDesignPoint, solve_off_design
    use engine_state
    use hrsg, only: HrsgResult, solve_hrsg
    use steam_cycle, only: SteamCycleResult, solve_steam_cycle, ramp_limited, STEAM_RAMP_MW_PER_S
    use fleet_dispatch, only: refresh_fleet_dispatch, trip_fleet_unit, restore_fleet_units
    use market_data, only: apply_market_profile, cycle_market_profile, refresh_market_data, &
        market_profile_name, MARKET_PROFILE_N, MARKET_STOCKHOLM_SE3, MARKET_GERMANY_DELU, &
        MARKET_TEXAS_ERCOT, MARKET_LOUISIANA_HH
    use grid_dynamics, only: tick_frequency_dynamics
    use dispatch_agc, only: tick_auto_balance, balance_now, reset_controls, &
        ramp_renewable_curtailment_to, should_curtail_renewables, &
        apply_load_step, apply_cloud_ramp, apply_turbine_trip
    use plant_economics, only: refresh_economics
    use tag_bus, only: tag_set
    implicit none
    private

    ! Orchestration API
    public :: engine_init, engine_step, refresh_model, update_battery_soc
    public :: baseline_case, publish_tags

    ! Re-exported engine API (state, physics, dispatch, economics)
    public :: GridState, clamp_real
    public :: effective_renewable_MW, renewable_headroom_MW
    public :: limited_storage_power, append_history, history_index
    public :: bottoming_power_MW, thermal_generation_MW
    public :: tick_frequency_dynamics
    public :: tick_auto_balance, balance_now, reset_controls
    public :: ramp_renewable_curtailment_to, should_curtail_renewables
    public :: apply_load_step, apply_cloud_ramp, apply_turbine_trip
    public :: trip_fleet_unit, restore_fleet_units
    public :: apply_market_profile, cycle_market_profile, refresh_market_data, market_profile_name
    public :: refresh_economics

    ! Re-exported parameters used by front-ends
    public :: DEMAND_MIN_MW, DEMAND_MAX_MW, RENEWABLE_MAX_MW
    public :: STORAGE_MIN_MW, STORAGE_MAX_MW
    public :: BATTERY_CAPACITY_MWH, BATTERY_INITIAL_SOC_PCT, BATTERY_EFFICIENCY
    public :: GAS_MIN_PCT, GAS_MAX_PCT, GAS_RAMP_PCT_PER_S
    public :: BESS_RAMP_MW_PER_S, CURTAIL_RAMP_MW_PER_S
    public :: FLEET_N, FLEET_GT1, FLEET_GT2, FLEET_CC1, FLEET_UNIT_NAME
    public :: MARKET_PROFILE_N, MARKET_STOCKHOLM_SE3, MARKET_GERMANY_DELU
    public :: MARKET_TEXAS_ERCOT, MARKET_LOUISIANA_HH
    public :: FREQ_NOMINAL_HZ, INERTIA_MWs, GOVERNOR_DROOP_R
    public :: BESS_PRIMARY_GAIN, BESS_PRIMARY_DB
    public :: UFLS_THRESH_1, UFLS_THRESH_2, UFLS_THRESH_3, UFLS_RESET, UFLS_SHED_PCT
    public :: LFSM_O_THRESH_HZ, LFSM_O_DROOP
    public :: POWER_PRICE_USD_MWH, FUEL_PRICE_USD_GJ, STORAGE_CYCLE_COST_USD_MWH
    public :: IMBALANCE_PENALTY_USD_MWH, BESS_DEGRADATION_USD_MWH
    public :: FCR_RESERVE_PRICE_USD_MW_H, BESS_ARBITRAGE_SPREAD_USD_MWH
    public :: RENEWABLE_RESERVE_PRICE_USD_MW_H, BATTERY_CAPEX_USD_MWH
    public :: ROI_EQUIVALENT_HOURS_PER_YEAR, CO2_KG_PER_KG_FUEL
    public :: PI_DP, HISTORY_N

contains

    !> Reset to the default operating point and solve the initial cycle.
    !> The live engine runs with temperature-dependent gas properties; the
    !> constant-property model remains the default elsewhere so the verified
    !> hand calculation (selftest) is untouched.
    subroutine engine_init(st)
        type(GridState), intent(inout) :: st

        call set_property_model(PROP_VARIABLE)
        call reset_controls(st)
        st%prev_gas_dispatch_pct = st%gas_dispatch_pct
        st%gas_ramp_pct_per_s = 0.0_dp
        call refresh_model(st)
        call publish_tags(st)
    end subroutine engine_init

    !> Advance the whole simulation by one tick.
    subroutine engine_step(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s

        st%elapsed_s = st%elapsed_s + dt_s
        call refresh_market_data(st, dt_s)      ! location weather, prices, and replayed load
        call tick_auto_balance(st, dt_s)        ! AGC secondary ramp
        ! Dispatch slew rate over this tick (slider moves + AGC combined);
        ! upward ramps drive the transient surge-margin excursion.
        st%gas_ramp_pct_per_s = (st%gas_dispatch_pct - st%prev_gas_dispatch_pct) / dt_s
        st%prev_gas_dispatch_pct = st%gas_dispatch_pct
        call refresh_model(st, dt_s)            ! gas/steam power, imbalance, economics
        call update_battery_soc(st, dt_s)       ! SOC tracking
        call tick_frequency_dynamics(st, dt_s)  ! swing eq + primary response + UFLS
        st%CO2_cumulative_t = st%CO2_cumulative_t + &
            st%CO2_rate_kg_s * dt_s / 1000.0_dp
        call append_history(st)
        call publish_tags(st)
    end subroutine engine_step

    !> Solve the gas-turbine operating point at current conditions and refresh
    !> the steady-state power balance and economics. The operating point comes
    !> from the off-design solver: choked-turbine running line, IGV-first load
    !> control, map efficiency penalties, and surge margin.
    subroutine refresh_model(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in), optional :: dt_s
        type(InputCase) :: ic
        type(OffDesignPoint) :: od_cap, od
        type(HrsgResult) :: hrsg_cap, hrsg_live
        type(SteamCycleResult) :: steam_cap, steam_live
        real(dp) :: load_fraction, cc_capacity_MW, cc_heat_rate_kJ_kWh
        real(dp) :: step_s

        ic = baseline_case()
        ic%ambient_T_K = st%ambient_C + KELVIN_OFFSET
        ic%T_turbine_inlet_K = st%TIT_K
        if (present(dt_s)) then
            step_s = dt_s
        else
            step_s = 0.0_dp
        end if

        ! Capacity: IGVs fully open at the operator's firing-temperature setpoint.
        call solve_off_design(ic, 1.0_dp, 0.0_dp, od_cap)
        st%gas_capacity_MW = max(0.0_dp, od_cap%cyc%net_power_MW)
        call solve_hrsg(od_cap%cyc%exhaust_temperature_K, od_cap%cyc%mdot_gas_kg_s, &
            ic%ambient_T_K, hrsg_cap)
        call solve_steam_cycle(hrsg_cap, ic%ambient_T_K, steam_cap)
        cc_capacity_MW = st%gas_capacity_MW + steam_cap%net_power_MW
        if (cc_capacity_MW > 1.0e-9_dp) then
            cc_heat_rate_kJ_kWh = 3600.0_dp * od_cap%cyc%heat_input_MW / cc_capacity_MW
        else
            cc_heat_rate_kJ_kWh = 6880.0_dp
        end if
        st%steam_capacity_MW = merge(steam_cap%net_power_MW, 0.0_dp, st%combined_cycle)
        st%plant_capacity_MW = st%gas_capacity_MW + st%steam_capacity_MW

        load_fraction = clamp_real(st%gas_dispatch_pct / 100.0_dp, 0.0_dp, 1.0_dp)
        call solve_off_design(ic, load_fraction, st%gas_ramp_pct_per_s, od)

        st%gas_power_MW = max(0.0_dp, od%cyc%net_power_MW)
        st%gt_heat_rate_kJ_kWh = od%cyc%heat_rate_kJ_kWh
        st%gt_thermal_efficiency = od%cyc%thermal_efficiency
        st%exhaust_K = od%cyc%exhaust_temperature_K
        st%fuel_flow_kg_s = od%cyc%fuel_flow_kg_s
        st%heat_input_MW = od%cyc%heat_input_MW
        st%surge_margin_pct = od%surge_margin_pct
        st%igv_pct = od%igv_pct
        st%flow_frac = od%flow_frac
        st%TIT_actual_K = od%TIT_K
        st%PR_op = od%PR_op
        st%storage_MW = limited_storage_power(st, st%storage_request_MW)
        call solve_hrsg(od%cyc%exhaust_temperature_K, od%cyc%mdot_gas_kg_s, &
            ic%ambient_T_K, hrsg_live)
        call solve_steam_cycle(hrsg_live, ic%ambient_T_K, steam_live)
        if (st%combined_cycle) then
            st%steam_power_target_MW = steam_live%net_power_MW
            if (step_s > 0.0_dp) then
                st%steam_power_MW = ramp_limited(st%steam_power_MW, st%steam_power_target_MW, &
                    STEAM_RAMP_MW_PER_S, step_s)
            else
                st%steam_power_MW = st%steam_power_target_MW
            end if
            st%hrsg_recovered_heat_MW = hrsg_live%recovered_heat_MW
            st%hrsg_stack_T_K = hrsg_live%stack_T_K
            st%hrsg_pinch_K = hrsg_live%pinch_K
            st%hrsg_approach_K = hrsg_live%approach_K
            st%hrsg_steam_flow_kg_s = hrsg_live%steam_flow_kg_s
            st%hrsg_steam_T_K = hrsg_live%steam_T_K
            st%hrsg_steam_pressure_bar = hrsg_live%steam_pressure_bar
            st%hrsg_effectiveness = hrsg_live%effectiveness
            st%condenser_pressure_kPa = steam_live%condenser_pressure_kPa
            st%alarm_hrsg_pinch = .not. hrsg_live%pinch_ok
        else
            st%steam_power_target_MW = 0.0_dp
            st%steam_power_MW = 0.0_dp
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
        end if
        st%plant_power_MW = st%gas_power_MW + bottoming_power_MW(st)
        if (st%heat_input_MW > 1.0e-9_dp) then
            st%plant_efficiency = st%plant_power_MW / st%heat_input_MW
            st%heat_rate_kJ_kWh = 3600.0_dp / max(st%plant_efficiency, 1.0e-9_dp)
        else
            st%plant_efficiency = 0.0_dp
            st%heat_rate_kJ_kWh = huge(1.0_dp)
        end if
        if (st%fleet_mode) then
            call refresh_fleet_dispatch(st, step_s, st%gas_capacity_MW, st%gt_heat_rate_kJ_kWh, &
                cc_capacity_MW, cc_heat_rate_kJ_kWh)
        end if
        st%supply_MW = thermal_generation_MW(st) + effective_renewable_MW(st) + st%storage_MW
        st%imbalance_MW = st%supply_MW - st%demand_MW
        if (.not. st%fleet_mode) st%reserve_MW = max(0.0_dp, st%plant_capacity_MW - st%plant_power_MW)
        ! frequency_Hz is integrated by tick_frequency_dynamics; not recomputed here
        call refresh_economics(st)
    end subroutine refresh_model

    !> Track battery energy with one-way efficiency applied on each direction.
    subroutine update_battery_soc(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp) :: delta_MWh
        real(dp), intent(in) :: dt_s

        if (st%storage_MW > 0.0_dp) then
            delta_MWh = -st%storage_MW * dt_s / 3600.0_dp / BATTERY_EFFICIENCY
        else
            delta_MWh = -st%storage_MW * dt_s / 3600.0_dp * BATTERY_EFFICIENCY
        end if

        st%battery_energy_MWh = clamp_real(st%battery_energy_MWh + delta_MWh, 0.0_dp, BATTERY_CAPACITY_MWH)
        st%battery_soc_pct = 100.0_dp * st%battery_energy_MWh / BATTERY_CAPACITY_MWH
    end subroutine update_battery_soc

    !> The representative machine the live dashboard manipulates.
    function baseline_case() result(ic)
        type(InputCase) :: ic

        ic%case_name = "gui_live_case"
        ic%ambient_T_K = 288.15_dp
        ic%ambient_P_Pa = 101325.0_dp
        ic%relative_humidity = 0.60_dp
        ic%inlet_pressure_loss = 0.010_dp
        ic%mdot_air_kg_s = 100.0_dp
        ic%pressure_ratio = 15.0_dp
        ic%eta_compressor = 0.86_dp
        ic%T_turbine_inlet_K = 1400.0_dp
        ic%eta_combustor = 0.98_dp
        ic%combustor_pressure_loss = 0.030_dp
        ic%LHV_J_kg = 50.0e6_dp
        ic%eta_turbine = 0.89_dp
        ic%exhaust_pressure_loss = 0.020_dp
        ic%eta_mechanical = 0.990_dp
        ic%eta_generator = 0.985_dp
        ic%auxiliary_load_fraction = 0.020_dp
        ic%degradation_mode = "clean"
    end function baseline_case

    !> Publish the live state to the tag bus (HMI/OPC UA/logger contract).
    subroutine publish_tags(st)
        type(GridState), intent(in) :: st
        real(dp) :: t

        t = st%elapsed_s
        call tag_set("GRID.FREQ_HZ",          st%frequency_Hz,        "Hz",     t)
        call tag_set("GRID.NOMINAL_HZ",       st%nominal_frequency_Hz, "Hz",    t)
        call tag_set("GRID.ROCOF_HZ_S",       st%ROCOF_Hz_s,          "Hz/s",   t)
        call tag_set("GRID.DEMAND_MW",        st%demand_MW,           "MW",     t)
        call tag_set("GRID.SUPPLY_MW",        st%supply_MW,           "MW",     t)
        call tag_set("GRID.IMBALANCE_MW",     st%imbalance_MW,        "MW",     t)
        call tag_set("GRID.UFLS_STAGE",       real(st%UFLS_stage, dp), "-",     t)
        call tag_set("GRID.INERTIA_MWS",      merge(st%fleet_inertia_MWs, INERTIA_MWs, &
            st%fleet_mode), "MWs", t)
        call tag_set("GT1.POWER_MW",          st%gas_power_MW,        "MW",     t)
        call tag_set("GT1.CAPACITY_MW",       st%gas_capacity_MW,     "MW",     t)
        call tag_set("GT1.DISPATCH_PCT",      st%gas_dispatch_pct,    "%",      t)
        call tag_set("GT1.RESERVE_MW",        st%reserve_MW,          "MW",     t)
        call tag_set("GT1.GOVERNOR_MW",       st%governor_delta_MW,   "MW",     t)
        call tag_set("GT1.HEAT_RATE_KJ_KWH",  st%gt_heat_rate_kJ_kWh, "kJ/kWh", t)
        call tag_set("GT1.EXHAUST_K",         st%exhaust_K,           "K",      t)
        call tag_set("GT1.FUEL_KG_S",         st%fuel_flow_kg_s,      "kg/s",   t)
        call tag_set("GT1.TIT_K",             st%TIT_K,               "K",      t)
        call tag_set("GT1.TIT_ACTUAL_K",      st%TIT_actual_K,        "K",      t)
        call tag_set("GT1.AMBIENT_C",         st%ambient_C,           "degC",   t)
        call tag_set("GT1.SURGE_MARGIN_PCT",  st%surge_margin_pct,    "%",      t)
        call tag_set("GT1.IGV_PCT",           st%igv_pct,             "%",      t)
        call tag_set("GT1.PR",                st%PR_op,               "-",      t)
        call tag_set("PLANT.MODE_CC",         merge(1.0_dp, 0.0_dp, st%combined_cycle), "-", t)
        call tag_set("PLANT.THERMAL_MW",      st%plant_power_MW,      "MW",     t)
        call tag_set("PLANT.CAPACITY_MW",     st%plant_capacity_MW,   "MW",     t)
        call tag_set("PLANT.EFFICIENCY",      st%plant_efficiency,    "-",      t)
        call tag_set("PLANT.HEAT_RATE_KJ_KWH", st%heat_rate_kJ_kWh,   "kJ/kWh", t)
        call tag_set("ST1.POWER_MW",          st%steam_power_MW,      "MW",     t)
        call tag_set("ST1.TARGET_MW",         st%steam_power_target_MW, "MW",   t)
        call tag_set("ST1.COND_KPA",          st%condenser_pressure_kPa, "kPa", t)
        call tag_set("HRSG.RECOVERED_MW",     st%hrsg_recovered_heat_MW, "MW",  t)
        call tag_set("HRSG.STACK_K",          st%hrsg_stack_T_K,      "K",      t)
        call tag_set("HRSG.PINCH_K",          st%hrsg_pinch_K,        "K",      t)
        call tag_set("HRSG.STEAM_KG_S",       st%hrsg_steam_flow_kg_s, "kg/s",  t)
        call tag_set("FLEET.MODE",            merge(1.0_dp, 0.0_dp, st%fleet_mode), "-", t)
        call tag_set("FLEET.TARGET_MW",       st%fleet_load_target_MW, "MW",    t)
        call tag_set("FLEET.RESERVE_MW",      st%fleet_reserve_MW,    "MW",     t)
        call tag_set("FLEET.RESERVE_REQ_MW",  st%fleet_reserve_requirement_MW, "MW", t)
        call tag_set("FLEET.LMP_USD_MWH",     st%fleet_lmp_usd_MWh,   "USD/MWh", t)
        call tag_set("FLEET.FUEL_USD_GJ",     st%fuel_price_usd_gj,   "USD/GJ", t)
        call tag_set("FLEET.BINDING",         merge(1.0_dp, 0.0_dp, st%fleet_reserve_binding), "-", t)
        call tag_set("FLEET.UNSERVED_MW",     st%fleet_unserved_dispatch_MW, "MW", t)
        call tag_set("FLEET.MARGINAL_UNIT",   real(st%fleet_marginal_unit, dp), "-", t)
        call publish_unit_tags(st, t)
        call tag_set("REN.AVAILABLE_MW",      st%renewable_MW,        "MW",     t)
        call tag_set("REN.ACTUAL_MW",         effective_renewable_MW(st), "MW", t)
        call tag_set("REN.CURTAIL_MW",        st%renewable_curtail_MW, "MW",    t)
        call tag_set("REN.LFSMO_MW",          st%renewable_lfsmo_MW,  "MW",     t)
        call tag_set("BESS.POWER_MW",         st%storage_MW,          "MW",     t)
        call tag_set("BESS.REQUEST_MW",       st%storage_request_MW,  "MW",     t)
        call tag_set("BESS.PRIMARY_MW",       st%BESS_primary_MW,     "MW",     t)
        call tag_set("BESS.SOC_PCT",          st%battery_soc_pct,     "%",      t)
        call tag_set("BESS.ENERGY_MWH",       st%battery_energy_MWh,  "MWh",    t)
        call tag_set("MARKET.PROFILE",        real(st%market_profile_id, dp), "-", t)
        call tag_set("MARKET.POWER_USD_MWH",  st%power_price_usd_mwh, "USD/MWh", t)
        call tag_set("MARKET.FUEL_USD_GJ",    st%fuel_price_usd_gj,   "USD/GJ", t)
        call tag_set("MARKET.CARBON_USD_T",   st%carbon_price_usd_t,  "USD/t",  t)
        call tag_set("MARKET.FCR_USD_MW_H",   st%fcr_reserve_price_usd_mw_h, "USD/MW-h", t)
        call tag_set("MARKET.HOUR",           st%market_hour,         "h",      t)
        call tag_set("MARKET.SOURCE",         real(st%market_source_code, dp), "-", t)
        call tag_set("WX.WIND_M_S",           st%market_wind_speed_m_s, "m/s",  t)
        call tag_set("WX.SOLAR_W_M2",         st%market_solar_W_m2,   "W/m2",   t)
        call tag_set("WX.WIND_MW",            st%market_wind_power_MW, "MW",    t)
        call tag_set("WX.PV_MW",              st%market_pv_power_MW,  "MW",     t)
        call tag_set("ECON.MARGIN_USD_H",     st%margin_usd_h,        "USD/h",  t)
        call tag_set("ECON.REVENUE_USD_H",    st%revenue_usd_h,       "USD/h",  t)
        call tag_set("ECON.FUEL_USD_H",       st%fuel_cost_usd_h,     "USD/h",  t)
        call tag_set("ECON.CO2_USD_H",        st%co2_cost_usd_h,      "USD/h",  t)
        call tag_set("ECON.VALUE_STACK_USD_H", st%value_stack_usd_h,  "USD/h",  t)
        call tag_set("EMIS.CO2_KG_S",         st%CO2_rate_kg_s,       "kg/s",   t)
        call tag_set("EMIS.CO2_G_KWH",        st%CO2_intensity_g_kWh, "g/kWh",  t)
        call tag_set("EMIS.CO2_TOTAL_T",      st%CO2_cumulative_t,    "t",      t)
    end subroutine publish_tags

    subroutine publish_unit_tags(st, t)
        type(GridState), intent(in) :: st
        real(dp), intent(in) :: t

        call tag_set("FLEET.GT1.MW",      st%fleet_unit_actual_MW(FLEET_GT1), "MW", t)
        call tag_set("FLEET.GT1.SP_MW",   st%fleet_unit_setpoint_MW(FLEET_GT1), "MW", t)
        call tag_set("FLEET.GT1.ONLINE",  merge(1.0_dp, 0.0_dp, st%fleet_unit_online(FLEET_GT1)), "-", t)
        call tag_set("FLEET.GT1.COST",    st%fleet_unit_cost_usd_MWh(FLEET_GT1), "USD/MWh", t)
        call tag_set("FLEET.GT1.PART",    st%fleet_unit_participation(FLEET_GT1), "-", t)

        call tag_set("FLEET.GT2.MW",      st%fleet_unit_actual_MW(FLEET_GT2), "MW", t)
        call tag_set("FLEET.GT2.SP_MW",   st%fleet_unit_setpoint_MW(FLEET_GT2), "MW", t)
        call tag_set("FLEET.GT2.ONLINE",  merge(1.0_dp, 0.0_dp, st%fleet_unit_online(FLEET_GT2)), "-", t)
        call tag_set("FLEET.GT2.COST",    st%fleet_unit_cost_usd_MWh(FLEET_GT2), "USD/MWh", t)
        call tag_set("FLEET.GT2.PART",    st%fleet_unit_participation(FLEET_GT2), "-", t)

        call tag_set("FLEET.CC1.MW",      st%fleet_unit_actual_MW(FLEET_CC1), "MW", t)
        call tag_set("FLEET.CC1.SP_MW",   st%fleet_unit_setpoint_MW(FLEET_CC1), "MW", t)
        call tag_set("FLEET.CC1.ONLINE",  merge(1.0_dp, 0.0_dp, st%fleet_unit_online(FLEET_CC1)), "-", t)
        call tag_set("FLEET.CC1.COST",    st%fleet_unit_cost_usd_MWh(FLEET_CC1), "USD/MWh", t)
        call tag_set("FLEET.CC1.PART",    st%fleet_unit_participation(FLEET_CC1), "-", t)
    end subroutine publish_unit_tags

end module engine_core
