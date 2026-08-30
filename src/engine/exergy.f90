!> [7.0-P1] Exergy / second-law analysis.
!>
!> Computes a component-level exergy (availability) balance for the gas-turbine /
!> combined-cycle plant from the live thermodynamic state, and the rational
!> (second-law) efficiency.  Exergy is the maximum useful work obtainable as a
!> stream is brought reversibly to the dead state (T0, P0); the *destruction* of
!> exergy in each component is its irreversibility (T0 * entropy generation) and
!> is where real plants lose their thermodynamic potential — the combustor
!> typically dominates (~25-30 % of fuel exergy).
!>
!> Governing balance (rates, kW), closed to `closure`:
!>     Ex_fuel = W_net + (D_comp + D_comb + D_turb + D_hrsg) + Ex_stack + Ex_cond
!>
!> P1 derives gas-side stations from cycle quantities and lumps the bottoming
!> cycle; 7.0-P2 refines the steam side with IAPWS-IF97 exergy.  All property
!> assumptions are named constants below.
module exergy
    use precision_kinds, only: dp
    use engine_state,    only: GridState
    implicit none
    private
    public :: ExergyResult, compute_exergy

    real(dp), parameter :: P0_kPa    = 101.325_dp  ! dead-state pressure
    real(dp), parameter :: CP_AIR    = 1.005_dp    ! kJ/kg.K
    real(dp), parameter :: CP_GAS    = 1.150_dp    ! kJ/kg.K (hot combustion products)
    real(dp), parameter :: R_AIR     = 0.287_dp    ! kJ/kg.K
    real(dp), parameter :: R_GAS     = 0.290_dp    ! kJ/kg.K
    real(dp), parameter :: GAMMA_AIR = 1.400_dp
    real(dp), parameter :: ETA_C     = 0.870_dp    ! compressor isentropic eff (T2 estimate)
    real(dp), parameter :: PHI_FUEL  = 1.040_dp    ! chemical-exergy / LHV ratio (natural gas)

    !> Exergy breakdown (all rates in kW unless noted).
    type :: ExergyResult
        real(dp) :: T0_K       = 288.15_dp
        real(dp) :: m_air      = 0.0_dp   ! kg/s
        real(dp) :: m_gas      = 0.0_dp   ! kg/s
        real(dp) :: ex_fuel    = 0.0_dp   ! fuel exergy in
        real(dp) :: w_comp     = 0.0_dp   ! compressor work
        real(dp) :: w_gt       = 0.0_dp   ! GT net work out
        real(dp) :: w_st       = 0.0_dp   ! steam-turbine work out
        real(dp) :: w_net      = 0.0_dp   ! plant net work out
        real(dp) :: dest_comp  = 0.0_dp   ! exergy destruction — compressor
        real(dp) :: dest_comb  = 0.0_dp   !                       combustor
        real(dp) :: dest_turb  = 0.0_dp   !                       expander
        real(dp) :: dest_hrsg  = 0.0_dp   !                       HRSG + steam cycle (lumped, P1)
        real(dp) :: ex_stack   = 0.0_dp   ! external loss — flue gas to stack
        real(dp) :: ex_cond    = 0.0_dp   ! external loss — condenser (low grade)
        real(dp) :: dest_total = 0.0_dp   ! sum of destructions
        real(dp) :: eta_II     = 0.0_dp   ! rational (2nd-law) efficiency [-]
        real(dp) :: closure    = 0.0_dp   ! balance residual / Ex_fuel [-] (V&V)
    end type ExergyResult

