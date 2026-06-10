!> @file steam_cycle.f90
!> @brief Single-pressure steam bottoming cycle for Phase 3.
!>
!> The model uses HRSG steam flow/temperature plus a condenser back-pressure
!> correlation against ambient temperature. It is intentionally compact but
!> keeps the governing levers visible: steam mass flow, expansion enthalpy drop,
!> turbine efficiency, generator efficiency, and parasitic auxiliaries.
module steam_cycle
    use precision_kinds, only: dp
    use hrsg, only: HrsgResult
    implicit none
    private

    public :: SteamCycleResult, solve_steam_cycle, ramp_limited
    public :: STEAM_RAMP_MW_PER_S

    real(dp), parameter :: STEAM_TURBINE_ETA = 0.86_dp
    real(dp), parameter :: STEAM_GENERATOR_ETA = 0.985_dp
    real(dp), parameter :: STEAM_AUX_FRACTION = 0.020_dp
    real(dp), parameter :: STEAM_RAMP_MW_PER_S = 0.18_dp
    real(dp), parameter :: BASE_IDEAL_DROP_J_KG = 1.68e6_dp

    type :: SteamCycleResult
        real(dp) :: condenser_pressure_kPa = 6.0_dp
        real(dp) :: ideal_work_J_kg = 0.0_dp
        real(dp) :: actual_work_J_kg = 0.0_dp
        real(dp) :: gross_power_MW = 0.0_dp
        real(dp) :: net_power_MW = 0.0_dp
    end type SteamCycleResult

contains

    subroutine solve_steam_cycle(hrsg_res, ambient_T_K, res)
        type(HrsgResult), intent(in) :: hrsg_res
        real(dp), intent(in) :: ambient_T_K
        type(SteamCycleResult), intent(out) :: res
        real(dp) :: ambient_C

        ambient_C = ambient_T_K - 273.15_dp
        res%condenser_pressure_kPa = clamp_real(6.0_dp + 0.22_dp * (ambient_C - 15.0_dp), &
            4.5_dp, 14.0_dp)

        res%ideal_work_J_kg = BASE_IDEAL_DROP_J_KG + &
            700.0_dp * (hrsg_res%steam_T_K - 773.15_dp) - &
            12000.0_dp * (res%condenser_pressure_kPa - 6.0_dp)
        res%ideal_work_J_kg = max(0.0_dp, res%ideal_work_J_kg)
        res%actual_work_J_kg = res%ideal_work_J_kg * STEAM_TURBINE_ETA

        res%gross_power_MW = hrsg_res%steam_flow_kg_s * res%actual_work_J_kg * &
            STEAM_GENERATOR_ETA / 1.0e6_dp
        res%net_power_MW = res%gross_power_MW * (1.0_dp - STEAM_AUX_FRACTION)
    end subroutine solve_steam_cycle

    pure function ramp_limited(current, target, rate, dt_s) result(value)
        real(dp), intent(in) :: current, target, rate, dt_s
        real(dp) :: value

        value = current + clamp_real(target - current, -rate * dt_s, rate * dt_s)
    end function ramp_limited

    pure function clamp_real(value, lo, hi) result(clamped)
        real(dp), intent(in) :: value, lo, hi
        real(dp) :: clamped
        clamped = min(max(value, lo), hi)
    end function clamp_real

end module steam_cycle
