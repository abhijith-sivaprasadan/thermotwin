!> @file cycle_solver.f90
!> @brief Top-level Brayton-cycle solver. Assembles the component models into a
!>        complete station-by-station solution and computes plant KPIs.
!>
!> Station numbering (simple/open cycle):
!>   1 : compressor inlet      2 : compressor outlet
!>   3 : turbine inlet         4 : turbine outlet (exhaust)
!>
!> Mass-flow bookkeeping: the compressor passes mdot_air; the turbine passes
!> mdot_gas = mdot_air*(1+f). Heat input for efficiency/heat-rate is the fuel
!> chemical energy mdot_fuel*LHV.
module cycle_solver
    use precision_kinds, only: dp
    use constants, only: W_PER_MW, SECONDS_PER_HOUR, T_REF_ISO_K, TINY_DP
    use types, only: InputCase, CycleResult
    use ambient, only: inlet_state
    use compressor, only: solve_compressor
    use combustor, only: solve_combustor
    use turbine, only: solve_turbine
    use shaft_generator, only: solve_shaft_generator
    use fluid_properties, only: cp_gas_at
    use utilities, only: safe_divide
    implicit none
    private
    public :: solve_cycle

contains

    !> Evaluate one operating point. Pure-ish: no I/O, only fills `res`.
    function solve_cycle(ic) result(res)
        type(InputCase), intent(in) :: ic
        type(CycleResult) :: res

        real(dp) :: T1, P1, T2, P2, w_c
        real(dp) :: P3, f, q_in_air
        real(dp) :: T4, w_t, P4
        real(dp) :: mdot_air, mdot_gas, mdot_fuel
        real(dp) :: power_comp_W, power_turb_W
        real(dp) :: gross_W, net_W
        real(dp) :: Q_fuel_W, cp_exh

        res%case_name        = ic%case_name
        res%degradation_mode = ic%degradation_mode

        ! ---- Station 1: inlet -------------------------------------------------
        call inlet_state(ic, T1, P1)

        ! ---- Station 2: compressor -------------------------------------------
        call solve_compressor(T1, P1, ic%pressure_ratio, ic%eta_compressor, &
                              T2, P2, w_c)

        ! ---- Station 3: combustor --------------------------------------------
        call solve_combustor(T2, P2, ic%T_turbine_inlet_K, ic%eta_combustor, &
                            ic%combustor_pressure_loss, ic%LHV_J_kg, &
                            P3, f, q_in_air)

        ! ---- Station 4: turbine ----------------------------------------------
        ! Exhaust pressure = ambient raised by exhaust/diffuser back-pressure loss.
        P4 = ic%ambient_P_Pa * (1.0_dp + ic%exhaust_pressure_loss)
        call solve_turbine(ic%T_turbine_inlet_K, P3, P4, ic%eta_turbine, T4, w_t)

        ! ---- Mass flows -------------------------------------------------------
        mdot_air  = ic%mdot_air_kg_s
        mdot_fuel = mdot_air * f
        mdot_gas  = mdot_air + mdot_fuel

        ! ---- Powers (W) -------------------------------------------------------
        power_comp_W = mdot_air * w_c            ! compressor pumps air only
        power_turb_W = mdot_gas * w_t            ! turbine expands air + fuel
        call solve_shaft_generator(power_turb_W, power_comp_W, &
                                  ic%eta_mechanical, ic%eta_generator, &
                                  ic%auxiliary_load_fraction, gross_W, net_W)

        ! ---- Heat input & efficiency -----------------------------------------
        Q_fuel_W = mdot_fuel * ic%LHV_J_kg       ! fuel chemical energy rate

        ! ---- Exhaust sensible energy above ISO reference ---------------------
        cp_exh = cp_gas_at(0.5_dp*(T4 + T_REF_ISO_K))

        ! ---- Pack results -----------------------------------------------------
        res%T1_K = T1;  res%P1_Pa = P1
        res%T2_K = T2;  res%P2_Pa = P2
        res%T3_K = ic%T_turbine_inlet_K; res%P3_Pa = P3
        res%T4_K = T4;  res%P4_Pa = P4

        res%w_compressor_J_kg   = w_c
        res%w_turbine_J_kg      = w_t
        res%w_net_specific_J_kg = w_t - w_c
        res%fuel_air_ratio      = f
        res%fuel_flow_kg_s      = mdot_fuel
        res%mdot_air_kg_s       = mdot_air
        res%mdot_gas_kg_s       = mdot_gas

        res%power_compressor_MW = power_comp_W / W_PER_MW
        res%power_turbine_MW    = power_turb_W / W_PER_MW
        res%gross_power_MW      = gross_W / W_PER_MW
        res%net_power_MW        = net_W / W_PER_MW
        res%heat_input_MW       = Q_fuel_W / W_PER_MW

        res%thermal_efficiency  = safe_divide(net_W, Q_fuel_W)
        ! Heat rate [kJ/kWh] = 3600 [kJ/kWh per unit efficiency] / eta.
        if (res%thermal_efficiency > TINY_DP) then
            res%heat_rate_kJ_kWh = SECONDS_PER_HOUR / res%thermal_efficiency
        else
            res%heat_rate_kJ_kWh = huge(1.0_dp)
        end if

        res%exhaust_temperature_K = T4
        res%exhaust_energy_MW     = mdot_gas * cp_exh * (T4 - T_REF_ISO_K) / W_PER_MW
        res%specific_power_kW_per_kgps = safe_divide(net_W, mdot_air) / 1000.0_dp

        ! ---- Basic physical sanity flags -------------------------------------
        res%converged = .true.
        res%status_message = "ok"
        if (T2 <= T1) then
            res%converged = .false.; res%status_message = "compressor outlet <= inlet"
        else if (T4 <= ic%ambient_T_K) then
            res%converged = .false.; res%status_message = "exhaust <= ambient (unphysical)"
        else if (res%net_power_MW <= 0.0_dp) then
            res%converged = .false.; res%status_message = "non-positive net power"
        else if (f <= 0.0_dp) then
            res%converged = .false.; res%status_message = "non-positive fuel-air ratio"
        end if
    end function solve_cycle

end module cycle_solver
