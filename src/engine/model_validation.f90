!> @file model_validation.f90
!> @brief Compact deterministic validation harness for Revamp 5.0 C1.
!>
!> The harness keeps the EXE self-contained: it evaluates a small fixed set of
!> operating points and reports MAE/bias for the thermodynamic cycle solver and
!> the DNN heat-rate surrogate.  The DNN target is the same dispatch-map label
!> model used by train_dnn.py; the cycle target is a calibrated GT reference map
!> near the verified 30 MW design point.
module model_validation
    use precision_kinds, only: dp
    use constants, only: KELVIN_OFFSET
    use types, only: InputCase, CycleResult
    use cycle_solver, only: solve_cycle
    use dnn_surrogate, only: DNN_ACTIVE, dnn_heat_rate
    implicit none
    private

    integer, parameter, public :: MODEL_VAL_N = 8

    type, public :: ModelValidationResult
        logical  :: ready = .false.
        logical  :: dnn_available = .false.
        integer  :: n = 0
        integer  :: worst_idx = 0
        real(dp) :: cycle_power_mae_MW = 0.0_dp
        real(dp) :: cycle_power_bias_MW = 0.0_dp
        real(dp) :: cycle_hr_mae_kJ_kWh = 0.0_dp
        real(dp) :: cycle_hr_bias_kJ_kWh = 0.0_dp
        real(dp) :: dnn_hr_mae_kJ_kWh = 0.0_dp
        real(dp) :: dnn_hr_bias_kJ_kWh = 0.0_dp
        real(dp) :: dnn_hr_max_abs_kJ_kWh = 0.0_dp
    end type ModelValidationResult

    public :: run_model_validation
    public :: validation_dispatch_reference_hr, validation_cycle_reference_hr
    public :: validation_reference_power

    real(dp), parameter :: VAL_LOAD(MODEL_VAL_N) = &
        [0.35_dp, 0.45_dp, 0.55_dp, 0.65_dp, 0.75_dp, 0.85_dp, 0.95_dp, 1.00_dp]
    real(dp), parameter :: VAL_TAMB_C(MODEL_VAL_N) = &
        [-10.0_dp, 0.0_dp, 10.0_dp, 15.0_dp, 25.0_dp, 35.0_dp, 40.0_dp, 15.0_dp]
    real(dp), parameter :: VAL_TIT_K(MODEL_VAL_N) = &
        [1320.0_dp, 1360.0_dp, 1400.0_dp, 1440.0_dp, 1480.0_dp, 1500.0_dp, 1540.0_dp, 1400.0_dp]
    real(dp), parameter :: VAL_FOUL_PCT(MODEL_VAL_N) = &
        [0.0_dp, 1.0_dp, 2.0_dp, 4.0_dp, 5.0_dp, 8.0_dp, 10.0_dp, 0.0_dp]

