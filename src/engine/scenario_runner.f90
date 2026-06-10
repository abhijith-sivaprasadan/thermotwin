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
    use engine_core, only: engine_init, engine_step, refresh_model
    use dispatch_agc, only: balance_now, reset_controls, &
        apply_load_step, apply_cloud_ramp, apply_turbine_trip
    use tag_bus, only: tag_count, tag_name_at, tag_value_at
    implicit none
    private

    public :: Scenario, ScenarioEvent, scenario_load, scenario_run

    integer, parameter :: MAX_EVENTS = 96
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
            if (recording) call record_row(rec_unit, t)
        end do
        if (recording) close(rec_unit)

        if (n_failures == 0) then
            write(*, '(A,I0,A)') "PASS: scenario "//trim(sc%name)//" (", n_asserts, " assertions)"
        else
            write(*, '(A,I0,A,I0,A)') "FAIL: scenario "//trim(sc%name)//" (", n_failures, &
                " of ", n_asserts, " assertions failed)"
        end if
    end subroutine scenario_run

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
        integer :: ios, i

        open(newunit=unit, file=path, status='replace', action='write', iostat=ios)
        ok = ios == 0
        if (.not. ok) then
            write(*, '(A)') "   WARNING: cannot open recorder file '"//trim(path)//"'"
            return
        end if
        write(unit, '(A)', advance='no') "time_s"
        do i = 1, tag_count()
            write(unit, '(A)', advance='no') ","//trim(tag_name_at(i))
        end do
        write(unit, '(A)') ""
    end subroutine open_recorder

    subroutine record_row(unit, t_now)
        integer, intent(in) :: unit
        real(dp), intent(in) :: t_now
        integer :: i

        write(unit, '(ES16.8)', advance='no') t_now
        do i = 1, tag_count()
            write(unit, '(A,ES16.8)', advance='no') ",", tag_value_at(i)
        end do
        write(unit, '(A)') ""
    end subroutine record_row

end module scenario_runner
