! =============================================================================
! h2_blend.f90  --  Hydrogen co-firing blend properties for ThermoTwin-F
!
! Computes fuel-blend thermodynamic and emissions properties for a natural
! gas / hydrogen volumetric mixture (0–30 vol% H2).
!
!   lhv_blend_mj  : mass-weighted LHV [MJ/kg]  -- replaces ic%LHV_J_kg/1e6
!   co2_factor    : kg CO2 per kg blend fuel    -- only NG fraction produces CO2
!   nox_factor    : relative NOx multiplier     -- 1.0 = pure NG baseline
!   wobbe_ok      : .true. if Wobbe index within ±5% of NG reference
!
! Physical basis:
!   CH4: LHV = 50.0 MJ/kg,  M = 16.043 g/mol,  CO2 = 2.75 kg/kg, Wobbe = 51.6 MJ/m3
!   H2:  LHV = 120.0 MJ/kg, M =  2.016 g/mol,  CO2 = 0   kg/kg, Wobbe = 48.2 MJ/m3
!
! NOx is modelled as a linear increase with H2 vol fraction (thermal NOx
! dominates at elevated flame temperatures). The slope k_nox = 2.5 gives
! ~+75% NOx at 30 vol% H2, consistent with published burner-test data.
! =============================================================================
module h2_blend
    use precision_kinds, only: dp
    implicit none
    private

    public :: compute_h2_blend

    real(dp), parameter :: LHV_H2_MJ_KG     = 120.0_dp   ! H2 lower heating value
    real(dp), parameter :: LHV_NG_MJ_KG     = 50.0_dp    ! natural gas (CH4) LHV
    real(dp), parameter :: CO2_NG_KG_PER_KG = 2.75_dp    ! CO2 per kg NG combusted
    real(dp), parameter :: M_H2             = 2.016_dp   ! H2 molar mass [g/mol]
    real(dp), parameter :: M_CH4            = 16.043_dp  ! CH4 molar mass [g/mol]
    real(dp), parameter :: WOBBE_NG         = 51.6_dp    ! NG Wobbe index [MJ/m3]
    real(dp), parameter :: WOBBE_H2         = 48.2_dp    ! H2 Wobbe index [MJ/m3]
    real(dp), parameter :: NOX_K            = 2.5_dp     ! thermal NOx slope [per unit xv]
    real(dp), parameter :: WOBBE_TOL        = 0.05_dp    ! ±5% Wobbe tolerance

contains

    ! -------------------------------------------------------------------------
    ! Compute blend properties for a given H2 volumetric fraction.
    ! h2_vol_pct: 0–30 vol% H2 (clamped internally)
    ! -------------------------------------------------------------------------
    subroutine compute_h2_blend(h2_vol_pct, lhv_blend_mj, co2_factor, nox_factor, wobbe_ok)
        real(dp), intent(in)  :: h2_vol_pct     ! H2 vol % in fuel blend
        real(dp), intent(out) :: lhv_blend_mj   ! blended LHV [MJ/kg]
        real(dp), intent(out) :: co2_factor      ! kg CO2 per kg blend fuel
        real(dp), intent(out) :: nox_factor      ! NOx multiplier vs pure NG
        logical,  intent(out) :: wobbe_ok        ! Wobbe within ±5% of NG

        real(dp) :: xv, xm_h2, wobbe_blend

        xv    = min(30.0_dp, max(0.0_dp, h2_vol_pct)) / 100.0_dp

        ! H2 mass fraction from volumetric fraction (ideal gas, M = const in blend)
        xm_h2 = xv * M_H2 / (xv * M_H2 + (1.0_dp - xv) * M_CH4)

        ! Mass-weighted LHV
        lhv_blend_mj = xm_h2 * LHV_H2_MJ_KG + (1.0_dp - xm_h2) * LHV_NG_MJ_KG

        ! CO2 factor -- only the NG fraction oxidises to CO2
        co2_factor = (1.0_dp - xm_h2) * CO2_NG_KG_PER_KG

        ! Thermal NOx: linear increase with volumetric H2 fraction
        nox_factor = 1.0_dp + NOX_K * xv

        ! Wobbe index: volumetric-fraction weighted (simplified; ignores density detail)
        wobbe_blend = xv * WOBBE_H2 + (1.0_dp - xv) * WOBBE_NG
        wobbe_ok    = abs(wobbe_blend - WOBBE_NG) / WOBBE_NG < WOBBE_TOL

    end subroutine compute_h2_blend

end module h2_blend
