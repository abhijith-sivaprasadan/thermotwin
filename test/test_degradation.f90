!> @file test_degradation.f90
!> @brief Tests that degradation presets behave monotonically and physically.
program test_degradation
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult, DegradationSet
    use cycle_solver, only: solve_cycle
    use degradation, only: make_preset, apply_degradation
    use fluid_properties, only: set_property_model, PROP_CONSTANT
    implicit none
    type(InputCase) :: base
    type(CycleResult) :: clean, mild, severe, washed
    integer :: failures
    failures = 0

    call set_property_model(PROP_CONSTANT)

    clean  = solve_cycle(apply_degradation(base, make_preset("clean")))
    mild   = solve_cycle(apply_degradation(base, make_preset("mild")))
    severe = solve_cycle(apply_degradation(base, make_preset("severe")))
    washed = solve_cycle(apply_degradation(base, make_preset("washed")))

    ! Power must fall monotonically clean -> mild -> severe.
    call expect_true("power: clean > mild",   clean%net_power_MW > mild%net_power_MW,  failures)
    call expect_true("power: mild  > severe",  mild%net_power_MW  > severe%net_power_MW, failures)

    ! Efficiency must fall with degradation.
    call expect_true("eff: clean > mild",   clean%thermal_efficiency > mild%thermal_efficiency, failures)
    call expect_true("eff: mild  > severe",  mild%thermal_efficiency  > severe%thermal_efficiency, failures)

    ! Heat rate must rise (worsen) with degradation.
    call expect_true("HR: severe > clean", severe%heat_rate_kJ_kWh > clean%heat_rate_kJ_kWh, failures)

    ! Washing recovers some performance vs severe (compressor restored) but does
    ! not fully recover because turbine erosion persists.
    call expect_true("washed power > severe power", washed%net_power_MW > severe%net_power_MW, failures)
    call expect_true("washed power < clean power",  washed%net_power_MW < clean%net_power_MW,  failures)

    ! Degraded machines run a hotter exhaust (classic monitoring signature).
    call expect_true("severe exhaust hotter than clean", &
                     severe%exhaust_temperature_K > clean%exhaust_temperature_K, failures)

    call finish("test_degradation", failures)
contains
    include "test_assert.inc"
end program test_degradation
