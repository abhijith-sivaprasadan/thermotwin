!> @file gfm_bess.f90
!> @brief Grid-Forming (GFM) BESS with virtual inertia and frequency droop.
!>
!> When gfm_mode is enabled the BESS responds to frequency deviations with
!> two concurrent contributions that are summed and added to the storage
!> setpoint each time step:
!>
!>   P_inertia  — proportional to ROCOF (df/dt), emulating the kinetic energy
!>                release of a synchronous machine with inertia constant H.
!>   P_droop    — proportional to steady-state frequency error (Δf), acting
!>                like a governor with a configurable droop percentage.
!>
!> Both contributions are sized relative to a GFM BESS rating of 20 % of the
!> plant gas-turbine capacity, and the combined response is clamped to
!> ±25 % of gas_capacity_MW before writing back to storage_request_MW.
!>
!> An energy-availability guard prevents discharge below 20 % SOC and
!> charging above 80 % SOC.  The equivalent inertia contribution
!> gfm_H_equiv reports the available virtual inertia contribution, while
!> gfm_synth_MW reports the instantaneous power response actually delivered.
!>
!> The request is clamped to the inverter command range here; the actual
!> delivered power is still energy-limited by the common BESS limiter.
module gfm_bess
    use precision_kinds, only: dp
    use engine_state,    only: GridState, STORAGE_MIN_MW, STORAGE_MAX_MW, clamp_real
    implicit none
    private

    public :: gfm_step

    ! GFM BESS sizing as a fraction of plant gas-turbine capacity
    real(dp), parameter :: GFM_SIZE_FRAC = 0.20_dp   ! 20 % of gas_capacity_MW

    ! Hard clamp: GFM response never exceeds this fraction of gas_capacity_MW
    real(dp), parameter :: GFM_CLAMP_FRAC = 0.25_dp  ! ±25 % of gas_capacity_MW

    ! SOC limits for energy-availability guard [%]
    real(dp), parameter :: SOC_MIN_DISCHARGE = 20.0_dp
    real(dp), parameter :: SOC_MAX_CHARGE    = 80.0_dp

contains

    !> Compute one time-step of GFM BESS response and update state.
    !>
    !> @param st   Shared plant/grid state (intent inout).
    !> @param dt_s Integration time step [s] (not used in the steady-state
    !>             formulation but kept for API consistency with other engine
    !>             tick routines and future rate-limited implementations).
    subroutine gfm_step(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp),        intent(in)    :: dt_s

        real(dp) :: f_nominal      ! state-specific nominal frequency [Hz]
        real(dp) :: delta_f        ! frequency deviation from nominal [Hz]
        real(dp) :: P_inertia      ! virtual-inertia power response [MW]
        real(dp) :: P_droop        ! frequency-droop power response [MW]
        real(dp) :: gfm_total      ! combined (unclamped) response [MW]
        real(dp) :: gfm_capacity   ! GFM BESS rated power ceiling [MW]
        real(dp) :: clamp_limit    ! absolute clamp value [MW]
        real(dp) :: gfm_delivered  ! response after SOC guard [MW]

        ! Unused in current formulation; suppress compiler warning
        real(dp) :: dt_unused
        dt_unused = dt_s

        ! ── Early exit when GFM is disabled ─────────────────────────────────
        if (.not. st%gfm_mode) then
            st%gfm_synth_MW = 0.0_dp
            st%gfm_H_equiv  = 0.0_dp
            return
        end if

        ! ── Sizing reference ─────────────────────────────────────────────────
        ! Use max() so a zero gas_capacity_MW (plant offline) yields a finite
        ! but negligible GFM contribution rather than a division by zero.
        gfm_capacity = max(st%gas_capacity_MW, 1.0_dp) * GFM_SIZE_FRAC
        clamp_limit  = max(st%gas_capacity_MW, 1.0_dp) * GFM_CLAMP_FRAC

        ! ── Frequency deviation ──────────────────────────────────────────────
        f_nominal = max(1.0_dp, st%nominal_frequency_Hz)
        delta_f = st%frequency_Hz - f_nominal

        ! ── Virtual-inertia term ─────────────────────────────────────────────
        ! P_inertia = 2H × S_GFM × (−ROCOF) / f0
        !   Sign: positive ROCOF (frequency rising) → absorb power (negative P).
        !   The factor 2 arises from the standard swing-equation definition of H
        !   (H = stored kinetic energy / rated MVA).
        P_inertia = 2.0_dp * st%gfm_virtual_H * gfm_capacity * &
                    (-st%freq_rocof_Hz_s) / f_nominal

        ! ── Droop term ───────────────────────────────────────────────────────
        ! P_droop = −Δf / f0 / (R/100) × S_GFM,  where R = droop [%]
        ! Frequency below nominal → negative delta_f → positive droop response.
        P_droop = -delta_f / f_nominal / (st%gfm_droop_pct / 100.0_dp) * gfm_capacity

        ! ── Combined response (clamped) ──────────────────────────────────────
        gfm_total = P_inertia + P_droop
        gfm_total = max(-clamp_limit, min(clamp_limit, gfm_total))

        ! ── Energy-availability guard ────────────────────────────────────────
        ! Discharge (positive): block if SOC is too low.
        ! Charge   (negative): block if battery is already near full.
        gfm_delivered = gfm_total
        if (gfm_delivered > 0.0_dp .and. st%battery_soc_pct < SOC_MIN_DISCHARGE) then
            gfm_delivered = 0.0_dp
        else if (gfm_delivered < 0.0_dp .and. st%battery_soc_pct > SOC_MAX_CHARGE) then
            gfm_delivered = 0.0_dp
        end if

        ! ── Write outputs ────────────────────────────────────────────────────
        st%gfm_synth_MW = gfm_delivered

        ! Accumulate into storage request, then clamp the command to the
        ! inverter range. Actual delivered MW is still energy-limited later.
        st%storage_request_MW = clamp_real(st%storage_request_MW + gfm_delivered, &
                                           STORAGE_MIN_MW, STORAGE_MAX_MW)

        ! Equivalent inertia contribution available to the plant. Keep this
        ! nonzero at steady frequency so the HMI and scenarios can distinguish
        ! "GFM armed" from "GFM actively injecting this instant".
        if (st%battery_soc_pct > SOC_MIN_DISCHARGE .and. st%battery_soc_pct < SOC_MAX_CHARGE) then
            st%gfm_H_equiv = st%gfm_virtual_H * &
                             (gfm_capacity / max(st%gas_capacity_MW, 1.0_dp))
        else
            st%gfm_H_equiv = 0.0_dp
        end if

    end subroutine gfm_step

end module gfm_bess
