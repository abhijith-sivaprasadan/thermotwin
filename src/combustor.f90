!> @file combustor.f90
!> @brief Combustor model: fuel-air ratio from an energy balance, plus the
!>        combustor pressure loss that sets turbine-inlet pressure.
!>
!> Energy balance (per unit air mass) including the fuel mass addition:
!>
!>     mdot_a*cp_a*T2 + mdot_f*eta_b*LHV = (mdot_a+mdot_f)*cp_g*T3
!>
!> Dividing by mdot_a and writing f = mdot_f/mdot_a:
!>
!>     f = (cp_g*T3 - cp_a*T2) / (eta_b*LHV - cp_g*T3)
!>
!> This is the standard lean-combustion form and is more rigorous than the
!> often-seen q = cp*(T3-T2) shortcut because it conserves the fuel mass that
!> later flows through the turbine.
module combustor
    use precision_kinds, only: dp
    use fluid_properties, only: cp_air_at, cp_gas_at
    use utilities, only: assert_positive, assert_in_range, safe_divide
    implicit none
    private
    public :: solve_combustor

contains

    !> @param[in]  T_in_K        compressor-outlet temperature (station 2) [K]
    !> @param[in]  P_in_Pa       compressor-outlet pressure (station 2) [Pa]
    !> @param[in]  T_turbine_inlet_K firing temperature (station 3) [K]
    !> @param[in]  eta_combustor combustion efficiency [-]
    !> @param[in]  dP_fraction   fractional pressure loss across combustor [-]
    !> @param[in]  LHV_J_kg      fuel lower heating value [J/kg]
    !> @param[out] P_out_Pa      turbine-inlet pressure (station 3) [Pa]
    !> @param[out] fuel_air_ratio f = mdot_fuel/mdot_air [-]
    !> @param[out] q_in_per_air_J_kg sensible heat added per kg air [J/kg]
    subroutine solve_combustor(T_in_K, P_in_Pa, T_turbine_inlet_K, eta_combustor, &
                               dP_fraction, LHV_J_kg, P_out_Pa, fuel_air_ratio, &
                               q_in_per_air_J_kg)
        real(dp), intent(in)  :: T_in_K, P_in_Pa, T_turbine_inlet_K
        real(dp), intent(in)  :: eta_combustor, dP_fraction, LHV_J_kg
        real(dp), intent(out) :: P_out_Pa, fuel_air_ratio, q_in_per_air_J_kg

        real(dp) :: cp_a, cp_g, numer, denom

        call assert_positive(T_in_K, "combustor T_in_K")
        call assert_positive(P_in_Pa, "combustor P_in_Pa")
        call assert_positive(LHV_J_kg, "LHV_J_kg")
        call assert_in_range(eta_combustor, 0.50_dp, 1.0_dp, "eta_combustor")
        call assert_in_range(dP_fraction, 0.0_dp, 0.30_dp, "combustor_pressure_loss")

        if (T_turbine_inlet_K <= T_in_K) then
            write(*, '(A)') "FATAL: turbine inlet temperature must exceed compressor outlet."
            error stop 1
        end if

        ! Properties evaluated at representative temperatures.
        cp_a = cp_air_at(T_in_K)
        cp_g = cp_gas_at(T_turbine_inlet_K)

        numer = cp_g * T_turbine_inlet_K - cp_a * T_in_K
        denom = eta_combustor * LHV_J_kg - cp_g * T_turbine_inlet_K
        fuel_air_ratio = safe_divide(numer, denom)

        ! Sensible heat added per kg of air (useful diagnostic).
        q_in_per_air_J_kg = cp_g * T_turbine_inlet_K - cp_a * T_in_K

        ! Combustor pressure loss.
        P_out_Pa = P_in_Pa * (1.0_dp - dP_fraction)
    end subroutine solve_combustor

end module combustor
