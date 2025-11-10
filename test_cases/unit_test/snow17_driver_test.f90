!
! This program tests the BMI functionality in Fortran
! The generic code can be used in any BMI-implemented Fortran model
! 
! Adapted by Zhengtao Cui (Zhengtao.Cui@noaa.gov) from the noah-owp-modular
! unit testing code at https://github.com/NOAA-OWP/noah-owp-modular.git 
! 
! Added the unimplemented BMI 2.0 functions to be BMI 2.0 compliant. These
! functions will return `BMI_FAILURE` once envoked.
!

program snow17_driver_test

  !---------------------------------------------------------------------
  !  Modules
  !  Change from non-BMI: Only BMI modules need to be exposed
  !  The rest are used in ../src/NoahMPSurfaceModule.f90
  !---------------------------------------------------------------------
  use bmi_snow17_module
  use bmif_2_0
  use dateTimeUtilsModule
  use, intrinsic :: ieee_arithmetic
  use, intrinsic :: ieee_exceptions

  implicit none

  !---------------------------------------------------------------------
  !  Types
  !  Change from non-BMI: only the bmi_noahowp type needed
  !  Forcing, Energy, Water, etc. not needed
  !---------------------------------------------------------------------
    type (bmi_snow17)  :: m
  
  !---------------------------------------------------------------------
  !  Local variable(s) for BMI testing
  !---------------------------------------------------------------------
    character (len = 80)                              :: arg              ! command line argument for config file
    integer                                           :: status           ! returning status values
    character (len = BMI_MAX_COMPONENT_NAME), pointer :: component_name   ! component name
    integer                                           :: count            ! var counts
    character (len = BMI_MAX_VAR_NAME), pointer       :: names_inputs(:)  ! var names
    character (len = BMI_MAX_VAR_NAME), pointer       :: names_outputs(:) ! var names
    integer                                           :: n_inputs         ! n input vars
    integer                                           :: n_outputs        ! n output vars
    integer                                           :: iBMI             ! loop counter
    character (len = 20)                              :: var_type         ! name of variable type
    character (len = 10)                              :: var_units        ! variable units
    integer                                           :: var_itemsize     ! memory size per var array element
    integer                                           :: var_nbytes       ! memory size over full var array
    character (len = BMI_MAX_VAR_NAME)                :: current_var_name ! scratch var name holder
    double precision                                  :: timestep         ! timestep
    double precision                                  :: bmi_time         ! time output from BMI functions
    double precision                                  :: time_until       ! time to which update until should run
    double precision                                  :: end_time         ! time of last model time step
    double precision                                  :: current_time     ! current model time
    character (len = 1 )                              :: ts_units         ! timestep units (widened for safety)
    double precision, allocatable, target             :: var_value_get(:) ! value of a variable
    double precision, allocatable                     :: var_value_set(:) ! value of a variable
    double precision                                  :: replacement_value ! scalar used when assigning arrays
    integer                                           :: grid_int         ! grid value
    character (len = 20)                              :: grid_type        ! name of grid type
    integer                                           :: grid_rank        ! rank of grid
    integer, dimension(2)                             :: grid_shape       ! shape of grid (change dims if not X * Y grid)
    integer                                           :: j                ! generic index
    integer                                           :: grid_size        ! size of grid (ie. nX * nY)
    double precision, dimension(2)                    :: grid_spacing     ! resolution of grid in X & Y (change dims if not X * Y grid)
    double precision, dimension(2)                    :: grid_origin      ! X & Y origin of grid (change dims if not X * Y grid)
    double precision, dimension(1)                    :: grid_x           ! X coordinate of grid nodes (change dims if multiple nodes)
    double precision, dimension(1)                    :: grid_y           ! Y coordinate of grid nodes (change dims if multiple nodes)
    double precision, dimension(1)                    :: grid_z           ! Y coordinate of grid nodes (change dims if multiple nodes)
    
    double precision, pointer                         :: var_value_get_ptr(:) ! value of a variable for get_value_ptr

    integer, dimension(3)                             :: grid_indices       ! grid indices (change dims as needed)
    logical                                           :: overall_passed    ! overall test status
    logical                                           :: had_failure       ! latch for fatal errors
  !---------------------------------------------------------------------
  !  Initialize
  !---------------------------------------------------------------------
    print*, "Initializing..."
    call get_command_argument(1, arg)
    overall_passed = .true.
    had_failure = .false.
    status = m%initialize(arg)
    call assert_success('initialize', status)
    if (had_failure) goto 900

  !---------------------------------------------------------------------
  ! Get model information
  ! component_name and input/output_var
  !---------------------------------------------------------------------
    status = m%get_component_name(component_name)
    call assert_success('get_component_name', status)
    print*, "Component name = ", trim(component_name)

    status = m%get_input_item_count(count)
    call assert_success('get_input_item_count', status)
    print*, "Total input vars = ", count
    n_inputs = count

    status = m%get_output_item_count(count)
    call assert_success('get_output_item_count', status)
    print*, "Total output vars = ", count
    n_outputs = count

    status = m%get_input_var_names(names_inputs)
    call assert_success('get_input_var_names', status)
    do iBMI = 1, n_inputs
      print*, "Input var = ", trim(names_inputs(iBMI))
    end do
    if (had_failure) goto 900

    status = m%get_output_var_names(names_outputs)
    call assert_success('get_output_var_names', status)
    do iBMI = 1, n_outputs
      print*, "Output var = ", trim(names_outputs(iBMI))
    end do
    if (had_failure) goto 900
    
    ! Sum input and outputs to get total vars
    count = n_inputs + n_outputs
    
    ! Get other variable info
    do j = 1, count
      if (j <= n_inputs) then
        current_var_name = trim(names_inputs(j))
      else
        current_var_name = trim(names_outputs(j - n_inputs))
      end if

      status = m%get_var_type(trim(current_var_name), var_type)
      call assert_success('get_var_type('//trim(current_var_name)//')', status)
      status = m%get_var_units(trim(current_var_name), var_units)
      call assert_success('get_var_units('//trim(current_var_name)//')', status)
      status = m%get_var_itemsize(trim(current_var_name), var_itemsize)
      call assert_success('get_var_itemsize('//trim(current_var_name)//')', status)
      status = m%get_var_nbytes(trim(current_var_name), var_nbytes)
      call assert_success('get_var_nbytes('//trim(current_var_name)//')', status)
      print*, "The variable ", trim(current_var_name)
      print*, "    has a type of ", var_type
      print*, "    units of ", var_units
      print*, "    a size of ", var_itemsize
      print*, "    and total n bytes of ", var_nbytes
    end do
    if (had_failure) goto 900

    
  !---------------------------------------------------------------------
  ! Get time information
  !---------------------------------------------------------------------
  status = m%get_start_time(bmi_time)
  call assert_success('get_start_time', status)
    print*, "The start time is ", bmi_time

  status = m%get_current_time(bmi_time)
  call assert_success('get_current_time', status)
    print*, "The current time is ", bmi_time

  status = m%get_end_time(bmi_time)
  call assert_success('get_end_time', status)
    print*, "The end time is ", bmi_time

  status = m%get_time_step(timestep)
  call assert_success('get_time_step', status)
  status = m%get_time_units(ts_units)
  call assert_success('get_time_units', status)
    print*, " The time step is ", timestep
    print*, "with a unit of ", ts_units
    if (had_failure) goto 900

  !---------------------------------------------------------------------
  ! Run some time steps with the update_until function
  !---------------------------------------------------------------------
    status = m%get_current_time(current_time)
    call assert_success('get_current_time before update_until', status)
    if (status == BMI_SUCCESS) then
      time_until = current_time + timestep
      status = m%update_until(time_until)
      call assert_success('update_until', status)
    end if
    if (had_failure) goto 900
    
  !---------------------------------------------------------------------
  ! Run the rest of the time with update in a loop
  !---------------------------------------------------------------------
    ! get the current and end time for running the execution loop
    status = m%get_current_time(current_time)
    call assert_success('get_current_time pre-loop', status)
    status = m%get_end_time(end_time)
    call assert_success('get_end_time pre-loop', status)
    if (had_failure) goto 900
  
    ! loop through while current time <= end time
    print*, "Running..."
    do while (current_time < end_time)
      status = m%update()                       ! run the model one time step
      call assert_success('update', status)
      if (status /= BMI_SUCCESS) exit
      status = m%get_current_time(current_time) ! update current_time
      call assert_success('get_current_time(loop)', status)
      if (status /= BMI_SUCCESS) exit
      if (had_failure) exit
    end do
    if (had_failure) goto 900

  !---------------------------------------------------------------------
  ! Test the get/set_value functionality with BMI
  !---------------------------------------------------------------------
    allocate(var_value_get(1))
    allocate(var_value_set(1))
    
    ! Loop through the input vars
    do iBMI = 1, n_inputs
      status = m%get_value(trim(names_inputs(iBMI)), var_value_get)
      call assert_success('get_value('//trim(names_inputs(iBMI))//')', status)
      if (status /= BMI_SUCCESS) cycle
      call ensure_size(var_value_set, size(var_value_get))
      print*, trim(names_inputs(iBMI)), " from get_value = ", var_value_get

      ! Only set a safe subset of inputs to avoid invalid model states
      if (can_set_var(trim(names_inputs(iBMI)))) then
        call get_test_value(trim(names_inputs(iBMI)), replacement_value)
        var_value_set = replacement_value
        print*, "    our replacement value = ", var_value_set
        status = m%set_value(trim(names_inputs(iBMI)), var_value_set)
        if (status == BMI_SUCCESS) then
          status = m%get_value(trim(names_inputs(iBMI)), var_value_get)
          call assert_success('get_value('//trim(names_inputs(iBMI))//') (post-set)', status)
          if (status /= BMI_SUCCESS) cycle
          print*, "    and the new value of ", trim(names_inputs(iBMI)), " = ", var_value_get
        else
          print*, "    set_value returned BMI_FAILURE for ", trim(names_inputs(iBMI))
          overall_passed = .false.
          had_failure = .true.
        end if
      else
        print*, "    SKIP: not setting this input in the test (to avoid invalid states)"
      end if
    end do
    
    ! Loop through the output vars (read-only check)
    do iBMI = 1, n_outputs
      status = m%get_value(trim(names_outputs(iBMI)), var_value_get)
      call assert_success('get_value('//trim(names_outputs(iBMI))//')', status)
      if (status /= BMI_SUCCESS) cycle
      print*, trim(names_outputs(iBMI)), " from get_value = ", var_value_get
      ! Do not attempt to set output variables; BMI implementations may
      ! legitimately allow it. We treat outputs as read-only in this test.
    end do
    
    ! Test 3-parameter ADC validation specifically
    call test_3param_adc_validation(m)
    if (had_failure) goto 900
    
    ! Sanity: verify 3-parameter settings recompute 11-pt ADC values
    call test_adc_recompute(m)
    if (had_failure) goto 900
    
  !---------------------------------------------------------------------
  ! The following functions are not implemented/only return BMI_FAILURE
  ! Change if your model implements them
  !---------------------------------------------------------------------
  
    print*, "The unstructured grid functions will return BMI_FAILURE"
    print*, "BMI functions that require ", trim(component_name), &
            " to use pointer vars are not implemented"
  
  !---------------------------------------------------------------------
  ! Test the get_value_ptr functionality with BMI
  !---------------------------------------------------------------------
    var_value_get_ptr => var_value_get
    ! test the get value pointer  functions
    ! Loop through the input vars
    do iBMI = 1, n_inputs
      status = m%get_value_ptr(trim(names_inputs(iBMI)), var_value_get_ptr)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_inputs(iBMI)), " from get_value_ptr returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_inputs(iBMI)), " from get_value_ptr returned ", status, " TEST FAILED!" 
        overall_passed = .false.
        had_failure = .true.
        exit
      end if
    end do
    if (had_failure) goto 900

    ! Loop through the output vars
    do iBMI = 1, n_outputs
      status = m%get_value_ptr(trim(names_outputs(iBMI)), var_value_get_ptr)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_outputs(iBMI)), " from get_value_ptr returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_outputs(iBMI)), " from get_value_ptr returned ", status, " TEST FAILED!" 
        overall_passed = .false.
        had_failure = .true.
        exit
      end if
    end do
    if (had_failure) goto 900

  !---------------------------------------------------------------------
  ! Test the get_value_at_indices functionality with BMI
  !---------------------------------------------------------------------
    ! Initialize grid indices to a safe default for scalar grids
    grid_indices = (/1, 1, 1/)

    ! Loop through the input vars
    do iBMI = 1, n_inputs
      status = m%get_value_at_indices(trim(names_inputs(iBMI)), var_value_get, grid_indices)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_inputs(iBMI)), " from get_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_inputs(iBMI)), " from get_value_at_indices returned ", status, " TEST FAILED!" 
        overall_passed = .false.
        had_failure = .true.
        exit
      end if
      status = m%set_value_at_indices(trim(names_inputs(iBMI)), grid_indices, var_value_set)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_inputs(iBMI)), " from set_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_inputs(iBMI)), " from set_value_at_indices returned ", status, " TEST FAILED!" 
        overall_passed = .false.
        had_failure = .true.
        exit
      end if
    end do
    if (had_failure) goto 900
    
    ! Loop through the output vars
    do iBMI = 1, n_outputs
      status = m%get_value_at_indices(trim(names_outputs(iBMI)), var_value_get, grid_indices)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_outputs(iBMI)), " from get_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_outputs(iBMI)), " from get_value_at_indices returned ", status, " TEST FAILED!" 
        overall_passed = .false.
        had_failure = .true.
        exit
      end if
      status = m%set_value_at_indices(trim(names_outputs(iBMI)), grid_indices, var_value_set)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_outputs(iBMI)), " from set_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_outputs(iBMI)), " from set_value_at_indices returned ", status, " TEST FAILED!" 
        overall_passed = .false.
        had_failure = .true.
        exit
      end if
    end do
    if (had_failure) goto 900

    nullify( var_value_get_ptr )
    deallocate(var_value_get)
    deallocate(var_value_set)

  !---------------------------------------------------------------------
  ! Test the grid info functionality with BMI
  !---------------------------------------------------------------------

    ! All vars currently have same spatial discretization
    ! Modify to test all discretizations if > 1
    
    ! get_var_grid
    iBMI = 1
    status = m%get_var_grid(trim(names_outputs(iBMI)), grid_int)
    print*, "The integer value for the ", trim(names_outputs(iBMI)), " grid is ", grid_int
    
    ! get_grid_type
    status = m%get_grid_type(grid_int, grid_type)
    print*, "The grid type for ", trim(names_outputs(iBMI)), " is ", trim(grid_type)
    
    ! get_grid_rank
    status = m%get_grid_rank(grid_int, grid_rank)
    print*, "The grid rank for ", trim(names_outputs(iBMI)), " is ", grid_rank
    
    ! get_grid_shape
    ! only scalars implemented thus far
    status = m%get_grid_shape(grid_int, grid_shape)
    if(grid_shape(1) == -1) then
      print*, "No grid shape for the grid type/rank"
    end if
    
    ! get_grid_size
    status = m%get_grid_size(grid_int, grid_size)
    print*, "The grid size for ", trim(names_outputs(iBMI)), " is ", grid_size
    
    ! get_grid_spacing
    ! only scalars implemented thus far
    status = m%get_grid_spacing(grid_int, grid_spacing)
    if(grid_spacing(1) == -1.d0) then
      print*, "No grid spacing for the grid type/rank"
    end if
   
    ! get_grid_origin
    ! only scalars implemented thus far
    status = m%get_grid_origin(grid_int, grid_origin)
    if(grid_origin(1) == -1.d0) then
      print*, "No grid origin for the grid type/rank"
    end if
   
    ! get_grid_x/y/z
    ! should return 0 for a 1 node "grid" because not currently spatially explicit
    status = m%get_grid_x(grid_int, grid_x)
    status = m%get_grid_y(grid_int, grid_y)
    status = m%get_grid_z(grid_int, grid_z)
    print*, "The X coord for grid ", grid_int, " is ", grid_x
    print*, "The Y coord for grid ", grid_int, " is ", grid_y
    print*, "The Z coord for grid ", grid_int, " is ", grid_z
    
!---------------------------------------------------------------------
  ! Finalize with BMI
  !---------------------------------------------------------------------
900   continue
      if (overall_passed) then
        print*, "Unit test status: PASS"
      else
        print*, "Unit test status: FAIL"
      end if
      print*, "Finalizing..."
      status = m%finalize()
      call assert_success('finalize', status)
      print*, "Model is finalized!"
      ! Clear any sticky floating-point exception flags before exiting
      call clear_fpe()
      if (overall_passed) then
        stop 0
      else
        stop 1
      end if
contains

  subroutine assert_success(context, status)
    implicit none
    character(len=*), intent(in) :: context
    integer, intent(in) :: status
    if (status /= BMI_SUCCESS) then
      print*, '  FAIL: ', trim(context), ' returned status ', status
      overall_passed = .false.
      had_failure = .true.
    end if
  end subroutine assert_success

  subroutine ensure_size(arr, desired_size)
    implicit none
    double precision, allocatable, intent(inout) :: arr(:)
    integer, intent(in) :: desired_size
    if (desired_size <= 0) return
    if (.not. allocated(arr)) then
      allocate(arr(desired_size))
    else if (size(arr) /= desired_size) then
      deallocate(arr)
      allocate(arr(desired_size))
    end if
  end subroutine ensure_size

  integer function get_var_length(model, var_name) result(len_out)
    implicit none
    type(bmi_snow17), intent(inout) :: model
    character(len=*), intent(in) :: var_name
    integer :: item_size, nbytes, status_local
    len_out = 0
    status_local = model%get_var_itemsize(trim(var_name), item_size)
    call assert_success('get_var_itemsize('//trim(var_name)//')', status_local)
    if (status_local /= BMI_SUCCESS) return
    status_local = model%get_var_nbytes(trim(var_name), nbytes)
    call assert_success('get_var_nbytes('//trim(var_name)//')', status_local)
    if (status_local /= BMI_SUCCESS) return
    if (item_size <= 0) then
      print*, '  FAIL: item size for ', trim(var_name), ' is non-positive (', item_size, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    len_out = nbytes / item_size
  end function get_var_length

  logical function arrays_close(a, b, tol) result(is_close)
    implicit none
    double precision, intent(in) :: a(:), b(:)
    double precision, intent(in) :: tol
    if (size(a) /= size(b)) then
      is_close = .false.
    else
      is_close = maxval(abs(a - b)) <= tol
    end if
  end function arrays_close

  subroutine restore_3param_baseline(model, a_ref, b_ref, c_ref, flag_ref)
    implicit none
    type(bmi_snow17), intent(inout) :: model
    double precision, intent(in) :: a_ref(:), b_ref(:), c_ref(:)
    integer, intent(in), optional :: flag_ref(:)
    integer :: rc

    rc = model%set_value('adc_a', a_ref)
    call assert_success('restore adc_a baseline', rc)
    if (rc /= BMI_SUCCESS) return

    rc = model%set_value('adc_b', b_ref)
    call assert_success('restore adc_b baseline', rc)
    if (rc /= BMI_SUCCESS) return

    rc = model%set_value('adc_c', c_ref)
    call assert_success('restore adc_c baseline', rc)
    if (rc /= BMI_SUCCESS) return

    if (present(flag_ref)) then
      rc = model%set_value('use_3param_adc', flag_ref)
      call assert_success('restore use_3param_adc baseline', rc)
    end if
  end subroutine restore_3param_baseline

  subroutine verify_3param_state(model, adc_ref, a_ref, b_ref, c_ref, flag_ref, tol, context, overall_passed, had_failure)
    implicit none
    type(bmi_snow17), intent(inout) :: model
    double precision, intent(in) :: adc_ref(:), a_ref(:), b_ref(:), c_ref(:)
    integer, intent(in) :: flag_ref(:)
    double precision, intent(in) :: tol
    character(len=*), intent(in) :: context
    logical, intent(inout) :: overall_passed, had_failure
    double precision, allocatable :: temp_real(:)
    integer, allocatable :: temp_int(:)
    integer :: status

    call ensure_size(temp_real, size(adc_ref))
    status = model%get_value('adc', temp_real)
    call assert_success('get_value(adc) during '//trim(context), status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(temp_real, adc_ref, tol)) then
        print*, '  FAIL: ADC curve changed during ', trim(context)
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    call ensure_size(temp_real, size(a_ref))
    status = model%get_value('adc_a', temp_real)
    call assert_success('get_value(adc_a) during '//trim(context), status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(temp_real, a_ref, tol)) then
        print*, '  FAIL: adc_a changed during ', trim(context)
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    call ensure_size(temp_real, size(b_ref))
    status = model%get_value('adc_b', temp_real)
    call assert_success('get_value(adc_b) during '//trim(context), status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(temp_real, b_ref, tol)) then
        print*, '  FAIL: adc_b changed during ', trim(context)
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    call ensure_size(temp_real, size(c_ref))
    status = model%get_value('adc_c', temp_real)
    call assert_success('get_value(adc_c) during '//trim(context), status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(temp_real, c_ref, tol)) then
        print*, '  FAIL: adc_c changed during ', trim(context)
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    if (.not. allocated(temp_int)) then
      allocate(temp_int(size(flag_ref)))
    else if (size(temp_int) /= size(flag_ref)) then
      deallocate(temp_int)
      allocate(temp_int(size(flag_ref)))
    end if
    status = model%get_value('use_3param_adc', temp_int)
    call assert_success('get_value(use_3param_adc) during '//trim(context), status)
    if (status == BMI_SUCCESS) then
      if (.not. all(temp_int == flag_ref)) then
        print*, '  FAIL: use_3param_adc flags changed during ', trim(context)
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
  end subroutine verify_3param_state

  !---------------------------------------------------------------------
  ! Helper subroutine to get appropriate test values for each variable
  !---------------------------------------------------------------------
  subroutine get_test_value(var_name, test_value)
    character(len=*), intent(in) :: var_name
    double precision, intent(out) :: test_value
    
    ! Set appropriate test values based on variable type
    select case (trim(var_name))
      case ('adc_a')
        test_value = 0.15d0    ! Valid range: 0.0-0.25
      case ('adc_b')
        test_value = 2.0d0     ! Valid range: 0.05-50.0
      case ('adc_c')
        test_value = 3.0d0     ! Valid range: 0.5-50.0
      case ('adc1', 'adc2', 'adc3', 'adc4', 'adc5', 'adc6', &
            'adc7', 'adc8', 'adc9', 'adc10', 'adc11')
        test_value = 0.5d0     ! ADC curve values typically 0.0-1.0
      case default
        test_value = 0.0d0      ! Safe default for non-ADC inputs
    end select
    
  end subroutine get_test_value

  !---------------------------------------------------------------------
  ! Helper to whitelist variables that are safe to set in this driver
  !---------------------------------------------------------------------
  logical function can_set_var(var_name)
    character(len=*), intent(in) :: var_name

    can_set_var = .false.
    select case (trim(var_name))
      case ('adc_a','adc_b','adc_c', &
            'adc1','adc2','adc3','adc4','adc5','adc6','adc7','adc8','adc9','adc10','adc11')
        can_set_var = .true.
      case default
        can_set_var = .false.
    end select
  end function can_set_var

  !---------------------------------------------------------------------
  ! Test 3-parameter ADC validation with invalid values
  !---------------------------------------------------------------------
  subroutine test_3param_adc_validation(model)
    implicit none
    type(bmi_snow17), intent(inout) :: model
  double precision, allocatable :: adc_before(:), adc_current(:)
  double precision, allocatable :: adc_a_baseline(:), adc_b_baseline(:), adc_c_baseline(:)
  double precision, allocatable :: working(:), new_a(:), new_b(:), new_c(:)
  integer, allocatable :: baseline_flags(:), flags(:)
  integer :: status, adc_len, n_hru, n_points, i, j
    double precision :: tol
    double precision :: invalid_scalar
  double precision, parameter :: expected_curve(11) = (/0.05d0, 0.10d0, 0.20d0, 0.30d0, 0.40d0, 0.50d0, 0.60d0, 0.70d0, 0.80d0, 0.90d0, 1.00d0/)
  logical, parameter :: verbose_adc_output = .true.

    print*, ""
    print*, "Testing 3-parameter ADC validation..."

    tol = 1.0e-8
    adc_len = get_var_length(model, 'adc')
    if (adc_len <= 0) then
      print*, "  FAIL: Could not determine ADC length for validation."
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    n_hru = get_var_length(model, 'adc_a')
    if (n_hru <= 0) then
      print*, "  FAIL: Could not determine number of HRUs for 3-parameter validation."
      overall_passed = .false.
      had_failure = .true.
      return
    end if

  allocate(adc_before(adc_len), adc_current(adc_len))
    allocate(adc_a_baseline(n_hru), adc_b_baseline(n_hru), adc_c_baseline(n_hru))
  allocate(working(n_hru), new_a(n_hru), new_b(n_hru), new_c(n_hru))
    allocate(baseline_flags(n_hru), flags(n_hru))

    n_points = adc_len / max(1, n_hru)
    if (n_points * max(1, n_hru) /= adc_len) then
      print*, "  FAIL: ADC array length does not divide evenly by HRU count."
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%get_value('adc', adc_before)
    call assert_success('get_value(adc baseline)', status)
    if (status /= BMI_SUCCESS) return

    status = model%get_value('adc_a', adc_a_baseline)
    call assert_success('get_value(adc_a baseline)', status)
    if (status /= BMI_SUCCESS) return

    status = model%get_value('adc_b', adc_b_baseline)
    call assert_success('get_value(adc_b baseline)', status)
    if (status /= BMI_SUCCESS) return

    status = model%get_value('adc_c', adc_c_baseline)
    call assert_success('get_value(adc_c baseline)', status)
    if (status /= BMI_SUCCESS) return

    status = model%get_value('use_3param_adc', baseline_flags)
    call assert_success('get_value(use_3param_adc baseline)', status)
    if (status /= BMI_SUCCESS) return

    ! Invalid adc_a values
    working = adc_a_baseline
    invalid_scalar = -0.1
    working(1) = invalid_scalar
    status = model%set_value('adc_a', working)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_a = ", invalid_scalar
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'adc_a below range', overall_passed, had_failure)
    else
      print*, "  FAIL: Failed to reject invalid adc_a = ", invalid_scalar
      overall_passed = .false.
      had_failure = .true.
  call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
      return
    end if
    if (had_failure) return

    working = adc_a_baseline
    invalid_scalar = 0.30
    working(1) = invalid_scalar
    status = model%set_value('adc_a', working)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_a = ", invalid_scalar
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'adc_a above range', overall_passed, had_failure)
    else
      print*, "  FAIL: Failed to reject invalid adc_a = ", invalid_scalar
      overall_passed = .false.
      had_failure = .true.
  call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
      return
    end if
    if (had_failure) return

    ! Invalid adc_b values
    working = adc_b_baseline
    invalid_scalar = 0.01
    working(1) = invalid_scalar
    status = model%set_value('adc_b', working)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_b = ", invalid_scalar
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'adc_b below range', overall_passed, had_failure)
    else
      print*, "  FAIL: Failed to reject invalid adc_b = ", invalid_scalar
      overall_passed = .false.
      had_failure = .true.
  call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
      return
    end if
    if (had_failure) return

    working = adc_b_baseline
    invalid_scalar = 55.0
    working(1) = invalid_scalar
    status = model%set_value('adc_b', working)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_b = ", invalid_scalar
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'adc_b above range', overall_passed, had_failure)
    else
      print*, "  FAIL: Failed to reject invalid adc_b = ", invalid_scalar
      overall_passed = .false.
      had_failure = .true.
  call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
      return
    end if
    if (had_failure) return

    ! Invalid adc_c values
    working = adc_c_baseline
    invalid_scalar = 0.10
    working(1) = invalid_scalar
    status = model%set_value('adc_c', working)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_c = ", invalid_scalar
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'adc_c below range', overall_passed, had_failure)
    else
      print*, "  FAIL: Failed to reject invalid adc_c = ", invalid_scalar
      overall_passed = .false.
      had_failure = .true.
  call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
      return
    end if
    if (had_failure) return

    working = adc_c_baseline
    invalid_scalar = 55.0
    working(1) = invalid_scalar
    status = model%set_value('adc_c', working)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_c = ", invalid_scalar
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'adc_c above range', overall_passed, had_failure)
    else
      print*, "  FAIL: Failed to reject invalid adc_c = ", invalid_scalar
      overall_passed = .false.
      had_failure = .true.
  call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
      return
    end if
    if (had_failure) return

    ! Compose distinct valid values for all HRUs to exercise vector setters
    do i = 1, n_hru
      new_a(i) = min(0.24, 0.10 + 0.02*real(i))
      new_b(i) = min(45.0, 1.50 + 0.75*real(i))
      new_c(i) = min(45.0, 2.00 + 0.50*real(i))
    end do

    status = model%set_value('adc_a', new_a)
    if (status == BMI_SUCCESS) then
      print*, '  PASS: Correctly accepted valid adc_a values.'
    else
      print*, '  FAIL: Failed to accept valid adc_a values (status = ', status, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%set_value('adc_b', new_b)
    if (status == BMI_SUCCESS) then
      print*, '  PASS: Correctly accepted valid adc_b values.'
    else
      print*, '  FAIL: Failed to accept valid adc_b values (status = ', status, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%set_value('adc_c', new_c)
    if (status == BMI_SUCCESS) then
      print*, '  PASS: Correctly accepted valid adc_c values.'
    else
      print*, '  FAIL: Failed to accept valid adc_c values (status = ', status, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%get_value('adc_a', working)
    call assert_success('get_value(adc_a post-valid)', status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(working, new_a, tol)) then
        print*, '  FAIL: adc_a values do not match requested valid set.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return
    adc_a_baseline = working

    status = model%get_value('adc_b', working)
    call assert_success('get_value(adc_b post-valid)', status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(working, new_b, tol)) then
        print*, '  FAIL: adc_b values do not match requested valid set.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return
    adc_b_baseline = working

    status = model%get_value('adc_c', working)
    call assert_success('get_value(adc_c post-valid)', status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(working, new_c, tol)) then
        print*, '  FAIL: adc_c values do not match requested valid set.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return
    adc_c_baseline = working

    status = model%get_value('adc', adc_current)
    call assert_success('get_value(adc post-valid)', status)
    if (status == BMI_SUCCESS) then
      if (.not. any(abs(adc_current - adc_before) > tol)) then
        print*, '  FAIL: 11-point ADC did not change after valid 3-parameter updates.'
        overall_passed = .false.
        had_failure = .true.
      else
        print*, '  PASS: 11-point ADC recomputed after valid 3-parameter updates.'
      end if
      adc_before = adc_current
    end if
    if (had_failure) return

    status = model%get_value('use_3param_adc', flags)
    call assert_success('get_value(use_3param_adc post-valid)', status)
    if (status == BMI_SUCCESS) then
      if (.not. all(flags == 1)) then
        print*, '  FAIL: Expected use_3param_adc == 1 for all HRUs after valid update.'
        overall_passed = .false.
        had_failure = .true.
      else
        print*, '  PASS: use_3param_adc asserted for all HRUs.'
      end if
      baseline_flags = flags
    end if

    ! Test 1: adc_a=0.25, adc_b=0.05, adc_c=0.5
    print*, ""
    print*, "Testing 3-parameter ADC computation - Test 1..."
    print*, "  Setting adc_a=0.25, adc_b=0.05, adc_c=0.5"
    
    new_a(:) = 0.25
    new_b(:) = 0.05
    new_c(:) = 0.5
    
    status = model%set_value('adc_a', new_a)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_a=0.25"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%set_value('adc_b', new_b)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_b=0.05"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%set_value('adc_c', new_c)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_c=0.5"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%get_value('adc', adc_current)
    call assert_success('get_value(adc test 1)', status)
    if (status == BMI_SUCCESS) then
      if (verbose_adc_output) then
        do i = 1, n_hru
          print*, "  HRU ", i, " 11-point ADC values:" 
          do j = 1, n_points
            print '(A,I2,A,I0,A,F10.6)', "    adc", j, " (HRU ", i, ") = ", &
              adc_current((i-1)*n_points + j)
          end do
        end do
      end if
      print*, "  PASS: Test 1 completed."
    end if

    ! Test 2: adc_a=0.0, adc_b=1.0, adc_c=1.0
    print*, ""
    print*, "Testing 3-parameter ADC computation - Test 2..."
    print*, "  Setting adc_a=0.0, adc_b=1.0, adc_c=1.0"
    
    new_a(:) = 0.0
    new_b(:) = 1.0
    new_c(:) = 1.0
    
    status = model%set_value('adc_a', new_a)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_a=0.0"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%set_value('adc_b', new_b)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_b=1.0"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%set_value('adc_c', new_c)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_c=1.0"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%get_value('adc', adc_current)
    call assert_success('get_value(adc test 2)', status)
    if (status == BMI_SUCCESS) then
      if (n_points /= size(expected_curve)) then
        print*, "  FAIL: Unexpected number of ADC support points (", n_points, ") in test 2."
        overall_passed = .false.
        had_failure = .true.
      else
        do i = 1, n_hru
          if (verbose_adc_output) then
            print*, "  HRU ", i, " 11-point ADC values:" 
            do j = 1, n_points
              print '(A,I2,A,I0,A,F10.6)', "    adc", j, " (HRU ", i, ") = ", &
                adc_current((i-1)*n_points + j)
            end do
          end if
          ! Verify each ADC value matches the expected values
          do j = 1, n_points
            if (abs(adc_current((i-1)*n_points + j) - expected_curve(j)) > tol) then
              print '(A,I0,A,I2,A,F10.6,A,F10.6)', "  FAIL: HRU ", i, " adc", j, &
                " = ", adc_current((i-1)*n_points + j), " (expected ", expected_curve(j), ")"
              overall_passed = .false.
              had_failure = .true.
            end if
          end do
          if (.not. had_failure) then
            print '(A,I0,A)', "  PASS: HRU ", i, " ADC values match expected values."
          end if
        end do
        if (.not. had_failure) then
          print*, '  PASS: Test 2 values match expected evenly spaced curve.'
        end if
      end if
      if (.not. had_failure) then
        print*, "  PASS: Test 2 completed."
      end if
    end if

    ! Test 3: adc_a=0.25, adc_b=6.0, adc_c=6.0
    print*, ""
    print*, "Testing 3-parameter ADC computation - Test 3..."
    print*, "  Setting adc_a=0.25, adc_b=6.0, adc_c=6.0"
    
    new_a(:) = 0.25
    new_b(:) = 6.0
    new_c(:) = 6.0
    
    status = model%set_value('adc_a', new_a)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_a=0.25"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%set_value('adc_b', new_b)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_b=6.0"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%set_value('adc_c', new_c)
    if (status /= BMI_SUCCESS) then
      print*, "  FAIL: Could not set adc_c=6.0"
      overall_passed = .false.
      had_failure = .true.
      return
    end if
    
    status = model%get_value('adc', adc_current)
    call assert_success('get_value(adc test 3)', status)
    if (status == BMI_SUCCESS) then
      if (verbose_adc_output) then
        do i = 1, n_hru
          print*, "  HRU ", i, " 11-point ADC values:" 
          do j = 1, n_points
            print '(A,I2,A,I0,A,F10.6)', "    adc", j, " (HRU ", i, ") = ", &
              adc_current((i-1)*n_points + j)
          end do
        end do
      end if
      print*, "  PASS: Test 3 completed."
    end if

    ! Restore baseline state so subsequent tests start with expected configuration
    call restore_3param_baseline(model, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags)
    if (.not. had_failure) then
      call verify_3param_state(model, adc_before, adc_a_baseline, adc_b_baseline, adc_c_baseline, baseline_flags, tol, 'post-validation restoration', overall_passed, had_failure)
    end if

    print*, ""
    print*, "3-parameter ADC validation testing complete."
    print*, ""

  end subroutine test_3param_adc_validation

  !---------------------------------------------------------------------
  ! Test that setting 3-parameter values recomputes 11-pt ADC curve
  !---------------------------------------------------------------------
  subroutine test_adc_recompute(model)
    type(bmi_snow17), intent(inout) :: model
    double precision, allocatable :: adc_before(:), adc_after(:)
    double precision, allocatable :: new_a(:), new_b(:), new_c(:), slice(:)
    double precision, allocatable :: current(:)
    integer, allocatable :: flags(:)
    integer :: status, adc_len, n_hru, n_points, i
    double precision, parameter :: tol = 1.0e-6

    print*, "Testing ADC recomputation after 3-parameter update..."

    adc_len = get_var_length(model, 'adc')
    if (adc_len <= 0) then
      print*, '  SKIP: ADC array not exposed; skipping recompute test.'
      return
    end if

    n_hru = get_var_length(model, 'adc_a')
    if (n_hru <= 0) then
      print*, '  FAIL: Unable to determine HRU count for recompute test.'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    if (mod(adc_len, n_hru) /= 0) then
      print*, '  FAIL: ADC array length does not divide evenly across HRUs.'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    n_points = adc_len / max(1, n_hru)
    if (n_points <= 0) then
      print*, '  FAIL: Invalid ADC discretization detected.'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    allocate(adc_before(adc_len), adc_after(adc_len))
    allocate(new_a(n_hru), new_b(n_hru), new_c(n_hru))
    allocate(slice(n_points), current(n_hru), flags(n_hru))

    status = model%get_value('adc', adc_before)
    call assert_success('get_value(adc before recompute)', status)
    if (status /= BMI_SUCCESS) return

    do i = 1, n_hru
      new_a(i) = min(0.23, 0.14 + 0.01*real(i))
      new_b(i) = min(40.0, 2.25 + 0.60*real(i))
      new_c(i) = min(40.0, 3.40 + 0.55*real(i))
    end do

    status = model%set_value('adc_a', new_a)
    if (status /= BMI_SUCCESS) then
      print*, '  FAIL: Could not apply recompute adc_a vector (status = ', status, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%set_value('adc_b', new_b)
    if (status /= BMI_SUCCESS) then
      print*, '  FAIL: Could not apply recompute adc_b vector (status = ', status, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%set_value('adc_c', new_c)
    if (status /= BMI_SUCCESS) then
      print*, '  FAIL: Could not apply recompute adc_c vector (status = ', status, ')'
      overall_passed = .false.
      had_failure = .true.
      return
    end if

    status = model%get_value('adc', adc_after)
    call assert_success('get_value(adc after recompute)', status)
    if (status /= BMI_SUCCESS) return

    do i = 1, n_hru
      slice = adc_after((i-1)*n_points+1 : i*n_points) - adc_before((i-1)*n_points+1 : i*n_points)
      if (.not. any(abs(slice) > tol)) then
        print*, '  FAIL: HRU ', i, ' ADC ordinates unchanged after recompute.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end do
    if (had_failure) return
    print*, '  PASS: All HRU ADC ordinates changed after recompute.'

    status = model%get_value('adc_a', current)
    call assert_success('get_value(adc_a after recompute)', status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(current, new_a, tol)) then
        print*, '  FAIL: adc_a state mismatch after recompute.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    status = model%get_value('adc_b', current)
    call assert_success('get_value(adc_b after recompute)', status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(current, new_b, tol)) then
        print*, '  FAIL: adc_b state mismatch after recompute.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    status = model%get_value('adc_c', current)
    call assert_success('get_value(adc_c after recompute)', status)
    if (status == BMI_SUCCESS) then
      if (.not. arrays_close(current, new_c, tol)) then
        print*, '  FAIL: adc_c state mismatch after recompute.'
        overall_passed = .false.
        had_failure = .true.
      end if
    end if
    if (had_failure) return

    status = model%get_value('use_3param_adc', flags)
    call assert_success('get_value(use_3param_adc after recompute)', status)
    if (status == BMI_SUCCESS) then
      if (.not. all(flags == 1)) then
        print*, '  FAIL: Expected use_3param_adc == 1 for all HRUs after recompute.'
        overall_passed = .false.
        had_failure = .true.
      else
        print*, '  PASS: use_3param_adc remains asserted for all HRUs.'
      end if
    end if

  end subroutine test_adc_recompute

  !---------------------------------------------------------------------
  ! Clear floating-point exception flags to avoid runtime notes on exit
  !---------------------------------------------------------------------
  subroutine clear_fpe()
    logical :: has_ieee
    has_ieee = ieee_support_datatype(0.0)
    if (has_ieee) then
      call ieee_set_flag(ieee_invalid, .false.)
      call ieee_set_flag(ieee_divide_by_zero, .false.)
      call ieee_set_flag(ieee_overflow, .false.)
      call ieee_set_flag(ieee_underflow, .false.)
      call ieee_set_flag(ieee_inexact, .false.)
    end if
  end subroutine clear_fpe

end program
