!> @file test_market_data.f90
!> @brief Phase 5 checks for location profiles, weather fallback, replay, and live economics.
program test_market_data
    use precision_kinds, only: dp
    use engine_core
    implicit none

    integer :: failures
    failures = 0

    ! --- Location profile switches frequency standard, prices, and weather mode. ---
    block
        type(GridState) :: st
        call engine_init(st)
        call apply_market_profile(st, MARKET_TEXAS_ERCOT)
        call expect_near("market: ERCOT nominal frequency", st%nominal_frequency_Hz, 60.0_dp, 1.0e-12_dp, failures)
        call expect_near("market: ERCOT live frequency reset", st%frequency_Hz, 60.0_dp, 1.0e-12_dp, failures)
        call expect_true("market: ERCOT fuel cheaper than TTF default", st%fuel_price_usd_gj < FUEL_PRICE_USD_GJ, failures)
        call expect_true("market: weather drive enabled on profile switch", st%market_weather_enabled, failures)
    end block

    ! --- Open-Meteo-style fallback variables drive PV/wind renewable availability. ---
    block
        type(GridState) :: st
        call engine_init(st)
        call apply_market_profile(st, MARKET_GERMANY_DELU)
        st%elapsed_s = 0.50_dp * st%market_replay_day_s
        call refresh_market_data(st, 0.0_dp)
        call expect_true("market: midday solar irradiance positive", st%market_solar_W_m2 > 500.0_dp, failures)
        call expect_true("market: PV contributes at midday", st%market_pv_power_MW > 10.0_dp, failures)
        call expect_true("market: renewable availability is physical", &
            st%renewable_MW > st%market_wind_power_MW, failures)
    end block

    ! --- Replayed market day drives a diurnal demand and price curve. ---
    block
        type(GridState) :: st
        real(dp) :: low_load, peak_load, low_price, peak_price
        call engine_init(st)
        call apply_market_profile(st, MARKET_STOCKHOLM_SE3)
        st%market_load_replay_enabled = .true.
        st%market_replay_day_s = 240.0_dp
        st%elapsed_s = 0.0_dp
        call refresh_market_data(st, 0.0_dp)
        low_load = st%demand_MW
        low_price = st%power_price_usd_mwh
        st%elapsed_s = 185.0_dp
        call refresh_market_data(st, 0.0_dp)
        peak_load = st%demand_MW
        peak_price = st%power_price_usd_mwh
        call expect_true("market: replay raises evening load", peak_load > low_load + 12.0_dp, failures)
        call expect_true("market: replay raises power price with load", peak_price > low_price, failures)
    end block

    ! --- Economics consumes live power, fuel, reserve, and carbon prices. ---
    block
        type(GridState) :: st
        call engine_init(st)
        st%demand_MW = 10.0_dp
        st%supply_MW = 10.0_dp
        st%plant_power_MW = 10.0_dp
        st%heat_input_MW = 10.0_dp
        st%fuel_flow_kg_s = 0.20_dp
        st%power_price_usd_mwh = 120.0_dp
        st%fuel_price_usd_gj = 5.0_dp
        st%carbon_price_usd_t = 50.0_dp
        call refresh_economics(st)
        call expect_near("market: revenue uses live power price", st%revenue_usd_h, 1200.0_dp, 1.0e-9_dp, failures)
        call expect_near("market: fuel uses live gas price", st%fuel_cost_usd_h, 180.0_dp, 1.0e-9_dp, failures)
        call expect_near("market: carbon cost uses live profile", st%co2_cost_usd_h, 99.0_dp, 1.0e-9_dp, failures)
    end block

    call finish("market_data", failures)

contains

    include "test_assert.inc"

end program test_market_data
