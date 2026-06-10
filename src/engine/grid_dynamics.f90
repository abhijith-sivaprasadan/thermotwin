!> @file grid_dynamics.f90
!> @brief Fast grid frequency dynamics: swing equation, governor droop,
!>        BESS primary response, UFLS relays, and renewable LFSM-O.
!>
!> All primary (seconds-scale) frequency control lives here. Secondary
!> dispatch (AGC) lives in dispatch_agc; this module only consumes the
!> setpoints it produces.
module grid_dynamics
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: tick_frequency_dynamics

contains

    !> Integrate one time step of the grid frequency model and refresh
    !> the primary-response contributions and alarm flags.
    subroutine tick_frequency_dynamics(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        real(dp) :: delta_f, P_gen_eff, P_load_eff, df_dt
        real(dp) :: gov_max_up, gov_max_dn

        delta_f = st%frequency_Hz - FREQ_NOMINAL_HZ

        ! Governor primary droop: dP_gov = -(df/f0)/R * P_rated (clamped to headroom)
        st%governor_delta_MW = -(delta_f / FREQ_NOMINAL_HZ) / GOVERNOR_DROOP_R * st%gas_capacity_MW
        gov_max_up = st%gas_capacity_MW - st%gas_power_MW
        gov_max_dn = st%gas_power_MW - st%gas_capacity_MW * (GAS_MIN_PCT / 100.0_dp)
        st%governor_delta_MW = clamp_real(st%governor_delta_MW, -gov_max_dn, gov_max_up)

        ! BESS primary frequency response (dead-band 0.02 Hz)
        if (abs(delta_f) > BESS_PRIMARY_DB) then
            st%BESS_primary_MW = clamp_real(-delta_f * BESS_PRIMARY_GAIN, -5.0_dp, 5.0_dp)
            if (st%BESS_primary_MW > 0.0_dp .and. st%battery_energy_MWh <= 1.0e-6_dp) &
                st%BESS_primary_MW = 0.0_dp
            if (st%BESS_primary_MW < 0.0_dp .and. &
                    st%battery_energy_MWh >= BATTERY_CAPACITY_MWH - 1.0e-6_dp) &
                st%BESS_primary_MW = 0.0_dp
        else
            st%BESS_primary_MW = 0.0_dp
        end if

        ! UFLS (ENTSO-E): latching stages, reset above 49.5 Hz
        if (st%frequency_Hz >= UFLS_RESET) then
            st%UFLS_stage = 0
            st%UFLS_shed_fraction = 0.0_dp
        else if (st%frequency_Hz < UFLS_THRESH_3 .and. st%UFLS_stage < 3) then
            st%UFLS_stage = 3
            st%UFLS_shed_fraction = 3.0_dp * UFLS_SHED_PCT
        else if (st%frequency_Hz < UFLS_THRESH_2 .and. st%UFLS_stage < 2) then
            st%UFLS_stage = 2
            st%UFLS_shed_fraction = 2.0_dp * UFLS_SHED_PCT
        else if (st%frequency_Hz < UFLS_THRESH_1 .and. st%UFLS_stage < 1) then
            st%UFLS_stage = 1
            st%UFLS_shed_fraction = UFLS_SHED_PCT
        end if

        ! LFSM-O (ENTSO-E RfG): above 50.2 Hz renewables shed output with 5% droop
        if (st%frequency_Hz > LFSM_O_THRESH_HZ) then
            st%renewable_lfsmo_MW = min(effective_renewable_MW(st), &
                effective_renewable_MW(st) * (st%frequency_Hz - LFSM_O_THRESH_HZ) / &
                FREQ_NOMINAL_HZ / LFSM_O_DROOP)
        else
            st%renewable_lfsmo_MW = 0.0_dp
        end if

        ! Swing equation: df/dt = (P_gen - P_load) / M_eff
        P_gen_eff  = st%gas_power_MW + st%governor_delta_MW + &
                     effective_renewable_MW(st) - st%renewable_lfsmo_MW + &
                     st%storage_MW + st%BESS_primary_MW
        P_load_eff = st%demand_MW * (1.0_dp - st%UFLS_shed_fraction)
        df_dt = (P_gen_eff - P_load_eff) / INERTIA_MWs
        st%ROCOF_Hz_s = df_dt
        st%frequency_Hz = clamp_real(st%frequency_Hz + df_dt * dt_s, 47.0_dp, 53.0_dp)

        ! Update alarm flags
        st%alarm_underfreq   = st%frequency_Hz < (FREQ_NOMINAL_HZ - 0.5_dp)
        st%alarm_overfreq    = st%frequency_Hz > (FREQ_NOMINAL_HZ + 0.5_dp)
        st%alarm_low_reserve = st%reserve_MW < 2.0_dp
        st%alarm_low_soc     = st%battery_soc_pct < 15.0_dp
        st%alarm_ufls_active = st%UFLS_stage > 0
        st%alarm_turbine_max = st%gas_dispatch_pct >= (GAS_MAX_PCT - 0.5_dp)
    end subroutine tick_frequency_dynamics

end module grid_dynamics
