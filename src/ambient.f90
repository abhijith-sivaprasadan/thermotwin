!> @file ambient.f90
!> @brief Inlet / ambient model establishing compressor-inlet (station 1) state.
!>
!> Accounts for the inlet/filter pressure loss. Humidity is carried through the
!> input but not yet applied to properties (documented limitation); the hook is
!> present so a humid-air property model can be added later without changing the
!> calling convention.
module ambient
    use precision_kinds, only: dp
    use types, only: InputCase
    use utilities, only: assert_positive, assert_in_range
    implicit none
    private
    public :: inlet_state

contains

    !> Compute station-1 (compressor inlet) temperature and pressure.
    !>
    !> @param[in]  ic   operating-point inputs
    !> @param[out] T1_K compressor-inlet stagnation temperature [K]
    !> @param[out] P1_Pa compressor-inlet stagnation pressure [Pa]
    subroutine inlet_state(ic, T1_K, P1_Pa)
        type(InputCase), intent(in) :: ic
        real(dp), intent(out) :: T1_K
        real(dp), intent(out) :: P1_Pa

        call assert_positive(ic%ambient_T_K, "ambient_T_K")
        call assert_positive(ic%ambient_P_Pa, "ambient_P_Pa")
        call assert_in_range(ic%inlet_pressure_loss, 0.0_dp, 0.20_dp, "inlet_pressure_loss")

        ! Inlet does not change total temperature (adiabatic duct + filter).
        T1_K  = ic%ambient_T_K
        ! Pressure drop across filter/silencer/inlet duct.
        P1_Pa = ic%ambient_P_Pa * (1.0_dp - ic%inlet_pressure_loss)
    end subroutine inlet_state

end module ambient
