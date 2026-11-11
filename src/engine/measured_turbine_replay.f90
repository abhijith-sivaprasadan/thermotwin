!> Read-only historical UCI 551 measured-versus-predicted TEY replay.
!> NEVER writes to GridState, equipment protection or OPC UA.
!> An import from disk is locally UNVERIFIED; only the Python producer audits hashes.
module measured_turbine_replay
    use, intrinsic :: ieee_arithmetic, only: ieee_is_finite
    use, intrinsic :: iso_fortran_env, only: iostat_end
    use precision_kinds, only: dp
    implicit none
    private
    integer, parameter, public :: REPLAY_EXPECTED_N=14542
    integer, parameter :: REPLAY_YEAR14_N=7158
    character(len=*), parameter :: REPLAY_HEADER = &
        "year,within_year_row,observed_AT_degC,observed_AP_mbar,observed_AFDP_mbar,"// &
        "observed_TIT_degC,observed_TAT_degC,measured_TEY_source_units,"// &
        "predicted_TEY_source_units,training_mean_baseline_TEY_source_units,"// &
        "residual_measured_minus_prediction_source_units,outside_training_feature_ranges,"// &
        "large_residual_relative_to_training_3sigma"
    type, public :: MeasuredReplay
        integer :: n=0
        integer :: index=1
        integer, allocatable :: year(:), source_row(:)
        real(dp), allocatable :: measured(:), predicted(:), ambient(:), tit(:), residual(:)
        logical, allocatable :: outside(:)
        character(len=180) :: status="NOT LOADED - generate original UCI replay CSV; no measured data is active"
    end type
    public :: replay_load, replay_seek, replay_clear
contains
    subroutine replay_clear(r)
        type(MeasuredReplay), intent(inout) :: r
        type(MeasuredReplay) :: empty
        r=empty
    end subroutine

    subroutine replay_load(path,r,ok)
        character(len=*), intent(in) :: path
        type(MeasuredReplay), intent(inout) :: r
        logical, intent(out) :: ok
        type(MeasuredReplay) :: work
        integer :: u,ios,i,loaded,yr,row,oof,largeflag,expect_year,expect_row,close_ios
        character(len=1800) :: line
        real(dp) :: at,ap,afdp,tit,tat,actual,pred,baseline,resid
        ok=.false.
        call replay_clear(r)
        open(newunit=u,file=trim(path),status="old",action="read",iostat=ios)
        if(ios/=0) then
            r%status="NO DATA - measured replay CSV absent; run UCI Python producer first"
            return
        end if
        read(u,'(A)',iostat=ios) line
        if(ios/=0.or.trim(line)/=REPLAY_HEADER) then
            r%status="REJECTED - measured replay CSV header does not match v0.1 schema"
            close(u)
            return
        end if
        allocate(work%year(REPLAY_EXPECTED_N),work%source_row(REPLAY_EXPECTED_N))
        allocate(work%measured(REPLAY_EXPECTED_N),work%predicted(REPLAY_EXPECTED_N))
        allocate(work%ambient(REPLAY_EXPECTED_N),work%tit(REPLAY_EXPECTED_N))
        allocate(work%residual(REPLAY_EXPECTED_N),work%outside(REPLAY_EXPECTED_N))
        loaded=0
        do i=1,REPLAY_EXPECTED_N
            read(u,'(A)',iostat=ios) line
            if(ios/=0) exit
            read(line,*,iostat=ios) yr,row,at,ap,afdp,tit,tat,actual,pred,baseline,resid,oof,largeflag
            if(ios/=0) exit
            expect_year=2014
            expect_row=i
            if(i>REPLAY_YEAR14_N) then
                expect_year=2015
                expect_row=i-REPLAY_YEAR14_N
            end if
            if(yr/=expect_year.or.row/=expect_row.or.(oof/=0.and.oof/=1).or. &
               (largeflag/=0.and.largeflag/=1)) then
                ios=-1
                exit
            end if
            if(.not.all(ieee_is_finite([at,ap,afdp,tit,tat,actual,pred,baseline,resid]))) then
                ios=-1
                exit
            end if
            if(at< -60.0_dp.or.at>80.0_dp.or.ap<850.0_dp.or.ap>1150.0_dp.or. &
               afdp<0.0_dp.or.afdp>25.0_dp.or.tit<700.0_dp.or.tit>1300.0_dp.or. &
               tat<300.0_dp.or.tat>800.0_dp.or.actual<0.0_dp.or.actual>300.0_dp) then
                ios=-1
                exit
            end if
            if(abs(actual-pred-resid)>1.0e-6_dp) then
                ios=-1
                exit
            end if
            work%year(i)=yr
            work%source_row(i)=row
            work%measured(i)=actual
            work%predicted(i)=pred
            work%ambient(i)=at
            work%tit(i)=tit
            work%residual(i)=resid
            work%outside(i)=oof==1
            loaded=i
        end do
        if(loaded==REPLAY_EXPECTED_N.and.ios==0) then
            read(u,'(A)',iostat=ios) line
            if(ios/=iostat_end) ios=1
        else
            ios=1
        end if
        close(u,iostat=close_ios)
        if(loaded/=REPLAY_EXPECTED_N.or.ios/=iostat_end.or.close_ios/=0) then
            r%status="REJECTED - CSV row count, source values or ordering invalid"
            return
        end if
        work%n=REPLAY_EXPECTED_N
        work%status="LOCAL UCI 551 REPLAY - read-only; source file hash NOT checked by GUI"
        r=work
        ok=.true.
    end subroutine

    subroutine replay_seek(r,direction)
        type(MeasuredReplay),intent(inout) :: r
        integer,intent(in) :: direction
        if(r%n==0) return
        r%index=max(1,min(r%n,r%index+direction))
    end subroutine
end module measured_turbine_replay
