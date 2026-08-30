!> @file engine_state.f90
!> @brief Shared state and parameters for the ThermoTwin-F plant/grid engine.
!>
!> Phase 0 of the revamp (docs/REVAMP_PLAN.md): the simulation engine is
!> extracted from the Win32 GUI so it can be unit-tested, scripted, and later
!> exposed over OPC UA. This module owns the GridState derived type and every
!> physical/economic parameter. It has no GUI or Win32 dependency.
module engine_state
    use precision_kinds, only: dp
    implicit none
    private

    public :: GridState, clamp_real
    public :: FLEET_N, FLEET_GT1, FLEET_GT2, FLEET_CC1, FLEET_UNIT_NAME
    public :: effective_renewable_MW, renewable_headroom_MW
    public :: bottoming_power_MW, thermal_generation_MW
    public :: limited_storage_power, append_history, history_index

    ! --- Operator-adjustable ranges -------------------------------------
    real(dp), parameter, public :: DEMAND_MIN_MW = 10.0_dp
    real(dp), parameter, public :: DEMAND_MAX_MW = 100.0_dp
    real(dp), parameter, public :: RENEWABLE_MAX_MW = 60.0_dp
    real(dp), parameter, public :: STORAGE_MIN_MW = -20.0_dp
    real(dp), parameter, public :: STORAGE_MAX_MW = 20.0_dp

    ! --- Battery energy storage -----------------------------------------
    real(dp), parameter, public :: BATTERY_CAPACITY_MWH = 30.0_dp
    real(dp), parameter, public :: BATTERY_INITIAL_SOC_PCT = 50.0_dp
    real(dp), parameter, public :: BATTERY_EFFICIENCY = 0.92_dp

    ! --- Market / economics ----------------------------------------------
    real(dp), parameter, public :: POWER_PRICE_USD_MWH = 95.0_dp
    real(dp), parameter, public :: FUEL_PRICE_USD_GJ = 7.5_dp
    real(dp), parameter, public :: STORAGE_CYCLE_COST_USD_MWH = 8.0_dp
    real(dp), parameter, public :: IMBALANCE_PENALTY_USD_MWH = 250.0_dp
    real(dp), parameter, public :: BESS_DEGRADATION_USD_MWH = 6.0_dp
    real(dp), parameter, public :: FCR_RESERVE_PRICE_USD_MW_H = 18.0_dp
    real(dp), parameter, public :: BESS_ARBITRAGE_SPREAD_USD_MWH = 38.0_dp
    real(dp), parameter, public :: RENEWABLE_RESERVE_PRICE_USD_MW_H = 12.0_dp
    real(dp), parameter, public :: BATTERY_CAPEX_USD_MWH = 180000.0_dp
    real(dp), parameter, public :: ROI_EQUIVALENT_HOURS_PER_YEAR = 2200.0_dp
    real(dp), parameter, public :: CO2_KG_PER_KG_FUEL = 2.75_dp

    ! --- Grid frequency physics, ENTSO-E 50 Hz ---------------------------
    real(dp), parameter, public :: FREQ_NOMINAL_HZ   = 50.0_dp
    real(dp), parameter, public :: INERTIA_MWs       = 25.0_dp   ! swing-equation M_eff
    real(dp), parameter, public :: GOVERNOR_DROOP_R  = 0.05_dp   ! 5 % droop
    real(dp), parameter, public :: BESS_PRIMARY_GAIN = 5.0_dp    ! MW/Hz primary response
    real(dp), parameter, public :: BESS_PRIMARY_DB   = 0.02_dp   ! Hz dead-band
    real(dp), parameter, public :: UFLS_THRESH_1     = 49.0_dp   ! ENTSO-E stage 1
    real(dp), parameter, public :: UFLS_THRESH_2     = 48.7_dp   ! stage 2
    real(dp), parameter, public :: UFLS_THRESH_3     = 48.4_dp   ! stage 3
    real(dp), parameter, public :: UFLS_RESET        = 49.5_dp   ! latch reset
    real(dp), parameter, public :: UFLS_SHED_PCT     = 0.10_dp   ! 10 % per stage
    real(dp), parameter, public :: LFSM_O_THRESH_HZ  = 50.2_dp   ! ENTSO-E RfG
    real(dp), parameter, public :: LFSM_O_DROOP      = 0.05_dp

    ! --- Dispatch actuator limits ----------------------------------------
    real(dp), parameter, public :: GAS_MIN_PCT = 20.0_dp
    real(dp), parameter, public :: GAS_MAX_PCT = 100.0_dp
    ! AGC slew limit: fast for a demo, but bounded so sustained ramps keep the
    ! compressor clear of the surge-margin alarm (see off_design transient PR)
    real(dp), parameter, public :: GAS_RAMP_PCT_PER_S = 8.0_dp
    real(dp), parameter, public :: BESS_RAMP_MW_PER_S = 4.0_dp
    real(dp), parameter, public :: CURTAIL_RAMP_MW_PER_S = 10.0_dp  ! inverter-fast

    real(dp), parameter, public :: PI_DP = 3.14159265358979323846_dp
    integer,  parameter, public :: HISTORY_N = 240
    integer,  parameter, public :: DA_H     = 24   ! day-ahead planning horizon (hours)
    integer,  parameter, public :: GT_OPT_N = 20   ! P2 optimizer scan points (30%→100%)
    integer,  parameter, public :: FC_N     = 48   ! 4-hour forecast horizon (48 × 5-min steps)
    integer,  parameter, public :: PARETO_N = 20   ! Pareto front sample points
    integer,  parameter, public :: MPC_HORIZON_N = 5 ! MPC preview points (5 × 60 s)
    integer,  parameter, public :: FIDELITY_N = 7 ! C3 reference map points (30%→100%)
    integer,  parameter :: FLEET_N = 3
    integer,  parameter :: FLEET_GT1 = 1
    integer,  parameter :: FLEET_GT2 = 2
    integer,  parameter :: FLEET_CC1 = 3
    character(len=4), parameter :: FLEET_UNIT_NAME(FLEET_N) = &
        [character(len=4) :: "GT1 ", "GT2 ", "CC1 "]

    !> Complete live state of the plant + grid sandbox. One instance is the
    !> whole simulation; tests may hold several independent instances.
    type :: GridState
        real(dp) :: demand_MW = 35.0_dp
        real(dp) :: renewable_MW = 12.0_dp
        real(dp) :: storage_request_MW = 0.0_dp
        real(dp) :: storage_MW = 0.0_dp
        real(dp) :: battery_energy_MWh = BATTERY_CAPACITY_MWH * BATTERY_INITIAL_SOC_PCT / 100.0_dp
        real(dp) :: battery_soc_pct = BATTERY_INITIAL_SOC_PCT
        real(dp) :: gas_dispatch_pct = 82.0_dp
        real(dp) :: ambient_C = 15.0_dp
        real(dp) :: TIT_K = 1400.0_dp
        real(dp) :: gas_power_MW = 0.0_dp
        real(dp) :: gas_capacity_MW = 0.0_dp
        real(dp) :: plant_power_MW = 0.0_dp
        real(dp) :: plant_capacity_MW = 0.0_dp
        real(dp) :: steam_power_MW = 0.0_dp
        real(dp) :: steam_power_target_MW = 0.0_dp
        real(dp) :: steam_capacity_MW = 0.0_dp
        real(dp) :: supply_MW = 0.0_dp
        real(dp) :: imbalance_MW = 0.0_dp
        real(dp) :: reserve_MW = 0.0_dp
        real(dp) :: frequency_Hz = 50.0_dp
        real(dp) :: gt_heat_rate_kJ_kWh = 0.0_dp
        real(dp) :: gt_thermal_efficiency = 0.0_dp
        real(dp) :: heat_rate_kJ_kWh = 0.0_dp
        real(dp) :: plant_efficiency = 0.0_dp
        real(dp) :: exhaust_K = 0.0_dp
        real(dp) :: fuel_flow_kg_s = 0.0_dp
        real(dp) :: heat_input_MW = 0.0_dp
        real(dp) :: revenue_usd_h = 0.0_dp
        real(dp) :: fuel_cost_usd_h = 0.0_dp
        real(dp) :: storage_cost_usd_h = 0.0_dp
        real(dp) :: imbalance_penalty_usd_h = 0.0_dp
        real(dp) :: co2_cost_usd_h = 0.0_dp
        real(dp) :: margin_usd_h = 0.0_dp
        real(dp) :: power_price_usd_mwh = POWER_PRICE_USD_MWH
        real(dp) :: fcr_reserve_price_usd_mw_h = FCR_RESERVE_PRICE_USD_MW_H
        real(dp) :: bess_arbitrage_spread_usd_mwh = BESS_ARBITRAGE_SPREAD_USD_MWH
        real(dp) :: renewable_reserve_price_usd_mw_h = RENEWABLE_RESERVE_PRICE_USD_MW_H
        real(dp) :: carbon_price_usd_t = 0.0_dp
        real(dp) :: battery_value_usd_h = 0.0_dp
        real(dp) :: battery_payback_years = 0.0_dp
        real(dp) :: bess_imbalance_value_usd_h = 0.0_dp
        real(dp) :: bess_fcr_value_usd_h = 0.0_dp
        real(dp) :: bess_arbitrage_value_usd_h = 0.0_dp
        real(dp) :: bess_degradation_cost_usd_h = 0.0_dp
        real(dp) :: renewable_reserve_value_usd_h = 0.0_dp
        real(dp) :: renewable_curtail_cost_usd_h = 0.0_dp
        real(dp) :: value_stack_usd_h = 0.0_dp
        real(dp) :: elapsed_s = 0.0_dp
        real(dp) :: CO2_rate_kg_s = 0.0_dp
        real(dp) :: CO2_intensity_g_kWh = 0.0_dp
        real(dp) :: CO2_cumulative_t = 0.0_dp
        ! Dynamic frequency model fields
        real(dp) :: ROCOF_Hz_s = 0.0_dp
        real(dp) :: nominal_frequency_Hz = FREQ_NOMINAL_HZ
        real(dp) :: governor_delta_MW = 0.0_dp
        real(dp) :: BESS_primary_MW = 0.0_dp
        real(dp) :: UFLS_shed_fraction = 0.0_dp
        real(dp) :: ufls_thresh_1_Hz = UFLS_THRESH_1
        real(dp) :: ufls_thresh_2_Hz = UFLS_THRESH_2
        real(dp) :: ufls_thresh_3_Hz = UFLS_THRESH_3
        real(dp) :: ufls_reset_Hz = UFLS_RESET
        real(dp) :: lfsm_o_thresh_Hz = LFSM_O_THRESH_HZ
        integer  :: UFLS_stage = 0
        ! Renewable dispatch: resource availability is the ceiling; the visible
        ! HMI row shows actual injection, which AGC may curtail below the ceiling.
        real(dp) :: renewable_curtail_MW = 0.0_dp
        real(dp) :: renewable_lfsmo_MW = 0.0_dp
        logical  :: roi_dispatch = .true.
        logical  :: fcr_hold = .true.
        ! Off-design map context (Phase 2): IGV + TIT load control
        real(dp) :: surge_margin_pct = 20.0_dp
        real(dp) :: igv_pct = 100.0_dp
        real(dp) :: flow_frac = 1.0_dp
        real(dp) :: TIT_actual_K = 1400.0_dp
        real(dp) :: PR_op = 15.0_dp
        real(dp) :: gas_ramp_pct_per_s = 0.0_dp
        real(dp) :: prev_gas_dispatch_pct = 82.0_dp
        ! Phase 3 combined-cycle bottoming system
        logical  :: combined_cycle = .false.
        real(dp) :: hrsg_recovered_heat_MW = 0.0_dp
        real(dp) :: hrsg_stack_T_K = 0.0_dp
        real(dp) :: hrsg_pinch_K = 0.0_dp
        real(dp) :: hrsg_approach_K = 0.0_dp
        real(dp) :: hrsg_steam_flow_kg_s = 0.0_dp
        real(dp) :: hrsg_steam_T_K = 0.0_dp
        real(dp) :: hrsg_steam_pressure_bar = 0.0_dp
        real(dp) :: hrsg_effectiveness = 0.0_dp
        real(dp) :: condenser_pressure_kPa = 0.0_dp
        logical  :: alarm_hrsg_pinch = .false.
        ! Phase 4 multi-unit dispatch state
        logical  :: fleet_mode = .false.
        real(dp) :: fuel_price_usd_gj = FUEL_PRICE_USD_GJ
        real(dp) :: fleet_load_target_MW = 0.0_dp
        real(dp) :: fleet_total_MW = 0.0_dp
        real(dp) :: fleet_capacity_MW = 0.0_dp
        real(dp) :: fleet_online_capacity_MW = 0.0_dp
        real(dp) :: fleet_reserve_MW = 0.0_dp
        real(dp) :: fleet_reserve_requirement_MW = 5.0_dp
        real(dp) :: fleet_unserved_dispatch_MW = 0.0_dp
        real(dp) :: fleet_inertia_MWs = INERTIA_MWs
        real(dp) :: fleet_lmp_usd_MWh = 0.0_dp
        real(dp) :: fleet_agc_error_MW = 0.0_dp
        integer  :: fleet_marginal_unit = 0
        logical  :: fleet_reserve_binding = .false.
        logical  :: fleet_unit_online(FLEET_N) = [.true., .true., .true.]
        real(dp) :: fleet_unit_capacity_MW(FLEET_N) = [30.0_dp, 15.0_dp, 45.0_dp]
        real(dp) :: fleet_unit_setpoint_MW(FLEET_N) = 0.0_dp
        real(dp) :: fleet_unit_actual_MW(FLEET_N) = 0.0_dp
        real(dp) :: fleet_unit_ramp_MW_s(FLEET_N) = [3.5_dp, 8.0_dp, 0.25_dp]
        real(dp) :: fleet_unit_heat_rate_kJ_kWh(FLEET_N) = [11750.0_dp, 9800.0_dp, 6880.0_dp]
        real(dp) :: fleet_unit_var_om_usd_MWh(FLEET_N) = [5.0_dp, 7.0_dp, 3.0_dp]
        real(dp) :: fleet_unit_cost_usd_MWh(FLEET_N) = 0.0_dp
        real(dp) :: fleet_unit_participation(FLEET_N) = 0.0_dp
        real(dp) :: fleet_unit_inertia_MWs(FLEET_N) = [24.0_dp, 8.0_dp, 70.0_dp]
        ! P1 Fleet Unit Commitment + Economic Dispatch display state
        integer  :: fleet_uc_commit(FLEET_N) = 0          ! 1 = committed in what-if UC
        real(dp) :: fleet_uc_p(FLEET_N)      = 0.0_dp    ! dispatch MW per unit
        real(dp) :: fleet_uc_total_cost_h    = 0.0_dp    ! total variable cost $/h
        logical  :: fleet_uc_solved          = .false.
        ! Phase 5 market/weather/location state
        integer  :: market_profile_id = 1
        character(len=24) :: market_profile_name = "Default SE3"
        character(len=16) :: market_power_zone = "SE3"
        character(len=16) :: market_gas_hub = "TTF"
        integer  :: market_source_code = 0
        logical  :: market_weather_enabled = .false.
        logical  :: market_load_replay_enabled = .false.
        real(dp) :: market_latitude_deg = 59.33_dp
        real(dp) :: market_longitude_deg = 18.07_dp
        real(dp) :: market_replay_day_s = 300.0_dp
        real(dp) :: market_hour = 12.0_dp
        real(dp) :: market_last_update_s = 0.0_dp
        real(dp) :: market_data_age_s = 0.0_dp
        real(dp) :: renewable_scale_pct = 100.0_dp
        real(dp) :: market_wind_capacity_MW = 28.0_dp
        real(dp) :: market_pv_capacity_MW = 18.0_dp
        real(dp) :: market_wind_speed_m_s = 0.0_dp
        real(dp) :: market_solar_W_m2 = 0.0_dp
        real(dp) :: market_wind_power_MW = 0.0_dp
        real(dp) :: market_pv_power_MW = 0.0_dp
        real(dp) :: market_base_demand_MW = 35.0_dp
        real(dp) :: market_peak_demand_MW = 72.0_dp
        logical  :: alarm_surge = .false.
        ! Alarm state flags (drives annunciator tiles)
        logical  :: alarm_underfreq    = .false.
        logical  :: alarm_overfreq     = .false.
        logical  :: alarm_low_reserve  = .false.
        logical  :: alarm_low_soc      = .false.
        logical  :: alarm_ufls_active  = .false.
        logical  :: alarm_turbine_max  = .false.
        integer :: history_count = 0
        integer :: history_head = 0
        real(dp) :: hist_frequency_Hz(HISTORY_N) = 50.0_dp
        real(dp) :: hist_demand_MW(HISTORY_N) = 35.0_dp
        real(dp) :: hist_gas_dispatch_pct(HISTORY_N) = 82.0_dp
        logical :: auto_balance = .true.
        ! Day-ahead MINLP optimizer results (written by minlp_dayahead every ~5 s)
        logical  :: da_solved       = .false.
        real(dp) :: da_demand(DA_H) = 0.0_dp   ! forecast demand MW, hours 1..DA_H
        real(dp) :: da_price(DA_H)  = 0.0_dp   ! forecast price $/MWh
        integer  :: da_commit(DA_H) = 0         ! optimal GT commitment 0/1
        real(dp) :: da_p_gt(DA_H)   = 0.0_dp   ! optimal GT dispatch MW
        real(dp) :: da_p_bess(DA_H) = 0.0_dp   ! optimal BESS power MW (+discharge/-charge)
        real(dp) :: da_soc(DA_H+1)  = 0.0_dp   ! SoC trajectory MWh (hour 0..DA_H)
        real(dp) :: da_cost_usd     = 0.0_dp    ! total 24 h GT operating cost $
        real(dp) :: da_revenue_usd  = 0.0_dp    ! total 24 h revenue $
        real(dp) :: da_gap_pct      = 0.0_dp    ! LP relaxation duality gap %
        real(dp) :: da_price_lo(DA_H)  = 0.0_dp   ! P5 price scenario (fan lower bound)
        real(dp) :: da_price_hi(DA_H)  = 0.0_dp   ! P95 price scenario (fan upper bound)
        integer  :: da_current_hour    = 1        ! current hour (1-24) within day-ahead plan
        real(dp) :: da_redispatch_saving_usd = 0.0_dp  ! P2 re-dispatch estimated saving [$]
        real(dp) :: wash_hr_gap_pct       = 0.0_dp   ! HR gap vs clean design-point [%]
        real(dp) :: wash_daily_saving_usd = 0.0_dp   ! fuel saving per day from washing [$]
        real(dp) :: wash_breakeven_days   = 0.0_dp   ! wash cost breakeven interval [days]
        ! DNN surrogate status (mirrored from dnn_surrogate module by engine_init)
        logical  :: dnn_active  = .false.
        real(dp) :: dnn_hr_mae  = 0.0_dp             ! HR surrogate val MAE [kJ/kWh]
        ! Revamp 5.0 C1 model-validation harness
        logical  :: model_val_ready = .false.
        logical  :: model_val_dnn_available = .false.
        integer  :: model_val_n = 0
        integer  :: model_val_worst_idx = 0
        real(dp) :: model_val_cycle_power_mae_MW = 0.0_dp
        real(dp) :: model_val_cycle_power_bias_MW = 0.0_dp
        real(dp) :: model_val_cycle_hr_mae_kJ_kWh = 0.0_dp
        real(dp) :: model_val_cycle_hr_bias_kJ_kWh = 0.0_dp
        real(dp) :: model_val_dnn_hr_mae_kJ_kWh = 0.0_dp
        real(dp) :: model_val_dnn_hr_bias_kJ_kWh = 0.0_dp
        real(dp) :: model_val_dnn_hr_max_abs_kJ_kWh = 0.0_dp
        ! Revamp 5.0 C3 published-map-style reference overlays
        logical  :: physics_fidelity_ready = .false.
        integer  :: physics_fidelity_n = 0
        real(dp) :: physics_load_pct(FIDELITY_N) = 0.0_dp
        real(dp) :: physics_ref_gt_hr_kJ_kWh(FIDELITY_N) = 0.0_dp
        real(dp) :: physics_ref_hrsg_pinch_K(FIDELITY_N) = 0.0_dp
        real(dp) :: physics_gt_hr_ref_kJ_kWh = 0.0_dp
        real(dp) :: physics_gt_hr_gap_pct = 0.0_dp
        real(dp) :: physics_hrsg_pinch_ref_K = 0.0_dp
        real(dp) :: physics_hrsg_pinch_gap_K = 0.0_dp
        ! P2 real-time GT economic dispatch optimizer
        logical  :: gt_opt_solved           = .false.
        integer  :: gt_opt_best_idx         = 1
        real(dp) :: gt_opt_pwr(GT_OPT_N)   = 0.0_dp  ! GT power at each scan point [MW]
        real(dp) :: gt_opt_hr(GT_OPT_N)    = 0.0_dp  ! heat rate [kJ/kWh]
        real(dp) :: gt_opt_margin(GT_OPT_N)= 0.0_dp  ! net margin [$/h]
        real(dp) :: gt_opt_best_margin      = 0.0_dp  ! best margin found [$/h]
        real(dp) :: gt_opt_curr_margin      = 0.0_dp  ! margin at current dispatch [$/h]
        real(dp) :: gt_opt_saving_h         = 0.0_dp  ! saving vs current [$/h]

        ! H2 co-firing state (operator-controlled, 0-30 vol%)
        real(dp) :: h2_fraction_pct  = 0.0_dp   ! H2 vol % in fuel blend
        real(dp) :: h2_lhv_mj_kg    = 50.0_dp  ! blended LHV [MJ/kg]
        real(dp) :: h2_co2_factor    = 2.75_dp  ! kg CO2 per kg blend fuel
        real(dp) :: h2_nox_factor    = 1.0_dp   ! NOx multiplier vs pure NG
        logical  :: h2_wobbe_ok      = .true.   ! Wobbe index within ±5% of NG
        real(dp) :: h2_co2_avoided_t = 0.0_dp   ! cumulative CO2 avoided vs 0% H2 [tonnes]
        real(dp) :: co2_daily_t      = 0.0_dp   ! CO2 emitted today [tonnes] (resets each sim day)
        real(dp) :: co2_daily_ref_t  = 0.0_dp   ! CO2 baseline today (if h2_fraction_pct=0) [tonnes]
        ! Revamp 7.0-P3 combustion chemistry and hot-section component physics
        real(dp) :: h2_mass_fraction = 0.0_dp
        real(dp) :: h2_wobbe_mj_m3 = 51.6_dp
        real(dp) :: h2_wobbe_deviation_pct = 0.0_dp
        real(dp) :: flame_temp_ad_K = 2145.0_dp
        real(dp) :: flame_temp_shift_K = 0.0_dp
        real(dp) :: nox_ppm_15o2 = 30.0_dp
        real(dp) :: nox_mg_nm3_15o2 = 61.5_dp
        real(dp) :: co_ppm_15o2 = 5.0_dp
        real(dp) :: co_mg_nm3_15o2 = 6.25_dp
        real(dp) :: stack_o2_dry_pct = 15.0_dp
        real(dp) :: stack_co2_vol_pct = 3.5_dp
        real(dp) :: combustion_lambda = 3.2_dp
        real(dp) :: flashback_margin_pct = 105.0_dp
        real(dp) :: turbine_cooling_air_pct = 7.0_dp
        real(dp) :: turbine_cooling_air_kg_s = 7.0_dp
        real(dp) :: turbine_metal_margin_K = 170.0_dp
        real(dp) :: tip_clearance_mm = 1.2_dp
        real(dp) :: tip_loss_pct = 0.9_dp
        real(dp) :: compressor_poly_loss_pct = 14.0_dp
        real(dp) :: turbine_poly_loss_pct = 12.0_dp
        real(dp) :: combustor_pattern_factor_pct = 8.0_dp

        ! ── Anomaly detector (EWMA Z-score on 4 GT sensors) ─────────────────────
        integer  :: anom_tick        = 0
        real(dp) :: anom_ewma_hr     = 9200.0_dp
        real(dp) :: anom_ewma_tex    = 850.0_dp
        real(dp) :: anom_ewma_sm     = 25.0_dp
        real(dp) :: anom_ewma_eta    = 0.37_dp
        real(dp) :: anom_var_hr      = 400.0_dp
        real(dp) :: anom_var_tex     = 100.0_dp
        real(dp) :: anom_var_sm      = 9.0_dp
        real(dp) :: anom_var_eta     = 1.0e-4_dp
        real(dp) :: anom_score_hr    = 0.0_dp
        real(dp) :: anom_score_tex   = 0.0_dp
        real(dp) :: anom_score_sm    = 0.0_dp
        real(dp) :: anom_score_eta   = 0.0_dp
        real(dp) :: anom_composite   = 0.0_dp

        ! ── RL dispatch (tabular Q-learning; 80 states × 3 actions) ─────────────
        logical  :: rl_mode          = .false.
        integer  :: rl_state_prev    = 1
        integer  :: rl_action_prev   = 2
        real(dp) :: rl_storage_setpt = 0.0_dp
        real(dp) :: rl_last_reward   = 0.0_dp
        real(dp) :: rl_cumreward     = 0.0_dp
        real(dp) :: rl_q_table(80,3) = 0.0_dp

        ! ── Online DNN adaptation (output-layer bias correction) ─────────────────
        logical  :: dnn_adapting     = .false.
        real(dp) :: dnn_online_bias  = 0.0_dp
        real(dp) :: dnn_online_rmse  = 0.0_dp
        integer  :: dnn_online_n     = 0

        ! ── ML fault classifier (decision-tree; top-2 fault classes) ─────────────
        integer  :: fc_class1        = 0
        integer  :: fc_class2        = 0
        real(dp) :: fc_conf1         = 0.0_dp
        real(dp) :: fc_conf2         = 0.0_dp

        ! ── 4-hour demand + price forecast (48 × 5-min steps) ───────────────────
        real(dp) :: fcast_demand(FC_N) = 0.0_dp
        real(dp) :: fcast_price(FC_N)  = 0.0_dp
        real(dp) :: fcast_dem_lo(FC_N) = 0.0_dp
        real(dp) :: fcast_dem_hi(FC_N) = 0.0_dp

        ! ── Operator advisory NLP ────────────────────────────────────────────────
        ! advisory_hash starts at -1 (impossible) so the first build_advisory call
        ! always populates advisory_text even when the steady-state hash is 0.
        character(len=2048) :: advisory_text = ""
        integer              :: advisory_hash = -1

        ! ── P2X flexible electrolyser ─────────────────────────────────────────
        logical  :: p2x_active        = .false.      ! operator enable/disable
        real(dp) :: p2x_capacity_MW   = 30.0_dp     ! rated electrolyser capacity [MW]
        real(dp) :: p2x_load_MW       = 0.0_dp      ! actual absorbed load [MW]
        real(dp) :: p2x_h2_kg_s       = 0.0_dp      ! H2 production rate [kg/s]
        real(dp) :: p2x_efficiency    = 0.70_dp     ! electrical-to-H2 efficiency [–]

        ! ── MEA post-combustion CCS ──────────────────────────────────────────────
        logical  :: ccs_active            = .false.  ! enable CCS sub-system
        real(dp) :: ccs_capture_eff       = 0.90_dp  ! CO2 capture efficiency [0-1]
        real(dp) :: ccs_parasitic_MW      = 0.0_dp   ! regeneration parasitic load [MW]
        real(dp) :: ccs_co2_captured_t_h  = 0.0_dp   ! CO2 captured [t/h]

        ! ── Grid-Forming (GFM) BESS — virtual inertia + frequency droop ──────
        logical  :: gfm_mode          = .false.      ! operator enable/disable
        real(dp) :: gfm_virtual_H     = 4.0_dp      ! virtual inertia constant [s]
        real(dp) :: gfm_droop_pct     = 5.0_dp      ! frequency droop [%]
        real(dp) :: gfm_synth_MW      = 0.0_dp      ! current GFM power response [MW]
        real(dp) :: gfm_H_equiv       = 0.0_dp      ! equivalent H contribution [MWs/MVA]
        real(dp) :: freq_rocof_Hz_s   = 0.0_dp      ! ROCOF filled by nadir predictor [Hz/s]

        ! ── MPC-AGC (5-step, 1-min/step receding-horizon frequency regulator) ──
        logical  :: mpc_active        = .false.      ! operator enable/disable
        real(dp) :: mpc_setpt_MW      = 0.0_dp      ! MPC recommended GT setpoint [MW]
        real(dp) :: mpc_cost_last     = 0.0_dp      ! last optimisation horizon cost [–]
        logical  :: mpc_horizon_ready = .false.     ! true once prediction arrays are valid
        integer  :: mpc_horizon_n     = 0           ! number of valid preview points
        real(dp) :: mpc_cost_hold     = 0.0_dp      ! cost index if GT setpoint is held
        real(dp) :: mpc_cost_saving   = 0.0_dp      ! hold cost minus chosen MPC cost
        real(dp) :: mpc_pred_time_s(MPC_HORIZON_N) = 0.0_dp
        real(dp) :: mpc_pred_freq_Hz(MPC_HORIZON_N) = FREQ_NOMINAL_HZ
        real(dp) :: mpc_pred_pgen_MW(MPC_HORIZON_N) = 0.0_dp
        real(dp) :: mpc_pred_setpt_MW(MPC_HORIZON_N) = 0.0_dp
        real(dp) :: mpc_pred_imbalance_MW(MPC_HORIZON_N) = 0.0_dp

        ! ── Tie-line / two-area ACE model (tie_line module) ──────────────────
        logical  :: tie_active          = .false.    ! enable tie-line sub-system
        real(dp) :: tie_flow_MW         = 0.0_dp    ! actual tie flow [MW]; +ve = export from zone 1
        real(dp) :: tie_scheduled_MW    = 0.0_dp    ! scheduled interchange [MW]
        real(dp) :: tie_capacity_MW     = 200.0_dp  ! thermal rating of the corridor [MW]
        real(dp) :: ace_MW              = 0.0_dp    ! area control error [MW] (output)
        real(dp) :: zone2_freq_Hz       = 50.0_dp   ! zone-2 frequency [Hz]
        real(dp) :: zone2_demand_MW     = 150.0_dp  ! zone-2 load [MW]
        real(dp) :: zone2_gen_MW        = 150.0_dp  ! zone-2 generation [MW]

        ! ── Hot-parts LCF cycle counter ──────────────────────────────────────────
        integer  :: lcf_starts         = 0           ! cold starts accumulated
        real(dp) :: lcf_hot_hours      = 0.0_dp     ! hot-section operating hours [h]
        real(dp) :: lcf_comp_life_pct  = 0.0_dp     ! compressor life consumed [%]
        real(dp) :: lcf_hst_life_pct   = 0.0_dp     ! hot-section turbine life consumed [%]
        real(dp) :: lcf_hrsg_life_pct  = 0.0_dp     ! HRSG life consumed [%]
        logical  :: lcf_was_running    = .false.     ! for start/stop detection

        ! ── Stochastic Ornstein-Uhlenbeck noise ──────────────────────────────────
        logical  :: ou_active          = .false.
        real(dp) :: ou_demand_noise    = 0.0_dp     ! current demand noise [MW]
        real(dp) :: ou_wind_noise      = 0.0_dp     ! current wind noise [MW]
        real(dp) :: ou_sigma_demand    = 2.0_dp     ! demand noise std [MW]
        real(dp) :: ou_tau_demand      = 120.0_dp   ! mean-reversion time [s]
        real(dp) :: ou_sigma_wind      = 3.0_dp
        real(dp) :: ou_tau_wind        = 300.0_dp
        integer  :: ou_iseed           = 123456789  ! LCG state

        ! ── Frequency nadir predictor ─────────────────────────────────────────────
        real(dp) :: freq_nadir_Hz      = 50.0_dp    ! predicted N-1 nadir [Hz]
        real(dp) :: freq_prev_Hz       = 50.0_dp    ! previous-tick frequency (ROCOF)
        real(dp) :: nadir_trip_MW      = 50.0_dp    ! assumed N-1 trip size [MW]

        ! ── DNN MC-dropout uncertainty ────────────────────────────────────────────
        real(dp) :: dnn_hr_sigma       = 0.0_dp     ! HR std from 20 MC passes [kJ/kWh]

        ! ── Multi-objective Pareto front ──────────────────────────────────────────
        real(dp) :: pareto_cost(PARETO_N)   = 0.0_dp   ! $/h optimal cost
        real(dp) :: pareto_co2(PARETO_N)    = 0.0_dp   ! t/h CO2 emissions
        real(dp) :: pareto_avail(PARETO_N)  = 0.0_dp   ! availability [%]
        integer  :: pareto_n_pts            = 0
        logical  :: pareto_dirty            = .true.
    end type GridState

