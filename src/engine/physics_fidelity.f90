!> @file physics_fidelity.f90
!> @brief Revamp 5.0 C3 reference envelopes for GT part-load and HRSG pinch.
!>
!> The values here are transparent reference curves, not OEM-proprietary maps.
!> They provide a defensible comparison envelope for the HMI: industrial simple-
!> cycle heat rate worsens at part load, hot ambient raises heat rate, higher
!> firing temperature improves it, and single-pressure HRSG pinch targets stay in
!> the 12-20 K design class with extra margin at low load.
module physics_fidelity
    use precision_kinds, only: dp
    use engine_state, only: GridState, FIDELITY_N, clamp_real
    implicit none
    private

    public :: refresh_physics_fidelity
    public :: reference_gt_heat_rate, reference_hrsg_pinch_K
    public :: FIDELITY_LOAD_PCT, GT_REFERENCE_DESIGN_HR_KJ_KWH

    real(dp), parameter :: GT_REFERENCE_DESIGN_HR_KJ_KWH = 11550.0_dp
    real(dp), parameter :: FIDELITY_LOAD_PCT(FIDELITY_N) = &
        [30.0_dp, 40.0_dp, 50.0_dp, 60.0_dp, 70.0_dp, 85.0_dp, 100.0_dp]
    real(dp), parameter :: HR_RATIO(FIDELITY_N) = &
        [1.52_dp, 1.38_dp, 1.27_dp, 1.17_dp, 1.10_dp, 1.04_dp, 1.00_dp]

contains

    subroutine refresh_physics_fidelity(st)
        type(GridState), intent(inout) :: st
        integer :: i
        real(dp) :: load_frac, ref_hr, ref_pinch

        load_frac = clamp_real(st%gas_dispatch_pct / 100.0_dp, 0.30_dp, 1.0_dp)

        do i = 1, FIDELITY_N
            st%physics_load_pct(i) = FIDELITY_LOAD_PCT(i)
            st%physics_ref_gt_hr_kJ_kWh(i) = reference_gt_heat_rate( &
                FIDELITY_LOAD_PCT(i) / 100.0_dp, st%ambient_C, st%TIT_K)
            st%physics_ref_hrsg_pinch_K(i) = reference_hrsg_pinch_K( &
                FIDELITY_LOAD_PCT(i) / 100.0_dp)
        end do

        ref_hr = reference_gt_heat_rate(load_frac, st%ambient_C, st%TIT_K)
        ref_pinch = reference_hrsg_pinch_K(load_frac)

        st%physics_gt_hr_ref_kJ_kWh = ref_hr
        if (ref_hr > 1.0e-9_dp .and. st%gt_heat_rate_kJ_kWh > 0.0_dp) then
            st%physics_gt_hr_gap_pct = (st%gt_heat_rate_kJ_kWh - ref_hr) / ref_hr * 100.0_dp
        else
            st%physics_gt_hr_gap_pct = 0.0_dp
        end if

        st%physics_hrsg_pinch_ref_K = ref_pinch
        if (st%combined_cycle) then
            st%physics_hrsg_pinch_gap_K = st%hrsg_pinch_K - ref_pinch
        else
            st%physics_hrsg_pinch_gap_K = 0.0_dp
        end if

        st%physics_fidelity_n = FIDELITY_N
        st%physics_fidelity_ready = .true.
    end subroutine refresh_physics_fidelity

    pure function reference_gt_heat_rate(load_frac, ambient_C, tit_K) result(hr)
        real(dp), intent(in) :: load_frac, ambient_C, tit_K
        real(dp) :: hr
        real(dp) :: lpct, ratio, ambient_factor, tit_factor

        lpct = clamp_real(100.0_dp * load_frac, FIDELITY_LOAD_PCT(1), FIDELITY_LOAD_PCT(FIDELITY_N))
        ratio = interp_reference(lpct, FIDELITY_LOAD_PCT, HR_RATIO)
        ambient_factor = 1.0_dp + 0.0022_dp * (ambient_C - 15.0_dp)
        tit_factor = 1.0_dp - 0.00045_dp * (tit_K - 1400.0_dp)
        hr = GT_REFERENCE_DESIGN_HR_KJ_KWH * ratio * &
             clamp_real(ambient_factor, 0.90_dp, 1.16_dp) * &
             clamp_real(tit_factor, 0.88_dp, 1.22_dp)
    end function reference_gt_heat_rate

    pure function reference_hrsg_pinch_K(load_frac) result(pinch_K)
        real(dp), intent(in) :: load_frac
        real(dp) :: pinch_K, lf

        lf = clamp_real(load_frac, 0.30_dp, 1.0_dp)
        pinch_K = 12.0_dp + 8.0_dp * (1.0_dp - lf) ** 1.35_dp
    end function reference_hrsg_pinch_K

    pure function interp_reference(x, xp, yp) result(y)
        real(dp), intent(in) :: x
        real(dp), intent(in) :: xp(:), yp(:)
        real(dp) :: y, w
        integer :: i

        if (x <= xp(1)) then
            y = yp(1)
            return
        end if
        do i = 1, size(xp) - 1
            if (x <= xp(i + 1)) then
                w = (x - xp(i)) / max(xp(i + 1) - xp(i), 1.0e-9_dp)
                y = yp(i) * (1.0_dp - w) + yp(i + 1) * w
                return
            end if
        end do
        y = yp(size(yp))
    end function interp_reference

end module physics_fidelity
