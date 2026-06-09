!> @file types.f90
!> @brief Central derived types shared across the whole simulator.
!>
!> Design principle: one input type (`InputCase`) describes a machine + operating
!> point; one result type (`CycleResult`) carries every computed quantity. Every
!> module (degradation, sensors, uncertainty, diagnostics) operates on these two
!> types. Keeping the data model centralised is what lets the modules compose
!> into a single coherent tool rather than a pile of independent scripts.
module types
    use precision_kinds, only: dp
    implicit none
    private

    integer, parameter, public :: NAME_LEN = 64
    integer, parameter, public :: TAG_LEN  = 32

    !> -------------------------------------------------------------------
    !> InputCase: everything needed to evaluate one operating point of one
    !> (possibly degraded) machine. Read from a CSV row by `csv_io`.
    !> -------------------------------------------------------------------
    type, public :: InputCase
        character(len=NAME_LEN) :: case_name = "unnamed"

        ! Ambient / inlet
        real(dp) :: ambient_T_K            = 288.15_dp
        real(dp) :: ambient_P_Pa           = 101325.0_dp
        real(dp) :: relative_humidity      = 0.60_dp        !< [-] (0..1), reserved for humid-air model
        real(dp) :: inlet_pressure_loss    = 0.010_dp       !< fractional dP across filter/inlet
        real(dp) :: mdot_air_kg_s          = 100.0_dp

        ! Compressor
        real(dp) :: pressure_ratio         = 15.0_dp
        real(dp) :: eta_compressor         = 0.86_dp        !< isentropic efficiency

        ! Combustor
        real(dp) :: T_turbine_inlet_K      = 1400.0_dp      !< TIT (firing temperature)
        real(dp) :: eta_combustor          = 0.98_dp
        real(dp) :: combustor_pressure_loss= 0.030_dp       !< fractional dP across combustor
        real(dp) :: LHV_J_kg               = 50.0e6_dp      !< fuel lower heating value

        ! Turbine
        real(dp) :: eta_turbine            = 0.89_dp        !< isentropic efficiency
        real(dp) :: exhaust_pressure_loss  = 0.020_dp       !< fractional dP exhaust/diffuser

        ! Shaft / generator / plant
        real(dp) :: eta_mechanical         = 0.990_dp
        real(dp) :: eta_generator          = 0.985_dp
        real(dp) :: auxiliary_load_fraction= 0.020_dp

        ! Bookkeeping
        character(len=TAG_LEN) :: degradation_mode = "clean"
    end type InputCase

    !> -------------------------------------------------------------------
    !> CycleResult: complete set of computed station states and KPIs.
    !> -------------------------------------------------------------------
    type, public :: CycleResult
        character(len=NAME_LEN) :: case_name        = "unnamed"
        character(len=TAG_LEN)  :: degradation_mode = "clean"

        ! Station 1 - compressor inlet
        real(dp) :: T1_K = 0.0_dp
        real(dp) :: P1_Pa = 0.0_dp

        ! Station 2 - compressor outlet
        real(dp) :: T2_K = 0.0_dp
        real(dp) :: P2_Pa = 0.0_dp
        real(dp) :: w_compressor_J_kg = 0.0_dp
        real(dp) :: power_compressor_MW = 0.0_dp

        ! Station 3 - turbine inlet (combustor outlet)
        real(dp) :: T3_K = 0.0_dp
        real(dp) :: P3_Pa = 0.0_dp
        real(dp) :: fuel_air_ratio = 0.0_dp
        real(dp) :: fuel_flow_kg_s = 0.0_dp
        real(dp) :: heat_input_MW = 0.0_dp     !< chemical (fuel*LHV)

        ! Station 4 - turbine outlet (exhaust)
        real(dp) :: T4_K = 0.0_dp
        real(dp) :: P4_Pa = 0.0_dp
        real(dp) :: w_turbine_J_kg = 0.0_dp
        real(dp) :: power_turbine_MW = 0.0_dp

        ! Mass flows
        real(dp) :: mdot_air_kg_s = 0.0_dp
        real(dp) :: mdot_gas_kg_s = 0.0_dp

        ! Plant-level KPIs
        real(dp) :: net_power_MW = 0.0_dp
        real(dp) :: gross_power_MW = 0.0_dp
        real(dp) :: w_net_specific_J_kg = 0.0_dp
        real(dp) :: thermal_efficiency = 0.0_dp    !< fraction
        real(dp) :: heat_rate_kJ_kWh = 0.0_dp
        real(dp) :: exhaust_temperature_K = 0.0_dp
        real(dp) :: exhaust_energy_MW = 0.0_dp     !< sensible energy above reference
        real(dp) :: specific_power_kW_per_kgps = 0.0_dp

        ! Solver status
        logical :: converged = .true.
        character(len=NAME_LEN) :: status_message = "ok"
    end type CycleResult

    !> -------------------------------------------------------------------
    !> DegradationSet: the four physically-interpretable degradation knobs.
    !> Applied to an InputCase by the `degradation` module.
    !> -------------------------------------------------------------------
    type, public :: DegradationSet
        character(len=TAG_LEN) :: mode = "clean"
        real(dp) :: delta_eta_compressor = 0.0_dp   !< absolute drop in compressor eta (fouling)
        real(dp) :: delta_mdot_fraction  = 0.0_dp   !< fractional reduction in inlet mass flow
        real(dp) :: delta_eta_turbine    = 0.0_dp   !< absolute drop in turbine eta (erosion)
        real(dp) :: delta_dP_combustor   = 0.0_dp   !< additional combustor pressure-loss fraction
    end type DegradationSet

    !> -------------------------------------------------------------------
    !> ComponentState: lumped-mass thermal node for the transient model.
    !> -------------------------------------------------------------------
    type, public :: ComponentState
        character(len=NAME_LEN) :: name = "metal_node"
        real(dp) :: temperature_K   = 300.0_dp   !< current metal temperature
        real(dp) :: thermal_mass_J_K= 5.0e5_dp   !< m * cp  [J/K]
        real(dp) :: hA_W_K          = 2.0e3_dp   !< gas-side conductance  h*A [W/K]
        real(dp) :: UA_loss_W_K     = 1.0e2_dp   !< ambient-loss conductance UA [W/K]
    end type ComponentState

    !> -------------------------------------------------------------------
    !> SensorSpec: error characteristics for one measured channel.
    !> Used by `sensor_model` and `uncertainty_analysis`.
    !> -------------------------------------------------------------------
    type, public :: SensorSpec
        character(len=TAG_LEN) :: channel = "generic"
        real(dp) :: bias        = 0.0_dp   !< systematic offset (same units as channel)
        real(dp) :: noise_sigma = 0.0_dp   !< random 1-sigma (same units as channel)
        real(dp) :: drift_rate  = 0.0_dp   !< per-hour drift (same units as channel)
    end type SensorSpec

end module types
