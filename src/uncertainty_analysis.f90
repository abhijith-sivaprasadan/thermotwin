!> @file uncertainty_analysis.f90
!> @brief Propagates measurement uncertainty into performance-KPI uncertainty.
!>
!> Two complementary methods (both standard in performance test practice):
!>
!>   1. Monte Carlo: draw N noisy realisations of the inlet boundary conditions
!>      using the sensor noise/bias model, re-solve the cycle each time, and
!>      report the resulting KPI distributions (mean, sigma, 95% interval).
!>
!>   2. Deterministic bias sensitivity: perturb one channel by +/- its bias and
!>      record the KPI shift, exposing which measurement dominates uncertainty.
!>
!> This mirrors the spirit of ASME PTC 19.1 / PTC 22 uncertainty analysis at a
!> teaching level (it is not a certified uncertainty budget).
module uncertainty_analysis
    use precision_kinds, only: dp, i4
    use types, only: InputCase, CycleResult, SensorSpec
    use cycle_solver, only: solve_cycle
    use utilities, only: mean, stddev, percentile, gaussian_random
    implicit none
    private
    public :: UncertaintyResult, monte_carlo_uncertainty, bias_sensitivity_row
    public :: BiasSensitivity

    !> Aggregate Monte Carlo output for the main KPIs.
    type :: UncertaintyResult
        integer :: n_samples = 0
        ! net power [MW]
        real(dp) :: power_mean = 0.0_dp, power_sigma = 0.0_dp
        real(dp) :: power_p025 = 0.0_dp, power_p975 = 0.0_dp
        ! thermal efficiency [-]
        real(dp) :: eff_mean = 0.0_dp, eff_sigma = 0.0_dp
        real(dp) :: eff_p025 = 0.0_dp, eff_p975 = 0.0_dp
        ! heat rate [kJ/kWh]
        real(dp) :: hr_mean = 0.0_dp, hr_sigma = 0.0_dp
        real(dp) :: hr_p025 = 0.0_dp, hr_p975 = 0.0_dp
    end type UncertaintyResult

    !> One row of a deterministic bias-sensitivity study.
    type :: BiasSensitivity
        character(len=32) :: channel = ""
        real(dp) :: applied_bias = 0.0_dp
        real(dp) :: dpower_MW = 0.0_dp
        real(dp) :: deff = 0.0_dp
        real(dp) :: dHR_kJ_kWh = 0.0_dp
    end type BiasSensitivity

