!> Instructor-session regression. Uses the real engine protection path.
program test_instructor_console
    use precision_kinds, only: dp
    use engine_state
    use engine_core, only: engine_init, engine_step
    use instructor_console
    implicit none
    type(GridState) :: st
    type(InstructorSession) :: session
    integer :: fails,k
    logical :: ok
    real(dp) :: old_time, before_demand
    fails=0
    call engine_init(st)
    before_demand=st%demand_MW
    call instructor_capture(session,st)
    call ck('snapshot stored',session%saved)
    call instructor_change_boundary(session,st,INSTR_LOAD_UP,ok)
    call ck('boundary change accepted',ok.and.st%demand_MW==before_demand+10.0_dp)
    call instructor_set_frozen(session,st,.true.)
    old_time=st%elapsed_s
    call instructor_change_boundary(session,st,INSTR_LOAD_UP,ok)
    call ck('frozen controls reject boundary mutation',.not.ok.and.st%demand_MW==before_demand+10.0_dp)
    ! The GUI intentionally does NOT call engine_step while frozen.
    call ck('freeze does not modify simulation time',st%elapsed_s==old_time)
    call instructor_set_frozen(session,st,.false.)
    call instructor_inject_fault(session,st,EQ_SURGE,0.0_dp,ok)
    call ck('cannot inject model-derived compressor map values',.not.ok)
    call instructor_inject_fault(session,st,EQ_OIL,0.70_dp,ok)
    call ck('training oil input accepted',ok.and.session%fault_id==EQ_OIL)
    do k=1,7
        call instructor_refresh_fault(session,st)
        call engine_step(st,0.25_dp)
        call instructor_observe(session,st)
    end do
    call ck('instructor oil fault activates qualified trip, not direct state edit', &
        st%gt_phase/=GT_ONLINE.and.st%gt_first_out==GT_CAUSE_OIL)
    call ck('first-out and closed fuel model persist', &
        .not.st%gt_breaker_closed.and..not.st%gt_fuel_valve_open)
    call ck('instructor observes protected trip',session%trip_seen)
    call instructor_operator_action(session,st,INSTR_RESET,.false.)
    call ck('denied reset is not a passing action', &
        session%reset_count==0.and.session%unsafe_attempts==1)
    call instructor_operator_action(session,st,INSTR_ACK,.true.)
    call ck('ACK earns only training credit',session%ack_count==1.and.instructor_score(session)==45)
    call instructor_clear_fault(session,st)
    call engine_step(st,0.25_dp)
    call ck('removed oil input becomes NO DATA (not normal)', &
        st%eq_source(EQ_OIL)==EQ_SRC_UNAVAILABLE)
    call instructor_restore(session,st,ok)
    call ck('snapshot restore succeeds and halts time',ok.and.session%frozen)
    call ck('restored model demand and generator state are exact', &
        st%demand_MW==before_demand.and.st%gt_phase==GT_ONLINE.and.st%elapsed_s==old_time)
    call ck('restore also clears active fault and assessment counters', &
        session%fault_id==0.and.instructor_score(session)==0)
    call instructor_inject_fault(session,st,EQ_COMBUST,7.0_dp,ok)
    call ck('frozen instructor cannot inject',.not.ok)
    call instructor_set_frozen(session,st,.false.)
    call instructor_inject_fault(session,st,EQ_OVERSPEED,115.0_dp,ok)
    call ck('second training fault supported',ok)
    do k=1,24
        call instructor_refresh_fault(session,st)
        call engine_step(st,0.25_dp)
    end do
    call ck('continual instructor injection never silently goes stale', &
        st%eq_source(EQ_OVERSPEED)==EQ_SRC_TRAINING)
    call ck('overspeed routed through protection monitor',st%gt_first_out==GT_CAUSE_OVERSPEED)

    if(fails/=0) then
        write(*,'(A,I0)') 'FAIL instructor console: ',fails
        stop 1
    end if
    print '(A)', 'PASS instructor console'
contains
    subroutine ck(message,pass)
        character(len=*),intent(in) :: message
        logical,intent(in) :: pass
        if(pass) then
            print '(A)', 'PASS: '//message
        else
            print '(A)', 'FAIL: '//message
            fails=fails+1
        end if
    end subroutine ck
end program test_instructor_console
