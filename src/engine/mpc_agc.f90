!> @file mpc_agc.f90
!> @brief Model Predictive Control for secondary frequency regulation (AGC).
!>
!> Implements a 5-step (1 minute per step, 5-minute horizon) receding-horizon
!> optimiser that chooses the GT active-power setpoint to minimise a quadratic
!> cost penalising frequency deviation and control effort.  A linearised first-
!> order plant model (swing equation + actuator lag tau = 30 s) is used in place
!> of the full DNN surrogate so the solve remains real-time safe.
!>
!> The public entry point mpc_step() is called once per simulation tick when
!> st%mpc_active is .true.  engine_core applies st%mpc_setpt_MW downstream.
!> The F2 diagnostics screen compares the MPC cost trajectory against the
!> PI-style AGC steady-state error for operator insight.
!>
!> Algorithm
!> ---------
!>   Candidate set : 11 uniformly-spaced setpoint offsets in [-20, +20] MW
!>   For each candidate:
!>     Simulate HORIZON steps of the linearised plant (Euler integration)
!>     Accumulate J = sum_k [ Q*(f_k - f_nom)^2 + R*delta_sp^2 ]
!>   Select the candidate with minimum J.
!>
!> Tuneable parameters are declared as named constants for easy adjustment.
module mpc_agc
    use engine_state, only: GridState, MPC_HORIZON_N, effective_renewable_MW, clamp_real
    use precision_kinds, only: dp
    implicit none
    private

    public :: mpc_step

    ! ── Horizon & time parameters ────────────────────────────────────────────
    integer,  parameter :: HORIZON   = MPC_HORIZON_N ! prediction steps
    real(dp), parameter :: DT_STEP   = 60.0_dp    ! s per prediction step

    ! ── Physics constants ────────────────────────────────────────────────────
    real(dp), parameter :: FREQ_NOM   = 50.0_dp   ! Hz  (ENTSO-E nominal)
    real(dp), parameter :: TAU_ACT    = 30.0_dp   ! s   first-order GT actuator lag
    real(dp), parameter :: TAU_FREQ   = 90.0_dp   ! s   aggregate frequency response lag
    real(dp), parameter :: MW_PER_HZ_MIN = 12.0_dp ! minimum grid stiffness for sandbox island
    real(dp), parameter :: FREQ_LO    = 47.0_dp   ! Hz  simulation clamp lower bound
    real(dp), parameter :: FREQ_HI    = 53.0_dp   ! Hz  simulation clamp upper bound

    ! ── Cost weights ─────────────────────────────────────────────────────────
    real(dp), parameter :: Q_FREQ   = 250.0_dp    ! frequency deviation weight
    real(dp), parameter :: R_DELTA  = 0.04_dp     ! control-effort weight
    real(dp), parameter :: R_RAMP   = 0.015_dp    ! predicted actuator movement weight

    ! ── Candidate sweep ──────────────────────────────────────────────────────
    integer,  parameter :: N_TRIES   = 11         ! number of candidate offsets
    real(dp), parameter :: DELTA_LO  = -20.0_dp   ! MW  sweep lower bound
    real(dp), parameter :: DELTA_HI  =  20.0_dp   ! MW  sweep upper bound

