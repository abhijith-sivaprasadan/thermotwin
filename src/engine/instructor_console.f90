!> Instructor-only controls for the offline educational plant HMI.
!> This module does not actuate protection or create fictitious measurements.
!> Faults enter through the established qualified training-input monitor.
module instructor_console
    use precision_kinds, only: dp
    use engine_state, only: GridState, EQ_N, EQ_OIL, EQ_OVERSPEED, EQ_COMBUST, &
        EQ_BEARING, GT_ONLINE, DEMAND_MIN_MW, DEMAND_MAX_MW, RENEWABLE_MAX_MW
    use equipment_protection, only: set_equipment_training_input, clear_equipment_training_input
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private

    integer, parameter, public :: INSTR_LOG_N=16
    integer, parameter, public :: INSTR_LOAD_UP=1, INSTR_LOAD_DOWN=2, &
        INSTR_RENEWABLE_DROP=3, INSTR_AMBIENT_HOT=4
    integer, parameter, public :: INSTR_ACK=1, INSTR_RESET=2, INSTR_RESTART=3
    public :: InstructorSession, instructor_set_frozen, instructor_capture, &
        instructor_restore, instructor_inject_fault, instructor_clear_fault, &
        instructor_refresh_fault, instructor_change_boundary, instructor_observe, &
        instructor_operator_action, instructor_score

    type :: InstructorSession
        logical :: frozen=.false.
        logical :: saved=.false.
        type(GridState) :: saved_grid
        integer :: fault_id=0
        real(dp) :: fault_value=0.0_dp
        integer :: saved_fault_id=0
        real(dp) :: saved_fault_value=0.0_dp
        logical :: trip_seen=.false.
        integer :: ack_count=0
        integer :: reset_count=0
        integer :: restart_count=0
        integer :: unsafe_attempts=0
        integer :: log_count=0
        real(dp) :: log_s(INSTR_LOG_N)=0.0_dp
        character(len=72) :: log_text(INSTR_LOG_N)=''
    end type InstructorSession

