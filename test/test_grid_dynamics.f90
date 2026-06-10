!> @file test_grid_dynamics.f90
!> @brief Tests the grid frequency dynamics: swing equation, governor droop
!>        clamping, BESS primary response, UFLS latching, and LFSM-O.
program test_grid_dynamics
    use precision_kinds, only: dp
    use engine_state
    use grid_dynamics, only: tick_frequency_dynamics
    implicit none
    integer :: failures
    real(dp), parameter :: DT = 0.25_dp
    failures = 0

    ! --- Balanced system stays at nominal frequency. ---
    block
        type(GridState) :: st
        st%demand_MW = 35.0_dp
        st%renewable_MW = 12.0_dp
        st%gas_power_MW = 23.0_dp
        st%gas_capacity_MW = 29.0_dp
        st%storage_MW = 0.0_dp
        st%frequency_Hz = 50.0_dp
        call tick_frequency_dynamics(st, DT)
        call expect_near("balanced: ROCOF is zero", st%ROCOF_Hz_s, 0.0_dp, 1.0e-9_dp, failures)
        call expect_near("balanced: frequency holds 50 Hz", st%frequency_Hz, 50.0_dp, 1.0e-9_dp, failures)
    end block

    ! --- 5 MW shortage with no primary headroom: df/dt = -P/M exactly. ---
    block
        type(GridState) :: st
        st%demand_MW = 35.0_dp
        st%renewable_MW = 7.0_dp
        st%gas_power_MW = 23.0_dp
        st%gas_capacity_MW = 23.0_dp      ! governor has zero upward headroom
        st%gas_dispatch_pct = 100.0_dp
        st%storage_MW = 0.0_dp
        st%frequency_Hz = 50.0_dp          ! delta_f = 0 -> primary inactive this tick
        call tick_frequency_dynamics(st, DT)
        call expect_near("shortage: ROCOF = -P/M", st%ROCOF_Hz_s, -5.0_dp / INERTIA_MWs, 1.0e-9_dp, failures)
        call expect_near("shortage: freq integrates one step", st%frequency_Hz, &
            50.0_dp - 5.0_dp / INERTIA_MWs * DT, 1.0e-9_dp, failures)
    end block

    ! --- Governor droop output is clamped to spinning headroom. ---
    block
        type(GridState) :: st
        st%demand_MW = 35.0_dp
        st%renewable_MW = 12.0_dp
        st%gas_power_MW = 23.0_dp
        st%gas_capacity_MW = 29.0_dp       ! 6 MW headroom
        st%frequency_Hz = 49.0_dp          ! raw droop demand = 0.4 * 29 = 11.6 MW
        st%battery_energy_MWh = 0.0_dp     ! silence BESS primary for clarity
        call tick_frequency_dynamics(st, DT)
        call expect_near("governor clamps to headroom", st%governor_delta_MW, 6.0_dp, 1.0e-9_dp, failures)
    end block

    ! --- BESS primary: discharges below nominal, blocked when empty. ---
    block
        type(GridState) :: st
        st%demand_MW = 30.0_dp
        st%renewable_MW = 0.0_dp
        st%gas_power_MW = 30.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%frequency_Hz = 49.5_dp
        st%battery_energy_MWh = 15.0_dp
        call tick_frequency_dynamics(st, DT)
        call expect_near("BESS primary discharges on underfrequency", &
            st%BESS_primary_MW, 0.5_dp * BESS_PRIMARY_GAIN, 1.0e-9_dp, failures)

        st%frequency_Hz = 49.5_dp
        st%battery_energy_MWh = 0.0_dp
        call tick_frequency_dynamics(st, DT)
        call expect_near("BESS primary blocked when battery empty", &
            st%BESS_primary_MW, 0.0_dp, 1.0e-9_dp, failures)
    end block

    ! --- UFLS stages latch and only reset above 49.5 Hz. ---
    block
        type(GridState) :: st
        st%demand_MW = 35.0_dp
        st%renewable_MW = 0.0_dp
        st%gas_power_MW = 35.0_dp
        st%gas_capacity_MW = 40.0_dp
        st%battery_energy_MWh = 0.0_dp

        st%frequency_Hz = 48.9_dp
        call tick_frequency_dynamics(st, DT)
        call expect_true("UFLS stage 1 trips below 49.0 Hz", st%UFLS_stage == 1, failures)
        call expect_near("UFLS stage 1 sheds 10%", st%UFLS_shed_fraction, UFLS_SHED_PCT, 1.0e-12_dp, failures)

        st%frequency_Hz = 49.2_dp          ! recovered, but below the 49.5 reset
        call tick_frequency_dynamics(st, DT)
        call expect_true("UFLS stage latches until reset", st%UFLS_stage == 1, failures)

        st%frequency_Hz = 49.6_dp          ! above reset threshold
        call tick_frequency_dynamics(st, DT)
        call expect_true("UFLS resets above 49.5 Hz", st%UFLS_stage == 0, failures)

        st%frequency_Hz = 48.3_dp          ! deep event jumps straight to stage 3
        call tick_frequency_dynamics(st, DT)
        call expect_true("deep underfrequency arms stage 3", st%UFLS_stage == 3, failures)
        call expect_near("stage 3 sheds 30%", st%UFLS_shed_fraction, 3.0_dp * UFLS_SHED_PCT, 1.0e-12_dp, failures)
    end block

    ! --- LFSM-O sheds renewables proportionally above 50.2 Hz. ---
    block
        type(GridState) :: st
        st%demand_MW = 20.0_dp
        st%renewable_MW = 20.0_dp
        st%renewable_curtail_MW = 0.0_dp
        st%gas_power_MW = 0.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%gas_dispatch_pct = GAS_MIN_PCT
        st%battery_energy_MWh = 0.0_dp
        st%frequency_Hz = 50.7_dp          ! 0.5 Hz above LFSM-O threshold
        call tick_frequency_dynamics(st, DT)
        call expect_near("LFSM-O sheds with 5% droop", st%renewable_lfsmo_MW, &
            20.0_dp * (0.5_dp / FREQ_NOMINAL_HZ) / LFSM_O_DROOP, 1.0e-9_dp, failures)

        st%frequency_Hz = 50.1_dp          ! inside the dead zone
        call tick_frequency_dynamics(st, DT)
        call expect_near("LFSM-O inactive below threshold", st%renewable_lfsmo_MW, 0.0_dp, 1.0e-12_dp, failures)
    end block

    ! --- Alarm flags follow the state. ---
    block
        type(GridState) :: st
        st%frequency_Hz = 49.3_dp
        st%reserve_MW = 1.0_dp
        st%battery_soc_pct = 10.0_dp
        st%gas_dispatch_pct = 100.0_dp
        st%gas_power_MW = 30.0_dp
        st%gas_capacity_MW = 30.0_dp
        st%demand_MW = 30.0_dp
        st%renewable_MW = 0.0_dp
        st%battery_energy_MWh = 0.0_dp
        call tick_frequency_dynamics(st, 0.001_dp)
        call expect_true("underfrequency alarm raises", st%alarm_underfreq, failures)
        call expect_true("low reserve alarm raises", st%alarm_low_reserve, failures)
        call expect_true("low SOC alarm raises", st%alarm_low_soc, failures)
        call expect_true("turbine max alarm raises", st%alarm_turbine_max, failures)
    end block

    call finish("grid_dynamics", failures)

contains

    include "test_assert.inc"

end program test_grid_dynamics
