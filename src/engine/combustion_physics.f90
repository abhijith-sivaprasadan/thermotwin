!> @file combustion_physics.f90
!> @brief Revamp 7.0 P3 combustor chemistry and hot-section loss correlations.
module combustion_physics
    use precision_kinds, only: dp
    implicit none
    private

    public :: CombustionPhysicsResult, solve_combustion_physics

    real(dp), parameter :: M_CH4 = 16.04_dp
    real(dp), parameter :: M_H2  = 2.016_dp
    real(dp), parameter :: LHV_CH4_MJ_KG = 50.0_dp
    real(dp), parameter :: LHV_H2_MJ_KG  = 120.0_dp
    real(dp), parameter :: CO2_CH4_KG_KG = 2.75_dp
    real(dp), parameter :: WOBBE_NG_MJ_M3 = 51.6_dp
    real(dp), parameter :: WOBBE_H2_MJ_M3 = 48.2_dp
    real(dp), parameter :: STOICH_AF_CH4 = 17.2_dp
    real(dp), parameter :: STOICH_AF_H2  = 34.3_dp
    real(dp), parameter :: MW_CO2 = 44.01_dp
    real(dp), parameter :: MW_AIR = 28.97_dp

    type :: CombustionPhysicsResult
        real(dp) :: lhv_mj_kg = LHV_CH4_MJ_KG
        real(dp) :: co2_factor_kg_kg = CO2_CH4_KG_KG
        real(dp) :: h2_mass_fraction = 0.0_dp
        real(dp) :: wobbe_mj_m3 = WOBBE_NG_MJ_M3
        real(dp) :: wobbe_deviation_pct = 0.0_dp
        logical  :: wobbe_ok = .true.
        real(dp) :: adiabatic_flame_T_K = 2145.0_dp
        real(dp) :: flame_shift_K = 0.0_dp
        real(dp) :: nox_factor = 1.0_dp
        real(dp) :: nox_ppm_15o2 = 30.0_dp
        real(dp) :: nox_mg_nm3_15o2 = 61.5_dp
        real(dp) :: co_ppm_15o2 = 5.0_dp
        real(dp) :: co_mg_nm3_15o2 = 6.25_dp
        real(dp) :: lambda = 3.2_dp
        real(dp) :: o2_dry_pct = 15.0_dp
        real(dp) :: co2_vol_pct = 3.5_dp
        real(dp) :: flashback_margin_pct = 105.0_dp
        real(dp) :: cooling_air_pct = 7.0_dp
        real(dp) :: cooling_air_kg_s = 7.0_dp
        real(dp) :: metal_temp_margin_K = 170.0_dp
        real(dp) :: tip_clearance_mm = 1.2_dp
        real(dp) :: tip_loss_pct = 0.9_dp
        real(dp) :: compressor_poly_loss_pct = 14.0_dp
        real(dp) :: turbine_poly_loss_pct = 12.0_dp
        real(dp) :: combustor_pattern_factor_pct = 8.0_dp
    end type CombustionPhysicsResult

