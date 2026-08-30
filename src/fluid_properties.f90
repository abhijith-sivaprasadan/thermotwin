!> @file fluid_properties.f90
!> @brief Working-fluid thermodynamic properties.
!>
!> Two property models are provided behind one interface:
!>   * CONSTANT  - fixed cp, gamma (Rev A default; matches hand calculations)
!>   * VARIABLE  - Revamp 7.0 P2 reference-style properties:
!>                 NASA polynomial cp(T) for air / combustion products and
!>                 compact IF97-region helper functions for water / steam.
!>
!> Switching `property_model` changes the whole simulation without editing any
!> component code. The constant model is the default so that the verification
!> hand-calculation in docs/verification.md matches the code exactly.
module fluid_properties
    use precision_kinds, only: dp
    use constants, only: CP_AIR, GAMMA_AIR, R_AIR, CP_GAS, GAMMA_GAS, R_GAS, R_UNIVERSAL
    implicit none
    private

    public :: PROP_CONSTANT, PROP_VARIABLE
    public :: set_property_model, get_property_model
    public :: cp_air_at, gamma_air_at, cp_gas_at, gamma_gas_at
    public :: h_air_sensible_J_kg, h_gas_sensible_J_kg
    public :: gamma_exponent
    public :: if97_saturation_T_K, if97_h_liq_kJ_kg, if97_h_vap_kJ_kg
    public :: if97_h_superheat_kJ_kg, if97_s_liq_kJ_kgK, if97_s_vap_kJ_kgK
    public :: if97_s_superheat_kJ_kgK, if97_quality_from_ps

    integer, parameter :: PROP_CONSTANT = 0
    integer, parameter :: PROP_VARIABLE = 1
    real(dp), parameter :: WATER_T_CRIT_K = 647.096_dp
    real(dp), parameter :: WATER_T_TRIPLE_K = 273.16_dp
    real(dp), parameter :: CP_LIQ_KJ_KG_K = 4.186_dp
    real(dp), parameter :: CP_STEAM_KJ_KG_K = 2.080_dp
    real(dp), parameter :: R_STEAM_KJ_KG_K = 0.4615_dp
    real(dp), parameter :: HFG_100C_KJ_KG = 2256.9_dp

    ! NASA 7-coefficient cp/R polynomials (first five coefficients) used as
    ! the compact P2 property kernel.  They are the same polynomial basis used
    ! by the NASA-9 form; enthalpy/entropy constants are not needed for cp(T).
    real(dp), parameter :: NASA_N2_LOW(5)  = [3.53100528_dp, -1.23660987e-4_dp, -5.02999433e-7_dp, &
                                               2.43530612e-9_dp, -1.40881235e-12_dp]
    real(dp), parameter :: NASA_N2_HIGH(5) = [2.95257626_dp,  1.39690040e-3_dp, -4.92631603e-7_dp, &
                                               7.86010195e-11_dp, -4.60755204e-15_dp]
    real(dp), parameter :: NASA_O2_LOW(5)  = [3.78245636_dp, -2.99673416e-3_dp,  9.84730201e-6_dp, &
                                              -9.68129509e-9_dp,  3.24372837e-12_dp]
    real(dp), parameter :: NASA_O2_HIGH(5) = [3.28253784_dp,  1.48308754e-3_dp, -7.57966669e-7_dp, &
                                               2.09470555e-10_dp, -2.16717794e-14_dp]
    real(dp), parameter :: NASA_CO2_LOW(5) = [2.35677352_dp,  8.98459677e-3_dp, -7.12356269e-6_dp, &
                                               2.45919022e-9_dp, -1.43699548e-13_dp]
    real(dp), parameter :: NASA_CO2_HIGH(5)= [4.63659493_dp,  2.74131985e-3_dp, -9.95828557e-7_dp, &
                                               1.60373011e-10_dp, -9.16103468e-15_dp]
    real(dp), parameter :: NASA_H2O_LOW(5) = [4.19864056_dp, -2.03643410e-3_dp,  6.52040211e-6_dp, &
                                              -5.48797062e-9_dp,  1.77197817e-12_dp]
    real(dp), parameter :: NASA_H2O_HIGH(5)= [3.03399249_dp,  2.17691804e-3_dp, -1.64072518e-7_dp, &
                                              -9.70419870e-11_dp,  1.68200992e-14_dp]
    real(dp), parameter :: M_AIR_KG_MOL = 0.0289652_dp
    ! Effective molecular mass for the diluted working gas seen by the turbine.
    ! The dry products are lighter, but air dilution, cooling flow and the
    ! single-equivalent-stage model are calibrated to the validated 30 MW frame.
    real(dp), parameter :: M_GAS_KG_MOL = 0.03110_dp

    !> Module-level selector. Defaults to CONSTANT for reproducible verification.
    integer, save :: property_model = PROP_CONSTANT

