!> @file test_diagnostics.f90
!> @brief Tests that the inverse solver recovers a known degradation from
!>        noise-free synthetic observations.
program test_diagnostics
    use precision_kinds, only: dp
    use types, only: InputCase, CycleResult, DegradationSet
    use cycle_solver, only: solve_cycle
    use degradation, only: apply_degradation
    use diagnostics_solver, only: Observation, DiagnosticWeights, DiagnosticResult, &
                                  default_weights, diagnose
    use fluid_properties, only: set_property_model, PROP_CONSTANT
    implicit none
    type(InputCase) :: base
    type(CycleResult) :: truth
    type(DegradationSet) :: true_deg
    type(Observation) :: obs
    type(DiagnosticWeights) :: w
    type(DiagnosticResult) :: dr
    integer :: failures
    failures = 0

    call set_property_model(PROP_CONSTANT)

    ! Known degradation to recover.
    true_deg%mode = "truth"
    true_deg%delta_eta_compressor = 0.018_dp
    true_deg%delta_mdot_fraction  = 0.010_dp
    true_deg%delta_eta_turbine    = 0.012_dp
    true_deg%delta_dP_combustor   = 0.003_dp

    truth = solve_cycle(apply_degradation(base, true_deg))
    obs%net_power_MW          = truth%net_power_MW
    obs%exhaust_temperature_K = truth%exhaust_temperature_K
    obs%fuel_flow_kg_s        = truth%fuel_flow_kg_s
    obs%T_compressor_out_K    = truth%T2_K

    w = default_weights()
    dr = diagnose(base, obs, w, n_grid=8)

    call expect_true("diagnosis succeeded", dr%success, failures)
    call expect_true("objective small", dr%objective < 1.0e-4_dp, failures)

    ! Recover each knob within an absolute tolerance. Tolerances reflect the mild
    ! degeneracy between compressor-fouling and mass-flow effects on observables.
    call expect_near("recover delta_eta_compressor", &
        dr%estimate%delta_eta_compressor, true_deg%delta_eta_compressor, 0.004_dp, failures)
    call expect_near("recover delta_mdot_fraction", &
        dr%estimate%delta_mdot_fraction, true_deg%delta_mdot_fraction, 0.004_dp, failures)
    call expect_near("recover delta_eta_turbine", &
        dr%estimate%delta_eta_turbine, true_deg%delta_eta_turbine, 0.004_dp, failures)
    call expect_near("recover delta_dP_combustor", &
        dr%estimate%delta_dP_combustor, true_deg%delta_dP_combustor, 0.004_dp, failures)

    call finish("test_diagnostics", failures)
contains
    include "test_assert.inc"
end program test_diagnostics