contains

    subroutine log_instructor(s,st,message)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(in) :: st
        character(len=*),intent(in) :: message
        if(s%log_count==INSTR_LOG_N) then
            s%log_s(1:INSTR_LOG_N-1)=s%log_s(2:INSTR_LOG_N)
            s%log_text(1:INSTR_LOG_N-1)=s%log_text(2:INSTR_LOG_N)
            s%log_count=INSTR_LOG_N-1
        end if
        s%log_count=s%log_count+1
        s%log_s(s%log_count)=st%elapsed_s
        s%log_text(s%log_count)=message
    end subroutine log_instructor

    subroutine instructor_set_frozen(s,st,value)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(in) :: st
        logical,intent(in) :: value
        if(s%frozen.eqv.value) return
        s%frozen=value
        if(value) then
            call log_instructor(s,st,'INSTRUCTOR FREEZE - engine time halted')
        else
            call log_instructor(s,st,'INSTRUCTOR RESUME')
        end if
    end subroutine instructor_set_frozen

    subroutine instructor_capture(s,st)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(in) :: st
        s%saved_grid=st
        s%saved_fault_id=s%fault_id
        s%saved_fault_value=s%fault_value
        s%saved=.true.
        call log_instructor(s,st,'CAPTURE full GridState and instructor fault')
    end subroutine instructor_capture

    subroutine instructor_restore(s,st,accepted)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(inout) :: st
        logical,intent(out) :: accepted
        accepted=s%saved
        if(.not.accepted) return
        ! Restore all modeled accumulators, SOE and history, not just slider values.
        st=s%saved_grid
        s%fault_id=s%saved_fault_id
        s%fault_value=s%saved_fault_value
        s%frozen=.true. ! explicit resume required, no automatic advancement
        s%trip_seen=st%gt_phase/=GT_ONLINE
        s%ack_count=0
        s%reset_count=0
        s%restart_count=0
        s%unsafe_attempts=0
        s%log_count=0
        call log_instructor(s,st,'SNAPSHOT RESTORED - FROZEN; assessment reset')
    end subroutine instructor_restore

    subroutine instructor_inject_fault(s,st,id,value,accepted)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(inout) :: st
        integer,intent(in) :: id
        real(dp),intent(in) :: value
        logical,intent(out) :: accepted
        integer :: previous
        accepted=.false.
        if(id/=EQ_OIL.and.id/=EQ_OVERSPEED.and.id/=EQ_COMBUST.and.id/=EQ_BEARING) return
        if(.not.ieee_is_finite(value)) return
        if(s%frozen) return
        if(s%fault_id/=0.and.s%fault_id/=id) then
            previous=s%fault_id
            call clear_equipment_training_input(st,previous)
        end if
        call set_equipment_training_input(st,id,value,accepted)
        if(.not.accepted) return
        s%fault_id=id
        s%fault_value=value
        call log_instructor(s,st,'TRAINING fault injected (qualified by equipment monitor)')
    end subroutine instructor_inject_fault

    subroutine instructor_clear_fault(s,st)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(inout) :: st
        if(s%fault_id==0) return
        call clear_equipment_training_input(st,s%fault_id)
        s%fault_id=0
        s%fault_value=0.0_dp
        call log_instructor(s,st,'INJECTION CLEARED - missing sensor is NO DATA')
    end subroutine instructor_clear_fault

    subroutine instructor_refresh_fault(s,st)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(inout) :: st
        logical :: accepted
        if(s%frozen.or.s%fault_id==0) return
        ! Re-stamp each tick. The underlying model's 5 s freshness gate remains
        ! active; no stale-value bypass or simulated sensor hidden as measured.
        call set_equipment_training_input(st,s%fault_id,s%fault_value,accepted)
        if(.not.accepted) call instructor_clear_fault(s,st)
    end subroutine instructor_refresh_fault

    subroutine instructor_change_boundary(s,st,action,accepted)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(inout) :: st
        integer,intent(in) :: action
        logical,intent(out) :: accepted
        accepted=.false.
        if(s%frozen) return
        select case(action)
        case(INSTR_LOAD_UP)
            st%demand_MW=min(DEMAND_MAX_MW,st%demand_MW+10.0_dp)
        case(INSTR_LOAD_DOWN)
            st%demand_MW=max(DEMAND_MIN_MW,st%demand_MW-10.0_dp)
        case(INSTR_RENEWABLE_DROP)
            st%renewable_MW=max(0.0_dp,st%renewable_MW-8.0_dp)
        case(INSTR_AMBIENT_HOT)
            st%ambient_C=min(60.0_dp,st%ambient_C+5.0_dp)
        case default
            return
        end select
        st%renewable_MW=min(RENEWABLE_MAX_MW,st%renewable_MW)
        accepted=.true.
        call log_instructor(s,st,'INSTRUCTOR boundary changed; engine solves next tick')
    end subroutine instructor_change_boundary

    subroutine instructor_observe(s,st)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(in) :: st
        if(.not.s%trip_seen.and.st%gt_phase/=GT_ONLINE) then
            s%trip_seen=.true.
            call log_instructor(s,st,'FIRST OUT / GT trip recognized by instructor')
        end if
    end subroutine instructor_observe

    subroutine instructor_operator_action(s,st,action,accepted)
        type(InstructorSession),intent(inout) :: s
        type(GridState),intent(in) :: st
        integer,intent(in) :: action
        logical,intent(in) :: accepted
        select case(action)
        case(INSTR_ACK)
            if(accepted.and.s%trip_seen) s%ack_count=s%ack_count+1
            if(.not.accepted) s%unsafe_attempts=s%unsafe_attempts+1
            call log_instructor(s,st,'OPERATOR first-out ACK evaluated')
        case(INSTR_RESET)
            if(accepted.and.s%trip_seen.and.st%gt_first_out/=0) then
                s%reset_count=s%reset_count+1
            else if(.not.accepted) then
                s%unsafe_attempts=s%unsafe_attempts+1
            end if
            call log_instructor(s,st,'OPERATOR reset request evaluated')
        case(INSTR_RESTART)
            if(accepted.and.s%trip_seen) then
                s%restart_count=s%restart_count+1
            else if(.not.accepted) then
                s%unsafe_attempts=s%unsafe_attempts+1
            end if
            call log_instructor(s,st,'OPERATOR restart request evaluated')
        end select
    end subroutine instructor_operator_action

    pure integer function instructor_score(s) result(score)
        type(InstructorSession),intent(in) :: s
        score=0
        if(s%trip_seen) score=20
        if(s%ack_count>0) score=score+30
        if(s%reset_count>0) score=score+30
        if(s%restart_count>0) score=score+20
        score=max(0,score-5*s%unsafe_attempts)
    end function instructor_score
end module instructor_console