contains

    !> Advance the MPC optimiser by one call.
    !>
    !> @param[inout] st  Full simulation state.  Reads the current frequency,
    !>                   GT dispatch, capacity, demand and imbalance.  Writes
    !>                   st%mpc_setpt_MW and st%mpc_cost_last.
    subroutine mpc_step(st)
        type(GridState), intent(inout) :: st

        ! Local optimisation workspace
        real(dp) :: delta_sp       ! candidate setpoint offset [MW]
        real(dp) :: candidate_sp   ! candidate absolute setpoint [MW]
        real(dp) :: best_sp        ! setpoint with lowest cost so far [MW]
        real(dp) :: best_cost      ! lowest cost found [–]
        real(dp) :: cost           ! accumulated cost for current candidate [–]
        real(dp) :: freq_path(HORIZON), pgen_path(HORIZON), imbal_path(HORIZON)
        real(dp) :: best_freq(HORIZON), best_pgen(HORIZON), best_imbal(HORIZON)
        real(dp) :: hold_freq(HORIZON), hold_pgen(HORIZON), hold_imbal(HORIZON)
        integer  :: i, k           ! loop indices

        ! Guard: do nothing when MPC is disabled
        if (.not. st%mpc_active) return

        ! Initialise best-cost tracker
        best_cost = huge(1.0_dp)
        best_sp   = st%gas_power_MW

        ! ── Candidate sweep ─────────────────────────────────────────────────
        do i = 1, N_TRIES
            ! Uniformly-spaced offset: -20, -16, -12, ..., +20 MW
            delta_sp     = DELTA_LO + real(i - 1, dp) * &
                           (DELTA_HI - DELTA_LO) / real(N_TRIES - 1, dp)
            candidate_sp = min(max(st%gas_power_MW + delta_sp, 0.0_dp), &
                               st%gas_capacity_MW)

            call simulate_candidate(st, candidate_sp, delta_sp, cost, freq_path, pgen_path, imbal_path)

            if (cost < best_cost) then
                best_cost = cost
                best_sp   = candidate_sp
                best_freq  = freq_path
                best_pgen  = pgen_path
                best_imbal = imbal_path
            end if
        end do
        ! ── End candidate sweep ──────────────────────────────────────────────

        call simulate_candidate(st, st%gas_power_MW, 0.0_dp, st%mpc_cost_hold, &
                                hold_freq, hold_pgen, hold_imbal)

        ! Write outputs — engine_core applies mpc_setpt_MW to the GT actuator
        st%mpc_setpt_MW  = best_sp
        st%mpc_cost_last = best_cost
        st%mpc_cost_saving = max(0.0_dp, st%mpc_cost_hold - best_cost)
        st%mpc_horizon_ready = .true.
        st%mpc_horizon_n = HORIZON
        do k = 1, HORIZON
            st%mpc_pred_time_s(k) = real(k, dp) * DT_STEP
            st%mpc_pred_freq_Hz(k) = best_freq(k)
            st%mpc_pred_pgen_MW(k) = best_pgen(k)
            st%mpc_pred_setpt_MW(k) = best_sp
            st%mpc_pred_imbalance_MW(k) = best_imbal(k)
        end do

    end subroutine mpc_step

    subroutine simulate_candidate(st, candidate_sp, delta_sp, cost, freq_path, pgen_path, imbal_path)
        type(GridState), intent(in) :: st
        real(dp), intent(in) :: candidate_sp, delta_sp
        real(dp), intent(out) :: cost
        real(dp), intent(out) :: freq_path(HORIZON), pgen_path(HORIZON), imbal_path(HORIZON)

        real(dp) :: freq_sim, pgen_sim, fixed_supply, imbal, freq_target
        real(dp) :: stiffness_MW_Hz, alpha_act, alpha_freq, ramp_move
        integer :: k

        cost = 0.0_dp
        freq_sim = st%frequency_Hz
        pgen_sim = st%gas_power_MW
        fixed_supply = st%steam_power_MW + effective_renewable_MW(st) + st%storage_MW
        stiffness_MW_Hz = max(MW_PER_HZ_MIN, 0.55_dp * max(st%demand_MW, 1.0_dp))
        alpha_act = clamp_real(DT_STEP / TAU_ACT, 0.0_dp, 1.0_dp)
        alpha_freq = clamp_real(DT_STEP / TAU_FREQ, 0.0_dp, 1.0_dp)

        do k = 1, HORIZON
            ramp_move = (candidate_sp - pgen_sim) * alpha_act
            pgen_sim = clamp_real(pgen_sim + ramp_move, 0.0_dp, max(st%gas_capacity_MW, 0.0_dp))
            imbal = pgen_sim + fixed_supply - st%demand_MW

            ! Reduced-order island frequency response:
            ! steady-state droop target plus a first-order aggregate lag. This
            ! stays numerically well-behaved for 60 s preview steps while still
            ! rewarding dispatch choices that reduce MW imbalance.
            freq_target = FREQ_NOM + imbal / stiffness_MW_Hz
            freq_sim = clamp_real(freq_sim + alpha_freq * (freq_target - freq_sim), FREQ_LO, FREQ_HI)

            freq_path(k) = freq_sim
            pgen_path(k) = pgen_sim
            imbal_path(k) = imbal
            cost = cost + Q_FREQ * (freq_sim - FREQ_NOM)**2 + &
                          R_DELTA * delta_sp**2 + R_RAMP * ramp_move**2
        end do
    end subroutine simulate_candidate

end module mpc_agc
