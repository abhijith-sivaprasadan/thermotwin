!> Equipment-specific *condition* alarms for the educational gas-turbine model.
!> No automatic trip, first-out latch, rundown or restart permits belong here;
!> those are independent step-2 work. No OEM certified thresholds are implied.
module equipment_protection
    use precision_kinds, only: dp
    use engine_state, only: GridState, EQ_N, EQ_SURGE, EQ_OVERSPEED, EQ_EXHAUST, &
        EQ_COMBUST, EQ_OIL, EQ_BEARING, EQ_GENERATOR, EQ_SRC_MODEL, &
        EQ_SRC_TRAINING, EQ_SRC_UNAVAILABLE, GT_ONLINE
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    public :: reset_equipment_monitor, tick_equipment_monitor
    public :: set_equipment_training_input, clear_equipment_training_input
    public :: equipment_name, equipment_unit, equipment_priority
    public :: EQ_THRESHOLD_ON, EQ_THRESHOLD_CLEAR, EQ_CONFIRM_S, EQ_RELEASE_S
    public :: EQ_INPUT_STALE_S

    ! Illustrative training thresholds only, NOT unit-specific trip setpoints.
    ! Surge is % positive margin. Overspeed is % rated rotor speed. Exhaust K.
    ! Dynamic combustor pressure is kPa RMS; oil is bar; bearing is deg C.
    ! Generator signal is absolute grid-frequency deviation, not actual
    ! generator differential, voltage or current protection.
    real(dp), parameter :: EQ_THRESHOLD_ON(EQ_N) = &
        [6.0_dp, 110.0_dp, 950.0_dp, 4.0_dp, 1.2_dp, 105.0_dp, 1.0_dp]
    real(dp), parameter :: EQ_THRESHOLD_CLEAR(EQ_N) = &
        [9.0_dp, 106.0_dp, 925.0_dp, 2.0_dp, 1.8_dp, 95.0_dp, 0.5_dp]
    real(dp), parameter :: EQ_CONFIRM_S(EQ_N) = &
        [0.50_dp, 0.25_dp, 2.0_dp, 1.0_dp, 1.0_dp, 2.0_dp, 0.50_dp]
    real(dp), parameter :: EQ_RELEASE_S(EQ_N) = &
        [1.0_dp, 1.0_dp, 2.0_dp, 2.0_dp, 2.0_dp, 3.0_dp, 1.0_dp]
    real(dp), parameter, public :: EQ_INPUT_STALE_S = 5.0_dp

