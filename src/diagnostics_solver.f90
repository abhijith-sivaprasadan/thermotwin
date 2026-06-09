!> @file diagnostics_solver.f90
!> @brief Inverse problem: infer the degradation state from "measured" data.
!>
!> Given a set of observed performance quantities (net power, exhaust
!> temperature, fuel flow, compressor-outlet temperature) for an engine known
!> to be degraded, estimate the most likely degradation parameters by
!> minimising a weighted least-squares residual between measured and modelled
!> quantities.
!>
!> Strategy:
!>   * coarse grid search over the four degradation knobs (robust, no gradients)
!>   * followed by coordinate-descent refinement around the best grid point
!>
!> The objective and weighting are made explicit (documented in
!> docs/validation_and_uncertainty.md) rather than hidden, which is the honest
!> way to present an inverse/diagnostic tool.
module diagnostics_solver
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult, DegradationSet
    use cycle_solver, only: solve_cycle
    use degradation, only: apply_degradation
    implicit none
    private
    public :: Observation, DiagnosticWeights, DiagnosticResult
    public :: default_weights, residual, diagnose

    !> The measured quantities used to constrain the inversion.
    type :: Observation
        real(dp) :: net_power_MW = 0.0_dp
        real(dp) :: exhaust_temperature_K = 0.0_dp
        real(dp) :: fuel_flow_kg_s = 0.0_dp
        real(dp) :: T_compressor_out_K = 0.0_dp
    end type Observation

    !> Relative weights on each residual term (dimensionless; applied to the
    !> fractional error of each quantity so units do not bias the fit).
    type :: DiagnosticWeights
        real(dp) :: w_power = 1.0_dp
        real(dp) :: w_exhaust = 1.0_dp
        real(dp) :: w_fuel = 1.0_dp
        real(dp) :: w_comp_out = 1.0_dp
    end type DiagnosticWeights

    type :: DiagnosticResult
        type(DegradationSet) :: estimate
        real(dp) :: objective = huge(1.0_dp)
        integer  :: evaluations = 0
        logical  :: success = .false.
    end type DiagnosticResult

contains

    pure function default_weights() result(w)
        type(DiagnosticWeights) :: w
        w%w_power = 1.0_dp
        w%w_exhaust = 1.0_dp
        w%w_fuel = 1.0_dp
        w%w_comp_out = 0.5_dp     ! T2 is informative but often noisier
    end function default_weights

    !> Weighted sum of squared fractional residuals for a candidate degradation.
    function residual(ic_clean, d, obs, w) result(J)
        type(InputCase), intent(in)       :: ic_clean
        type(DegradationSet), intent(in)  :: d
        type(Observation), intent(in)     :: obs
        type(DiagnosticWeights), intent(in) :: w
        real(dp) :: J
        type(InputCase)   :: ic
        type(CycleResult) :: r

        ic = apply_degradation(ic_clean, d)
        r  = solve_cycle(ic)
        if (.not. r%converged) then
            J = huge(1.0_dp)
            return
        end if
        J =   w%w_power    * frac2(obs%net_power_MW,          r%net_power_MW)        &
            + w%w_exhaust  * frac2(obs%exhaust_temperature_K, r%exhaust_temperature_K) &
            + w%w_fuel     * frac2(obs%fuel_flow_kg_s,        r%fuel_flow_kg_s)       &
            + w%w_comp_out * frac2(obs%T_compressor_out_K,    r%T2_K)
    end function residual

    !> Main entry point. Returns the best-fit degradation estimate.
    function diagnose(ic_clean, obs, w, n_grid) result(dr)
        type(InputCase), intent(in)        :: ic_clean
        type(Observation), intent(in)      :: obs
        type(DiagnosticWeights), intent(in):: w
        integer, intent(in)                :: n_grid
        type(DiagnosticResult) :: dr

        ! Search bounds for each knob (physically reasonable degradation ranges).
        real(dp), parameter :: ETA_C_MAX = 0.040_dp
        real(dp), parameter :: MDOT_MAX  = 0.030_dp
        real(dp), parameter :: ETA_T_MAX = 0.030_dp
        real(dp), parameter :: DPCB_MAX  = 0.010_dp

        type(DegradationSet) :: d, best
        real(dp) :: J, Jbest
        integer  :: i1, i2, i3, i4_, evals
        real(dp) :: s1, s2, s3, s4

        best%mode = "diagnosed"
        Jbest = huge(1.0_dp)
        evals = 0

        ! ---- Coarse grid search ---------------------------------------------
        do i1 = 0, n_grid
            s1 = ETA_C_MAX * real(i1, dp) / real(n_grid, dp)
            do i2 = 0, n_grid
                s2 = MDOT_MAX * real(i2, dp) / real(n_grid, dp)
                do i3 = 0, n_grid
                    s3 = ETA_T_MAX * real(i3, dp) / real(n_grid, dp)
                    do i4_ = 0, n_grid
                        s4 = DPCB_MAX * real(i4_, dp) / real(n_grid, dp)
                        d%mode = "diagnosed"
                        d%delta_eta_compressor = s1
                        d%delta_mdot_fraction  = s2
                        d%delta_eta_turbine    = s3
                        d%delta_dP_combustor   = s4
                        J = residual(ic_clean, d, obs, w)
                        evals = evals + 1
                        if (J < Jbest) then
                            Jbest = J
                            best  = d
                        end if
                    end do
                end do
            end do
        end do

        ! ---- Coordinate-descent refinement ----------------------------------
        call refine(ic_clean, obs, w, best, Jbest, evals)

        dr%estimate    = best
        dr%objective   = Jbest
        dr%evaluations = evals
        dr%success     = (Jbest < huge(1.0_dp))
    end function diagnose

    !> Local refinement: shrink a step around the current best for each knob.
    subroutine refine(ic_clean, obs, w, best, Jbest, evals)
        type(InputCase), intent(in)        :: ic_clean
        type(Observation), intent(in)      :: obs
        type(DiagnosticWeights), intent(in):: w
        type(DegradationSet), intent(inout):: best
        real(dp), intent(inout) :: Jbest
        integer, intent(inout)  :: evals

        integer, parameter :: PASSES = 40
        real(dp) :: step, J
        type(DegradationSet) :: trial
        integer :: p, knob, dir

        step = 0.004_dp
        do p = 1, PASSES
            do knob = 1, 4
                do dir = -1, 1, 2
                    trial = best
                    select case (knob)
                    case (1); trial%delta_eta_compressor = max(0.0_dp, best%delta_eta_compressor + dir*step)
                    case (2); trial%delta_mdot_fraction  = max(0.0_dp, best%delta_mdot_fraction  + dir*step)
                    case (3); trial%delta_eta_turbine    = max(0.0_dp, best%delta_eta_turbine    + dir*step)
                    case (4); trial%delta_dP_combustor   = max(0.0_dp, best%delta_dP_combustor   + dir*step)
                    end select
                    J = residual(ic_clean, trial, obs, w)
                    evals = evals + 1
                    if (J < Jbest) then
                        Jbest = J
                        best  = trial
                    end if
                end do
            end do
            step = step * 0.7_dp     ! geometric step reduction
        end do
    end subroutine refine

    !> Squared fractional residual, guarded against zero reference.
    pure function frac2(measured, modelled) result(f2)
        real(dp), intent(in) :: measured, modelled
        real(dp) :: f2, denom
        denom = max(abs(measured), 1.0e-9_dp)
        f2 = ((modelled - measured) / denom)**2
    end function frac2

end module diagnostics_solver
