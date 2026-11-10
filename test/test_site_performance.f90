!> @file test_site_performance.f90
!> @brief Reference-to-site correction identity, fixed calibration and rejection.
program test_site_performance
    use precision_kinds, only: dp
    use types, only: InputCase
    use fluid_properties, only: set_property_model, PROP_VARIABLE
    use site_performance, only: SiteCorrection, evaluate_site
    implicit none
    type(InputCase) :: hardware, site
    type(SiteCorrection) :: ref, actual, candidate
    integer :: failures, i
    real(dp) :: temperatures(5), pressures(5)
    failures = 0
    call set_property_model(PROP_VARIABLE)

    hardware%case_name = "ISO_fixed_hardware"
    hardware%inlet_pressure_loss = 0.0_dp
    hardware%exhaust_pressure_loss = 0.0_dp
    site = hardware
    ref = evaluate_site(hardware, site)
    call expect_true("ISO baseline valid", ref%valid, failures)
    if (.not. ref%valid) then
        print *, trim(ref%status)
        error stop 1
    end if
    call expect_near("ISO compressor intake flange pressure = 101325 Pa", &
         ref%reference%cyc%P1_Pa, 101325.0_dp, 1.0e-3_dp, failures)
    call expect_near("ISO turbine exhaust flange pressure = 101325 Pa", &
         ref%reference%cyc%P4_Pa, 101325.0_dp, 1.0e-3_dp, failures)
    call expect_near("ISO intake flange temperature = 288.15 K", &
         ref%reference%cyc%T1_K, 288.15_dp, 1.0e-6_dp, failures)
    call expect_near("ISO reference/site net power equality", &
         ref%reference%cyc%net_power_MW, ref%installed%cyc%net_power_MW, 1.0e-9_dp, failures)
    call expect_near("ISO power multiplier unity", ref%power_correction_ref_per_site, 1.0_dp, 1.0e-10_dp, failures)
    call expect_near("ISO heat-rate multiplier unity", ref%heat_rate_correction_ref_per_site, &
                     1.0_dp, 1.0e-10_dp, failures)
    call expect_near("ISO flow multiplier unity", ref%exhaust_flow_correction_ref_per_site, 1.0_dp, 1.0e-10_dp, failures)
    call expect_near("ISO exhaust temperature offset zero", &
                     ref%exhaust_T_additive_ref_minus_site_K, 0.0_dp, 1.0e-9_dp, failures)

    site = hardware
    site%ambient_T_K = 308.15_dp
    actual = evaluate_site(hardware, site)
    call expect_true("hot site valid", actual%valid, failures)
    call expect_true("hot-day net output falls", actual%power_derate_ratio < 1.0_dp, failures)
    call expect_true("hot day correction multiplier exceeds unity", &
         actual%power_correction_ref_per_site > 1.0_dp, failures)
    call expect_near("hot test corrected to ISO equals model reference", &
         actual%installed%cyc%net_power_MW*actual%power_correction_ref_per_site, &
         actual%reference%cyc%net_power_MW, 1.0e-8_dp, failures)

    site = hardware
    site%ambient_P_Pa = 85000.0_dp
    actual = evaluate_site(hardware, site)
    call expect_true("low pressure site valid", actual%valid, failures)
    call expect_true("low site pressure reduces capacity", actual%power_derate_ratio < 1.0_dp, failures)

    site = hardware
    site%inlet_pressure_loss = 0.045_dp
    actual = evaluate_site(hardware, site)
    call expect_true("higher inlet loss case valid", actual%valid, failures)
    call expect_true("greater inlet loss derates power", actual%power_derate_ratio < 1.0_dp, failures)
    call expect_near("site inlet-loss changes do not alter reference engine", &
         actual%reference%cyc%net_power_MW, ref%reference%cyc%net_power_MW, 1.0e-9_dp, failures)

    site = hardware
    site%exhaust_pressure_loss = 0.06_dp
    actual = evaluate_site(hardware, site)
    call expect_true("higher exhaust backpressure case valid", actual%valid, failures)
    call expect_true("higher exhaust loss derates power", actual%power_derate_ratio < 1.0_dp, failures)
    call expect_near("exhaust loss does not recalibrate turbine", &
         actual%reference%cyc%net_power_MW, ref%reference%cyc%net_power_MW, 1.0e-9_dp, failures)

    site = hardware
    site%ambient_T_K = 308.15_dp
    site%ambient_P_Pa = 85000.0_dp
    site%inlet_pressure_loss = 0.035_dp
    site%exhaust_pressure_loss = 0.055_dp
    actual = evaluate_site(hardware, site)
    call expect_true("multi-factor hot low-pressure high-loss case valid", actual%valid, failures)
    call expect_true("multi-factor case derates", actual%power_derate_ratio < 1.0_dp, failures)

    temperatures = [258.15_dp, 273.15_dp, 288.15_dp, 303.15_dp, 318.15_dp]
    pressures = [80000.0_dp, 85000.0_dp, 90000.0_dp, 100000.0_dp, 105000.0_dp]
    do i = 1, 5
        site = hardware
        site%ambient_T_K = temperatures(i)
        candidate = evaluate_site(hardware, site)
        call expect_true("temperature sweep site valid", candidate%valid, failures)
        site = hardware
        site%ambient_P_Pa = pressures(i)
        candidate = evaluate_site(hardware, site)
        call expect_true("pressure sweep site valid", candidate%valid, failures)
    end do

    block
        type(InputCase) :: invalid_ref
        invalid_ref = hardware
        invalid_ref%inlet_pressure_loss = 0.01_dp
        candidate = evaluate_site(invalid_ref, invalid_ref)
        call expect_true("upstream atmospheric reference is not ISO flange", &
             .not. candidate%valid, failures)
        invalid_ref = hardware
        invalid_ref%exhaust_pressure_loss = 0.02_dp
        candidate = evaluate_site(invalid_ref, invalid_ref)
        call expect_true("nonzero ISO exhaust backpressure rejected", &
             .not. candidate%valid, failures)
    end block

    site = hardware
    site%relative_humidity = 0.90_dp
    candidate = evaluate_site(hardware, site)
    call expect_true("unsupported humidity change rejected", .not. candidate%valid, failures)
    site = hardware
    site%eta_compressor = 0.70_dp
    candidate = evaluate_site(hardware, site)
    call expect_true("hardware change rejected", .not. candidate%valid, failures)
    site = hardware
    site%ambient_P_Pa = 60000.0_dp
    candidate = evaluate_site(hardware, site)
    call expect_true("out-of-domain ambient pressure rejected", .not. candidate%valid, failures)
    site = hardware
    site%degradation_mode = "mild"
    candidate = evaluate_site(hardware, site)
    call expect_true("unmodelled degraded machine rejected", .not. candidate%valid, failures)
    site = hardware
    site%LHV_J_kg = 40.0e6_dp
    candidate = evaluate_site(hardware, site)
    call expect_true("scalar LHV scenario accepted", candidate%valid, failures)

    call finish("site_performance", failures)
contains
    include "test_assert.inc"
end program test_site_performance
