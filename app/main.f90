!> @file main.f90
!> @brief ThermoTwin-F command-line driver.
!>
!> Usage:
!>   thermotwin run         <input.csv> [output.csv]
!>   thermotwin degradation <baseline.csv>
!>   thermotwin transient   <baseline.csv>
!>   thermotwin uncertainty <baseline.csv>
!>   thermotwin diagnostics <baseline.csv>
!>   thermotwin selftest
!>
!> "run" solves every row of an input CSV (single design point OR a sweep).
!> The other modes take the FIRST row of the file as a baseline machine and
!> generate their own scenarios. All outputs are CSV files under output/.
program thermotwin
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult, DegradationSet, ComponentState, SensorSpec
    use constants, only: T_REF_ISO_K
    use csv_io, only: read_input_cases, write_results, write_results_header, write_result_row
    use cycle_solver, only: solve_cycle
    use sensitivity_driver, only: run_cases
    use degradation, only: make_preset, apply_degradation, performance_delta
    use transient_thermal, only: simulate_transient, INTEG_RK4
    use uncertainty_analysis, only: monte_carlo_uncertainty, bias_sensitivity_row, &
                                    UncertaintyResult, BiasSensitivity
    use diagnostics_solver, only: Observation, DiagnosticWeights, DiagnosticResult, &
                                  default_weights, diagnose
    use utilities, only: seed_rng, itoa
    use scenario_runner, only: Scenario, scenario_load, scenario_run
    implicit none

    character(len=256) :: mode, infile, outfile
    integer :: nargs

    nargs = command_argument_count()
    if (nargs < 1) then
        call print_usage()
        stop
    end if

    call get_command_argument(1, mode)

    select case (trim(mode))
    case ("run", "design")
        if (nargs < 2) then
            write(*, '(A)') "ERROR: 'run' needs an input CSV."; call print_usage(); error stop 2
        end if
        call get_command_argument(2, infile)
        if (nargs >= 3) then
            call get_command_argument(3, outfile)
        else
            outfile = "output/results_run.csv"
        end if
        call mode_run(trim(infile), trim(outfile))

    case ("degradation")
        call require_infile(nargs, infile)
        call mode_degradation(trim(infile))

    case ("transient")
        call require_infile(nargs, infile)
        call mode_transient(trim(infile))

    case ("uncertainty")
        call require_infile(nargs, infile)
        call mode_uncertainty(trim(infile))

    case ("diagnostics")
        call require_infile(nargs, infile)
        call mode_diagnostics(trim(infile))

    case ("selftest")
        call mode_selftest()

    case ("scenario")
        call mode_scenario(nargs)

    case default
        write(*, '(A)') "ERROR: unknown mode '"//trim(mode)//"'"
        call print_usage()
        error stop 2
    end select

