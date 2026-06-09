!> @file degradation.f90
!> @brief Maps interpretable degradation knobs onto an operating-point input.
!>
!> Four physically-grounded mechanisms are modelled:
!>   * compressor fouling      -> lowers compressor efficiency (delta_eta_compressor)
!>                                and reduces swallowed mass flow (delta_mdot_fraction)
!>   * turbine erosion/oxidation -> lowers turbine efficiency (delta_eta_turbine)
!>   * combustor/liner degradation -> raises combustor pressure loss (delta_dP_combustor)
!>
!> A "washed" preset captures the realistic asymmetry that on-line/off-line water
!> washing largely recovers compressor fouling but does NOT recover turbine
!> hot-section erosion - a genuine performance-engineering insight that falls
!> straight out of the model.
module degradation
    use precision_kinds, only: dp
    use types, only: InputCase, DegradationSet, CycleResult
    use utilities, only: to_upper
    implicit none
    private
    public :: make_preset, apply_degradation, performance_delta

contains

    !> Return a named preset degradation set. Extend freely with site-specific
    !> mechanisms; these four levels are a reasonable demonstration ladder.
    function make_preset(mode) result(d)
        character(len=*), intent(in) :: mode
        type(DegradationSet) :: d
        character(len=:), allocatable :: m

        m = trim(to_upper(mode))
        d%mode = trim(mode)
        select case (m)
        case ("CLEAN")
            d%delta_eta_compressor = 0.000_dp
            d%delta_mdot_fraction  = 0.000_dp
            d%delta_eta_turbine    = 0.000_dp
            d%delta_dP_combustor   = 0.000_dp
        case ("MILD")
            d%delta_eta_compressor = 0.010_dp
            d%delta_mdot_fraction  = 0.005_dp
            d%delta_eta_turbine    = 0.008_dp
            d%delta_dP_combustor   = 0.002_dp
        case ("SEVERE")
            d%delta_eta_compressor = 0.025_dp
            d%delta_mdot_fraction  = 0.015_dp
            d%delta_eta_turbine    = 0.018_dp
            d%delta_dP_combustor   = 0.005_dp
        case ("WASHED")
            ! Compressor recovered, turbine erosion persists.
            d%delta_eta_compressor = 0.005_dp
            d%delta_mdot_fraction  = 0.002_dp
            d%delta_eta_turbine    = 0.018_dp
            d%delta_dP_combustor   = 0.002_dp
        case default
            ! Unknown -> treat as clean but keep the label for traceability.
            d%delta_eta_compressor = 0.000_dp
            d%delta_mdot_fraction  = 0.000_dp
            d%delta_eta_turbine    = 0.000_dp
            d%delta_dP_combustor   = 0.000_dp
        end select
    end function make_preset

    !> Return a copy of `ic_clean` with the degradation set applied.
    function apply_degradation(ic_clean, d) result(ic_deg)
        type(InputCase), intent(in)     :: ic_clean
        type(DegradationSet), intent(in):: d
        type(InputCase) :: ic_deg

        ic_deg = ic_clean
        ic_deg%degradation_mode = d%mode

        ic_deg%eta_compressor = max(0.30_dp, ic_clean%eta_compressor - d%delta_eta_compressor)
        ic_deg%mdot_air_kg_s  = ic_clean%mdot_air_kg_s * (1.0_dp - d%delta_mdot_fraction)
        ic_deg%eta_turbine    = max(0.30_dp, ic_clean%eta_turbine - d%delta_eta_turbine)
        ic_deg%combustor_pressure_loss = ic_clean%combustor_pressure_loss + d%delta_dP_combustor
    end function apply_degradation

    !> Percentage performance deltas of `deg` relative to a clean baseline.
    !> Positive power/efficiency delta = improvement; positive heat-rate delta = worse.
    subroutine performance_delta(base, deg, dpower_pct, deff_pct, dHR_pct, dExhT_K, dFuel_pct)
        type(CycleResult), intent(in) :: base, deg
        real(dp), intent(out) :: dpower_pct, deff_pct, dHR_pct, dExhT_K, dFuel_pct

        dpower_pct = pct_change(base%net_power_MW,       deg%net_power_MW)
        deff_pct   = pct_change(base%thermal_efficiency, deg%thermal_efficiency)
        dHR_pct    = pct_change(base%heat_rate_kJ_kWh,   deg%heat_rate_kJ_kWh)
        dExhT_K    = deg%exhaust_temperature_K - base%exhaust_temperature_K
        dFuel_pct  = pct_change(base%fuel_flow_kg_s,     deg%fuel_flow_kg_s)
    end subroutine performance_delta

    pure function pct_change(base, val) result(p)
        real(dp), intent(in) :: base, val
        real(dp) :: p
        if (abs(base) < 1.0e-12_dp) then
            p = 0.0_dp
        else
            p = 100.0_dp * (val - base) / base
        end if
    end function pct_change

end module degradation
