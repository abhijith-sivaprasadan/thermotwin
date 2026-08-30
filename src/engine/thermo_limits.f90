!> [7.0-P6] Theoretical efficiency limits for benchmarking the live plant.
!>
!> Computes the absolute and practical upper bounds against which the achieved
!> efficiency is judged: the Carnot limit between turbine-inlet and ambient
!> temperatures, the Curzon-Ahlborn endoreversible (maximum-power) limit, the
!> ideal air-standard Brayton limit from the pressure ratio, and the plant's
!> actual first-law efficiency with its fraction-of-Carnot. Pure thermodynamic
!> identities — the interpretation layer that says how close the plant is to the
!> physics ceiling.
module thermo_limits
    use precision_kinds, only: dp
    use engine_state,    only: GridState
    implicit none
    private
    public :: ThermoLimits, compute_thermo_limits

    real(dp), parameter :: GAMMA = 1.4_dp

    type :: ThermoLimits
        real(dp) :: T_source_K         = 0.0_dp
        real(dp) :: T_sink_K           = 0.0_dp
        real(dp) :: eta_carnot         = 0.0_dp   ! 1 - T_sink/T_source (absolute ceiling)
        real(dp) :: eta_curzon_ahlborn = 0.0_dp   ! 1 - sqrt(T_sink/T_source) (max-power)
        real(dp) :: eta_brayton_ideal  = 0.0_dp   ! 1 - PR^(-(g-1)/g)
        real(dp) :: eta_actual         = 0.0_dp   ! plant_power / fuel LHV heat
        real(dp) :: carnot_fraction    = 0.0_dp   ! eta_actual / eta_carnot
    end type ThermoLimits

contains

    subroutine compute_thermo_limits(st, r)
        type(GridState),    intent(in)  :: st
        type(ThermoLimits), intent(out) :: r
        real(dp) :: Tsrc, Tsnk, ratio, fuel_heat_kW

        Tsnk  = st%ambient_C + 273.15_dp
        Tsrc  = max(Tsnk + 1.0_dp, st%TIT_actual_K)
        ratio = Tsnk / Tsrc

        r%T_source_K         = Tsrc
        r%T_sink_K           = Tsnk
        r%eta_carnot         = 1.0_dp - ratio
        r%eta_curzon_ahlborn = 1.0_dp - sqrt(ratio)
        r%eta_brayton_ideal  = 1.0_dp - max(1.0_dp, st%PR_op) ** (-(GAMMA - 1.0_dp) / GAMMA)

        fuel_heat_kW = max(1.0e-6_dp, st%fuel_flow_kg_s) * max(1.0_dp, st%h2_lhv_mj_kg) * 1000.0_dp
        r%eta_actual      = max(0.0_dp, st%plant_power_MW) * 1000.0_dp / fuel_heat_kW
        r%carnot_fraction = r%eta_actual / max(1.0e-9_dp, r%eta_carnot)
    end subroutine compute_thermo_limits

end module thermo_limits
