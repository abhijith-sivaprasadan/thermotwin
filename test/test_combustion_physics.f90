!> @file test_combustion_physics.f90
!> @brief Revamp 7.0 P3 checks for combustion chemistry and hot-section losses.
program test_combustion_physics
    use precision_kinds, only: dp
    use combustion_physics, only: CombustionPhysicsResult, solve_combustion_physics
    use engine_core, only: GridState, engine_init, refresh_model
    implicit none

    integer :: failures
    failures = 0

    block
        type(CombustionPhysicsResult) :: ng, h2, low_load, hot

        call solve_combustion_physics(0.0_dp, 680.0_dp, 1400.0_dp, 780.0_dp, 288.15_dp, &
            0.018_dp, 100.0_dp, 100.0_dp, 1.0_dp, 15.0_dp, 0.86_dp, 0.89_dp, ng)
        call solve_combustion_physics(30.0_dp, 680.0_dp, 1400.0_dp, 780.0_dp, 288.15_dp, &
            0.018_dp, 100.0_dp, 100.0_dp, 1.0_dp, 15.0_dp, 0.86_dp, 0.89_dp, h2)
        call solve_combustion_physics(0.0_dp, 640.0_dp, 1350.0_dp, 700.0_dp, 288.15_dp, &
            0.014_dp, 82.0_dp, 35.0_dp, 0.55_dp, 10.0_dp, 0.86_dp, 0.89_dp, low_load)
        call solve_combustion_physics(0.0_dp, 710.0_dp, 1550.0_dp, 880.0_dp, 310.0_dp, &
            0.020_dp, 100.0_dp, 100.0_dp, 1.0_dp, 15.0_dp, 0.86_dp, 0.89_dp, hot)

        call expect_true("P3 NG flame temperature plausible", &
            ng%adiabatic_flame_T_K > 2050.0_dp .and. ng%adiabatic_flame_T_K < 2250.0_dp, failures)
        call expect_true("P3 H2 raises flame temperature", h2%adiabatic_flame_T_K > ng%adiabatic_flame_T_K, failures)
        call expect_true("P3 H2 raises Zeldovich NOx", h2%nox_ppm_15o2 > ng%nox_ppm_15o2, failures)
        call expect_true("P3 H2 reduces CO2 factor", h2%co2_factor_kg_kg < ng%co2_factor_kg_kg, failures)
        call expect_true("P3 Wobbe deviation tracked", h2%wobbe_deviation_pct < -1.0_dp, failures)
        call expect_true("P3 flashback margin tightens with H2", &
            h2%flashback_margin_pct < ng%flashback_margin_pct, failures)
        call expect_true("P3 low-load CO rises", low_load%co_ppm_15o2 > ng%co_ppm_15o2, failures)
        call expect_true("P3 hotter firing raises cooling demand", hot%cooling_air_pct > ng%cooling_air_pct, failures)
        call expect_true("P3 hotter firing increases tip loss", hot%tip_loss_pct > ng%tip_loss_pct, failures)
    end block

    block
        type(GridState) :: st

        call engine_init(st)
        st%h2_fraction_pct = 25.0_dp
        st%gas_dispatch_pct = 88.0_dp
        st%TIT_K = 1450.0_dp
        call refresh_model(st, 0.25_dp)

        call expect_true("P3 engine H2 mass fraction populated", st%h2_mass_fraction > 0.0_dp, failures)
        call expect_true("P3 engine flame temperature populated", st%flame_temp_ad_K > 2050.0_dp, failures)
        call expect_true("P3 engine NOx populated", st%nox_mg_nm3_15o2 > 0.0_dp, failures)
        call expect_true("P3 engine CO populated", st%co_mg_nm3_15o2 > 0.0_dp, failures)
        call expect_true("P3 engine flashback remains finite", st%flashback_margin_pct > 20.0_dp, failures)
        call expect_true("P3 engine component losses populated", &
            st%compressor_poly_loss_pct > 0.0_dp .and. st%turbine_poly_loss_pct > 0.0_dp, failures)
    end block

    call finish("combustion_physics", failures)

contains
    include "test_assert.inc"
end program test_combustion_physics
