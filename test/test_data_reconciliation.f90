!> @file test_data_reconciliation.f90
!> @brief Revamp 7.0 P5 — data reconciliation & gross-error detection.
program test_data_reconciliation
    use precision_kinds, only: dp
    use engine_core
    use data_reconciliation, only: ReconResult, reconcile_single, reconcile_power_balance
    implicit none

    integer :: failures
    failures = 0

    block
        type(ReconResult) :: r
        real(dp) :: a(3), sig(3), y(3)
        a = [1.0_dp, 1.0_dp, -1.0_dp]
        sig = [1.0_dp, 1.0_dp, 1.0_dp]

        ! Small imbalance (measurement noise) -> reconcile, no gross error
        y = [10.0_dp, 5.0_dp, 16.0_dp]
        call reconcile_single(a, sig, y, 3, 10.83_dp, r)
        call expect_true("recon: reconciled balance closes exactly", abs(r%imbalance_rec) < 1.0e-9_dp, failures)
        call expect_true("recon: reconciliation does not worsen imbalance", &
            abs(r%imbalance_rec) <= abs(r%imbalance_raw), failures)
        call expect_true("recon: small residual -> no gross error", .not. r%gross_error, failures)

        ! Large imbalance (faulty sensor) -> gross error flagged
        y = [10.0_dp, 5.0_dp, 30.0_dp]
        call reconcile_single(a, sig, y, 3, 10.83_dp, r)
        call expect_true("recon: gross error detected", r%gross_error, failures)
        call expect_true("recon: still closes after reconcile", abs(r%imbalance_rec) < 1.0e-9_dp, failures)
    end block

    block
        type(GridState)   :: st
        type(ReconResult) :: r
        call engine_init(st)
        st%gas_power_MW   = 18.0_dp
        st%steam_power_MW = 15.0_dp
        st%plant_power_MW = 33.0_dp
        call reconcile_power_balance(st, r)
        call expect_true("recon: consistent plant -> tiny adjustments", &
            maxval(abs(r%adjust(1:3))) < 0.1_dp, failures)
        call expect_true("recon: consistent plant -> no gross error", .not. r%gross_error, failures)
    end block

    call finish("data_reconciliation", failures)

contains

    include "test_assert.inc"

end program test_data_reconciliation
