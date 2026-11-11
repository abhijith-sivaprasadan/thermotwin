!> Cross-module energy accounting tests for issue #47.
!> Numerical conservation/causality only: no measured or OEM validation.
program test_grid_primary_energy
    use precision_kinds, only: dp
    use engine_state
    use engine_core, only: engine_init, engine_step, update_battery_soc
    use grid_primary_balance, only: tick_governor_setpoint, resolve_bess_injection
    use grid_dynamics, only: tick_frequency_dynamics
    use gfm_bess, only: gfm_step
    implicit none
    type(GridState) :: st, one, many, qt
    real(dp) :: p0, fuel0, energy0, expected, storage0, req0
    integer :: failures, i
    failures=0

    ! A frequency-responsive governor must change the off-design turbine
    ! solution, not inject anonymous additional MW into the swing equation.
    call engine_init(st)
    st%auto_balance=.false.
    st%fcr_hold=.false.
    st%frequency_Hz=50.0_dp
    st%storage_request_MW=0.0_dp
    p0=st%gas_power_MW
    fuel0=st%fuel_flow_kg_s
    energy0=st%battery_energy_MWh
    st%frequency_Hz=49.8_dp  ! below MANUAL BESS step deadband, above FCR deadband
    call engine_step(st,0.25_dp)
    call check("governor raises actual off-design turbine MW",st%gas_power_MW>p0)
    call check("governor also raises solved fuel flow",st%fuel_flow_kg_s>fuel0)
    call check("governor MW is diagnostic, not extra grid injection",st%governor_delta_MW>0.0_dp)
    call check_close("governor dispatch request is physically bounded", &
         st%effective_gas_dispatch_pct,st%gas_dispatch_pct+st%governor_offset_pct,1.0e-8_dp)
    call check_close("one net MW supply includes both GT and BESS only once", &
        st%supply_MW,thermal_generation_MW(st)+ &
        max(0.0_dp,effective_renewable_MW(st)-st%renewable_lfsmo_MW)+st%storage_MW,1.0e-8_dp)
    call check_close("one imbalance equals supply less served demand", &
        st%imbalance_MW,st%supply_MW-st%served_demand_MW,1.0e-8_dp)
    call check("frequency response supplies actual positive BESS MW",st%BESS_primary_MW>0.0_dp)
    call check_close("base zero BESS request means net power equals FCR contribution", &
        st%storage_MW,st%BESS_primary_MW,1.0e-8_dp)
    expected=energy0-st%storage_MW*0.25_dp/(3600.0_dp*BATTERY_EFFICIENCY)
    call check_close("all BESS primary energy charged to SOC",st%battery_energy_MWh,expected,1.0e-10_dp)

    ! Power is shared by base dispatch, conventional FCR and GFM: no two
    ! independent inverter outputs, no accumulated GFM offset.
    qt=GridState()
    qt%storage_request_MW=STORAGE_MAX_MW-0.1_dp
    qt%frequency_Hz=49.0_dp
    qt%gas_capacity_MW=30.0_dp
    qt%gfm_mode=.true.
    qt%gfm_virtual_H=4.0_dp
    qt%gfm_droop_pct=5.0_dp
    req0=qt%storage_request_MW
    call gfm_step(qt,0.25_dp)
    call gfm_step(qt,0.25_dp)
    call check_close("GFM calls cannot accumulate into baseline request",qt%storage_request_MW,req0,1.0e-12_dp)
    call resolve_bess_injection(qt,0.25_dp)
    call check("combined BESS response cannot exceed inverter rating", &
        qt%storage_MW<=STORAGE_MAX_MW+1.0e-9_dp)
    call check_close("saturated BESS cannot create extra primary power", &
        qt%storage_MW,STORAGE_MAX_MW,1.0e-9_dp)
    call check_close("GFM actually delivered equals post-arbitration remainder", &
        qt%gfm_synth_MW,0.0_dp,1.0e-8_dp)

    ! When energy would be exhausted part-way through a timestep, the
    ! delivered power is limited BEFORE integration, not clipped afterward.
    qt=GridState()
    qt%battery_energy_MWh=0.05_dp
    qt%battery_soc_pct=100.0_dp*qt%battery_energy_MWh/BATTERY_CAPACITY_MWH
    qt%storage_request_MW=10.0_dp
    qt%frequency_Hz=50.0_dp
    call resolve_bess_injection(qt,3600.0_dp)
    expected=0.05_dp*BATTERY_EFFICIENCY
    call check_close("energy-limited one-hour discharge MW",qt%storage_MW,expected,1.0e-9_dp)
    call update_battery_soc(qt,3600.0_dp)
    call check_close("energy-limited discharge reaches zero without hidden energy", &
        qt%battery_energy_MWh,0.0_dp,1.0e-9_dp)

    qt=GridState()
    qt%battery_energy_MWh=BATTERY_CAPACITY_MWH-0.05_dp
    qt%storage_request_MW=-10.0_dp
    call resolve_bess_injection(qt,3600.0_dp)
    expected=-0.05_dp/BATTERY_EFFICIENCY
    call check_close("energy-limited one-hour charge MW",qt%storage_MW,expected,1.0e-9_dp)
    call update_battery_soc(qt,3600.0_dp)
    call check_close("energy-limited charge reaches cap without hidden energy", &
        qt%battery_energy_MWh,BATTERY_CAPACITY_MWH,1.0e-9_dp)

    ! Fixed 1-s BESS energy transfer is dt-invariant at 1x1s vs 4x0.25s.
    one=GridState()
    many=one
    one%frequency_Hz=50.0_dp
    many%frequency_Hz=50.0_dp
    one%storage_request_MW=10.0_dp
    many%storage_request_MW=10.0_dp
    call resolve_bess_injection(one,1.0_dp)
    call update_battery_soc(one,1.0_dp)
    do i=1,4
        call resolve_bess_injection(many,0.25_dp)
        call update_battery_soc(many,0.25_dp)
    end do
    call check_close("MWh time-step subdivision consistency", &
        one%battery_energy_MWh,many%battery_energy_MWh,1.0e-10_dp)

    ! No governor output should exist after a trip.
    qt=GridState()
    qt%gt_phase=GT_TRIPPED
    qt%gas_capacity_MW=30.0_dp
    qt%frequency_Hz=49.0_dp
    call tick_governor_setpoint(qt,0.25_dp)
    call check_close("tripped governor cannot add dispatch",qt%effective_gas_dispatch_pct,0.0_dp,1.0e-10_dp)
    call check_close("tripped governor reports zero electrical support",qt%governor_delta_MW,0.0_dp,1.0e-10_dp)

    ! UFLS and LFSM-O affect the same reported imbalance as the swing RHS.
    qt=GridState()
    qt%gt_phase=GT_TRIPPED
    qt%gas_power_MW=0.0_dp
    qt%demand_MW=30.0_dp
    qt%renewable_MW=10.0_dp
    qt%storage_MW=5.0_dp
    qt%frequency_Hz=48.3_dp
    call tick_frequency_dynamics(qt,0.25_dp)
    call check("deep UFLS trip reaches stage 3",qt%UFLS_stage==3)
    call check_close("UFLS served MW reconciled",qt%served_demand_MW,21.0_dp,1.0e-9_dp)
    call check_close("UFLS net power mismatch reported accurately",qt%imbalance_MW,-6.0_dp,1.0e-9_dp)
    call check_close("swing ROCOF uses that SAME mismatch",qt%ROCOF_Hz_s, &
        qt%imbalance_MW/INERTIA_MWs,1.0e-9_dp)

    qt=GridState()
    qt%gt_phase=GT_TRIPPED
    qt%gas_power_MW=0.0_dp
    qt%demand_MW=20.0_dp
    qt%renewable_MW=20.0_dp
    qt%frequency_Hz=50.7_dp
    call tick_frequency_dynamics(qt,0.25_dp)
    call check("LFSM-O active above deadband",qt%renewable_lfsmo_MW>0.0_dp)
    call check_close("LFSM-O physically subtracts generated renewable MW", &
        qt%supply_MW,20.0_dp-qt%renewable_lfsmo_MW,1.0e-9_dp)
    call check_close("LFSM-O appears in published imbalance and swing", &
        qt%imbalance_MW,-qt%renewable_lfsmo_MW,1.0e-9_dp)

    if(failures/=0) then
        print '(A,I0)', "FAIL grid primary energy reconciliation: ", failures
        stop 1
    end if
    print '(A)',"PASS governor/FCR/GFM actual MW, MWh, UFLS and LFSM-O balances"
contains
    subroutine check(label,ok)
        character(len=*),intent(in) :: label
        logical,intent(in) :: ok
        if(.not.ok) then
            failures=failures+1
            print '(A,A)',"FAIL: ",label
        end if
    end subroutine check
    subroutine check_close(label,a,b,tol)
        character(len=*),intent(in) :: label
        real(dp),intent(in) :: a,b,tol
        call check(label,abs(a-b)<=tol)
    end subroutine check_close
end program test_grid_primary_energy
