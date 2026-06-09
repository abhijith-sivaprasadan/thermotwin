!> @file shaft_generator.f90
!> @brief Shaft power balance, mechanical losses, generator and auxiliary loads.
!>
!> Converts component aerodynamic powers into net electrical output:
!>
!>   P_shaft   = (P_turbine - P_compressor) * eta_mechanical
!>   P_gross   = P_shaft * eta_generator
!>   P_net     = P_gross * (1 - aux_load_fraction)
!>
!> Powers are in watts here; conversion to MW happens in the cycle solver.
module shaft_generator
    use precision_kinds, only: dp
    use utilities, only: assert_in_range
    implicit none
    private
    public :: solve_shaft_generator

contains

    !> @param[in]  power_turbine_W      gross turbine power [W]
    !> @param[in]  power_compressor_W   compressor power absorbed [W]
    !> @param[in]  eta_mechanical       bearing/windage mechanical efficiency [-]
    !> @param[in]  eta_generator        generator electrical efficiency [-]
    !> @param[in]  aux_load_fraction    fraction of gross power for auxiliaries [-]
    !> @param[out] gross_power_W        generator terminal power [W]
    !> @param[out] net_power_W          power exported after auxiliaries [W]
    subroutine solve_shaft_generator(power_turbine_W, power_compressor_W, &
                                     eta_mechanical, eta_generator, aux_load_fraction, &
                                     gross_power_W, net_power_W)
        real(dp), intent(in)  :: power_turbine_W, power_compressor_W
        real(dp), intent(in)  :: eta_mechanical, eta_generator, aux_load_fraction
        real(dp), intent(out) :: gross_power_W, net_power_W

        real(dp) :: shaft_power_W

        call assert_in_range(eta_mechanical, 0.80_dp, 1.0_dp, "eta_mechanical")
        call assert_in_range(eta_generator, 0.80_dp, 1.0_dp, "eta_generator")
        call assert_in_range(aux_load_fraction, 0.0_dp, 0.20_dp, "auxiliary_load_fraction")

        shaft_power_W = (power_turbine_W - power_compressor_W) * eta_mechanical
        gross_power_W = shaft_power_W * eta_generator
        net_power_W   = gross_power_W * (1.0_dp - aux_load_fraction)
    end subroutine solve_shaft_generator

end module shaft_generator
