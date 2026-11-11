! Equipment condition-monitor acceptance tests: model versus training quality,
! persistence, hysteresis, staleness, invalid data and independent instances.
program test_equipment_protection
    use precision_kinds, only: dp
    use engine_state
    use equipment_protection
    use, intrinsic :: ieee_arithmetic, only: ieee_value, ieee_quiet_nan
    implicit none
    type(GridState) :: st, another
    integer :: failures
    logical :: ok
    real(dp), parameter :: dt=0.25_dp
    integer :: i

    failures=0
    call reset_equipment_monitor(st)
    st%surge_margin_pct=20.0_dp
    st%exhaust_K=800.0_dp
    st%frequency_Hz=50.0_dp
    call tick_equipment_monitor(st,dt)
    call expect_true("model channels present",all(st%eq_source([EQ_SURGE,EQ_EXHAUST,EQ_GENERATOR])==EQ_SRC_MODEL))
    call expect_true("other four initially not modelled", &
        all(st%eq_source([EQ_OVERSPEED,EQ_COMBUST,EQ_OIL,EQ_BEARING])==EQ_SRC_UNAVAILABLE))
    call expect_true("unmonitored are not alarms nor claimed healthy", &
        .not.any(st%eq_alarm) .and. .not.any(st%eq_training_present))
    call expect_true("generated labels explicit",trim(equipment_name(EQ_GENERATOR))=="GEN GRID FREQ DEV")

    ! Minimum 0.5 s positive dwell for compressor-surge map margin.
    st%surge_margin_pct=5.9_dp
    call tick_equipment_monitor(st,dt)
    call expect_true("surge not active before debounce",.not.st%eq_alarm(EQ_SURGE))
    call tick_equipment_monitor(st,dt)
    call expect_true("surge active after dwell",st%eq_alarm(EQ_SURGE))
    st%surge_margin_pct=7.0_dp
    do i=1,8
        call tick_equipment_monitor(st,dt)
    end do
    call expect_true("surge hysteresis preserves standing state",st%eq_alarm(EQ_SURGE))
    st%surge_margin_pct=10.0_dp
    do i=1,3
        call tick_equipment_monitor(st,dt)
    end do
    call expect_true("surge still active during clear dwell",st%eq_alarm(EQ_SURGE))
    call tick_equipment_monitor(st,dt)
    call expect_true("surge recovers after clear dwell",.not.st%eq_alarm(EQ_SURGE))

    ! Exhaust high-temperature response is model-derived but is NOT a trip.
    st%exhaust_K=951.0_dp
    do i=1,7
        call tick_equipment_monitor(st,dt)
    end do
    call expect_true("exhaust has two seconds confirm dwell",.not.st%eq_alarm(EQ_EXHAUST))
    call tick_equipment_monitor(st,dt)
    call expect_true("exhaust over-limit condition asserted",st%eq_alarm(EQ_EXHAUST))

    ! Generator alarm is explicitly frequency-deviation proxy, NOT electrical relay.
    st%nominal_frequency_Hz=60.0_dp
    st%frequency_Hz=58.8_dp
    call tick_equipment_monitor(st,dt)
    call expect_true("60 Hz one-tick debounce",.not.st%eq_alarm(EQ_GENERATOR))
    call tick_equipment_monitor(st,dt)
    call expect_true("60 Hz grid frequency proxy alarm",st%eq_alarm(EQ_GENERATOR))

    ! Every unavailable training channel accepts only authorized synthetic signals.
    call set_equipment_training_input(st, EQ_SURGE, 2.0_dp, ok)
    call expect_true("cannot override model signal with synthetic source",.not.ok)
    call set_equipment_training_input(st, EQ_OVERSPEED, 112.0_dp, ok)
    call expect_true("training overspeed input is accepted with explicit provenance",ok)
    call tick_equipment_monitor(st,dt)
    call expect_true("overspeed synthetic channel quality tagged", &
        st%eq_source(EQ_OVERSPEED)==EQ_SRC_TRAINING .and. st%eq_alarm(EQ_OVERSPEED))
    call set_equipment_training_input(st, EQ_COMBUST, 5.0_dp, ok)
    call set_equipment_training_input(st, EQ_OIL, 0.8_dp, ok)
    call set_equipment_training_input(st, EQ_BEARING, 110.0_dp, ok)
    do i=1,8
        call tick_equipment_monitor(st,dt)
    end do
    call expect_true("combustor dynamics injected signal asserted",st%eq_alarm(EQ_COMBUST))
    call expect_true("lube-oil injected sensor asserted",st%eq_alarm(EQ_OIL))
    call expect_true("bearing training signal asserted",st%eq_alarm(EQ_BEARING))
    call expect_true("model output is unaffected by monitor",st%surge_margin_pct==10.0_dp)

    st%elapsed_s=EQ_INPUT_STALE_S+0.01_dp
    call tick_equipment_monitor(st,dt)
    call expect_true("stale training values fail unknown not healthy", &
        all(st%eq_source([EQ_OVERSPEED,EQ_COMBUST,EQ_OIL,EQ_BEARING])==EQ_SRC_UNAVAILABLE))
    call expect_true("no stale training signal stays alarm-active", &
        .not.any(st%eq_alarm([EQ_OVERSPEED,EQ_COMBUST,EQ_OIL,EQ_BEARING])))
    call set_equipment_training_input(st, EQ_OIL, ieee_value(1.0_dp,ieee_quiet_nan),ok)
    call expect_true("NaN training measurements rejected",.not.ok)
    st%exhaust_K=ieee_value(1.0_dp,ieee_quiet_nan)
    call tick_equipment_monitor(st,dt)
    call expect_true("invalid source physics output explicitly no data", &
        st%eq_source(EQ_EXHAUST)==EQ_SRC_UNAVAILABLE)

    call reset_equipment_monitor(another)
    another%surge_margin_pct=5.0_dp
    call tick_equipment_monitor(another,dt)
    call expect_true("independent instances do not share dwell state", &
        .not.another%eq_alarm(EQ_SURGE) .and. .not.st%eq_alarm(EQ_SURGE))

    call reset_equipment_monitor(st)
    call expect_true("reset clears all signal provenance and events", &
        all(st%eq_source==EQ_SRC_UNAVAILABLE) .and. .not.any(st%eq_training_present) .and. &
        .not.any(st%eq_alarm))
    if (failures>0) then
        write(*,'(A,I0)') "FAIL equipment protection: ",failures
        stop 1
    end if
    print '(A)',"PASS equipment alarms / physics provenance / hysteresis / stale inputs"
contains
    subroutine expect_true(name,condition)
        character(len=*),intent(in) :: name
        logical,intent(in) :: condition
        if (.not.condition) then
            failures=failures+1
            print '(A,A)',"FAIL: ",name
        end if
    end subroutine
end program test_equipment_protection