contains

    subroutine run_model_validation(res)
        type(ModelValidationResult), intent(out) :: res
        type(InputCase) :: ic
        type(CycleResult) :: cy
        integer :: i
        real(dp) :: ref_power, ref_cycle_hr, ref_dnn_hr
        real(dp) :: e_power, e_cycle_hr, e_dnn_hr, max_abs
        real(dp) :: dnn_hr

        res = ModelValidationResult()
        res%n = MODEL_VAL_N
        res%dnn_available = DNN_ACTIVE
        max_abs = -1.0_dp

        do i = 1, MODEL_VAL_N
            ic = make_validation_case(i)
            cy = solve_cycle(ic)

            ref_power = validation_reference_power(VAL_LOAD(i), VAL_TAMB_C(i), &
                VAL_TIT_K(i), VAL_FOUL_PCT(i))
            ref_cycle_hr = validation_cycle_reference_hr(VAL_LOAD(i), VAL_TAMB_C(i), &
                VAL_TIT_K(i), VAL_FOUL_PCT(i))
            ref_dnn_hr = validation_dispatch_reference_hr(VAL_LOAD(i), VAL_TAMB_C(i), &
                VAL_TIT_K(i), VAL_FOUL_PCT(i))

            e_power = cy%net_power_MW - ref_power
            e_cycle_hr = cy%heat_rate_kJ_kWh - ref_cycle_hr
            res%cycle_power_bias_MW = res%cycle_power_bias_MW + e_power
            res%cycle_power_mae_MW = res%cycle_power_mae_MW + abs(e_power)
            res%cycle_hr_bias_kJ_kWh = res%cycle_hr_bias_kJ_kWh + e_cycle_hr
            res%cycle_hr_mae_kJ_kWh = res%cycle_hr_mae_kJ_kWh + abs(e_cycle_hr)

            if (DNN_ACTIVE) then
                dnn_hr = dnn_heat_rate(VAL_LOAD(i), VAL_TAMB_C(i), VAL_TIT_K(i), VAL_FOUL_PCT(i))
                e_dnn_hr = dnn_hr - ref_dnn_hr
                res%dnn_hr_bias_kJ_kWh = res%dnn_hr_bias_kJ_kWh + e_dnn_hr
                res%dnn_hr_mae_kJ_kWh = res%dnn_hr_mae_kJ_kWh + abs(e_dnn_hr)
                if (abs(e_dnn_hr) > max_abs) then
                    max_abs = abs(e_dnn_hr)
                    res%worst_idx = i
                end if
            end if
        end do

        res%cycle_power_bias_MW = res%cycle_power_bias_MW / real(MODEL_VAL_N, dp)
        res%cycle_power_mae_MW = res%cycle_power_mae_MW / real(MODEL_VAL_N, dp)
        res%cycle_hr_bias_kJ_kWh = res%cycle_hr_bias_kJ_kWh / real(MODEL_VAL_N, dp)
        res%cycle_hr_mae_kJ_kWh = res%cycle_hr_mae_kJ_kWh / real(MODEL_VAL_N, dp)
        if (DNN_ACTIVE) then
            res%dnn_hr_bias_kJ_kWh = res%dnn_hr_bias_kJ_kWh / real(MODEL_VAL_N, dp)
            res%dnn_hr_mae_kJ_kWh = res%dnn_hr_mae_kJ_kWh / real(MODEL_VAL_N, dp)
            res%dnn_hr_max_abs_kJ_kWh = max_abs
        end if
        res%ready = .true.
    end subroutine run_model_validation

    function make_validation_case(i) result(ic)
        integer, intent(in) :: i
        type(InputCase) :: ic
        real(dp) :: fouling

        fouling = VAL_FOUL_PCT(i)
        write(ic%case_name, '("rev5_val_",I0)') i
        ic%ambient_T_K = VAL_TAMB_C(i) + KELVIN_OFFSET
        ic%T_turbine_inlet_K = VAL_TIT_K(i)
        ic%mdot_air_kg_s = 100.0_dp * VAL_LOAD(i)
        ic%eta_compressor = max(0.78_dp, 0.86_dp - 0.0018_dp * fouling)
        ic%eta_turbine = max(0.82_dp, 0.89_dp - 0.0012_dp * fouling)
        ic%inlet_pressure_loss = 0.010_dp + 0.0003_dp * fouling
        ic%combustor_pressure_loss = 0.030_dp + 0.0002_dp * fouling
    end function make_validation_case

    pure function validation_dispatch_reference_hr(load_frac, tamb_c, tit_k, fouling_pct) result(hr)
        real(dp), intent(in) :: load_frac, tamb_c, tit_k, fouling_pct
        real(dp) :: hr

        ! Same label model used by train_dnn.py for the dispatch surrogate.
        hr = 9200.0_dp + 4600.0_dp * (1.0_dp - load_frac)**2
        hr = hr * (1.0_dp + 0.003_dp * (tamb_c - 15.0_dp))
        hr = hr * (1.0_dp - 0.0008_dp * (tit_k - 1400.0_dp))
        hr = hr + fouling_pct * 0.009_dp * 9200.0_dp
    end function validation_dispatch_reference_hr

    pure function validation_cycle_reference_hr(load_frac, tamb_c, tit_k, fouling_pct) result(hr)
        real(dp), intent(in) :: load_frac, tamb_c, tit_k, fouling_pct
        real(dp) :: hr

        ! Calibrated GT performance-map reference near the verified design point.
        hr = 11550.0_dp + 2750.0_dp * (1.0_dp - load_frac)**2
        hr = hr * (1.0_dp + 0.0022_dp * (tamb_c - 15.0_dp))
        hr = hr * (1.0_dp - 0.00045_dp * (tit_k - 1400.0_dp))
        hr = hr + fouling_pct * 0.0065_dp * 11550.0_dp
    end function validation_cycle_reference_hr

    pure function validation_reference_power(load_frac, tamb_c, tit_k, fouling_pct) result(power_MW)
        real(dp), intent(in) :: load_frac, tamb_c, tit_k, fouling_pct
        real(dp) :: power_MW, derate

        derate = 1.0_dp - 0.0035_dp * max(0.0_dp, tamb_c - 15.0_dp) + &
                 0.0015_dp * max(0.0_dp, 15.0_dp - tamb_c)
        derate = derate * (1.0_dp + 0.00035_dp * (tit_k - 1400.0_dp))
        derate = derate * (1.0_dp - 0.0025_dp * fouling_pct)
        power_MW = 30.4_dp * load_frac * max(0.70_dp, min(1.18_dp, derate))
    end function validation_reference_power

end module model_validation
