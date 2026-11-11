!> Independent dimensioned grid inertia and analytic horizon tests.
program test_grid_frequency_physics
    use precision_kinds, only: dp
    use engine_state
    use grid_frequency_physics
    use grid_dynamics, only: tick_frequency_dynamics
    implicit none
    integer :: failures,i
    type(GridState) :: st, slow, fast, invalid
    real(dp) :: e, m, predicted, expected, error_slow, error_fast, tau, exact_f
    logical :: valid
    failures=0

    st=GridState()
    e=grid_stored_energy_MWs(st)
    m=grid_swing_MW_s_per_Hz(st)
    call check_close("rotational stored energy sums H*S in MW*s",e,625.0_dp,1.0e-10_dp)
    call check_close("M=2E/f0, dimensional MW*s/Hz",m,25.0_dp,1.0e-10_dp)
    st%nominal_frequency_Hz=60.0_dp
    call check_close("same rotor energy at 60Hz changes swing coefficient", &
        grid_swing_MW_s_per_Hz(st),2.0_dp*625.0_dp/60.0_dp,1.0e-10_dp)

    st=GridState()
    st%gt_phase=GT_TRIPPED
    st%gt_breaker_closed=.false.
    call check_close("tripped unit kinetic energy immediately removed", &
        grid_stored_energy_MWs(st),525.0_dp,1.0e-10_dp)
    st%fleet_mode=.true.
    st%fleet_unit_online=[.true.,.true.,.true.]
    call check_close("fleet adds only online rotating kinetic stores", &
        grid_stored_energy_MWs(st),627.0_dp,1.0e-10_dp)
    st%fleet_unit_online(FLEET_CC1)=.false.
    call check_close("CC1 loss removes its modelled 70 MW*s stored energy", &
        grid_stored_energy_MWs(st),557.0_dp,1.0e-10_dp)

    st=GridState()
    st%demand_MW=30.0_dp
    st%frequency_Hz=49.0_dp
    call refresh_frequency_sensitive_demand(st)
    call check_close("UFLS-free static served load",st%static_served_demand_MW,30.0_dp,1.0e-12_dp)
    call check_close("underfrequency reduces actual demand by D*df", &
        st%grid_damping_load_MW,-0.5_dp,1.0e-12_dp)
    call check_close("negative damping load still conserves net MW", &
        st%served_demand_MW,29.5_dp,1.0e-12_dp)
    st%UFLS_shed_fraction=0.3_dp
    call refresh_frequency_sensitive_demand(st)
    call check_close("UFLS static served load",st%static_served_demand_MW,21.0_dp,1.0e-12_dp)
    call check_close("UFLS remains separate from frequency damping", &
        st%ufls_shed_MW,9.0_dp,1.0e-12_dp)

    st=GridState()
    st%frequency_Hz=50.0_dp
    st%imbalance_MW=0.0_dp
    st%grid_damping_load_MW=0.0_dp
    call grid_fixed_loss_horizon_min(st,10.0_dp,5.0_dp,predicted,valid)
    expected=50.0_dp-10.0_dp/st%grid_damping_MW_per_Hz* &
        (1.0_dp-exp(-st%grid_damping_MW_per_Hz*5.0_dp/25.0_dp))
    call check("5-second fixed-deficit horizon in bounded simulator domain",valid)
    call check_close("forecast independently solved first-order closed form",predicted,expected,1.0e-10_dp)
    st%grid_damping_MW_per_Hz=0.0_dp
    call grid_fixed_loss_horizon_min(st,10.0_dp,5.0_dp,predicted,valid)
    call check_close("zero-damping limit is straight inertial slope", &
        predicted,48.0_dp,1.0e-10_dp)
    call grid_fixed_loss_horizon_min(st,100.0_dp,5.0_dp,predicted,valid)
    call check("out-of-range projection reported invalid, not concealed by clipping", &
        .not.valid .and. predicted<47.0_dp)

    ! Reduced-order isolated step, no feedback. Compare explicit numerical
    ! model against an analytic first-order solution at two resolutions.
    slow=GridState()
    slow%gas_power_MW=28.0_dp
    slow%demand_MW=30.0_dp
    slow%renewable_MW=0.0_dp
    slow%storage_MW=0.0_dp
    fast=slow
    do i=1,4
        call tick_frequency_dynamics(slow,0.5_dp)
    end do
    do i=1,20
        call tick_frequency_dynamics(fast,0.1_dp)
    end do
    tau=2.0_dp
    exact_f=50.0_dp-2.0_dp/GRID_DEFAULT_DAMPING_MW_PER_HZ* &
        (1.0_dp-exp(-GRID_DEFAULT_DAMPING_MW_PER_HZ*tau/25.0_dp))
    error_slow=abs(slow%frequency_Hz-exact_f)
    error_fast=abs(fast%frequency_Hz-exact_f)
    call check("smaller timestep converges to independent exponential",error_fast<error_slow)
    call check("fine timestep is close to analytic",error_fast<0.0005_dp)
    call check_close("damping appears in actual MW imbalance", &
        fast%imbalance_MW,28.0_dp-fast%served_demand_MW,1.0e-10_dp)

    invalid=GridState()
    invalid%grid_external_inertia_H_s=-1.0_dp
    invalid%frequency_Hz=50.0_dp
    call tick_frequency_dynamics(invalid,0.25_dp)
    call check("negative inertia fails closed",.not.invalid%grid_model_valid)
    call check_close("invalid inertia cannot integrate a fabricated frequency",&
        invalid%frequency_Hz,50.0_dp,1.0e-12_dp)
    invalid=GridState()
    invalid%grid_damping_MW_per_Hz=-0.1_dp
    call tick_frequency_dynamics(invalid,0.25_dp)
    call check("negative damping fails closed",.not.invalid%grid_model_valid)
    invalid=GridState()
    invalid%nominal_frequency_Hz=0.0_dp
    call grid_fixed_loss_horizon_min(invalid,10.0_dp,5.0_dp,predicted,valid)
    call check("invalid reference frequency rejects horizon",.not.valid)
    invalid=GridState()
    call grid_fixed_loss_horizon_min(invalid,10.0_dp,0.0_dp,predicted,valid)
    call check("zero prediction horizon fails closed",.not.valid)

    if(failures>0) then
        print '(A,I0)',"FAIL dimensioned grid physics: ",failures
        stop 1
    end if
    print '(A)',"PASS dimensioned inertia, damping, analytic horizon, timestep convergence"
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
end program test_grid_frequency_physics
