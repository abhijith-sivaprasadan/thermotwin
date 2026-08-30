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
    use dispatch_agc, only: tick_auto_balance, tick_frequency_support, balance_now, reset_controls, &
        ramp_renewable_curtailment_to, should_curtail_renewables, &
        apply_load_step, apply_cloud_ramp, apply_turbine_trip
    use plant_economics, only: refresh_economics
    use minlp_dayahead, only: solve_dayahead, compute_pareto_front
    use gt_optimizer,   only: solve_gt_optimizer
    use fleet_uc,       only: solve_fleet_uc
    use dnn_surrogate,  only: dnn_init, DNN_ACTIVE, DNN_POLICY_ACTIVE, DNN_HR_MAE, &
                               dnn_online_update, dnn_heat_rate_mc
    use model_validation, only: ModelValidationResult, run_model_validation
    use physics_fidelity, only: refresh_physics_fidelity
    use h2_blend,       only: compute_h2_blend
    use combustion_physics, only: CombustionPhysicsResult, solve_combustion_physics
    use anomaly_detector, only: update_anomaly_detector, reset_anomaly_detector
    use p2x_electrolyser, only: p2x_step
    use ccs_model,      only: ccs_step
    use gfm_bess,       only: gfm_step
    use tie_line,       only: tie_line_step
    use mpc_agc,        only: mpc_step
    use rl_dispatch,      only: rl_step, rl_reset
    use fault_classifier, only: update_fault_classifier
    use forecast_engine,  only: update_forecast
    use tag_bus, only: tag_set
    implicit none
    private

    integer, save :: da_tick_counter        = 0
    integer, save :: gt_opt_tick_counter    = 0
    integer, save :: fleet_uc_tick_counter  = 0
    integer, save :: ai_tick_counter        = 0   ! AI/ML sub-step counter (forecast every 4 ticks)

    ! Orchestration API
    public :: engine_init, engine_step, refresh_model, refresh_model_validation, update_battery_soc
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
    public :: PI_DP, HISTORY_N, DA_H, GT_OPT_N, FC_N, PARETO_N, FIDELITY_N
    public :: DNN_ACTIVE, DNN_POLICY_ACTIVE, DNN_HR_MAE
    public :: compute_h2_blend, compute_pareto_front
    public :: reset_anomaly_detector, rl_reset