contains

    pure function clamp_real(value, lo, hi) result(clamped)
        real(dp), intent(in) :: value, lo, hi
        real(dp) :: clamped
        clamped = min(max(value, lo), hi)
    end function clamp_real

    !> Actual grid injection = available (weather ceiling) minus AGC curtailment.
    pure function effective_renewable_MW(st) result(mw)
        type(GridState), intent(in) :: st
        real(dp) :: mw
        mw = max(0.0_dp, st%renewable_MW - st%renewable_curtail_MW)
    end function effective_renewable_MW

    !> Upward reserve currently held as curtailed renewable output.
    pure function renewable_headroom_MW(st) result(mw)
        type(GridState), intent(in) :: st
        real(dp) :: mw
        mw = clamp_real(st%renewable_curtail_MW, 0.0_dp, st%renewable_MW)
    end function renewable_headroom_MW

    pure function bottoming_power_MW(st) result(mw)
        type(GridState), intent(in) :: st
        real(dp) :: mw
        if (st%combined_cycle) then
            mw = st%steam_power_MW
        else
            mw = 0.0_dp
        end if
    end function bottoming_power_MW

    pure function thermal_generation_MW(st) result(mw)
        type(GridState), intent(in) :: st
        real(dp) :: mw
        if (st%fleet_mode) then
            mw = st%fleet_total_MW
        else
            mw = st%gas_power_MW + bottoming_power_MW(st)
        end if
    end function thermal_generation_MW

    !> BESS power actually deliverable for a request, honouring energy limits.
    !> Sign convention: positive = discharge (adds to supply).
    pure function limited_storage_power(st, request_MW) result(actual_MW)
        type(GridState), intent(in) :: st
        real(dp), intent(in) :: request_MW
        real(dp) :: actual_MW

        actual_MW = clamp_real(request_MW, STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (actual_MW > 0.0_dp .and. st%battery_energy_MWh <= 1.0e-6_dp) then
            actual_MW = 0.0_dp
        else if (actual_MW < 0.0_dp .and. st%battery_energy_MWh >= BATTERY_CAPACITY_MWH - 1.0e-6_dp) then
            actual_MW = 0.0_dp
        end if
    end function limited_storage_power

    !> Push the current sample onto the ring buffer of trend history.
    subroutine append_history(st)
        type(GridState), intent(inout) :: st
        integer :: idx

        idx = mod(st%history_head, HISTORY_N) + 1
        st%hist_frequency_Hz(idx) = st%frequency_Hz
        st%hist_demand_MW(idx) = st%demand_MW
        st%hist_gas_dispatch_pct(idx) = st%gas_dispatch_pct
        st%history_head = idx
        st%history_count = min(st%history_count + 1, HISTORY_N)
    end subroutine append_history

    !> Ring-buffer index of the i-th oldest stored sample (1 = oldest).
    pure function history_index(st, position) result(idx)
        type(GridState), intent(in) :: st
        integer, intent(in) :: position
        integer :: idx

        idx = mod(st%history_head - st%history_count + position - 1 + HISTORY_N, HISTORY_N) + 1
    end function history_index

end module engine_state
