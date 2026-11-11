!> Independent trip-state and plant-boundary regression tests.
program test_gt_trip_sequence
    use precision_kinds, only: dp
    use engine_state
    use gt_trip_sequence
    use engine_core, only: engine_init, engine_step, refresh_model, &
         apply_turbine_trip, reset_controls, balance_now
    implicit none
    type(GridState) :: st, out, ft, guard
    integer :: failures, k, old_cause, event_n
    real(dp) :: before_t, older_speed
    logical :: accepted
    failures=0

    ! Test that old GT TRIP no longer means reducing to 20% dispatch.
    call engine_init(st)
    call check("nominal GT power is nonzero",st%gas_power_MW>0.0_dp)
    call check("nominal input is nonzero",st%fuel_flow_kg_s>0.0_dp)
    st%combined_cycle=.true.
    call refresh_model(st)
    call apply_turbine_trip(st)
    call check("operator trip latches",st%gt_trip_latched)
    call check("one first-out cause",st%gt_first_out==GT_CAUSE_MANUAL)
    call check("first-out has simulation timestamp",st%gt_first_out_s==st%elapsed_s)
    call check("breaker open and fuel isolated immediately",&
       .not.st%gt_breaker_closed .and. .not.st%gt_fuel_valve_open)
    call refresh_model(st)
    call check("tripped GT breaker output zero",st%gas_power_MW==0.0_dp)
    call check("trip fuel and combustion input zero",&
       st%fuel_flow_kg_s==0.0_dp .and. st%heat_input_MW==0.0_dp)
    call check("steam-only coast residual can remain",&
       st%plant_power_MW>=0.0_dp .and. st%plant_power_MW==st%steam_power_MW)
    call check("net supply accounts for independent renewable and BESS",&
       abs(st%supply_MW-(st%plant_power_MW+effective_renewable_MW(st)+st%storage_MW))<1.0e-8_dp)
    call check("trip does not carry fabricated GT reserve",st%gas_capacity_MW==0.0_dp)
    before_t=st%elapsed_s
    call balance_now(st)
    call check("BALANCE cannot restart tripped plant",st%gas_dispatch_pct==0.0_dp)
    call reset_controls(st)
    call check("RESET cannot erase trip latch or change sim time",&
       st%gt_trip_latched .and. st%elapsed_s==before_t)
    ! Even if a caller wrongly toggles fleet_mode, protection boundary wins.
    st%fleet_total_MW=45.0_dp
    st%fleet_mode=.true.
    call check("thermal power dispatch cannot bypass tripped GT latch", &
        abs(thermal_generation_MW(st)-(st%gas_power_MW+st%steam_power_MW))<1.0e-9_dp)
    st%fleet_mode=.false.
    event_n=st%gt_trip_seq
    old_cause=st%gt_first_out
    call gt_trip_request(st,GT_CAUSE_OIL,accepted)
    call check("repeated condition cannot overwrite first out",&
       .not.accepted .and. st%gt_first_out==old_cause .and. st%gt_trip_seq==event_n)

    call engine_step(st,0.25_dp)
    call check("coastdown begins",st%gt_phase==GT_RUNDOWN)
    call check("tripped physics still zero output after AGC tick", &
       st%gas_power_MW==0.0_dp .and. st%fuel_flow_kg_s==0.0_dp)
    call check("no fuel cost or CO2 during fuel-isolated coast", &
       st%fuel_cost_usd_h==0.0_dp .and. st%CO2_rate_kg_s==0.0_dp)
    call check("plant supply and demand remain energetically reconciled",&
       abs(st%supply_MW-st%demand_MW-st%imbalance_MW)<1.0e-8_dp)
    older_speed=st%gt_rotor_est_pct
    call engine_step(st,0.25_dp)
    call check("synthetic rotor rundown monotone",st%gt_rotor_est_pct<older_speed)
    call check("no automatic restart on following tick",&
       st%gt_phase/=GT_ONLINE .and. st%gas_power_MW==0.0_dp)
    call check("first-out event logged",st%gt_trip_log_count>=4)
    call engine_step(st,0.25_dp)
    call engine_step(st,0.25_dp)
    call check("offline turbine cannot show green STATUS OK", &
        index(st%advisory_text,"SIM GT OFFLINE")>0 .and. &
        index(st%advisory_text,"STATUS OK")==0)
    call check("trip advisory must not recommend increasing GT dispatch", &
        index(st%advisory_text,"increase GT dispatch")==0)

    ! Isolated state machine: do not rely on selftest nominal operating data.
    call gt_trip_reset_state(out)
    out%ambient_C=15.0_dp
    out%exhaust_K=800.0_dp
    out%steam_power_MW=5.0_dp
    out%combined_cycle=.true.
    call gt_trip_request(out,GT_CAUSE_MANUAL,accepted)
    call check("direct trip accepted",accepted)
    call gt_trip_reset_latch(out,accepted)
    call check("reset before ACK/rundown denied",.not.accepted .and. out%gt_trip_latched)
    call gt_trip_acknowledge(out)
    call check("ACK does not reset trip",out%gt_trip_ack .and. out%gt_trip_latched)
    do k=1,800
        out%elapsed_s=out%elapsed_s+0.25_dp
        call gt_trip_advance(out,0.25_dp)
        if(out%gt_phase==GT_LOCKOUT .and. &
           out%gt_exhaust_est_K<=out%ambient_C+273.15_dp+200.0_dp) exit
    end do
    call check("rundown reaches lockout",out%gt_phase==GT_LOCKOUT)
    call check("turning gear assumption shown only at rotor rest",out%gt_turning_gear_on)
    call check("required unavailable sensors block reset by default",&
       btest(gt_trip_permit_mask(out),3))
    call gt_trip_reset_latch(out,accepted)
    call check("reset denied when sensor input missing",.not.accepted)
    call gt_trip_toggle_training_bypass(out)
    call check("operator has to enable explicit educational bypass",out%gt_training_bypass)
    call check("remaining reset mask clear",gt_trip_permit_mask(out)==0)
    out%eq_alarm(EQ_OIL)=.true.
    call check("training bypass cannot override a real standing alarm",&
       btest(gt_trip_permit_mask(out),2))
    out%eq_alarm(EQ_OIL)=.false.
    call gt_trip_reset_latch(out,accepted)
    call check("acknowledged safe educational reset accepted",accepted .and. out%gt_phase==GT_READY)
    call check("reset does not spontaneously restart generation",&
       .not.out%gt_breaker_closed .and. .not.out%gt_fuel_valve_open)
    out%eq_alarm(EQ_OVERSPEED)=.true.
    call gt_trip_start(out,accepted)
    call check("restart blocked by standing overspeed condition",.not.accepted)
    out%eq_alarm(EQ_OVERSPEED)=.false.
    call gt_trip_start(out,accepted)
    call check("start enters purging with fuel and breaker isolated",&
       accepted .and. out%gt_phase==GT_PURGING .and. &
       .not.out%gt_breaker_closed .and. .not.out%gt_fuel_valve_open)
    do k=1,240
        out%elapsed_s=out%elapsed_s+0.25_dp
        call gt_trip_advance(out,0.25_dp)
        call gt_trip_apply_boundary(out)
        if(out%gt_phase==GT_ONLINE) exit
        call check("never electrically generate before synchronizing",&
            out%gas_power_MW==0.0_dp .and. .not.out%gt_breaker_closed)
        if(out%gt_phase==GT_PURGING) then
            call check("purge timer never marks flame present",.not.out%gt_flame_on)
        end if
    end do
    call check("illustrative startup reaches ONLINE",out%gt_phase==GT_ONLINE)
    call check("breaker closes only at end of startup",out%gt_breaker_closed)
    call check("training bypass not left permanently asserted",.not.out%gt_training_bypass)
    call check("first-out event remains in historical log",out%gt_first_out==GT_CAUSE_MANUAL)

    ! Training auto-trigger: only an actual supplied, qualified training point
    ! can cause protection trip; model-only warning cannot become OEM trip.
    call gt_trip_reset_state(ft)
    ft%eq_alarm(EQ_SURGE)=.true.
    ft%eq_source(EQ_SURGE)=EQ_SRC_MODEL
    call gt_trip_monitor(ft)
    call check("modeled surge margin alone is NOT automatic trip",ft%gt_phase==GT_ONLINE)
    ft%eq_alarm(EQ_OVERSPEED)=.true.
    ft%eq_source(EQ_OVERSPEED)=EQ_SRC_UNAVAILABLE
    call gt_trip_monitor(ft)
    call check("unavailable overspeed cannot falsely trip",ft%gt_phase==GT_ONLINE)
    ft%eq_source(EQ_OVERSPEED)=EQ_SRC_TRAINING
    call gt_trip_monitor(ft)
    call check("qualified training overspeed triggers first out",&
       ft%gt_phase==GT_TRIPPED .and. ft%gt_first_out==GT_CAUSE_OVERSPEED)

    call gt_trip_reset_state(ft)
    ft%fleet_mode=.true.
    call gt_trip_request(ft,GT_CAUSE_MANUAL,accepted)
    call check("unmodeled fleet single-unit trip not falsely presented",&
       .not.accepted .and. ft%gt_phase==GT_ONLINE)

    ! Restart interlocks must remain asserted for the entire simulated
    ! start, including a final check before the breaker may close.
    call gt_trip_reset_state(guard)
    guard%gt_phase=GT_READY
    guard%gt_training_bypass=.true.
    guard%gt_pretrip_fuel_kg_s=1.0_dp
    call gt_trip_start(guard,accepted)
    call check("guarded educational startup begins",accepted)
    call gt_trip_toggle_training_bypass(guard)
    call gt_trip_advance(guard,0.25_dp)
    call check("withdrawn bypass aborts an in-progress start", &
        guard%gt_phase==GT_TRIPPED .and. guard%gt_trip_latched .and. &
        guard%gt_first_out==GT_CAUSE_START_ABORT .and. &
        .not.guard%gt_breaker_closed .and. .not.guard%gt_fuel_valve_open)
    call check("start abort preserves historical log and fuel reference", &
        guard%gt_trip_log_count>=3 .and. &
        guard%gt_pretrip_fuel_kg_s==1.0_dp .and. guard%fuel_flow_kg_s==0.0_dp)

    call gt_trip_reset_state(guard)
    guard%gt_phase=GT_READY
    guard%gt_training_bypass=.true.
    call gt_trip_start(guard,accepted)
    guard%eq_alarm(EQ_OIL)=.true.
    guard%eq_source(EQ_OIL)=EQ_SRC_TRAINING
    call gt_trip_advance(guard,0.25_dp)
    call check("new training oil alarm aborts start with specific first-out", &
        guard%gt_phase==GT_TRIPPED .and. guard%gt_first_out==GT_CAUSE_OIL)

    call gt_trip_reset_state(guard)
    guard%gt_phase=GT_READY
    guard%elapsed_s=10.0_dp
    guard%eq_source(EQ_OVERSPEED)=EQ_SRC_TRAINING
    guard%eq_source(EQ_COMBUST)=EQ_SRC_TRAINING
    guard%eq_source(EQ_OIL)=EQ_SRC_TRAINING
    guard%eq_source(EQ_BEARING)=EQ_SRC_TRAINING
    guard%eq_training_present=.true.
    guard%eq_training_value=1.0_dp
    guard%eq_training_stamp_s=0.0_dp
    call check("cached TRAIN sources are insufficient when samples are stale", &
        btest(gt_trip_restart_mask(guard),3))

    call gt_trip_reset_state(guard)
    guard%gt_phase=GT_SYNCHRONIZING
    guard%gt_training_bypass=.true.
    guard%gt_phase_s=GT_SYNC_DEMO_S-0.1_dp
    guard%eq_alarm(EQ_BEARING)=.true.
    call gt_trip_advance(guard,0.25_dp)
    call check("standing alarm blocks simulated sync breaker closure", &
        guard%gt_phase==GT_TRIPPED .and. .not.guard%gt_breaker_closed)

    if(failures>0) then
        write(*,'("FAIL GT trip validation: ",I0)') failures
        stop 1
    end if
    print '(A)',"PASS GT trip first-out, fuel/breaker, model boundary and restart gating"
contains
    subroutine check(label,ok)
        character(len=*),intent(in) :: label
        logical,intent(in) :: ok
        if(.not.ok) then
            failures=failures+1
            print '(A,A)',"FAIL: ",label
        end if
    end subroutine check
end program test_gt_trip_sequence
