program benchmark_cases
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult
    use sensitivity_driver, only: run_cases
    use cycle_solver, only: solve_cycle
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    !$ use omp_lib, only: omp_get_num_threads
    implicit none
    type(InputCase), allocatable :: cases(:)
    type(CycleResult), allocatable :: results(:)
    type(CycleResult) :: reference
    integer :: n, i, observed_threads, rate, started, stopped
    real(dp) :: error, max_error, elapsed
    character(len=64) :: arg
    n = 10000
    call get_command_argument(1, arg)
    if (len_trim(arg) > 0) read(arg, *) n
    if (n < 1) error stop 'n must be positive'
    allocate(cases(n))
    do i = 1, n
        ! Supported ambient temperature / pressure-ratio / TIT sensitivity ranges.
        cases(i)%ambient_T_K = 273.15_dp + 40.0_dp * real(mod(i, 101),dp)/100.0_dp
        cases(i)%pressure_ratio = 10.0_dp + 10.0_dp * real(mod(i, 97),dp)/96.0_dp
        cases(i)%T_turbine_inlet_K = 1350.0_dp + 150.0_dp * real(mod(i, 89),dp)/88.0_dp
    end do
    observed_threads = 1
    !$omp parallel default(none) shared(observed_threads)
    !$omp single
    !$ observed_threads = omp_get_num_threads()
    !$omp end single
    !$omp end parallel
    call system_clock(started, rate)
    call run_cases(cases, results)
    call system_clock(stopped)
    elapsed = real(stopped-started,dp)/real(rate,dp)
    ! Verification is deliberately OUTSIDE the timed workload. Compare all numeric
    ! fields, status, names and convergence against direct serial solves.
    max_error = 0.0_dp
    do i = 1, n
        reference = solve_cycle(cases(i))
        if (.not. reference%converged .or. .not. results(i)%converged) error stop 'unconverged'
        if (reference%case_name /= results(i)%case_name) error stop 'case name differs'
        if (reference%degradation_mode /= results(i)%degradation_mode) error stop 'mode differs'
        if (reference%status_message /= results(i)%status_message) error stop 'status differs'
        if (.not. all(ieee_is_finite(values(results(i))))) error stop 'nonfinite result'
        error = maxval(abs(values(results(i))-values(reference))/max(1.0_dp,abs(values(reference))))
        max_error = max(max_error, error)
    end do
    if (max_error > 1.0e-12_dp) error stop 'serial / parallel mismatch'
    write(*,'(A,I0)') 'threads=', observed_threads
    write(*,'(A,ES24.16)') 'wall_seconds=', elapsed
    write(*,'(A,ES24.16)') 'max_relative_error=', max_error
    write(*,'(A,I0)') 'cases_verified=', n
contains
    function values(r) result(v)
        type(CycleResult), intent(in) :: r
        real(dp) :: v(25)
        v = [r%T1_K, &
            r%P1_Pa, &
            r%T2_K, &
            r%P2_Pa, &
            r%w_compressor_J_kg, &
            r%power_compressor_MW, &
            r%T3_K, &
            r%P3_Pa, &
            r%fuel_air_ratio, &
            r%fuel_flow_kg_s, &
            r%heat_input_MW, &
            r%T4_K, &
            r%P4_Pa, &
            r%w_turbine_J_kg, &
            r%power_turbine_MW, &
            r%mdot_air_kg_s, &
            r%mdot_gas_kg_s, &
            r%net_power_MW, &
            r%gross_power_MW, &
            r%w_net_specific_J_kg, &
            r%thermal_efficiency, &
            r%heat_rate_kJ_kWh, &
            r%exhaust_temperature_K, &
            r%exhaust_energy_MW, &
            r%specific_power_kW_per_kgps]
    end function values
end program benchmark_cases
