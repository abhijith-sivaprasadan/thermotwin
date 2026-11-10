!> Equation-based dimensional and derivative checks for a fixed ideal-gas
!> surrogate combustion-product mixture. NOT OEM/commercial validation.
program test_gas_mixture_consistency
    use precision_kinds, only: dp
    use constants, only: R_UNIVERSAL, CP_GAS, GAMMA_GAS
    use fluid_properties, only: set_property_model, PROP_CONSTANT, PROP_VARIABLE, &
                                cp_gas_at, gamma_gas_at, h_gas_sensible_J_kg
    implicit none
    integer :: failures
    real(dp) :: m_mix, r_expected, cp, gamma, r_from_gamma, derivative, t, dt
    failures = 0

    ! Independent ideal-mixture molar-mass calculation (kg/mol):
    ! WIP fraction values are MOLAR, never mass fractions.
    m_mix = 0.735_dp*0.0280134_dp + 0.085_dp*0.0440095_dp + &
            0.115_dp*0.0180153_dp + 0.065_dp*0.0319988_dp
    r_expected = R_UNIVERSAL / m_mix
    call expect_near("molar-fraction sum", &
                     0.735_dp+0.085_dp+0.115_dp+0.065_dp, 1.0_dp, 1.0e-14_dp, failures)

    call set_property_model(PROP_VARIABLE)
    t = 1200.0_dp
    dt = 0.01_dp
    cp = cp_gas_at(t)
    gamma = gamma_gas_at(t)
    r_from_gamma = cp * (1.0_dp - 1.0_dp/gamma)
    derivative = (h_gas_sensible_J_kg(t+dt) - h_gas_sensible_J_kg(t-dt)) / (2.0_dp*dt)

    call expect_true("mixture cp positive", cp > r_expected, failures)
    call expect_true("mixture gamma physical", gamma > 1.0_dp .and. gamma < 1.50_dp, failures)
    call expect_near("R_mix from gamma and cp equals universal R divided by mixture molar mass", &
                     r_from_gamma, r_expected, 1.0e-7_dp, failures)
    call expect_near("enthalpy temperature derivative matches cp", derivative, cp, 0.02_dp, failures)

    ! Separate CONSTANT teaching-fluid parameters deliberately retain
    ! their historical component-property defaults.
    call set_property_model(PROP_CONSTANT)
    call expect_near("legacy constant cp preserved", cp_gas_at(t), CP_GAS, 1.0e-10_dp, failures)
    call expect_near("legacy constant gamma preserved", gamma_gas_at(t), GAMMA_GAS, 1.0e-10_dp, failures)
    call finish("gas_mixture_consistency", failures)

contains
    include "test_assert.inc"

end program test_gas_mixture_consistency
