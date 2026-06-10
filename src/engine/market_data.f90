!> @file market_data.f90
!> @brief Phase 5 location profiles, offline market/weather fallback, and load replay.
module market_data
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private

    integer, parameter, public :: MARKET_PROFILE_N = 4
    integer, parameter, public :: MARKET_STOCKHOLM_SE3 = 1
    integer, parameter, public :: MARKET_GERMANY_DELU = 2
    integer, parameter, public :: MARKET_TEXAS_ERCOT = 3
    integer, parameter, public :: MARKET_LOUISIANA_HH = 4

    character(len=24), parameter :: PROFILE_NAME(MARKET_PROFILE_N) = &
        [character(len=24) :: "Stockholm SE3", "Germany DE-LU", "Texas ERCOT", "Louisiana HH"]
    character(len=16), parameter :: POWER_ZONE(MARKET_PROFILE_N) = &
        [character(len=16) :: "SE3", "DE-LU", "ERCOT", "MISO-S"]
    character(len=16), parameter :: GAS_HUB(MARKET_PROFILE_N) = &
        [character(len=16) :: "TTF", "THE/TTF", "Waha/HH", "Henry Hub"]
    real(dp), parameter :: LAT_DEG(MARKET_PROFILE_N) = [59.33_dp, 52.52_dp, 31.97_dp, 30.22_dp]
    real(dp), parameter :: LON_DEG(MARKET_PROFILE_N) = [18.07_dp, 13.40_dp, -99.90_dp, -92.02_dp]
    real(dp), parameter :: AMBIENT_C(MARKET_PROFILE_N) = [8.0_dp, 10.0_dp, 26.0_dp, 25.0_dp]
    real(dp), parameter :: POWER_USD_MWH(MARKET_PROFILE_N) = [88.0_dp, 104.0_dp, 72.0_dp, 64.0_dp]
    real(dp), parameter :: FUEL_USD_GJ(MARKET_PROFILE_N) = [11.5_dp, 12.0_dp, 3.8_dp, 3.2_dp]
    real(dp), parameter :: CARBON_USD_T(MARKET_PROFILE_N) = [72.0_dp, 78.0_dp, 0.0_dp, 0.0_dp]
    real(dp), parameter :: FCR_USD_MW_H(MARKET_PROFILE_N) = [24.0_dp, 22.0_dp, 15.0_dp, 13.0_dp]
    real(dp), parameter :: BASE_DEMAND_MW(MARKET_PROFILE_N) = [32.0_dp, 42.0_dp, 44.0_dp, 38.0_dp]
    real(dp), parameter :: PEAK_DEMAND_MW(MARKET_PROFILE_N) = [64.0_dp, 88.0_dp, 86.0_dp, 76.0_dp]
    real(dp), parameter :: WIND_CAP_MW(MARKET_PROFILE_N) = [36.0_dp, 34.0_dp, 42.0_dp, 18.0_dp]
    real(dp), parameter :: PV_CAP_MW(MARKET_PROFILE_N) = [16.0_dp, 28.0_dp, 38.0_dp, 32.0_dp]
    real(dp), parameter :: WIND_BASE_M_S(MARKET_PROFILE_N) = [7.4_dp, 6.5_dp, 7.0_dp, 5.7_dp]
    real(dp), parameter :: SOLAR_PEAK_W_M2(MARKET_PROFILE_N) = [650.0_dp, 760.0_dp, 930.0_dp, 900.0_dp]

    public :: apply_market_profile, cycle_market_profile, refresh_market_data
    public :: market_profile_name, wind_capacity_factor

