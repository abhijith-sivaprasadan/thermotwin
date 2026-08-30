!> @file test_sensor_model.f90
!> @brief Tests the measurement-chain model: deterministic bias/drift, and that
!>        a large noise ensemble recovers the intended mean and sigma.
program test_sensor_model
    use precision_kinds, only: dp
    use types, only: SensorSpec
    use sensor_model, only: make_sensor, apply_sensor
    use utilities, only: seed_rng, mean, stddev
    implicit none
    integer :: failures
    failures = 0

    ! --- Pure bias, no noise: measured = true + bias, exactly. ---
    block
        type(SensorSpec) :: s
        real(dp) :: m
        s = make_sensor("T_exhaust", bias=3.0_dp, noise_sigma=0.0_dp, drift_rate=0.0_dp)
        m = apply_sensor(800.0_dp, s, 0.0_dp)
        call expect_near("bias applied exactly", m, 803.0_dp, 1.0e-12_dp, failures)
    end block

    ! --- Drift: measured grows linearly with elapsed hours. ---
    block
        type(SensorSpec) :: s
        real(dp) :: m
        s = make_sensor("fuel_flow", bias=0.0_dp, noise_sigma=0.0_dp, drift_rate=0.5_dp)
        m = apply_sensor(100.0_dp, s, 10.0_dp)
        call expect_near("drift over 10 h", m, 105.0_dp, 1.0e-12_dp, failures)
    end block

    ! --- Noise ensemble recovers mean and sigma. ---
    block
        type(SensorSpec) :: s
        integer, parameter :: N = 50000
        real(dp) :: samp(N)
        integer :: i
        call seed_rng(12345)
        s = make_sensor("net_power", bias=0.0_dp, noise_sigma=2.0_dp, drift_rate=0.0_dp)
        do i = 1, N
            samp(i) = apply_sensor(50.0_dp, s, 0.0_dp)
        end do
        call expect_near("noise ensemble mean ~ true", mean(samp), 50.0_dp, 0.1_dp, failures)
        call expect_near("noise ensemble sigma ~ spec", stddev(samp), 2.0_dp, 0.1_dp, failures)
    end block

    ! Re-seeding reproduces a sequence within one compiler/runtime.
    ! Cross-compiler bitwise equivalence is not promised by RANDOM_NUMBER.
    block
        type(SensorSpec) :: s
        real(dp) :: first(17), repeated(17)
        integer :: i
        s = make_sensor("reseed", bias=0.0_dp, noise_sigma=2.0_dp, drift_rate=0.0_dp)
        call seed_rng(2026)
        do i = 1, size(first)
            first(i) = apply_sensor(50.0_dp, s, 0.0_dp)
        end do
        call seed_rng(2026)
        do i = 1, size(repeated)
            repeated(i) = apply_sensor(50.0_dp, s, 0.0_dp)
        end do
        call expect_true("seed reproduces noise sequence", all(first == repeated), failures)
    end block

    call finish("test_sensor_model", failures)
contains
    include "test_assert.inc"
end program test_sensor_model
