!> @file off_design.f90
!> @brief Off-design operating-point solver: IGV + firing-temperature load
!>        control with compressor/turbine map behaviour (revamp Phase 2).
!>
!> Physical picture (single-shaft machine at synchronous speed):
!>
!>   * The turbine first nozzle runs choked across the load range, so its
!>     corrected flow is constant:  W3*sqrt(T3)/P3 = K_t  (calibrated once at
!>     the ISO design point). For a given inlet flow and firing temperature
!>     this pins the cycle pressure ratio — the classic "running line"
!>     (Saravanamuttoo et al., Gas Turbine Theory; Walsh & Fletcher,
!>     Gas Turbine Performance).
!>   * Load is reduced the way real industrial machines do it: variable
!>     inlet guide vanes close first (corrected inlet flow 100% -> 70% of
!>     design, firing temperature held), then fuel/TIT reduction takes over
!>     below the IGV range (Kehlhofer et al., Combined-Cycle Gas & Steam
!>     Turbine Power Plants).
!>   * Component efficiencies fall quadratically with distance from the
!>     design point on their maps (representative penalty coefficients,
!>     not engine-specific data — see docs/assumptions_limitations.md).
!>   * Ambient corrections: at fixed shaft speed and IGV setting the
!>     compressor swallows constant CORRECTED flow, so physical flow scales
!>     with delta/sqrt(theta). Hot days genuinely derate the machine.
!>   * Surge margin: the surge line lies a design margin above the running
!>     line and falls with IGV closure; fast load increases over-fuel the
!>     combustor before airflow catches up, pushing the transient operating
!>     point toward surge:  SM = (PR_surge - PR_transient)/PR_transient.
module off_design
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult
    use ambient, only: inlet_state
    use cycle_solver, only: solve_cycle
    implicit none
    private

    public :: OffDesignPoint, solve_off_design
    public :: IGV_MIN_FLOW_FRAC, TIT_MIN_K, SURGE_ALARM_PCT

    ! Load-control envelope
    real(dp), parameter :: IGV_MIN_FLOW_FRAC = 0.70_dp  ! corrected-flow floor from IGVs
    real(dp), parameter :: TIT_MIN_K         = 950.0_dp ! lean-stability firing floor

    ! Hardware design references (the machine, independent of operator setpoints)
    real(dp), parameter :: DESIGN_TIT_K  = 1400.0_dp
    real(dp), parameter :: ISO_T_K       = 288.15_dp
    real(dp), parameter :: ISO_P_Pa      = 101325.0_dp

    ! Representative map penalties (quadratic distance-from-design)
    real(dp), parameter :: ETA_C_IGV_PENALTY = 0.20_dp  ! eta drop ~1.8 pts at 70% flow
    real(dp), parameter :: ETA_T_PR_PENALTY  = 0.30_dp  ! eta drop with PR deviation
    real(dp), parameter :: ETA_FLOOR         = 0.50_dp

    ! Surge line and transient excursion
    real(dp), parameter :: SURGE_PR_MARGIN_FACTOR = 1.20_dp ! 20% design surge margin
    real(dp), parameter :: SURGE_LINE_EXPONENT    = 0.85_dp ! surge PR vs flow fraction
    real(dp), parameter :: RAMP_PR_GAIN_PER_PCT_S = 0.008_dp! overfuel PR excursion gain
    real(dp), parameter :: RAMP_PR_FACTOR_MAX     = 1.25_dp
    real(dp), parameter :: SURGE_ALARM_PCT        = 8.0_dp  ! alarm threshold on SM

    !> One solved off-design operating point with map context.
    type :: OffDesignPoint
        type(CycleResult) :: cyc
        real(dp) :: flow_frac = 1.0_dp        ! corrected inlet flow / design (IGV)
        real(dp) :: igv_pct = 100.0_dp        ! IGV position, 100 = fully open
        real(dp) :: TIT_K = DESIGN_TIT_K      ! firing temperature actually used
        real(dp) :: PR_op = 15.0_dp           ! steady operating pressure ratio
        real(dp) :: PR_surge = 18.0_dp        ! surge-line PR at this flow
        real(dp) :: surge_margin_pct = 20.0_dp! vs transient operating PR
        logical  :: at_min_load = .false.     ! clamped at IGV+TIT floors
    end type OffDesignPoint

