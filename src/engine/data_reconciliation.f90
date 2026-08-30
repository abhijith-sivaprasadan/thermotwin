!> [7.0-P5] Data reconciliation & gross-error detection (V&V).
!>
!> Single-constraint weighted least-squares reconciliation: given redundant noisy
!> measurements y subject to a conservation law a . x = 0 (e.g. gas + steam −
!> plant power = 0), find the minimal weighted correction that makes the balance
!> close exactly. The chi-square(1) global test on the raw imbalance flags a gross
!> error (a faulty sensor) when the residual is too large to be measurement noise.
!> This is the verification layer: it both *enforces* conservation and *detects*
!> when the data can't be trusted.
module data_reconciliation
    use precision_kinds, only: dp
    use engine_state,    only: GridState
    implicit none
    private
    public :: ReconResult, reconcile_single, reconcile_power_balance
    integer, parameter, public :: RECON_MAXV = 8

    type :: ReconResult
        integer  :: n = 0
        real(dp) :: y(RECON_MAXV)      = 0.0_dp   ! raw measurements
        real(dp) :: x(RECON_MAXV)      = 0.0_dp   ! reconciled values
        real(dp) :: adjust(RECON_MAXV) = 0.0_dp   ! corrections (x - y)
        real(dp) :: imbalance_raw = 0.0_dp        ! a . y
        real(dp) :: imbalance_rec = 0.0_dp        ! a . x  (~0)
        real(dp) :: test_stat     = 0.0_dp        ! chi-square(1) global test
        logical  :: gross_error   = .false.
    end type ReconResult

contains

    !> Minimise sum(((x-y)/sigma)^2) subject to a . x = 0 (Lagrange, closed form).
    subroutine reconcile_single(a, sigma, y, n, crit, r)
        integer,  intent(in) :: n
        real(dp), intent(in) :: a(n), sigma(n), y(n), crit
        type(ReconResult), intent(out) :: r
        real(dp) :: imb, s, lambda
        integer  :: i, m

        m   = min(n, RECON_MAXV)
        imb = 0.0_dp;  s = 0.0_dp
        do i = 1, m
            imb = imb + a(i) * y(i)
            s   = s   + a(i) * a(i) * sigma(i) * sigma(i)
        end do
        s      = max(s, 1.0e-30_dp)
        lambda = imb / s
        r%n = m
        do i = 1, m
            r%y(i)      = y(i)
            r%x(i)      = y(i) - sigma(i) * sigma(i) * a(i) * lambda
            r%adjust(i) = r%x(i) - y(i)
        end do
        r%imbalance_raw = imb
        r%imbalance_rec = sum(a(1:m) * r%x(1:m))
        r%test_stat     = imb * imb / s
        r%gross_error   = r%test_stat > crit
    end subroutine reconcile_single

    !> Reconcile the plant power balance  gas + steam - plant = 0  with redundant
    !> generation measurements.  crit = chi-square(1) at 99.9% (10.83).
    subroutine reconcile_power_balance(st, r)
        type(GridState),   intent(in)  :: st
        type(ReconResult), intent(out) :: r
        real(dp) :: a(3), sig(3), y(3)
        a   = [1.0_dp, 1.0_dp, -1.0_dp]
        y   = [st%gas_power_MW, st%steam_power_MW, st%plant_power_MW]
        sig = [0.3_dp, 0.3_dp, 0.4_dp]
        call reconcile_single(a, sig, y, 3, 10.83_dp, r)
    end subroutine reconcile_power_balance

end module data_reconciliation
