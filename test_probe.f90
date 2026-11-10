program probe
    use precision_kinds, only: dp
    use types, only: InputCase
    use fluid_properties, only: set_property_model, PROP_VARIABLE
    use off_design, only: OffDesignPoint, solve_off_design
    use engine_core
    implicit none
    type(InputCase) :: base
    type(OffDesignPoint) :: od
    type(GridState) :: st

    call set_property_model(PROP_VARIABLE)
    base%case_name = "probe"
    call solve_off_design(base, 1.0_dp, 0.0_dp, od)
    print *, "off_design full load net_power_MW =", od%cyc%net_power_MW

    call engine_init(st)
    st%combined_cycle = .true.
    st%gas_dispatch_pct = 100.0_dp
    st%demand_MW = 50.0_dp
    call refresh_model(st)
    print *, "CC plant_efficiency =", st%plant_efficiency
    print *, "CC gas_power_MW =", st%gas_power_MW
    print *, "CC steam_power_MW =", st%steam_power_MW
    print *, "CC plant_power_MW =", st%plant_power_MW
end program probe