contains

    pure subroutine solve_combustion_physics(h2_vol_pct, T2_K, TIT_K, exhaust_K, ambient_T_K, &
            fuel_air_ratio, mdot_air_kg_s, gas_dispatch_pct, flow_frac, PR_op, eta_c, eta_t, res)
        real(dp), intent(in) :: h2_vol_pct, T2_K, TIT_K, exhaust_K, ambient_T_K
        real(dp), intent(in) :: fuel_air_ratio, mdot_air_kg_s, gas_dispatch_pct
        real(dp), intent(in) :: flow_frac, PR_op, eta_c, eta_t
        type(CombustionPhysicsResult), intent(out) :: res
        real(dp) :: xv, xm, denom, stoich_af, air_fuel, load_frac
        real(dp) :: t_ad_ng, base_nox, fuel_mass_frac, co2_mass_frac
        real(dp) :: t2, tit, texh, amb, flow, cooling, metal_T

        xv = clamp_real(h2_vol_pct / 100.0_dp, 0.0_dp, 0.30_dp)
        denom = xv * M_H2 + (1.0_dp - xv) * M_CH4
        if (denom > 1.0e-12_dp) then
            xm = xv * M_H2 / denom
        else
            xm = 0.0_dp
        end if

        t2 = clamp_real(T2_K, 450.0_dp, 950.0_dp)
        tit = clamp_real(TIT_K, 1100.0_dp, 1700.0_dp)
        texh = clamp_real(exhaust_K, 450.0_dp, 1100.0_dp)
        amb = clamp_real(ambient_T_K, 240.0_dp, 330.0_dp)
        flow = clamp_real(flow_frac, 0.30_dp, 1.10_dp)
        load_frac = clamp_real(gas_dispatch_pct / 100.0_dp, 0.20_dp, 1.10_dp)

        res%h2_mass_fraction = xm
        res%lhv_mj_kg = (1.0_dp - xm) * LHV_CH4_MJ_KG + xm * LHV_H2_MJ_KG
        res%co2_factor_kg_kg = CO2_CH4_KG_KG * (1.0_dp - xm)
        res%wobbe_mj_m3 = (1.0_dp - xv) * WOBBE_NG_MJ_M3 + xv * WOBBE_H2_MJ_M3
        res%wobbe_deviation_pct = 100.0_dp * (res%wobbe_mj_m3 / WOBBE_NG_MJ_M3 - 1.0_dp)
        res%wobbe_ok = abs(res%wobbe_deviation_pct) <= 5.0_dp

        stoich_af = (1.0_dp - xm) * STOICH_AF_CH4 + xm * STOICH_AF_H2
        if (fuel_air_ratio > 1.0e-8_dp) then
            air_fuel = 1.0_dp / fuel_air_ratio
        else
            air_fuel = 3.2_dp * stoich_af
        end if
        res%lambda = clamp_real(air_fuel / max(stoich_af, 1.0e-6_dp), 1.05_dp, 6.0_dp)
        res%o2_dry_pct = clamp_real(21.0_dp * (res%lambda - 1.0_dp) / res%lambda, 0.0_dp, 18.5_dp)

        fuel_mass_frac = max(0.0_dp, fuel_air_ratio) / (1.0_dp + max(0.0_dp, fuel_air_ratio))
        co2_mass_frac = clamp_real(fuel_mass_frac * res%co2_factor_kg_kg, 0.0_dp, 0.20_dp)
        denom = co2_mass_frac / MW_CO2 + (1.0_dp - co2_mass_frac) / MW_AIR
        if (denom > 1.0e-12_dp) then
            res%co2_vol_pct = 100.0_dp * (co2_mass_frac / MW_CO2) / denom
        else
            res%co2_vol_pct = 0.0_dp
        end if

        t_ad_ng = flame_temperature_model(0.0_dp, t2, tit, res%lambda)
        res%adiabatic_flame_T_K = flame_temperature_model(xv, t2, tit, res%lambda)
        res%flame_shift_K = res%adiabatic_flame_T_K - t_ad_ng

        base_nox = nox_ppm_model(0.0_dp, t_ad_ng, load_frac, res%o2_dry_pct)
        res%nox_ppm_15o2 = nox_ppm_model(xv, res%adiabatic_flame_T_K, load_frac, res%o2_dry_pct)
        res%nox_factor = res%nox_ppm_15o2 / max(base_nox, 1.0e-6_dp)
        res%nox_mg_nm3_15o2 = res%nox_ppm_15o2 * 2.05_dp
        res%co_ppm_15o2 = co_ppm_model(xv, res%adiabatic_flame_T_K, load_frac)
        res%co_mg_nm3_15o2 = res%co_ppm_15o2 * 1.25_dp

        res%flashback_margin_pct = clamp_real(115.0_dp - 155.0_dp * xv - 0.030_dp * (t2 - 680.0_dp) + &
            22.0_dp * (flow - 0.75_dp) - 0.015_dp * max(0.0_dp, tit - 1400.0_dp), -20.0_dp, 130.0_dp)

        cooling = 6.2_dp + 0.020_dp * (tit - 1350.0_dp) + &
            1.3_dp * max(0.0_dp, 1.0_dp - load_frac) ** 1.2_dp + &
            0.008_dp * max(0.0_dp, res%adiabatic_flame_T_K - 2150.0_dp)
        res%cooling_air_pct = clamp_real(cooling, 4.5_dp, 15.0_dp)
        res%cooling_air_kg_s = mdot_air_kg_s * res%cooling_air_pct / 100.0_dp
        metal_T = 940.0_dp + 0.28_dp * (tit - 1400.0_dp) + &
            0.08_dp * (res%adiabatic_flame_T_K - 2150.0_dp) - &
            3.5_dp * (res%cooling_air_pct - 7.0_dp) + 0.02_dp * (texh - 760.0_dp)
        res%metal_temp_margin_K = 1125.0_dp - metal_T

        res%tip_clearance_mm = clamp_real(1.15_dp + 0.0035_dp * (amb - 288.15_dp) + &
            0.0025_dp * (tit - 1400.0_dp) + 0.25_dp * (1.0_dp - flow), 0.70_dp, 3.0_dp)
        res%tip_loss_pct = clamp_real(0.85_dp + 0.55_dp * (res%tip_clearance_mm - 1.15_dp) + &
            0.40_dp * (1.0_dp - flow), 0.30_dp, 4.0_dp)

        res%compressor_poly_loss_pct = clamp_real((1.0_dp - eta_c) * 100.0_dp + &
            1.8_dp * (1.0_dp - flow) ** 2 + 0.10_dp * max(0.0_dp, PR_op - 15.0_dp) + &
            0.020_dp * max(0.0_dp, amb - 288.15_dp), 4.0_dp, 25.0_dp)
        res%turbine_poly_loss_pct = clamp_real((1.0_dp - eta_t) * 100.0_dp + res%tip_loss_pct + &
            0.12_dp * res%cooling_air_pct + 2.0_dp * xv, 5.0_dp, 25.0_dp)
        res%combustor_pattern_factor_pct = clamp_real(8.0_dp + 6.0_dp * xv + &
            0.008_dp * max(0.0_dp, res%adiabatic_flame_T_K - 2150.0_dp) + &
            4.0_dp * abs(res%lambda - 3.0_dp) / 3.0_dp, 5.0_dp, 18.0_dp)
    end subroutine solve_combustion_physics

    pure function flame_temperature_model(h2_vol_frac, T2_K, TIT_K, lambda) result(t_ad)
        real(dp), intent(in) :: h2_vol_frac, T2_K, TIT_K, lambda
        real(dp) :: t_ad

        t_ad = 2145.0_dp + 125.0_dp * h2_vol_frac + 0.22_dp * (T2_K - 680.0_dp) + &
            0.18_dp * (TIT_K - 1400.0_dp) - 35.0_dp * (lambda - 3.2_dp)
        t_ad = clamp_real(t_ad, 1750.0_dp, 2450.0_dp)
    end function flame_temperature_model

    pure function nox_ppm_model(h2_vol_frac, t_ad_K, load_frac, o2_dry_pct) result(ppm)
        real(dp), intent(in) :: h2_vol_frac, t_ad_K, load_frac, o2_dry_pct
        real(dp) :: ppm, thermal, load_gain, o2_gain

        thermal = exp(clamp_real((t_ad_K - 2100.0_dp) / 115.0_dp, -3.0_dp, 3.0_dp))
        load_gain = 0.65_dp + 0.55_dp * sqrt(clamp_real(load_frac, 0.05_dp, 1.10_dp))
        o2_gain = clamp_real(1.0_dp + 0.15_dp * (o2_dry_pct - 15.0_dp) / 5.0_dp, 0.75_dp, 1.25_dp)
        ppm = clamp_real(23.0_dp * thermal * load_gain * o2_gain * (1.0_dp + 1.20_dp * h2_vol_frac), &
            2.0_dp, 220.0_dp)
    end function nox_ppm_model

    pure function co_ppm_model(h2_vol_frac, t_ad_K, load_frac) result(ppm)
        real(dp), intent(in) :: h2_vol_frac, t_ad_K, load_frac
        real(dp) :: ppm, low_load, cold_gain

        low_load = (1.0_dp - clamp_real(load_frac, 0.0_dp, 1.0_dp)) ** 2.2_dp
        cold_gain = exp(clamp_real((2050.0_dp - t_ad_K) / 220.0_dp, -1.5_dp, 1.5_dp))
        ppm = clamp_real((4.0_dp + 42.0_dp * low_load) * cold_gain * (1.0_dp - 0.35_dp * h2_vol_frac), &
            1.0_dp, 180.0_dp)
    end function co_ppm_model

    pure function clamp_real(x, lo, hi) result(y)
        real(dp), intent(in) :: x, lo, hi
        real(dp) :: y

        y = min(max(x, lo), hi)
    end function clamp_real

end module combustion_physics
