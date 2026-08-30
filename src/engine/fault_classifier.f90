! =============================================================================
! fault_classifier.f90  --  Decision-tree fault classifier (top-2 faults)
!
! Evaluates a score in [0, 1] for each of 6 fault classes based on anomaly
! Z-scores and physical thresholds, then stores the two highest-scoring faults
! (confidence > 0.1) in GridState fields fc_class1/fc_conf1 and
! fc_class2/fc_conf2.  fc_class = FC_NONE (0) when no fault is credible.
!
! Fault class IDs (named integer parameters):
!   FC_NONE      = 0   No credible fault
!   FC_COMP_FOUL = 1   Compressor fouling
!   FC_TIP_CLEAR = 2   Blade tip clearance degradation
!   FC_TBC_SPALL = 3   Thermal barrier coating spallation
!   FC_FUEL_BIAS = 4   Fuel flow / metering bias
!   FC_SENSOR_DRIFT= 5 Isolated sensor drift
!   FC_HRSG_PINCH  = 6 HRSG pinch-point deterioration
! =============================================================================
module fault_classifier
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: update_fault_classifier

    ! ── Fault class ID constants ─────────────────────────────────────────────
    integer, parameter, public :: FC_NONE       = 0
    integer, parameter, public :: FC_COMP_FOUL  = 1
    integer, parameter, public :: FC_TIP_CLEAR  = 2
    integer, parameter, public :: FC_TBC_SPALL  = 3
    integer, parameter, public :: FC_FUEL_BIAS  = 4
    integer, parameter, public :: FC_SENSOR_DRIFT = 5
    integer, parameter, public :: FC_HRSG_PINCH = 6

    integer, parameter :: N_FAULTS = 6
    real(dp), parameter :: CONF_THRESHOLD = 0.1_dp

contains

    ! -------------------------------------------------------------------------
    !> Compute per-fault scores, rank them, and write the top-2 into st.
    ! -------------------------------------------------------------------------
    subroutine update_fault_classifier(st)
        type(GridState), intent(inout) :: st

        real(dp) :: scores(N_FAULTS)   ! scores for classes 1..6
        real(dp) :: score_cf, score_tc, score_tbc, score_fb, score_sd, score_hp
        real(dp) :: expected_ff, bias, max_score_ind
        integer  :: ids(N_FAULTS), i, top1, top2

        ! ── FC_COMP_FOUL (1) ──────────────────────────────────────────────────
        if (st%anom_score_hr > 3.0_dp .and. st%surge_margin_pct < 20.0_dp) then
            score_cf = (st%anom_score_hr / 10.0_dp) * 0.6_dp + &
                       (1.0_dp - st%surge_margin_pct / 30.0_dp) * 0.4_dp
        else
            score_cf = 0.0_dp
        end if
        score_cf = min(1.0_dp, max(0.0_dp, score_cf))

        ! ── FC_TIP_CLEAR (2) ──────────────────────────────────────────────────
        if (st%anom_score_eta > 2.0_dp .and. st%exhaust_K > 900.0_dp) then
            score_tc = (st%anom_score_eta / 10.0_dp) * 0.7_dp + &
                       ((st%exhaust_K - 880.0_dp) / 100.0_dp) * 0.3_dp
        else
            score_tc = 0.0_dp
        end if
        score_tc = min(1.0_dp, max(0.0_dp, score_tc))

        ! ── FC_TBC_SPALL (3) ──────────────────────────────────────────────────
        if (st%TIT_actual_K > 1470.0_dp .and. st%anom_score_tex > 2.0_dp) then
            score_tbc = (st%anom_score_tex / 10.0_dp) * 0.5_dp + &
                        ((st%TIT_actual_K - 1450.0_dp) / 100.0_dp) * 0.5_dp
        else
            score_tbc = 0.0_dp
        end if
        score_tbc = min(1.0_dp, max(0.0_dp, score_tbc))

        ! ── FC_FUEL_BIAS (4) ──────────────────────────────────────────────────
        ! Expected fuel flow: heuristic from plant power (30 MW → 1 kg/s)
        if (st%plant_power_MW > 1.0e-3_dp) then
            expected_ff = st%plant_power_MW / 30.0_dp
        else
            expected_ff = 0.0_dp
        end if
        bias = abs(st%fuel_flow_kg_s - expected_ff)
        if (bias > 0.3_dp) then
            score_fb = min(1.0_dp, bias / 1.5_dp)
        else
            score_fb = 0.0_dp
        end if

        ! ── FC_SENSOR_DRIFT (5) ───────────────────────────────────────────────
        ! Isolated spike: one individual score > 4 but composite < 2
        max_score_ind = max(st%anom_score_hr, st%anom_score_tex, &
                            st%anom_score_sm, st%anom_score_eta)
        if (max_score_ind > 4.0_dp .and. st%anom_composite < 2.0_dp) then
            score_sd = max_score_ind / 10.0_dp
        else
            score_sd = 0.0_dp
        end if

        ! ── FC_HRSG_PINCH (6) ─────────────────────────────────────────────────
        if (st%combined_cycle .and. st%hrsg_pinch_K < 8.0_dp) then
            score_hp = (8.0_dp - st%hrsg_pinch_K) / 8.0_dp
        else
            score_hp = 0.0_dp
        end if
        score_hp = min(1.0_dp, max(0.0_dp, score_hp))

        ! Pack into array (index = fault class ID)
        scores(FC_COMP_FOUL)   = score_cf
        scores(FC_TIP_CLEAR)   = score_tc
        scores(FC_TBC_SPALL)   = score_tbc
        scores(FC_FUEL_BIAS)   = score_fb
        scores(FC_SENSOR_DRIFT)= score_sd
        scores(FC_HRSG_PINCH)  = score_hp

        ! Build ID array for ranking
        do i = 1, N_FAULTS
            ids(i) = i
        end do

        ! Find top-1
        top1 = 1
        do i = 2, N_FAULTS
            if (scores(i) > scores(top1)) top1 = i
        end do

        ! Find top-2 (excluding top1)
        top2 = 0
        do i = 1, N_FAULTS
            if (i == top1) cycle
            if (top2 == 0) then
                top2 = i
            else if (scores(i) > scores(top2)) then
                top2 = i
            end if
        end do

        ! Write results; class = FC_NONE when below threshold
        if (scores(top1) > CONF_THRESHOLD) then
            st%fc_class1 = top1
            st%fc_conf1  = scores(top1)
        else
            st%fc_class1 = FC_NONE
            st%fc_conf1  = 0.0_dp
        end if

        if (top2 > 0 .and. scores(top2) > CONF_THRESHOLD) then
            st%fc_class2 = top2
            st%fc_conf2  = scores(top2)
        else
            st%fc_class2 = FC_NONE
            st%fc_conf2  = 0.0_dp
        end if
    end subroutine update_fault_classifier

end module fault_classifier
