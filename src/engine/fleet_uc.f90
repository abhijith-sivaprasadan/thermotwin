! =============================================================================
! fleet_uc.f90  —  P1 Fleet Unit Commitment + Economic Dispatch
!
! Performs a merit-order UC + ED for the 3-unit fleet every ~4 s:
!   1. Rank units by variable cost (fuel + O&M) ascending → merit order
!   2. Commit cheapest units first until residual demand is met
!   3. Store results in st%fleet_uc_* for the F10 display screen
!
! Uses the same unit parameters as fleet_dispatch (costs updated each tick
! by refresh_fleet_dispatch → update_unit_costs with live GT heat rate).
! =============================================================================
module fleet_uc
    use precision_kinds, only: dp
    use engine_state
    implicit none
    private
    public :: solve_fleet_uc

contains

    subroutine solve_fleet_uc(st)
        type(GridState), intent(inout) :: st
        integer  :: ord(FLEET_N), i, j, k, tmp
        real(dp) :: residual_MW, remaining, take

        do i = 1, FLEET_N
            if (st%fleet_unit_cost_usd_MWh(i) <= 1.0e-9_dp .and. &
                    st%fleet_unit_heat_rate_kJ_kWh(i) > 1.0_dp) then
                st%fleet_unit_cost_usd_MWh(i) = st%fleet_unit_heat_rate_kJ_kWh(i) / 1000.0_dp * &
                    st%fuel_price_usd_gj + st%fleet_unit_var_om_usd_MWh(i)
            end if
        end do

        ! Merit-order sort: ascending variable cost
        ord = [(i, i = 1, FLEET_N)]
        do i = 1, FLEET_N - 1
            do j = 1, FLEET_N - i
                if (st%fleet_unit_cost_usd_MWh(ord(j)) > st%fleet_unit_cost_usd_MWh(ord(j+1))) then
                    tmp = ord(j);  ord(j) = ord(j+1);  ord(j+1) = tmp
                end if
            end do
        end do

        ! Residual demand after renewables + BESS
        residual_MW = max(0.0_dp, st%demand_MW - effective_renewable_MW(st) - st%storage_MW)

        ! Economic dispatch: load cheapest online units first
        st%fleet_uc_commit = 0
        st%fleet_uc_p      = 0.0_dp
        st%fleet_unserved_dispatch_MW = 0.0_dp
        remaining = residual_MW

        do k = 1, FLEET_N
            i = ord(k)
            if (.not. st%fleet_unit_online(i)) cycle
            if (remaining <= 0.0_dp) exit
            st%fleet_uc_commit(i) = 1
            take = min(st%fleet_unit_capacity_MW(i), remaining)
            ! Enforce minimum load (20%) to avoid unrealistic part-load
            if (take < st%fleet_unit_capacity_MW(i) * 0.20_dp) &
                take = min(remaining, st%fleet_unit_capacity_MW(i) * 0.20_dp)
            st%fleet_uc_p(i) = take
            remaining = remaining - take
        end do
        st%fleet_unserved_dispatch_MW = max(0.0_dp, remaining)

        ! Total variable cost $/h + marginal unit (last committed in merit order)
        st%fleet_uc_total_cost_h = 0.0_dp
        st%fleet_marginal_unit   = 0
        st%fleet_lmp_usd_MWh     = 0.0_dp
        do k = 1, FLEET_N
            i = ord(k)
            if (st%fleet_uc_commit(i) == 1) then
                st%fleet_uc_total_cost_h = st%fleet_uc_total_cost_h + &
                    st%fleet_uc_p(i) * st%fleet_unit_cost_usd_MWh(i)
                st%fleet_marginal_unit = i
                st%fleet_lmp_usd_MWh   = st%fleet_unit_cost_usd_MWh(i)
            end if
        end do

        st%fleet_uc_solved = .true.
    end subroutine solve_fleet_uc

end module fleet_uc
