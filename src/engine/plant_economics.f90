!> @file plant_economics.f90
!> @brief Operating economics: revenue, fuel, imbalance penalty, the BESS
!>        value stack (imbalance/FCR/arbitrage), renewable reserve value,
!>        battery payback, and CO2 accounting.
module plant_economics
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    public :: refresh_economics

contains

    subroutine refresh_economics(st)
        type(GridState), intent(inout) :: st
        real(dp) :: served_MW, battery_capex_usd, annual_value_usd
        real(dp) :: imbalance_without_bess_MW, avoided_imbalance_MW
        real(dp) :: bess_up_reserve_MW, bess_down_reserve_MW, bess_fcr_reserve_MW
        real(dp) :: surplus_without_bess_MW, captured_surplus_MW

        served_MW = min(st%demand_MW, max(0.0_dp, st%supply_MW))
        st%revenue_usd_h = served_MW * POWER_PRICE_USD_MWH
        st%fuel_cost_usd_h = st%heat_input_MW * 3.6_dp * FUEL_PRICE_USD_GJ
        st%storage_cost_usd_h = abs(st%storage_MW) * STORAGE_CYCLE_COST_USD_MWH
        st%imbalance_penalty_usd_h = abs(st%imbalance_MW) * IMBALANCE_PENALTY_USD_MWH
        st%margin_usd_h = st%revenue_usd_h - st%fuel_cost_usd_h - &
            st%storage_cost_usd_h - st%imbalance_penalty_usd_h

        imbalance_without_bess_MW = st%plant_power_MW + effective_renewable_MW(st) - st%demand_MW
        avoided_imbalance_MW = max(0.0_dp, abs(imbalance_without_bess_MW) - abs(st%imbalance_MW))
        st%bess_imbalance_value_usd_h = avoided_imbalance_MW * IMBALANCE_PENALTY_USD_MWH

        bess_up_reserve_MW = max(0.0_dp, STORAGE_MAX_MW - max(0.0_dp, st%storage_MW))
        bess_down_reserve_MW = max(0.0_dp, abs(STORAGE_MIN_MW) - max(0.0_dp, -st%storage_MW))
        if (st%battery_soc_pct < 20.0_dp) bess_up_reserve_MW = 0.0_dp
        if (st%battery_soc_pct > 80.0_dp) bess_down_reserve_MW = 0.0_dp
        bess_fcr_reserve_MW = min(5.0_dp, min(bess_up_reserve_MW, bess_down_reserve_MW))
        if (.not. st%fcr_hold) bess_fcr_reserve_MW = 0.0_dp
        st%bess_fcr_value_usd_h = bess_fcr_reserve_MW * FCR_RESERVE_PRICE_USD_MW_H

        surplus_without_bess_MW = max(0.0_dp, imbalance_without_bess_MW)
        captured_surplus_MW = min(max(0.0_dp, -st%storage_MW), surplus_without_bess_MW)
        st%bess_arbitrage_value_usd_h = &
            captured_surplus_MW * BESS_ARBITRAGE_SPREAD_USD_MWH + &
            max(0.0_dp, st%storage_MW) * BESS_ARBITRAGE_SPREAD_USD_MWH * 0.35_dp
        st%bess_degradation_cost_usd_h = abs(st%storage_MW) * BESS_DEGRADATION_USD_MWH

        st%renewable_reserve_value_usd_h = renewable_headroom_MW(st) * RENEWABLE_RESERVE_PRICE_USD_MW_H
        st%renewable_curtail_cost_usd_h = renewable_headroom_MW(st) * POWER_PRICE_USD_MWH
        st%value_stack_usd_h = st%bess_imbalance_value_usd_h + st%bess_fcr_value_usd_h + &
            st%bess_arbitrage_value_usd_h + st%renewable_reserve_value_usd_h - &
            st%storage_cost_usd_h - st%bess_degradation_cost_usd_h - &
            st%renewable_curtail_cost_usd_h

        st%battery_value_usd_h = max(0.0_dp, st%bess_imbalance_value_usd_h + &
            st%bess_fcr_value_usd_h + st%bess_arbitrage_value_usd_h - &
            st%storage_cost_usd_h - st%bess_degradation_cost_usd_h)
        battery_capex_usd = BATTERY_CAPACITY_MWH * BATTERY_CAPEX_USD_MWH
        annual_value_usd = st%battery_value_usd_h * ROI_EQUIVALENT_HOURS_PER_YEAR
        if (annual_value_usd > 1.0e-6_dp) then
            st%battery_payback_years = battery_capex_usd / annual_value_usd
        else
            st%battery_payback_years = 99.0_dp
        end if

        st%CO2_rate_kg_s = st%fuel_flow_kg_s * CO2_KG_PER_KG_FUEL
        if (st%plant_power_MW > 0.1_dp) then
            st%CO2_intensity_g_kWh = st%CO2_rate_kg_s * 3600.0_dp / st%plant_power_MW
        else
            st%CO2_intensity_g_kWh = 0.0_dp
        end if
    end subroutine refresh_economics

end module plant_economics