contains

    !> Physical (thermomechanical) specific exergy of an ideal-gas stream [kJ/kg]
    !> relative to the dead state (T0, P0): ex = (h-h0) - T0 (s-s0).
    pure function phys_ex(T, P, cp, Rg, T0) result(ex)
        real(dp), intent(in) :: T, P, cp, Rg, T0
        real(dp) :: ex
        ex = cp * (T - T0) - T0 * (cp * log(T / T0) - Rg * log(P / P0_kPa))
    end function phys_ex

    !> Component-level exergy / second-law analysis from the live plant state.
    subroutine compute_exergy(st, r)
        type(GridState),    intent(in)  :: st
        type(ExergyResult), intent(out) :: r
        real(dp) :: T0, LHV, Qf, P2, T2, T2s
        real(dp) :: ex_air2, ex_gas_tit, ex_gas_exh, ex_gas_stk
        real(dp) :: w_turb_gross, ex_to_bottom, sum_dest

        T0     = st%ambient_C + 273.15_dp
        r%T0_K = T0
        LHV    = max(1.0_dp, st%h2_lhv_mj_kg) * 1000.0_dp     ! kJ/kg
        r%w_gt  = max(0.0_dp, st%gas_power_MW)   * 1000.0_dp  ! kW
        r%w_st  = max(0.0_dp, st%steam_power_MW) * 1000.0_dp
        r%w_net = max(0.0_dp, st%plant_power_MW) * 1000.0_dp

        Qf        = max(0.0_dp, st%fuel_flow_kg_s) * LHV       ! kW (LHV heat input)
        r%ex_fuel = Qf * PHI_FUEL

        ! Plant essentially off — report zeros (avoid log domain errors)
        if (st%fuel_flow_kg_s <= 1.0e-6_dp .or. st%exhaust_K <= T0 + 1.0_dp) return

        ! Gas / air mass flow from the GT energy balance (exhaust sensible heat)
        r%m_gas = max(1.0_dp, (Qf - r%w_gt) / (CP_GAS * (st%exhaust_K - T0)))
        r%m_air = max(0.5_dp, r%m_gas - st%fuel_flow_kg_s)

        ! Compressor discharge state (isentropic + efficiency estimate)
        P2  = max(1.0_dp, st%PR_op) * P0_kPa
        T2s = T0 * st%PR_op ** ((GAMMA_AIR - 1.0_dp) / GAMMA_AIR)
        T2  = T0 + (T2s - T0) / ETA_C
        ex_air2 = phys_ex(T2, P2, CP_AIR, R_AIR, T0)

        ! Gas-side station exergies (combustor/turbine-inlet at P2, exhaust at P0)
        ex_gas_tit = phys_ex(st%TIT_actual_K, P2,     CP_GAS, R_GAS, T0)
        ex_gas_exh = phys_ex(st%exhaust_K,    P0_kPa, CP_GAS, R_GAS, T0)

        ! Compressor: drawn work vs air exergy gain
        r%w_comp    = r%m_air * CP_AIR * (T2 - T0)
        r%dest_comp = max(0.0_dp, r%w_comp - r%m_air * ex_air2)

        ! Combustor: fuel + compressed-air exergy in, hot-gas exergy out
        r%dest_comb = max(0.0_dp, r%ex_fuel + r%m_air * ex_air2 - r%m_gas * ex_gas_tit)

        ! Expander: hot gas in, gross shaft work + exhaust gas out
        w_turb_gross = r%w_gt + r%w_comp
        r%dest_turb  = max(0.0_dp, r%m_gas * ex_gas_tit - w_turb_gross - r%m_gas * ex_gas_exh)

        ! Bottoming cycle (HRSG + ST + condenser) — lumped for P1
        if (st%combined_cycle .and. st%hrsg_stack_T_K > T0 + 1.0_dp) then
            ex_gas_stk   = phys_ex(st%hrsg_stack_T_K, P0_kPa, CP_GAS, R_GAS, T0)
            ex_to_bottom = max(0.0_dp, r%m_gas * (ex_gas_exh - ex_gas_stk))
            r%ex_stack   = r%m_gas * ex_gas_stk
            r%ex_cond    = 0.10_dp * max(0.0_dp, ex_to_bottom - r%w_st)   ! low-grade condenser exergy
            r%dest_hrsg  = max(0.0_dp, ex_to_bottom - r%w_st - r%ex_cond)
        else
            r%ex_stack   = r%m_gas * ex_gas_exh    ! simple cycle: full exhaust is stack loss
            r%ex_cond    = 0.0_dp
            r%dest_hrsg  = 0.0_dp
        end if

        ! Totals, rational efficiency, and balance-closure residual (V&V)
        sum_dest     = r%dest_comp + r%dest_comb + r%dest_turb + r%dest_hrsg
        r%dest_total = sum_dest
        r%eta_II     = r%w_net / max(1.0_dp, r%ex_fuel)
        r%closure    = (r%ex_fuel - r%w_net - sum_dest - r%ex_stack - r%ex_cond) &
                       / max(1.0_dp, r%ex_fuel)
    end subroutine compute_exergy

end module exergy
