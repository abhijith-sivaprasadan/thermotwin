!> @file test_off_design.f90
!> @brief Tests the off-design solver: design-point recovery, load tracking,
!>        IGV-first control strategy, part-load heat-rate shape, surge margin
!>        behaviour, ambient derate, and the minimum-load floor.
program test_off_design
    use precision_kinds, only: dp
    use types, only: InputCase
    use fluid_properties, only: set_property_model, PROP_VARIABLE
    use off_design, only: OffDesignPoint, solve_off_design, IGV_MIN_FLOW_FRAC, TIT_MIN_K
    implicit none
    integer :: failures
    type(InputCase) :: base
    failures = 0

    ! The live engine runs with temperature-dependent properties; test there.
    call set_property_model(PROP_VARIABLE)
    base%case_name = "off_design_test"

    ! --- Design point: full load recovers the design operating point. ---
    block
        type(OffDesignPoint) :: od
        call solve_off_design(base, 1.0_dp, 0.0_dp, od)
        call expect_near("full load: design PR", od%PR_op, base%pressure_ratio, 0.10_dp, failures)
        call expect_near("full load: IGVs fully open", od%flow_frac, 1.0_dp, 1.0e-9_dp, failures)
        call expect_near("full load: firing at setpoint", od%TIT_K, base%T_turbine_inlet_K, 1.0e-9_dp, failures)
        call expect_near("full load: design surge margin 20%", od%surge_margin_pct, 20.0_dp, 1.0_dp, failures)
        call expect_true("full load: ~30 MW class machine", &
            od%cyc%net_power_MW > 28.0_dp .and. od%cyc%net_power_MW < 32.0_dp, failures)
    end block

    ! --- Load tracking: requested fraction of capacity is delivered. ---
    block
        type(OffDesignPoint) :: od_cap, od
        call solve_off_design(base, 1.0_dp, 0.0_dp, od_cap)
        call solve_off_design(base, 0.70_dp, 0.0_dp, od)
        call expect_near("70% load delivered", od%cyc%net_power_MW, &
            0.70_dp * od_cap%cyc%net_power_MW, 0.10_dp, failures)
        call solve_off_design(base, 0.40_dp, 0.0_dp, od)
        call expect_near("40% load delivered", od%cyc%net_power_MW, &
            0.40_dp * od_cap%cyc%net_power_MW, 0.10_dp, failures)
    end block

    ! --- Control strategy: IGVs first (TIT held), firing temperature second. ---
    block
        type(OffDesignPoint) :: od
        call solve_off_design(base, 0.80_dp, 0.0_dp, od)
        call expect_near("80% load: TIT still at setpoint", od%TIT_K, &
            base%T_turbine_inlet_K, 1.0e-6_dp, failures)
        call expect_true("80% load: IGVs partly closed", od%flow_frac < 0.999_dp, failures)
        call solve_off_design(base, 0.35_dp, 0.0_dp, od)
        call expect_near("35% load: IGVs at minimum flow", od%flow_frac, &
            IGV_MIN_FLOW_FRAC, 1.0e-9_dp, failures)
        call expect_true("35% load: firing temperature reduced", &
            od%TIT_K < base%T_turbine_inlet_K - 50.0_dp, failures)
    end block

    ! --- Part-load heat rate: rises monotonically, sharply below 60%. ---
    block
        type(OffDesignPoint) :: od100, od70, od40
        call solve_off_design(base, 1.00_dp, 0.0_dp, od100)
        call solve_off_design(base, 0.70_dp, 0.0_dp, od70)
        call solve_off_design(base, 0.40_dp, 0.0_dp, od40)
        call expect_true("HR(70%) > HR(100%)", &
            od70%cyc%heat_rate_kJ_kWh > od100%cyc%heat_rate_kJ_kWh, failures)
        call expect_true("HR(40%) > HR(70%)", &
            od40%cyc%heat_rate_kJ_kWh > od70%cyc%heat_rate_kJ_kWh, failures)
        call expect_true("HR(40%) at least 25% worse than design", &
            od40%cyc%heat_rate_kJ_kWh > 1.25_dp * od100%cyc%heat_rate_kJ_kWh, failures)
    end block

    ! --- Surge margin: grows toward part load, shrinks with ramp rate. ---
    block
        type(OffDesignPoint) :: od_full, od_part, od_ramp, od_slam
        call solve_off_design(base, 1.0_dp, 0.0_dp, od_full)
        call solve_off_design(base, 0.6_dp, 0.0_dp, od_part)
        call expect_true("SM grows at part load (IGV operation)", &
            od_part%surge_margin_pct > od_full%surge_margin_pct, failures)
        call solve_off_design(base, 1.0_dp, 8.0_dp, od_ramp)
        call expect_true("normal AGC ramp keeps SM above alarm", &
            od_ramp%surge_margin_pct > 8.0_dp, failures)
        call expect_true("ramping erodes SM", &
            od_ramp%surge_margin_pct < od_full%surge_margin_pct, failures)
        call solve_off_design(base, 1.0_dp, 40.0_dp, od_slam)
        call expect_true("dispatch slam violates surge margin", &
            od_slam%surge_margin_pct < 8.0_dp, failures)
    end block

    ! --- Ambient derate: hot day reduces capacity (corrected-flow physics). ---
    block
        type(OffDesignPoint) :: od_iso, od_hot
        type(InputCase) :: hot
        call solve_off_design(base, 1.0_dp, 0.0_dp, od_iso)
        hot = base
        hot%ambient_T_K = 308.15_dp     ! +35 C day
        call solve_off_design(hot, 1.0_dp, 0.0_dp, od_hot)
        call expect_true("hot day derates capacity by >5%", &
            od_hot%cyc%net_power_MW < 0.95_dp * od_iso%cyc%net_power_MW, failures)
    end block

    ! --- Minimum stable load: pinned at IGV + TIT floors. ---
    block
        type(OffDesignPoint) :: od
        call solve_off_design(base, 0.05_dp, 0.0_dp, od)
        call expect_true("min-load floor flagged", od%at_min_load, failures)
        call expect_near("min load: IGVs at floor", od%flow_frac, IGV_MIN_FLOW_FRAC, 1.0e-9_dp, failures)
        call expect_near("min load: firing at floor", od%TIT_K, TIT_MIN_K, 1.0e-9_dp, failures)
        call expect_true("min load is a real positive power", od%cyc%net_power_MW > 1.0_dp, failures)
    end block

    call finish("off_design", failures)

contains

    include "test_assert.inc"

end program test_off_design