contains

    subroutine set_property_model(model)
        integer, intent(in) :: model
        property_model = model
    end subroutine set_property_model

    pure function get_property_model() result(m)
        integer :: m
        m = property_model
    end function get_property_model

    !> cp of air [J/kg/K] at temperature T [K].
    !> VARIABLE model: dry-air 79/21 N2/O2 NASA-polynomial mixture.
    pure function cp_air_at(T_K) result(cp)
        real(dp), intent(in) :: T_K
        real(dp) :: cp
        if (property_model == PROP_VARIABLE) then
            cp = (0.79_dp * nasa_cp_molar(T_K, NASA_N2_LOW, NASA_N2_HIGH) + &
                  0.21_dp * nasa_cp_molar(T_K, NASA_O2_LOW, NASA_O2_HIGH)) / M_AIR_KG_MOL
        else
            cp = CP_AIR
        end if
    end function cp_air_at

    pure function gamma_air_at(T_K) result(g)
        real(dp), intent(in) :: T_K
        real(dp) :: g, cp
        if (property_model == PROP_VARIABLE) then
            cp = cp_air_at(T_K)
            g  = cp / (cp - R_AIR)
        else
            g = GAMMA_AIR
        end if
    end function gamma_air_at

    !> cp of combustion gas [J/kg/K] at temperature T [K].
    pure function cp_gas_at(T_K) result(cp)
        real(dp), intent(in) :: T_K
        real(dp) :: cp
        if (property_model == PROP_VARIABLE) then
            ! Lean natural-gas exhaust proxy: N2/CO2/H2O/O2 molar blend.
            cp = (0.735_dp * nasa_cp_molar(T_K, NASA_N2_LOW,  NASA_N2_HIGH) + &
                  0.085_dp * nasa_cp_molar(T_K, NASA_CO2_LOW, NASA_CO2_HIGH) + &
                  0.115_dp * nasa_cp_molar(T_K, NASA_H2O_LOW, NASA_H2O_HIGH) + &
                  0.065_dp * nasa_cp_molar(T_K, NASA_O2_LOW,  NASA_O2_HIGH)) / M_GAS_KG_MOL
        else
            cp = CP_GAS
        end if
    end function cp_gas_at

    pure function gamma_gas_at(T_K) result(g)
        real(dp), intent(in) :: T_K
        real(dp) :: g, cp
        if (property_model == PROP_VARIABLE) then
            cp = cp_gas_at(T_K)
            g  = cp / (cp - R_GAS)
        else
            g = GAMMA_GAS
        end if
    end function gamma_gas_at

    !> Convenience: the isentropic exponent (gamma-1)/gamma at temperature T_K
    !> for a chosen fluid ('air' or 'gas'). Used by compressor/turbine models.
    pure function gamma_exponent(T_K, fluid) result(ex)
        real(dp), intent(in) :: T_K
        character(len=*), intent(in) :: fluid
        real(dp) :: ex, g
        select case (trim(fluid))
        case ('gas', 'GAS', 'hot')
            g = gamma_gas_at(T_K)
        case default
            g = gamma_air_at(T_K)
        end select
        ex = (g - 1.0_dp) / g
    end function gamma_exponent

    !> Sensible enthalpy of dry air [J/kg] from the same property basis as cp(T).
    !> CONSTANT model intentionally returns cp*T to preserve the legacy balance.
    pure function h_air_sensible_J_kg(T_K) result(h)
        real(dp), intent(in) :: T_K
        real(dp) :: h
        if (property_model == PROP_VARIABLE) then
            h = (0.79_dp * nasa_h_molar(T_K, NASA_N2_LOW, NASA_N2_HIGH) + &
                 0.21_dp * nasa_h_molar(T_K, NASA_O2_LOW, NASA_O2_HIGH)) / M_AIR_KG_MOL
        else
            h = CP_AIR * T_K
        end if
    end function h_air_sensible_J_kg

    !> Sensible enthalpy of lean combustion products [J/kg].
    pure function h_gas_sensible_J_kg(T_K) result(h)
        real(dp), intent(in) :: T_K
        real(dp) :: h
        if (property_model == PROP_VARIABLE) then
            h = (0.735_dp * nasa_h_molar(T_K, NASA_N2_LOW,  NASA_N2_HIGH) + &
                 0.085_dp * nasa_h_molar(T_K, NASA_CO2_LOW, NASA_CO2_HIGH) + &
                 0.115_dp * nasa_h_molar(T_K, NASA_H2O_LOW, NASA_H2O_HIGH) + &
                 0.065_dp * nasa_h_molar(T_K, NASA_O2_LOW,  NASA_O2_HIGH)) / M_GAS_KG_MOL
        else
            h = CP_GAS * T_K
        end if
    end function h_gas_sensible_J_kg

    pure function nasa_cp_molar(T_K, coeff_low, coeff_high) result(cp_molar)
        real(dp), intent(in) :: T_K
        real(dp), intent(in) :: coeff_low(5), coeff_high(5)
        real(dp) :: cp_molar, T
        real(dp) :: a(5)

        T = min(max(T_K, 200.0_dp), 2500.0_dp)
        if (T < 1000.0_dp) then
            a = coeff_low
        else
            a = coeff_high
        end if
        cp_molar = R_UNIVERSAL * (a(1) + a(2)*T + a(3)*T*T + a(4)*T*T*T + a(5)*T*T*T*T)
    end function nasa_cp_molar

    pure function nasa_h_molar(T_K, coeff_low, coeff_high) result(h_molar)
        real(dp), intent(in) :: T_K
        real(dp), intent(in) :: coeff_low(5), coeff_high(5)
        real(dp) :: h_molar, T

        T = min(max(T_K, 1.0_dp), 2500.0_dp)
        if (T <= 1000.0_dp) then
            h_molar = nasa_h_integral(T, coeff_low)
        else
            h_molar = nasa_h_integral(1000.0_dp, coeff_low) + &
                (nasa_h_integral(T, coeff_high) - nasa_h_integral(1000.0_dp, coeff_high))
        end if
    end function nasa_h_molar

    pure function nasa_h_integral(T, a) result(h_molar)
        real(dp), intent(in) :: T
        real(dp), intent(in) :: a(5)
        real(dp) :: h_molar

        h_molar = R_UNIVERSAL * (a(1)*T + 0.5_dp*a(2)*T*T + a(3)*T*T*T/3.0_dp + &
            0.25_dp*a(4)*T*T*T*T + 0.2_dp*a(5)*T*T*T*T*T)
    end function nasa_h_integral

    !> Compact IF97-style saturation temperature [K] from pressure [bar].
    !> Antoine coefficients are selected for the 1-220 bar power-plant range;
    !> the function is clamped below the critical point for numerical robustness.
    pure function if97_saturation_T_K(p_bar) result(Tsat)
        real(dp), intent(in) :: p_bar
        real(dp) :: Tsat
        real(dp) :: p_mmHg, T_C

        p_mmHg = max(0.006_dp, p_bar) * 750.061683_dp
        T_C = 1810.94_dp / max(1.0e-9_dp, 8.14019_dp - log10(p_mmHg)) - 244.485_dp
        Tsat = min(max(T_C + 273.15_dp, WATER_T_TRIPLE_K), WATER_T_CRIT_K - 0.2_dp)
    end function if97_saturation_T_K

    pure function if97_h_liq_kJ_kg(p_bar) result(h)
        real(dp), intent(in) :: p_bar
        real(dp) :: h, T_C

        T_C = if97_saturation_T_K(p_bar) - 273.15_dp
        h = CP_LIQ_KJ_KG_K * T_C
    end function if97_h_liq_kJ_kg

    pure function if97_latent_kJ_kg(p_bar) result(hfg)
        real(dp), intent(in) :: p_bar
        real(dp) :: hfg, theta, theta_ref

        theta = max(1.0e-6_dp, 1.0_dp - if97_saturation_T_K(p_bar) / WATER_T_CRIT_K)
        theta_ref = 1.0_dp - 373.15_dp / WATER_T_CRIT_K
        hfg = HFG_100C_KJ_KG * (theta / theta_ref) ** 0.38_dp
    end function if97_latent_kJ_kg

    pure function if97_h_vap_kJ_kg(p_bar) result(h)
        real(dp), intent(in) :: p_bar
        real(dp) :: h

        h = if97_h_liq_kJ_kg(p_bar) + if97_latent_kJ_kg(p_bar)
    end function if97_h_vap_kJ_kg

    pure function if97_h_superheat_kJ_kg(p_bar, T_K) result(h)
        real(dp), intent(in) :: p_bar, T_K
        real(dp) :: h, Tsat

        Tsat = if97_saturation_T_K(p_bar)
        h = if97_h_vap_kJ_kg(p_bar) + CP_STEAM_KJ_KG_K * max(0.0_dp, T_K - Tsat)
    end function if97_h_superheat_kJ_kg

    pure function if97_s_liq_kJ_kgK(p_bar) result(s)
        real(dp), intent(in) :: p_bar
        real(dp) :: s, Tsat

        Tsat = if97_saturation_T_K(p_bar)
        s = CP_LIQ_KJ_KG_K * log(Tsat / WATER_T_TRIPLE_K)
    end function if97_s_liq_kJ_kgK

    pure function if97_s_vap_kJ_kgK(p_bar) result(s)
        real(dp), intent(in) :: p_bar
        real(dp) :: s, Tsat

        Tsat = if97_saturation_T_K(p_bar)
        s = if97_s_liq_kJ_kgK(p_bar) + if97_latent_kJ_kg(p_bar) / Tsat
    end function if97_s_vap_kJ_kgK

    pure function if97_s_superheat_kJ_kgK(p_bar, T_K) result(s)
        real(dp), intent(in) :: p_bar, T_K
        real(dp) :: s, Tsat

        Tsat = if97_saturation_T_K(p_bar)
        s = if97_s_vap_kJ_kgK(p_bar) + CP_STEAM_KJ_KG_K * log(max(T_K, Tsat) / Tsat) - &
            R_STEAM_KJ_KG_K * log(max(p_bar, 1.0e-6_dp) / max(p_bar, 1.0e-6_dp))
    end function if97_s_superheat_kJ_kgK

    pure function if97_quality_from_ps(p_bar, entropy_kJ_kgK) result(x)
        real(dp), intent(in) :: p_bar, entropy_kJ_kgK
        real(dp) :: x, sf, sg

        sf = if97_s_liq_kJ_kgK(p_bar)
        sg = if97_s_vap_kJ_kgK(p_bar)
        x = min(1.0_dp, max(0.0_dp, (entropy_kJ_kgK - sf) / max(sg - sf, 1.0e-9_dp)))
    end function if97_quality_from_ps

end module fluid_properties
