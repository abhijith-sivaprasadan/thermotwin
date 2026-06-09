! test_assert.inc
! Shared assertion helpers, textually included after `contains` in each test
! program. Kept as an include (not a module) so each test stays a single
! self-contained program that fpm can build and run independently.

    !> Fail (increment counter) if |got - expect| > tol.
    subroutine expect_near(name, got, expect, tol, failures)
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: got, expect, tol
        integer, intent(inout) :: failures
        if (abs(got - expect) > tol) then
            write(*, '(A,3(1x,ES14.6))') "  [FAIL] "//name//"  got/expect/tol:", &
                got, expect, tol
            failures = failures + 1
        else
            write(*, '(A)') "  [ok]   "//name
        end if
    end subroutine expect_near

    !> Fail if the logical condition is not true.
    subroutine expect_true(name, cond, failures)
        character(len=*), intent(in) :: name
        logical, intent(in) :: cond
        integer, intent(inout) :: failures
        if (.not. cond) then
            write(*, '(A)') "  [FAIL] "//name
            failures = failures + 1
        else
            write(*, '(A)') "  [ok]   "//name
        end if
    end subroutine expect_true

    !> Print a summary line and stop non-zero if any test failed.
    subroutine finish(suite, failures)
        character(len=*), intent(in) :: suite
        integer, intent(in) :: failures
        write(*, '(A)') ""
        if (failures == 0) then
            write(*, '(A)') "PASS: "//suite
        else
            write(*, '(A,I0,A)') "FAIL: "//suite//" (", failures, " failing checks)"
            error stop 1
        end if
    end subroutine finish
