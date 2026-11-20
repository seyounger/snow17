! Test: does update_until(time) advance the model to `time` and stop there?
!
! The namelist defines 6 hourly timesteps of snowfall, so SWE grows every step. Compares
! update_until with the same number of update() calls:
!
!   reference: update() x2, then update() x2 more; records time and sneqv after 2 and 4 updates.
!   1. update_until(start + 2*dt): should succeed and match the reference after 2 updates.
!   2. update_until(start + 4*dt): should succeed and match the reference after 4 updates.
!   3. update_until(current time): should succeed without advancing.
!   4. update_until(start), a time in the past: should return BMI_FAILURE without advancing.
!   5. update_until(end_time + 5*dt), past the end of the run: should return BMI_FAILURE without
!      advancing.
!
! Usage: update_until_test <namelist>
program update_until_test
  use bmi_snow17_module
  use bmif_2_0
  implicit none

  type(bmi_snow17)   :: m
  character(len=400) :: namelist_file
  integer            :: status, failures
  double precision   :: t_start, dt, t_end, t2, t4
  real               :: swe2, swe4          ! sneqv (mm)

  call get_command_argument(1, namelist_file)
  if (len_trim(namelist_file) == 0) namelist_file = 'namelist.input'
  failures = 0

  ! -- reference: update() calls
  status = m%initialize(namelist_file)
  status = m%get_start_time(t_start)
  status = m%get_time_step(dt)
  status = m%get_end_time(t_end)
  status = m%update()
  status = m%update()
  call state(t2, swe2)
  status = m%update()
  status = m%update()
  call state(t4, swe4)
  status = m%finalize()
  print '(a)', '----'
  print '(a,f0.3,a,f0.3)', 'reference sneqv (mm) after 2 updates: ', swe2, ', after 4: ', swe4

  ! -- update_until
  status = m%initialize(namelist_file)
  status = m%update_until(t_start + 2*dt)
  call check('1. update_until(start + 2*dt)', status, BMI_SUCCESS, t2, swe2)
  status = m%update_until(t_start + 4*dt)
  call check('2. update_until(start + 4*dt)', status, BMI_SUCCESS, t4, swe4)
  status = m%update_until(t4)
  call check('3. update_until(current time)', status, BMI_SUCCESS, t4, swe4)
  status = m%update_until(t_start)
  call check('4. update_until(start), in the past', status, BMI_FAILURE, t4, swe4)
  status = m%update_until(t_end + 5*dt)
  call check('5. update_until(end_time + 5*dt)', status, BMI_FAILURE, t4, swe4)
  status = m%finalize()

  print '(a)', '----'
  if (failures == 0) then
    print '(a)', 'PASS'
  else
    print '(a,i0,a)', 'FAIL (', failures, ' check(s))'
    error stop 1
  end if

contains

  subroutine state(t, swe)
    double precision, intent(out) :: t
    real, intent(out)             :: swe
    real    :: v(1)
    integer :: s                              ! local, so callers' status isn't overwritten
    s = m%get_current_time(t)
    s = m%get_value('sneqv', v)
    swe = v(1) * 1000.                        ! m -> mm
  end subroutine state

  subroutine check(label, got_status, want_status, t_want, swe_want)
    character(len=*), intent(in) :: label
    integer, intent(in)          :: got_status, want_status
    double precision, intent(in) :: t_want
    real, intent(in)             :: swe_want
    double precision :: t
    real             :: swe
    logical          :: ok
    call state(t, swe)
    ok = (got_status == want_status) .and. (t == t_want) .and. (swe == swe_want)
    if (.not. ok) failures = failures + 1
    print '(a,t40,a,i0,a,f0.1,a,f0.3,a,f0.3,a,a)', label, 'status ', got_status, &
          ', time - target = ', t - t_want, ' s, sneqv (mm) ', swe, ' (want ', swe_want, ')  ', &
          merge('ok  ', 'FAIL', ok)
  end subroutine check

end program update_until_test