contains

    !> Monte Carlo propagation. The sensors describe noise/bias on the BOUNDARY
    !> inputs (ambient T, ambient P, mass flow, TIT, fuel LHV...). Here we apply
    !> noise to the most influential boundary conditions: ambient temperature,
    !> ambient pressure, mass flow, and TIT. Extend as needed.
    function monte_carlo_uncertainty(ic_nominal, sigma_Tamb_K, sigma_Pamb_Pa, &
            sigma_mdot_frac, sigma_TIT_K, n_samples, seed_already_set) result(u)
        type(InputCase), intent(in) :: ic_nominal
        real(dp), intent(in) :: sigma_Tamb_K, sigma_Pamb_Pa, sigma_mdot_frac, sigma_TIT_K
        integer, intent(in)  :: n_samples
        logical, intent(in)  :: seed_already_set
        type(UncertaintyResult) :: u

        type(InputCase)   :: ic
        type(CycleResult) :: r
        real(dp), allocatable :: pw(:), ef(:), hr(:)
        integer :: k, kept

        if (.not. seed_already_set) continue   ! caller controls seeding via utilities

        allocate(pw(n_samples), ef(n_samples), hr(n_samples))
        kept = 0
        do k = 1, n_samples
            ic = ic_nominal
            ic%ambient_T_K       = ic_nominal%ambient_T_K + gaussian_random(0.0_dp, sigma_Tamb_K)
            ic%ambient_P_Pa      = ic_nominal%ambient_P_Pa + gaussian_random(0.0_dp, sigma_Pamb_Pa)
            ic%mdot_air_kg_s     = ic_nominal%mdot_air_kg_s * &
                                   (1.0_dp + gaussian_random(0.0_dp, sigma_mdot_frac))
            ic%T_turbine_inlet_K = ic_nominal%T_turbine_inlet_K + gaussian_random(0.0_dp, sigma_TIT_K)

            r = solve_cycle(ic)
            if (r%converged) then
                kept = kept + 1
                pw(kept) = r%net_power_MW
                ef(kept) = r%thermal_efficiency
                hr(kept) = r%heat_rate_kJ_kWh
            end if
        end do

        u%n_samples = kept
        if (kept >= 1) then
            u%power_mean = mean(pw(1:kept)); u%power_sigma = stddev(pw(1:kept))
            u%eff_mean   = mean(ef(1:kept)); u%eff_sigma   = stddev(ef(1:kept))
            u%hr_mean    = mean(hr(1:kept)); u%hr_sigma    = stddev(hr(1:kept))
            u%power_p025 = percentile(pw(1:kept), 2.5_dp)
            u%power_p975 = percentile(pw(1:kept), 97.5_dp)
            u%eff_p025   = percentile(ef(1:kept), 2.5_dp)
            u%eff_p975   = percentile(ef(1:kept), 97.5_dp)
            u%hr_p025    = percentile(hr(1:kept), 2.5_dp)
            u%hr_p975    = percentile(hr(1:kept), 97.5_dp)
        end if
        deallocate(pw, ef, hr)
    end function monte_carlo_uncertainty

    !> Deterministic +bias / -bias sensitivity for a single ambient-T channel
    !> (the most common dominant systematic error). The pattern generalises:
    !> copy this for other channels by perturbing the relevant InputCase field.
    function bias_sensitivity_row(ic_nominal, channel, bias_value) result(row)
        type(InputCase), intent(in) :: ic_nominal
        character(len=*), intent(in) :: channel
        real(dp), intent(in) :: bias_value
        type(BiasSensitivity) :: row

        type(InputCase)   :: ic_hi, ic_lo
        type(CycleResult) :: r_hi, r_lo

        ic_hi = ic_nominal
        ic_lo = ic_nominal

        select case (trim(channel))
        case ("T_ambient")
            ic_hi%ambient_T_K = ic_nominal%ambient_T_K + bias_value
            ic_lo%ambient_T_K = ic_nominal%ambient_T_K - bias_value
        case ("T_turbine_inlet")
            ic_hi%T_turbine_inlet_K = ic_nominal%T_turbine_inlet_K + bias_value
            ic_lo%T_turbine_inlet_K = ic_nominal%T_turbine_inlet_K - bias_value
        case ("pressure_ratio")
            ic_hi%pressure_ratio = ic_nominal%pressure_ratio + bias_value
            ic_lo%pressure_ratio = ic_nominal%pressure_ratio - bias_value
        case ("mdot_air")
            ic_hi%mdot_air_kg_s = ic_nominal%mdot_air_kg_s + bias_value
            ic_lo%mdot_air_kg_s = ic_nominal%mdot_air_kg_s - bias_value
        case default
            ! No-op channel; return zeros.
        end select

        r_hi = solve_cycle(ic_hi)
        r_lo = solve_cycle(ic_lo)

        row%channel = channel
        row%applied_bias = bias_value
        ! Half-range sensitivity (symmetric finite difference magnitude).
        row%dpower_MW  = 0.5_dp * (r_hi%net_power_MW       - r_lo%net_power_MW)
        row%deff       = 0.5_dp * (r_hi%thermal_efficiency - r_lo%thermal_efficiency)
        row%dHR_kJ_kWh = 0.5_dp * (r_hi%heat_rate_kJ_kWh   - r_lo%heat_rate_kJ_kWh)
    end function bias_sensitivity_row

end module uncertainty_analysis
