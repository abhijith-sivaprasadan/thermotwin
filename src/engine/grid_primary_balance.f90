!> Source-of-truth primary active-power controls for the educational grid.
!> All BESS support is reconciled into ONE delivered storage_MW that is
!> subsequently integrated by battery SOC, economic accounting and the swing
!> equation. The turbine governor acts through the off-design dispatch solver,
!> not as an extra electrical injection created in grid_dynamics.
module grid_primary_balance
    use precision_kinds, only: dp
    use engine_state
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    public :: tick_governor_setpoint, resolve_bess_injection
contains
    subroutine tick_governor_setpoint(st,dt_s)
        type(GridState),intent(inout) :: st
        real(dp),intent(in) :: dt_s
        real(dp) :: delta_f, target_pct, max_step

        if(st%gt_phase/=GT_ONLINE .or. st%fleet_mode .or. .not.st%governor_enabled .or. &
           st%gas_capacity_MW<=1.0e-9_dp) then
            ! A fleet governor is NOT modeled; no synthetic MW is injected.
            st%governor_offset_pct=0.0_dp
            st%effective_gas_dispatch_pct=merge(0.0_dp,st%gas_dispatch_pct,st%gt_phase/=GT_ONLINE)
            st%governor_delta_MW=0.0_dp
            return
        end if
        if(.not.ieee_is_finite(dt_s) .or. dt_s<=0.0_dp .or. &
           .not.ieee_is_finite(st%frequency_Hz) .or. &
           .not.ieee_is_finite(st%nominal_frequency_Hz) .or. &
           st%nominal_frequency_Hz<=0.0_dp) then
            st%governor_offset_pct=0.0_dp
            st%effective_gas_dispatch_pct=st%gas_dispatch_pct
            st%governor_delta_MW=0.0_dp
            return
        end if

        delta_f=st%frequency_Hz-st%nominal_frequency_Hz
        ! Convert 5% droop to an additive fraction of rated power. Because the
        ! off-design solver targets load fraction of capacity, this changes
        ! *actual fuel consumption and GT electrical output* in the same solve.
        ! Rotor and fuel-valve transient dynamics are NOT modeled.
        target_pct=-100.0_dp*delta_f/st%nominal_frequency_Hz/GOVERNOR_DROOP_R
        target_pct=clamp_real(target_pct,GAS_MIN_PCT-st%gas_dispatch_pct, &
            GAS_MAX_PCT-st%gas_dispatch_pct)
        max_step=GAS_RAMP_PCT_PER_S*dt_s
        st%governor_offset_pct=st%governor_offset_pct+ &
            clamp_real(target_pct-st%governor_offset_pct,-max_step,max_step)
        st%governor_offset_pct=clamp_real(st%governor_offset_pct, &
            GAS_MIN_PCT-st%gas_dispatch_pct,GAS_MAX_PCT-st%gas_dispatch_pct)
        st%effective_gas_dispatch_pct=clamp_real(st%gas_dispatch_pct+st%governor_offset_pct, &
            GAS_MIN_PCT,GAS_MAX_PCT)
    end subroutine tick_governor_setpoint

    subroutine resolve_bess_injection(st,dt_s)
        type(GridState),intent(inout) :: st
        real(dp),intent(in) :: dt_s
        real(dp) :: baseline_MW, primary_target_MW, after_primary_MW
        real(dp) :: final_MW, delta_f

        baseline_MW=limited_storage_power_for_step(st,st%storage_request_MW,dt_s)
        primary_target_MW=0.0_dp
        if(ieee_is_finite(st%frequency_Hz) .and. &
           ieee_is_finite(st%nominal_frequency_Hz) .and. st%nominal_frequency_Hz>0.0_dp) then
            delta_f=st%frequency_Hz-st%nominal_frequency_Hz
            if(st%fcr_hold .and. abs(delta_f)>BESS_PRIMARY_DB) then
                primary_target_MW=clamp_real(-delta_f*BESS_PRIMARY_GAIN,-5.0_dp,5.0_dp)
            end if
        end if
        ! Order of arbitration is deliberate: commanded storage first, then
        ! conventional frequency response, then GFM response. Every stage is
        ! bounded by the SAME power inverter and remaining timestep energy.
        after_primary_MW=limited_storage_power_for_step(st,baseline_MW+primary_target_MW,dt_s)
        st%BESS_primary_MW=after_primary_MW-baseline_MW
        final_MW=after_primary_MW
        if(st%gfm_mode) then
            final_MW=limited_storage_power_for_step(st,after_primary_MW+st%gfm_request_MW,dt_s)
        end if
        st%gfm_synth_MW=final_MW-after_primary_MW
        st%storage_MW=final_MW
    end subroutine resolve_bess_injection
end module grid_primary_balance
