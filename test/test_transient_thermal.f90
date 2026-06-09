!> @file test_transient_thermal.f90
!> @brief Tests the lumped-capacitance transient model: steady-state limit,
!>        monotone heating, and Euler/RK4 agreement on a fine grid.
program test_transient_thermal
    use precision_kinds, only: dp
    use types, only: ComponentState
    use transient_thermal, only: simulate_transient, step_component, dTdt, &
                                 INTEG_EULER, INTEG_RK4
    implicit none
    integer :: failures
    failures = 0

    ! --- Steady-state limit: with no ambient loss, metal -> gas temperature. ---
    block
        type(ComponentState) :: c
        integer, parameter :: N = 2001
        real(dp) :: t(N), Tg(N), Tm(N)
        integer :: i
        c%name = "node"
        c%temperature_K = 300.0_dp
        c%thermal_mass_J_K = 1.0e5_dp
        c%hA_W_K = 5.0e3_dp
        c%UA_loss_W_K = 0.0_dp        ! no losses -> asymptote exactly at T_gas
        do i = 1, N
            t(i) = real(i-1, dp) * 5.0_dp     ! up to 1e4 s, many time constants
            Tg(i) = 900.0_dp
        end do
        call simulate_transient(c, t, Tg, 300.0_dp, INTEG_RK4, 5, Tm)
        call expect_near("metal -> gas temp at steady state", Tm(N), 900.0_dp, 1.0_dp, failures)
        call expect_true("heating is monotone", Tm(N) > Tm(1), failures)
        call expect_true("never overshoots gas temp", maxval(Tm) <= 900.0_dp + 1.0e-6_dp, failures)
    end block

    ! --- With ambient losses, steady state sits below the gas temperature. ---
    block
        type(ComponentState) :: c
        integer, parameter :: N = 4001
        real(dp) :: t(N), Tg(N), Tm(N), T_inf
        integer :: i
        c%temperature_K = 300.0_dp
        c%thermal_mass_J_K = 1.0e5_dp
        c%hA_W_K = 5.0e3_dp
        c%UA_loss_W_K = 1.0e3_dp
        do i = 1, N
            t(i) = real(i-1, dp) * 5.0_dp
            Tg(i) = 900.0_dp
        end do
        call simulate_transient(c, t, Tg, 300.0_dp, INTEG_RK4, 5, Tm)
        ! Analytic steady state: hA*(Tg-T) = UA*(T-Tamb)
        T_inf = (c%hA_W_K*900.0_dp + c%UA_loss_W_K*300.0_dp) / (c%hA_W_K + c%UA_loss_W_K)
        call expect_near("loss steady-state matches analytic", Tm(N), T_inf, 1.0_dp, failures)
        call expect_true("loss steady state below gas temp", T_inf < 900.0_dp, failures)
    end block

    ! --- Euler and RK4 agree closely on a sufficiently fine time grid. ---
    block
        type(ComponentState) :: ce, cr
        integer, parameter :: N = 1001
        real(dp) :: t(N), Tg(N), Tme(N), Tmr(N)
        integer :: i
        ce%temperature_K = 300.0_dp; ce%thermal_mass_J_K = 2.0e5_dp
        ce%hA_W_K = 4.0e3_dp; ce%UA_loss_W_K = 2.0e2_dp
        cr = ce
        do i = 1, N
            t(i) = real(i-1, dp) * 2.0_dp
            Tg(i) = 800.0_dp
        end do
        call simulate_transient(ce, t, Tg, 300.0_dp, INTEG_EULER, 20, Tme)
        call simulate_transient(cr, t, Tg, 300.0_dp, INTEG_RK4,   20, Tmr)
        call expect_near("Euler vs RK4 agree (fine grid)", Tme(N), Tmr(N), 0.5_dp, failures)
    end block

    call finish("test_transient_thermal", failures)
contains
    include "test_assert.inc"
end program test_transient_thermal
