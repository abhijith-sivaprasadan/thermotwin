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
        gap_MW = st%demand_MW - eff_renew - st%gas_power_MW &
                 - limited_storage_power(st, st%storage_request_MW)
        if (gap_MW > 0.10_dp .and. st%renewable_curtail_MW > 0.0_dp) then
            target_curtail_MW = max(0.0_dp, st%renewable_curtail_MW - gap_MW)
            call ramp_renewable_curtailment_to(st, target_curtail_MW, dt_s)
        end if

        ! Stage 2: BESS covers the residual quickly while respecting SOC limits.
        eff_renew = effective_renewable_MW(st)
        bess_target_MW = clamp_real(st%demand_MW - eff_renew - st%gas_power_MW, &
                                    STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (st%fcr_hold) then
            if (bess_target_MW < -0.5_dp) bess_target_MW = max(bess_target_MW, 0.65_dp * bess_target_MW)
            bess_target_MW = clamp_real(bess_target_MW, STORAGE_MIN_MW + 5.0_dp, STORAGE_MAX_MW - 5.0_dp)
            if (abs(bess_target_MW) < 0.5_dp .and. st%battery_soc_pct < 45.0_dp) &
                bess_target_MW = -2.0_dp
            if (abs(bess_target_MW) < 0.5_dp .and. st%battery_soc_pct > 55.0_dp) &
                bess_target_MW = 2.0_dp
        end if
        if (bess_target_MW > 0.0_dp .and. st%battery_soc_pct < 5.0_dp) &
            bess_target_MW = 0.0_dp   ! no discharge when nearly empty
        if (bess_target_MW < 0.0_dp .and. st%battery_soc_pct > 95.0_dp) &
            bess_target_MW = 0.0_dp   ! no charge when nearly full
        bess_step_MW = BESS_RAMP_MW_PER_S * dt_s
        st%storage_request_MW = st%storage_request_MW + &
            clamp_real(bess_target_MW - st%storage_request_MW, -bess_step_MW, bess_step_MW)

        ! Stage 3: if BESS cannot absorb surplus fast enough, trim renewable injection.
        gap_MW = st%demand_MW - eff_renew - st%gas_power_MW &
                 - limited_storage_power(st, st%storage_request_MW)
        if (gap_MW < -0.50_dp .and. should_curtail_renewables(st)) then
            surplus_MW = -gap_MW
            target_curtail_MW = min(st%renewable_MW, st%renewable_curtail_MW + surplus_MW)
            call ramp_renewable_curtailment_to(st, target_curtail_MW, dt_s)
        else if (abs(gap_MW) <= 0.50_dp .and. st%renewable_curtail_MW > 0.0_dp .and. &
                 st%renewable_reserve_value_usd_h < st%renewable_curtail_cost_usd_h) then
            call ramp_renewable_curtailment_to(st, 0.0_dp, dt_s)
        end if

        ! Stage 4: turbine follows the remaining steady dispatch requirement.
        eff_renew = effective_renewable_MW(st)
        needed_gas_MW = st%demand_MW - eff_renew &
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

        if (st%gas_capacity_MW <= 1.0e-6_dp) return
        st%renewable_curtail_MW = 0.0_dp
        bess_snap_MW = clamp_real(st%demand_MW - st%renewable_MW - st%gas_power_MW, &
                                  STORAGE_MIN_MW, STORAGE_MAX_MW)
        if (bess_snap_MW > 0.0_dp .and. st%battery_soc_pct < 5.0_dp)  bess_snap_MW = 0.0_dp
        if (bess_snap_MW < 0.0_dp .and. st%battery_soc_pct > 95.0_dp) bess_snap_MW = 0.0_dp
        st%storage_request_MW = bess_snap_MW
        needed_gas_MW = st%demand_MW - st%renewable_MW &
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
        st%gas_dispatch_pct = GAS_MIN_PCT
        st%storage_request_MW = min(st%storage_request_MW + 8.0_dp, STORAGE_MAX_MW)
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
        st%frequency_Hz = FREQ_NOMINAL_HZ
        st%ROCOF_Hz_s = 0.0_dp
        st%governor_delta_MW = 0.0_dp
        st%BESS_primary_MW = 0.0_dp
        st%UFLS_shed_fraction = 0.0_dp
        st%UFLS_stage = 0
        st%renewable_curtail_MW = 0.0_dp
        st%renewable_lfsmo_MW = 0.0_dp
        st%roi_dispatch = .true.
        st%fcr_hold = .true.
        st%alarm_underfreq = .false.
        st%alarm_overfreq  = .false.
        st%alarm_low_reserve = .false.
        st%alarm_low_soc = .false.
        st%alarm_ufls_active = .false.
        st%alarm_turbine_max = .false.
    end subroutine reset_controls

end module dispatch_agc
