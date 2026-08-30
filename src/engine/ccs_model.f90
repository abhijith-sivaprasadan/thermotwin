! =============================================================================
! ccs_model.f90  --  MEA post-combustion carbon capture for ThermoTwin-F
!
! Applies a simplified monoethanolamine (MEA) CO2 capture model to the
! combined-cycle exhaust stream.  Only executes when both ccs_active and
! combined_cycle are .true. and the plant is generating power.
!
! Physics summary
! ---------------
! 1. Fuel flow is derived from plant electrical output and the GT heat rate:
!
!      fuel_kg_s = P_el [kW] * HR [kJ/kWh] / (3600 [s/h] * LHV [kJ/kg])
!
!    with LHV_BLEND = 50 000 kJ/kg as the natural-gas baseline (the H2-blend
!    module updates st%h2_lhv_mj_kg but we use the fixed NG value here for
!    robustness when h2_fraction_pct = 0; the error at 30 vol% H2 is < 5 %).
!
! 2. CO2 flow scales with the fuel's CO2 emission factor (st%h2_co2_factor,
!    default 2.75 kg-CO2/kg-fuel for pure natural gas).
!
! 3. The MEA stripping duty follows the well-established rule of thumb:
!    roughly 3.6 GJ-thermal/t-CO2.  Only a fraction appears as electric net
!    output penalty because a combined-cycle plant supplies this mostly as
!    extracted low-pressure steam rather than direct electric load.
!
! 4. The parasitic load is subtracted from st%plant_power_MW (floored at 0).
!
! References
! ----------
!   IPCC CCS Special Report, Chapter 3 (MEA parasitic: 3–4 GJ/t-CO2)
!   Rochelle (2009) Science 325:1652, MEA regeneration energy ~3.6 GJ/t
! =============================================================================
module ccs_model
    use engine_state,    only: GridState
    use precision_kinds, only: dp
    implicit none
    private

    public :: ccs_step

    ! Electric-equivalent penalty for MEA regeneration and auxiliaries.
    ! 3.6 GJ(th)/t × ~25 % electric-equivalent opportunity cost.
    real(dp), parameter :: PARASITIC_MW_PER_T_H = 0.25_dp   ! [MW / (t CO2 / h)]

    ! Natural-gas lower heating value used for fuel-flow derivation [kJ/kg]
    real(dp), parameter :: LHV_BLEND_KJ_KG = 50000.0_dp

    ! Minimum plausible heat rate guard [kJ/kWh]  (avoids division by zero)
    real(dp), parameter :: HR_MIN_KJ_KWH = 6000.0_dp

contains

    ! =========================================================================
    !> @brief  Advance the CCS sub-system by one simulation step.
    !>
    !> @param[inout]  st  Live plant/grid state.  Writes:
    !>                      st%ccs_co2_captured_t_h  -- CO2 removed from exhaust [t/h]
    !>                      st%ccs_parasitic_MW      -- MEA regeneration penalty [MW]
    !>                      st%plant_power_MW        -- reduced by parasitic (>= 0)
    !>
    !> The subroutine is a no-op when any of the following holds:
    !>   * st%ccs_active        is .false.
    !>   * st%combined_cycle    is .false.
    !>   * st%plant_power_MW    <= 0
    ! =========================================================================
    subroutine ccs_step(st)
        type(GridState), intent(inout) :: st

        real(dp) :: fuel_kg_s      ! fuel mass flow rate [kg/s]
        real(dp) :: co2_kg_s       ! raw CO2 flow from combustion [kg/s]
        real(dp) :: captured_kg_s  ! CO2 removed by MEA absorber [kg/s]
        real(dp) :: hr_safe        ! heat rate, guarded against zero [kJ/kWh]

        ! ── Guard: only run when CCS + combined-cycle are both active ──────────
        if (.not. st%ccs_active .or. .not. st%combined_cycle) then
            st%ccs_co2_captured_t_h = 0.0_dp
            st%ccs_parasitic_MW     = 0.0_dp
            return
        end if
        if (st%plant_power_MW <= 0.0_dp) then
            st%ccs_co2_captured_t_h = 0.0_dp
            st%ccs_parasitic_MW     = 0.0_dp
            return
        end if

        ! ── Step 1: derive fuel mass flow from heat-rate ───────────────────────
        ! Prefer the live cycle fuel flow. Fall back to a guarded heat-rate
        ! estimate for tests or future callers that have not refreshed the cycle.
        fuel_kg_s = max(0.0_dp, st%fuel_flow_kg_s)
        if (fuel_kg_s <= 1.0e-9_dp) then
            hr_safe   = max(st%gt_heat_rate_kJ_kWh, HR_MIN_KJ_KWH)
            fuel_kg_s = (st%plant_power_MW * 1000.0_dp * hr_safe) &
                        / (3600.0_dp * LHV_BLEND_KJ_KG)
        end if

        ! ── Step 2: CO2 production ─────────────────────────────────────────────
        !   st%h2_co2_factor [kg-CO2/kg-fuel], default 2.75 for pure NG
        co2_kg_s = fuel_kg_s * st%h2_co2_factor

        ! ── Step 3: captured flow ──────────────────────────────────────────────
        captured_kg_s = co2_kg_s * max(0.0_dp, min(1.0_dp, st%ccs_capture_eff))

        ! ── Step 4: convert to t/h  (kg/s × 3600 s/h ÷ 1000 kg/t = × 3.6) ────
        st%ccs_co2_captured_t_h = captured_kg_s * 3.6_dp

        ! ── Step 5: parasitic power penalty  (1 MW per t/h captured) ─────────
        st%ccs_parasitic_MW = st%ccs_co2_captured_t_h * PARASITIC_MW_PER_T_H

        ! ── Step 6: reduce net plant output; floor at zero ─────────────────────
        st%plant_power_MW = max(0.0_dp, st%plant_power_MW - st%ccs_parasitic_MW)

    end subroutine ccs_step

end module ccs_model
