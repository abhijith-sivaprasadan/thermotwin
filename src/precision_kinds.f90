!> @file precision_kinds.f90
!> @brief Centralised definition of real/integer kinds for the whole project.
!>
!> Using a single named kind everywhere (`dp`) means the entire codebase can be
!> switched between single/double/quad precision by editing one line. This is
!> standard practice in maintainable engineering Fortran and avoids the
!> portability traps of hard-coded `real*8` or magic kind numbers.
module precision_kinds
    use, intrinsic :: iso_fortran_env, only: real32, real64, real128, int32, int64
    implicit none
    private

    !> Working real precision for all physical quantities.
    !> real64 (double precision, ~15-16 significant digits) is the right default
    !> for thermodynamic property work where small temperature differences are
    !> divided by efficiencies.
    integer, parameter, public :: dp = real64

    !> Single precision, exposed for the rare case it is genuinely wanted.
    integer, parameter, public :: sp = real32

    !> Extended precision, occasionally useful for verification cross-checks.
    integer, parameter, public :: qp = real128

    !> Default integer kind used for counters/sizes across the project.
    integer, parameter, public :: i4 = int32

    !> Long integer kind for large iteration counts (e.g. Monte Carlo draws).
    integer, parameter, public :: i8 = int64

end module precision_kinds
