!> @file site_performance.f90
!> @brief ISO-to-site full-load performance ratios at fixed machine hardware.
!>
!> A transparent educational correction method, NOT an OEM guarantee model
!> and NOT compliance with ISO 3977 / ASME PTC 22. The reference calibration
!> is taken once from the supplied ISO hardware case, never from the site.
module site_performance
    use precision_kinds, only: dp
    use types, only: InputCase
    use off_design, only: OffDesignPoint, solve_off_design
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    implicit none
    private
    public :: SiteCorrection, evaluate_site

    type :: SiteCorrection
        type(OffDesignPoint) :: reference, installed
        real(dp) :: power_derate_ratio = 0.0_dp
        real(dp) :: power_correction_ref_per_site = 0.0_dp
        real(dp) :: heat_rate_correction_ref_per_site = 0.0_dp
        real(dp) :: exhaust_flow_correction_ref_per_site = 0.0_dp
        real(dp) :: exhaust_T_additive_ref_minus_site_K = 0.0_dp
        logical :: valid = .false.
        character(len=160) :: status = "not evaluated"
    end type SiteCorrection

contains

    !> Reference conditions are fixed at ISO day with explicitly modelled
    !> lumped inlet/exhaust losses. Off-design full-load capacity is evaluated
    !> on each day with the SAME choked-turbine hardware calibration.
    !> Humidity and detailed fuel chemistry are not correction variables.
    function evaluate_site(reference_machine, installed_conditions) result(c)
        type(InputCase), intent(in) :: reference_machine, installed_conditions
        type(SiteCorrection) :: c

        c%status = "invalid input or unsupported correction"
        if (.not. ieee_is_finite(reference_machine%ambient_T_K) .or. &
            .not. ieee_is_finite(reference_machine%ambient_P_Pa) .or. &
            .not. ieee_is_finite(installed_conditions%ambient_T_K) .or. &
            .not. ieee_is_finite(installed_conditions%ambient_P_Pa)) return

        if (abs(reference_machine%ambient_T_K - 288.15_dp) > 1.0e-6_dp .or. &
            abs(reference_machine%ambient_P_Pa - 101325.0_dp) > 1.0e-4_dp) then
            c%status = "reference case must specify 288.15 K and 101325 Pa ISO ambient"
            return
        end if
        if (installed_conditions%ambient_T_K < 250.0_dp .or. &
            installed_conditions%ambient_T_K > 325.0_dp .or. &
            installed_conditions%ambient_P_Pa < 75000.0_dp .or. &
            installed_conditions%ambient_P_Pa > 110000.0_dp) then
            c%status = "outside illustrative site T/P model envelope"
            return
        end if

        if (.not. near(reference_machine%relative_humidity, 0.60_dp) .or. &
            .not. near(installed_conditions%relative_humidity, &
                       reference_machine%relative_humidity)) then
            c%status = "humidity correction unsupported; keep RH=0.60 reference assumption"
            return
        end if

        if (.not. same_hardware(reference_machine, installed_conditions)) then
            c%status = "site row changes fixed compressor/turbine/shaft hardware or firing control"
            return
        end if
        if (trim(reference_machine%degradation_mode) /= "clean" .or. &
            trim(installed_conditions%degradation_mode) /= "clean") then
            c%status = "site correction v0.1 requires clean undegraded machine"
            return
        end if

        if (.not. ieee_is_finite(installed_conditions%inlet_pressure_loss) .or. &
            .not. ieee_is_finite(installed_conditions%exhaust_pressure_loss) .or. &
            .not. ieee_is_finite(installed_conditions%LHV_J_kg)) return
        if (installed_conditions%inlet_pressure_loss < 0.0_dp .or. &
            installed_conditions%inlet_pressure_loss > 0.20_dp .or. &
            installed_conditions%exhaust_pressure_loss < 0.0_dp .or. &
            installed_conditions%exhaust_pressure_loss > 0.20_dp .or. &
            installed_conditions%LHV_J_kg < 35.0e6_dp .or. &
            installed_conditions%LHV_J_kg > 60.0e6_dp) then
            c%status = "site loss/LHV out of declared illustrative envelope"
            return
        end if

        call solve_off_design(reference_machine, 1.0_dp, 0.0_dp, &
                              c%reference, reference_machine)
        call solve_off_design(installed_conditions, 1.0_dp, 0.0_dp, &
                              c%installed, reference_machine)

        if (.not. c%reference%cyc%converged .or. &
            .not. c%installed%cyc%converged) then
            c%status = "reference or site cycle solver reported invalid result"
            return
        end if
        if (.not. valid_kpi(c%reference) .or. &
            .not. valid_kpi(c%installed)) then
            c%status = "reference or site cycle KPI is nonfinite/nonpositive"
            return
        end if

        c%power_derate_ratio = c%installed%cyc%net_power_MW / &
                              c%reference%cyc%net_power_MW
        c%power_correction_ref_per_site = 1.0_dp / c%power_derate_ratio
        c%heat_rate_correction_ref_per_site = &
            c%reference%cyc%heat_rate_kJ_kWh / c%installed%cyc%heat_rate_kJ_kWh
        c%exhaust_flow_correction_ref_per_site = &
            c%reference%cyc%mdot_gas_kg_s / c%installed%cyc%mdot_gas_kg_s
        c%exhaust_T_additive_ref_minus_site_K = &
            c%reference%cyc%exhaust_temperature_K - &
            c%installed%cyc%exhaust_temperature_K
        c%valid = .true.
        c%status = "ok; illustrative dry-air model, not OEM validated"
    end function evaluate_site

    pure logical function near(a,b)
        real(dp), intent(in) :: a,b
        near = ieee_is_finite(a) .and. ieee_is_finite(b)
        if (near) near = abs(a-b) <= 1.0e-9_dp*max(1.0_dp,abs(a),abs(b))
    end function near

    pure logical function same_hardware(a,b)
        type(InputCase), intent(in) :: a,b
        same_hardware = &
          near(a%mdot_air_kg_s,b%mdot_air_kg_s) .and. &
          near(a%pressure_ratio,b%pressure_ratio) .and. &
          near(a%eta_compressor,b%eta_compressor) .and. &
          near(a%T_turbine_inlet_K,b%T_turbine_inlet_K) .and. &
          near(a%eta_combustor,b%eta_combustor) .and. &
          near(a%combustor_pressure_loss,b%combustor_pressure_loss) .and. &
          near(a%eta_turbine,b%eta_turbine) .and. &
          near(a%eta_mechanical,b%eta_mechanical) .and. &
          near(a%eta_generator,b%eta_generator) .and. &
          near(a%auxiliary_load_fraction,b%auxiliary_load_fraction)
    end function same_hardware

    pure logical function valid_kpi(od)
        type(OffDesignPoint), intent(in) :: od
        valid_kpi = &
            ieee_is_finite(od%cyc%net_power_MW) .and. &
            ieee_is_finite(od%cyc%heat_rate_kJ_kWh) .and. &
            ieee_is_finite(od%cyc%mdot_gas_kg_s) .and. &
            ieee_is_finite(od%cyc%exhaust_temperature_K)
        if (valid_kpi) then
            valid_kpi = od%cyc%net_power_MW > 0.0_dp .and. &
                od%cyc%heat_rate_kJ_kWh > 0.0_dp .and. &
                od%cyc%mdot_gas_kg_s > 0.0_dp
        end if
    end function valid_kpi
end module site_performance
