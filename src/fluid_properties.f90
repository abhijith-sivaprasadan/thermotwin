!> @file fluid_properties.f90
!> @brief Working-fluid thermodynamic properties.
!>
!> Two property models are provided behind one interface:
!>   * CONSTANT  - fixed cp, gamma (Rev A default; matches hand calculations)
!>   * VARIABLE  - simple temperature-dependent cp polynomial, gamma from cp & R
!>
!> Switching `property_model` changes the whole simulation without editing any
!> component code. The constant model is the default so that the verification
!> hand-calculation in docs/verification.md matches the code exactly.
module fluid_properties
    use precision_kinds, only: dp
    use constants, only: CP_AIR, GAMMA_AIR, R_AIR, CP_GAS, GAMMA_GAS, R_GAS
    implicit none
    private

    public :: PROP_CONSTANT, PROP_VARIABLE
    public :: set_property_model, get_property_model
    public :: cp_air_at, gamma_air_at, cp_gas_at, gamma_gas_at
    public :: gamma_exponent

    integer, parameter :: PROP_CONSTANT = 0
    integer, parameter :: PROP_VARIABLE = 1

    !> Module-level selector. Defaults to CONSTANT for reproducible verification.
    integer, save :: property_model = PROP_CONSTANT

contains

    subroutine set_property_model(model)
        integer, intent(in) :: model
        property_model = model
    end subroutine set_property_model

    pure function get_property_model() result(m)
        integer :: m
        m = property_model
    end function get_property_model

    !> cp of air [J/kg/K] at temperature T [K].
    !> VARIABLE model: mild linear rise capturing real-air behaviour 250-900 K.
    pure function cp_air_at(T_K) result(cp)
        real(dp), intent(in) :: T_K
        real(dp) :: cp
        if (property_model == PROP_VARIABLE) then
            ! ~1004 J/kgK at 300 K, rising gently with temperature.
            cp = 1004.0_dp + 0.075_dp * (T_K - 300.0_dp)
        else
            cp = CP_AIR
        end if
    end function cp_air_at

    pure function gamma_air_at(T_K) result(g)
        real(dp), intent(in) :: T_K
        real(dp) :: g, cp
        if (property_model == PROP_VARIABLE) then
            cp = cp_air_at(T_K)
            g  = cp / (cp - R_AIR)
        else
            g = GAMMA_AIR
        end if
    end function gamma_air_at

    !> cp of combustion gas [J/kg/K] at temperature T [K].
    pure function cp_gas_at(T_K) result(cp)
        real(dp), intent(in) :: T_K
        real(dp) :: cp
        if (property_model == PROP_VARIABLE) then
            ! ~1140 J/kgK at 1000 K, rising toward ~1200 J/kgK near 1600 K.
            cp = 1140.0_dp + 0.10_dp * (T_K - 1000.0_dp)
        else
            cp = CP_GAS
        end if
    end function cp_gas_at

    pure function gamma_gas_at(T_K) result(g)
        real(dp), intent(in) :: T_K
        real(dp) :: g, cp
        if (property_model == PROP_VARIABLE) then
            cp = cp_gas_at(T_K)
            g  = cp / (cp - R_GAS)
        else
            g = GAMMA_GAS
        end if
    end function gamma_gas_at

    !> Convenience: the isentropic exponent (gamma-1)/gamma at temperature T_K
    !> for a chosen fluid ('air' or 'gas'). Used by compressor/turbine models.
    pure function gamma_exponent(T_K, fluid) result(ex)
        real(dp), intent(in) :: T_K
        character(len=*), intent(in) :: fluid
        real(dp) :: ex, g
        select case (trim(fluid))
        case ('gas', 'GAS', 'hot')
            g = gamma_gas_at(T_K)
        case default
            g = gamma_air_at(T_K)
        end select
        ex = (g - 1.0_dp) / g
    end function gamma_exponent

end module fluid_properties
