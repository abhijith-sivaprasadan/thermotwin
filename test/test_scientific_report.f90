!> @file test_scientific_report.f90
!> @brief Revamp 7.0 P7 — scientific report aggregates the whole analysis stack.
!>
!> Runs the full pipeline (exergy + UQ + Sobol + limits + reconciliation) and
!> writes the report to a scratch unit, verifying it produces substantial output.
program test_scientific_report
    use precision_kinds, only: dp
    use engine_core
    use scientific_report, only: write_scientific_report
    implicit none

    integer :: failures, iu, ios, nlines
    character(len=200) :: line
    failures = 0

    block
        type(GridState) :: st
        call engine_init(st)
        st%ambient_C      = 15.0_dp
        st%PR_op          = 15.0_dp
        st%TIT_actual_K   = 1400.0_dp
        st%exhaust_K      = 850.0_dp
        st%fuel_flow_kg_s = 1.5_dp
        st%h2_lhv_mj_kg   = 50.0_dp
        st%gas_power_MW   = 18.0_dp
        st%steam_power_MW = 15.0_dp
        st%plant_power_MW = 33.0_dp
        st%combined_cycle = .true.
        st%hrsg_stack_T_K = 380.0_dp

        open(newunit=iu, status='scratch', action='readwrite')
        call write_scientific_report(iu, st)
        rewind(iu)
        nlines = 0
        do
            read(iu, '(a)', iostat=ios) line
            if (ios /= 0) exit
            nlines = nlines + 1
        end do
        close(iu)
        call expect_true("report: produces substantial multi-section output", nlines >= 25, failures)
    end block

    call finish("scientific_report", failures)

contains

    include "test_assert.inc"

end program test_scientific_report