contains

    !> Solve the operating point that delivers load_frac of the machine's
    !> current capacity (ambient- and setpoint-aware), with the load carried
    !> by IGVs first and firing temperature second.
    !>
    !> @param[in]  base        machine at design PR/flow; ambient + TIT setpoint live here
    !> @param[in]  load_frac   requested net power / current capacity (0..1)
    !> @param[in]  ramp_pct_s  dispatch slew rate [%/s], drives transient surge excursion
    !> @param[out] od          solved operating point
    subroutine solve_off_design(base, load_frac, ramp_pct_s, od)
        type(InputCase), intent(in) :: base
        real(dp), intent(in) :: load_frac, ramp_pct_s
        type(OffDesignPoint), intent(out) :: od

        real(dp) :: K_t, PR_d_iso, W_phys_max
        real(dp) :: cap_MW, target_MW
        real(dp) :: lo, hi, mid
        type(OffDesignPoint) :: probe
        integer :: it
        integer, parameter :: MAX_BISECT = 24
        real(dp), parameter :: P_TOL_MW = 0.02_dp

        call calibrate(base, K_t, PR_d_iso, W_phys_max)

        ! Capacity at the current ambient and TIT setpoint: IGVs full open.
        call eval_point(base, K_t, PR_d_iso, W_phys_max, 1.0_dp, base%T_turbine_inlet_K, od)
        cap_MW = od%cyc%net_power_MW
        target_MW = max(0.0_dp, min(load_frac, 1.0_dp)) * cap_MW

        if (load_frac < 0.999_dp) then
            ! Stage 1 — IGV range at full firing temperature.
            call eval_point(base, K_t, PR_d_iso, W_phys_max, IGV_MIN_FLOW_FRAC, &
                            base%T_turbine_inlet_K, probe)
            if (probe%cyc%net_power_MW <= target_MW) then
                ! Target sits inside the IGV range: bisect flow fraction.
                lo = IGV_MIN_FLOW_FRAC; hi = 1.0_dp
                do it = 1, MAX_BISECT
                    mid = 0.5_dp * (lo + hi)
                    call eval_point(base, K_t, PR_d_iso, W_phys_max, mid, &
                                    base%T_turbine_inlet_K, od)
                    if (abs(od%cyc%net_power_MW - target_MW) < P_TOL_MW) exit
                    if (od%cyc%net_power_MW > target_MW) then
                        hi = mid
                    else
                        lo = mid
                    end if
                end do
            else
                ! Stage 2 — IGVs at minimum: bisect firing temperature.
                lo = TIT_MIN_K; hi = base%T_turbine_inlet_K
                call eval_point(base, K_t, PR_d_iso, W_phys_max, IGV_MIN_FLOW_FRAC, lo, od)
                if (od%cyc%net_power_MW >= target_MW) then
                    od%at_min_load = .true.   ! cannot go lower; pinned at the floor
                else
                    do it = 1, MAX_BISECT
                        mid = 0.5_dp * (lo + hi)
                        call eval_point(base, K_t, PR_d_iso, W_phys_max, &
                                        IGV_MIN_FLOW_FRAC, mid, od)
                        if (abs(od%cyc%net_power_MW - target_MW) < P_TOL_MW) exit
                        if (od%cyc%net_power_MW > target_MW) then
                            hi = mid
                        else
                            lo = mid
                        end if
                    end do
                end if
            end if
        end if

        call apply_surge(od, PR_d_iso, ramp_pct_s)
    end subroutine solve_off_design

    !> Calibrate the choked-turbine constant and the ambient flow correction.
    subroutine calibrate(base, K_t, PR_d_iso, W_phys_max)
        type(InputCase), intent(in) :: base
        real(dp), intent(out) :: K_t, PR_d_iso, W_phys_max
        type(InputCase) :: ic
        type(CycleResult) :: res
        real(dp) :: T1, P1, T1_iso, P1_iso

        ! Hardware reference: ISO day, design firing temperature.
        ic = base
        ic%ambient_T_K = ISO_T_K
        ic%ambient_P_Pa = ISO_P_Pa
        ic%T_turbine_inlet_K = DESIGN_TIT_K
        res = solve_cycle(ic)
        K_t = ic%mdot_air_kg_s * (1.0_dp + res%fuel_air_ratio) * &
              sqrt(DESIGN_TIT_K) / res%P3_Pa
        PR_d_iso = base%pressure_ratio
        T1_iso = res%T1_K
        P1_iso = res%P1_Pa

        ! Constant corrected flow at fixed speed/IGV: physical flow scales
        ! with inlet delta/sqrt(theta) relative to the ISO design inlet.
        call inlet_state(base, T1, P1)
        W_phys_max = base%mdot_air_kg_s * (P1 / P1_iso) * sqrt(T1_iso / T1)
    end subroutine calibrate

    !> Evaluate one (flow fraction, TIT) point on the running line.
    subroutine eval_point(base, K_t, PR_d_iso, W_phys_max, flow_frac, TIT_K, od)
        type(InputCase), intent(in) :: base
        real(dp), intent(in) :: K_t, PR_d_iso, W_phys_max, flow_frac, TIT_K
        type(OffDesignPoint), intent(out) :: od
        type(InputCase) :: ic
        real(dp) :: T1, P1, W, f, P3, PR
        integer :: pass

        call inlet_state(base, T1, P1)
        W = W_phys_max * flow_frac

        ! Choked-turbine flow matching pins P3 (hence PR) for this W and TIT.
        ! Fuel-air ratio feeds back weakly; two passes converge it.
        f = 0.020_dp
        PR = PR_d_iso
        do pass = 1, 3
            P3 = W * (1.0_dp + f) * sqrt(TIT_K) / K_t
            PR = max(1.5_dp, P3 / (P1 * (1.0_dp - base%combustor_pressure_loss)))

            ic = base
            ic%mdot_air_kg_s = W
            ic%pressure_ratio = PR
            ic%T_turbine_inlet_K = TIT_K
            ! Map efficiency penalties: quadratic distance from design.
            ic%eta_compressor = max(ETA_FLOOR, base%eta_compressor - &
                ETA_C_IGV_PENALTY * (1.0_dp - flow_frac)**2)
            ic%eta_turbine = max(ETA_FLOOR, base%eta_turbine - &
                ETA_T_PR_PENALTY * (1.0_dp - PR / PR_d_iso)**2)

            od%cyc = solve_cycle(ic)
            f = od%cyc%fuel_air_ratio
        end do

        od%flow_frac = flow_frac
        od%igv_pct = 100.0_dp * (flow_frac - IGV_MIN_FLOW_FRAC) / &
                     (1.0_dp - IGV_MIN_FLOW_FRAC)
        od%TIT_K = TIT_K
        od%PR_op = PR
        od%at_min_load = .false.
    end subroutine eval_point

    !> Surge line position and margin against the (possibly transient) PR.
    subroutine apply_surge(od, PR_d_iso, ramp_pct_s)
        type(OffDesignPoint), intent(inout) :: od
        real(dp), intent(in) :: PR_d_iso, ramp_pct_s
        real(dp) :: PR_transient, ramp_factor

        od%PR_surge = PR_d_iso * SURGE_PR_MARGIN_FACTOR * &
                      od%flow_frac**SURGE_LINE_EXPONENT
        ramp_factor = min(RAMP_PR_FACTOR_MAX, &
            1.0_dp + RAMP_PR_GAIN_PER_PCT_S * max(0.0_dp, ramp_pct_s))
        PR_transient = od%PR_op * ramp_factor
        od%surge_margin_pct = 100.0_dp * (od%PR_surge - PR_transient) / PR_transient
    end subroutine apply_surge

end module off_design
