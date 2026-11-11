!> Explicit dimensional area inertia and open-loop frequency forecast.
!> Research-only aggregate-area model. No OEM/network identification is implied.
module grid_frequency_physics
    use precision_kinds, only: dp
    use engine_state
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    public :: grid_stored_energy_MWs, grid_swing_MW_s_per_Hz
    public :: refresh_frequency_sensitive_demand, grid_fixed_loss_horizon_min
contains
    !> Total aggregate rotational energy at nominal speed (MW*s = MJ).
    !> External area inertia is deliberately kept when the modelled GT trips:
    !> this represents OTHER, not directly simulated, connected rotating assets.
    pure real(dp) function grid_stored_energy_MWs(st) result(e)
        type(GridState), intent(in) :: st
        integer :: i
        e=-1.0_dp
        if(.not.ieee_is_finite(st%grid_external_inertia_H_s) .or. &
           .not.ieee_is_finite(st%grid_external_inertia_rated_MW) .or. &
           .not.ieee_is_finite(st%grid_gt_inertia_H_s) .or. &
           .not.ieee_is_finite(st%grid_gt_inertia_rated_MW)) return
        if(st%grid_external_inertia_H_s<0.0_dp .or. &
           st%grid_external_inertia_rated_MW<0.0_dp .or. &
           st%grid_gt_inertia_H_s<0.0_dp .or. st%grid_gt_inertia_rated_MW<0.0_dp) return
        e=st%grid_external_inertia_H_s*st%grid_external_inertia_rated_MW
        if(st%fleet_mode) then
            do i=1,FLEET_N
                if(.not.ieee_is_finite(st%fleet_unit_inertia_MWs(i)) .or. &
                   st%fleet_unit_inertia_MWs(i)<0.0_dp) then
                    e=-1.0_dp
                    return
                end if
                if(st%fleet_unit_online(i)) e=e+st%fleet_unit_inertia_MWs(i)
            end do
        else if(st%gt_phase==GT_ONLINE .and. st%gt_breaker_closed) then
            e=e+st%grid_gt_inertia_H_s*st%grid_gt_inertia_rated_MW
        end if
        if(.not.ieee_is_finite(e) .or. e<=0.0_dp) e=-1.0_dp
    end function grid_stored_energy_MWs

    !> M=2*H*S/f_nom, unit MW*s/Hz. Dividing MW by this yields Hz/s.
    pure real(dp) function grid_swing_MW_s_per_Hz(st) result(m)
        type(GridState),intent(in) :: st
        real(dp) :: e
        m=-1.0_dp
        e=grid_stored_energy_MWs(st)
        if(e<=0.0_dp .or. .not.ieee_is_finite(st%nominal_frequency_Hz)) return
        if(st%nominal_frequency_Hz<=0.0_dp) return
        m=2.0_dp*e/st%nominal_frequency_Hz
        if(.not.ieee_is_finite(m) .or. m<=0.0_dp) m=-1.0_dp
    end function grid_swing_MW_s_per_Hz

    !> Actual frequency-sensitive load is separately BOOKED as a consumer:
    !> P_served=P_gross_after_UFLS + D*(f-f_nom), with a nonnegative floor.
    subroutine refresh_frequency_sensitive_demand(st)
        type(GridState),intent(inout) :: st
        st%static_served_demand_MW=max(0.0_dp, &
            st%demand_MW*(1.0_dp-st%UFLS_shed_fraction))
        st%ufls_shed_MW=st%demand_MW-st%static_served_demand_MW
        st%grid_damping_load_MW=0.0_dp
        if(.not.ieee_is_finite(st%grid_damping_MW_per_Hz) .or. &
           st%grid_damping_MW_per_Hz<0.0_dp .or. &
           .not.ieee_is_finite(st%frequency_Hz) .or. &
           .not.ieee_is_finite(st%nominal_frequency_Hz)) then
            st%grid_model_valid=.false.
        else
            st%grid_damping_load_MW=max(-st%static_served_demand_MW, &
                st%grid_damping_MW_per_Hz*(st%frequency_Hz-st%nominal_frequency_Hz))
        end if
        st%served_demand_MW=st%static_served_demand_MW+st%grid_damping_load_MW
    end subroutine refresh_frequency_sensitive_demand

    !> Minimum over a fixed horizon for M df/dt = P_fixed - D*(f-fnom).
    !> P_fixed = current nominal-load power balance minus the hypothetical
    !> additional loss. NO governor, UFLS, demand or BESS feedback is
    !> predicted. Monotone first-order response -> min is at an endpoint.
    subroutine grid_fixed_loss_horizon_min(st,loss_MW,horizon_s,min_Hz,valid)
        type(GridState),intent(in) :: st
        real(dp),intent(in) :: loss_MW,horizon_s
        real(dp),intent(out) :: min_Hz
        logical,intent(out) :: valid
        real(dp) :: m, d, p_fixed, f_end, decay, f0
        valid=.false.
        min_Hz=st%frequency_Hz
        m=grid_swing_MW_s_per_Hz(st)
        d=st%grid_damping_MW_per_Hz
        if(m<=0.0_dp .or. .not.ieee_is_finite(d) .or. d<0.0_dp .or. &
           .not.ieee_is_finite(loss_MW) .or. loss_MW<0.0_dp .or. &
           .not.ieee_is_finite(horizon_s) .or. horizon_s<=0.0_dp .or. &
           .not.ieee_is_finite(st%imbalance_MW) .or. &
           .not.ieee_is_finite(st%grid_damping_load_MW) .or. &
           .not.ieee_is_finite(st%frequency_Hz)) return
        f0=st%nominal_frequency_Hz
        p_fixed=st%imbalance_MW+st%grid_damping_load_MW-loss_MW
        if(d==0.0_dp) then
            f_end=st%frequency_Hz+(p_fixed/m)*horizon_s
        else
            decay=exp(-d*horizon_s/m)
            f_end=f0+(st%frequency_Hz-f0)*decay+ &
                (p_fixed/d)*(1.0_dp-decay)
        end if
        if(.not.ieee_is_finite(f_end)) return
        min_Hz=min(st%frequency_Hz,f_end)
        ! A projected excursion beyond the simulator's +/-3 Hz integration
        ! domain is reported, NOT hidden by artificial 47 Hz clipping.
        valid=abs(st%frequency_Hz-f0)<=3.0_dp .and. &
            abs(f_end-f0)<=3.0_dp .and. abs(min_Hz-f0)<=3.0_dp
    end subroutine grid_fixed_loss_horizon_min
end module grid_frequency_physics
