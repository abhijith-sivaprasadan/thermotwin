!> @file constants.f90
!> @brief Physical constants and default fluid/reference properties.
!>
!> All values are SI unless explicitly suffixed. Combustion-gas properties are
!> representative textbook averages for lean kerosene/natural-gas products in
!> the 1000-1500 K range. They are intentionally simple (constant) at this
!> stage; `fluid_properties` provides temperature-dependent alternatives that
!> can be switched on later without touching the component models.
module constants
    use precision_kinds, only: dp
    implicit none
    private

    ! ---------------------------------------------------------------------
    ! Universal / mathematical
    ! ---------------------------------------------------------------------
    real(dp), parameter, public :: PI            = 3.14159265358979323846_dp
    real(dp), parameter, public :: R_UNIVERSAL   = 8.314462618_dp      !< J/(mol K)

    ! ---------------------------------------------------------------------
    ! Reference / standard conditions
    ! ---------------------------------------------------------------------
    !> ISO 2314 reference ambient (15 degC) used for corrected-performance work.
    real(dp), parameter, public :: T_REF_ISO_K   = 288.15_dp           !< K
    real(dp), parameter, public :: P_REF_ISO_PA  = 101325.0_dp         !< Pa
    real(dp), parameter, public :: RH_REF_ISO    = 0.60_dp             !< 60% relative humidity

    ! ---------------------------------------------------------------------
    ! Air properties (cold-side, around compressor temperatures)
    ! ---------------------------------------------------------------------
    real(dp), parameter, public :: R_AIR         = 287.05_dp           !< J/(kg K)
    real(dp), parameter, public :: CP_AIR        = 1004.5_dp           !< J/(kg K)
    real(dp), parameter, public :: GAMMA_AIR     = 1.400_dp            !< [-]

    ! ---------------------------------------------------------------------
    ! Combustion-gas properties (hot-side, around turbine temperatures)
    ! ---------------------------------------------------------------------
    real(dp), parameter, public :: R_GAS         = 287.80_dp           !< J/(kg K)
    real(dp), parameter, public :: CP_GAS        = 1148.0_dp           !< J/(kg K)
    real(dp), parameter, public :: GAMMA_GAS     = 1.333_dp            !< [-]

    ! ---------------------------------------------------------------------
    ! Unit-conversion helpers (named to make call sites self-documenting)
    ! ---------------------------------------------------------------------
    real(dp), parameter, public :: W_PER_MW      = 1.0e6_dp
    real(dp), parameter, public :: J_PER_KJ      = 1.0e3_dp
    real(dp), parameter, public :: SECONDS_PER_HOUR = 3600.0_dp
    real(dp), parameter, public :: KELVIN_OFFSET = 273.15_dp           !< degC -> K offset

    ! ---------------------------------------------------------------------
    ! Numerical tolerances
    ! ---------------------------------------------------------------------
    real(dp), parameter, public :: TINY_DP       = 1.0e-12_dp          !< guard against /0
    real(dp), parameter, public :: SMALL_DP      = 1.0e-6_dp

end module constants
