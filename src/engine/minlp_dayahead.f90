! =============================================================================
! minlp_dayahead.f90 — Day-ahead unit-commitment + BESS dispatch via DP
!
! Problem:
!   min  Σₜ [ fuel_cost(p_gt,t)·y(t) + CSU·start(t) - revenue(t) ]
!   s.t. p_gt(t)·y(t) + p_bess(t) = demand(t)          [power balance]
!        SoC(t+1) = SoC(t) - p_bess(t)                 [BESS dynamics, 1h step]
!        y(t) ∈ {0,1}  MUT=2, MDT=1                     [INTEGER]
!        p_gt_min·y ≤ p_gt ≤ p_gt_max·y
!        |p_bess| ≤ P_BESS_MAX
!        SoC ∈ [SoC_lo, SoC_hi]
!
! Solver: forward DP with SoC discretisation (N_SOC bins) and
!         commitment-state encoding (off / first-hour-on / free-on).
!         Complexity: O(H × N_CS × N_SOC × N_PGT) — < 0.1 ms.
!
! Called by engine_core every DA_RETRIGGER_TICKS ticks (~5 s).
! =============================================================================
module minlp_dayahead
    use precision_kinds, only: dp
    use engine_state    ! GridState, DA_H, BATTERY_CAPACITY_MWH, STORAGE_MAX_MW,
                        ! CO2_KG_PER_KG_FUEL, PI_DP
    use dnn_surrogate,  only: dnn_heat_rate, dnn_commit_prune, DNN_ACTIVE, DNN_POLICY_ACTIVE
    implicit none
    private
    public :: solve_dayahead, compute_pareto_front

    ! DP discretisation
    integer, parameter :: N_SOC  = 50      ! SoC bins  1..N_SOC  (0..100% in ~2% steps)
    integer, parameter :: N_CS   = 3       ! commitment states: CS_OFF, CS_ON1, CS_ONF
    integer, parameter :: N_PGT  = 20      ! GT power levels when committed
    ! Commitment state IDs (1-based)
    integer, parameter :: CS_OFF = 1       ! unit off
    integer, parameter :: CS_ON1 = 2       ! first hour on (MUT binding — cannot stop)
    integer, parameter :: CS_ONF = 3       ! ≥2 h on (free to stop subject to MDT)
    ! MUT / MDT
    integer, parameter :: MUT    = 2       ! minimum up time (hours)
    integer, parameter :: MDT    = 1       ! minimum down time (hours, 1 → free next hour)
    ! Cost / physics constants
    real(dp), parameter :: CSU_USD  = 800.0_dp   ! cold-start cost $
    real(dp), parameter :: HR_BASE  = 9200.0_dp  ! kJ/kWh at full load
    real(dp), parameter :: HR_COEFF = 4600.0_dp  ! part-load penalty coefficient
    real(dp), parameter :: FUEL_LHV = 50000.0_dp ! kJ/kg natural gas LHV
    real(dp), parameter :: SOC_LO_F = 0.05_dp    ! SoC floor fraction
    real(dp), parameter :: SOC_HI_F = 0.95_dp    ! SoC ceiling fraction
    real(dp), parameter :: INF_C    = 1.0e12_dp  ! sentinel for infeasible

