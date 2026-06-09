!> @file sensitivity_driver.f90
!> @brief Batch evaluation helpers: solve arrays of cases, and build in-memory
!>        parameter sweeps without needing a CSV per sweep.
!>
!> `run_cases` is the workhorse used by the main "run" mode. `sweep_parameter`
!> generates a one-dimensional sweep of a single InputCase field, which is handy
!> for programmatic studies and for the unit tests.
module sensitivity_driver
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult
    use cycle_solver, only: solve_cycle
    implicit none
    private
    public :: run_cases, sweep_parameter

contains

    !> Solve every case in `cases`, returning a matching array of results.
    subroutine run_cases(cases, results)
        type(InputCase), intent(in)  :: cases(:)
        type(CycleResult), allocatable, intent(out) :: results(:)
        integer :: i
        allocate(results(size(cases)))
        do i = 1, size(cases)
            results(i) = solve_cycle(cases(i))
        end do
    end subroutine run_cases

    !> Sweep one named field of a base case over [v_lo, v_hi] in n points.
    !> Recognised fields: "ambient_T_K", "pressure_ratio", "T_turbine_inlet_K",
    !> "eta_compressor", "eta_turbine", "mdot_air_kg_s".
    subroutine sweep_parameter(base, field, v_lo, v_hi, n, results)
        type(InputCase), intent(in) :: base
        character(len=*), intent(in) :: field
        real(dp), intent(in) :: v_lo, v_hi
        integer, intent(in)  :: n
        type(CycleResult), allocatable, intent(out) :: results(:)
        integer :: i
        real(dp) :: v
        type(InputCase) :: ic
        character(len=64) :: label

        allocate(results(n))
        do i = 1, n
            ic = base
            if (n > 1) then
                v = v_lo + (v_hi - v_lo) * real(i - 1, dp) / real(n - 1, dp)
            else
                v = v_lo
            end if
            select case (trim(field))
            case ("ambient_T_K");       ic%ambient_T_K = v
            case ("pressure_ratio");    ic%pressure_ratio = v
            case ("T_turbine_inlet_K"); ic%T_turbine_inlet_K = v
            case ("eta_compressor");    ic%eta_compressor = v
            case ("eta_turbine");       ic%eta_turbine = v
            case ("mdot_air_kg_s");     ic%mdot_air_kg_s = v
            case default
                write(*, '(A)') "WARNING: unknown sweep field '"//trim(field)//"'"
            end select
            write(label, '(A,"=",F0.4)') trim(field), v
            ic%case_name = trim(label)
            results(i) = solve_cycle(ic)
        end do
    end subroutine sweep_parameter

end module sensitivity_driver
