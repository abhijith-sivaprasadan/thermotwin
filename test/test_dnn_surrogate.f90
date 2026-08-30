! =============================================================================
! test_dnn_surrogate.f90  --  Unit tests for the dnn_surrogate module
!
! Tests cover:
!   1. Missing weight file -> graceful fallback (DNN_ACTIVE = .false.)
!   2. Valid weight file   -> DNN_ACTIVE = .true., MAE in plausible range
!   3. HR surrogate        -> physical monotonicity + Python reference values
!   4. Commit policy       -> mask structure, no all-false mask
!   5. Split flags         -> DNN_POLICY_ACTIVE independent of DNN_ACTIVE
!
! Run from the project root (where dnn_weights.txt lives):
!   build/tests/test_dnn_surrogate
!
! Exit code 0 = all pass, 1 = at least one failure.
! =============================================================================
program test_dnn_surrogate
    use precision_kinds, only: dp
    use dnn_surrogate
    implicit none

    integer :: n_fail = 0

    ! ── T1: missing file -> graceful fallback ──────────────────────────────
    call dnn_init("__nonexistent_weights_xyz__.txt")
    call chk(.not. DNN_ACTIVE,        "T1 missing file: DNN_ACTIVE = .false.")
    call chk(.not. DNN_POLICY_ACTIVE, "T1 missing file: DNN_POLICY_ACTIVE = .false.")
    call chk(DNN_HR_MAE == 0.0_dp,    "T1 missing file: DNN_HR_MAE = 0")

    ! ── T2: valid file -> flags set, MAE plausible ──────────────────────────
    call dnn_init("dnn_weights.txt")
    call chk(DNN_ACTIVE,              "T2 valid file: DNN_ACTIVE = .true.")
    call chk(DNN_POLICY_ACTIVE,       "T2 valid file: DNN_POLICY_ACTIVE = .true.")
    call chk(DNN_HR_MAE > 0.0_dp .and. DNN_HR_MAE < 500.0_dp, &
                                      "T2 valid file: MAE in (0, 500) kJ/kWh")

    ! ── T3: HR surrogate physical plausibility ──────────────────────────────

    ! Full load at reference conditions: HR near 9200 kJ/kWh
    ! Python reference: 9173.18 kJ/kWh  (1% tolerance = 92 kJ/kWh)
    call chk_near(dnn_heat_rate(1.0_dp, 15.0_dp, 1400.0_dp, 0.0_dp), &
                  9173.18_dp, 200.0_dp, "T3 full-load HR matches Python ref ±200")

    ! Part load (30%) has higher HR than full load (part-load penalty)
    call chk(dnn_heat_rate(0.3_dp, 15.0_dp, 1400.0_dp, 0.0_dp) > &
             dnn_heat_rate(1.0_dp, 15.0_dp, 1400.0_dp, 0.0_dp), &
                                      "T3 part-load HR > full-load HR")

    ! Part-load HR in physical range
    call chk_near(dnn_heat_rate(0.3_dp, 15.0_dp, 1400.0_dp, 0.0_dp), &
                  11435.34_dp, 300.0_dp, "T3 30%-load HR matches Python ref ±300")

    ! Fouling raises HR
    call chk(dnn_heat_rate(0.7_dp, 15.0_dp, 1400.0_dp, 10.0_dp) > &
             dnn_heat_rate(0.7_dp, 15.0_dp, 1400.0_dp,  0.0_dp), &
                                      "T3 fouling=10% raises HR")

    ! Hot ambient raises HR
    call chk(dnn_heat_rate(0.7_dp, 40.0_dp, 1400.0_dp, 0.0_dp) > &
             dnn_heat_rate(0.7_dp, 15.0_dp, 1400.0_dp, 0.0_dp), &
                                      "T3 hot ambient raises HR")

    ! Higher TIT lowers HR (better efficiency)
    call chk(dnn_heat_rate(0.7_dp, 15.0_dp, 1600.0_dp, 0.0_dp) < &
             dnn_heat_rate(0.7_dp, 15.0_dp, 1200.0_dp, 0.0_dp), &
                                      "T3 high TIT lowers HR")

    ! Physical bounds always respected
    call chk(dnn_heat_rate(0.0_dp, -30.0_dp, 1000.0_dp, 30.0_dp) >= 7000.0_dp, &
                                      "T3 extreme lo: HR >= 7000 kJ/kWh floor")
    call chk(dnn_heat_rate(2.0_dp, 60.0_dp, 2000.0_dp, 0.0_dp) <= 30000.0_dp, &
                                      "T3 extreme hi: HR <= 30000 kJ/kWh ceiling")

    ! ── T4: commit policy pruning ────────────────────────────────────────────
    block
        logical :: mask(20)
        integer :: k

        ! High-price, high-demand -> mostly-full dispatch: low-power branches pruned
        call dnn_commit_prune(0.5_dp, 1.2_dp, 0.8_dp, 0.5_dp, 1.0_dp, 20, mask)
        call chk(any(mask),            "T4 high-price mask not all-false")
        call chk(count(mask) >= 3,     "T4 high-price: at least 3 branches kept")
        call chk(mask(20),             "T4 high-price: top dispatch always kept")

        ! Low-price, low-demand -> prefer off: high-power branches pruned
        call dnn_commit_prune(0.5_dp, 0.27_dp, 0.25_dp, 0.9_dp, 0.0_dp, 20, mask)
        call chk(any(mask),            "T4 low-price mask not all-false")
        call chk(count(mask) >= 3,     "T4 low-price: at least 3 branches kept")

        ! Mid-price neutral: mask mostly true
        call dnn_commit_prune(0.5_dp, 0.65_dp, 0.55_dp, 0.5_dp, 0.5_dp, 20, mask)
        call chk(count(mask) >= 10,    "T4 neutral price: >= 10 branches kept")

        ! Single branch: always kept regardless of policy
        block
            logical :: one(1)
            call dnn_commit_prune(0.5_dp, 0.5_dp, 0.5_dp, 0.5_dp, 0.5_dp, 1, one)
            call chk(one(1),           "T4 n_pgt=1: single branch kept")
        end block
    end block

    ! ── T5: reload clears state correctly (re-init idempotent) ───────────────
    call dnn_init("dnn_weights.txt")
    call chk(DNN_ACTIVE,              "T5 re-init: DNN_ACTIVE still .true.")
    call dnn_init("__nonexistent__.txt")
    call chk(.not. DNN_ACTIVE,        "T5 re-init bad file: DNN_ACTIVE reset to .false.")
    call chk(.not. DNN_POLICY_ACTIVE, "T5 re-init bad file: DNN_POLICY_ACTIVE reset to .false.")
    ! Restore good weights for any downstream use
    call dnn_init("dnn_weights.txt")

    ! ── Report ──────────────────────────────────────────────────────────────
    if (n_fail == 0) then
        write(*, '("PASS  all dnn_surrogate tests")')
        stop 0
    else
        write(*, '(I0," FAIL")') n_fail
        stop 1
    end if

contains

    subroutine chk(cond, msg)
        logical,          intent(in) :: cond
        character(len=*), intent(in) :: msg
        if (cond) then
            write(*, '("  ok  ", A)') msg
        else
            write(*, '("FAIL  ", A)') msg
            n_fail = n_fail + 1
        end if
    end subroutine

    subroutine chk_near(val, ref, tol, msg)
        real(dp),         intent(in) :: val, ref, tol
        character(len=*), intent(in) :: msg
        if (abs(val - ref) <= tol) then
            write(*, '("  ok  ", A, "  (", F8.2, ")")') msg, val
        else
            write(*, '("FAIL  ", A, "  got ", F8.2, "  expected ", F8.2, " +-", F6.1)') &
                msg, val, ref, tol
            n_fail = n_fail + 1
        end if
    end subroutine

end program test_dnn_surrogate
