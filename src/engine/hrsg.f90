!> @file hrsg.f90
!> @brief Compact HRSG model for the Phase 3 combined-cycle pass.
!>
!> This is a transparent 0-D heat-balance model rather than a vendor HRSG design
!> code. It enforces the HP evaporator pinch/approach, computes a stack
!> temperature, allocates recovered heat across economizer/evaporator/
!> superheater duties, and includes a small LP/economizer recovery credit so the
!> demonstrator behaves like a modern multi-pressure CCGT instead of a pure
!> single-pressure teaching boiler.
module hrsg
    use precision_kinds, only: dp
    use fluid_properties, only: cp_gas_at, if97_saturation_T_K, if97_h_liq_kJ_kg, &
        if97_h_vap_kJ_kg, if97_h_superheat_kJ_kg
    implicit none
    private

    public :: HrsgResult, solve_hrsg
    public :: HRSG_MIN_PINCH_K, HRSG_APPROACH_K, HRSG_STEAM_PRESSURE_BAR

    real(dp), parameter :: HRSG_MIN_PINCH_K = 15.0_dp
    real(dp), parameter :: HRSG_APPROACH_K = 8.0_dp
    real(dp), parameter :: HRSG_STEAM_PRESSURE_BAR = 35.0_dp
    real(dp), parameter :: HRSG_STACK_FLOOR_K = 363.15_dp
    real(dp), parameter :: HRSG_SUPERHEAT_MARGIN_K = 25.0_dp
    real(dp), parameter :: HRSG_RECOVERY_FACTOR = 0.97_dp
    real(dp), parameter :: HRSG_LP_RECOVERY_FACTOR = 0.92_dp
    real(dp), parameter :: CP_WATER_J_KG_K = 4200.0_dp
    real(dp), parameter :: HRSG_UA_HP_MW_K = 1.85_dp
    real(dp), parameter :: HRSG_UA_LP_MW_K = 1.05_dp
    real(dp), parameter :: HRSG_LP_PRESSURE_BAR = 0.8_dp

    type :: HrsgResult
        real(dp) :: stack_T_K = HRSG_STACK_FLOOR_K
        real(dp) :: pinch_K = HRSG_MIN_PINCH_K
        real(dp) :: approach_K = HRSG_APPROACH_K
        real(dp) :: feedwater_T_K = 320.0_dp
        real(dp) :: steam_pressure_bar = HRSG_STEAM_PRESSURE_BAR
        real(dp) :: steam_T_K = 773.15_dp
        real(dp) :: steam_flow_kg_s = 0.0_dp
        real(dp) :: recovered_heat_MW = 0.0_dp
        real(dp) :: hp_recovered_heat_MW = 0.0_dp
        real(dp) :: lp_recovered_heat_MW = 0.0_dp
        real(dp) :: economizer_MW = 0.0_dp
        real(dp) :: evaporator_MW = 0.0_dp
        real(dp) :: superheater_MW = 0.0_dp
        real(dp) :: effectiveness = 0.0_dp
        logical  :: pinch_ok = .true.
    end type HrsgResult