contains

    subroutine require_infile(nargs, infile)
        integer, intent(in) :: nargs
        character(len=*), intent(out) :: infile
        if (nargs < 2) then
            write(*, '(A)') "ERROR: this mode needs a baseline CSV."
            call print_usage(); error stop 2
        end if
        call get_command_argument(2, infile)
    end subroutine require_infile

    subroutine print_usage()
        write(*, '(A)') ""
        write(*, '(A)') "ThermoTwin-F : Modern Fortran gas-turbine performance simulator"
        write(*, '(A)') "---------------------------------------------------------------"
        write(*, '(A)') "Usage:"
        write(*, '(A)') "  thermotwin run         <input.csv> [output.csv]"
        write(*, '(A)') "  thermotwin degradation <baseline.csv>"
        write(*, '(A)') "  thermotwin transient   <baseline.csv>"
        write(*, '(A)') "  thermotwin uncertainty <baseline.csv>"
        write(*, '(A)') "  thermotwin diagnostics <baseline.csv>"
        write(*, '(A)') "  thermotwin selftest"
        write(*, '(A)') "  thermotwin scenario run <file.scn> [--record out.csv]"
        write(*, '(A)') ""
    end subroutine print_usage

    !===================================================================
    ! MODE: scenario -- scripted grid/plant playback with assertions
    !===================================================================
    subroutine mode_scenario(nargs)
        integer, intent(in) :: nargs
        character(len=256) :: sub, scn_path, arg, record_path
        type(Scenario) :: sc
        integer :: i, failures
        logical :: ok

        if (nargs < 3) then
            write(*, '(A)') "ERROR: usage: thermotwin scenario run <file.scn> [--record out.csv]"
            error stop 2
        end if
        call get_command_argument(2, sub)
        if (trim(sub) /= "run") then
            write(*, '(A)') "ERROR: unknown scenario subcommand '"//trim(sub)//"'"
            error stop 2
        end if
        call get_command_argument(3, scn_path)

        record_path = ""
        i = 4
        do while (i <= nargs)
            call get_command_argument(i, arg)
            if (trim(arg) == "--record" .and. i + 1 <= nargs) then
                call get_command_argument(i + 1, record_path)
                i = i + 2
            else
                write(*, '(A)') "ERROR: unknown scenario option '"//trim(arg)//"'"
                error stop 2
            end if
        end do

        call scenario_load(trim(scn_path), sc, ok)
        if (.not. ok) error stop 3

        call scenario_run(sc, failures, trim(record_path))
        if (failures > 0) error stop 6
    end subroutine mode_scenario

    !===================================================================
    ! MODE: run  -- solve every row of an input CSV
    !===================================================================
    subroutine mode_run(infile, outfile)
        character(len=*), intent(in) :: infile, outfile
        type(InputCase), allocatable :: cases(:)
        type(CycleResult), allocatable :: results(:)
        integer :: n
        logical :: ok

        write(*, '(A)') "== ThermoTwin-F : run =="
        call read_input_cases(infile, cases, n, ok)
        if (.not. ok) error stop 3
        write(*, '(A,I0,A)') "  read ", n, " case(s) from "//infile
        call run_cases(cases, results)
        call write_results(outfile, results, n)
        call print_one_line_summary(results(1))
    end subroutine mode_run

    !===================================================================
    ! MODE: degradation -- baseline + clean/mild/severe/washed presets
    !===================================================================
    subroutine mode_degradation(infile)
        character(len=*), intent(in) :: infile
        type(InputCase), allocatable :: cases(:)
        type(InputCase) :: base
        type(CycleResult) :: res(4), clean
        type(DegradationSet) :: d
        integer :: n, i, unit, ios
        logical :: ok
        character(len=8) :: presets(4)
        real(dp) :: dPow, dEff, dHR, dExhT, dFuel

        presets = [character(len=8) :: "clean", "mild", "severe", "washed"]

        write(*, '(A)') "== ThermoTwin-F : degradation =="
        call read_input_cases(infile, cases, n, ok)
        if (.not. ok) error stop 3
        base = cases(1)

        do i = 1, 4
            d = make_preset(trim(presets(i)))
            res(i) = solve_cycle(apply_degradation(base, d))
        end do
        clean = res(1)

        call write_results("output/results_degradation.csv", res, 4)

        ! Deltas relative to clean.
        open(newunit=unit, file="output/results_degradation_deltas.csv", &
             status='replace', action='write', iostat=ios)
        if (ios == 0) then
            write(unit, '(A)') "mode,net_power_MW,thermal_efficiency,heat_rate_kJ_kWh,"// &
                "exhaust_temperature_K,dPower_pct,dEff_pct,dHR_pct,dExhT_K,dFuel_pct"
            do i = 1, 4
                call performance_delta(clean, res(i), dPow, dEff, dHR, dExhT, dFuel)
                write(unit, '(A,9(",",ES16.8))') trim(presets(i)), &
                    res(i)%net_power_MW, res(i)%thermal_efficiency, res(i)%heat_rate_kJ_kWh, &
                    res(i)%exhaust_temperature_K, dPow, dEff, dHR, dExhT, dFuel
            end do
            close(unit)
            write(*, '(A)') "  wrote output/results_degradation_deltas.csv"
        end if

        write(*, '(A)') ""
        write(*, '(A)') "  mode      net_MW    eff[%]   HR[kJ/kWh]   Texh[K]"
        do i = 1, 4
            write(*, '(2x,A8,F9.2,F9.2,F12.1,F11.1)') trim(presets(i)), &
                res(i)%net_power_MW, 100.0_dp*res(i)%thermal_efficiency, &
                res(i)%heat_rate_kJ_kWh, res(i)%exhaust_temperature_K
        end do
    end subroutine mode_degradation

    !===================================================================
    ! MODE: transient -- startup / load-ramp / shutdown metal heating
    !===================================================================
    subroutine mode_transient(infile)
        character(len=*), intent(in) :: infile
        type(InputCase), allocatable :: cases(:)
        type(InputCase) :: base
        type(CycleResult) :: hot
        type(ComponentState) :: comp
        integer, parameter :: NT = 361          ! 0..3600 s in 10 s samples
        real(dp) :: t(NT), Tgas(NT), Tmetal(NT)
        integer :: n, i, unit, ios
        logical :: ok
        real(dp) :: T_exhaust_hot, T_amb

        write(*, '(A)') "== ThermoTwin-F : transient =="
        call read_input_cases(infile, cases, n, ok)
        if (.not. ok) error stop 3
        base = cases(1)
        hot  = solve_cycle(base)
        T_exhaust_hot = hot%exhaust_temperature_K
        T_amb = base%ambient_T_K

        ! Time base
        do i = 1, NT
            t(i) = real(i - 1, dp) * 10.0_dp
        end do

        ! Component node representative of a hot-section casing.
        comp%name = "hot_casing"
        comp%temperature_K   = T_amb
        comp%thermal_mass_J_K= 8.0e5_dp
        comp%hA_W_K          = 4.0e3_dp
        comp%UA_loss_W_K     = 1.5e2_dp

        open(newunit=unit, file="output/results_transient.csv", &
             status='replace', action='write', iostat=ios)
        if (ios /= 0) error stop 4
        write(unit, '(A)') "schedule,time_s,T_gas_K,T_metal_K"

        ! --- Schedule 1: cold start (step to hot exhaust) ---
        do i = 1, NT
            Tgas(i) = T_exhaust_hot
        end do
        comp%temperature_K = T_amb
        call simulate_transient(comp, t, Tgas, T_amb, INTEG_RK4, 10, Tmetal)
        call dump_transient(unit, "startup", t, Tgas, Tmetal, NT)

        ! --- Schedule 2: load ramp (linear gas-temp rise then hold) ---
        do i = 1, NT
            if (t(i) <= 1200.0_dp) then
                Tgas(i) = T_amb + (T_exhaust_hot - T_amb) * (t(i) / 1200.0_dp)
            else
                Tgas(i) = T_exhaust_hot
            end if
        end do
        comp%temperature_K = T_amb
        call simulate_transient(comp, t, Tgas, T_amb, INTEG_RK4, 10, Tmetal)
        call dump_transient(unit, "load_ramp", t, Tgas, Tmetal, NT)

        ! --- Schedule 3: shutdown (start hot, gas drops to ambient) ---
        do i = 1, NT
            if (t(i) <= 600.0_dp) then
                Tgas(i) = T_exhaust_hot - (T_exhaust_hot - T_amb) * (t(i) / 600.0_dp)
            else
                Tgas(i) = T_amb
            end if
        end do
        comp%temperature_K = T_exhaust_hot * 0.95_dp   ! start near soaked
        call simulate_transient(comp, t, Tgas, T_amb, INTEG_RK4, 10, Tmetal)
        call dump_transient(unit, "shutdown", t, Tgas, Tmetal, NT)

        close(unit)
        write(*, '(A)') "  wrote output/results_transient.csv (startup, load_ramp, shutdown)"
        write(*, '(A,F7.1,A)') "  hot exhaust drive temperature = ", T_exhaust_hot, " K"
    end subroutine mode_transient

    subroutine dump_transient(unit, tag, t, Tgas, Tmetal, n)
        integer, intent(in) :: unit, n
        character(len=*), intent(in) :: tag
        real(dp), intent(in) :: t(:), Tgas(:), Tmetal(:)
        integer :: i
        do i = 1, n
            write(unit, '(A,3(",",ES16.8))') trim(tag), t(i), Tgas(i), Tmetal(i)
        end do
    end subroutine dump_transient

    !===================================================================
    ! MODE: uncertainty -- Monte Carlo + deterministic bias sensitivity
    !===================================================================
    subroutine mode_uncertainty(infile)
        character(len=*), intent(in) :: infile
        type(InputCase), allocatable :: cases(:)
        type(InputCase) :: base
        type(CycleResult) :: nominal
        type(UncertaintyResult) :: u
        type(BiasSensitivity) :: b
        integer :: n, unit, ios
        logical :: ok
        integer, parameter :: NMC = 5000
        character(len=16) :: channels(4)
        real(dp) :: biases(4)
        integer :: i

        write(*, '(A)') "== ThermoTwin-F : uncertainty =="
        call read_input_cases(infile, cases, n, ok)
        if (.not. ok) error stop 3
        base = cases(1)
        nominal = solve_cycle(base)

        call seed_rng(20240601)   ! reproducible study

        ! 1-sigma instrument uncertainties (representative values).
        u = monte_carlo_uncertainty(base, &
                sigma_Tamb_K   = 1.0_dp, &
                sigma_Pamb_Pa  = 200.0_dp, &
                sigma_mdot_frac= 0.01_dp, &
                sigma_TIT_K    = 8.0_dp, &
                n_samples      = NMC, &
                seed_already_set = .true.)

        open(newunit=unit, file="output/results_uncertainty.csv", &
             status='replace', action='write', iostat=ios)
        if (ios /= 0) error stop 4
        write(unit, '(A)') "quantity,nominal,mean,sigma,p2_5,p97_5"
        write(unit, '(A,5(",",ES16.8))') "net_power_MW", nominal%net_power_MW, &
            u%power_mean, u%power_sigma, u%power_p025, u%power_p975
        write(unit, '(A,5(",",ES16.8))') "thermal_efficiency", nominal%thermal_efficiency, &
            u%eff_mean, u%eff_sigma, u%eff_p025, u%eff_p975
        write(unit, '(A,5(",",ES16.8))') "heat_rate_kJ_kWh", nominal%heat_rate_kJ_kWh, &
            u%hr_mean, u%hr_sigma, u%hr_p025, u%hr_p975
        close(unit)

        ! Deterministic bias sensitivity table.
        channels = [character(len=16) :: "T_ambient", "T_turbine_inlet", &
                                         "pressure_ratio", "mdot_air"]
        biases   = [2.0_dp, 10.0_dp, 0.3_dp, 2.0_dp]
        open(newunit=unit, file="output/results_bias_sensitivity.csv", &
             status='replace', action='write', iostat=ios)
        if (ios /= 0) error stop 4
        write(unit, '(A)') "channel,applied_bias,dPower_MW,dEfficiency,dHeatRate_kJ_kWh"
        do i = 1, 4
            b = bias_sensitivity_row(base, trim(channels(i)), biases(i))
            write(unit, '(A,4(",",ES16.8))') trim(b%channel), b%applied_bias, &
                b%dpower_MW, b%deff, b%dHR_kJ_kWh
        end do
        close(unit)

        write(*, '(A,I0,A)') "  Monte Carlo: ", u%n_samples, " converged samples"
        write(*, '(A,F8.2,A,F6.2,A)') "  net power = ", u%power_mean, " +/- ", &
            u%power_sigma, " MW (1-sigma)"
        write(*, '(A,F8.3,A,F6.3)') "  efficiency = ", u%eff_mean, " +/- ", u%eff_sigma
        write(*, '(A)') "  wrote output/results_uncertainty.csv, output/results_bias_sensitivity.csv"
    end subroutine mode_uncertainty

    !===================================================================
    ! MODE: diagnostics -- create synthetic degraded "truth", then invert
    !===================================================================
    subroutine mode_diagnostics(infile)
        character(len=*), intent(in) :: infile
        type(InputCase), allocatable :: cases(:)
        type(InputCase) :: base
        type(CycleResult) :: truth
        type(DegradationSet) :: true_deg
        type(Observation) :: obs
        type(DiagnosticWeights) :: w
        type(DiagnosticResult) :: dr
        integer :: n, unit, ios
        logical :: ok

        write(*, '(A)') "== ThermoTwin-F : diagnostics =="
        call read_input_cases(infile, cases, n, ok)
        if (.not. ok) error stop 3
        base = cases(1)

        ! Synthetic ground truth: a known degradation we will try to recover.
        true_deg%mode = "synthetic_truth"
        true_deg%delta_eta_compressor = 0.018_dp
        true_deg%delta_mdot_fraction  = 0.010_dp
        true_deg%delta_eta_turbine    = 0.012_dp
        true_deg%delta_dP_combustor   = 0.003_dp

        truth = solve_cycle(apply_degradation(base, true_deg))

        ! "Measured" observations (here noise-free; add sensor_model for realism).
        obs%net_power_MW          = truth%net_power_MW
        obs%exhaust_temperature_K = truth%exhaust_temperature_K
        obs%fuel_flow_kg_s        = truth%fuel_flow_kg_s
        obs%T_compressor_out_K    = truth%T2_K

        w = default_weights()
        dr = diagnose(base, obs, w, n_grid=8)

        open(newunit=unit, file="output/results_diagnostics.csv", &
             status='replace', action='write', iostat=ios)
        if (ios /= 0) error stop 4
        write(unit, '(A)') "parameter,true_value,estimated_value,abs_error"
        write(unit, '(A,3(",",ES16.8))') "delta_eta_compressor", &
            true_deg%delta_eta_compressor, dr%estimate%delta_eta_compressor, &
            abs(true_deg%delta_eta_compressor - dr%estimate%delta_eta_compressor)
        write(unit, '(A,3(",",ES16.8))') "delta_mdot_fraction", &
            true_deg%delta_mdot_fraction, dr%estimate%delta_mdot_fraction, &
            abs(true_deg%delta_mdot_fraction - dr%estimate%delta_mdot_fraction)
        write(unit, '(A,3(",",ES16.8))') "delta_eta_turbine", &
            true_deg%delta_eta_turbine, dr%estimate%delta_eta_turbine, &
            abs(true_deg%delta_eta_turbine - dr%estimate%delta_eta_turbine)
        write(unit, '(A,3(",",ES16.8))') "delta_dP_combustor", &
            true_deg%delta_dP_combustor, dr%estimate%delta_dP_combustor, &
            abs(true_deg%delta_dP_combustor - dr%estimate%delta_dP_combustor)
        close(unit)

        write(*, '(A,I0,A,ES10.3)') "  evaluations = ", dr%evaluations, &
            ",  final objective = ", dr%objective
        write(*, '(A)') "  parameter              true      estimated"
        write(*, '(2x,A,2F11.5)') "delta_eta_compressor ", &
            true_deg%delta_eta_compressor, dr%estimate%delta_eta_compressor
        write(*, '(2x,A,2F11.5)') "delta_mdot_fraction  ", &
            true_deg%delta_mdot_fraction, dr%estimate%delta_mdot_fraction
        write(*, '(2x,A,2F11.5)') "delta_eta_turbine    ", &
            true_deg%delta_eta_turbine, dr%estimate%delta_eta_turbine
        write(*, '(2x,A,2F11.5)') "delta_dP_combustor   ", &
            true_deg%delta_dP_combustor, dr%estimate%delta_dP_combustor
        write(*, '(A)') "  wrote output/results_diagnostics.csv"
    end subroutine mode_diagnostics

    !===================================================================
    ! MODE: selftest -- verify the design-point hand calculation
    !===================================================================
    subroutine mode_selftest()
        type(InputCase) :: ic
        type(CycleResult) :: r
        logical :: pass

        write(*, '(A)') "== ThermoTwin-F : selftest =="
        ! Canonical verification case (see docs/verification.md).
        ic%case_name = "verification_baseline"
        ic%ambient_T_K = 288.15_dp
        ic%ambient_P_Pa = 101325.0_dp
        ic%relative_humidity = 0.60_dp
        ic%inlet_pressure_loss = 0.0_dp        ! no inlet loss for clean hand calc
        ic%mdot_air_kg_s = 100.0_dp
        ic%pressure_ratio = 15.0_dp
        ic%eta_compressor = 0.86_dp
        ic%T_turbine_inlet_K = 1400.0_dp
        ic%eta_combustor = 0.98_dp
        ic%combustor_pressure_loss = 0.03_dp
        ic%LHV_J_kg = 50.0e6_dp
        ic%eta_turbine = 0.89_dp
        ic%exhaust_pressure_loss = 0.0_dp      ! exhaust to ambient for hand calc
        ic%eta_mechanical = 0.99_dp
        ic%eta_generator = 0.985_dp
        ic%auxiliary_load_fraction = 0.02_dp

        r = solve_cycle(ic)

        write(*, '(A)') "  computed station states:"
        write(*, '(A,F9.2,A)') "    T2 (compressor out) = ", r%T2_K, " K   [hand ~679.5 K]"
        write(*, '(A,F9.2,A)') "    T4 (exhaust)        = ", r%T4_K, " K   [hand ~792 K]"
        write(*, '(A,F9.4,A)') "    fuel-air ratio      = ", r%fuel_air_ratio, "     [hand ~0.0195]"
        write(*, '(A,F9.2,A)') "    net power           = ", r%net_power_MW, " MW  [hand ~30.4 MW]"
        write(*, '(A,F9.4,A)') "    thermal efficiency  = ", r%thermal_efficiency, "   [hand ~0.312]"
        write(*, '(A,F9.1,A)') "    heat rate           = ", r%heat_rate_kJ_kWh, " kJ/kWh"

        ! Tolerances chosen to match the documented hand calculation.
        pass = .true.
        call check("T2_K",  r%T2_K, 679.5_dp, 3.0_dp, pass)
        call check("T4_K",  r%T4_K, 792.0_dp, 5.0_dp, pass)
        call check("f",     r%fuel_air_ratio, 0.0195_dp, 0.0010_dp, pass)
        call check("eta",   r%thermal_efficiency, 0.312_dp, 0.010_dp, pass)
        call check("Pnet",  r%net_power_MW, 30.4_dp, 1.5_dp, pass)

        write(*, '(A)') ""
        if (pass) then
            write(*, '(A)') "  SELFTEST RESULT: PASS"
        else
            write(*, '(A)') "  SELFTEST RESULT: FAIL"
            error stop 5
        end if
    end subroutine mode_selftest

    subroutine check(name, got, expect, tol, pass)
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: got, expect, tol
        logical, intent(inout) :: pass
        if (abs(got - expect) > tol) then
            write(*, '(A)') "    [FAIL] "//trim(name)
            pass = .false.
        end if
    end subroutine check

    subroutine print_one_line_summary(r)
        type(CycleResult), intent(in) :: r
        write(*, '(A)') ""
        write(*, '(A,F8.2,A,F6.2,A,F9.1,A,F7.1,A)') &
            "  net power ", r%net_power_MW, " MW | eff ", &
            100.0_dp*r%thermal_efficiency, " % | HR ", r%heat_rate_kJ_kWh, &
            " kJ/kWh | Texh ", r%exhaust_temperature_K, " K"
    end subroutine print_one_line_summary

end program thermotwin
