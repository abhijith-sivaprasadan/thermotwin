!> @file transient_thermal.f90
!> @brief Lumped-capacitance transient heating of a hot-gas-path component.
!>
!> Governing ODE for a single metal node:
!>
!>   m*cp dT/dt = hA*(T_gas - T_metal) - UA_loss*(T_metal - T_amb)
!>
!> The gas temperature that drives the node is taken from the cycle solver's
!> exhaust/firing temperatures, so a load schedule (e.g. a TIT ramp) couples
!> directly into metal-temperature response. This is the link to the thermal
!> testing / component-heating side of the project.
!>
!> Two integrators are provided so the documentation can show the accuracy
!> trade-off: explicit Euler (cheap, conditionally stable) and classical RK4.
module transient_thermal
    use precision_kinds, only: dp
    use types, only: ComponentState
    use utilities, only: assert_positive
    implicit none
    private
    public :: INTEG_EULER, INTEG_RK4
    public :: dTdt, step_component, simulate_transient

    integer, parameter :: INTEG_EULER = 0
    integer, parameter :: INTEG_RK4   = 1

contains

    !> Right-hand side dT_metal/dt for a given metal temperature and drivers.
    pure function dTdt(T_metal, T_gas, T_amb, comp) result(rate)
        real(dp), intent(in) :: T_metal, T_gas, T_amb
        type(ComponentState), intent(in) :: comp
        real(dp) :: rate
        rate = (comp%hA_W_K * (T_gas - T_metal) &
              - comp%UA_loss_W_K * (T_metal - T_amb)) / comp%thermal_mass_J_K
    end function dTdt

    !> Advance the metal temperature by one time step dt [s].
    subroutine step_component(comp, T_gas, T_amb, dt, method)
        type(ComponentState), intent(inout) :: comp
        real(dp), intent(in) :: T_gas, T_amb, dt
        integer, intent(in)  :: method
        real(dp) :: k1, k2, k3, k4, T

        T = comp%temperature_K
        select case (method)
        case (INTEG_RK4)
            k1 = dTdt(T,                 T_gas, T_amb, comp)
            k2 = dTdt(T + 0.5_dp*dt*k1,  T_gas, T_amb, comp)
            k3 = dTdt(T + 0.5_dp*dt*k2,  T_gas, T_amb, comp)
            k4 = dTdt(T + dt*k3,         T_gas, T_amb, comp)
            comp%temperature_K = T + dt/6.0_dp * (k1 + 2.0_dp*k2 + 2.0_dp*k3 + k4)
        case default ! INTEG_EULER
            comp%temperature_K = T + dt * dTdt(T, T_gas, T_amb, comp)
        end select
    end subroutine step_component

    !> Simulate a full transient given a time-varying gas-temperature schedule.
    !>
    !> @param[inout] comp        component node (its temperature is the IC)
    !> @param[in]    time_s      array of sample times [s] (size N, increasing)
    !> @param[in]    T_gas_K     driving gas temperature at each time [K] (size N)
    !> @param[in]    T_amb_K     ambient temperature [K]
    !> @param[in]    method      INTEG_EULER or INTEG_RK4
    !> @param[in]    n_substeps  integration sub-steps between samples (>=1)
    !> @param[out]   T_metal_K   metal temperature history [K] (size N)
    subroutine simulate_transient(comp, time_s, T_gas_K, T_amb_K, method, &
                                  n_substeps, T_metal_K)
        type(ComponentState), intent(inout) :: comp
        real(dp), intent(in)  :: time_s(:), T_gas_K(:), T_amb_K
        integer, intent(in)   :: method, n_substeps
        real(dp), intent(out) :: T_metal_K(:)

        integer :: i, s, n
        real(dp) :: dt_sample, dt_sub, T_gas_local

        n = size(time_s)
        call assert_positive(comp%thermal_mass_J_K, "thermal_mass_J_K")

        T_metal_K(1) = comp%temperature_K
        do i = 1, n - 1
            dt_sample = time_s(i + 1) - time_s(i)
            dt_sub = dt_sample / real(max(1, n_substeps), dp)
            ! Drive with the segment's mean gas temperature (piecewise-linear).
            do s = 1, max(1, n_substeps)
                T_gas_local = 0.5_dp * (T_gas_K(i) + T_gas_K(i + 1))
                call step_component(comp, T_gas_local, T_amb_K, dt_sub, method)
            end do
            T_metal_K(i + 1) = comp%temperature_K
        end do
    end subroutine simulate_transient

end module transient_thermal
