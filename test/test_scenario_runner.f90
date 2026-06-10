!> @file test_scenario_runner.f90
!> @brief Tests the scenario engine: parsing, event application, assertion
!>        evaluation (both passing and failing), and parse-error rejection.
program test_scenario_runner
    use precision_kinds, only: dp
    use scenario_runner, only: Scenario, scenario_load, scenario_run
    implicit none
    integer :: failures
    character(len=*), parameter :: TMP = "output/_test_scenario_tmp.scn"
    failures = 0

    ! --- A well-formed scenario parses, runs, and passes its assertions. ---
    block
        type(Scenario) :: sc
        integer :: scn_failures
        logical :: ok
        call write_file(TMP, &
            "name unit_smoke" // new_line('a') // &
            "duration 2" // new_line('a') // &
            "dt 0.25" // new_line('a') // &
            "at 0.0 set demand_MW 40   # inline comment" // new_line('a') // &
            "at 1.0 assert_near demand_MW 40 0.001" // new_line('a') // &
            "at 1.5 assert_above gas_capacity_MW 5" // new_line('a') // &
            "at 1.5 assert_below UFLS_stage 0.5" // new_line('a'))
        call scenario_load(TMP, sc, ok)
        call expect_true("well-formed scenario parses", ok, failures)
        call expect_true("all four events captured", sc%n_events == 4, failures)
        call expect_near("duration parsed", sc%duration_s, 2.0_dp, 1.0e-12_dp, failures)
        if (ok) then
            call scenario_run(sc, scn_failures)
            call expect_true("passing scenario reports zero failures", scn_failures == 0, failures)
        end if
    end block

    ! --- A failing assertion is actually detected (the checker checks). ---
    block
        type(Scenario) :: sc
        integer :: scn_failures
        logical :: ok
        call write_file(TMP, &
            "name unit_must_fail" // new_line('a') // &
            "duration 1" // new_line('a') // &
            "at 0.5 assert_above demand_MW 1000" // new_line('a'))
        call scenario_load(TMP, sc, ok)
        call expect_true("failing scenario parses", ok, failures)
        if (ok) then
            call scenario_run(sc, scn_failures)
            call expect_true("impossible assertion is caught", scn_failures == 1, failures)
        end if
    end block

    ! --- Unknown directives are rejected with ok=.false. ---
    block
        type(Scenario) :: sc
        logical :: ok
        call write_file(TMP, &
            "name bad" // new_line('a') // &
            "frobnicate 12" // new_line('a'))
        call scenario_load(TMP, sc, ok)
        call expect_true("unknown directive rejected", .not. ok, failures)

        call write_file(TMP, &
            "at 1.0 assert_near frequency_Hz" // new_line('a'))
        call scenario_load(TMP, sc, ok)
        call expect_true("truncated assertion rejected", .not. ok, failures)
    end block

    call cleanup(TMP)
    call finish("scenario_runner", failures)

contains

    subroutine write_file(path, content)
        character(len=*), intent(in) :: path, content
        integer :: unit
        open(newunit=unit, file=path, status='replace', action='write')
        write(unit, '(A)') content
        close(unit)
    end subroutine write_file

    subroutine cleanup(path)
        character(len=*), intent(in) :: path
        integer :: unit, ios
        open(newunit=unit, file=path, status='old', iostat=ios)
        if (ios == 0) close(unit, status='delete')
    end subroutine cleanup

    include "test_assert.inc"

end program test_scenario_runner
