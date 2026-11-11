!> Synthetic parser fixture ONLY. Never an actual turbine observation.
program test_measured_turbine_replay
    use precision_kinds, only: dp
    use measured_turbine_replay
    implicit none
    type(MeasuredReplay) :: r
    logical :: ok
    integer :: u,i,year,source_row,fails
    character(len=*),parameter :: path='build/test_measured_replay_fixture.csv'
    character(len=*),parameter :: header = &
        'year,within_year_row,observed_AT_degC,observed_AP_mbar,observed_AFDP_mbar,'// &
        'observed_TIT_degC,observed_TAT_degC,measured_TEY_source_units,'// &
        'predicted_TEY_source_units,training_mean_baseline_TEY_source_units,'// &
        'residual_measured_minus_prediction_source_units,outside_training_feature_ranges,'// &
        'large_residual_relative_to_training_3sigma'
    fails=0
    call replay_load('build/not-present-replay.csv',r,ok)
    call ck('missing real CSV produces NO DATA',.not.ok.and.r%n==0)
    open(newunit=u,file=path,status='replace',action='write')
    write(u,'(A)') header
    do i=1,REPLAY_EXPECTED_N
        year=2014;source_row=i
        if(i>7158) then
            year=2015;source_row=i-7158
        end if
        write(u,'(I0,",",I0,",",A)') year,source_row, &
            '20,1013,3,1080,530,131,130,125,1,0,0'
    end do
    close(u)
    call replay_load(path,r,ok)
    call ck('full exact ordered fixture imported',ok.and.r%n==REPLAY_EXPECTED_N)
    call ck('source-year boundary preserved',r%year(7158)==2014.and.r%year(7159)==2015)
    call ck('no measured data pushed to plant',r%index==1)
    call replay_seek(r,-10)
    call ck('lower cursor clamp',r%index==1)
    call replay_seek(r,REPLAY_EXPECTED_N+5)
    call ck('upper cursor clamp',r%index==REPLAY_EXPECTED_N)
    call replay_clear(r)
    call ck('clear removes source arrays',r%n==0.and..not.allocated(r%measured))
    open(newunit=u,file=path,status='replace',action='write')
    write(u,'(A)') header
    write(u,'(A)') '2015,1,20,1013,3,1080,530,131,130,125,1,0,0'
    close(u)
    call replay_load(path,r,ok)
    call ck('out-of-order / short input fails closed',.not.ok.and.r%n==0)
    open(newunit=u,file=path,status='delete')
    close(u)
    if(fails/=0) then
        write(*,'(A,I0)') 'FAIL measured replay parser checks: ',fails
        stop 1
    end if
    print '(A)', 'PASS measured replay (synthetic I/O contract tests only)'
contains
    subroutine ck(label,pass)
        character(len=*),intent(in) :: label
        logical,intent(in) :: pass
        if(pass) then
            print '(A)', 'PASS '//label
        else
            fails=fails+1
            print '(A)', 'FAIL '//label
        end if
    end subroutine ck
end program test_measured_turbine_replay