contains

    subroutine reset_equipment_monitor(st)
        type(GridState), intent(inout) :: st
        st%eq_alarm = .false.
        st%eq_source = EQ_SRC_UNAVAILABLE
        st%eq_value = 0.0_dp
        st%eq_breach_s = 0.0_dp
        st%eq_clear_s = 0.0_dp
        st%eq_training_present = .false.
        st%eq_training_value = 0.0_dp
        st%eq_training_stamp_s = -1.0_dp
    end subroutine reset_equipment_monitor

    subroutine set_equipment_training_input(st, id, value, ok)
        type(GridState), intent(inout) :: st
        integer, intent(in) :: id
        real(dp), intent(in) :: value
        logical, intent(out) :: ok
        ok = .false.
        ! Model-derived tags cannot be replaced by a fictional sensor reading.
        if (id /= EQ_OVERSPEED .and. id /= EQ_COMBUST .and. &
            id /= EQ_OIL .and. id /= EQ_BEARING) return
        if (.not.ieee_is_finite(value)) return
        if (value < 0.0_dp) return
        if (.not.ieee_is_finite(st%elapsed_s) .or. st%elapsed_s < 0.0_dp) return
        st%eq_training_value(id) = value
        st%eq_training_stamp_s(id) = st%elapsed_s
        st%eq_training_present(id) = .true.
        ok = .true.
    end subroutine set_equipment_training_input

    subroutine clear_equipment_training_input(st,id)
        type(GridState), intent(inout) :: st
        integer, intent(in) :: id
        if (id < 1 .or. id > EQ_N) return
        st%eq_training_present(id) = .false.
        st%eq_training_stamp_s(id) = -1.0_dp
    end subroutine clear_equipment_training_input

    subroutine tick_equipment_monitor(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        integer :: id, src
        real(dp) :: value
        logical :: rising, restored, valid

        if (.not.ieee_is_finite(dt_s) .or. dt_s < 0.0_dp) return
        do id = 1, EQ_N
            src = EQ_SRC_UNAVAILABLE
            value = 0.0_dp
            valid = .false.
            select case (id)
            case (EQ_SURGE)
                ! Off-design map margin is *modelled*, not measured surge.
                value = st%surge_margin_pct
                valid = ieee_is_finite(value) .and. value >= -50.0_dp .and. value <= 100.0_dp
                valid = valid .and. st%gt_phase==GT_ONLINE
                if (valid) src = EQ_SRC_MODEL
            case (EQ_EXHAUST)
                value = st%exhaust_K
                valid = ieee_is_finite(value) .and. value > 0.0_dp .and. value < 2500.0_dp
                valid = valid .and. st%gt_phase==GT_ONLINE
                if (valid) src = EQ_SRC_MODEL
            case (EQ_GENERATOR)
                ! Electrical grid-frequency *proxy*, not rotor or generator relay.
                value = abs(st%frequency_Hz - st%nominal_frequency_Hz)
                valid = ieee_is_finite(value) .and. ieee_is_finite(st%nominal_frequency_Hz)
                valid = valid .and. st%nominal_frequency_Hz > 0.0_dp
                if (valid) src = EQ_SRC_MODEL
            case default
                if (st%eq_training_present(id) .and. &
                    ieee_is_finite(st%eq_training_value(id)) .and. &
                    ieee_is_finite(st%elapsed_s) .and. &
                    ieee_is_finite(st%eq_training_stamp_s(id))) then
                    value = st%eq_training_value(id)
                    valid = value >= 0.0_dp .and. &
                        st%elapsed_s >= st%eq_training_stamp_s(id) .and. &
                        st%elapsed_s - st%eq_training_stamp_s(id) <= EQ_INPUT_STALE_S
                    if (valid) src = EQ_SRC_TRAINING
                end if
            end select

            if (.not.valid) then
                ! Fail-unknown: missing channels are NOT reported healthy.
                ! GUI must display NO DATA, not NORMAL; never trigger an
                ! imaginary trip, and clear accumulated dwell on data loss.
                st%eq_source(id) = EQ_SRC_UNAVAILABLE
                st%eq_alarm(id) = .false.
                st%eq_breach_s(id) = 0.0_dp
                st%eq_clear_s(id) = 0.0_dp
                cycle
            end if

            st%eq_source(id) = src
            st%eq_value(id) = value
            if (id == EQ_SURGE .or. id == EQ_OIL) then
                rising = value <= EQ_THRESHOLD_ON(id)
                restored = value >= EQ_THRESHOLD_CLEAR(id)
            else
                rising = value >= EQ_THRESHOLD_ON(id)
                restored = value <= EQ_THRESHOLD_CLEAR(id)
            end if

            if (.not.st%eq_alarm(id)) then
                st%eq_clear_s(id) = 0.0_dp
                if (rising) then
                    st%eq_breach_s(id) = st%eq_breach_s(id) + dt_s
                    if (st%eq_breach_s(id) + 1.0e-10_dp >= EQ_CONFIRM_S(id)) then
                        st%eq_alarm(id) = .true.
                        st%eq_breach_s(id) = 0.0_dp
                    end if
                else
                    st%eq_breach_s(id) = 0.0_dp
                end if
            else
                st%eq_breach_s(id) = 0.0_dp
                if (restored) then
                    st%eq_clear_s(id) = st%eq_clear_s(id) + dt_s
                    if (st%eq_clear_s(id) + 1.0e-10_dp >= EQ_RELEASE_S(id)) then
                        st%eq_alarm(id) = .false.
                        st%eq_clear_s(id) = 0.0_dp
                    end if
                else
                    st%eq_clear_s(id) = 0.0_dp
                end if
            end if
        end do
    end subroutine tick_equipment_monitor

    pure function equipment_name(id) result(label)
        integer, intent(in) :: id
        character(len=20) :: label
        select case(id)
        case(EQ_SURGE); label="COMP SURGE MARGIN"
        case(EQ_OVERSPEED); label="ROTOR OVERSPEED"
        case(EQ_EXHAUST); label="GT EXHAUST HIGH"
        case(EQ_COMBUST); label="COMB PRESS OSC"
        case(EQ_OIL); label="LUBE OIL PRESS LOW"
        case(EQ_BEARING); label="BEARING TEMP HIGH"
        case(EQ_GENERATOR); label="GEN GRID FREQ DEV"
        case default; label="UNKNOWN EQUIPMENT"
        end select
    end function equipment_name

    pure function equipment_unit(id) result(unit)
        integer, intent(in) :: id
        character(len=12) :: unit
        select case(id)
        case(EQ_SURGE,EQ_OVERSPEED); unit="%"
        case(EQ_EXHAUST); unit="K"
        case(EQ_COMBUST); unit="kPa RMS"
        case(EQ_OIL); unit="bar"
        case(EQ_BEARING); unit="deg C"
        case(EQ_GENERATOR); unit="Hz delta"
        case default; unit="?"
        end select
    end function equipment_unit

    pure function equipment_priority(id) result(priority)
        integer, intent(in) :: id
        integer :: priority
        select case(id)
        case(EQ_SURGE,EQ_OVERSPEED,EQ_COMBUST,EQ_OIL,EQ_GENERATOR)
            priority=1
        case(EQ_EXHAUST,EQ_BEARING)
            priority=2
        case default
            priority=0
        end select
    end function equipment_priority
end module equipment_protection
