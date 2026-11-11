!> Source-labelled alarm drill-down data and actual sampled traces.
!> No synthetic sensor value may be substituted for an unavailable channel.
module alarm_drilldown
    use precision_kinds, only: dp
    use engine_state
    use equipment_protection, only: equipment_name, equipment_unit, &
        EQ_THRESHOLD_ON, EQ_THRESHOLD_CLEAR
    use off_design, only: SURGE_ALARM_PCT
    use hrsg, only: HRSG_MIN_PINCH_K
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    integer, parameter, public :: DRILL_PLANT_N=8, DRILL_N=DRILL_PLANT_N+EQ_N
    integer, parameter, public :: DRILL_MAP=1, DRILL_TURBINE=2, DRILL_PID=3, &
        DRILL_FACEPLATE=4, DRILL_GRID=5, DRILL_BESS=6
    integer, parameter, public :: DRILL_SRC_NONE=EQ_SRC_UNAVAILABLE, &
        DRILL_SRC_MODEL=EQ_SRC_MODEL, DRILL_SRC_TRAIN=EQ_SRC_TRAINING
    public :: DrillObservation, DrillHistory, drill_observe, drill_record, &
        drill_history_index, drill_annunciator_hit, drill_alarm_row_hit, &
        drill_source_label

    type :: DrillObservation
        real(dp) :: value=0.0_dp, limit=0.0_dp, clear_limit=0.0_dp
        logical :: valid=.false., active=.false., lower_is_bad=.false.
        integer :: source=DRILL_SRC_NONE, diagram=DRILL_FACEPLATE
        character(len=32) :: title="UNKNOWN ALARM"
        character(len=16) :: unit="-"
        character(len=46) :: limit_note=""
        character(len=106) :: advice(3)=""  ! operator diagnostics, NOT safety instructions
    end type DrillObservation

    type :: DrillHistory
        real(dp) :: value(DRILL_N,HISTORY_N)=0.0_dp
        logical :: valid(DRILL_N,HISTORY_N)=.false.
        real(dp) :: time_s(HISTORY_N)=0.0_dp
        integer :: head=0,count=0
    end type DrillHistory

