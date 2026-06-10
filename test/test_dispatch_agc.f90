!> @file test_dispatch_agc.f90
!> @brief Tests the secondary AGC merit order: BESS discharge sign in a
!>        shortage, curtailment restore-before-dispatch, gas ramp limiting,
!>        surplus curtailment as last resort, and the one-shot balance.
program test_dispatch_agc
    use precision_kinds, only: dp
    use engine_state
    use dispatch_agc, only: tick_auto_balance, balance_now, reset_controls, &
        apply_turbine_trip, apply_load_step
    use engine_core, only: update_battery_soc
    implicit none
    integer :: failures
    real(dp), parameter :: DT = 0.25_dp
    failures = 0

    ! --- Shortage: BESS request ramps POSITIVE (discharge adds supply). ---
    block
        type(GridState) :: st
        st%auto_balance = .true.
        st%fcr_hold = .false.
        st%demand_MW = 50.0_dp
        st%renewable_MW = 10.0_dp
        st%renewable_curtail_MW = 0.0_dp
        st%gas_power_MW = 30.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%gas_dispatch_pct = 100.0_dp
        st%storage_request_MW = 0.0_dp
        st%battery_soc_pct = 50.0_dp
        st%battery_energy_MWh = 15.0_dp
        call tick_auto_balance(st, DT)
        call expect_true("shortage: BESS commanded to discharge", st%storage_request_MW > 0.0_dp, failures)
        call expect_near("shortage: BESS ramp-rate limited", st%storage_request_MW, &
            BESS_RAMP_MW_PER_S * DT, 1.0e-9_dp, failures)
    end block

    ! --- Shortage with curtailed renewables: free energy restored first. ---
    block
        type(GridState) :: st
        st%auto_balance = .true.
        st%fcr_hold = .false.
        st%demand_MW = 40.0_dp
        st%renewable_MW = 20.0_dp
        st%renewable_curtail_MW = 5.0_dp   ! 5 MW held back
        st%gas_power_MW = 20.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%gas_dispatch_pct = 66.7_dp
        st%storage_request_MW = 0.0_dp
        st%battery_soc_pct = 50.0_dp
        st%battery_energy_MWh = 15.0_dp
        call tick_auto_balance(st, DT)
        call expect_true("shortage: curtailment is restored first", &
            st%renewable_curtail_MW < 5.0_dp, failures)
        call expect_near("curtailment restore is inverter-ramp limited", st%renewable_curtail_MW, &
            5.0_dp - CURTAIL_RAMP_MW_PER_S * DT, 1.0e-9_dp, failures)
    end block

    ! --- Gas dispatch slews toward target at the published ramp rate. ---
    block
        type(GridState) :: st
        st%auto_balance = .true.
        st%fcr_hold = .false.
        st%demand_MW = 60.0_dp
        st%renewable_MW = 0.0_dp
        st%gas_power_MW = 15.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%gas_dispatch_pct = 50.0_dp
        st%storage_request_MW = 0.0_dp
        st%battery_soc_pct = 50.0_dp
        st%battery_energy_MWh = 15.0_dp
        call tick_auto_balance(st, DT)
        call expect_true("gas dispatch rises toward shortage target", &
            st%gas_dispatch_pct > 50.0_dp, failures)
        call expect_true("gas dispatch is ramp-rate limited", &
            st%gas_dispatch_pct <= 50.0_dp + GAS_RAMP_PCT_PER_S * DT + 1.0e-9_dp, failures)
    end block

    ! --- Deep surplus with gas at minimum: renewables get curtailed. ---
    block
        type(GridState) :: st
        st%auto_balance = .true.
        st%fcr_hold = .true.               ! FCR hold permits ROI-gated curtailment
        st%roi_dispatch = .true.
        st%demand_MW = 20.0_dp
        st%renewable_MW = 30.0_dp
        st%renewable_curtail_MW = 0.0_dp
        st%gas_power_MW = 6.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%gas_dispatch_pct = GAS_MIN_PCT
        st%storage_request_MW = 0.0_dp
        st%battery_soc_pct = 50.0_dp
        st%battery_energy_MWh = 15.0_dp
        call tick_auto_balance(st, DT)
        call expect_true("surplus: renewables are curtailed", st%renewable_curtail_MW > 0.0_dp, failures)
        call expect_true("surplus: BESS charges (negative request)", st%storage_request_MW < 0.0_dp, failures)
    end block

    ! --- One-shot balance lands the turbine on the balancing setpoint. ---
    block
        type(GridState) :: st
        real(dp) :: expected_pct
        st%demand_MW = 35.0_dp
        st%renewable_MW = 12.0_dp
        st%renewable_curtail_MW = 3.0_dp   ! must be dropped by the snap
        st%gas_power_MW = 23.0_dp
        st%gas_capacity_MW = 29.0_dp
        st%battery_soc_pct = 50.0_dp
        st%battery_energy_MWh = 15.0_dp
        st%storage_request_MW = 0.0_dp
        call balance_now(st)
        expected_pct = 100.0_dp * (35.0_dp - 12.0_dp) / 29.0_dp
        call expect_near("balance_now: gas setpoint balances the grid", &
            st%gas_dispatch_pct, expected_pct, 1.0e-9_dp, failures)
        call expect_near("balance_now: curtailment cleared", st%renewable_curtail_MW, 0.0_dp, 1.0e-12_dp, failures)
    end block

    ! --- Scenario events. ---
    block
        type(GridState) :: st
        real(dp) :: demand_before
        demand_before = st%demand_MW
        call apply_load_step(st)
        call expect_near("load step adds 10 MW", st%demand_MW, demand_before + 10.0_dp, 1.0e-12_dp, failures)

        st%storage_request_MW = 0.0_dp
        call apply_turbine_trip(st)
        call expect_near("turbine trip drops gas to minimum", st%gas_dispatch_pct, GAS_MIN_PCT, 1.0e-12_dp, failures)
        call expect_true("turbine trip calls on the battery", st%storage_request_MW > 0.0_dp, failures)
        call expect_true("turbine trip re-arms AUTO", st%auto_balance, failures)
    end block

    ! --- Battery SOC bookkeeping applies one-way efficiency. ---
    block
        type(GridState) :: st
        st%battery_energy_MWh = 15.0_dp
        st%storage_MW = 10.0_dp            ! discharging 10 MW for one hour
        call update_battery_soc(st, 3600.0_dp)
        call expect_near("discharge drains energy / efficiency", st%battery_energy_MWh, &
            15.0_dp - 10.0_dp / BATTERY_EFFICIENCY, 1.0e-6_dp, failures)

        st%battery_energy_MWh = 15.0_dp
        st%storage_MW = -10.0_dp           ! charging 10 MW for one hour
        call update_battery_soc(st, 3600.0_dp)
        call expect_near("charge stores energy * efficiency", st%battery_energy_MWh, &
            15.0_dp + 10.0_dp * BATTERY_EFFICIENCY, 1.0e-6_dp, failures)
    end block

    ! --- Reset restores the documented defaults. ---
    block
        type(GridState) :: st
        st%demand_MW = 90.0_dp
        st%frequency_Hz = 48.0_dp
        st%UFLS_stage = 3
        call reset_controls(st)
        call expect_near("reset: demand back to 35 MW", st%demand_MW, 35.0_dp, 1.0e-12_dp, failures)
        call expect_near("reset: frequency back to nominal", st%frequency_Hz, FREQ_NOMINAL_HZ, 1.0e-12_dp, failures)
        call expect_true("reset: UFLS disarmed", st%UFLS_stage == 0, failures)
        call expect_true("reset: AUTO re-armed", st%auto_balance, failures)
    end block

    call finish("dispatch_agc", failures)

contains

    include "test_assert.inc"

end program test_dispatch_agc
