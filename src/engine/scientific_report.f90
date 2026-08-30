!> [7.0-P7] Scientific analysis report.
!>
!> Aggregates the full 7.0 analysis stack into one human-readable report:
!> exergy / second-law breakdown (P1), Monte-Carlo uncertainty (P4), Sobol global
!> sensitivity (P4), theoretical-limit benchmarking (P6), and data-reconciliation
!> V&V (P5). Writes to any open unit, so the HMI's CSV/PDF exporter can embed it.
module scientific_report
    use precision_kinds,      only: dp
    use engine_state,         only: GridState
    use exergy,               only: ExergyResult, compute_exergy
    use exergy_uq,            only: ExergyUQ, run_exergy_uq
    use exergy_sobol,         only: SobolResult, run_exergy_sobol, SOBOL_NIN
    use thermo_limits,        only: ThermoLimits, compute_thermo_limits
    use data_reconciliation,  only: ReconResult, reconcile_power_balance
    implicit none
    private
    public :: write_scientific_report

contains

    subroutine write_scientific_report(iunit, st)
        integer,         intent(in) :: iunit
        type(GridState), intent(in) :: st
        type(ExergyResult) :: ex
        type(ExergyUQ)     :: uq
        type(SobolResult)  :: sob
        type(ThermoLimits) :: lim
        type(ReconResult)  :: rec
        real(dp) :: sig(SOBOL_NIN)
        character(len=14) :: names(SOBOL_NIN)
        integer :: i

        names = [character(len=14) :: "ambient T", "TIT", "exhaust T", "fuel flow", "press. ratio"]
        sig   = [3.0_dp, 25.0_dp, 15.0_dp, 0.08_dp, 0.5_dp]

        call compute_exergy(st, ex)
        call run_exergy_uq(st, sig(1), sig(2), sig(3), sig(4), sig(5), 2000, uq)
        call run_exergy_sobol(st, sig, 600, 1, sob)
        call compute_thermo_limits(st, lim)
        call reconcile_power_balance(st, rec)

        write(iunit,'(a)') "=========================================================="
        write(iunit,'(a)') " ThermoTwin-F  -  Scientific Analysis Report"
        write(iunit,'(a)') "=========================================================="
        write(iunit,'(a)') ""
        write(iunit,'(a)') "[1] EXERGY / SECOND-LAW ANALYSIS"
        write(iunit,'("  Fuel exergy in         : ",F12.1," kW")') ex%ex_fuel
        write(iunit,'("  Net useful work        : ",F12.1," kW")') ex%w_net
        write(iunit,'("  Rational efficiency II : ",F12.3)')        ex%eta_II
        write(iunit,'("  Destruction compressor : ",F12.1," kW")') ex%dest_comp
        write(iunit,'("  Destruction combustor  : ",F12.1," kW")') ex%dest_comb
        write(iunit,'("  Destruction turbine    : ",F12.1," kW")') ex%dest_turb
        write(iunit,'("  Destruction HRSG/bottom: ",F12.1," kW")') ex%dest_hrsg
        write(iunit,'("  Stack loss             : ",F12.1," kW")') ex%ex_stack
        write(iunit,'("  Balance closure (V&V)  : ",F12.4)')        ex%closure
        write(iunit,'(a)') ""
        write(iunit,'(a)') "[2] UNCERTAINTY QUANTIFICATION  (Monte-Carlo)"
        write(iunit,'("  eta_II = ",F6.3," +/- ",F6.3,"   95% CI [",F6.3,", ",F6.3,"]")') &
            uq%eta_II_mean, uq%eta_II_std, uq%eta_II_lo95, uq%eta_II_hi95
        write(iunit,'("  combustor destruction  = ",F10.1," +/- ",F8.1," kW")') &
            uq%dest_comb_mean, uq%dest_comb_std
        write(iunit,'(a)') ""
        write(iunit,'(a)') "[3] GLOBAL SENSITIVITY  (Sobol, target eta_II)"
        do i = 1, SOBOL_NIN
            write(iunit,'("  ",A14,"  S1 = ",F6.3,"   ST = ",F6.3)') names(i), sob%S1(i), sob%ST(i)
        end do
        write(iunit,'("  dominant driver        : ",A)') trim(names(sob%dominant))
        write(iunit,'(a)') ""
        write(iunit,'(a)') "[4] THEORETICAL LIMITS"
        write(iunit,'("  Carnot                 : ",F12.3)') lim%eta_carnot
        write(iunit,'("  Curzon-Ahlborn         : ",F12.3)') lim%eta_curzon_ahlborn
        write(iunit,'("  Ideal Brayton          : ",F12.3)') lim%eta_brayton_ideal
        write(iunit,'("  Actual (first law)     : ",F12.3)') lim%eta_actual
        write(iunit,'("  Fraction of Carnot     : ",F12.3)') lim%carnot_fraction
        write(iunit,'(a)') ""
        write(iunit,'(a)') "[5] DATA RECONCILIATION / V&V  (power balance)"
        write(iunit,'("  Raw imbalance          : ",F12.4," MW")') rec%imbalance_raw
        write(iunit,'("  Reconciled imbalance   : ",F12.6," MW")') rec%imbalance_rec
        write(iunit,'("  Global test statistic  : ",F12.4)')        rec%test_stat
        write(iunit,'("  Gross error detected   : ",L1)')           rec%gross_error
        write(iunit,'(a)') "=========================================================="
    end subroutine write_scientific_report

end module scientific_report
