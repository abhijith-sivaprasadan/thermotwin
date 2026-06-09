!> @file csv_io.f90
!> @brief Transparent CSV input/output for cases and results.
!>
!> CSV is chosen deliberately: inputs and outputs are human-auditable, diffable
!> in git, and trivially consumed by the Python post-processing. The input
!> column order is fixed and documented in cases/README and docs/equations.md.
!>
!> Input header (exact order expected):
!>   case_name, ambient_T_K, ambient_P_Pa, relative_humidity,
!>   inlet_pressure_loss, mdot_air_kg_s, pressure_ratio, eta_compressor,
!>   T_turbine_inlet_K, eta_combustor, combustor_pressure_loss, LHV_J_kg,
!>   eta_turbine, exhaust_pressure_loss, eta_mechanical, eta_generator,
!>   auxiliary_load_fraction, degradation_mode
module csv_io
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult, NAME_LEN, TAG_LEN
    implicit none
    private
    public :: read_input_cases, write_results, write_results_header, write_result_row
    public :: N_INPUT_COLUMNS

    integer, parameter :: N_INPUT_COLUMNS = 18
    integer, parameter :: MAX_LINE = 4096
    integer, parameter :: MAX_FIELDS = 64

contains

    !-------------------------------------------------------------------
    ! Reading
    !-------------------------------------------------------------------

    !> Read all data rows of an input CSV into an allocatable array of cases.
    subroutine read_input_cases(filename, cases, n_cases, ok)
        character(len=*), intent(in) :: filename
        type(InputCase), allocatable, intent(out) :: cases(:)
        integer, intent(out) :: n_cases
        logical, intent(out) :: ok

        integer :: unit, ios, n_rows, irow
        character(len=MAX_LINE) :: line
        type(InputCase), allocatable :: tmp(:)

        ok = .false.
        n_cases = 0

        open(newunit=unit, file=filename, status='old', action='read', iostat=ios)
        if (ios /= 0) then
            write(*, '(A)') "ERROR: cannot open input file: "//trim(filename)
            return
        end if

        ! First pass: count non-blank data rows. The first non-comment line is
        ! the header; everything after it (that is not blank/comment) is data.
        n_rows = 0
        block
            logical :: header_seen
            header_seen = .false.
            do
                read(unit, '(A)', iostat=ios) line
                if (ios /= 0) exit
                if (is_blank_or_comment(line)) cycle
                if (.not. header_seen) then
                    header_seen = .true.   ! consume the header line
                    cycle
                end if
                n_rows = n_rows + 1
            end do
        end block

        if (n_rows == 0) then
            write(*, '(A)') "ERROR: no data rows in "//trim(filename)
            close(unit)
            return
        end if

        allocate(tmp(n_rows))

        ! Second pass: parse data rows (same header-skipping logic).
        rewind(unit)
        irow = 0
        block
            logical :: header_seen
            header_seen = .false.
            do
                read(unit, '(A)', iostat=ios) line
                if (ios /= 0) exit
                if (is_blank_or_comment(line)) cycle
                if (.not. header_seen) then
                    header_seen = .true.   ! consume the header line
                    cycle
                end if
                irow = irow + 1
                call parse_case_line(line, tmp(irow))
            end do
        end block
        close(unit)

        call move_alloc(tmp, cases)
        n_cases = n_rows
        ok = .true.
    end subroutine read_input_cases

    !> Parse one CSV data line into an InputCase by column position.
    subroutine parse_case_line(line, ic)
        character(len=*), intent(in) :: line
        type(InputCase), intent(out) :: ic
        character(len=MAX_LINE) :: fields(MAX_FIELDS)
        integer :: nf

        call split_csv(line, fields, nf)
        if (nf < N_INPUT_COLUMNS) then
            write(*, '(A,I0,A,I0)') "WARNING: row has ", nf, &
                " fields; expected ", N_INPUT_COLUMNS
        end if

        ic%case_name              = adjustl_name(get_field(fields, nf, 1))
        ic%ambient_T_K            = to_real(get_field(fields, nf, 2))
        ic%ambient_P_Pa           = to_real(get_field(fields, nf, 3))
        ic%relative_humidity      = to_real(get_field(fields, nf, 4))
        ic%inlet_pressure_loss    = to_real(get_field(fields, nf, 5))
        ic%mdot_air_kg_s          = to_real(get_field(fields, nf, 6))
        ic%pressure_ratio         = to_real(get_field(fields, nf, 7))
        ic%eta_compressor         = to_real(get_field(fields, nf, 8))
        ic%T_turbine_inlet_K      = to_real(get_field(fields, nf, 9))
        ic%eta_combustor          = to_real(get_field(fields, nf, 10))
        ic%combustor_pressure_loss= to_real(get_field(fields, nf, 11))
        ic%LHV_J_kg               = to_real(get_field(fields, nf, 12))
        ic%eta_turbine            = to_real(get_field(fields, nf, 13))
        ic%exhaust_pressure_loss  = to_real(get_field(fields, nf, 14))
        ic%eta_mechanical         = to_real(get_field(fields, nf, 15))
        ic%eta_generator          = to_real(get_field(fields, nf, 16))
        ic%auxiliary_load_fraction= to_real(get_field(fields, nf, 17))
        ic%degradation_mode       = adjustl_tag(get_field(fields, nf, 18))
    end subroutine parse_case_line

    !-------------------------------------------------------------------
    ! Writing
    !-------------------------------------------------------------------

    !> Write the results header to an open unit.
    subroutine write_results_header(unit)
        integer, intent(in) :: unit
        write(unit, '(A)') &
            "case_name,degradation_mode,T1_K,P1_Pa,T2_K,P2_Pa,T3_K,P3_Pa,T4_K,P4_Pa,"// &
            "w_compressor_kJ_kg,w_turbine_kJ_kg,w_net_kJ_kg,fuel_air_ratio,fuel_flow_kg_s,"// &
            "mdot_air_kg_s,mdot_gas_kg_s,power_compressor_MW,power_turbine_MW,gross_power_MW,"// &
            "net_power_MW,heat_input_MW,thermal_efficiency,heat_rate_kJ_kWh,"// &
            "exhaust_temperature_K,exhaust_energy_MW,specific_power_kW_per_kgps,converged,status"
    end subroutine write_results_header

    !> Write one result row to an open unit.
    subroutine write_result_row(unit, r)
        integer, intent(in) :: unit
        type(CycleResult), intent(in) :: r
        character(len=8) :: conv
        if (r%converged) then
            conv = "1"
        else
            conv = "0"
        end if
        write(unit, '(A,",",A,25(",",ES16.8),",",A,",",A)') &
            trim(r%case_name), trim(r%degradation_mode), &
            r%T1_K, r%P1_Pa, r%T2_K, r%P2_Pa, r%T3_K, r%P3_Pa, r%T4_K, r%P4_Pa, &
            r%w_compressor_J_kg/1.0e3_dp, r%w_turbine_J_kg/1.0e3_dp, r%w_net_specific_J_kg/1.0e3_dp, &
            r%fuel_air_ratio, r%fuel_flow_kg_s, r%mdot_air_kg_s, r%mdot_gas_kg_s, &
            r%power_compressor_MW, r%power_turbine_MW, r%gross_power_MW, r%net_power_MW, &
            r%heat_input_MW, r%thermal_efficiency, r%heat_rate_kJ_kWh, &
            r%exhaust_temperature_K, r%exhaust_energy_MW, r%specific_power_kW_per_kgps, &
            trim(conv), trim(r%status_message)
    end subroutine write_result_row

    !> Convenience: write a whole array of results to a new file.
    subroutine write_results(filename, results, n)
        character(len=*), intent(in) :: filename
        type(CycleResult), intent(in) :: results(:)
        integer, intent(in) :: n
        integer :: unit, ios, i
        open(newunit=unit, file=filename, status='replace', action='write', iostat=ios)
        if (ios /= 0) then
            write(*, '(A)') "ERROR: cannot write results file: "//trim(filename)
            return
        end if
        call write_results_header(unit)
        do i = 1, n
            call write_result_row(unit, results(i))
        end do
        close(unit)
        write(*, '(A,I0,A)') "  wrote ", n, " rows -> "//trim(filename)
    end subroutine write_results

    !-------------------------------------------------------------------
    ! Low-level string helpers
    !-------------------------------------------------------------------

    !> Split a comma-separated line into trimmed fields.
    subroutine split_csv(line, fields, nf)
        character(len=*), intent(in) :: line
        character(len=*), intent(out) :: fields(:)
        integer, intent(out) :: nf
        integer :: i, start, n
        character(len=1) :: c

        nf = 0
        start = 1
        n = len_trim(line)
        do i = 1, n
            c = line(i:i)
            if (c == ',') then
                nf = nf + 1
                if (nf <= size(fields)) fields(nf) = adjustl(line(start:i-1))
                start = i + 1
            end if
        end do
        ! last field
        nf = nf + 1
        if (nf <= size(fields)) fields(nf) = adjustl(line(start:max(start,n)))
    end subroutine split_csv

    pure function get_field(fields, nf, idx) result(s)
        character(len=*), intent(in) :: fields(:)
        integer, intent(in) :: nf, idx
        character(len=MAX_LINE) :: s
        if (idx <= nf) then
            s = fields(idx)
        else
            s = ""
        end if
    end function get_field

    !> Convert a string to real; returns 0 on blank, stops on garbage.
    function to_real(s) result(x)
        character(len=*), intent(in) :: s
        real(dp) :: x
        integer :: ios
        character(len=:), allocatable :: t
        t = trim(adjustl(s))
        if (len(t) == 0) then
            x = 0.0_dp
            return
        end if
        read(t, *, iostat=ios) x
        if (ios /= 0) then
            write(*, '(A)') "FATAL: could not parse number from '"//t//"'"
            error stop 1
        end if
    end function to_real

    pure function adjustl_name(s) result(out)
        character(len=*), intent(in) :: s
        character(len=NAME_LEN) :: out
        out = trim(adjustl(s))
    end function adjustl_name

    pure function adjustl_tag(s) result(out)
        character(len=*), intent(in) :: s
        character(len=TAG_LEN) :: out
        out = trim(adjustl(s))
    end function adjustl_tag

    !> True for blank lines or lines whose first non-space char is '#' or '!'.
    pure function is_blank_or_comment(line) result(yes)
        character(len=*), intent(in) :: line
        logical :: yes
        character(len=:), allocatable :: t
        t = adjustl(line)
        if (len_trim(t) == 0) then
            yes = .true.
        else if (t(1:1) == '#' .or. t(1:1) == '!') then
            yes = .true.
        else
            yes = .false.
        end if
    end function is_blank_or_comment

end module csv_io