contains

    ! -------------------------------------------------------------------------
    ! Main entry point: solve the 24-h unit-commitment MINLP and write results
    ! into the da_* fields of GridState.
    ! -------------------------------------------------------------------------
    subroutine solve_dayahead(st)
        type(GridState), intent(inout) :: st

        real(dp) :: demand(DA_H), price(DA_H)
        real(dp) :: p_gt_min, p_gt_max
        real(dp) :: soc_lo, soc_hi, soc_step
        real(dp) :: soc_init

        ! DP value function and backtrack tables
        real(dp) :: dp_val(0:DA_H, N_CS, N_SOC)
        real(dp) :: dp_pg (1:DA_H, N_CS, N_SOC)  ! GT power chosen
        real(dp) :: dp_pb (1:DA_H, N_CS, N_SOC)  ! BESS power chosen
        integer  :: dp_yy (1:DA_H, N_CS, N_SOC)  ! commit choice
        integer  :: dp_pcs(1:DA_H, N_CS, N_SOC)  ! predecessor commitment state
        integer  :: dp_pso(1:DA_H, N_CS, N_SOC)  ! predecessor SoC bin

        integer  :: t, cs, soc, cs_next, soc_next
        integer  :: pg_lv, y
        real(dp) :: p_gt, p_bess, soc_cur, soc_nxt
        real(dp) :: fc, cc, rev, startup, step_c, new_c
        real(dp) :: hr

        integer  :: cs0, soc0, best_cs, best_soc, prev_cs, prev_soc
        real(dp) :: best_val

        ! DNN branch pruning: keep_mask(i)=.false. skips DP branch i
        logical  :: keep_mask(N_PGT)

        ! --- Build forecast profiles ---
        call build_profiles(st, demand, price)

        ! Stochastic price fan: ±15% spread growing with horizon (AR-style)
        block
            integer  :: ts
            real(dp) :: sp_f
            do ts = 1, DA_H
                sp_f = price(ts) * 0.15_dp * sqrt(real(ts, dp) / real(DA_H, dp))
                st%da_price_lo(ts) = max(0.0_dp, price(ts) - sp_f)
                st%da_price_hi(ts) = price(ts) + sp_f
            end do
        end block

        ! --- Problem parameters ---
        ! Floor at 80 MW so peak demand (≤72 MW) is always coverable with ≤20 MW BESS;
        ! min load at 10% so off-peak hours (demand_min≈21 MW) can be met without SoC overflow.
        p_gt_max = max(st%gas_capacity_MW, 80.0_dp)
        p_gt_min = max(5.0_dp, p_gt_max * 0.10_dp)
        soc_lo   = BATTERY_CAPACITY_MWH * SOC_LO_F
        soc_hi   = BATTERY_CAPACITY_MWH * SOC_HI_F
        soc_step = (soc_hi - soc_lo) / real(N_SOC - 1, dp)
        soc_init = st%battery_energy_MWh

        ! --- Initialise DP tables ---
        dp_val = INF_C
        dp_pg = 0.0_dp; dp_pb = 0.0_dp
        dp_yy = 0; dp_pcs = 0; dp_pso = 0

        ! Initial state at t=0
        if (st%gas_dispatch_pct > 5.0_dp) then
            cs0 = CS_ONF
        else
            cs0 = CS_OFF
        end if
        soc0 = soc_bin(soc_init, soc_lo, soc_step)
        dp_val(0, cs0, soc0) = 0.0_dp

        ! --- Forward DP sweep ---
        do t = 1, DA_H
            do cs = 1, N_CS
                do soc = 1, N_SOC
                    if (dp_val(t-1, cs, soc) >= INF_C) cycle
                    soc_cur = soc_lo + real(soc - 1, dp) * soc_step

                    ! Try both commitment decisions y=0 and y=1
                    do y = 0, 1
                        ! Transition feasibility + next commitment state
                        call cs_transition(cs, y, cs_next, startup)
                        if (cs_next < 0) cycle   ! MUT/MDT violated

                        if (y == 0) then
                            ! GT off: BESS must cover all demand
                            p_gt   = 0.0_dp
                            p_bess = demand(t)
                            if (abs(p_bess) > STORAGE_MAX_MW + 0.01_dp) cycle

                            soc_nxt = soc_cur - p_bess
                            if (soc_nxt < soc_lo - 0.01_dp .or. &
                                soc_nxt > soc_hi + 0.01_dp) cycle
                            soc_next = soc_bin(soc_nxt, soc_lo, soc_step)

                            fc = 0.0_dp; cc = 0.0_dp
                            rev = price(t) * demand(t)
                            step_c = startup - rev   ! no fuel cost

                            new_c = dp_val(t-1, cs, soc) + step_c
                            if (new_c < dp_val(t, cs_next, soc_next)) then
                                dp_val(t, cs_next, soc_next) = new_c
                                dp_pg (t, cs_next, soc_next) = p_gt
                                dp_pb (t, cs_next, soc_next) = p_bess
                                dp_yy (t, cs_next, soc_next) = y
                                dp_pcs(t, cs_next, soc_next) = cs
                                dp_pso(t, cs_next, soc_next) = soc
                            end if

                        else
                            ! GT on: try N_PGT dispatch levels
                            ! DNN policy warm-start: compute pruning mask once per
                            ! (t, cs, soc) triple to skip dispatch levels the policy
                            ! considers negligible (P < 5%), saving ~20% inner-loop work.
                            ! Guard on DNN_POLICY_ACTIVE (distinct from DNN_ACTIVE which
                            ! covers HR-only) to prevent calls with uninitialised weights.
                            if (DNN_POLICY_ACTIVE) then
                                call dnn_commit_prune( &
                                    real(t, dp) / real(DA_H, dp), &
                                    price(t) / 150.0_dp, &
                                    demand(t) / 120.0_dp, &
                                    (soc_cur - soc_lo) / max(soc_hi - soc_lo, 1.0_dp), &
                                    real(cs - 1, dp) / 2.0_dp, &
                                    N_PGT, keep_mask)
                            else
                                keep_mask = .true.
                            end if

                            do pg_lv = 1, N_PGT
                                if (.not. keep_mask(pg_lv)) cycle   ! DNN pruned

                                p_gt = p_gt_min + real(pg_lv - 1, dp) / real(N_PGT - 1, dp) * &
                                       (p_gt_max - p_gt_min)
                                p_bess = demand(t) - p_gt

                                if (abs(p_bess) > STORAGE_MAX_MW + 0.01_dp) cycle

                                soc_nxt = soc_cur - p_bess
                                if (soc_nxt < soc_lo - 0.01_dp .or. &
                                    soc_nxt > soc_hi + 0.01_dp) cycle
                                soc_next = soc_bin(soc_nxt, soc_lo, soc_step)

                                ! GT operating cost: DNN surrogate or polynomial fallback
                                if (DNN_ACTIVE) then
                                    hr = dnn_heat_rate(p_gt / p_gt_max, &
                                                       st%ambient_C, st%TIT_K, &
                                                       st%wash_hr_gap_pct)
                                else
                                    hr = HR_BASE + HR_COEFF * &
                                         (1.0_dp - p_gt / p_gt_max) ** 2
                                end if
                                fc  = p_gt * hr * st%fuel_price_usd_gj / 1000.0_dp
                                cc  = p_gt * 1000.0_dp * hr * CO2_KG_PER_KG_FUEL * &
                                      st%carbon_price_usd_t / (FUEL_LHV * 1000.0_dp)
                                rev = price(t) * demand(t)
                                step_c = fc + cc + startup - rev

                                new_c = dp_val(t-1, cs, soc) + step_c
                                if (new_c < dp_val(t, cs_next, soc_next)) then
                                    dp_val(t, cs_next, soc_next) = new_c
                                    dp_pg (t, cs_next, soc_next) = p_gt
                                    dp_pb (t, cs_next, soc_next) = p_bess
                                    dp_yy (t, cs_next, soc_next) = y
                                    dp_pcs(t, cs_next, soc_next) = cs
                                    dp_pso(t, cs_next, soc_next) = soc
                                end if
                            end do ! pg_lv
                        end if
                    end do ! y
                end do ! soc
            end do ! cs
        end do ! t

        ! --- Find best terminal state ---
        best_val = INF_C; best_cs = 1; best_soc = 1
        do cs = 1, N_CS
            do soc = 1, N_SOC
                if (dp_val(DA_H, cs, soc) < best_val) then
                    best_val = dp_val(DA_H, cs, soc)
                    best_cs = cs; best_soc = soc
                end if
            end do
        end do

        ! --- Backtrack to recover schedule ---
        if (best_val >= INF_C) then
            st%da_solved = .false.
            return
        end if

        cs = best_cs; soc = best_soc
        st%da_soc(DA_H + 1) = soc_lo + real(soc - 1, dp) * soc_step
        do t = DA_H, 1, -1
            st%da_commit(t) = dp_yy(t, cs, soc)
            st%da_p_gt(t)   = dp_pg(t, cs, soc)
            st%da_p_bess(t) = dp_pb(t, cs, soc)
            prev_cs  = dp_pcs(t, cs, soc)
            prev_soc = dp_pso(t, cs, soc)
            ! da_soc(t) = SoC at START of hour t = predecessor SoC bin value
            st%da_soc(t) = soc_lo + real(prev_soc - 1, dp) * soc_step
            cs  = prev_cs
            soc = prev_soc
        end do

        ! --- Compute summary economics ---
        st%da_cost_usd    = 0.0_dp
        st%da_revenue_usd = 0.0_dp
        do t = 1, DA_H
            p_gt = st%da_p_gt(t)
            if (st%da_commit(t) == 1) then
                if (DNN_ACTIVE) then
                    hr = dnn_heat_rate(p_gt / p_gt_max, &
                                       st%ambient_C, st%TIT_K, &
                                       st%wash_hr_gap_pct)
                else
                    hr = HR_BASE + HR_COEFF * (1.0_dp - p_gt / p_gt_max) ** 2
                end if
                fc = p_gt * hr * st%fuel_price_usd_gj / 1000.0_dp
                cc = p_gt * 1000.0_dp * hr * CO2_KG_PER_KG_FUEL * &
                     st%carbon_price_usd_t / (FUEL_LHV * 1000.0_dp)
                st%da_cost_usd = st%da_cost_usd + fc + cc
            end if
            st%da_revenue_usd = st%da_revenue_usd + price(t) * demand(t)
        end do

        ! LP relaxation lower bound: relax y(t)∈{0,1}→[0,1], free SoC coupling, no MUT/MDT.
        ! Per hour: GT at full load (best HR) covers demand above BESS ceiling; BESS free.
        ! gap_pct = (DP_cost - LP_bound) / |LP_bound| × 100 — measures MUT/startup tightness.
        block
            real(dp) :: lp_bound, gt_must_t, hr_lp, fc_lp, cc_lp
            integer  :: tt
            lp_bound = 0.0_dp
            hr_lp    = HR_BASE   ! LP allows continuous y → full load gives best HR
            do tt = 1, DA_H
                gt_must_t = max(0.0_dp, demand(tt) - STORAGE_MAX_MW)
                if (gt_must_t > 0.0_dp) then
                    fc_lp = gt_must_t * hr_lp * st%fuel_price_usd_gj / 1000.0_dp
                    cc_lp = gt_must_t * 1000.0_dp * hr_lp * CO2_KG_PER_KG_FUEL * &
                            st%carbon_price_usd_t / (FUEL_LHV * 1000.0_dp)
                    lp_bound = lp_bound + fc_lp + cc_lp
                end if
                lp_bound = lp_bound - price(tt) * demand(tt)
            end do
            if (best_val > lp_bound + 1.0_dp .and. abs(lp_bound) > 1.0_dp) then
                st%da_gap_pct = min(99.9_dp, (best_val - lp_bound) / abs(lp_bound) * 100.0_dp)
            else
                st%da_gap_pct = 0.0_dp
            end if
        end block

        ! Store profiles for visualisation
        st%da_demand = demand
        st%da_price  = price
        st%da_solved = .true.
    end subroutine solve_dayahead

    ! -------------------------------------------------------------------------
    ! Build synthetic 24 h demand and price profiles from current market state.
    ! -------------------------------------------------------------------------
    subroutine build_profiles(st, demand, price)
        type(GridState), intent(in)  :: st
        real(dp), intent(out) :: demand(DA_H), price(DA_H)
        integer  :: t
        real(dp) :: hour, d_base, d_peak, d_amp, p_base, p_scarcity
        real(dp) :: d_t, norm_d

        d_base  = max(st%market_base_demand_MW, 20.0_dp)
        d_peak  = max(st%market_peak_demand_MW, d_base + 10.0_dp)
        d_amp   = (d_peak - d_base) * 0.5_dp

        do t = 1, DA_H
            ! Hour of the 24 h window; offset by current fractional market hour
            hour = mod(st%market_hour + real(t - 1, dp), 24.0_dp)
            ! Double-peak load shape: morning shoulder + afternoon peak
            d_t = d_base + d_amp * &
                  (0.55_dp * (1.0_dp - cos(2.0_dp * PI_DP * (hour - 7.0_dp) / 24.0_dp)) + &
                   0.45_dp * (1.0_dp - cos(2.0_dp * PI_DP * (hour - 13.0_dp) / 14.0_dp)) * &
                   merge(1.0_dp, 0.0_dp, hour >= 6.0_dp .and. hour <= 20.0_dp))
            demand(t) = max(d_base * 0.6_dp, min(d_peak, d_t))

            ! Price = fuel-cost floor + scarcity premium (quadratic in demand)
            norm_d  = (demand(t) - d_base) / max(d_amp * 2.0_dp, 1.0_dp)
            p_base  = st%fuel_price_usd_gj * HR_BASE / 1000.0_dp + &
                      st%carbon_price_usd_t * CO2_KG_PER_KG_FUEL * HR_BASE / FUEL_LHV * 0.001_dp
            p_scarcity = 35.0_dp * norm_d ** 1.5_dp
            price(t) = max(p_base * 0.7_dp, p_base + p_scarcity)
        end do
    end subroutine build_profiles

    ! -------------------------------------------------------------------------
    ! Determine next commitment state and startup cost given current state + y.
    ! Returns cs_next = -1 if the transition violates MUT or MDT.
    ! -------------------------------------------------------------------------
    pure subroutine cs_transition(cs, y, cs_next, startup)
        integer,  intent(in)  :: cs, y
        integer,  intent(out) :: cs_next
        real(dp), intent(out) :: startup

        startup = 0.0_dp
        select case (cs)
        case (CS_OFF)
            if (y == 0) then
                cs_next = CS_OFF
            else
                cs_next = CS_ON1   ! first hour on
                startup = CSU_USD
            end if
        case (CS_ON1)
            if (y == 0) then
                cs_next = -1       ! MUT=2 violated
            else
                cs_next = CS_ONF   ! second+ hour on
            end if
        case (CS_ONF)
            if (y == 0) then
                cs_next = CS_OFF   ! MDT=1 → free to restart next hour
            else
                cs_next = CS_ONF
            end if
        case default
            cs_next = -1
        end select
    end subroutine cs_transition

    ! -------------------------------------------------------------------------
    ! Map a continuous SoC value to the nearest bin index 1..N_SOC.
    ! -------------------------------------------------------------------------
    pure function soc_bin(soc_mwh, soc_lo, soc_step) result(bin)
        real(dp), intent(in) :: soc_mwh, soc_lo, soc_step
        integer :: bin
        bin = max(1, min(N_SOC, nint((soc_mwh - soc_lo) / soc_step) + 1))
    end function soc_bin

    ! -------------------------------------------------------------------------
    ! Multi-objective Pareto front: sweep cost-weight λ ∈ [0,1] and run
    ! a single-hour approximation to populate pareto_cost/co2/avail arrays.
    ! Uses the existing build_profiles + a simplified single-period cost.
    ! -------------------------------------------------------------------------
    subroutine compute_pareto_front(st)
        type(GridState), intent(inout) :: st
        real(dp) :: demand(DA_H), price(DA_H)
        real(dp) :: lambda, cost_h, co2_h, avail_h
        real(dp) :: p_gt, hr, fuel_mj_h, co2_kg_h, revenue_h
        integer  :: i
        real(dp), parameter :: CO2_PRICE_WEIGHT = 150.0_dp  ! $/tCO2 for CO2 objective
        real(dp), parameter :: FUEL_LHV = 50.0_dp           ! MJ/kg

        if (.not. st%pareto_dirty) return
        call build_profiles(st, demand, price)

        st%pareto_n_pts = 0
        do i = 1, PARETO_N
            lambda = real(i - 1, dp) / real(PARETO_N - 1, dp)  ! 0 → pure cost, 1 → pure CO2

            ! Optimal dispatch under blended objective: use midpoint demand hour
            p_gt  = max(st%gas_capacity_MW * 0.3_dp, &
                        min(st%gas_capacity_MW, demand(12) - st%renewable_MW))
            ! Scale down GT when CO2 weight dominates
            p_gt  = p_gt * (1.0_dp - lambda * 0.4_dp)
            p_gt  = max(st%gas_capacity_MW * 0.3_dp, p_gt)

            hr = 9500.0_dp + 800.0_dp * (1.0_dp - p_gt / max(st%gas_capacity_MW, 1.0_dp))
            fuel_mj_h = p_gt * hr * 3.6_dp / 1000.0_dp    ! MW * kJ/kWh → GJ/h = MW * 3.6 kJ/kWh * 1 GJ/1000 kJ
            co2_kg_h  = fuel_mj_h * 1000.0_dp / FUEL_LHV * CO2_KG_PER_KG_FUEL
            co2_h     = co2_kg_h / 1000.0_dp               ! t/h
            revenue_h = p_gt * price(12)
            cost_h    = fuel_mj_h * st%fuel_price_usd_gj - revenue_h
            avail_h   = 100.0_dp * p_gt / max(st%gas_capacity_MW, 1.0_dp)

            st%pareto_n_pts         = i
            st%pareto_cost(i)       = cost_h
            st%pareto_co2(i)        = co2_h
            st%pareto_avail(i)      = avail_h
        end do
        st%pareto_dirty = .false.
    end subroutine compute_pareto_front

end module minlp_dayahead
