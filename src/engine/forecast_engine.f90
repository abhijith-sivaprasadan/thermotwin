! =============================================================================
! forecast_engine.f90  --  4-hour sinusoidal demand & price forecast
!
! Produces 48 × 5-minute-step (4-hour) look-ahead arrays stored in GridState:
!   fcast_demand(FC_N)  : forecast demand [MW]
!   fcast_price(FC_N)   : forecast price  [$/MWh]
!   fcast_dem_lo(FC_N)  : demand lower confidence band [MW]
!   fcast_dem_hi(FC_N)  : demand upper confidence band [MW]
!
! The demand model is a diurnal sinusoid centred on the mid-range demand:
!   D(i) = demand_MW + amplitude * sin(2π*(elapsed_s + i*300)/86400 - φ)
! where φ is the current time-of-day phase and amplitude is half the
! market peak-to-base swing.  Confidence bands widen linearly from ±3 % at
! step 1 to ±4.5 % at step 48 relative to mean demand.
!
! The price model oscillates around the current spot price with a ±15 %
! diurnal modulation plus deterministic Lehmer-LCG "noise" of ±8 $/MWh.
!
! To avoid recomputing every engine tick (which runs at ~10 Hz) an internal
! module-level counter limits full recomputation to every 10 calls.
! =============================================================================
module forecast_engine
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: update_forecast

    ! ── Local horizon constant (mirrors engine_state FC_N = 48) ──────────────
    integer,  parameter :: FC_N_LOCAL = 48      ! 48 × 5-min = 4 hours
    real(dp), parameter :: DT_S       = 300.0_dp ! 5-minute step [s]
    real(dp), parameter :: DAY_S      = 86400.0_dp
    real(dp), parameter :: TWO_PI     = 6.28318530717958647692_dp

    ! ── Internal recompute throttle ───────────────────────────────────────────
    integer :: tick_counter = 0
    integer, parameter :: RECOMPUTE_EVERY = 10

contains

    ! -------------------------------------------------------------------------
    !> Recompute (or skip) the 4-hour demand & price forecast arrays.
    !> Should be called once per engine tick; internally throttled.
    ! -------------------------------------------------------------------------
    subroutine update_forecast(st)
        type(GridState), intent(inout) :: st

        tick_counter = tick_counter + 1
        if (mod(tick_counter, RECOMPUTE_EVERY) /= 1) return

        call compute_forecast(st)
    end subroutine update_forecast

    ! =========================================================================
    ! Private: full recomputation
    ! =========================================================================
    subroutine compute_forecast(st)
        type(GridState), intent(inout) :: st

        integer  :: i, seed_i
        real(dp) :: amplitude, current_phase, phase_i
        real(dp) :: d_i, p_i, band_frac, band_MW, noise
        real(dp) :: mean_demand
        integer  :: lcg_val

        ! Amplitude of diurnal demand swing [MW]
        amplitude = (st%market_peak_demand_MW - st%market_base_demand_MW) * 0.5_dp

        ! Current time-of-day phase [rad]
        current_phase = TWO_PI * mod(st%elapsed_s, DAY_S) / DAY_S

        mean_demand = 0.5_dp * (st%market_base_demand_MW + st%market_peak_demand_MW)

        do i = 1, FC_N_LOCAL
            ! ── Demand forecast ───────────────────────────────────────────────
            phase_i = TWO_PI * (st%elapsed_s + real(i, dp) * DT_S) / DAY_S
            d_i = st%demand_MW + amplitude * (sin(phase_i) - sin(current_phase))

            ! Keep demand physical
            d_i = max(st%market_base_demand_MW * 0.5_dp, d_i)

            ! Confidence band: widens from 3 % to 4.5 % of mean demand
            band_frac = 0.03_dp + 0.015_dp * (real(i, dp) / real(FC_N_LOCAL, dp))
            band_MW   = band_frac * mean_demand

            st%fcast_demand(i) = d_i
            st%fcast_dem_lo(i) = d_i - band_MW
            st%fcast_dem_hi(i) = d_i + band_MW

            ! ── Price forecast ────────────────────────────────────────────────
            ! Diurnal modulation (±15 % of current spot price)
            p_i = st%power_price_usd_mwh * &
                  (1.0_dp + 0.15_dp * sin(phase_i))

            ! Deterministic Lehmer LCG noise: ±8 $/MWh
            seed_i  = int(st%elapsed_s) + i
            lcg_val = mod(seed_i * 1664525 + 1013904223, 65536)
            if (lcg_val < 0) lcg_val = lcg_val + 65536  ! ensure non-negative
            noise   = 8.0_dp * (2.0_dp * real(lcg_val, dp) / 65536.0_dp - 1.0_dp)

            st%fcast_price(i) = max(0.0_dp, p_i + noise)
        end do
    end subroutine compute_forecast

end module forecast_engine