contains

    subroutine apply_market_profile(st, profile_id)
        type(GridState), intent(inout) :: st
        integer, intent(in) :: profile_id
        integer :: id

        id = min(max(profile_id, 1), MARKET_PROFILE_N)
        st%market_profile_id = id
        st%market_profile_name = PROFILE_NAME(id)
        st%market_power_zone = POWER_ZONE(id)
        st%market_gas_hub = GAS_HUB(id)
        st%market_latitude_deg = LAT_DEG(id)
        st%market_longitude_deg = LON_DEG(id)
        st%ambient_C = AMBIENT_C(id)
        st%power_price_usd_mwh = POWER_USD_MWH(id)
        st%fuel_price_usd_gj = FUEL_USD_GJ(id)
        st%carbon_price_usd_t = CARBON_USD_T(id)
        st%fcr_reserve_price_usd_mw_h = FCR_USD_MW_H(id)
        st%bess_arbitrage_spread_usd_mwh = max(12.0_dp, 0.38_dp * st%power_price_usd_mwh)
        st%renewable_reserve_price_usd_mw_h = max(8.0_dp, 0.14_dp * st%power_price_usd_mwh)
        st%market_base_demand_MW = BASE_DEMAND_MW(id)
        st%market_peak_demand_MW = PEAK_DEMAND_MW(id)
        st%market_wind_capacity_MW = WIND_CAP_MW(id)
        st%market_pv_capacity_MW = PV_CAP_MW(id)
        st%market_weather_enabled = .true.
        st%market_source_code = 0
        call set_frequency_standard(st, merge(60.0_dp, 50.0_dp, id >= MARKET_TEXAS_ERCOT))
        call refresh_market_data(st, 0.0_dp)
    end subroutine apply_market_profile

    subroutine cycle_market_profile(st)
        type(GridState), intent(inout) :: st
        integer :: next_id

        next_id = st%market_profile_id + 1
        if (next_id > MARKET_PROFILE_N) next_id = 1
        call apply_market_profile(st, next_id)
    end subroutine cycle_market_profile

    subroutine refresh_market_data(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: dt_s
        real(dp) :: hour, shape, wind_cf, solar_cf, price_shape
        integer :: id

        id = min(max(st%market_profile_id, 1), MARKET_PROFILE_N)
        hour = market_hour_from_clock(st)
        st%market_hour = hour
        st%market_data_age_s = max(0.0_dp, st%elapsed_s - st%market_last_update_s)

        if (st%market_weather_enabled) then
            st%ambient_C = AMBIENT_C(id) + 5.0_dp * sin(2.0_dp * PI_DP * (hour - 14.0_dp) / 24.0_dp)
            st%market_wind_speed_m_s = max(0.0_dp, WIND_BASE_M_S(id) + &
                2.1_dp * sin(2.0_dp * PI_DP * (hour + real(id, dp)) / 24.0_dp) + &
                0.7_dp * sin(4.0_dp * PI_DP * hour / 24.0_dp))
            solar_cf = daylight_shape(hour)
            st%market_solar_W_m2 = SOLAR_PEAK_W_M2(id) * solar_cf
            st%market_pv_power_MW = st%market_pv_capacity_MW * solar_cf * &
                max(0.82_dp, 1.0_dp - 0.004_dp * max(0.0_dp, st%ambient_C - 25.0_dp))
            wind_cf = wind_capacity_factor(st%market_wind_speed_m_s)
            st%market_wind_power_MW = st%market_wind_capacity_MW * wind_cf
            st%renewable_MW = clamp_real((st%market_pv_power_MW + st%market_wind_power_MW) * &
                st%renewable_scale_pct / 100.0_dp, 0.0_dp, RENEWABLE_MAX_MW)
            st%renewable_curtail_MW = min(st%renewable_curtail_MW, st%renewable_MW)
        end if

        if (st%market_load_replay_enabled) then
            shape = demand_shape(hour)
            st%demand_MW = clamp_real(st%market_base_demand_MW + &
                shape * (st%market_peak_demand_MW - st%market_base_demand_MW), &
                DEMAND_MIN_MW, DEMAND_MAX_MW)
            price_shape = 0.78_dp + 0.44_dp * shape
            st%power_price_usd_mwh = POWER_USD_MWH(id) * price_shape
        end if

        if (dt_s >= 0.0_dp) st%market_last_update_s = st%elapsed_s
    end subroutine refresh_market_data

    pure function market_profile_name(profile_id) result(name)
        integer, intent(in) :: profile_id
        character(len=24) :: name
        integer :: id

        id = min(max(profile_id, 1), MARKET_PROFILE_N)
        name = PROFILE_NAME(id)
    end function market_profile_name

    pure function wind_capacity_factor(speed_m_s) result(cf)
        real(dp), intent(in) :: speed_m_s
        real(dp) :: cf

        if (speed_m_s < 3.0_dp .or. speed_m_s >= 25.0_dp) then
            cf = 0.0_dp
        else if (speed_m_s >= 12.0_dp) then
            cf = 1.0_dp
        else
            cf = ((speed_m_s - 3.0_dp) / 9.0_dp)**3
        end if
    end function wind_capacity_factor

    subroutine set_frequency_standard(st, nominal_hz)
        type(GridState), intent(inout) :: st
        real(dp), intent(in) :: nominal_hz

        st%nominal_frequency_Hz = nominal_hz
        st%frequency_Hz = nominal_hz
        st%UFLS_stage = 0
        st%UFLS_shed_fraction = 0.0_dp
        if (nominal_hz >= 59.0_dp) then
            st%ufls_thresh_1_Hz = 59.3_dp
            st%ufls_thresh_2_Hz = 58.9_dp
            st%ufls_thresh_3_Hz = 58.5_dp
            st%ufls_reset_Hz = 59.7_dp
            st%lfsm_o_thresh_Hz = 60.2_dp
        else
            st%ufls_thresh_1_Hz = UFLS_THRESH_1
            st%ufls_thresh_2_Hz = UFLS_THRESH_2
            st%ufls_thresh_3_Hz = UFLS_THRESH_3
            st%ufls_reset_Hz = UFLS_RESET
            st%lfsm_o_thresh_Hz = LFSM_O_THRESH_HZ
        end if
    end subroutine set_frequency_standard

    pure function market_hour_from_clock(st) result(hour)
        type(GridState), intent(in) :: st
        real(dp) :: hour, day_s

        day_s = max(1.0_dp, st%market_replay_day_s)
        hour = modulo(st%elapsed_s, day_s) / day_s * 24.0_dp
    end function market_hour_from_clock

    pure function daylight_shape(hour) result(shape)
        real(dp), intent(in) :: hour
        real(dp) :: shape

        if (hour <= 5.5_dp .or. hour >= 20.5_dp) then
            shape = 0.0_dp
        else
            shape = sin(PI_DP * (hour - 5.5_dp) / 15.0_dp)
            shape = max(0.0_dp, shape)**1.35_dp
        end if
    end function daylight_shape

    pure function demand_shape(hour) result(shape)
        real(dp), intent(in) :: hour
        real(dp) :: shape, morning, evening

        morning = exp(-((hour - 8.0_dp) / 3.4_dp)**2)
        evening = exp(-((hour - 18.5_dp) / 4.2_dp)**2)
        shape = 0.16_dp + 0.34_dp * morning + 0.50_dp * evening
        shape = clamp_real(shape, 0.0_dp, 1.0_dp)
    end function demand_shape

end module market_data
