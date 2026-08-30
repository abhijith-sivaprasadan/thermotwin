!> @file test_thermo_fidelity.f90
!> @brief Revamp 7.0 P2 checks for NASA-gas properties, IF97-style steam
!>        helpers, and epsilon-NTU HRSG / steam-cycle coupling.
program test_thermo_fidelity
    use precision_kinds, only: dp
    use fluid_properties, only: set_property_model, PROP_CONSTANT, PROP_VARIABLE, &
        cp_air_at, cp_gas_at, gamma_air_at, gamma_gas_at, if97_saturation_T_K, &
        if97_h_liq_kJ_kg, if97_h_vap_kJ_kg
    use hrsg, only: HrsgResult, solve_hrsg
    use steam_cycle, only: SteamCycleResult, solve_steam_cycle
    implicit none

    integer :: failures
    failures = 0

    block
        real(dp) :: cp300, cp1000, cpg800, cpg1500
        call set_property_model(PROP_VARIABLE)
        cp300 = cp_air_at(300.0_dp)
        cp1000 = cp_air_at(1000.0_dp)
        cpg800 = cp_gas_at(800.0_dp)
        cpg1500 = cp_gas_at(1500.0_dp)

        call expect_true("NASA air cp(300 K) in reference band", &
            cp300 > 995.0_dp .and. cp300 < 1020.0_dp, failures)
        call expect_true("NASA air cp rises with temperature", cp1000 > cp300, failures)
        call expect_true("NASA gas cp rises with temperature", cpg1500 > cpg800, failures)
        call expect_true("air gamma drops at high T", gamma_air_at(1000.0_dp) < gamma_air_at(300.0_dp), failures)
        call expect_true("gas gamma remains physical", &
            gamma_gas_at(1500.0_dp) > 1.20_dp .and. gamma_gas_at(1500.0_dp) < 1.35_dp, failures)
    end block

    block
        real(dp) :: Tsat1, Tsat35, hf1, hg1
        Tsat1 = if97_saturation_T_K(1.01325_dp)
        Tsat35 = if97_saturation_T_K(35.0_dp)
        hf1 = if97_h_liq_kJ_kg(1.01325_dp)
        hg1 = if97_h_vap_kJ_kg(1.01325_dp)

        call expect_near("IF97 helper: 1 atm saturation temperature", Tsat1, 373.15_dp, 3.0_dp, failures)
        call expect_near("IF97 helper: 35 bar saturation temperature", Tsat35, 515.0_dp, 5.0_dp, failures)
        call expect_near("IF97 helper: saturated liquid h at 1 atm", hf1, 419.0_dp, 18.0_dp, failures)
        call expect_near("IF97 helper: saturated vapour h at 1 atm", hg1, 2676.0_dp, 45.0_dp, failures)
    end block

    block
        type(HrsgResult) :: h
        type(SteamCycleResult) :: s
        call set_property_model(PROP_VARIABLE)
        call solve_hrsg(850.0_dp, 80.0_dp, 288.15_dp, h)
        call solve_steam_cycle(h, 288.15_dp, s)

        call expect_true("P2 HRSG: HP heat recovery positive", h%hp_recovered_heat_MW > 10.0_dp, failures)
        call expect_true("P2 HRSG: LP recovery active", h%lp_recovered_heat_MW > 0.1_dp, failures)
        call expect_true("P2 HRSG: pinch respected", h%pinch_ok .and. h%pinch_K >= 15.0_dp, failures)
        call expect_true("P2 steam: IF97 enthalpy drop physical", &
            s%ideal_work_J_kg > 0.8e6_dp .and. s%ideal_work_J_kg < 1.6e6_dp, failures)
        call expect_true("P2 steam: wet exhaust quality plausible", &
            s%exhaust_quality > 0.78_dp .and. s%exhaust_quality <= 1.0_dp, failures)
    end block

    call set_property_model(PROP_CONSTANT)
    call finish("thermo_fidelity", failures)

contains
    include "test_assert.inc"
end program test_thermo_fidelity
