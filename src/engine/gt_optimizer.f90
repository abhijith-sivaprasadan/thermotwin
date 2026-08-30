! =============================================================================
! gt_optimizer.f90 — P2 real-time GT economic dispatch optimizer
!
! Sweeps GT_OPT_N dispatch levels (30 %–100 %) using the live off-design
! solver and finds the operating point that maximises:
!
!   margin(P) = price · P  –  fuel_cost(P)  –  carbon_cost(P)     [$/h]
!
! where fuel_cost and carbon_cost come from the physics-consistent heat
! input and fuel flow returned by solve_off_design.
!
! Called by engine_core every GT_OPT_TICKS ticks (~2 s).
! =============================================================================
module gt_optimizer
    use precision_kinds, only: dp
    use engine_state                        ! GridState, GT_OPT_N, CO2_KG_PER_KG_FUEL
    use off_design,      only: OffDesignPoint, solve_off_design
    use types,           only: InputCase
    implicit none
    private
    public :: solve_gt_optimizer

    real(dp), parameter :: KELVIN = 273.15_dp

contains

    ! -------------------------------------------------------------------------
    ! Main entry: sweep 20 dispatch levels, write results into GridState.
    ! -------------------------------------------------------------------------
    subroutine solve_gt_optimizer(st)
        type(GridState), intent(inout) :: st
        type(InputCase)      :: ic
        type(OffDesignPoint) :: od
        integer  :: i, best_idx
        real(dp) :: dispatch, margin, best_margin

        ! Build InputCase from live GridState (mirrors engine_core::baseline_case)
        ic%case_name               = "gt_opt"
        ic%ambient_T_K             = st%ambient_C + KELVIN
        ic%ambient_P_Pa            = 101325.0_dp
        ic%relative_humidity       = 0.60_dp
        ic%inlet_pressure_loss     = 0.010_dp
        ic%mdot_air_kg_s           = 100.0_dp
        ic%pressure_ratio          = 15.0_dp
        ic%eta_compressor          = 0.86_dp
        ic%T_turbine_inlet_K       = st%TIT_K
        ic%eta_combustor           = 0.98_dp
        ic%combustor_pressure_loss = 0.030_dp
        ic%LHV_J_kg                = 50.0e6_dp
        ic%eta_turbine             = 0.89_dp
        ic%exhaust_pressure_loss   = 0.020_dp
        ic%eta_mechanical          = 0.990_dp
        ic%eta_generator           = 0.985_dp
        ic%auxiliary_load_fraction = 0.020_dp
        ic%degradation_mode        = "clean"

        ! Current-dispatch margin (for delta computation)
        call solve_off_design(ic, &
            max(0.01_dp, min(1.0_dp, st%gas_dispatch_pct / 100.0_dp)), &
            0.0_dp, od)
        st%gt_opt_curr_margin = margin_usd_h(od, st)

        ! Scan GT_OPT_N equally-spaced points from 30 % to 100 % dispatch
        best_margin = -1.0e30_dp
        best_idx    = 1
        do i = 1, GT_OPT_N
            dispatch = 0.30_dp + real(i - 1, dp) / real(GT_OPT_N - 1, dp) * 0.70_dp
            call solve_off_design(ic, dispatch, 0.0_dp, od)
            margin = margin_usd_h(od, st)
            st%gt_opt_pwr   (i) = max(0.0_dp, od%cyc%net_power_MW)
            st%gt_opt_hr    (i) = od%cyc%heat_rate_kJ_kWh
            st%gt_opt_margin(i) = margin
            if (margin > best_margin) then
                best_margin = margin
                best_idx    = i
            end if
        end do

        st%gt_opt_best_idx    = best_idx
        st%gt_opt_best_margin = best_margin
        st%gt_opt_saving_h    = best_margin - st%gt_opt_curr_margin
        st%gt_opt_solved      = .true.
    end subroutine solve_gt_optimizer

    ! -------------------------------------------------------------------------
    ! Contribution margin $/h: revenue – fuel cost – carbon cost.
    ! -------------------------------------------------------------------------
    pure function margin_usd_h(od, st) result(m)
        type(OffDesignPoint), intent(in) :: od
        type(GridState),      intent(in) :: st
        real(dp) :: m
        real(dp) :: fc_h, cc_h, rev_h
        ! Fuel cost: heat_input [MW] × 3.6 [GJ/MWh] × price [$/GJ]
        fc_h  = od%cyc%heat_input_MW * 3.6_dp * st%fuel_price_usd_gj
        ! Carbon cost: fuel_flow [kg/s] × CO2 ratio × 3600 [s/h] × price [$/t] / 1000 [kg/t]
        cc_h  = od%cyc%fuel_flow_kg_s * CO2_KG_PER_KG_FUEL * 3600.0_dp * &
                st%carbon_price_usd_t / 1000.0_dp
        ! Revenue: price [$/MWh] × power [MW]
        rev_h = st%power_price_usd_mwh * max(0.0_dp, od%cyc%net_power_MW)
        m     = rev_h - fc_h - cc_h
    end function margin_usd_h

end module gt_optimizer
