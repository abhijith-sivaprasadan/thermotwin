!> [7.0-P4] Uncertainty quantification for the exergy analysis.
!>
!> Monte-Carlo propagation of 1-sigma input/measurement uncertainty (ambient,
!> turbine-inlet & exhaust temperature, fuel flow, pressure ratio) through the
!> second-law accounting in `exergy`, producing mean ± standard deviation and a
!> 95% interval on the rational efficiency and on exergy destruction. This puts
!> defensible error bars on the headline thermodynamic results — i.e. the
!> analysis reports not just a number, but how well that number is known.
!>
!> Scope: this propagates uncertainty through the exergy *accounting* given the
!> state; a full-cycle UQ (re-solving the cycle each sample) is the broader P4
!> item. The RNG is seeded deterministically so results are reproducible.
module exergy_uq
    use precision_kinds, only: dp
    use engine_state,    only: GridState
    use exergy,          only: ExergyResult, compute_exergy
    implicit none
    private
    public :: ExergyUQ, run_exergy_uq

    real(dp), parameter :: PI = 3.141592653589793_dp

    type :: ExergyUQ
        integer  :: n_samples       = 0
        real(dp) :: eta_II_mean     = 0.0_dp   ! rational efficiency [-]
        real(dp) :: eta_II_std      = 0.0_dp
        real(dp) :: eta_II_lo95     = 0.0_dp
        real(dp) :: eta_II_hi95     = 0.0_dp
        real(dp) :: dest_comb_mean  = 0.0_dp   ! combustor destruction [kW]
        real(dp) :: dest_comb_std   = 0.0_dp
        real(dp) :: dest_total_mean = 0.0_dp   ! total destruction [kW]
        real(dp) :: dest_total_std  = 0.0_dp
    end type ExergyUQ

contains

    subroutine seed_rng(seed)
        integer, intent(in) :: seed
        integer :: m, i
        integer, allocatable :: s(:)
        call random_seed(size = m)
        allocate(s(m))
        do i = 1, m
            s(i) = seed + 37 * i
        end do
        call random_seed(put = s)
        deallocate(s)
    end subroutine seed_rng

    !> One standard-normal draw (Box-Muller).
    function gauss() result(z)
        real(dp) :: u1, u2, z
        call random_number(u1)
        call random_number(u2)
        u1 = max(u1, 1.0e-12_dp)
        z  = sqrt(-2.0_dp * log(u1)) * cos(2.0_dp * PI * u2)
    end function gauss

    pure function std_from(s1, s2, n) result(sd)
        real(dp), intent(in) :: s1, s2
        integer,  intent(in) :: n
        real(dp) :: sd, var
        var = (s2 - s1 * s1 / real(n, dp)) / real(max(1, n - 1), dp)
        sd  = sqrt(max(0.0_dp, var))
    end function std_from

    !> Monte-Carlo UQ: perturb the listed inputs by their 1-sigma uncertainty,
    !> re-run the exergy analysis n times, and accumulate statistics.
    subroutine run_exergy_uq(st, sig_ambient, sig_TIT, sig_exhaust, sig_fuel, sig_PR, n, r)
        type(GridState),   intent(in)  :: st
        real(dp),          intent(in)  :: sig_ambient, sig_TIT, sig_exhaust, sig_fuel, sig_PR
        integer,           intent(in)  :: n
        type(ExergyUQ),    intent(out) :: r
        type(GridState)    :: s
        type(ExergyResult) :: ex
        integer  :: i, m
        real(dp) :: e, dc, dt
        real(dp) :: se, se2, sdc, sdc2, sdt, sdt2

        m  = max(1, n)
        call seed_rng(20260615)
        se = 0.0_dp; se2 = 0.0_dp; sdc = 0.0_dp; sdc2 = 0.0_dp; sdt = 0.0_dp; sdt2 = 0.0_dp
        do i = 1, m
            s = st
            s%ambient_C      = st%ambient_C    + sig_ambient * gauss()
            s%TIT_actual_K   = st%TIT_actual_K + sig_TIT     * gauss()
            s%exhaust_K      = st%exhaust_K    + sig_exhaust * gauss()
            s%fuel_flow_kg_s = max(1.0e-6_dp, st%fuel_flow_kg_s + sig_fuel * gauss())
            s%PR_op          = max(1.0_dp,     st%PR_op        + sig_PR   * gauss())
            call compute_exergy(s, ex)
            e  = ex%eta_II;   dc = ex%dest_comb;   dt = ex%dest_total
            se  = se  + e;    se2  = se2  + e  * e
            sdc = sdc + dc;   sdc2 = sdc2 + dc * dc
            sdt = sdt + dt;   sdt2 = sdt2 + dt * dt
        end do

        r%n_samples       = m
        r%eta_II_mean     = se / real(m, dp)
        r%eta_II_std      = std_from(se, se2, m)
        r%eta_II_lo95     = r%eta_II_mean - 1.96_dp * r%eta_II_std
        r%eta_II_hi95     = r%eta_II_mean + 1.96_dp * r%eta_II_std
        r%dest_comb_mean  = sdc / real(m, dp)
        r%dest_comb_std   = std_from(sdc, sdc2, m)
        r%dest_total_mean = sdt / real(m, dp)
        r%dest_total_std  = std_from(sdt, sdt2, m)
    end subroutine run_exergy_uq

end module exergy_uq
