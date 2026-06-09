!> @file utilities.f90
!> @brief Cross-cutting helpers: assertions, simple statistics, interpolation,
!>        a controllable Gaussian RNG, and string helpers.
!>
!> Everything here is deliberately dependency-free so it can be used by any
!> module without creating circular `use` chains.
module utilities
    use precision_kinds, only: dp, i4, i8
    use constants, only: TINY_DP, PI
    implicit none
    private

    public :: assert_positive, assert_in_range, safe_divide
    public :: mean, stddev, percentile
    public :: linear_interp
    public :: seed_rng, gaussian_random, uniform_random
    public :: to_upper, itoa

contains

    !-------------------------------------------------------------------
    ! Assertions / guards
    !-------------------------------------------------------------------

    !> Stop with a clear message if `x` is not strictly positive.
    subroutine assert_positive(x, name)
        real(dp), intent(in) :: x
        character(len=*), intent(in) :: name
        if (x <= 0.0_dp) then
            write(*, '(A)') "FATAL: expected positive value for '"//trim(name)//"'."
            error stop 1
        end if
    end subroutine assert_positive

    !> Stop if `x` falls outside [lo, hi].
    subroutine assert_in_range(x, lo, hi, name)
        real(dp), intent(in) :: x, lo, hi
        character(len=*), intent(in) :: name
        if (x < lo .or. x > hi) then
            write(*, '(A,3(1x,ES12.4))') "FATAL: '"//trim(name)// &
                "' out of range. value, lo, hi =", x, lo, hi
            error stop 1
        end if
    end subroutine assert_in_range

    !> Division that guards against a vanishing denominator.
    pure function safe_divide(numer, denom) result(q)
        real(dp), intent(in) :: numer, denom
        real(dp) :: q
        if (abs(denom) < TINY_DP) then
            q = sign(huge(1.0_dp), numer*denom)
        else
            q = numer / denom
        end if
    end function safe_divide

    !-------------------------------------------------------------------
    ! Simple descriptive statistics (used by uncertainty analysis)
    !-------------------------------------------------------------------

    pure function mean(x) result(m)
        real(dp), intent(in) :: x(:)
        real(dp) :: m
        if (size(x) == 0) then
            m = 0.0_dp
        else
            m = sum(x) / real(size(x), dp)
        end if
    end function mean

    pure function stddev(x) result(s)
        real(dp), intent(in) :: x(:)
        real(dp) :: s, m
        integer :: n
        n = size(x)
        if (n < 2) then
            s = 0.0_dp
            return
        end if
        m = mean(x)
        s = sqrt(sum((x - m)**2) / real(n - 1, dp))   ! sample standard deviation
    end function stddev

    !> Linear-interpolated percentile (p in [0,100]). Input need not be sorted.
    function percentile(x, p) result(val)
        real(dp), intent(in) :: x(:)
        real(dp), intent(in) :: p
        real(dp) :: val
        real(dp), allocatable :: s(:)
        real(dp) :: rank, frac
        integer :: n, lo

        n = size(x)
        if (n == 0) then
            val = 0.0_dp
            return
        else if (n == 1) then
            val = x(1)
            return
        end if

        allocate(s, source=x)
        call sort_in_place(s)

        rank = (p / 100.0_dp) * real(n - 1, dp) + 1.0_dp   ! 1-based fractional rank
        lo   = int(rank)
        frac = rank - real(lo, dp)
        if (lo >= n) then
            val = s(n)
        else
            val = s(lo) + frac * (s(lo + 1) - s(lo))
        end if
        deallocate(s)
    end function percentile

    !> In-place ascending insertion sort (n is small for our use cases).
    pure subroutine sort_in_place(a)
        real(dp), intent(inout) :: a(:)
        integer :: i, j
        real(dp) :: key
        do i = 2, size(a)
            key = a(i)
            j = i - 1
            do while (j >= 1)
                if (a(j) <= key) exit
                a(j + 1) = a(j)
                j = j - 1
            end do
            a(j + 1) = key
        end do
    end subroutine sort_in_place

    !-------------------------------------------------------------------
    ! 1-D linear interpolation (for future property tables / maps)
    !-------------------------------------------------------------------

    !> Interpolate y(x) given monotonically increasing xs, ys. Clamps at ends.
    pure function linear_interp(xq, xs, ys) result(yq)
        real(dp), intent(in) :: xq
        real(dp), intent(in) :: xs(:), ys(:)
        real(dp) :: yq
        integer :: i, n
        n = size(xs)
        if (n == 0) then
            yq = 0.0_dp
            return
        else if (n == 1 .or. xq <= xs(1)) then
            yq = ys(1)
            return
        else if (xq >= xs(n)) then
            yq = ys(n)
            return
        end if
        do i = 1, n - 1
            if (xq >= xs(i) .and. xq <= xs(i + 1)) then
                yq = ys(i) + (ys(i + 1) - ys(i)) * (xq - xs(i)) / (xs(i + 1) - xs(i))
                return
            end if
        end do
        yq = ys(n)
    end function linear_interp

    !-------------------------------------------------------------------
    ! Random number generation
    !-------------------------------------------------------------------

    !> Seed the intrinsic RNG deterministically so Monte Carlo runs are
    !> reproducible. Pass the same `seed` to reproduce a study exactly.
    subroutine seed_rng(seed)
        integer, intent(in) :: seed
        integer :: n
        integer, allocatable :: seed_array(:)
        integer :: i
        call random_seed(size=n)
        allocate(seed_array(n))
        do i = 1, n
            seed_array(i) = seed + 37*i      ! simple deterministic spread
        end do
        call random_seed(put=seed_array)
        deallocate(seed_array)
    end subroutine seed_rng

    !> Uniform random in [0,1).
    function uniform_random() result(u)
        real(dp) :: u
        call random_number(u)
    end function uniform_random

    !> Standard-normal sample via Box-Muller. Returns N(mu, sigma).
    function gaussian_random(mu, sigma) result(z)
        real(dp), intent(in) :: mu, sigma
        real(dp) :: z
        real(dp) :: u1, u2
        call random_number(u1)
        call random_number(u2)
        ! guard against log(0)
        if (u1 < TINY_DP) u1 = TINY_DP
        z = sqrt(-2.0_dp * log(u1)) * cos(2.0_dp * PI * u2)
        z = mu + sigma * z
    end function gaussian_random

    !-------------------------------------------------------------------
    ! Small string helpers
    !-------------------------------------------------------------------

    pure function to_upper(s) result(u)
        character(len=*), intent(in) :: s
        character(len=len(s)) :: u
        integer :: i, code
        do i = 1, len(s)
            code = iachar(s(i:i))
            if (code >= iachar('a') .and. code <= iachar('z')) then
                u(i:i) = achar(code - 32)
            else
                u(i:i) = s(i:i)
            end if
        end do
    end function to_upper

    !> Integer -> left-trimmed string.
    pure function itoa(i) result(s)
        integer, intent(in) :: i
        character(len=:), allocatable :: s
        character(len=32) :: buf
        write(buf, '(I0)') i
        s = trim(buf)
    end function itoa

end module utilities
