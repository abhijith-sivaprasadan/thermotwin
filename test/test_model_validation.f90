!> @file test_model_validation.f90
!> @brief Regression tests for the Revamp 5.0 C1 model-validation harness.
program test_model_validation
    use precision_kinds, only: dp
    use dnn_surrogate, only: dnn_init, DNN_ACTIVE
    use model_validation, only: ModelValidationResult, MODEL_VAL_N, &
        run_model_validation, validation_dispatch_reference_hr, &
        validation_cycle_reference_hr, validation_reference_power
    implicit none

    type(ModelValidationResult) :: mv
    integer :: failures
    failures = 0

    call dnn_init("dnn_weights.txt")
    call run_model_validation(mv)

    call expect_true("validation harness reports ready", mv%ready, failures)
    call expect_true("validation point count matches constant", mv%n == MODEL_VAL_N, failures)
    call expect_true("cycle power MAE is finite and bounded", &
        mv%cycle_power_mae_MW >= 0.0_dp .and. mv%cycle_power_mae_MW < 12.0_dp, failures)
    call expect_true("cycle power bias is finite and bounded", &
        abs(mv%cycle_power_bias_MW) < 12.0_dp, failures)
    call expect_true("cycle heat-rate MAE is finite and bounded", &
        mv%cycle_hr_mae_kJ_kWh >= 0.0_dp .and. mv%cycle_hr_mae_kJ_kWh < 3500.0_dp, failures)
    call expect_true("cycle heat-rate bias is finite and bounded", &
        abs(mv%cycle_hr_bias_kJ_kWh) < 3500.0_dp, failures)

    if (DNN_ACTIVE) then
        call expect_true("DNN availability follows loaded weights", mv%dnn_available, failures)
        call expect_true("DNN heat-rate MAE is bounded", &
            mv%dnn_hr_mae_kJ_kWh >= 0.0_dp .and. mv%dnn_hr_mae_kJ_kWh < 700.0_dp, failures)
        call expect_true("DNN heat-rate bias is bounded", &
            abs(mv%dnn_hr_bias_kJ_kWh) < 700.0_dp, failures)
        call expect_true("DNN worst point index is valid", &
            mv%worst_idx >= 1 .and. mv%worst_idx <= MODEL_VAL_N, failures)
        call expect_true("DNN max absolute error is bounded", &
            mv%dnn_hr_max_abs_kJ_kWh >= mv%dnn_hr_mae_kJ_kWh .and. &
            mv%dnn_hr_max_abs_kJ_kWh < 1200.0_dp, failures)
    else
        call expect_true("DNN unavailable when weights are absent", .not. mv%dnn_available, failures)
        call expect_near("DNN MAE remains zero without weights", &
            mv%dnn_hr_mae_kJ_kWh, 0.0_dp, 1.0e-12_dp, failures)
    end if

    call expect_near("dispatch reference matches train_dnn full-load baseline", &
        validation_dispatch_reference_hr(1.0_dp, 15.0_dp, 1400.0_dp, 0.0_dp), &
        9200.0_dp, 1.0e-9_dp, failures)
    call expect_true("hot ambient raises dispatch heat rate", &
        validation_dispatch_reference_hr(0.7_dp, 40.0_dp, 1400.0_dp, 0.0_dp) > &
        validation_dispatch_reference_hr(0.7_dp, 15.0_dp, 1400.0_dp, 0.0_dp), failures)
    call expect_true("fouling raises dispatch heat rate", &
        validation_dispatch_reference_hr(0.7_dp, 15.0_dp, 1400.0_dp, 8.0_dp) > &
        validation_dispatch_reference_hr(0.7_dp, 15.0_dp, 1400.0_dp, 0.0_dp), failures)
    call expect_true("cycle reference is above dispatch label at design", &
        validation_cycle_reference_hr(1.0_dp, 15.0_dp, 1400.0_dp, 0.0_dp) > &
        validation_dispatch_reference_hr(1.0_dp, 15.0_dp, 1400.0_dp, 0.0_dp), failures)
    call expect_near("reference power full-load design anchor", &
        validation_reference_power(1.0_dp, 15.0_dp, 1400.0_dp, 0.0_dp), &
        30.4_dp, 1.0e-9_dp, failures)

    call finish("test_model_validation", failures)
contains
    include "test_assert.inc"
end program test_model_validation