contains

    subroutine solve_hrsg(exhaust_T_K, exhaust_mdot_kg_s, ambient_T_K, res)
        real(dp), intent(in) :: exhaust_T_K, exhaust_mdot_kg_s, ambient_T_K
        type(HrsgResult), intent(out) :: res
        real(dp) :: stack_target_K, hp_stack_target_K, cp_exh, available_stack_MW, pinch_limited_MW
        real(dp) :: hp_recovered_MW, lp_recovered_MW, stack_after_hp_K
        real(dp) :: q_econ_J_kg, q_evap_J_kg, q_sh_J_kg, q_total_J_kg
        real(dp) :: gas_span_MW, frac_sh_ev, hot_T_at_evap_out_K
        real(dp) :: h_fw, h_sat_liq, h_sat_vap, h_super
        real(dp) :: c_hot_MW_K, eps_hp, eps_lp, ntu_hp, ntu_lp, load_proxy
        real(dp) :: lp_sat_T_K

        res%pinch_K = HRSG_MIN_PINCH_K
        res%approach_K = HRSG_APPROACH_K
        res%steam_pressure_bar = HRSG_STEAM_PRESSURE_BAR
        res%lp_recovered_heat_MW = 0.0_dp
        res%hp_recovered_heat_MW = 0.0_dp
        res%feedwater_T_K = max(303.15_dp, ambient_T_K + 32.0_dp)
        res%steam_T_K = min(793.15_dp, exhaust_T_K - HRSG_SUPERHEAT_MARGIN_K)
        res%steam_T_K = max(res%steam_T_K, if97_saturation_T_K(res%steam_pressure_bar) + 20.0_dp)

        if (exhaust_T_K <= if97_saturation_T_K(res%steam_pressure_bar) + HRSG_MIN_PINCH_K + 20.0_dp .or. &
                exhaust_mdot_kg_s <= 0.0_dp) then
            res%pinch_ok = .false.
            res%stack_T_K = exhaust_T_K
            return
        end if

        stack_target_K = max(HRSG_STACK_FLOOR_K, ambient_T_K + 75.0_dp)
        stack_target_K = min(stack_target_K, exhaust_T_K - 1.0_dp)
        lp_sat_T_K = if97_saturation_T_K(HRSG_LP_PRESSURE_BAR)
        hp_stack_target_K = max(stack_target_K, lp_sat_T_K + 10.0_dp)
        h_fw = CP_WATER_J_KG_K / 1000.0_dp * max(0.0_dp, res%feedwater_T_K - 273.15_dp)
        h_sat_liq = if97_h_liq_kJ_kg(res%steam_pressure_bar)
        h_sat_vap = if97_h_vap_kJ_kg(res%steam_pressure_bar)
        h_super = if97_h_superheat_kJ_kg(res%steam_pressure_bar, res%steam_T_K)
        q_econ_J_kg = 1000.0_dp * max(0.0_dp, h_sat_liq - h_fw)
        q_evap_J_kg = 1000.0_dp * max(0.0_dp, h_sat_vap - h_sat_liq)
        q_sh_J_kg = 1000.0_dp * max(0.0_dp, h_super - h_sat_vap)
        q_total_J_kg = q_econ_J_kg + q_evap_J_kg + q_sh_J_kg

        cp_exh = cp_gas_at(0.5_dp * (exhaust_T_K + stack_target_K))
        c_hot_MW_K = max(1.0e-9_dp, exhaust_mdot_kg_s * cp_exh / 1.0e6_dp)
        load_proxy = min(1.0_dp, max(0.25_dp, exhaust_mdot_kg_s / 120.0_dp))
        ntu_hp = HRSG_UA_HP_MW_K * (0.75_dp + 0.35_dp * load_proxy) / c_hot_MW_K
        eps_hp = 1.0_dp - exp(-max(0.0_dp, ntu_hp))
        available_stack_MW = exhaust_mdot_kg_s * cp_exh * (exhaust_T_K - hp_stack_target_K) / 1.0e6_dp
        frac_sh_ev = (q_sh_J_kg + q_evap_J_kg) / max(q_total_J_kg, 1.0e-9_dp)
        pinch_limited_MW = exhaust_mdot_kg_s * cp_exh * &
            max(0.0_dp, exhaust_T_K - (if97_saturation_T_K(res%steam_pressure_bar) + HRSG_MIN_PINCH_K)) / &
            max(frac_sh_ev, 1.0e-6_dp) / 1.0e6_dp
        hp_recovered_MW = max(0.0_dp, min(HRSG_RECOVERY_FACTOR * eps_hp * available_stack_MW, &
            pinch_limited_MW))
        stack_after_hp_K = exhaust_T_K - hp_recovered_MW * 1.0e6_dp / &
            max(exhaust_mdot_kg_s * cp_exh, 1.0e-9_dp)
        ntu_lp = HRSG_UA_LP_MW_K / c_hot_MW_K
        eps_lp = 1.0_dp - exp(-max(0.0_dp, ntu_lp))
        lp_recovered_MW = HRSG_LP_RECOVERY_FACTOR * eps_lp * max(0.0_dp, &
            exhaust_mdot_kg_s * cp_exh * (stack_after_hp_K - max(stack_target_K, lp_sat_T_K + 8.0_dp)) / 1.0e6_dp)
        res%recovered_heat_MW = hp_recovered_MW + lp_recovered_MW
        res%hp_recovered_heat_MW = hp_recovered_MW
        res%lp_recovered_heat_MW = lp_recovered_MW
        res%stack_T_K = exhaust_T_K - res%recovered_heat_MW * 1.0e6_dp / &
            max(exhaust_mdot_kg_s * cp_exh, 1.0e-9_dp)
        hot_T_at_evap_out_K = exhaust_T_K - frac_sh_ev * hp_recovered_MW * 1.0e6_dp / &
            max(exhaust_mdot_kg_s * cp_exh, 1.0e-9_dp)
        res%pinch_K = hot_T_at_evap_out_K - if97_saturation_T_K(res%steam_pressure_bar)

        if (q_total_J_kg > 1.0e-9_dp) then
            res%steam_flow_kg_s = res%recovered_heat_MW * 1.0e6_dp / q_total_J_kg
            res%economizer_MW = res%steam_flow_kg_s * q_econ_J_kg / 1.0e6_dp
            res%evaporator_MW = res%steam_flow_kg_s * q_evap_J_kg / 1.0e6_dp
            res%superheater_MW = res%steam_flow_kg_s * q_sh_J_kg / 1.0e6_dp
        end if

        gas_span_MW = exhaust_mdot_kg_s * cp_exh * &
            max(exhaust_T_K - res%feedwater_T_K, 1.0_dp) / 1.0e6_dp
        res%effectiveness = min(1.0_dp, res%recovered_heat_MW / max(gas_span_MW, 1.0e-9_dp))
        res%pinch_ok = res%pinch_K >= HRSG_MIN_PINCH_K - 1.0e-9_dp
    end subroutine solve_hrsg

end module hrsg
