!> @file test_scenario_runner.f90
!> @brief Tests the scenario engine: parsing, event application, assertion
!>        evaluation (both passing and failing), and parse-error rejection.
program test_scenario_runner
    use precision_kinds, only: dp
    use scenario_runner, only: Scenario, ScenarioComparison, SCENARIO_TRACE_N, &
        scenario_load, scenario_run, scenario_compare
    implicit none
    integer :: failures
    character(len=*), parameter :: TMP = "output/_test_scenario_tmp.scn"
    character(len=*), parameter :: TMP_B = "output/_test_scenario_tmp_b.scn"
    character(len=*), parameter :: TMP_REC = "output/_test_scenario_record.csv"
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

    ! --- Flight recorder writes a compact state CSV without crashing. ---
    block
        type(Scenario) :: sc
        integer :: scn_failures
        logical :: ok, exists
        integer :: unit, ios
        character(len=512) :: header

        call write_file(TMP, &
            "name recorder_smoke" // new_line('a') // &
            "duration 1" // new_line('a') // &
            "dt 0.25" // new_line('a') // &
            "at 0.0 set auto_balance 0" // new_line('a') // &
            "at 0.5 assert_near frequency_Hz 50.0 0.5" // new_line('a'))
        call scenario_load(TMP, sc, ok)
        call expect_true("recorder scenario parses", ok, failures)
        if (ok) then
            call scenario_run(sc, scn_failures, TMP_REC)
            call expect_true("recorded scenario reports zero failures", scn_failures == 0, failures)
            inquire(file=TMP_REC, exist=exists)
            call expect_true("recorded CSV exists", exists, failures)
            if (exists) then
                open(newunit=unit, file=TMP_REC, status='old', action='read', iostat=ios)
                call expect_true("recorded CSV opens", ios == 0, failures)
                if (ios == 0) then
                    read(unit, '(A)', iostat=ios) header
                    call expect_true("recorded CSV has frequency header", &
                        index(header, "frequency_Hz") > 0, failures)
                    close(unit)
                end if
            end if
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

    ! --- Scenario comparison records two deterministic traces and summary deltas. ---
    block
        type(Scenario) :: sc_a, sc_b
        type(ScenarioComparison) :: cmp
        logical :: ok_a, ok_b
        call write_file(TMP, &
            "name compare_A" // new_line('a') // &
            "duration 6" // new_line('a') // &
            "dt 0.25" // new_line('a') // &
            "at 0.0 set auto_balance 1" // new_line('a') // &
            "at 1.0 set demand_MW 45" // new_line('a'))
        call write_file(TMP_B, &
            "name compare_B_mpc" // new_line('a') // &
            "duration 6" // new_line('a') // &
            "dt 0.25" // new_line('a') // &
            "at 0.0 set auto_balance 1" // new_line('a') // &
            "at 0.0 set mpc_active 1" // new_line('a') // &
            "at 1.0 set demand_MW 45" // new_line('a'))
        call scenario_load(TMP, sc_a, ok_a)
        call scenario_load(TMP_B, sc_b, ok_b)
        call expect_true("comparison scenario A parses", ok_a, failures)
        call expect_true("comparison scenario B parses", ok_b, failures)
        if (ok_a .and. ok_b) then
            call scenario_compare(sc_a, sc_b, cmp)
            call expect_true("comparison is ready", cmp%ready, failures)
            call expect_true("trace A has samples", cmp%a%n > 2, failures)
            call expect_true("trace B has samples", cmp%b%n > 2, failures)
            call expect_true("trace A respects sample cap", cmp%a%n <= SCENARIO_TRACE_N, failures)
            call expect_true("trace B respects sample cap", cmp%b%n <= SCENARIO_TRACE_N, failures)
            call expect_true("trace names preserved", trim(cmp%a%name) == "compare_A" .and. &
                trim(cmp%b%name) == "compare_B_mpc", failures)
            call expect_near("trace A ends at duration", cmp%a%time_s(cmp%a%n), &
                cmp%a%duration_s, cmp%a%dt_s + 1.0e-9_dp, failures)
            call expect_near("trace B ends at duration", cmp%b%time_s(cmp%b%n), &
                cmp%b%duration_s, cmp%b%dt_s + 1.0e-9_dp, failures)
            call expect_true("comparison deltas are finite", &
                abs(cmp%delta_final_margin_usd_h) < huge(1.0_dp) .and. &
                abs(cmp%delta_max_abs_imbalance_MW) < huge(1.0_dp), failures)
        end if
    end block

    call cleanup(TMP)
    call cleanup(TMP_B)
    call cleanup(TMP_REC)
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
