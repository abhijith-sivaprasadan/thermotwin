!> @file sensor_model.f90
!> @brief Measurement-chain model: corrupts a true value with bias, random
!>        noise and time drift, returning what an instrument would report.
!>
!> measured = true + bias + drift_rate*elapsed_hours + N(0, noise_sigma)
!>
!> This is the bridge between the "perfect simulation" and the reality of test
!> data, and is what lets the uncertainty and diagnostics modules ask: given
!> imperfect instrumentation, how well can performance actually be known?
module sensor_model
    use precision_kinds, only: dp
    use types, only: SensorSpec, CycleResult, InputCase
    use utilities, only: gaussian_random
    implicit none
    private
    public :: apply_sensor, make_sensor
    public :: corrupt_inputs

contains

    !> Convenience constructor.
    pure function make_sensor(channel, bias, noise_sigma, drift_rate) result(s)
        character(len=*), intent(in) :: channel
        real(dp), intent(in) :: bias, noise_sigma, drift_rate
        type(SensorSpec) :: s
        s%channel = channel
        s%bias = bias
        s%noise_sigma = noise_sigma
        s%drift_rate = drift_rate
    end function make_sensor

    !> Apply a sensor's error model to a single true value.
    !> @param[in] elapsed_hours operating time used for drift (0 for snapshot).
    function apply_sensor(true_value, s, elapsed_hours) result(measured)
        real(dp), intent(in) :: true_value
        type(SensorSpec), intent(in) :: s
        real(dp), intent(in) :: elapsed_hours
        real(dp) :: measured
        measured = true_value + s%bias + s%drift_rate * elapsed_hours
        if (s%noise_sigma > 0.0_dp) then
            measured = measured + gaussian_random(0.0_dp, s%noise_sigma)
        end if
    end function apply_sensor

    !> Produce a "measured" copy of the key cycle observables by corrupting the
    !> true CycleResult with a set of channel sensors. Channels recognised:
    !> "T_ambient", "P_ambient", "T_compressor_out", "T_exhaust",
    !> "fuel_flow", "net_power". Unmatched sensors are ignored.
    subroutine corrupt_inputs(truth, sensors, elapsed_hours, &
                              T_amb_m, P_amb_m, T2_m, T4_m, fuel_m, power_m)
        type(CycleResult), intent(in) :: truth
        type(SensorSpec), intent(in)  :: sensors(:)
        real(dp), intent(in) :: elapsed_hours
        real(dp), intent(out) :: T_amb_m, P_amb_m, T2_m, T4_m, fuel_m, power_m
        integer :: i

        ! Start from truth (no error).
        T_amb_m = truth%T1_K
        P_amb_m = truth%P1_Pa
        T2_m    = truth%T2_K
        T4_m    = truth%T4_K
        fuel_m  = truth%fuel_flow_kg_s
        power_m = truth%net_power_MW

        do i = 1, size(sensors)
            select case (trim(sensors(i)%channel))
            case ("T_ambient")
                T_amb_m = apply_sensor(truth%T1_K, sensors(i), elapsed_hours)
            case ("P_ambient")
                P_amb_m = apply_sensor(truth%P1_Pa, sensors(i), elapsed_hours)
            case ("T_compressor_out")
                T2_m = apply_sensor(truth%T2_K, sensors(i), elapsed_hours)
            case ("T_exhaust")
                T4_m = apply_sensor(truth%T4_K, sensors(i), elapsed_hours)
            case ("fuel_flow")
                fuel_m = apply_sensor(truth%fuel_flow_kg_s, sensors(i), elapsed_hours)
            case ("net_power")
                power_m = apply_sensor(truth%net_power_MW, sensors(i), elapsed_hours)
            end select
        end do
    end subroutine corrupt_inputs

end module sensor_model
