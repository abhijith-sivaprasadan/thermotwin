!> @file hrsg.f90
!> @brief Single-pressure HRSG model for the Phase 3 combined-cycle pass.
!>
!> This is a transparent 0-D heat-balance model rather than a vendor HRSG
!> design code. It enforces a representative pinch/approach, computes a stack
!> temperature, allocates recovered heat across economizer/evaporator/
!> superheater duties, and returns the steam flow available to the bottoming
!> cycle.
module hrsg
    use precision_kinds, only: dp
    use fluid_properties, only: cp_gas_at
    implicit none
    private

    public :: HrsgResult, solve_hrsg
    public :: HRSG_MIN_PINCH_K, HRSG_APPROACH_K, HRSG_STEAM_PRESSURE_BAR

    real(dp), parameter :: HRSG_MIN_PINCH_K = 15.0_dp
    real(dp), parameter :: HRSG_APPROACH_K = 8.0_dp
    real(dp), parameter :: HRSG_STEAM_PRESSURE_BAR = 35.0_dp
    real(dp), parameter :: HRSG_SATURATION_T_K = 515.0_dp
    real(dp), parameter :: HRSG_STACK_FLOOR_K = 363.15_dp
    real(dp), parameter :: HRSG_SUPERHEAT_MARGIN_K = 25.0_dp
    real(dp), parameter :: HRSG_RECOVERY_FACTOR = 0.97_dp
    real(dp), parameter :: CP_WATER_J_KG_K = 4200.0_dp
    real(dp), parameter :: CP_STEAM_J_KG_K = 2200.0_dp
    real(dp), parameter :: LATENT_HEAT_J_KG = 1.55e6_dp

    type :: HrsgResult
        real(dp) :: stack_T_K = HRSG_STACK_FLOOR_K
        real(dp) :: pinch_K = HRSG_MIN_PINCH_K
        real(dp) :: approach_K = HRSG_APPROACH_K
        real(dp) :: feedwater_T_K = 320.0_dp
        real(dp) :: steam_pressure_bar = HRSG_STEAM_PRESSURE_BAR
        real(dp) :: steam_T_K = 773.15_dp
        real(dp) :: steam_flow_kg_s = 0.0_dp
        real(dp) :: recovered_heat_MW = 0.0_dp
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
        real(dp) :: stack_target_K, cp_exh, available_MW
        real(dp) :: q_econ_J_kg, q_evap_J_kg, q_sh_J_kg, q_total_J_kg
        real(dp) :: gas_span_MW

        res%pinch_K = HRSG_MIN_PINCH_K
        res%approach_K = HRSG_APPROACH_K
        res%steam_pressure_bar = HRSG_STEAM_PRESSURE_BAR
        res%feedwater_T_K = max(303.15_dp, ambient_T_K + 32.0_dp)
        res%steam_T_K = min(793.15_dp, exhaust_T_K - HRSG_SUPERHEAT_MARGIN_K)

        if (exhaust_T_K <= HRSG_SATURATION_T_K + HRSG_MIN_PINCH_K + 20.0_dp .or. &
                exhaust_mdot_kg_s <= 0.0_dp) then
            res%pinch_ok = .false.
            res%stack_T_K = exhaust_T_K
            return
        end if

        stack_target_K = max(HRSG_STACK_FLOOR_K, ambient_T_K + 75.0_dp)
        stack_target_K = min(stack_target_K, exhaust_T_K - 1.0_dp)
        cp_exh = cp_gas_at(0.5_dp * (exhaust_T_K + stack_target_K))
        available_MW = exhaust_mdot_kg_s * cp_exh * (exhaust_T_K - stack_target_K) / 1.0e6_dp
        res%recovered_heat_MW = max(0.0_dp, HRSG_RECOVERY_FACTOR * available_MW)
        res%stack_T_K = exhaust_T_K - res%recovered_heat_MW * 1.0e6_dp / &
            max(exhaust_mdot_kg_s * cp_exh, 1.0e-9_dp)

        q_econ_J_kg = CP_WATER_J_KG_K * max(0.0_dp, &
            HRSG_SATURATION_T_K - HRSG_APPROACH_K - res%feedwater_T_K)
        q_evap_J_kg = LATENT_HEAT_J_KG
        q_sh_J_kg = CP_STEAM_J_KG_K * max(0.0_dp, res%steam_T_K - HRSG_SATURATION_T_K)
        q_total_J_kg = q_econ_J_kg + q_evap_J_kg + q_sh_J_kg

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
