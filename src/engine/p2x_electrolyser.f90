! =============================================================================
! p2x_electrolyser.f90  --  P2X flexible electrolyser load for ThermoTwin-F
!
! Models a Power-to-X (P2X) alkaline/PEM electrolyser that absorbs renewable
! curtailment when enabled.  The electrolyser is treated as a controllable
! load: it does NOT inject power into the grid but reduces the net surplus that
! would otherwise be curtailed.  The engine_core imbalance loop accounts for
! p2x_load_MW on the demand side; this module only advances the internal state.
!
! Physics summary
! ---------------
!   H2 lower heating value  : H2_LHV = 120.0 MJ/kg
!   Target absorbed load    : min(renewable_curtail_MW, p2x_capacity_MW)
!                             (0 when p2x_active is .false.)
!   Ramp limit              : 10 MW/s  (fast inverter-coupled front-end)
!   H2 production rate      : p2x_load_MW [MW] * efficiency
!                             / (H2_LHV [MJ/kg] * 1000 [kJ/MJ])
!                           = p2x_load_MW * efficiency / 120000 [kg/s]
!
! Note: 1 MW = 1000 kJ/s; dividing by LHV in kJ/kg gives kg/s directly.
! =============================================================================
module p2x_electrolyser
    use precision_kinds, only: dp
    use engine_state,    only: GridState
    implicit none
    private

    public :: p2x_step

    ! H2 lower heating value [MJ/kg] — same value used in h2_blend.f90
    real(dp), parameter :: H2_LHV_MJ_KG  = 120.0_dp
    ! Ramp limit [MW/s] — inverter-coupled electrolyser front-end is fast
    real(dp), parameter :: P2X_RAMP_MW_S = 10.0_dp
    ! Curtailment threshold below which electrolyser does not engage [MW]
    real(dp), parameter :: P2X_CURTAIL_THRESH_MW = 0.5_dp

contains

    ! -------------------------------------------------------------------------
    ! Advance the P2X electrolyser by one time step dt_s [s].
    !
    ! Reads:   st%p2x_active, st%p2x_capacity_MW, st%p2x_efficiency,
    !          st%renewable_curtail_MW
    ! Updates: st%p2x_load_MW, st%p2x_h2_kg_s
    ! Does NOT modify st%supply_MW — engine_core handles the net imbalance.
    ! -------------------------------------------------------------------------
    subroutine p2x_step(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp),        intent(in)    :: dt_s

        real(dp) :: target_load, delta, max_step

        ! Determine desired absorption [MW]
        if (st%p2x_active .and. &
            st%renewable_curtail_MW > P2X_CURTAIL_THRESH_MW) then
            target_load = min(st%renewable_curtail_MW, st%p2x_capacity_MW)
        else
            target_load = 0.0_dp
        end if

        ! Apply ramp limit: max change = P2X_RAMP_MW_S * dt_s [MW]
        max_step = P2X_RAMP_MW_S * dt_s
        delta    = target_load - st%p2x_load_MW
        if (delta > max_step) then
            delta = max_step
        else if (delta < -max_step) then
            delta = -max_step
        end if
        st%p2x_load_MW = st%p2x_load_MW + delta

        ! Guard against numerical drift below zero
        if (st%p2x_load_MW < 0.0_dp) st%p2x_load_MW = 0.0_dp

        ! H2 production rate [kg/s]
        !   MW * 1000 kJ/s/MW * efficiency / (H2_LHV_MJ_kg * 1000 kJ/MJ)
        !   = MW * efficiency / H2_LHV_MJ_kg  [kg/s]
        st%p2x_h2_kg_s = st%p2x_load_MW * st%p2x_efficiency / H2_LHV_MJ_KG

    end subroutine p2x_step

end module p2x_electrolyser
