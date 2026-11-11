!> Live alarm metadata, quality provenance, thresholds and trace regression.
program test_alarm_drilldown
    use precision_kinds, only: dp
    use engine_state
    use alarm_drilldown
    implicit none
    type(GridState) :: st
    type(DrillObservation) :: o
    type(DrillHistory) :: hist
    integer :: fail,i,idx
    fail=0
    st=GridState()
    st%gt_phase=GT_ONLINE
    st%grid_model_valid=.true.

    call drill_observe(st,1,o)
    call ck("50 Hz underfrequency limit is 49.5",o%valid .and. &
        abs(o%limit-49.5_dp)<1.0e-10_dp .and. o%lower_is_bad)
    st%nominal_frequency_Hz=60.0_dp
    st%frequency_Hz=59.2_dp
    st%alarm_underfreq=.true.
    call drill_observe(st,1,o)
    call ck("60 Hz limit follows actual nominal and current value",o%active .and. &
        abs(o%limit-59.5_dp)<1.0e-10_dp .and. abs(o%value-59.2_dp)<1.0e-10_dp)
    call ck("freq drill opens electrical rather than compressor context",o%diagram==DRILL_GRID)
    st%grid_model_valid=.false.
    call drill_observe(st,1,o)
    call ck("invalid frequency physics cannot produce a good measurement",.not.o%valid .and. &
        o%source==DRILL_SRC_NONE)

    st=GridState()
    st%gt_phase=GT_ONLINE
    st%effective_gas_dispatch_pct=99.6_dp
    st%alarm_turbine_max=.true.
    call drill_observe(st,6,o)
    call ck("GT upper alert is dispatch percent, not TIT",o%valid .and. o%active .and. &
        o%limit==99.5_dp .and. index(o%limit_note,"NOT A TIT TRIP")>0)
    st%surge_margin_pct=7.0_dp
    st%alarm_surge=.true.
    call drill_observe(st,7,o)
    call ck("surge display is original modeled 8 percent warning",o%valid .and. &
        o%limit==8.0_dp .and. o%diagram==DRILL_MAP)
    st%gt_phase=GT_RUNDOWN
    call drill_observe(st,7,o)
    call ck("offline compressor cannot render fictitious running-map value",.not.o%valid)

    st=GridState()
    st%fleet_mode=.true.
    st%reserve_MW=3.0_dp
    st%fleet_reserve_requirement_MW=8.0_dp
    call drill_observe(st,3,o)
    call ck("fleet reserve limit is actual scenario requirement, not 2 MW",o%limit==8.0_dp)
    st%combined_cycle=.false.
    call drill_observe(st,8,o)
    call ck("HRSG data unavailable when CC is not operating",.not.o%valid)
    st%combined_cycle=.true.
    st%fleet_mode=.false. ! single-GT HRSG is the supported drill source
    call drill_observe(st,8,o)
    call ck("HRSG uses actual model pinch feasibility threshold",o%valid .and. o%limit==15.0_dp)

    st=GridState()
    call drill_observe(st,DRILL_PLANT_N+EQ_OIL,o)
    call ck("missing lube oil transmitter NO DATA, not healthy fake number", &
        .not.o%valid .and. o%source==DRILL_SRC_NONE .and. &
        o%diagram==DRILL_FACEPLATE)
    st%eq_source(EQ_OIL)=EQ_SRC_TRAINING
    st%eq_training_present(EQ_OIL)=.true.
    st%eq_training_value(EQ_OIL)=0.8_dp
    st%eq_training_stamp_s(EQ_OIL)=0.0_dp
    st%elapsed_s=1.0_dp
    st%eq_value(EQ_OIL)=0.8_dp
    st%eq_alarm(EQ_OIL)=.true.
    call drill_observe(st,DRILL_PLANT_N+EQ_OIL,o)
    call ck("injected oil pressure explicitly TRAINING",o%valid .and. o%active .and. &
        o%source==DRILL_SRC_TRAIN .and. o%lower_is_bad .and. &
        abs(o%limit-1.2_dp)<1.0e-10_dp .and. abs(o%value-0.8_dp)<1.0e-10_dp)
    call ck("retains alarm clear hysteresis threshold",abs(o%clear_limit-1.8_dp)<1.0e-10_dp)
    st%elapsed_s=7.0_dp
    call drill_observe(st,DRILL_PLANT_N+EQ_OIL,o)
    call ck("cached TRAIN enum cannot mask a stale training sample",&
        .not.o%valid .and. o%source==DRILL_SRC_NONE)
    st%elapsed_s=1.0_dp
    st%eq_training_present(EQ_OIL)=.false.
    call drill_observe(st,DRILL_PLANT_N+EQ_OIL,o)
    call ck("cached TRAIN enum without underlying sample is NO DATA",.not.o%valid)
    st%eq_source(EQ_OIL)=EQ_SRC_UNAVAILABLE
    call drill_observe(st,DRILL_PLANT_N+EQ_OIL,o)
    call ck("source loss immediately changes context to NO DATA",.not.o%valid)

    hist=DrillHistory()
    do i=1,HISTORY_N+8
        st%elapsed_s=real(i,dp)*0.25_dp
        st%eq_source(EQ_OIL)=EQ_SRC_UNAVAILABLE
        st%eq_training_present(EQ_OIL)=.false.
        if(i>HISTORY_N+3) then
            st%eq_source(EQ_OIL)=EQ_SRC_TRAINING
            st%eq_training_present(EQ_OIL)=.true.
            st%eq_training_stamp_s(EQ_OIL)=st%elapsed_s
            st%eq_training_value(EQ_OIL)=real(i,dp)/100.0_dp
            st%eq_value(EQ_OIL)=st%eq_training_value(EQ_OIL)
        end if
        call drill_record(hist,st)
    end do
    call ck("actual ring wraps at 240, never padded with zero fake samples", &
        hist%count==HISTORY_N .and. hist%head==8)
    idx=drill_history_index(hist,1)
    call ck("oldest retained sample starts 8 records after initial", &
        abs(hist%time_s(idx)-2.25_dp)<1.0e-10_dp)
    idx=drill_history_index(hist,HISTORY_N)
    call ck("latest retained history is new timestamp", &
        abs(hist%time_s(idx)-real(HISTORY_N+8,dp)*0.25_dp)<1.0e-10_dp)
    call ck("recovered training data marks newest sample valid", &
        hist%valid(DRILL_PLANT_N+EQ_OIL,idx))
    idx=drill_history_index(hist,HISTORY_N-8)
    call ck("NO DATA gap is recorded as invalid, never drawn zero",&
        .not.hist%valid(DRILL_PLANT_N+EQ_OIL,idx))
    call ck("out-of-bounds trend read rejected",drill_history_index(hist,HISTORY_N+1)==0)

    call ck("top first strip routes to underfreq", &
        drill_annunciator_hit(15,20,0,0,800,38)==1)
    call ck("top last tile routes to pinch", &
        drill_annunciator_hit(740,20,0,0,800,38)==8)
    call ck("outside strip has no selection",&
        drill_annunciator_hit(700,75,0,0,800,38)==0)
    call ck("equipment row routes to compressor-source alarm on page 2",&
        drill_alarm_row_hit(25,127,0,122,650,2)==9) ! first equipment row = surge
    call ck("last equipment row does not target a fictitious 16th alarm",&
        drill_alarm_row_hit(25,122+7*48+10,0,122,650,2)==0)

    if(fail/=0) then
        print '(A,I0)',"FAIL alarm drilldown: ",fail
        stop 1
    end if
    print '(A)',"PASS alarm context mapping, quality, thresholds, ring trend and hit geometry"
contains
    subroutine ck(label,ok)
        character(len=*),intent(in) :: label
        logical,intent(in) :: ok
        if(.not.ok) then
            fail=fail+1
            print '(A,A)',"FAIL: ",label
        end if
    end subroutine ck
end program test_alarm_drilldown
