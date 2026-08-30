! =============================================================================
! anomaly_detector.f90  --  EWMA anomaly detector for 4 GT sensors
!
! Tracks an exponentially-weighted mean (EWMA) and variance for each of the
! four key gas-turbine sensors:
!   hr  : gt_heat_rate_kJ_kWh
!   tex : exhaust_K
!   sm  : surge_margin_pct
!   eta : gt_thermal_efficiency
!
! During a warm-up period (BASELINE_TICKS ticks) the detector builds its
! baseline using an incremental mean/variance estimator.  After warm-up each
! tick updates the EWMA and variance with smoothing factor ALPHA and computes
! a Z-score (capped at 10) for each sensor.  A composite score is the mean of
! the four individual Z-scores.
! =============================================================================
module anomaly_detector
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: update_anomaly_detector, reset_anomaly_detector

    ! ── Tuning parameters ────────────────────────────────────────────────────
    integer,  parameter :: BASELINE_TICKS = 20
    real(dp), parameter :: ALPHA          = 0.05_dp

contains

    ! -------------------------------------------------------------------------
    !> Seed all EWMA/variance state from the current sensor readings and zero
    !> the tick counter and anomaly scores.  Call once before starting a new
    !> simulation run or after a manual reset.
    ! -------------------------------------------------------------------------
    subroutine reset_anomaly_detector(st)
        type(GridState), intent(inout) :: st

        st%anom_tick     = 0

        ! Seed EWMA at current sensor values
        st%anom_ewma_hr  = st%gt_heat_rate_kJ_kWh
        st%anom_ewma_tex = st%exhaust_K
        st%anom_ewma_sm  = st%surge_margin_pct
        st%anom_ewma_eta = st%gt_thermal_efficiency

        ! Seed variance with reasonable prior dispersions
        st%anom_var_hr   = 400.0_dp    ! (≈20 kJ/kWh)^2
        st%anom_var_tex  = 100.0_dp    ! (≈10 K)^2
        st%anom_var_sm   = 9.0_dp      ! (≈3 %)^2
        st%anom_var_eta  = 1.0e-4_dp   ! (≈0.01)^2

        ! Clear scores
        st%anom_score_hr  = 0.0_dp
        st%anom_score_tex = 0.0_dp
        st%anom_score_sm  = 0.0_dp
        st%anom_score_eta = 0.0_dp
        st%anom_composite = 0.0_dp
    end subroutine reset_anomaly_detector

    ! -------------------------------------------------------------------------
    !> Advance the detector by one engine tick.
    !>
    !> Ticks 1..BASELINE_TICKS: incremental mean/variance (alpha_eff = 1/tick);
    !>   scores are held at zero during this warm-up phase.
    !> Ticks >BASELINE_TICKS: EWMA+variance update and Z-score computation.
    ! -------------------------------------------------------------------------
    subroutine update_anomaly_detector(st)
        type(GridState), intent(inout) :: st

        real(dp) :: alpha_eff
        real(dp) :: sensor_hr, sensor_tex, sensor_sm, sensor_eta
        real(dp) :: dev_hr, dev_tex, dev_sm, dev_eta

        ! Snapshot sensor readings
        sensor_hr  = st%gt_heat_rate_kJ_kWh
        sensor_tex = st%exhaust_K
        sensor_sm  = st%surge_margin_pct
        sensor_eta = st%gt_thermal_efficiency

        st%anom_tick = st%anom_tick + 1

        if (st%anom_tick <= BASELINE_TICKS) then
            ! ── Warm-up: incremental (Welford-style) mean update ──────────────
            alpha_eff = 1.0_dp / real(st%anom_tick, dp)

            ! Mean update
            st%anom_ewma_hr  = st%anom_ewma_hr  + alpha_eff * (sensor_hr  - st%anom_ewma_hr)
            st%anom_ewma_tex = st%anom_ewma_tex + alpha_eff * (sensor_tex - st%anom_ewma_tex)
            st%anom_ewma_sm  = st%anom_ewma_sm  + alpha_eff * (sensor_sm  - st%anom_ewma_sm)
            st%anom_ewma_eta = st%anom_ewma_eta + alpha_eff * (sensor_eta - st%anom_ewma_eta)

            ! Variance update (same incremental alpha keeps it unbiased online)
            st%anom_var_hr  = st%anom_var_hr  + alpha_eff * ((sensor_hr  - st%anom_ewma_hr)**2  - st%anom_var_hr)
            st%anom_var_tex = st%anom_var_tex + alpha_eff * ((sensor_tex - st%anom_ewma_tex)**2 - st%anom_var_tex)
            st%anom_var_sm  = st%anom_var_sm  + alpha_eff * ((sensor_sm  - st%anom_ewma_sm)**2  - st%anom_var_sm)
            st%anom_var_eta = st%anom_var_eta + alpha_eff * ((sensor_eta - st%anom_ewma_eta)**2 - st%anom_var_eta)

            ! Scores remain zero during warm-up
            st%anom_score_hr  = 0.0_dp
            st%anom_score_tex = 0.0_dp
            st%anom_score_sm  = 0.0_dp
            st%anom_score_eta = 0.0_dp
            st%anom_composite = 0.0_dp
            return
        end if

        ! ── Post-warm-up: EWMA + variance update ─────────────────────────────
        ! Deviations before mean update (current residuals)
        dev_hr  = sensor_hr  - st%anom_ewma_hr
        dev_tex = sensor_tex - st%anom_ewma_tex
        dev_sm  = sensor_sm  - st%anom_ewma_sm
        dev_eta = sensor_eta - st%anom_ewma_eta

        ! EWMA mean
        st%anom_ewma_hr  = (1.0_dp - ALPHA) * st%anom_ewma_hr  + ALPHA * sensor_hr
        st%anom_ewma_tex = (1.0_dp - ALPHA) * st%anom_ewma_tex + ALPHA * sensor_tex
        st%anom_ewma_sm  = (1.0_dp - ALPHA) * st%anom_ewma_sm  + ALPHA * sensor_sm
        st%anom_ewma_eta = (1.0_dp - ALPHA) * st%anom_ewma_eta + ALPHA * sensor_eta

        ! EWMA variance
        st%anom_var_hr  = (1.0_dp - ALPHA) * st%anom_var_hr  + ALPHA * dev_hr**2
        st%anom_var_tex = (1.0_dp - ALPHA) * st%anom_var_tex + ALPHA * dev_tex**2
        st%anom_var_sm  = (1.0_dp - ALPHA) * st%anom_var_sm  + ALPHA * dev_sm**2
        st%anom_var_eta = (1.0_dp - ALPHA) * st%anom_var_eta + ALPHA * dev_eta**2

        ! Z-scores (capped at 10); only computed when variance is meaningful
        if (st%anom_var_hr > 1.0e-9_dp) then
            st%anom_score_hr = min(10.0_dp, abs(dev_hr) / sqrt(st%anom_var_hr))
        else
            st%anom_score_hr = 0.0_dp
        end if

        if (st%anom_var_tex > 1.0e-9_dp) then
            st%anom_score_tex = min(10.0_dp, abs(dev_tex) / sqrt(st%anom_var_tex))
        else
            st%anom_score_tex = 0.0_dp
        end if

        if (st%anom_var_sm > 1.0e-9_dp) then
            st%anom_score_sm = min(10.0_dp, abs(dev_sm) / sqrt(st%anom_var_sm))
        else
            st%anom_score_sm = 0.0_dp
        end if

        if (st%anom_var_eta > 1.0e-9_dp) then
            st%anom_score_eta = min(10.0_dp, abs(dev_eta) / sqrt(st%anom_var_eta))
        else
            st%anom_score_eta = 0.0_dp
        end if

        ! Composite = mean of four individual scores
        st%anom_composite = 0.25_dp * (st%anom_score_hr + st%anom_score_tex + &
                                        st%anom_score_sm + st%anom_score_eta)
    end subroutine update_anomaly_detector

end module anomaly_detector
