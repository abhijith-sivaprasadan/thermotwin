! =============================================================================
! rl_dispatch.f90  --  Tabular Q-learning BESS dispatch agent
!
! State space:  5 SOC buckets × 4 price tiers × 4 demand tiers = 80 states
!   SOC    : [0-20), [20-40), [40-60), [60-80), [80-100] → buckets 1-5
!   Price  : [<40), [40-80), [80-120), [≥120] $/MWh      → tiers  1-4
!   Demand : [<35), [35-55), [55-75), [≥75] MW            → tiers  1-4
!
! Linear state index: s = (soc_b-1)*16 + (price_b-1)*4 + demand_b
!
! Actions:
!   1 = charge    (rl_storage_setpt = STORAGE_MIN_MW = -20 MW)
!   2 = hold      (rl_storage_setpt = 0 MW)
!   3 = discharge (rl_storage_setpt = STORAGE_MAX_MW = +20 MW)
!
! rl_mode = .false. → ε-greedy exploration (training)
! rl_mode = .true.  → greedy exploitation
! =============================================================================
module rl_dispatch
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: rl_step, rl_reset

    ! ── Q-learning hyper-parameters ──────────────────────────────────────────
    real(dp), parameter :: ALPHA_Q   = 0.1_dp
    real(dp), parameter :: GAMMA_Q   = 0.9_dp
    real(dp), parameter :: EPSILON   = 0.1_dp

    ! ── State-space bounds ───────────────────────────────────────────────────
    integer,  parameter :: N_STATES  = 80
    integer,  parameter :: N_ACTIONS = 3

contains

    ! -------------------------------------------------------------------------
    !> Zero the Q-table and reset episode accumulators.
    ! -------------------------------------------------------------------------
    subroutine rl_reset(st)
        type(GridState), intent(inout) :: st
        st%rl_q_table      = 0.0_dp
        st%rl_state_prev   = 1
        st%rl_action_prev  = 2
        st%rl_storage_setpt = 0.0_dp
        st%rl_last_reward  = 0.0_dp
        st%rl_cumreward    = 0.0_dp
    end subroutine rl_reset

    ! -------------------------------------------------------------------------
    !> Advance the RL agent by one engine tick.
    !>
    !> 1. Encode current observation into a discrete state index.
    !> 2. Compute reward from current economics.
    !> 3. Q-table update using (s_prev, a_prev, reward, s_now).
    !> 4. Select next action (greedy or ε-greedy).
    !> 5. Map action to storage setpoint and save state/action for next tick.
    ! -------------------------------------------------------------------------
    subroutine rl_step(st)
        type(GridState), intent(inout) :: st

        integer  :: s_now, a_best, a_rand
        real(dp) :: q_max_now, reward, rnd

        ! ── 1. Encode current state ───────────────────────────────────────────
        s_now = encode_state(st%battery_soc_pct, &
                             st%power_price_usd_mwh, &
                             st%demand_MW)

        ! ── 2. Reward signal ──────────────────────────────────────────────────
        reward = st%margin_usd_h - st%imbalance_penalty_usd_h
        st%rl_last_reward = reward
        st%rl_cumreward   = st%rl_cumreward + reward

        ! ── 3. Q-table update (Bellman backup) ───────────────────────────────
        q_max_now = maxval(st%rl_q_table(s_now, :))
        st%rl_q_table(st%rl_state_prev, st%rl_action_prev) = &
            st%rl_q_table(st%rl_state_prev, st%rl_action_prev) + &
            ALPHA_Q * (reward + GAMMA_Q * q_max_now - &
                       st%rl_q_table(st%rl_state_prev, st%rl_action_prev))

        ! ── 4. Action selection ───────────────────────────────────────────────
        if (st%rl_mode) then
            ! Exploitation: greedy argmax
            a_best = argmax3(st%rl_q_table(s_now, 1), &
                             st%rl_q_table(s_now, 2), &
                             st%rl_q_table(s_now, 3))
        else
            ! ε-greedy exploration
            call random_number(rnd)
            if (rnd < EPSILON) then
                ! Random action 1, 2, or 3
                call random_number(rnd)
                a_rand = int(rnd * real(N_ACTIONS, dp)) + 1
                if (a_rand > N_ACTIONS) a_rand = N_ACTIONS
                a_best = a_rand
            else
                a_best = argmax3(st%rl_q_table(s_now, 1), &
                                 st%rl_q_table(s_now, 2), &
                                 st%rl_q_table(s_now, 3))
            end if
        end if

        ! ── 5. Map action → setpoint and save for next tick ──────────────────
        select case (a_best)
        case (1)
            st%rl_storage_setpt = STORAGE_MIN_MW   ! charge
        case (3)
            st%rl_storage_setpt = STORAGE_MAX_MW   ! discharge
        case default
            st%rl_storage_setpt = 0.0_dp           ! hold
        end select

        st%rl_state_prev  = s_now
        st%rl_action_prev = a_best
    end subroutine rl_step

    ! =========================================================================
    ! Private helpers
    ! =========================================================================

    ! -------------------------------------------------------------------------
    !> Encode (soc_pct, price, demand) into a 1-based linear state index [1..80].
    ! -------------------------------------------------------------------------
    pure function encode_state(soc_pct, price, demand_mw) result(s)
        real(dp), intent(in) :: soc_pct, price, demand_mw
        integer :: s
        integer :: soc_b, price_b, demand_b

        ! SOC bucket (1-5)
        if (soc_pct < 20.0_dp) then
            soc_b = 1
        else if (soc_pct < 40.0_dp) then
            soc_b = 2
        else if (soc_pct < 60.0_dp) then
            soc_b = 3
        else if (soc_pct < 80.0_dp) then
            soc_b = 4
        else
            soc_b = 5
        end if

        ! Price tier (1-4)
        if (price < 40.0_dp) then
            price_b = 1
        else if (price < 80.0_dp) then
            price_b = 2
        else if (price < 120.0_dp) then
            price_b = 3
        else
            price_b = 4
        end if

        ! Demand tier (1-4)
        if (demand_mw < 35.0_dp) then
            demand_b = 1
        else if (demand_mw < 55.0_dp) then
            demand_b = 2
        else if (demand_mw < 75.0_dp) then
            demand_b = 3
        else
            demand_b = 4
        end if

        s = (soc_b - 1) * 16 + (price_b - 1) * 4 + demand_b
        ! Guard: clamp to valid range (should never be needed)
        if (s < 1)        s = 1
        if (s > N_STATES) s = N_STATES
    end function encode_state

    ! -------------------------------------------------------------------------
    !> Return the index (1, 2, or 3) of the largest of three values.
    !> Ties are broken in favour of lower action indices (conservative hold).
    ! -------------------------------------------------------------------------
    pure function argmax3(q1, q2, q3) result(idx)
        real(dp), intent(in) :: q1, q2, q3
        integer :: idx
        if (q1 >= q2 .and. q1 >= q3) then
            idx = 1
        else if (q2 >= q3) then
            idx = 2
        else
            idx = 3
        end if
    end function argmax3

end module rl_dispatch
