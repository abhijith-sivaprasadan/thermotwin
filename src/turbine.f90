!> @file turbine.f90
!> @brief Turbine expansion model (single equivalent stage).
!>
!> Expands the hot gas from turbine-inlet pressure (station 3) to the exhaust
!> pressure (station 4), which is the ambient pressure raised by the exhaust /
!> diffuser back-pressure loss. Uses gas-side properties and an isentropic
!> efficiency. As in the compressor, a short iteration self-consistently sets
!> the isentropic exponent when variable properties are active.
module turbine
    use precision_kinds, only: dp
    use fluid_properties, only: cp_gas_at, gamma_exponent, get_property_model, PROP_CONSTANT
    use utilities, only: assert_positive, assert_in_range
    implicit none
    private
    public :: solve_turbine

contains

    !> @param[in]  T_in_K   turbine-inlet temperature (station 3) [K]
    !> @param[in]  P_in_Pa  turbine-inlet pressure (station 3) [Pa]
    !> @param[in]  P_out_Pa turbine-outlet pressure (station 4) [Pa]
    !> @param[in]  eta_isentropic turbine isentropic efficiency [-]
    !> @param[out] T_out_K  exhaust temperature (station 4) [K]
    !> @param[out] w_specific_J_kg specific work delivered [J/kg]
    subroutine solve_turbine(T_in_K, P_in_Pa, P_out_Pa, eta_isentropic, &
                             T_out_K, w_specific_J_kg)
        real(dp), intent(in)  :: T_in_K, P_in_Pa, P_out_Pa, eta_isentropic
        real(dp), intent(out) :: T_out_K, w_specific_J_kg

        real(dp) :: ex, T_out_isentropic, T_mean, cp_mean, expansion_ratio
        integer  :: it
        integer, parameter :: MAX_IT = 20
        real(dp), parameter :: TOL = 1.0e-8_dp
        real(dp) :: T_prev

        call assert_positive(T_in_K, "turbine T_in_K")
        call assert_positive(P_in_Pa, "turbine P_in_Pa")
        call assert_positive(P_out_Pa, "turbine P_out_Pa")
        call assert_in_range(eta_isentropic, 0.30_dp, 1.0_dp, "eta_turbine")

        if (P_out_Pa >= P_in_Pa) then
            write(*, '(A)') "FATAL: turbine outlet pressure must be below inlet pressure."
            error stop 1
        end if

        expansion_ratio = P_out_Pa / P_in_Pa     ! < 1

        ex = gamma_exponent(T_in_K, 'gas')
        T_out_isentropic = T_in_K * expansion_ratio**ex
        T_out_K = T_in_K - eta_isentropic * (T_in_K - T_out_isentropic)

        if (get_property_model() /= PROP_CONSTANT) then
            do it = 1, MAX_IT
                T_prev = T_out_K
                T_mean = 0.5_dp * (T_in_K + T_out_K)
                ex = gamma_exponent(T_mean, 'gas')
                T_out_isentropic = T_in_K * expansion_ratio**ex
                T_out_K = T_in_K - eta_isentropic * (T_in_K - T_out_isentropic)
                if (abs(T_out_K - T_prev) < TOL) exit
            end do
        end if

        T_mean  = 0.5_dp * (T_in_K + T_out_K)
        cp_mean = cp_gas_at(T_mean)
        w_specific_J_kg = cp_mean * (T_in_K - T_out_K)
    end subroutine solve_turbine

end module turbine
