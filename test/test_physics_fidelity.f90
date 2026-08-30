!> @file test_physics_fidelity.f90
!> @brief Revamp 5.0 C3 checks for GT map and HRSG pinch reference envelopes.
program test_physics_fidelity
    use precision_kinds, only: dp
    use engine_core
    use physics_fidelity, only: reference_gt_heat_rate, reference_hrsg_pinch_K
    implicit none

    integer :: failures
    failures = 0

    block
        real(dp) :: hr100, hr70, hr40, hr_hot, hr_tit
        hr100 = reference_gt_heat_rate(1.00_dp, 15.0_dp, 1400.0_dp)
        hr70  = reference_gt_heat_rate(0.70_dp, 15.0_dp, 1400.0_dp)
        hr40  = reference_gt_heat_rate(0.40_dp, 15.0_dp, 1400.0_dp)
        hr_hot = reference_gt_heat_rate(1.00_dp, 35.0_dp, 1400.0_dp)
        hr_tit = reference_gt_heat_rate(1.00_dp, 15.0_dp, 1500.0_dp)

        call expect_true("GT ref: 70% HR exceeds full-load HR", hr70 > hr100, failures)
        call expect_true("GT ref: 40% HR exceeds 70% HR", hr40 > hr70, failures)
        call expect_true("GT ref: 40% HR at least 30% over full-load", hr40 > 1.30_dp * hr100, failures)
        call expect_true("GT ref: hot ambient raises heat rate", hr_hot > hr100, failures)
        call expect_true("GT ref: higher TIT lowers heat rate", hr_tit < hr100, failures)
    end block

    block
        real(dp) :: p100, p70, p40
        p100 = reference_hrsg_pinch_K(1.00_dp)
        p70  = reference_hrsg_pinch_K(0.70_dp)
        p40  = reference_hrsg_pinch_K(0.40_dp)

        call expect_true("HRSG ref: full-load pinch in 10-16 K class", &
            p100 >= 10.0_dp .and. p100 <= 16.0_dp, failures)
        call expect_true("HRSG ref: low-load margin exceeds full-load target", p40 > p100, failures)
        call expect_true("HRSG ref: curve is monotonic through 70%", p40 > p70 .and. p70 > p100, failures)
    end block

    block
        type(GridState) :: st
        call engine_init(st)
        call expect_true("engine: C3 reference layer ready", st%physics_fidelity_ready, failures)
        call expect_true("engine: C3 point count wired", st%physics_fidelity_n == FIDELITY_N, failures)
        call expect_true("engine: live GT ref positive", st%physics_gt_hr_ref_kJ_kWh > 9000.0_dp, failures)
    end block

    call finish("physics_fidelity", failures)

contains

    include "test_assert.inc"

end program test_physics_fidelity
