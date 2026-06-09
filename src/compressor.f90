!> @file compressor.f90
!> @brief Axial-compressor thermodynamic model (single equivalent stage).
!>
!> Standard air-standard relations with an isentropic efficiency. With the
!> CONSTANT property model the result is analytic and matches the hand
!> calculation in docs/verification.md. With the VARIABLE property model the
!> isentropic exponent is evaluated at a representative mean temperature, so a
!> short fixed-point iteration is used to be self-consistent.
module compressor
    use precision_kinds, only: dp
    use fluid_properties, only: cp_air_at, gamma_exponent, get_property_model, PROP_CONSTANT
    use utilities, only: assert_positive, assert_in_range
    implicit none
    private
    public :: solve_compressor

contains

    !> Solve compressor outlet state and specific work.
    !>
    !> @param[in]  T_in_K        inlet temperature [K]
    !> @param[in]  P_in_Pa       inlet pressure [Pa]
    !> @param[in]  pressure_ratio total-to-total pressure ratio [-]
    !> @param[in]  eta_isentropic isentropic efficiency [-]
    !> @param[out] T_out_K       outlet temperature [K]
    !> @param[out] P_out_Pa      outlet pressure [Pa]
    !> @param[out] w_specific_J_kg specific work absorbed [J/kg]
    subroutine solve_compressor(T_in_K, P_in_Pa, pressure_ratio, eta_isentropic, &
                                T_out_K, P_out_Pa, w_specific_J_kg)
        real(dp), intent(in)  :: T_in_K, P_in_Pa, pressure_ratio, eta_isentropic
        real(dp), intent(out) :: T_out_K, P_out_Pa, w_specific_J_kg

        real(dp) :: ex, T_out_isentropic, T_mean, cp_mean
        integer  :: it
        integer, parameter :: MAX_IT = 20
        real(dp), parameter :: TOL = 1.0e-8_dp
        real(dp) :: T_prev

        call assert_positive(T_in_K, "compressor T_in_K")
        call assert_positive(P_in_Pa, "compressor P_in_Pa")
        call assert_in_range(pressure_ratio, 1.0_dp, 60.0_dp, "pressure_ratio")
        call assert_in_range(eta_isentropic, 0.30_dp, 1.0_dp, "eta_compressor")

        P_out_Pa = P_in_Pa * pressure_ratio

        ! First estimate using inlet-temperature exponent.
        ex = gamma_exponent(T_in_K, 'air')
        T_out_isentropic = T_in_K * pressure_ratio**ex
        T_out_K = T_in_K + (T_out_isentropic - T_in_K) / eta_isentropic

        ! With variable properties, iterate so the exponent reflects the mean
        ! temperature of the process (constant-property model converges in 1 pass).
        if (get_property_model() /= PROP_CONSTANT) then
            do it = 1, MAX_IT
                T_prev = T_out_K
                T_mean = 0.5_dp * (T_in_K + T_out_K)
                ex = gamma_exponent(T_mean, 'air')
                T_out_isentropic = T_in_K * pressure_ratio**ex
                T_out_K = T_in_K + (T_out_isentropic - T_in_K) / eta_isentropic
                if (abs(T_out_K - T_prev) < TOL) exit
            end do
        end if

        T_mean  = 0.5_dp * (T_in_K + T_out_K)
        cp_mean = cp_air_at(T_mean)
        w_specific_J_kg = cp_mean * (T_out_K - T_in_K)
    end subroutine solve_compressor

end module compressor
