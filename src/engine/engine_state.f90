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
    public :: effective_renewable_MW, renewable_headroom_MW
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
        real(dp) :: supply_MW = 0.0_dp
        real(dp) :: imbalance_MW = 0.0_dp
        real(dp) :: reserve_MW = 0.0_dp
        real(dp) :: frequency_Hz = 50.0_dp
        real(dp) :: heat_rate_kJ_kWh = 0.0_dp
        real(dp) :: exhaust_K = 0.0_dp
        real(dp) :: fuel_flow_kg_s = 0.0_dp
        real(dp) :: heat_input_MW = 0.0_dp
        real(dp) :: revenue_usd_h = 0.0_dp
        real(dp) :: fuel_cost_usd_h = 0.0_dp
        real(dp) :: storage_cost_usd_h = 0.0_dp
        real(dp) :: imbalance_penalty_usd_h = 0.0_dp
        real(dp) :: margin_usd_h = 0.0_dp
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
        real(dp) :: governor_delta_MW = 0.0_dp
        real(dp) :: BESS_primary_MW = 0.0_dp
        real(dp) :: UFLS_shed_fraction = 0.0_dp
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
