!> @file grid_dynamics.f90
!> @brief Fast grid frequency dynamics from physically booked net injection,
!>        UFLS, and renewable LFSM-O; primary controls are applied upstream.
!>
!> Primary response is resolved by grid_primary_balance (one actual BESS MW
!> and a governor-controlled GT off-design solve), never as unaccounted MW.
module grid_dynamics
    use precision_kinds, only: dp
    use engine_state
    use off_design, only: SURGE_ALARM_PCT
    implicit none
    private

    public :: tick_frequency_dynamics

contains

    !> Integrate one time step of the grid frequency model and refresh
    !> the primary-response contributions and alarm flags.
    subroutine tick_frequency_dynamics(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        real(dp) :: df_dt, m_eff_MWs
        if (dt_s<=0.0_dp) return

        ! The governor was already applied through the thermodynamic
        ! off-design load solve, and the BESS primary response was already
        ! combined into storage_MW. Never add either AGAIN as free power.
        if (st%fleet_mode) then
            m_eff_MWs = max(8.0_dp, st%fleet_inertia_MWs)
        else
            m_eff_MWs = INERTIA_MWs
        end if

        ! UFLS (ENTSO-E): latching stages, reset above 49.5 Hz
        if (st%frequency_Hz >= st%ufls_reset_Hz) then
            st%UFLS_stage = 0
            st%UFLS_shed_fraction = 0.0_dp
        else if (st%frequency_Hz < st%ufls_thresh_3_Hz .and. st%UFLS_stage < 3) then
            st%UFLS_stage = 3
            st%UFLS_shed_fraction = 3.0_dp * UFLS_SHED_PCT
        else if (st%frequency_Hz < st%ufls_thresh_2_Hz .and. st%UFLS_stage < 2) then
            st%UFLS_stage = 2
            st%UFLS_shed_fraction = 2.0_dp * UFLS_SHED_PCT
        else if (st%frequency_Hz < st%ufls_thresh_1_Hz .and. st%UFLS_stage < 1) then
            st%UFLS_stage = 1
            st%UFLS_shed_fraction = UFLS_SHED_PCT
        end if

        ! LFSM-O (ENTSO-E RfG): above 50.2 Hz renewables shed output with 5% droop
        if (st%frequency_Hz > st%lfsm_o_thresh_Hz) then
            st%renewable_lfsmo_MW = min(effective_renewable_MW(st), &
                effective_renewable_MW(st) * (st%frequency_Hz - st%lfsm_o_thresh_Hz) / &
                st%nominal_frequency_Hz / LFSM_O_DROOP)
        else
            st%renewable_lfsmo_MW = 0.0_dp
        end if

        ! One physical accounting convention for frequency AND published tags:
        ! positive BESS power supplies the grid; LFSM-O reduces RES injection;
        ! UFLS reduces actually served demand, but not gross demand request.
        st%served_demand_MW=st%demand_MW*(1.0_dp-st%UFLS_shed_fraction)
        st%ufls_shed_MW=st%demand_MW-st%served_demand_MW
        st%supply_MW=thermal_generation_MW(st)+ &
            max(0.0_dp,effective_renewable_MW(st)-st%renewable_lfsmo_MW)+ &
            st%storage_MW
        st%imbalance_MW=st%supply_MW-st%served_demand_MW
        df_dt=st%imbalance_MW/m_eff_MWs
        st%ROCOF_Hz_s=df_dt
        st%frequency_Hz=clamp_real(st%frequency_Hz+df_dt*dt_s, &
            st%nominal_frequency_Hz-3.0_dp,st%nominal_frequency_Hz+3.0_dp)

        ! Update alarm flags
        st%alarm_underfreq   = st%frequency_Hz < (st%nominal_frequency_Hz - 0.5_dp)
        st%alarm_overfreq    = st%frequency_Hz > (st%nominal_frequency_Hz + 0.5_dp)
        st%alarm_low_reserve = merge(st%reserve_MW < st%fleet_reserve_requirement_MW, &
            st%reserve_MW < 2.0_dp, st%fleet_mode)
        st%alarm_low_soc     = st%battery_soc_pct < 15.0_dp
        st%alarm_ufls_active = st%UFLS_stage > 0
        ! A stopped compressor has no running-map surge margin. Do not
        ! raise a fictitious surge or max-output alarm after fuel isolation.
        st%alarm_turbine_max = st%gt_phase==GT_ONLINE .and. &
            st%gas_dispatch_pct >= (GAS_MAX_PCT - 0.5_dp)
        st%alarm_surge       = st%gt_phase==GT_ONLINE .and. &
            st%surge_margin_pct < SURGE_ALARM_PCT
    end subroutine tick_frequency_dynamics

end module grid_dynamics
