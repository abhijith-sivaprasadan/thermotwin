!> @file tie_line.f90
!> @brief Tie-line model: two-area ACE and inter-area power exchange.
!>
!> A second grid zone is connected to zone 1 via a tie-line.  The Area
!> Control Error (ACE) drives inter-area power exchange according to the
!> standard NERC/ENTSO-E formulation:
!>
!>   ACE = (P_tie_actual - P_tie_scheduled) + B * (f - f_nom)
!>
!> where B is the frequency bias factor [MW/Hz].  Zone 2 has simple
!> first-order swing + governor dynamics sufficient for stability studies.
!>
!> Physics summary
!> ---------------
!>   Tie-flow dynamics (5 s time constant, capacitive synchronising term):
!>     target_flow = freq_diff * TIE_IMPEDANCE * capacity
!>     d(tie_flow)/dt = (target_flow - tie_flow) / 5 s
!>
!>   Zone-2 swing equation (H = 5 s, S_rated = 300 MW):
!>     df2/dt = imbalance2 / (2 H / f_nom * S_rated)
!>
!>   Zone-2 governor (4 % droop):
!>     dP2/dt = -(Δf2 / f_nom / R) * S_rated / 10 s   [slew-limited]
!>
!> All quantities are in SI-coherent engineering units (MW, Hz, s).
module tie_line
    use engine_state,    only: GridState
    use precision_kinds, only: dp
    implicit none
    private

    public :: tie_line_step

    ! ── Module-level physical constants ────────────────────────────────────────
    !> Nominal system frequency [Hz]
    real(dp), parameter :: FREQ_NOM = 50.0_dp

    !> Frequency bias factor B [MW/Hz]  (10B coefficient, typical 50 MW/Hz/area)
    real(dp), parameter :: FREQ_BIAS_MW_HZ = 50.0_dp

    !> Synchronising coefficient: tie-flow sensitivity to frequency difference
    !> [MW / (Hz · p.u. capacity)] — scales with tie_capacity_MW at call time.
    real(dp), parameter :: TIE_IMPEDANCE = 0.01_dp

    !> Zone-2 inertia constant [s]
    real(dp), parameter :: ZONE2_H = 5.0_dp

    !> Zone-2 rated capacity [MW]
    real(dp), parameter :: ZONE2_RATED_MW = 300.0_dp

    !> Zone-2 governor droop [p.u.]  (4 %)
    real(dp), parameter :: DROOP2 = 0.04_dp

    !> Tie-flow first-order time constant [s]
    real(dp), parameter :: TIE_TAU_S = 5.0_dp

    !> Zone-2 governor response time constant [s]  (slew divisor in dP2 expression)
    real(dp), parameter :: GOV2_TAU_S = 10.0_dp

    !> Zone-2 frequency hard clamp limits [Hz]
    real(dp), parameter :: ZONE2_FREQ_LO = 47.0_dp
    real(dp), parameter :: ZONE2_FREQ_HI = 53.0_dp

    !> Zone-2 generation hard clamp limits [MW]
    real(dp), parameter :: ZONE2_GEN_LO  = 50.0_dp
    real(dp), parameter :: ZONE2_GEN_HI  = 300.0_dp

