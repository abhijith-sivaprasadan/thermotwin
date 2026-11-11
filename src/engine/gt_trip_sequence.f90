!> Pedagogical turbine trip/restart *simulation*. Not a safety PLC.
!> Hard boundaries: no inferred OEM shaft speed, ignition control, purge
!> measurement, lube pump telemetry, or certified restart permissive.
module gt_trip_sequence
    use precision_kinds, only: dp
    use engine_state
    use equipment_protection, only: EQ_INPUT_STALE_S
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    public :: gt_trip_reset_state, gt_trip_request, gt_trip_monitor, gt_trip_advance
    public :: gt_trip_apply_boundary, gt_trip_acknowledge, gt_trip_reset_latch
    public :: gt_trip_start, gt_trip_toggle_training_bypass
    public :: gt_trip_phase_text, gt_trip_cause_text, gt_trip_permit_mask
    public :: gt_trip_restart_mask, gt_trip_reason_for_mask

    ! Durations and first-order time constants are intentionally illustrative.
    real(dp), parameter, public :: GT_COAST_TAU_S = 11.0_dp
    real(dp), parameter, public :: GT_COOL_TAU_S = 45.0_dp
    real(dp), parameter, public :: GT_PURGE_DEMO_S = 12.0_dp
    real(dp), parameter, public :: GT_IGNITION_DEMO_S = 4.0_dp
    real(dp), parameter, public :: GT_ACCEL_DEMO_S = 20.0_dp
    real(dp), parameter, public :: GT_SYNC_DEMO_S = 3.0_dp
    real(dp), parameter :: GT_STOP_RPM_PCT = 3.0_dp
    real(dp), parameter :: GT_RESET_HOT_MARGIN_K = 200.0_dp
    ! Mask bits: 1 phase, 2 ACK, 4 standing condition, 8 unavailable
    ! instrument, 16 rotor, 32 hot-case, 64 unsupported fleet mode.