contains
    pure function drill_source_label(source) result(label)
        integer,intent(in) :: source
        character(len=22) :: label
        select case(source)
        case(DRILL_SRC_MODEL);label="MODEL / SIMULATED"
        case(DRILL_SRC_TRAIN);label="TRAINING / INJECTED"
        case default;label="NO DATA"
        end select
    end function drill_source_label

    pure subroutine drill_observe(st,id,o)
        type(GridState),intent(in) :: st
        integer,intent(in) :: id
        type(DrillObservation),intent(out) :: o
        integer :: k
        o=DrillObservation()
        if(id<1 .or. id>DRILL_N) return
        o%source=DRILL_SRC_MODEL
        o%valid=.true.
        select case(id)
        case(1)
            o%title="GRID UNDERFREQUENCY"
            o%value=st%frequency_Hz
            o%limit=st%nominal_frequency_Hz-0.5_dp
            o%unit="Hz"
            o%lower_is_bad=.true.
            o%active=st%alarm_underfreq
            o%diagram=DRILL_GRID
            o%limit_note="MODEL ALARM BELOW f_nom - 0.5 Hz"
            o%advice(1)="Inspect generation minus served demand and the actual ROCOF."
            o%advice(2)="Review UFLS stage, available reserve and delivered BESS power/SOC."
            if(st%gt_phase/=GT_ONLINE) then
                o%advice(3)="GT isolated: do not command fuel or increased GT load."
            else
                o%advice(3)="Adjust only available sources; review response in the trend."
            end if
            o%valid=st%grid_model_valid
        case(2)
            o%title="GRID OVERFREQUENCY"
            o%value=st%frequency_Hz
            o%limit=st%nominal_frequency_Hz+0.5_dp
            o%unit="Hz"
            o%active=st%alarm_overfreq
            o%diagram=DRILL_GRID
            o%limit_note="MODEL ALARM ABOVE f_nom + 0.5 Hz"
            o%advice(1)="Check actual electrical surplus and LFSM-O renewable curtailment."
            o%advice(2)="Examine available GT downward dispatch and BESS charging headroom."
            o%advice(3)="Do not infer generator-relay or grid-code certification."
            o%valid=st%grid_model_valid
        case(3)
            o%title="INSUFFICIENT RESERVE"
            o%value=st%reserve_MW
            o%limit=2.0_dp
            if(st%fleet_mode) o%limit=st%fleet_reserve_requirement_MW
            o%unit="MW"
            o%lower_is_bad=.true.
            o%active=st%alarm_low_reserve
            o%diagram=DRILL_GRID
            o%limit_note="MODEL DISPATCH RESERVE THRESHOLD"
            o%advice(1)="Check committed generator headroom and unmet demand."
            o%advice(2)="Inspect BESS delivered power and SOC before assuming reserves."
            o%advice(3)="Fleet reserve uses the modeled fleet requirement, not 2 MW."
        case(4)
            o%title="LOW BATTERY STATE OF CHARGE"
            o%value=st%battery_soc_pct
            o%limit=15.0_dp
            o%unit="%"
            o%lower_is_bad=.true.
            o%active=st%alarm_low_soc
            o%diagram=DRILL_BESS
            o%limit_note="MODEL SOC ALARM BELOW 15%"
            o%advice(1)="Inspect battery MWh balance and actual inverter output."
            o%advice(2)="Review FCR availability and available charging capacity."
            o%advice(3)="Do not assume the battery can sustain an unmet grid deficit."
        case(5)
            o%title="UNDERFREQUENCY LOAD SHEDDING"
            o%value=real(st%UFLS_stage,dp)
            o%limit=1.0_dp
            o%unit="stage"
            o%active=st%alarm_ufls_active
            o%diagram=DRILL_GRID
            o%limit_note="STAGE 1 AT MODELED f1 SETTING"
            o%advice(1)="Inspect gross demand, shed MW and actual served demand."
            o%advice(2)="Monitor frequency recovery; UFLS stage persists until reset logic."
            o%advice(3)="Stages/thresholds are illustrative, not a utility relay setting."
        case(6)
            o%title="GT DISPATCH AT CEILING"
            o%value=st%effective_gas_dispatch_pct
            o%limit=GAS_MAX_PCT-0.5_dp
            o%unit="% dispatch"
            o%active=st%alarm_turbine_max
            o%diagram=DRILL_TURBINE
            o%limit_note="DISPATCH >= MAX - 0.5%, NOT A TIT TRIP"
            o%advice(1)="Verify requested versus effective GT dispatch and solved gas MW."
            o%advice(2)="Check turbine inlet/exhaust model temperatures and surge margin."
            o%advice(3)="This is a loading advisory, NOT a measured metal-temperature trip."
            o%valid=st%gt_phase==GT_ONLINE .and. .not.st%fleet_mode
        case(7)
            o%title="COMPRESSOR SURGE-MARGIN WARNING"
            o%value=st%surge_margin_pct
            o%limit=SURGE_ALARM_PCT
            o%unit="% margin"
            o%lower_is_bad=.true.
            o%active=st%alarm_surge
            o%diagram=DRILL_MAP
            o%limit_note="MODEL MARGIN BELOW 8% (MAP WARNING)"
            o%advice(1)="Inspect operating point versus compressor-map surge boundary."
            o%advice(2)="Review dispatch ramp, modeled IGV and bleed response."
            o%advice(3)="Do NOT treat model surge margin as OEM anti-surge protection."
            o%valid=st%gt_phase==GT_ONLINE .and. .not.st%fleet_mode
        case(8)
            o%title="HRSG PINCH / FEASIBILITY"
            o%value=st%hrsg_pinch_K
            o%limit=HRSG_MIN_PINCH_K
            o%unit="K"
            o%lower_is_bad=.true.
            o%active=st%alarm_hrsg_pinch
            o%diagram=DRILL_PID
            o%limit_note="MIN PINCH 15 K + HRSG SOLVER FEASIBILITY"
            o%advice(1)="Inspect HRSG recovery, steam flow, gas exhaust and modeled pinch."
            o%advice(2)="A feasibility failure can flag the alarm independently of pinch K."
            o%advice(3)="No instrumented drum/valve permissives are modeled here."
            o%valid=st%combined_cycle .and. st%gt_phase==GT_ONLINE .and. .not.st%fleet_mode
        case default
            k=id-DRILL_PLANT_N
            o%title=equipment_name(k)
            o%unit=equipment_unit(k)
            o%value=st%eq_value(k)
            o%limit=EQ_THRESHOLD_ON(k)
            o%clear_limit=EQ_THRESHOLD_CLEAR(k)
            o%active=st%eq_alarm(k)
            o%source=st%eq_source(k)
            o%valid=(o%source==DRILL_SRC_MODEL .or. o%source==DRILL_SRC_TRAIN)
            if(k==EQ_SURGE .or. k==EQ_OIL) o%lower_is_bad=.true.
            o%limit_note="TRAINING/MODEL ALARM THRESHOLD ONLY"
            select case(k)
            case(EQ_SURGE)
                o%diagram=DRILL_MAP
                o%advice(1)="Examine modeled compressor map, IGV and operating margin."
                o%advice(2)="This is a MAP output, not a measured surge detector."
            case(EQ_OVERSPEED)
                o%diagram=DRILL_TURBINE
                o%advice(1)="TRAINING rotor input only; inspect first-out and GT trip state."
                o%advice(2)="Real rotor-speed feedback/overspeed logic is NOT provided."
            case(EQ_EXHAUST)
                o%diagram=DRILL_TURBINE
                o%advice(1)="Inspect modeled exhaust and turbine-temperature trends."
                o%advice(2)="This is simulated exhaust, not exhaust thermocouple proof."
            case(EQ_COMBUST)
                o%diagram=DRILL_PID
                o%advice(1)="TRAINING combustion-pressure input; inspect first-out log."
                o%advice(2)="No combustor pressure transducer or spectral monitor exists."
            case(EQ_OIL)
                o%diagram=DRILL_FACEPLATE
                o%advice(1)="TRAINING oil-pressure input; inspect trip/auxiliary lube state."
                o%advice(2)="No pump, switch, filter or actual oil header is modeled."
            case(EQ_BEARING)
                o%diagram=DRILL_TURBINE
                o%advice(1)="TRAINING bearing-temperature input; inspect trend and trip log."
                o%advice(2)="No bearing-metal RTD, lubrication or rotor model exists."
            case(EQ_GENERATOR)
                o%diagram=DRILL_GRID
                o%advice(1)="Grid frequency-deviation proxy, not generator differential."
                o%advice(2)="Inspect breaker and grid frequency; no relay feedback exists."
            end select
            o%advice(3)="NO DATA is not NORMAL; use verified field/OEM information."
        end select
        if(.not.ieee_is_finite(o%value) .or. .not.ieee_is_finite(o%limit)) o%valid=.false.
        if(.not.o%valid) then
            o%source=DRILL_SRC_NONE
            o%value=0.0_dp
        end if
    end subroutine drill_observe

    subroutine drill_record(hist,st)
        type(DrillHistory),intent(inout) :: hist
        type(GridState),intent(in) :: st
        type(DrillObservation) :: o
        integer :: id,i
        i=mod(hist%head,HISTORY_N)+1
        hist%time_s(i)=st%elapsed_s
        do id=1,DRILL_N
            call drill_observe(st,id,o)
            hist%value(id,i)=o%value
            hist%valid(id,i)=o%valid
        end do
        hist%head=i
        hist%count=min(hist%count+1,HISTORY_N)
    end subroutine drill_record

    pure integer function drill_history_index(hist,position) result(idx)
        type(DrillHistory),intent(in) :: hist
        integer,intent(in) :: position
        idx=0
        if(position<1 .or. position>hist%count) return
        idx=mod(hist%head-hist%count+position-1+HISTORY_N,HISTORY_N)+1
    end function drill_history_index

    ! Same geometry as draw_annunciator_panel. Tiles open details, not ACK.
    pure integer function drill_annunciator_hit(px,py,x,y,w,h) result(id)
        integer,intent(in) :: px,py,x,y,w,h
        integer :: i,tile_w,tx
        id=0
        if(w<160 .or. h<12) return
        tile_w=(w-9*4)/8
        do i=1,8
            tx=x+4+(i-1)*(tile_w+4)
            if(px>=tx .and. px<=tx+tile_w .and. &
               py>=y+4 .and. py<=y+h-4) then
                id=i
                return
            end if
        end do
    end function drill_annunciator_hit

    pure integer function drill_alarm_row_hit(px,py,x,row_top,table_w,page) result(id)
        integer,intent(in) :: px,py,x,row_top,table_w,page
        integer :: k,alarm_id,yy
        id=0
        if(page<1 .or. page>2) return
        do k=1,8
            alarm_id=8*(page-1)+k
            if(alarm_id>DRILL_N) exit
            yy=row_top+(k-1)*48
            if(px>=x+8 .and. px<=x+table_w-8 .and. &
               py>=yy .and. py<=yy+45) then
                id=alarm_id
                return
            end if
        end do
    end function drill_alarm_row_hit
end module alarm_drilldown