contains

    ! ── Internal helper ────────────────────────────────────────────────────────

    !> Clamp a real(dp) value to [lo, hi].
    pure function clamp(val, lo, hi) result(c)
        real(dp), intent(in) :: val, lo, hi
        real(dp) :: c
        c = min(max(val, lo), hi)
    end function clamp

    ! ── Public procedure ───────────────────────────────────────────────────────

    !> Advance the tie-line and zone-2 state by one time step.
    !>
    !> @param[inout] st    Simulation state record (GridState).
    !> @param[in]    dt_s  Integration time step [s].  Must be > 0.
    !>
    !> @note No-op when st%tie_active is .false.; all state fields are left
    !>       unchanged so the caller may toggle the feature at any time without
    !>       discontinuity on re-enable (the fields retain their last values).
    subroutine tie_line_step(st, dt_s)
        type(GridState), intent(inout) :: st
        real(dp),        intent(in)    :: dt_s

        ! ── Local temporaries ──────────────────────────────────────────────────
        real(dp) :: freq_diff        ! f_zone1 - f_zone2               [Hz]
        real(dp) :: target_flow_MW   ! quasi-steady tie flow            [MW]
        real(dp) :: d_tie_MW         ! incremental tie-flow change      [MW]
        real(dp) :: zone2_imbalance  ! net mechanical power imbalance   [MW]
        real(dp) :: df2              ! d(f_zone2)/dt                    [Hz/s]
        real(dp) :: dP2              ! d(P_gen_zone2)/dt * dt_s         [MW]

        ! ── Guard: feature disabled ────────────────────────────────────────────
        if (.not. st%tie_active) return

        ! ======================================================================
        ! 1. Tie-flow dynamics
        !    The synchronising power flow is proportional to the angular
        !    (frequency) difference between the two areas, scaled by the
        !    tie-line impedance and the thermal capacity limit.
        !    A first-order lag (τ = TIE_TAU_S) represents the electrical
        !    transient of the transmission corridor.
        ! ======================================================================
        freq_diff      = st%frequency_Hz - st%zone2_freq_Hz
        target_flow_MW = freq_diff * TIE_IMPEDANCE * st%tie_capacity_MW

        d_tie_MW       = (target_flow_MW - st%tie_flow_MW) / TIE_TAU_S * dt_s

        st%tie_flow_MW = clamp( st%tie_flow_MW + d_tie_MW, &
                                -st%tie_capacity_MW,        &
                                 st%tie_capacity_MW )

        ! ======================================================================
        ! 2. Zone-2 frequency dynamics (swing equation)
        !    Sign convention:
        !      st%tie_flow_MW > 0  =>  zone 1 exports  =>  zone 2 *receives*
        !      Power entering zone 2 from the tie is therefore -tie_flow_MW
        !      (a positive export from zone 1 increases zone-2 generation-side
        !      balance, reducing zone-2 frequency deviation).
        !
        !    zone2_imbalance = gen2 - demand2 + tie_import_to_zone2
        !                    = gen2 - demand2 - tie_flow_MW
        ! ======================================================================
        zone2_imbalance = st%zone2_gen_MW - st%zone2_demand_MW - st%tie_flow_MW

        !  df/dt = P_imbalance / (2 H / f_nom * S_rated)   [swing equation]
        df2 = zone2_imbalance / ( 2.0_dp * ZONE2_H / FREQ_NOM * ZONE2_RATED_MW )

        st%zone2_freq_Hz = clamp( st%zone2_freq_Hz + df2 * dt_s, &
                                  ZONE2_FREQ_LO, ZONE2_FREQ_HI )

        ! ======================================================================
        ! 3. Zone-2 governor response (proportional frequency droop)
        !    dP = -(Δf / f_nom) / R * S_rated  with a slew time constant
        !    of GOV2_TAU_S to avoid algebraic stiffness.
        ! ======================================================================
        dP2 = -( st%zone2_freq_Hz - FREQ_NOM ) / FREQ_NOM / DROOP2 &
              * ZONE2_RATED_MW * dt_s / GOV2_TAU_S

        st%zone2_gen_MW = clamp( st%zone2_gen_MW + dP2, &
                                 ZONE2_GEN_LO, ZONE2_GEN_HI )

        ! ======================================================================
        ! 4. ACE calculation (NERC standard, frequency-biased tie-line error)
        !    ACE = (P_tie_actual - P_tie_scheduled) + B * (f - f_nom)
        !    A positive ACE means zone 1 is over-generating relative to its
        !    scheduled obligation; negative ACE means under-generation.
        ! ======================================================================
        st%ace_MW = ( st%tie_flow_MW - st%tie_scheduled_MW ) &
                  + FREQ_BIAS_MW_HZ * ( st%frequency_Hz - FREQ_NOM )

    end subroutine tie_line_step

end module tie_line
