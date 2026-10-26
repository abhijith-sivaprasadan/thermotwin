! CSV samples of approximate water/steam property functions; NOT IAPWS-IF97.
program property_reference_grid
  use precision_kinds, only: dp
  use fluid_properties, only: if97_saturation_T_K, if97_h_liq_kJ_kg, &
       if97_h_vap_kJ_kg, if97_s_liq_kJ_kgK, if97_s_vap_kJ_kgK, &
       if97_h_superheat_kJ_kg
  implicit none
  real(dp), parameter :: pressure_bar(9) = [0.1_dp, 1.01325_dp, 5.0_dp, 10.0_dp, &
       35.0_dp, 80.0_dp, 120.0_dp, 160.0_dp, 200.0_dp]
  real(dp) :: p,t
  integer :: i
  write(*,'(a)') 'p_bar,T_sat_K,h_liq_kJ_kg,h_vap_kJ_kg,s_liq_kJ_kgK,s_vap_kJ_kgK,h_superheat_50K_kJ_kg'
  do i=1,size(pressure_bar)
    p = pressure_bar(i)
    t = if97_saturation_T_K(p)
    write(*,'(*(g0,:,","))') p,t,if97_h_liq_kJ_kg(p),if97_h_vap_kJ_kg(p), &
         if97_s_liq_kJ_kgK(p),if97_s_vap_kJ_kgK(p),if97_h_superheat_kJ_kg(p,t+50.0_dp)
  end do
end program property_reference_grid
