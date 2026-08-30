!> @file test_optimizers.f90
!> @brief Unit tests for the day-ahead, GT P2, fleet UC, and startup display data.
program test_optimizers
    use precision_kinds, only: dp
    use engine_state
    use engine_core, only: engine_init, engine_step
    use minlp_dayahead, only: solve_dayahead
    use gt_optimizer, only: solve_gt_optimizer
    use fleet_uc, only: solve_fleet_uc
    implicit none

    integer :: failures

    failures = 0

    ! --- Startup should pre-populate every screen-backed optimizer dataset. ---
    block
        type(GridState) :: st

        call engine_init(st)
        call expect_true("engine_init: day-ahead solution available", st%da_solved, failures)
        call expect_true("engine_init: GT optimizer solution available", st%gt_opt_solved, failures)
        call expect_true("engine_init: fleet UC solution available", st%fleet_uc_solved, failures)
        call expect_true("engine_init: day-ahead demand populated", minval(st%da_demand) > 0.0_dp, failures)
        call expect_true("engine_init: GT scan populated", maxval(st%gt_opt_pwr) > 1.0_dp, failures)
        call expect_true("engine_init: fleet variable costs populated", &
            minval(st%fleet_unit_cost_usd_MWh) > 1.0_dp, failures)
        call expect_true("engine_init: fleet UC total cost visible", &
            st%fleet_uc_total_cost_h > 1.0_dp, failures)
        call expect_true("engine_init: fleet UC LMP visible", st%fleet_lmp_usd_MWh > 1.0_dp, failures)

        call engine_step(st, 0.25_dp)
        call expect_true("engine_step: optimizer data remains visible", &
            st%da_solved .and. st%gt_opt_solved .and. st%fleet_uc_solved, failures)
    end block

    ! --- OU disturbance should not integrate the same noise every tick. ---
    block
        type(GridState) :: st
        real(dp) :: base_demand, base_renewable
        integer :: i

        call engine_init(st)
        st%auto_balance = .false.
        st%market_load_replay_enabled = .false.
        st%market_weather_enabled = .false.
        st%ou_active = .true.
        st%ou_sigma_demand = 2.0_dp
        st%ou_sigma_wind = 3.0_dp
        st%ou_tau_demand = 120.0_dp
        st%ou_tau_wind = 300.0_dp
        st%ou_demand_noise = 0.0_dp
        st%ou_wind_noise = 0.0_dp

        base_demand = st%demand_MW
        base_renewable = st%renewable_MW
        do i = 1, 40
            call engine_step(st, 0.25_dp)
        end do

        call expect_near("OU: demand remains base plus current disturbance", &
            st%demand_MW - st%ou_demand_noise, base_demand, 1.0e-6_dp, failures)
        call expect_near("OU: renewable remains base plus current disturbance", &
            st%renewable_MW - st%ou_wind_noise, base_renewable, 1.0e-6_dp, failures)

        st%ou_active = .false.
        call engine_step(st, 0.25_dp)
        call expect_near("OU off: demand returns to operator setpoint", &
            st%demand_MW, base_demand, 1.0e-6_dp, failures)
        call expect_near("OU off: renewable returns to operator setpoint", &
            st%renewable_MW, base_renewable, 1.0e-6_dp, failures)
        call expect_near("OU off: demand noise clears", &
            st%ou_demand_noise, 0.0_dp, 1.0e-12_dp, failures)
        call expect_near("OU off: renewable noise clears", &
            st%ou_wind_noise, 0.0_dp, 1.0e-12_dp, failures)
    end block

    ! --- Day-ahead solver: power balance, BESS sign convention, and limits. ---
    block
        type(GridState) :: st
        integer :: t

        call engine_init(st)
        call solve_dayahead(st)
        call expect_true("day-ahead: solved flag", st%da_solved, failures)
        call expect_true("day-ahead: price fan lower bound", &
            minval(st%da_price - st%da_price_lo) >= -1.0e-9_dp, failures)
        call expect_true("day-ahead: price fan upper bound", &
            minval(st%da_price_hi - st%da_price) >= -1.0e-9_dp, failures)
        call expect_true("day-ahead: SoC respects floor", &
            minval(st%da_soc) >= BATTERY_CAPACITY_MWH * 0.05_dp - 1.0e-6_dp, failures)
        call expect_true("day-ahead: SoC respects ceiling", &
            maxval(st%da_soc) <= BATTERY_CAPACITY_MWH * 0.95_dp + 1.0e-6_dp, failures)

        do t = 1, DA_H
            call expect_near("day-ahead: GT+BESS equals demand", &
                st%da_p_gt(t) + st%da_p_bess(t), st%da_demand(t), 1.0e-7_dp, failures)
            call expect_true("day-ahead: BESS dispatch within inverter limit", &
                abs(st%da_p_bess(t)) <= STORAGE_MAX_MW + 1.0e-7_dp, failures)
            call expect_true("day-ahead: commitment is binary", &
                st%da_commit(t) == 0 .or. st%da_commit(t) == 1, failures)
            if (st%da_commit(t) == 0) then
                call expect_near("day-ahead: GT is zero when off", st%da_p_gt(t), 0.0_dp, 1.0e-9_dp, failures)
            end if
        end do
    end block

    ! --- P2 GT optimizer: best point agrees with the scan and economics. ---
    block
        type(GridState) :: st

        call engine_init(st)
        call solve_gt_optimizer(st)
        call expect_true("GT optimizer: solved flag", st%gt_opt_solved, failures)
        call expect_true("GT optimizer: best index in range", &
            st%gt_opt_best_idx >= 1 .and. st%gt_opt_best_idx <= GT_OPT_N, failures)
        call expect_true("GT optimizer: power scan positive", minval(st%gt_opt_pwr) > 0.0_dp, failures)
        call expect_true("GT optimizer: heat-rate scan finite", &
            minval(st%gt_opt_hr) > 1000.0_dp .and. maxval(st%gt_opt_hr) < 50000.0_dp, failures)
        call expect_near("GT optimizer: best margin is max scan margin", &
            st%gt_opt_best_margin, maxval(st%gt_opt_margin), 1.0e-6_dp, failures)
        call expect_near("GT optimizer: saving is best minus current", &
            st%gt_opt_saving_h, st%gt_opt_best_margin - st%gt_opt_curr_margin, 1.0e-6_dp, failures)
    end block

    ! --- Fleet UC: offline units stay offline and unserved load is explicit. ---
    block
        type(GridState) :: st
        real(dp) :: total_dispatch, expected_cost

        st%demand_MW = 80.0_dp
        st%renewable_MW = 0.0_dp
        st%renewable_curtail_MW = 0.0_dp
        st%storage_MW = 0.0_dp
        st%fleet_unit_online = [.true., .false., .true.]
        st%fleet_unit_capacity_MW = [30.0_dp, 15.0_dp, 45.0_dp]
        st%fleet_unit_cost_usd_MWh = [60.0_dp, 20.0_dp, 40.0_dp]

        call solve_fleet_uc(st)
        total_dispatch = sum(st%fleet_uc_p)
        expected_cost = 45.0_dp * 40.0_dp + 30.0_dp * 60.0_dp

        call expect_true("fleet UC: solved flag", st%fleet_uc_solved, failures)
        call expect_true("fleet UC: offline unit not committed", st%fleet_uc_commit(FLEET_GT2) == 0, failures)
        call expect_true("fleet UC: cheapest online unit committed", st%fleet_uc_commit(FLEET_CC1) == 1, failures)
        call expect_true("fleet UC: marginal unit is last dispatched online unit", &
            st%fleet_marginal_unit == FLEET_GT1, failures)
        call expect_near("fleet UC: dispatch limited to online capacity", total_dispatch, 75.0_dp, 1.0e-9_dp, failures)
        call expect_near("fleet UC: unserved residual is visible", &
            st%fleet_unserved_dispatch_MW, 5.0_dp, 1.0e-9_dp, failures)
        call expect_near("fleet UC: variable cost total", &
            st%fleet_uc_total_cost_h, expected_cost, 1.0e-9_dp, failures)
    end block

    call finish("optimizers", failures)

contains

    include "test_assert.inc"

end program test_optimizers
