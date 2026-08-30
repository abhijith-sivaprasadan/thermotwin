!> @file scenario_runner.f90
!> @brief Scripted scenario playback with assertions — the physics
!>        regression harness (revamp Phase 1).
!>
!> Scenarios are plain-text `.scn` files (one directive per line, `#` starts
!> a comment). The format is deliberately dependency-free:
!>
!>     name     load_step
!>     duration 45            # seconds of simulated time
!>     dt       0.25          # optional, defaults to the GUI tick
!>
!>     at 5.0   set demand_MW 45
!>     at 5.0   command turbine_trip
!>     at 25.0  assert_near  frequency_Hz 50.0 0.10
!>     at 30.0  assert_above gas_dispatch_pct 95
!>     at 30.0  assert_below UFLS_stage 0.5
!>
!> Timing semantics (deterministic): `set`/`command` events fire at the start
!> of the first tick whose start time >= t_event; assertions are evaluated
!> right after the tick that reaches t >= t_event.
!>
!> With a record path, every tick appends one row of the full tag bus to a
!> CSV — the flight recorder for later replay/analysis.
module scenario_runner
    use precision_kinds, only: dp
    use engine_state
    use engine_core, only: engine_init, engine_step, refresh_model, apply_market_profile
    use dispatch_agc, only: balance_now, reset_controls, &
        apply_load_step, apply_cloud_ramp, apply_turbine_trip
    implicit none
    private

    public :: Scenario, ScenarioEvent, ScenarioTrace, ScenarioComparison
    public :: scenario_load, scenario_run, scenario_gui_tick, scenario_trace, scenario_compare

    integer, parameter :: MAX_EVENTS = 96
    integer, parameter, public :: SCENARIO_TRACE_N = 240
    integer, parameter :: KIND_SET          = 1
    integer, parameter :: KIND_COMMAND      = 2
    integer, parameter :: KIND_ASSERT_NEAR  = 3
    integer, parameter :: KIND_ASSERT_ABOVE = 4
    integer, parameter :: KIND_ASSERT_BELOW = 5

    type :: ScenarioEvent
        real(dp) :: t_s = 0.0_dp
        integer :: kind = 0
        character(len=40) :: target = ""
        real(dp) :: value = 0.0_dp
        real(dp) :: tol = 0.0_dp
        logical :: done = .false.
    end type ScenarioEvent

    type :: Scenario
        character(len=64) :: name = "unnamed"
        real(dp) :: duration_s = 30.0_dp
        real(dp) :: dt_s = 0.25_dp
        integer :: n_events = 0
        type(ScenarioEvent) :: events(MAX_EVENTS)
    end type Scenario

    type :: ScenarioTrace
        character(len=64) :: name = "unnamed"
        integer :: n = 0
        real(dp) :: duration_s = 0.0_dp
        real(dp) :: dt_s = 0.0_dp
        real(dp) :: nominal_frequency_Hz = 50.0_dp
        real(dp) :: time_s(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: frequency_Hz(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: demand_MW(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: supply_MW(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: plant_MW(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: storage_MW(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: imbalance_MW(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: margin_usd_h(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: co2_g_kWh(SCENARIO_TRACE_N) = 0.0_dp
        real(dp) :: min_frequency_Hz = 0.0_dp
        real(dp) :: max_frequency_Hz = 0.0_dp
        real(dp) :: max_abs_imbalance_MW = 0.0_dp
        real(dp) :: final_margin_usd_h = 0.0_dp
        real(dp) :: final_CO2_intensity_g_kWh = 0.0_dp
        real(dp) :: final_soc_pct = 0.0_dp
        integer :: assertion_failures = 0
    end type ScenarioTrace

    type :: ScenarioComparison
        logical :: ready = .false.
        type(ScenarioTrace) :: a
        type(ScenarioTrace) :: b
        real(dp) :: delta_min_frequency_Hz = 0.0_dp
        real(dp) :: delta_max_abs_imbalance_MW = 0.0_dp
        real(dp) :: delta_final_margin_usd_h = 0.0_dp
        real(dp) :: delta_final_CO2_intensity_g_kWh = 0.0_dp
        real(dp) :: delta_final_soc_pct = 0.0_dp
    end type ScenarioComparison

contains

    !> Parse a .scn file. On failure prints the offending line and sets ok=.false.
    subroutine scenario_load(path, sc, ok)
        character(len=*), intent(in) :: path
        type(Scenario), intent(out) :: sc
        logical, intent(out) :: ok
        character(len=512) :: line
        integer :: unit, ios, line_no, hash

        ok = .false.
        open(newunit=unit, file=path, status='old', action='read', iostat=ios)
        if (ios /= 0) then
            write(*, '(A)') "ERROR: cannot open scenario file '"//trim(path)//"'"
            return
        end if

        line_no = 0
        do
            read(unit, '(A)', iostat=ios) line
            if (ios /= 0) exit
            line_no = line_no + 1
            call replace_tabs(line)
            hash = index(line, '#')
            if (hash > 0) line = line(:hash-1)
            if (len_trim(line) == 0) cycle
            if (trim(adjustl(line)) == "end") exit
            if (.not. parse_line(line, sc)) then
                write(*, '(A,I0,A)') "ERROR: "//trim(path)//" line ", line_no, &
                    ": cannot parse '"//trim(adjustl(line))//"'"
                close(unit)
                return
            end if
        end do
        close(unit)
        ok = .true.
    end subroutine scenario_load

    !> Run a scenario from the standard initial operating point.
    !> n_failures counts failed assertions (0 = scenario passes).
    subroutine scenario_run(sc, n_failures, record_path)
        type(Scenario), intent(inout) :: sc
        integer, intent(out) :: n_failures
        character(len=*), intent(in), optional :: record_path
        type(GridState) :: st
        integer :: k, nsteps, rec_unit, n_asserts
        real(dp) :: t
        logical :: recording

        n_failures = 0
        n_asserts = 0
        sc%events(1:sc%n_events)%done = .false.

        write(*, '(A)') "== scenario: "//trim(sc%name)//" =="
        call engine_init(st)

        recording = .false.
        rec_unit = -1
        if (present(record_path)) then
            if (len_trim(record_path) > 0) then
                call open_recorder(record_path, rec_unit, recording)
            end if
        end if

        nsteps = max(1, nint(sc%duration_s / sc%dt_s))
        t = 0.0_dp
        do k = 1, nsteps
            call apply_due_inputs(sc, st, t)
            call engine_step(st, sc%dt_s)
            t = real(k, dp) * sc%dt_s
            call eval_due_assertions(sc, st, t, n_failures, n_asserts)
            if (recording) call record_row(rec_unit, t, st)
        end do
        if (recording) close(rec_unit)

        if (n_failures == 0) then
            write(*, '(A,I0,A)') "PASS: scenario "//trim(sc%name)//" (", n_asserts, " assertions)"
        else
            write(*, '(A,I0,A,I0,A)') "FAIL: scenario "//trim(sc%name)//" (", n_failures, &
                " of ", n_asserts, " assertions failed)"
        end if
    end subroutine scenario_run

    !> Drive one GUI timer tick of a scenario against the live grid state.
    !> Call BEFORE engine_step(st, dt); t_now = st%elapsed_s (time before the tick).
    !> done is set .true. when the scenario duration has elapsed.
    subroutine scenario_gui_tick(sc, st, t_now, done)
        type(Scenario), intent(inout) :: sc
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: t_now
        logical, intent(out) :: done
        call apply_due_inputs(sc, st, t_now)
        done = t_now + sc%dt_s * 0.5_dp >= sc%duration_s
    end subroutine scenario_gui_tick

    !> Run a scenario and down-sample its live states into a GUI/report trace.
    !> This shares the same deterministic event semantics as scenario_run.
    subroutine scenario_trace(sc, tr, n_failures)
        type(Scenario), intent(inout) :: sc
        type(ScenarioTrace), intent(out) :: tr
        integer, intent(out), optional :: n_failures
        type(GridState) :: st
        integer :: k, nsteps, sample_stride, failures, n_asserts
        real(dp) :: t

        failures = 0
        n_asserts = 0
        sc%events(1:sc%n_events)%done = .false.

        tr = ScenarioTrace()
        tr%name = sc%name
        tr%duration_s = sc%duration_s
        tr%dt_s = sc%dt_s

        call engine_init(st)
        call apply_due_inputs(sc, st, 0.0_dp)
        call update_trace_metrics(tr, st)
        call sample_trace_point(tr, 0.0_dp, st)

        nsteps = max(1, nint(sc%duration_s / sc%dt_s))
        sample_stride = max(1, int(ceiling(real(nsteps + 1, dp) / &
            real(SCENARIO_TRACE_N, dp))))
        t = 0.0_dp
        do k = 1, nsteps
            call apply_due_inputs(sc, st, t)
            call engine_step(st, sc%dt_s)
            t = real(k, dp) * sc%dt_s
            call eval_due_assertions(sc, st, t, failures, n_asserts)
            call update_trace_metrics(tr, st)
            if (mod(k, sample_stride) == 0 .or. k == nsteps) then
                call sample_trace_point(tr, t, st, replace_last=(k == nsteps))
            end if
        end do

        tr%assertion_failures = failures
        if (present(n_failures)) n_failures = failures
    end subroutine scenario_trace

    !> Run two scenarios from the same initial point and calculate comparison deltas.
    !> Deltas are B - A; positive margin/nadir and negative imbalance/CO2 are better.
    subroutine scenario_compare(sc_a, sc_b, cmp)
        type(Scenario), intent(inout) :: sc_a
        type(Scenario), intent(inout) :: sc_b
        type(ScenarioComparison), intent(out) :: cmp
        integer :: fail_a, fail_b

        cmp = ScenarioComparison()
        call scenario_trace(sc_a, cmp%a, fail_a)
        call scenario_trace(sc_b, cmp%b, fail_b)
        cmp%ready = cmp%a%n > 1 .and. cmp%b%n > 1
        cmp%delta_min_frequency_Hz = cmp%b%min_frequency_Hz - cmp%a%min_frequency_Hz
        cmp%delta_max_abs_imbalance_MW = cmp%b%max_abs_imbalance_MW - cmp%a%max_abs_imbalance_MW
        cmp%delta_final_margin_usd_h = cmp%b%final_margin_usd_h - cmp%a%final_margin_usd_h
        cmp%delta_final_CO2_intensity_g_kWh = cmp%b%final_CO2_intensity_g_kWh - &
            cmp%a%final_CO2_intensity_g_kWh
        cmp%delta_final_soc_pct = cmp%b%final_soc_pct - cmp%a%final_soc_pct
    end subroutine scenario_compare

    ! ------------------------------------------------------------------
    ! Parsing
    ! ------------------------------------------------------------------

    function parse_line(line, sc) result(ok)
        character(len=*), intent(in) :: line
        type(Scenario), intent(inout) :: sc
        logical :: ok
        character(len=64) :: tok
        integer :: pos
        logical :: has

        ok = .false.
        pos = 1
        call next_token(line, pos, tok, has)
        if (.not. has) return

        select case (trim(tok))
        case ("name")
            call next_token(line, pos, tok, has)
            if (.not. has) return
            sc%name = tok
            ok = .true.
        case ("duration")
            ok = next_real(line, pos, sc%duration_s)
        case ("dt")
            ok = next_real(line, pos, sc%dt_s)
            if (ok) ok = sc%dt_s > 1.0e-6_dp
        case ("at")
            ok = parse_event(line, pos, sc)
        case default
            ok = .false.
        end select
    end function parse_line

    function parse_event(line, pos, sc) result(ok)
        character(len=*), intent(in) :: line
        integer, intent(inout) :: pos
        type(Scenario), intent(inout) :: sc
        logical :: ok
        type(ScenarioEvent) :: ev
        character(len=64) :: tok
        logical :: has

        ok = .false.
        if (sc%n_events >= MAX_EVENTS) return
        if (.not. next_real(line, pos, ev%t_s)) return

        call next_token(line, pos, tok, has)
        if (.not. has) return
        select case (trim(tok))
        case ("set")
            ev%kind = KIND_SET
            call next_token(line, pos, ev%target, has)
            if (.not. has) return
            if (.not. next_real(line, pos, ev%value)) return
        case ("command")
            ev%kind = KIND_COMMAND
            call next_token(line, pos, ev%target, has)
            if (.not. has) return
        case ("assert_near")
            ev%kind = KIND_ASSERT_NEAR
            call next_token(line, pos, ev%target, has)
            if (.not. has) return
            if (.not. next_real(line, pos, ev%value)) return
            if (.not. next_real(line, pos, ev%tol)) return
        case ("assert_above")
            ev%kind = KIND_ASSERT_ABOVE
            call next_token(line, pos, ev%target, has)
            if (.not. has) return
            if (.not. next_real(line, pos, ev%value)) return
        case ("assert_below")
            ev%kind = KIND_ASSERT_BELOW
            call next_token(line, pos, ev%target, has)
            if (.not. has) return
            if (.not. next_real(line, pos, ev%value)) return
        case default
            return
        end select

        sc%n_events = sc%n_events + 1
        sc%events(sc%n_events) = ev
        ok = .true.
    end function parse_event

    subroutine next_token(line, pos, token, has)
        character(len=*), intent(in) :: line
        integer, intent(inout) :: pos
        character(len=*), intent(out) :: token
        logical, intent(out) :: has
        integer :: n, start

        n = len_trim(line)
        token = ""
        has = .false.
        do while (pos <= n)
            if (line(pos:pos) /= ' ') exit
            pos = pos + 1
        end do
        if (pos > n) return
        start = pos
        do while (pos <= n)
            if (line(pos:pos) == ' ') exit
            pos = pos + 1
        end do
        token = line(start:pos-1)
        has = .true.
    end subroutine next_token

    function next_real(line, pos, value) result(ok)
        character(len=*), intent(in) :: line
        integer, intent(inout) :: pos
        real(dp), intent(out) :: value
        logical :: ok
        character(len=64) :: tok
        logical :: has
        integer :: ios

        ok = .false.
        value = 0.0_dp
        call next_token(line, pos, tok, has)
        if (.not. has) return
        read(tok, *, iostat=ios) value
        ok = ios == 0
    end function next_real

    subroutine replace_tabs(line)
        character(len=*), intent(inout) :: line
        integer :: i
        do i = 1, len(line)
            if (line(i:i) == char(9)) line(i:i) = ' '
        end do
    end subroutine replace_tabs

    ! ------------------------------------------------------------------
    ! Execution
    ! ------------------------------------------------------------------

    subroutine apply_due_inputs(sc, st, t_now)
        type(Scenario), intent(inout) :: sc
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: t_now
        integer :: i
        logical :: touched, ok

        touched = .false.
        do i = 1, sc%n_events
            associate (ev => sc%events(i))
                if (ev%done) cycle
                if (ev%kind /= KIND_SET .and. ev%kind /= KIND_COMMAND) cycle
                if (ev%t_s > t_now + 1.0e-9_dp) cycle
                if (ev%kind == KIND_SET) then
                    call set_state_field(st, ev%target, ev%value, ok)
                    if (ok) then
                        write(*, '(A,F8.2,A,F10.3)') "   t=", t_now, &
                            "  set "//trim(ev%target)//" =", ev%value
                    else
                        write(*, '(A)') "   WARNING: unknown set target '"//trim(ev%target)//"'"
                    end if
                else
                    call run_command(st, ev%target, ok)
                    if (ok) then
                        write(*, '(A,F8.2,A)') "   t=", t_now, "  command "//trim(ev%target)
                    else
                        write(*, '(A)') "   WARNING: unknown command '"//trim(ev%target)//"'"
                    end if
                end if
                ev%done = .true.
                touched = .true.
            end associate
        end do
        if (touched) call refresh_model(st)
    end subroutine apply_due_inputs

    subroutine eval_due_assertions(sc, st, t_now, n_failures, n_asserts)
        type(Scenario), intent(inout) :: sc
        type(GridState), intent(in) :: st
        real(dp), intent(in) :: t_now
        integer, intent(inout) :: n_failures, n_asserts
        integer :: i
        real(dp) :: got
        logical :: ok, pass

        do i = 1, sc%n_events
            associate (ev => sc%events(i))
                if (ev%done) cycle
                if (ev%kind /= KIND_ASSERT_NEAR .and. ev%kind /= KIND_ASSERT_ABOVE &
                    .and. ev%kind /= KIND_ASSERT_BELOW) cycle
                if (ev%t_s > t_now + 1.0e-9_dp) cycle

                call get_state_value(st, ev%target, got, ok)
                ev%done = .true.
                n_asserts = n_asserts + 1
                if (.not. ok) then
                    write(*, '(A)') "   [FAIL] unknown assert target '"//trim(ev%target)//"'"
                    n_failures = n_failures + 1
                    cycle
                end if

                select case (ev%kind)
                case (KIND_ASSERT_NEAR)
                    pass = abs(got - ev%value) <= ev%tol
                    call report(t_now, ev, got, pass, "within")
                case (KIND_ASSERT_ABOVE)
                    pass = got > ev%value
                    call report(t_now, ev, got, pass, "above")
                case default
                    pass = got < ev%value
                    call report(t_now, ev, got, pass, "below")
                end select
                if (.not. pass) n_failures = n_failures + 1
            end associate
        end do
    end subroutine eval_due_assertions

    subroutine update_trace_metrics(tr, st)
        type(ScenarioTrace), intent(inout) :: tr
        type(GridState), intent(in) :: st

        if (tr%n == 0 .and. tr%min_frequency_Hz == 0.0_dp .and. &
            tr%max_frequency_Hz == 0.0_dp) then
            tr%min_frequency_Hz = st%frequency_Hz
            tr%max_frequency_Hz = st%frequency_Hz
        else
            tr%min_frequency_Hz = min(tr%min_frequency_Hz, st%frequency_Hz)
            tr%max_frequency_Hz = max(tr%max_frequency_Hz, st%frequency_Hz)
        end if
        tr%nominal_frequency_Hz = st%nominal_frequency_Hz
        tr%max_abs_imbalance_MW = max(tr%max_abs_imbalance_MW, abs(st%imbalance_MW))
        tr%final_margin_usd_h = st%margin_usd_h
        tr%final_CO2_intensity_g_kWh = st%CO2_intensity_g_kWh
        tr%final_soc_pct = st%battery_soc_pct
    end subroutine update_trace_metrics

    subroutine sample_trace_point(tr, t_now, st, replace_last)
        type(ScenarioTrace), intent(inout) :: tr
        real(dp), intent(in) :: t_now
        type(GridState), intent(in) :: st
        logical, intent(in), optional :: replace_last
        logical :: replace
        integer :: j

        replace = .false.
        if (present(replace_last)) replace = replace_last
        if (replace .and. tr%n >= SCENARIO_TRACE_N) then
            j = SCENARIO_TRACE_N
        else
            if (tr%n >= SCENARIO_TRACE_N) return
            tr%n = tr%n + 1
            j = tr%n
        end if

        tr%time_s(j) = t_now
        tr%frequency_Hz(j) = st%frequency_Hz
        tr%demand_MW(j) = st%demand_MW
        tr%supply_MW(j) = st%supply_MW
        tr%plant_MW(j) = st%plant_power_MW
        tr%storage_MW(j) = st%storage_MW
        tr%imbalance_MW(j) = st%imbalance_MW
        tr%margin_usd_h(j) = st%margin_usd_h
        tr%co2_g_kWh(j) = st%CO2_intensity_g_kWh
    end subroutine sample_trace_point

    subroutine report(t_now, ev, got, pass, rel)
        real(dp), intent(in) :: t_now, got
        type(ScenarioEvent), intent(in) :: ev
        logical, intent(in) :: pass
        character(len=*), intent(in) :: rel
        character(len=6) :: tag

        if (pass) then
            tag = "[ok]  "
        else
            tag = "[FAIL]"
        end if
        write(*, '(3A,F8.2,2A,F12.4,3A,F12.4)') "   ", tag, " t=", t_now, &
            "  "//trim(ev%target), " =", got, "  (", rel, ")", ev%value
    end subroutine report

    subroutine run_command(st, name, ok)
        type(GridState), intent(inout) :: st
        character(len=*), intent(in) :: name
        logical, intent(out) :: ok

        ok = .true.
        select case (trim(name))
        case ("balance_now");   call balance_now(st)
        case ("reset");         call reset_controls(st)
        case ("load_step");     call apply_load_step(st)
        case ("cloud_ramp");    call apply_cloud_ramp(st)
        case ("turbine_trip");  call apply_turbine_trip(st)
        case ("trip_gt1")
            st%fleet_unit_online(FLEET_GT1) = .false.
            st%fleet_unit_setpoint_MW(FLEET_GT1) = 0.0_dp
            st%fleet_unit_actual_MW(FLEET_GT1) = 0.0_dp
        case ("trip_gt2")
            st%fleet_unit_online(FLEET_GT2) = .false.
            st%fleet_unit_setpoint_MW(FLEET_GT2) = 0.0_dp
            st%fleet_unit_actual_MW(FLEET_GT2) = 0.0_dp
        case ("trip_cc1")
            st%fleet_unit_online(FLEET_CC1) = .false.
            st%fleet_unit_setpoint_MW(FLEET_CC1) = 0.0_dp
            st%fleet_unit_actual_MW(FLEET_CC1) = 0.0_dp
        case ("restore_fleet")
            st%fleet_unit_online = [.true., .true., .true.]
        case default
            ok = .false.
        end select
    end subroutine run_command

    !> Write one operator-adjustable (or initial-condition) state field.
    subroutine set_state_field(st, name, value, ok)
        type(GridState), intent(inout) :: st
        character(len=*), intent(in) :: name
        real(dp), intent(in) :: value
        logical, intent(out) :: ok

        ok = .true.
        select case (trim(name))
        case ("demand_MW");            st%demand_MW = value
        case ("renewable_MW");         st%renewable_MW = value
        case ("storage_request_MW");   st%storage_request_MW = value
        case ("gas_dispatch_pct");     st%gas_dispatch_pct = value
        case ("ambient_C");            st%ambient_C = value
        case ("TIT_K");                st%TIT_K = value
        case ("frequency_Hz");         st%frequency_Hz = value
        case ("renewable_curtail_MW"); st%renewable_curtail_MW = value
        case ("battery_soc_pct")
            st%battery_soc_pct = clamp_real(value, 0.0_dp, 100.0_dp)
            st%battery_energy_MWh = BATTERY_CAPACITY_MWH * st%battery_soc_pct / 100.0_dp
        case ("auto_balance");         st%auto_balance = value > 0.5_dp
        case ("fcr_hold");             st%fcr_hold = value > 0.5_dp
        case ("roi_dispatch");         st%roi_dispatch = value > 0.5_dp
        case ("combined_cycle");       st%combined_cycle = value > 0.5_dp
        case ("fleet_mode")
            st%fleet_mode = value > 0.5_dp
            if (st%fleet_mode) st%combined_cycle = .true.
        case ("fuel_price_usd_gj");    st%fuel_price_usd_gj = value
        case ("fleet_load_target_MW"); st%fleet_load_target_MW = value
        case ("gt1_online");           st%fleet_unit_online(FLEET_GT1) = value > 0.5_dp
        case ("gt2_online");           st%fleet_unit_online(FLEET_GT2) = value > 0.5_dp
        case ("cc1_online");           st%fleet_unit_online(FLEET_CC1) = value > 0.5_dp
        case ("location_profile")
            call apply_market_profile(st, nint(value))
        case ("weather_drive_renewables"); st%market_weather_enabled = value > 0.5_dp
        case ("load_replay");          st%market_load_replay_enabled = value > 0.5_dp
        case ("market_replay_day_s");  st%market_replay_day_s = max(1.0_dp, value)
        case ("renewable_scale_pct");  st%renewable_scale_pct = clamp_real(value, 0.0_dp, 200.0_dp)
        case ("power_price_usd_mwh");  st%power_price_usd_mwh = value
        case ("carbon_price_usd_t");   st%carbon_price_usd_t = max(0.0_dp, value)
        case ("fcr_price_usd_mw_h");   st%fcr_reserve_price_usd_mw_h = value
        ! New-module controls (P2X, CCS, GFM-BESS, MPC-AGC, tie-line, RL, H2)
        case ("h2_fraction_pct");      st%h2_fraction_pct = clamp_real(value, 0.0_dp, 30.0_dp)
        case ("p2x_active");           st%p2x_active = value > 0.5_dp
        case ("p2x_capacity_MW");      st%p2x_capacity_MW = max(0.0_dp, value)
        case ("ccs_active");           st%ccs_active = value > 0.5_dp
        case ("gfm_mode");             st%gfm_mode = value > 0.5_dp
        case ("gfm_virtual_H");        st%gfm_virtual_H = max(0.0_dp, value)
        case ("mpc_active");           st%mpc_active = value > 0.5_dp
        case ("tie_active");           st%tie_active = value > 0.5_dp
        case ("tie_scheduled_MW");     st%tie_scheduled_MW = value
        case ("rl_mode");              st%rl_mode = value > 0.5_dp
        case default
            ok = .false.
        end select
    end subroutine set_state_field

    !> Read any observable state value by name (assert targets).
    subroutine get_state_value(st, name, value, ok)
        type(GridState), intent(in) :: st
        character(len=*), intent(in) :: name
        real(dp), intent(out) :: value
        logical, intent(out) :: ok

        ok = .true.
        select case (trim(name))
        case ("demand_MW");             value = st%demand_MW
        case ("renewable_MW");          value = st%renewable_MW
        case ("renewable_actual_MW");   value = effective_renewable_MW(st)
        case ("renewable_curtail_MW");  value = st%renewable_curtail_MW
        case ("renewable_lfsmo_MW");    value = st%renewable_lfsmo_MW
        case ("storage_request_MW");    value = st%storage_request_MW
        case ("storage_MW");            value = st%storage_MW
        case ("battery_soc_pct");       value = st%battery_soc_pct
        case ("battery_energy_MWh");    value = st%battery_energy_MWh
        case ("gas_dispatch_pct");      value = st%gas_dispatch_pct
        case ("gas_power_MW");          value = st%gas_power_MW
        case ("gas_capacity_MW");       value = st%gas_capacity_MW
        case ("plant_power_MW");        value = st%plant_power_MW
        case ("plant_capacity_MW");     value = st%plant_capacity_MW
        case ("plant_efficiency");      value = st%plant_efficiency
        case ("plant_heat_rate_kJ_kWh"); value = st%heat_rate_kJ_kWh
        case ("gt_heat_rate_kJ_kWh");   value = st%gt_heat_rate_kJ_kWh
        case ("fleet_mode");            value = merge(1.0_dp, 0.0_dp, st%fleet_mode)
        case ("fuel_price_usd_gj");     value = st%fuel_price_usd_gj
        case ("fleet_total_MW");        value = st%fleet_total_MW
        case ("fleet_target_MW");       value = st%fleet_load_target_MW
        case ("fleet_reserve_MW");      value = st%fleet_reserve_MW
        case ("fleet_reserve_req_MW");  value = st%fleet_reserve_requirement_MW
        case ("fleet_reserve_binding"); value = merge(1.0_dp, 0.0_dp, st%fleet_reserve_binding)
        case ("fleet_unserved_MW");     value = st%fleet_unserved_dispatch_MW
        case ("fleet_inertia_MWs");     value = st%fleet_inertia_MWs
        case ("fleet_lmp_usd_MWh");     value = st%fleet_lmp_usd_MWh
        case ("fleet_marginal_unit");   value = real(st%fleet_marginal_unit, dp)
        case ("gt1_MW");                value = st%fleet_unit_actual_MW(FLEET_GT1)
        case ("gt1_sp_MW");             value = st%fleet_unit_setpoint_MW(FLEET_GT1)
        case ("gt1_cost_usd_MWh");      value = st%fleet_unit_cost_usd_MWh(FLEET_GT1)
        case ("gt1_participation");     value = st%fleet_unit_participation(FLEET_GT1)
        case ("gt1_online");            value = merge(1.0_dp, 0.0_dp, st%fleet_unit_online(FLEET_GT1))
        case ("gt2_MW");                value = st%fleet_unit_actual_MW(FLEET_GT2)
        case ("gt2_sp_MW");             value = st%fleet_unit_setpoint_MW(FLEET_GT2)
        case ("gt2_cost_usd_MWh");      value = st%fleet_unit_cost_usd_MWh(FLEET_GT2)
        case ("gt2_participation");     value = st%fleet_unit_participation(FLEET_GT2)
        case ("gt2_online");            value = merge(1.0_dp, 0.0_dp, st%fleet_unit_online(FLEET_GT2))
        case ("cc1_MW");                value = st%fleet_unit_actual_MW(FLEET_CC1)
        case ("cc1_sp_MW");             value = st%fleet_unit_setpoint_MW(FLEET_CC1)
        case ("cc1_cost_usd_MWh");      value = st%fleet_unit_cost_usd_MWh(FLEET_CC1)
        case ("cc1_participation");     value = st%fleet_unit_participation(FLEET_CC1)
        case ("cc1_online");            value = merge(1.0_dp, 0.0_dp, st%fleet_unit_online(FLEET_CC1))
        case ("location_profile");      value = real(st%market_profile_id, dp)
        case ("nominal_frequency_Hz");  value = st%nominal_frequency_Hz
        case ("power_price_usd_mwh");   value = st%power_price_usd_mwh
        case ("carbon_price_usd_t");    value = st%carbon_price_usd_t
        case ("co2_cost_usd_h");        value = st%co2_cost_usd_h
        case ("market_hour");           value = st%market_hour
        case ("weather_drive_renewables"); value = merge(1.0_dp, 0.0_dp, st%market_weather_enabled)
        case ("load_replay");           value = merge(1.0_dp, 0.0_dp, st%market_load_replay_enabled)
        case ("wind_speed_m_s");        value = st%market_wind_speed_m_s
        case ("solar_W_m2");            value = st%market_solar_W_m2
        case ("pv_power_MW");           value = st%market_pv_power_MW
        case ("wind_power_MW");         value = st%market_wind_power_MW
        case ("steam_power_MW");        value = st%steam_power_MW
        case ("steam_target_MW");       value = st%steam_power_target_MW
        case ("hrsg_pinch_K");          value = st%hrsg_pinch_K
        case ("hrsg_stack_T_K");        value = st%hrsg_stack_T_K
        case ("hrsg_steam_flow_kg_s");  value = st%hrsg_steam_flow_kg_s
        case ("surge_margin_pct");      value = st%surge_margin_pct
        case ("igv_pct");               value = st%igv_pct
        case ("TIT_actual_K");          value = st%TIT_actual_K
        case ("PR_op");                 value = st%PR_op
        case ("gas_ramp_pct_per_s");    value = st%gas_ramp_pct_per_s
        case ("supply_MW");             value = st%supply_MW
        case ("imbalance_MW");          value = st%imbalance_MW
        case ("reserve_MW");            value = st%reserve_MW
        case ("frequency_Hz");          value = st%frequency_Hz
        case ("ROCOF_Hz_s");            value = st%ROCOF_Hz_s
        case ("governor_delta_MW");     value = st%governor_delta_MW
        case ("BESS_primary_MW");       value = st%BESS_primary_MW
        case ("UFLS_stage");            value = real(st%UFLS_stage, dp)
        case ("UFLS_shed_fraction");    value = st%UFLS_shed_fraction
        case ("margin_usd_h");          value = st%margin_usd_h
        case ("value_stack_usd_h");     value = st%value_stack_usd_h
        case ("CO2_intensity_g_kWh");   value = st%CO2_intensity_g_kWh
        case ("CO2_cumulative_t");      value = st%CO2_cumulative_t
        case ("heat_rate_kJ_kWh");      value = st%heat_rate_kJ_kWh
        case ("exhaust_K");             value = st%exhaust_K
        case ("elapsed_s");             value = st%elapsed_s
        case ("auto_balance");          value = merge(1.0_dp, 0.0_dp, st%auto_balance)
        ! New-module observables
        case ("h2_fraction_pct");       value = st%h2_fraction_pct
        case ("h2_co2_avoided_t");      value = st%h2_co2_avoided_t
        case ("h2_mass_fraction");      value = st%h2_mass_fraction
        case ("h2_wobbe_mj_m3");        value = st%h2_wobbe_mj_m3
        case ("h2_wobbe_deviation_pct"); value = st%h2_wobbe_deviation_pct
        case ("h2_wobbe_ok");           value = merge(1.0_dp, 0.0_dp, st%h2_wobbe_ok)
        case ("flame_temp_ad_K");       value = st%flame_temp_ad_K
        case ("flame_temp_shift_K");    value = st%flame_temp_shift_K
        case ("nox_ppm_15o2");          value = st%nox_ppm_15o2
        case ("nox_mg_nm3_15o2");       value = st%nox_mg_nm3_15o2
        case ("co_ppm_15o2");           value = st%co_ppm_15o2
        case ("co_mg_nm3_15o2");        value = st%co_mg_nm3_15o2
        case ("stack_o2_dry_pct");      value = st%stack_o2_dry_pct
        case ("stack_co2_vol_pct");     value = st%stack_co2_vol_pct
        case ("combustion_lambda");     value = st%combustion_lambda
        case ("flashback_margin_pct");  value = st%flashback_margin_pct
        case ("cooling_air_pct");       value = st%turbine_cooling_air_pct
        case ("cooling_air_kg_s");      value = st%turbine_cooling_air_kg_s
        case ("metal_temp_margin_K");   value = st%turbine_metal_margin_K
        case ("tip_clearance_mm");      value = st%tip_clearance_mm
        case ("tip_loss_pct");          value = st%tip_loss_pct
        case ("compressor_poly_loss_pct"); value = st%compressor_poly_loss_pct
        case ("turbine_poly_loss_pct"); value = st%turbine_poly_loss_pct
        case ("p2x_active");            value = merge(1.0_dp, 0.0_dp, st%p2x_active)
        case ("p2x_load_MW");           value = st%p2x_load_MW
        case ("p2x_h2_kg_s");           value = st%p2x_h2_kg_s
        case ("ccs_active");            value = merge(1.0_dp, 0.0_dp, st%ccs_active)
        case ("ccs_parasitic_MW");      value = st%ccs_parasitic_MW
        case ("ccs_co2_captured_t_h");  value = st%ccs_co2_captured_t_h
        case ("gfm_mode");              value = merge(1.0_dp, 0.0_dp, st%gfm_mode)
        case ("gfm_synth_MW");          value = st%gfm_synth_MW
        case ("gfm_H_equiv");           value = st%gfm_H_equiv
        case ("mpc_active");            value = merge(1.0_dp, 0.0_dp, st%mpc_active)
        case ("mpc_setpt_MW");          value = st%mpc_setpt_MW
        case ("tie_active");            value = merge(1.0_dp, 0.0_dp, st%tie_active)
        case ("tie_flow_MW");           value = st%tie_flow_MW
        case ("ace_MW");                value = st%ace_MW
        case ("rl_mode");               value = merge(1.0_dp, 0.0_dp, st%rl_mode)
        case ("rl_cumreward");          value = st%rl_cumreward
        case default
            value = 0.0_dp
            ok = .false.
        end select
    end subroutine get_state_value

    ! ------------------------------------------------------------------
    ! Flight recorder
    ! ------------------------------------------------------------------

    subroutine open_recorder(path, unit, ok)
        character(len=*), intent(in) :: path
        integer, intent(out) :: unit
        logical, intent(out) :: ok
        integer :: ios

        open(newunit=unit, file=path, status='replace', action='write', iostat=ios)
        ok = ios == 0
        if (.not. ok) then
            write(*, '(A)') "   WARNING: cannot open recorder file '"//trim(path)//"'"
            return
        end if
        write(unit, '(A)') "time_s,frequency_Hz,nominal_frequency_Hz,ROCOF_Hz_s,"// &
            "demand_MW,supply_MW,imbalance_MW,gas_dispatch_pct,gas_power_MW,"// &
            "plant_power_MW,steam_power_MW,renewable_available_MW,renewable_actual_MW,"// &
            "renewable_curtail_MW,storage_request_MW,storage_MW,BESS_primary_MW,"// &
            "battery_soc_pct,reserve_MW,UFLS_stage,margin_usd_h,CO2_intensity_g_kWh,"// &
            "heat_rate_kJ_kWh,flame_temp_ad_K,nox_mg_nm3_15o2,co_mg_nm3_15o2,"// &
            "flashback_margin_pct,cooling_air_pct,tip_loss_pct,gfm_synth_MW,gfm_H_equiv,mpc_setpt_MW"
    end subroutine open_recorder

    subroutine record_row(unit, t_now, st)
        integer, intent(in) :: unit
        real(dp), intent(in) :: t_now
        type(GridState), intent(in) :: st

        write(unit, '(*(ES16.8,:,","))') t_now, st%frequency_Hz, st%nominal_frequency_Hz, &
            st%ROCOF_Hz_s, st%demand_MW, st%supply_MW, st%imbalance_MW, st%gas_dispatch_pct, &
            st%gas_power_MW, st%plant_power_MW, st%steam_power_MW, st%renewable_MW, &
            effective_renewable_MW(st), st%renewable_curtail_MW, st%storage_request_MW, &
            st%storage_MW, st%BESS_primary_MW, st%battery_soc_pct, st%reserve_MW, &
            real(st%UFLS_stage, dp), st%margin_usd_h, st%CO2_intensity_g_kWh, &
            st%heat_rate_kJ_kWh, st%flame_temp_ad_K, st%nox_mg_nm3_15o2, &
            st%co_mg_nm3_15o2, st%flashback_margin_pct, st%turbine_cooling_air_pct, &
            st%tip_loss_pct, st%gfm_synth_MW, st%gfm_H_equiv, st%mpc_setpt_MW
    end subroutine record_row

end module scenario_runner
