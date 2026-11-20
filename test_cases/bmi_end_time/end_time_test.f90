! Test: does get_end_time let a BMI caller run every timestep from start_datehr to end_datehr?
!
! The namelist defines N timesteps, start_datehr through end_datehr inclusive. The model is
! run twice, each time with a different loop, and the number of updates is counted:
!
!   1. ngen:     before each update, ngen requires end_time >= current_time + dt when
!                allow_exceed_end_time is false (ngen Bmi_Module_Formulation.cpp:69-73).
!   2. bmi:      the usual BMI loop, do while (current_time < end_time).
!
! Each loop should run exactly N updates and end with current_time == end_time.
! (run_test.sh checks the standalone driver separately, by running the snow17 executable.)
!
! Usage: end_time_test <namelist>
program end_time_test
  use bmi_snow17_module
  use bmif_2_0
  use defNamelist, only: start_datehr, end_datehr
  use dateTimeUtilsModule, only: date_to_unix
  implicit none

  type(bmi_snow17)   :: m
  character(len=400) :: namelist_file
  integer            :: n_expected, n, status, failures
  double precision   :: t_start, t_end, t_cur, dt

  call get_command_argument(1, namelist_file)
  if (len_trim(namelist_file) == 0) namelist_file = 'namelist.input'
  failures = 0

  ! -- number of timesteps defined by the namelist (start_datehr .. end_datehr inclusive)
  status = m%initialize(namelist_file)
  status = m%get_start_time(t_start)
  status = m%get_end_time(t_end)
  status = m%get_time_step(dt)
  n_expected = nint((date_to_unix(end_datehr) - date_to_unix(start_datehr)) / dt) + 1
  print '(a)',       '----'
  print '(a,i0)',    'Timesteps defined by the namelist (start_datehr..end_datehr): ', n_expected
  print '(a,f0.1)',  'get_end_time - get_start_time (s):                            ', t_end - t_start
  print '(a,f0.1)',  'Time after the last timestep would be (s):                    ', &
                      (date_to_unix(end_datehr) + dt) - t_start
  status = m%finalize()

  ! -- 1. ngen-style check before each update
  status = m%initialize(namelist_file)
  n = 0
  do
    status = m%get_current_time(t_cur)
    if (t_end < t_cur + dt) exit                 ! ngen throws "exceeds model end time" here
    status = m%update()
    n = n + 1
    if (n > n_expected + 5) exit
  end do
  status = m%get_current_time(t_cur)
  call report('1. ngen (end_time >= current + dt)', n, t_cur)
  status = m%finalize()

  ! -- 2. standard BMI loop
  status = m%initialize(namelist_file)
  status = m%get_current_time(t_cur)
  n = 0
  do while (t_cur < t_end .and. n <= n_expected + 5)
    status = m%update()
    n = n + 1
    status = m%get_current_time(t_cur)
  end do
  call report('2. bmi  (current < end)', n, t_cur)
  status = m%finalize()

  print '(a)', '----'
  if (failures == 0) then
    print '(a)', 'PASS'
  else
    print '(a,i0,a)', 'FAIL (', failures, ' check(s))'
    error stop 1
  end if

contains

  subroutine report(label, n_run, t_final)
    character(len=*), intent(in) :: label
    integer, intent(in)          :: n_run
    double precision, intent(in) :: t_final
    logical :: ok

    ok = (n_run == n_expected) .and. (t_final == t_end)
    if (.not. ok) failures = failures + 1
    print '(a,t40,a,i0,a,i0,a,f0.1,a,a)', label, 'updates ', n_run, ' of ', n_expected, &
          ', final time - end_time = ', t_final - t_end, ' s  ', merge('ok  ', 'FAIL', ok)
  end subroutine report

end program end_time_test