contains
    subroutine gt_log(st,detail)
        type(GridState), intent(inout) :: st
        character(len=*),intent(in) :: detail
        integer :: n
        if(st%gt_trip_log_count>=GT_TRIP_LOG_N) then
            st%gt_trip_log_s(1:GT_TRIP_LOG_N-1)=st%gt_trip_log_s(2:GT_TRIP_LOG_N)
            st%gt_trip_log_text(1:GT_TRIP_LOG_N-1)=st%gt_trip_log_text(2:GT_TRIP_LOG_N)
        else
            st%gt_trip_log_count=st%gt_trip_log_count+1
        end if
        n=st%gt_trip_log_count
        st%gt_trip_log_s(n)=st%elapsed_s
        st%gt_trip_log_text(n)=detail
        st%gt_trip_seq=st%gt_trip_seq+1
    end subroutine gt_log

    subroutine gt_trip_reset_state(st)
        type(GridState),intent(inout) :: st
        ! Explicitly permitted ONLY when creating a new simulation run.
        st%gt_phase=GT_ONLINE
        st%gt_first_out=GT_CAUSE_NONE
        st%gt_first_out_s=-1.0_dp
        st%gt_phase_s=0.0_dp
        st%gt_rotor_est_pct=100.0_dp
        st%gt_exhaust_est_K=st%ambient_C+273.15_dp
        st%gt_steam_decay_MW=0.0_dp
        st%gt_pretrip_fuel_kg_s=0.0_dp
        st%gt_trip_latched=.false.
        st%gt_trip_ack=.false.
        st%gt_training_bypass=.false.
        st%gt_breaker_closed=.true.
        st%gt_fuel_valve_open=.true.
        st%gt_flame_on=.true.
        st%gt_blowoff_open=.false.
        st%gt_lube_support_on=.true.
        st%gt_turning_gear_on=.false.
        st%gt_purge_timer_done=.false.
        st%gt_trip_seq=0
        st%gt_trip_log_count=0
        st%gt_trip_log_s=0.0_dp
        st%gt_trip_log_text=""
        st%gt_trip_last_denial=""
    end subroutine gt_trip_reset_state

    subroutine gt_trip_request(st,cause,accepted)
        type(GridState),intent(inout) :: st
        integer,intent(in) :: cause
        logical,intent(out) :: accepted
        logical :: was_online
        accepted=.false.
        was_online=(st%gt_phase==GT_ONLINE)
        if(cause<GT_CAUSE_MANUAL .or. cause>GT_CAUSE_START_ABORT) return
        if(st%fleet_mode) then
            st%gt_trip_last_denial="Single-GT trip is not supported in fleet-mode"
            return
        end if
        if(st%gt_phase==GT_TRIPPED .or. st%gt_phase==GT_RUNDOWN .or. &
           st%gt_phase==GT_LOCKOUT) return
        accepted=.true.
        st%gt_phase=GT_TRIPPED
        st%gt_phase_s=0.0_dp
        st%gt_first_out=cause
        st%gt_first_out_s=st%elapsed_s
        st%gt_trip_latched=.true.
        st%gt_trip_ack=.false.
        st%gt_breaker_closed=.false.
        st%gt_fuel_valve_open=.false.
        st%gt_flame_on=.false.
        st%gt_blowoff_open=.true.
        st%gt_lube_support_on=.true.
        st%gt_turning_gear_on=.false.
        st%gt_purge_timer_done=.false.
        ! Keep estimated speed unchanged on an aborted simulated startup.
        if(was_online) st%gt_rotor_est_pct=max(15.0_dp,st%gt_rotor_est_pct)
        st%gt_exhaust_est_K=max(st%ambient_C+273.15_dp,st%exhaust_K)
        st%gt_steam_decay_MW=max(0.0_dp,st%steam_power_MW)
        ! Keep original online fuel reference through repeated start attempts.
        if(was_online) st%gt_pretrip_fuel_kg_s=max(0.0_dp,st%fuel_flow_kg_s)
        st%gas_dispatch_pct=0.0_dp
        st%effective_gas_dispatch_pct=0.0_dp
        st%governor_offset_pct=0.0_dp
        st%governor_delta_MW=0.0_dp
        st%prev_gas_dispatch_pct=0.0_dp
        st%gas_ramp_pct_per_s=0.0_dp
        st%ccs_active=.false.   ! absorber receives no guaranteed firing
        st%mpc_active=.false.   ! no dispatch optimiser can override fuel isolation
        st%rl_mode=.false.
        st%dnn_adapting=.false.
        st%gt_trip_last_denial=""
        call gt_log(st,"FIRST OUT: "//trim(gt_trip_cause_text(cause)))
        call gt_log(st,"BREAKER OPEN / FUEL VALVES SHUT / FLAME OUT (SIM)")
        call gt_log(st,"LUBE SUPPORT HELD / BLOWOFF OPEN (ASSUMED)")
    end subroutine gt_trip_request

    subroutine gt_trip_monitor(st)
        type(GridState),intent(inout) :: st
        logical :: accepted
        if(st%gt_phase/=GT_ONLINE .and. st%gt_phase/=GT_READY .and. &
           st%gt_phase/=GT_PURGING .and. st%gt_phase/=GT_IGNITING .and. &
           st%gt_phase/=GT_ACCELERATING .and. st%gt_phase/=GT_SYNCHRONIZING) return
        if(st%eq_source(EQ_OVERSPEED)==EQ_SRC_TRAINING .and. st%eq_alarm(EQ_OVERSPEED)) then
            call gt_trip_request(st,GT_CAUSE_OVERSPEED,accepted)
        else if(st%eq_source(EQ_OIL)==EQ_SRC_TRAINING .and. st%eq_alarm(EQ_OIL)) then
            call gt_trip_request(st,GT_CAUSE_OIL,accepted)
        else if(st%eq_source(EQ_COMBUST)==EQ_SRC_TRAINING .and. st%eq_alarm(EQ_COMBUST)) then
            call gt_trip_request(st,GT_CAUSE_COMBUST,accepted)
        end if
        ! A modeled surge margin or grid-frequency proxy is a warning, not
        ! an independently proven protective trip condition.
    end subroutine gt_trip_monitor

    subroutine gt_trip_advance(st,dt)
        type(GridState),intent(inout) :: st
        real(dp),intent(in) :: dt
        real(dp) :: ambient_K, alpha
        integer :: mask, abort_cause
        logical :: accepted
        character(len=96) :: denial
        if(.not.ieee_is_finite(dt) .or. dt<=0.0_dp) return
        if(st%gt_phase==GT_ONLINE) return
        ! Check each start step, including the instant before breaker closure.
        ! The phase bit is intentionally ignored during the start sequence.
        if(st%gt_phase>=GT_PURGING .and. st%gt_phase<=GT_SYNCHRONIZING) then
            mask=ibclr(gt_trip_restart_mask(st),0)
            if(mask/=0) then
                denial=gt_trip_reason_for_mask(mask)
                abort_cause=GT_CAUSE_START_ABORT
                if(st%eq_source(EQ_OVERSPEED)==EQ_SRC_TRAINING .and. &
                   st%eq_alarm(EQ_OVERSPEED)) abort_cause=GT_CAUSE_OVERSPEED
                if(st%eq_source(EQ_OIL)==EQ_SRC_TRAINING .and. &
                   st%eq_alarm(EQ_OIL)) abort_cause=GT_CAUSE_OIL
                if(st%eq_source(EQ_COMBUST)==EQ_SRC_TRAINING .and. &
                   st%eq_alarm(EQ_COMBUST)) abort_cause=GT_CAUSE_COMBUST
                call gt_trip_request(st,abort_cause,accepted)
                if(accepted) then
                    st%gt_trip_last_denial=denial
                    call gt_log(st,"SIM START ABORT / "//trim(denial))
                    call gt_trip_apply_boundary(st)
                end if
                return
            end if
        end if
        ambient_K=st%ambient_C+273.15_dp
        st%gt_phase_s=st%gt_phase_s+dt
        select case(st%gt_phase)
        case(GT_TRIPPED)
            st%gt_phase=GT_RUNDOWN
            st%gt_phase_s=0.0_dp
            call gt_log(st,"RUNDOWN BEGIN / ROTOR SPEED ESTIMATE ONLY")
        case(GT_RUNDOWN)
            st%gt_rotor_est_pct=st%gt_rotor_est_pct*exp(-dt/GT_COAST_TAU_S)
            st%gt_exhaust_est_K=ambient_K+max(0.0_dp,st%gt_exhaust_est_K-ambient_K) * &
                exp(-dt/GT_COOL_TAU_S)
            st%gt_steam_decay_MW=max(0.0_dp,st%gt_steam_decay_MW-0.45_dp*dt)
            if(st%gt_rotor_est_pct<=GT_STOP_RPM_PCT) then
                st%gt_rotor_est_pct=0.0_dp
                st%gt_turning_gear_on=.true.
                st%gt_blowoff_open=.false.
                st%gt_phase=GT_LOCKOUT
                st%gt_phase_s=0.0_dp
                call gt_log(st,"ROTOR REST ESTIMATED / TURNING GEAR ASSUMED")
            end if
        case(GT_LOCKOUT,GT_READY)
            st%gt_exhaust_est_K=ambient_K+max(0.0_dp,st%gt_exhaust_est_K-ambient_K) * &
                exp(-dt/GT_COOL_TAU_S)
            st%gt_steam_decay_MW=max(0.0_dp,st%gt_steam_decay_MW-0.45_dp*dt)
        case(GT_PURGING)
            ! No airflow or hydrocarbon concentrations are modeled. Timer only.
            if(st%gt_phase_s>=GT_PURGE_DEMO_S) then
                st%gt_purge_timer_done=.true.
                st%gt_phase=GT_IGNITING
                st%gt_phase_s=0.0_dp
                st%gt_fuel_valve_open=.true.
                st%gt_flame_on=.true. ! simulated flame proof
                st%gt_turning_gear_on=.false.
                call gt_log(st,"SIM PURGE TIMER DONE / IGNITION ASSUMED")
            end if
        case(GT_IGNITING)
            st%gt_rotor_est_pct=min(15.0_dp,15.0_dp*st%gt_phase_s/GT_IGNITION_DEMO_S)
            if(st%gt_phase_s>=GT_IGNITION_DEMO_S) then
                st%gt_phase=GT_ACCELERATING
                st%gt_phase_s=0.0_dp
                call gt_log(st,"IGNITION TIMER / SIM ACCELERATION")
            end if
        case(GT_ACCELERATING)
            alpha=min(1.0_dp,st%gt_phase_s/GT_ACCEL_DEMO_S)
            st%gt_rotor_est_pct=15.0_dp+85.0_dp*alpha
            if(alpha>=1.0_dp) then
                st%gt_phase=GT_SYNCHRONIZING
                st%gt_phase_s=0.0_dp
                call gt_log(st,"AT SIM RATED SPEED / SYNCH CHECK ASSUMED")
            end if
        case(GT_SYNCHRONIZING)
            if(st%gt_phase_s>=GT_SYNC_DEMO_S) then
                st%gt_breaker_closed=.true.
                st%gt_phase=GT_ONLINE
                st%gt_phase_s=0.0_dp
                st%gt_rotor_est_pct=100.0_dp
                st%gas_dispatch_pct=GAS_MIN_PCT
                st%prev_gas_dispatch_pct=GAS_MIN_PCT
                st%gt_training_bypass=.false.
                call gt_log(st,"SIMULATED GENERATOR SYNCH / ONLINE")
            end if
        end select
        if(st%gt_phase/=GT_ONLINE) then
            st%gas_dispatch_pct=0.0_dp
            st%prev_gas_dispatch_pct=0.0_dp
            st%gas_ramp_pct_per_s=0.0_dp
        end if
    end subroutine gt_trip_advance

    subroutine gt_trip_apply_boundary(st)
        type(GridState),intent(inout) :: st
        real(dp) :: frac
        if(st%gt_phase==GT_ONLINE) return
        st%gas_dispatch_pct=0.0_dp
        st%effective_gas_dispatch_pct=0.0_dp
        st%governor_offset_pct=0.0_dp
        st%governor_delta_MW=0.0_dp
        st%gas_ramp_pct_per_s=0.0_dp
        st%gas_power_MW=0.0_dp
        st%gas_capacity_MW=0.0_dp
        st%steam_power_target_MW=0.0_dp
        st%steam_power_MW=merge(st%gt_steam_decay_MW,0.0_dp,st%combined_cycle)
        st%steam_capacity_MW=0.0_dp
        st%plant_capacity_MW=0.0_dp
        st%reserve_MW=0.0_dp
        st%fuel_flow_kg_s=0.0_dp
        st%heat_input_MW=0.0_dp
        st%gt_thermal_efficiency=0.0_dp
        st%gt_heat_rate_kJ_kWh=0.0_dp
        st%igv_pct=0.0_dp
        st%flow_frac=0.0_dp
        st%PR_op=1.0_dp
        st%surge_margin_pct=0.0_dp
        st%TIT_actual_K=st%gt_exhaust_est_K
        st%exhaust_K=st%gt_exhaust_est_K
        st%hrsg_recovered_heat_MW=0.0_dp
        st%hrsg_steam_flow_kg_s=0.0_dp
        st%hrsg_steam_pressure_bar=0.0_dp
        st%hrsg_pinch_K=0.0_dp
        st%hrsg_approach_K=0.0_dp
        st%hrsg_effectiveness=0.0_dp
        st%ccs_co2_captured_t_h=0.0_dp
        st%ccs_parasitic_MW=0.0_dp
        ! Startup thermochemistry is an *illustrative* fraction of the
        ! pretrip fuel reference; no flame stabilization is solved.
        if(st%gt_phase==GT_IGNITING .or. st%gt_phase==GT_ACCELERATING .or. &
           st%gt_phase==GT_SYNCHRONIZING) then
            frac=0.08_dp
            if(st%gt_phase==GT_ACCELERATING) frac=0.15_dp
            if(st%gt_phase==GT_SYNCHRONIZING) frac=0.20_dp
            st%fuel_flow_kg_s=st%gt_pretrip_fuel_kg_s*frac
            st%heat_input_MW=st%fuel_flow_kg_s*st%h2_lhv_mj_kg
        end if
        ! No generator output before the assumed sync breaker closes.
        st%plant_power_MW=bottoming_power_MW(st)
    end subroutine gt_trip_apply_boundary

    subroutine gt_trip_acknowledge(st)
        type(GridState),intent(inout) :: st
        if(st%gt_phase==GT_ONLINE .or. st%gt_trip_ack) return
        st%gt_trip_ack=.true.
        call gt_log(st,"OPERATOR ACK / TRIP LATCH STILL ACTIVE")
    end subroutine gt_trip_acknowledge

    ! Cached TRAIN source identity is insufficient: the underlying numeric
    ! sample must remain present, finite and fresh through synchronization.
    logical function gt_trip_inputs_missing(st) result(missing)
        type(GridState),intent(in) :: st
        integer :: i
        missing=.false.
        if(st%gt_training_bypass) return
        if(.not.ieee_is_finite(st%elapsed_s)) then
            missing=.true.
            return
        end if
        do i=1,EQ_N
            if(i==EQ_SURGE .or. i==EQ_EXHAUST .or. i==EQ_GENERATOR) cycle
            if(st%eq_source(i)/=EQ_SRC_TRAINING .or. .not.st%eq_training_present(i)) then
                missing=.true.
                return
            end if
            if(.not.ieee_is_finite(st%eq_training_stamp_s(i)) .or. &
               .not.ieee_is_finite(st%eq_training_value(i))) then
                missing=.true.
                return
            end if
            if(st%eq_training_value(i)<0.0_dp .or. &
               st%elapsed_s<st%eq_training_stamp_s(i) .or. &
               st%elapsed_s-st%eq_training_stamp_s(i)>EQ_INPUT_STALE_S) then
                missing=.true.
                return
            end if
        end do
    end function gt_trip_inputs_missing

    integer function gt_trip_permit_mask(st) result(mask)
        type(GridState),intent(in) :: st
        mask=0
        if(st%gt_phase/=GT_LOCKOUT) mask=ibset(mask,0)
        if(.not.st%gt_trip_ack) mask=ibset(mask,1)
        if(any(st%eq_alarm)) mask=ibset(mask,2)
        if(gt_trip_inputs_missing(st)) mask=ibset(mask,3)
        if(st%gt_rotor_est_pct>GT_STOP_RPM_PCT .or. .not.st%gt_turning_gear_on) mask=ibset(mask,4)
        if(st%gt_exhaust_est_K>st%ambient_C+273.15_dp+GT_RESET_HOT_MARGIN_K) mask=ibset(mask,5)
        if(st%fleet_mode) mask=ibset(mask,6)
    end function gt_trip_permit_mask

    integer function gt_trip_restart_mask(st) result(mask)
        type(GridState),intent(in) :: st
        mask=0
        if(st%gt_phase/=GT_READY) mask=ibset(mask,0)
        if(any(st%eq_alarm)) mask=ibset(mask,2)
        if(gt_trip_inputs_missing(st)) mask=ibset(mask,3)
        if(st%fleet_mode) mask=ibset(mask,6)
    end function gt_trip_restart_mask

    pure function gt_trip_reason_for_mask(mask) result(label)
        integer,intent(in) :: mask
        character(len=96) :: label
        if(btest(mask,0)) then
            label="Wait for rundown / correct sequence phase"
        else if(btest(mask,1)) then
            label="Acknowledge first-out before reset"
        else if(btest(mask,2)) then
            label="Standing protective condition - restore model/input"
        else if(btest(mask,3)) then
            label="Required sensor inputs NO DATA - enable TRAINING bypass"
        else if(btest(mask,4)) then
            label="Rotor not at rest / turning gear not established"
        else if(btest(mask,5)) then
            label="Simulated exhaust case too hot for restart"
        else if(btest(mask,6)) then
            label="Single-GT simulation only, fleet mode not qualified"
        else
            label="Teaching-model permissives satisfied"
        end if
    end function gt_trip_reason_for_mask

    subroutine gt_trip_reset_latch(st,accepted)
        type(GridState),intent(inout) :: st
        logical,intent(out) :: accepted
        integer :: mask
        mask=gt_trip_permit_mask(st)
        accepted=(mask==0)
        if(.not.accepted) then
            st%gt_trip_last_denial=gt_trip_reason_for_mask(mask)
            call gt_log(st,"RESET DENIED / "//trim(st%gt_trip_last_denial))
            return
        end if
        st%gt_phase=GT_READY
        st%gt_phase_s=0.0_dp
        st%gt_trip_latched=.false.
        st%gt_trip_last_denial=""
        call gt_log(st,"TRIP LATCH RESET / MACHINE REMAINS OFFLINE")
    end subroutine gt_trip_reset_latch

    subroutine gt_trip_start(st,accepted)
        type(GridState),intent(inout) :: st
        logical,intent(out) :: accepted
        integer :: mask
        mask=gt_trip_restart_mask(st)
        accepted=(mask==0)
        if(.not.accepted) then
            st%gt_trip_last_denial=gt_trip_reason_for_mask(mask)
            call gt_log(st,"RESTART DENIED / "//trim(st%gt_trip_last_denial))
            return
        end if
        st%gt_phase=GT_PURGING
        st%gt_phase_s=0.0_dp
        st%gt_purge_timer_done=.false.
        st%gt_turning_gear_on=.false.
        st%gt_blowoff_open=.true.
        st%gt_fuel_valve_open=.false.
        st%gt_flame_on=.false.
        st%gt_trip_last_denial=""
        call gt_log(st,"SIMULATED START / PURGE TIMER (NO FLOW PROOF)")
    end subroutine gt_trip_start

    subroutine gt_trip_toggle_training_bypass(st)
        type(GridState),intent(inout) :: st
        if(st%gt_phase==GT_ONLINE) return
        st%gt_training_bypass=.not.st%gt_training_bypass
        if(st%gt_training_bypass) then
            call gt_log(st,"TRAINING BYPASS ENABLED / NOT PLANT SAFE")
        else
            call gt_log(st,"TRAINING BYPASS DISABLED")
        end if
    end subroutine gt_trip_toggle_training_bypass

    pure function gt_trip_phase_text(phase) result(label)
        integer,intent(in) :: phase
        character(len=20) :: label
        select case(phase)
        case(GT_ONLINE);label="ONLINE"
        case(GT_TRIPPED);label="TRIP INITIATED"
        case(GT_RUNDOWN);label="RUNDOWN"
        case(GT_LOCKOUT);label="PROTECTION LOCKOUT"
        case(GT_READY);label="RESET / OFFLINE"
        case(GT_PURGING);label="SIM PURGE"
        case(GT_IGNITING);label="SIM IGNITION"
        case(GT_ACCELERATING);label="SIM ACCELERATION"
        case(GT_SYNCHRONIZING);label="SIM SYNCH CHECK"
        case default;label="UNKNOWN"
        end select
    end function gt_trip_phase_text

    pure function gt_trip_cause_text(cause) result(label)
        integer,intent(in) :: cause
        character(len=24) :: label
        select case(cause)
        case(GT_CAUSE_MANUAL);label="MANUAL GT TRIP"
        case(GT_CAUSE_OVERSPEED);label="TRAIN ROTOR OVERSPEED"
        case(GT_CAUSE_COMBUST);label="TRAIN COMBUSTION DYN"
        case(GT_CAUSE_OIL);label="TRAIN LUBE LOW"
        case(GT_CAUSE_START_ABORT);label="SIM START INTERLOCK"
        case default;label="NONE"
        end select
    end function gt_trip_cause_text
end module gt_trip_sequence
