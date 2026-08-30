!> [7.0-P4] Global (variance-based / Sobol) sensitivity of the exergy KPIs.
!>
!> Uses the Saltelli sampling scheme with Jansen estimators to attribute the
!> variance of a chosen exergy KPI (rational efficiency or total destruction) to
!> each uncertain input — ambient T, turbine-inlet T, exhaust T, fuel flow, and
!> pressure ratio. First-order indices S1 capture each input's direct effect;
!> total-effect indices ST also include its interactions. The dominant driver is
!> the input with the largest ST. Deterministic seed for reproducibility.
module exergy_sobol
    use precision_kinds, only: dp
    use engine_state,    only: GridState
    use exergy,          only: ExergyResult, compute_exergy
    implicit none
    private
    public :: SobolResult, run_exergy_sobol
    integer, parameter, public :: SOBOL_NIN = 5   ! ambient, TIT, exhaust, fuel, PR

    real(dp), parameter :: PI = 3.141592653589793_dp

    type :: SobolResult
        integer  :: n_samples = 0
        real(dp) :: var_Y     = 0.0_dp
        real(dp) :: S1(SOBOL_NIN) = 0.0_dp   ! first-order indices
        real(dp) :: ST(SOBOL_NIN) = 0.0_dp   ! total-effect indices
        integer  :: dominant  = 0            ! input index with largest ST
    end type SobolResult

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

    function gauss() result(z)
        real(dp) :: u1, u2, z
        call random_number(u1)
        call random_number(u2)
        u1 = max(u1, 1.0e-12_dp)
        z  = sqrt(-2.0_dp * log(u1)) * cos(2.0_dp * PI * u2)
    end function gauss

    !> Evaluate the target KPI for one input vector p = [ambient,TIT,exhaust,fuel,PR].
    function eval_kpi(st, p, kpi) result(y)
        type(GridState), intent(in) :: st
        real(dp),        intent(in) :: p(SOBOL_NIN)
        integer,         intent(in) :: kpi
        real(dp) :: y
        type(GridState)    :: s
        type(ExergyResult) :: ex
        s = st
        s%ambient_C      = p(1)
        s%TIT_actual_K   = p(2)
        s%exhaust_K      = p(3)
        s%fuel_flow_kg_s = max(1.0e-6_dp, p(4))
        s%PR_op          = max(1.0_dp,     p(5))
        call compute_exergy(s, ex)
        select case (kpi)
        case (2);     y = ex%dest_total
        case default; y = ex%eta_II
        end select
    end function eval_kpi

    !> Saltelli/Jansen Sobol indices. kpi: 1 = rational efficiency, 2 = total destruction.
    subroutine run_exergy_sobol(st, sig, n, kpi, r)
        type(GridState),   intent(in)  :: st
        real(dp),          intent(in)  :: sig(SOBOL_NIN)
        integer,           intent(in)  :: n, kpi
        type(SobolResult), intent(out) :: r
        real(dp) :: base(SOBOL_NIN), c(SOBOL_NIN), mu, v, sumT, sum1
        real(dp), allocatable :: A(:,:), B(:,:), yA(:), yB(:), yC(:)
        integer  :: i, j, m

        m = max(2, n)
        base = [st%ambient_C, st%TIT_actual_K, st%exhaust_K, st%fuel_flow_kg_s, st%PR_op]
        allocate(A(m, SOBOL_NIN), B(m, SOBOL_NIN), yA(m), yB(m), yC(m))
        call seed_rng(20260615)
        do j = 1, m
            do i = 1, SOBOL_NIN
                A(j, i) = base(i) + sig(i) * gauss()
                B(j, i) = base(i) + sig(i) * gauss()
            end do
            yA(j) = eval_kpi(st, A(j, :), kpi)
            yB(j) = eval_kpi(st, B(j, :), kpi)
        end do

        mu = (sum(yA) + sum(yB)) / real(2 * m, dp)
        v  = (sum((yA - mu)**2) + sum((yB - mu)**2)) / real(2 * m - 1, dp)
        r%var_Y = v

        do i = 1, SOBOL_NIN
            do j = 1, m
                c = A(j, :);  c(i) = B(j, i)
                yC(j) = eval_kpi(st, c, kpi)
            end do
            sumT = sum((yA - yC)**2)                                  ! Jansen total
            sum1 = sum((yB - yC)**2)                                  ! Jansen first-order
            r%ST(i) = sumT / (2.0_dp * real(m, dp)) / max(v, 1.0e-30_dp)
            r%S1(i) = (v - sum1 / (2.0_dp * real(m, dp))) / max(v, 1.0e-30_dp)
        end do
        r%n_samples = m
        r%dominant  = maxloc(r%ST, dim=1)
        deallocate(A, B, yA, yB, yC)
    end subroutine run_exergy_sobol

end module exergy_sobol