contains

    !> Reset to the default operating point and solve the initial cycle.
    !> The live engine runs with temperature-dependent gas properties; the
    !> constant-property model remains the default elsewhere so the verified
    !> hand calculation (selftest) is untouched.
    subroutine engine_init(st)
        type(GridState), intent(inout) :: st

        ! Load DNN surrogate weights before the first solve.
        ! Falls back silently to the polynomial model if the file is absent.
        call dnn_init("dnn_weights.txt")
        st%dnn_active = DNN_ACTIVE
        st%dnn_hr_mae = DNN_HR_MAE

        call set_property_model(PROP_VARIABLE)
        call reset_controls(st)
        st%prev_gas_dispatch_pct = st%gas_dispatch_pct
        st%gas_ramp_pct_per_s = 0.0_dp
        call refresh_model(st)
        da_tick_counter = 0
        gt_opt_tick_counter = 0
        fleet_uc_tick_counter = 0
        call solve_dayahead(st)
        call solve_gt_optimizer(st)
        call compute_wash_roi(st)
        call check_intraday_redispatch(st)
        call solve_fleet_uc(st)
        call refresh_model_validation(st)
        call publish_tags(st)
    end subroutine engine_init

    !> Advance the whole simulation by one tick.
    subroutine engine_step(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        real(dp) :: old_ou_demand_noise, old_ou_wind_noise

        st%elapsed_s = st%elapsed_s + dt_s
        old_ou_demand_noise = st%ou_demand_noise
        old_ou_wind_noise = st%ou_wind_noise
        call refresh_market_data(st, dt_s)      ! location weather, prices, and replayed load
        call tick_ou_disturbance(st, dt_s, old_ou_demand_noise, old_ou_wind_noise)
        call tick_auto_balance(st, dt_s)        ! AGC secondary ramp
        call tick_frequency_support(st, dt_s)  ! BESS+RES freq support even in MANUAL mode
        ! Dispatch slew rate over this tick (slider moves + AGC combined);
        ! upward ramps drive the transient surge-margin excursion.
        st%gas_ramp_pct_per_s = (st%gas_dispatch_pct - st%prev_gas_dispatch_pct) / dt_s
        st%prev_gas_dispatch_pct = st%gas_dispatch_pct
        call refresh_model(st, dt_s)            ! gas/steam power, imbalance, economics
        call update_battery_soc(st, dt_s)       ! SOC tracking
        call tick_frequency_dynamics(st, dt_s)  ! swing eq + primary response + UFLS
        st%CO2_cumulative_t = st%CO2_cumulative_t + &
            st%CO2_rate_kg_s * dt_s / 1000.0_dp
        ! Daily CO2 accumulation (resets every 86400 sim-seconds)
        st%co2_daily_t = st%co2_daily_t + st%CO2_rate_kg_s * dt_s / 1000.0_dp
        if (mod(int(st%elapsed_s), 86400) < int(dt_s) + 1 .and. st%elapsed_s > dt_s) &
            st%co2_daily_t = 0.0_dp
        ! Baseline CO2 if running on pure NG at the same fuel flow
        st%co2_daily_ref_t = st%co2_daily_ref_t + &
            st%fuel_flow_kg_s * CO2_KG_PER_KG_FUEL * dt_s / 1000.0_dp
        if (mod(int(st%elapsed_s), 86400) < int(dt_s) + 1 .and. st%elapsed_s > dt_s) &
            st%co2_daily_ref_t = 0.0_dp
        ! Cumulative CO2 avoided vs pure-NG baseline
        st%h2_co2_avoided_t = st%h2_co2_avoided_t + &
            (CO2_KG_PER_KG_FUEL - st%h2_co2_factor) * st%fuel_flow_kg_s * dt_s / 1000.0_dp
        call append_history(st)
        ! Re-solve day-ahead MINLP every 20 ticks (~5 s at 250 ms / tick)
        da_tick_counter = da_tick_counter + 1
        if (da_tick_counter >= 20) then
            da_tick_counter = 0
            call solve_dayahead(st)
        end if
        ! P2 GT economic dispatch optimizer every 8 ticks (~2 s)
        gt_opt_tick_counter = gt_opt_tick_counter + 1
        if (gt_opt_tick_counter >= 8) then
            gt_opt_tick_counter = 0
            call solve_gt_optimizer(st)
            call compute_wash_roi(st)
            call check_intraday_redispatch(st)
        end if
        ! P1 Fleet UC + economic dispatch every 16 ticks (~4 s)
        fleet_uc_tick_counter = fleet_uc_tick_counter + 1
        if (fleet_uc_tick_counter >= 16) then
            fleet_uc_tick_counter = 0
            call solve_fleet_uc(st)
        end if
        ! ── AI/ML layer ──────────────────────────────────────────────────────────
        ! RL: if RL mode is active, override storage request before next physics tick
        if (st%rl_mode) then
            call rl_step(st)
            st%storage_request_MW = st%rl_storage_setpt
        end if

        ! Anomaly detector every tick (EWMA is lightweight)
        call update_anomaly_detector(st)

        ! Fault classifier every tick
        call update_fault_classifier(st)

        ! Online DNN adaptation every tick (if active and DNN loaded)
        if (st%dnn_adapting .and. DNN_ACTIVE .and. st%plant_power_MW > 1.0_dp) then
            call dnn_online_update( &
                st%plant_power_MW / st%gas_capacity_MW, &
                st%ambient_C, &
                st%TIT_K, &
                st%wash_hr_gap_pct, &
                st%gt_heat_rate_kJ_kWh, &
                st%dnn_online_bias, st%dnn_online_rmse, st%dnn_online_n)
        end if

        ! Forecast update every 4 ticks (~1 s) — heavier extrapolation
        ai_tick_counter = ai_tick_counter + 1
        if (ai_tick_counter >= 4) then
            ai_tick_counter = 0
            call update_forecast(st)
            call build_advisory(st)
            call refresh_model_validation(st)
        end if

        ! ── New physics modules ──────────────────────────────────────────────────
        ! P2X electrolyser: absorb curtailed renewable power
        call p2x_step(st, dt_s)

        ! GFM BESS: add virtual inertia + droop response to storage_request
        if (st%gfm_mode) then
            call gfm_step(st, dt_s)
        else
            st%gfm_synth_MW = 0.0_dp
            st%gfm_H_equiv = 0.0_dp
        end if

        ! Tie-line + ACE: advance two-zone dynamics
        if (st%tie_active) call tie_line_step(st, dt_s)

        ! MPC-AGC: compute 5-step optimal setpoint, apply as dispatch %
        if (st%mpc_active) then
            call mpc_step(st)
            if (st%gas_capacity_MW > 0.0_dp) &
                st%gas_dispatch_pct = min(100.0_dp, max(30.0_dp, &
                    st%mpc_setpt_MW / st%gas_capacity_MW * 100.0_dp))
        else
            st%mpc_setpt_MW = 0.0_dp
            st%mpc_cost_last = 0.0_dp
            st%mpc_horizon_ready = .false.
            st%mpc_horizon_n = 0
            st%mpc_cost_hold = 0.0_dp
            st%mpc_cost_saving = 0.0_dp
            st%mpc_pred_time_s = 0.0_dp
            st%mpc_pred_freq_Hz = FREQ_NOMINAL_HZ
            st%mpc_pred_pgen_MW = 0.0_dp
            st%mpc_pred_setpt_MW = 0.0_dp
            st%mpc_pred_imbalance_MW = 0.0_dp
        end if

        ! ── Frequency nadir predictor ─────────────────────────────────────────────
        ! ROCOF: Hz/s from consecutive ticks (250 ms)
        st%freq_rocof_Hz_s = (st%frequency_Hz - st%freq_prev_Hz) / max(dt_s, 1.0e-6_dp)
        st%freq_prev_Hz    = st%frequency_Hz
        ! Predicted nadir for N-1 trip: Δf_nadir ≈ −ΔP·f₀ / (2·H·P_load)
        block
            real(dp) :: h_total, p_load
            h_total = INERTIA_MWs / max(st%gas_capacity_MW, 1.0_dp)
            if (st%gfm_mode) h_total = h_total + st%gfm_virtual_H * 0.2_dp
            p_load  = max(st%demand_MW, 10.0_dp)
            st%freq_nadir_Hz = FREQ_NOMINAL_HZ &
                - st%nadir_trip_MW * FREQ_NOMINAL_HZ / (2.0_dp * h_total * p_load)
            st%freq_nadir_Hz = max(47.0_dp, st%freq_nadir_Hz)
        end block

        ! ── Hot-parts LCF counter ─────────────────────────────────────────────────
        block
            logical :: is_running
            real(dp), parameter :: COMP_DESIGN_STARTS = 500.0_dp    ! design life in starts
            real(dp), parameter :: HST_DESIGN_HOURS   = 24000.0_dp  ! hot-section design life [h]
            real(dp), parameter :: HRSG_DESIGN_HOURS  = 100000.0_dp ! HRSG design life [h]
            is_running = st%plant_power_MW > 1.0_dp
            if (is_running .and. .not. st%lcf_was_running) then
                st%lcf_starts = st%lcf_starts + 1
            end if
            if (is_running .and. st%TIT_actual_K > 900.0_dp) then
                st%lcf_hot_hours = st%lcf_hot_hours + dt_s / 3600.0_dp
            end if
            st%lcf_was_running = is_running
            st%lcf_comp_life_pct = min(100.0_dp, real(st%lcf_starts, dp) / COMP_DESIGN_STARTS * 100.0_dp)
            st%lcf_hst_life_pct  = min(100.0_dp, st%lcf_hot_hours / HST_DESIGN_HOURS   * 100.0_dp)
            st%lcf_hrsg_life_pct = min(100.0_dp, st%lcf_hot_hours / HRSG_DESIGN_HOURS  * 100.0_dp)
        end block

        ! ── DNN MC-dropout uncertainty (every 8 ticks to reduce cost) ────────────
        if (DNN_ACTIVE .and. st%plant_power_MW > 1.0_dp) then
            block
                integer, save :: mc_tick = 0
                real(dp) :: mc_mean
                mc_tick = mc_tick + 1
                if (mc_tick >= 8) then
                    mc_tick = 0
                    call dnn_heat_rate_mc( &
                        st%plant_power_MW / st%gas_capacity_MW, &
                        st%ambient_C, st%TIT_K, st%wash_hr_gap_pct, &
                        mc_mean, st%dnn_hr_sigma)
                end if
            end block
        end if

        call publish_tags(st)
    end subroutine engine_step

    !> Mean-reverting stochastic load/renewable disturbance. Apply only the
    !> change in OU state unless market replay/weather has just refreshed the
    !> underlying base signal for this tick.
    subroutine tick_ou_disturbance(st, dt_s, old_demand_noise, old_wind_noise)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s, old_demand_noise, old_wind_noise
        real(dp) :: dW_d, dW_w, r
        real(dp) :: demand_delta, wind_delta

        if (st%ou_active) then
            ! Park-Miller LCG for reproducible operator-training disturbances.
            st%ou_iseed = mod(st%ou_iseed * 48271, 2147483647)
            r = real(st%ou_iseed, dp) / 2147483647.0_dp - 0.5_dp
            dW_d = r * sqrt(dt_s)
            st%ou_iseed = mod(st%ou_iseed * 48271, 2147483647)
            r = real(st%ou_iseed, dp) / 2147483647.0_dp - 0.5_dp
            dW_w = r * sqrt(dt_s)
            st%ou_demand_noise = st%ou_demand_noise &
                - (st%ou_demand_noise / st%ou_tau_demand) * dt_s &
                + st%ou_sigma_demand * sqrt(2.0_dp / st%ou_tau_demand) * dW_d
            st%ou_wind_noise = st%ou_wind_noise &
                - (st%ou_wind_noise / st%ou_tau_wind) * dt_s &
                + st%ou_sigma_wind * sqrt(2.0_dp / st%ou_tau_wind) * dW_w

            if (st%market_load_replay_enabled) then
                demand_delta = st%ou_demand_noise
            else
                demand_delta = st%ou_demand_noise - old_demand_noise
            end if
            if (st%market_weather_enabled) then
                wind_delta = st%ou_wind_noise
            else
                wind_delta = st%ou_wind_noise - old_wind_noise
            end if
        else
            demand_delta = merge(0.0_dp, -old_demand_noise, st%market_load_replay_enabled)
            wind_delta = merge(0.0_dp, -old_wind_noise, st%market_weather_enabled)
            st%ou_demand_noise = 0.0_dp
            st%ou_wind_noise = 0.0_dp
        end if

        st%demand_MW = clamp_real(st%demand_MW + demand_delta, DEMAND_MIN_MW, DEMAND_MAX_MW)
        st%renewable_MW = clamp_real(st%renewable_MW + wind_delta, 0.0_dp, RENEWABLE_MAX_MW)
        st%renewable_curtail_MW = min(st%renewable_curtail_MW, st%renewable_MW)
    end subroutine tick_ou_disturbance

    subroutine refresh_model_validation(st)
        type(GridState), intent(inout) :: st
        type(ModelValidationResult) :: mv

        call run_model_validation(mv)
        st%model_val_ready = mv%ready
        st%model_val_dnn_available = mv%dnn_available
        st%model_val_n = mv%n
        st%model_val_worst_idx = mv%worst_idx
        st%model_val_cycle_power_mae_MW = mv%cycle_power_mae_MW
        st%model_val_cycle_power_bias_MW = mv%cycle_power_bias_MW
        st%model_val_cycle_hr_mae_kJ_kWh = mv%cycle_hr_mae_kJ_kWh
        st%model_val_cycle_hr_bias_kJ_kWh = mv%cycle_hr_bias_kJ_kWh
        st%model_val_dnn_hr_mae_kJ_kWh = mv%dnn_hr_mae_kJ_kWh
        st%model_val_dnn_hr_bias_kJ_kWh = mv%dnn_hr_bias_kJ_kWh
        st%model_val_dnn_hr_max_abs_kJ_kWh = mv%dnn_hr_max_abs_kJ_kWh
    end subroutine refresh_model_validation

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
        type(CombustionPhysicsResult) :: comb
        real(dp) :: load_fraction, cc_capacity_MW, cc_heat_rate_kJ_kWh
        real(dp) :: step_s

        ic = baseline_case()
        ic%ambient_T_K = st%ambient_C + KELVIN_OFFSET
        ic%T_turbine_inlet_K = st%TIT_K

        ! H2 co-firing: update blend properties and override LHV for this solve
        call compute_h2_blend(st%h2_fraction_pct, &
                              st%h2_lhv_mj_kg, st%h2_co2_factor, &
                              st%h2_nox_factor, st%h2_wobbe_ok)
        ic%LHV_J_kg = st%h2_lhv_mj_kg * 1.0e6_dp
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
        call solve_combustion_physics(st%h2_fraction_pct, od%cyc%T2_K, od%cyc%T3_K, &
            od%cyc%T4_K, ic%ambient_T_K, od%cyc%fuel_air_ratio, od%cyc%mdot_air_kg_s, &
            st%gas_dispatch_pct, od%flow_frac, od%PR_op, ic%eta_compressor, ic%eta_turbine, comb)
        st%h2_lhv_mj_kg = comb%lhv_mj_kg
        st%h2_co2_factor = comb%co2_factor_kg_kg
        st%h2_nox_factor = comb%nox_factor
        st%h2_wobbe_ok = comb%wobbe_ok
        st%h2_mass_fraction = comb%h2_mass_fraction
        st%h2_wobbe_mj_m3 = comb%wobbe_mj_m3
        st%h2_wobbe_deviation_pct = comb%wobbe_deviation_pct
        st%flame_temp_ad_K = comb%adiabatic_flame_T_K
        st%flame_temp_shift_K = comb%flame_shift_K
        st%nox_ppm_15o2 = comb%nox_ppm_15o2
        st%nox_mg_nm3_15o2 = comb%nox_mg_nm3_15o2
        st%co_ppm_15o2 = comb%co_ppm_15o2
        st%co_mg_nm3_15o2 = comb%co_mg_nm3_15o2
        st%stack_o2_dry_pct = comb%o2_dry_pct
        st%stack_co2_vol_pct = comb%co2_vol_pct
        st%combustion_lambda = comb%lambda
        st%flashback_margin_pct = comb%flashback_margin_pct
        st%turbine_cooling_air_pct = comb%cooling_air_pct
        st%turbine_cooling_air_kg_s = comb%cooling_air_kg_s
        st%turbine_metal_margin_K = comb%metal_temp_margin_K
        st%tip_clearance_mm = comb%tip_clearance_mm
        st%tip_loss_pct = comb%tip_loss_pct
        st%compressor_poly_loss_pct = comb%compressor_poly_loss_pct
        st%turbine_poly_loss_pct = comb%turbine_poly_loss_pct
        st%combustor_pattern_factor_pct = comb%combustor_pattern_factor_pct
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
        call refresh_fleet_dispatch(st, step_s, st%gas_capacity_MW, st%gt_heat_rate_kJ_kWh, &
            cc_capacity_MW, cc_heat_rate_kJ_kWh)
        call ccs_step(st)
        if (st%heat_input_MW > 1.0e-9_dp) then
            st%plant_efficiency = st%plant_power_MW / st%heat_input_MW
            st%heat_rate_kJ_kWh = 3600.0_dp / max(st%plant_efficiency, 1.0e-9_dp)
        else
            st%plant_efficiency = 0.0_dp
            st%heat_rate_kJ_kWh = huge(1.0_dp)
        end if
        st%supply_MW = thermal_generation_MW(st) + effective_renewable_MW(st) + st%storage_MW
        st%imbalance_MW = st%supply_MW - st%demand_MW
        if (.not. st%fleet_mode) st%reserve_MW = max(0.0_dp, st%plant_capacity_MW - st%plant_power_MW)
        ! frequency_Hz is integrated by tick_frequency_dynamics; not recomputed here
        call refresh_economics(st)
        call refresh_physics_fidelity(st)
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
        call tag_set("GT1.HR_REF_KJ_KWH",     st%physics_gt_hr_ref_kJ_kWh, "kJ/kWh", t)
        call tag_set("GT1.HR_GAP_PCT",        st%physics_gt_hr_gap_pct, "%",      t)
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
        call tag_set("HRSG.PINCH_REF_K",      st%physics_hrsg_pinch_ref_K, "K",  t)
        call tag_set("HRSG.PINCH_GAP_K",      st%physics_hrsg_pinch_gap_K, "K",  t)
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
        call tag_set("EMIS.NOX_PPM_15O2",     st%nox_ppm_15o2,        "ppm",    t)
        call tag_set("EMIS.NOX_MG_NM3",       st%nox_mg_nm3_15o2,     "mg/Nm3", t)
        call tag_set("EMIS.CO_PPM_15O2",      st%co_ppm_15o2,         "ppm",    t)
        call tag_set("EMIS.CO_MG_NM3",        st%co_mg_nm3_15o2,      "mg/Nm3", t)
        call tag_set("EMIS.O2_DRY_PCT",       st%stack_o2_dry_pct,    "%",      t)
        call tag_set("EMIS.CO2_VOL_PCT",      st%stack_co2_vol_pct,   "%",      t)
        call tag_set("COMB.FLAME_T_AD_K",     st%flame_temp_ad_K,     "K",      t)
        call tag_set("COMB.FLAME_SHIFT_K",    st%flame_temp_shift_K,  "K",      t)
        call tag_set("COMB.FLASHBACK_MARGIN_PCT", st%flashback_margin_pct, "%", t)
        call tag_set("COMB.WOBBE_MJ_M3",      st%h2_wobbe_mj_m3,      "MJ/m3",  t)
        call tag_set("COMB.WOBBE_DEV_PCT",    st%h2_wobbe_deviation_pct, "%",   t)
        call tag_set("GT1.COOLING_AIR_PCT",   st%turbine_cooling_air_pct, "%",   t)
        call tag_set("GT1.COOLING_AIR_KG_S",  st%turbine_cooling_air_kg_s, "kg/s", t)
        call tag_set("GT1.TIP_CLEARANCE_MM",  st%tip_clearance_mm,    "mm",     t)
        call tag_set("GT1.TIP_LOSS_PCT",      st%tip_loss_pct,        "%",      t)
        call tag_set("GT1.COMP_POLY_LOSS_PCT", st%compressor_poly_loss_pct, "%", t)
        call tag_set("GT1.TURB_POLY_LOSS_PCT", st%turbine_poly_loss_pct, "%",   t)
    end subroutine publish_tags

    ! -------------------------------------------------------------------------
    ! Compressor washing ROI: estimate daily fuel saving and breakeven interval.
    ! -------------------------------------------------------------------------
    subroutine compute_wash_roi(st)
        type(GridState), intent(inout) :: st
        real(dp), parameter :: WASH_USD    = 2500.0_dp
        real(dp), parameter :: WASH_HOURS  = 6.0_dp
        real(dp), parameter :: DISPATCH_H  = 18.0_dp
        real(dp) :: delta_hr, dispatch_MW, saving_rate, downtime_cost
        real(dp) :: load_frac, hr_clean_ref, w
        integer  :: idx_lo, idx_hi

        dispatch_MW = max(1.0_dp, st%gas_power_MW)

        ! Clean HR reference at current load: interpolate from the optimizer scan,
        ! which runs with degradation_mode="clean" so it captures only part-load
        ! effects without fouling. Delta is the fouling-only penalty.
        if (st%gt_opt_solved .and. st%gas_capacity_MW > 0.0_dp) then
            load_frac = min(1.0_dp, max(0.30_dp, dispatch_MW / st%gas_capacity_MW))
            w       = (load_frac - 0.30_dp) / 0.70_dp * real(GT_OPT_N - 1, dp) + 1.0_dp
            idx_lo  = max(1, min(GT_OPT_N,     int(w)))
            idx_hi  = max(1, min(GT_OPT_N, idx_lo + 1))
            w       = w - real(idx_lo, dp)
            hr_clean_ref = st%gt_opt_hr(idx_lo) * (1.0_dp - w) + st%gt_opt_hr(idx_hi) * w
        else
            hr_clean_ref = 9200.0_dp
        end if

        delta_hr = max(0.0_dp, st%gt_heat_rate_kJ_kWh - hr_clean_ref)
        st%wash_hr_gap_pct = delta_hr / max(hr_clean_ref, 1.0_dp) * 100.0_dp
        saving_rate = dispatch_MW * delta_hr * st%fuel_price_usd_gj / 1000.0_dp
        st%wash_daily_saving_usd = saving_rate * DISPATCH_H
        if (st%wash_daily_saving_usd > 0.5_dp) then
            downtime_cost = WASH_HOURS * dispatch_MW * st%power_price_usd_mwh
            st%wash_breakeven_days = (WASH_USD + downtime_cost) / st%wash_daily_saving_usd
        else
            st%wash_breakeven_days = 999.0_dp
        end if
    end subroutine compute_wash_roi

    ! -------------------------------------------------------------------------
    ! Intraday re-dispatch: compare DA plan with current P2 optimum.
    ! -------------------------------------------------------------------------
    subroutine check_intraday_redispatch(st)
        type(GridState), intent(inout) :: st
        integer  :: cur_h
        real(dp) :: saving_h, hours_remaining

        if (.not. st%da_solved .or. .not. st%gt_opt_solved) then
            st%da_redispatch_saving_usd = 0.0_dp
            return
        end if
        cur_h = max(1, min(DA_H, int(mod(st%market_hour, 24.0_dp)) + 1))
        st%da_current_hour = cur_h
        saving_h = st%gt_opt_saving_h        ! P2 margin improvement vs current dispatch [$/h]
        hours_remaining = max(1.0_dp, real(DA_H - cur_h + 1, dp))
        if (saving_h > 5.0_dp) then
            st%da_redispatch_saving_usd = saving_h * hours_remaining
        else
            st%da_redispatch_saving_usd = 0.0_dp
        end if
    end subroutine check_intraday_redispatch

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

    ! ── Operator advisory NLP ──────────────────────────────────────────────────
    ! Maps alarm combos + anomaly + fault classifier → operator-readable narrative.
    subroutine build_advisory(st)
        type(GridState), intent(inout) :: st
        character(len=2048) :: txt
        integer :: h
        character(len=40) :: s1, s2

        ! Hash current alarm/anomaly state; skip if unchanged
        h = merge(1,0,st%alarm_surge) * 1 + merge(1,0,st%alarm_turbine_max) * 2 + &
            merge(1,0,st%alarm_underfreq) * 4 + merge(1,0,st%alarm_overfreq) * 8 + &
            merge(1,0,st%alarm_hrsg_pinch) * 16 + merge(1,0,st%alarm_low_reserve) * 32 + &
            merge(1,0,st%alarm_low_soc) * 64 + &
            int(st%anom_composite) * 128 + st%fc_class1 * 1024 + &
            merge(1,0,.not. st%auto_balance .and. abs(st%frequency_Hz - FREQ_NOMINAL_HZ) > 0.3_dp) * 2048 + &
            merge(1,0, st%renewable_curtail_MW > 2.0_dp) * 4096 + &
            merge(1,0, st%battery_soc_pct > 70.0_dp) * 8192 + &
            merge(1,0, st%gas_dispatch_pct > 90.0_dp) * 16384
        if (h == st%advisory_hash .and. st%anom_tick > 1) return
        st%advisory_hash = h

        txt = ""

        ! Priority 1 — active alarms
        if (st%alarm_surge) then
            write(s1,'(F5.1)') st%surge_margin_pct
            txt = trim(txt) // "ALERT — Compressor surge: margin " // trim(adjustl(s1)) // &
                  "% below safe floor. Action: reduce gas dispatch 5-10 %, open " // &
                  "bleed valve, check IGV schedule." // char(10) // char(10)
        end if
        if (st%alarm_turbine_max) then
            write(s1,'(I6)') nint(st%TIT_actual_K)
            txt = trim(txt) // "ALERT — TIT limiter active at " // trim(adjustl(s1)) // &
                  " K. Action: reduce load setpoint or increase inlet cooling. " // &
                  "Check fuel schedule for bias." // char(10) // char(10)
        end if
        if (st%alarm_underfreq) then
            write(s1,'(F6.3)') st%frequency_Hz
            txt = trim(txt) // "ALERT — Under-frequency: " // trim(adjustl(s1)) // &
                  " Hz. BESS primary response active. Action: increase GT dispatch " // &
                  "or shed controllable load." // char(10) // char(10)
        end if
        if (st%alarm_overfreq) then
            txt = trim(txt) // "ALERT — Over-frequency. Excess generation. Action: " // &
                  "curtail renewables or back down GT to minimum load." // char(10) // char(10)
        end if
        if (st%alarm_hrsg_pinch) then
            write(s1,'(F5.1)') st%hrsg_pinch_K
            txt = trim(txt) // "ALERT — HRSG pinch violation (" // trim(adjustl(s1)) // &
                  " K). Risk of steam starvation. Action: reduce exhaust bypass " // &
                  "or de-load HRSG until pinch recovers." // char(10) // char(10)
        end if
        if (st%alarm_low_soc) then
            write(s1,'(F5.1)') st%battery_soc_pct
            txt = trim(txt) // "ALERT — BESS SoC critical (" // trim(adjustl(s1)) // &
                  "%). FCR capability suspended. Action: enable charge mode, " // &
                  "reduce BESS primary response obligation." // char(10) // char(10)
        end if

        ! Priority 2 — ML fault classifier
        if (st%fc_class1 > 0 .and. st%fc_conf1 > 0.3_dp) then
            write(s1,'(I3)') nint(st%fc_conf1 * 100.0_dp)
            select case (st%fc_class1)
            case (1)
                txt = trim(txt) // "DIAGNOSIS (" // trim(adjustl(s1)) // "% confidence) — " // &
                      "Compressor fouling. Heat-rate elevated; surge margin degrading. " // &
                      "Recommend offline wash within 48 h." // char(10)
            case (2)
                txt = trim(txt) // "DIAGNOSIS (" // trim(adjustl(s1)) // "% confidence) — " // &
                      "Tip-clearance loss. Turbine efficiency degraded; exhaust anomalous. " // &
                      "Schedule borescope at next outage window." // char(10)
            case (3)
                txt = trim(txt) // "DIAGNOSIS (" // trim(adjustl(s1)) // "% confidence) — " // &
                      "TBC spallation suspected. TIT repeatedly near limit; thermal " // &
                      "gradient abnormal. Reduce load, schedule hot-section inspection." // char(10)
            case (4)
                txt = trim(txt) // "DIAGNOSIS (" // trim(adjustl(s1)) // "% confidence) — " // &
                      "Fuel control valve bias. Fuel flow deviates from power-set model. " // &
                      "Calibrate valve or schedule instrument check." // char(10)
            case (5)
                txt = trim(txt) // "DIAGNOSIS (" // trim(adjustl(s1)) // "% confidence) — " // &
                      "Sensor drift (isolated). Single channel anomalous; physical state " // &
                      "within envelope. Verify and re-zero suspect transmitter." // char(10)
            case (6)
                txt = trim(txt) // "DIAGNOSIS (" // trim(adjustl(s1)) // "% confidence) — " // &
                      "HRSG pinch approaching. Stack conditions trending toward minimum " // &
                      "allowable ΔT. Reduce steam extraction or exhaust bypass." // char(10)
            end select
            if (st%fc_class2 > 0 .and. st%fc_conf2 > 0.2_dp) then
                write(s2,'(I3)') nint(st%fc_conf2 * 100.0_dp)
                txt = trim(txt) // "(Secondary: class " // char(48 + st%fc_class2) // &
                      " at " // trim(adjustl(s2)) // "%)" // char(10)
            end if
            txt = trim(txt) // char(10)
        end if

        ! Priority 3 — anomaly summary
        if (st%anom_composite > 2.0_dp .and. st%anom_tick > 20) then
            write(s1,'(F4.1)') st%anom_composite
            txt = trim(txt) // "ANOMALY — Composite sensor Z-score " // trim(adjustl(s1)) // &
                  " (>2 = attention, >4 = investigate). "
            if (st%anom_score_hr > 3.0_dp) txt = trim(txt) // "Heat-rate drift detected. "
            if (st%anom_score_tex > 3.0_dp) txt = trim(txt) // "Exhaust temperature anomaly. "
            if (st%anom_score_sm > 3.0_dp)  txt = trim(txt) // "Surge margin abnormal. "
            if (st%anom_score_eta > 3.0_dp) txt = trim(txt) // "GT efficiency declining. "
            txt = trim(txt) // char(10) // char(10)
        end if

        ! Priority 3.5 — operational optimisation advisories (stack with alarms/faults)
        if (.not. st%auto_balance .and. abs(st%frequency_Hz - FREQ_NOMINAL_HZ) > 0.3_dp) then
            write(s1,'(F6.3)') st%frequency_Hz
            if (st%frequency_Hz > FREQ_NOMINAL_HZ) then
                txt = trim(txt) // "OPT — Grid over-frequency (" // trim(adjustl(s1)) // &
                      " Hz) in MANUAL mode. BESS frequency-support active. " // &
                      "Press BALANCE 1X or enable AUTO to restore 50 Hz." // char(10) // char(10)
            else
                txt = trim(txt) // "OPT — Grid under-frequency (" // trim(adjustl(s1)) // &
                      " Hz) in MANUAL mode. BESS frequency-support active. " // &
                      "Press BALANCE 1X or enable AUTO to restore 50 Hz." // char(10) // char(10)
            end if
        end if
        if (st%renewable_curtail_MW > 2.0_dp .and. st%gas_dispatch_pct > 70.0_dp) then
            write(s1,'(F4.1)') st%renewable_curtail_MW
            txt = trim(txt) // "OPT — " // trim(adjustl(s1)) // " MW renewable curtailed while " // &
                  "GT runs above 70%. Back down GT dispatch or expand RES capacity to reduce " // &
                  "fuel cost and CO2." // char(10) // char(10)
        else if (st%renewable_MW < 10.0_dp .and. st%gas_dispatch_pct > 75.0_dp) then
            txt = trim(txt) // "OPT — GT carrying most of the load with minimal renewables online. " // &
                  "Deploying additional wind/solar capacity would lower LCOE and " // &
                  "decarbonise the portfolio." // char(10) // char(10)
        end if
        if (st%battery_soc_pct > 70.0_dp .and. st%power_price_usd_mwh > 90.0_dp &
                .and. st%storage_request_MW < 2.0_dp) then
            write(s1,'(F5.1)') st%battery_soc_pct
            write(s2,'(I3)') nint(st%power_price_usd_mwh)
            txt = trim(txt) // "OPT — BESS SoC " // trim(adjustl(s1)) // "% with spot $" // &
                  trim(adjustl(s2)) // "/MWh — high-price discharge opportunity. " // &
                  "Enable ROI dispatch to capture arbitrage value." // char(10) // char(10)
        end if
        if (st%gas_dispatch_pct > 90.0_dp .and. &
                st%reserve_MW < 0.1_dp * max(1.0_dp, st%plant_capacity_MW)) then
            txt = trim(txt) // "OPT — Plant operating near capacity ceiling with low reserve margin. " // &
                  "Consider adding peaker capacity or demand-side response to maintain N-1 " // &
                  "security." // char(10) // char(10)
        end if

        ! Priority 4 — normal/green status
        if (len_trim(txt) == 0) then
            write(s1,'(F5.2)') st%gt_thermal_efficiency * 100.0_dp
            write(s2,'(F5.1)') st%surge_margin_pct
            txt = "STATUS OK — All systems nominal. GT efficiency " // &
                  trim(adjustl(s1)) // "%, surge margin " // trim(adjustl(s2)) // &
                  "%. No anomalies detected. BESS ready."
            if (st%rl_mode) txt = trim(txt) // char(10) // &
                "RL dispatch policy active — Q-table learning in progress."
        end if

        st%advisory_text = txt
    end subroutine build_advisory

end module engine_core
