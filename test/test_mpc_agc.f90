!> @file test_mpc_agc.f90
!> @brief Unit tests for the Revamp 5.0 C2 MPC horizon preview.
program test_mpc_agc
    use precision_kinds, only: dp
    use engine_state
    use mpc_agc, only: mpc_step
    implicit none

    type(GridState) :: st
    integer :: failures
    failures = 0

    st%mpc_active = .true.
    st%demand_MW = 45.0_dp
    st%renewable_MW = 6.0_dp
    st%renewable_curtail_MW = 0.0_dp
    st%storage_MW = 1.0_dp
    st%steam_power_MW = 0.0_dp
    st%gas_capacity_MW = 60.0_dp
    st%gas_power_MW = 34.0_dp
    st%frequency_Hz = 49.92_dp

    call mpc_step(st)

    call expect_true("MPC horizon ready", st%mpc_horizon_ready, failures)
    call expect_true("MPC horizon count", st%mpc_horizon_n == MPC_HORIZON_N, failures)
    call expect_true("MPC setpoint within capacity", &
        st%mpc_setpt_MW >= 0.0_dp .and. st%mpc_setpt_MW <= st%gas_capacity_MW, failures)
    call expect_true("MPC cost beats or matches hold baseline", &
        st%mpc_cost_last <= st%mpc_cost_hold + 1.0e-9_dp, failures)
    call expect_true("MPC saving non-negative", st%mpc_cost_saving >= -1.0e-9_dp, failures)
    call expect_true("MPC time axis populated", &
        minval(st%mpc_pred_time_s) > 0.0_dp .and. &
        st%mpc_pred_time_s(MPC_HORIZON_N) > st%mpc_pred_time_s(1), failures)
    call expect_true("MPC frequency path bounded", &
        minval(st%mpc_pred_freq_Hz) >= 47.0_dp .and. &
        maxval(st%mpc_pred_freq_Hz) <= 53.0_dp, failures)
    call expect_true("MPC generation path bounded", &
        minval(st%mpc_pred_pgen_MW) >= 0.0_dp .and. &
        maxval(st%mpc_pred_pgen_MW) <= st%gas_capacity_MW + 1.0e-9_dp, failures)
    call expect_true("MPC setpoint path mirrors chosen setpoint", &
        maxval(abs(st%mpc_pred_setpt_MW - st%mpc_setpt_MW)) < 1.0e-9_dp, failures)
    call expect_true("MPC imbalance path finite", &
        maxval(abs(st%mpc_pred_imbalance_MW)) < 200.0_dp, failures)

    call finish("test_mpc_agc", failures)
contains
    include "test_assert.inc"
end program test_mpc_agc
