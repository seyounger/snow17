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
    double precision                                  :: timestep         ! timestep
    double precision                                  :: bmi_time         ! time output from BMI functions
    double precision                                  :: time_until       ! time to which update until should run
    double precision                                  :: end_time         ! time of last model time step
    double precision                                  :: current_time     ! current model time
  character (len = 32)                              :: ts_units         ! timestep units (widened for safety)
    real, allocatable, target                         :: var_value_get(:) ! value of a variable
    real, allocatable                                 :: var_value_set(:) ! value of a variable
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
    
    real, pointer                                 :: var_value_get_ptr(:) ! value of a variable for get_value_ptr

    integer, dimension(3)                             :: grid_indices       ! grid indices (change dims as needed)
  logical                                           :: overall_passed    ! overall test status
  !---------------------------------------------------------------------
  !  Initialize
  !---------------------------------------------------------------------
    print*, "Initializing..."
    call get_command_argument(1, arg)
    status = m%initialize(arg)
  overall_passed = .true.

  !---------------------------------------------------------------------
  ! Get model information
  ! component_name and input/output_var
  !---------------------------------------------------------------------
    status = m%get_component_name(component_name)
    print*, "Component name = ", trim(component_name)

    status = m%get_input_item_count(count)
    print*, "Total input vars = ", count
    n_inputs = count

    status = m%get_output_item_count(count)
    print*, "Total output vars = ", count
    n_outputs = count

    status = m%get_input_var_names(names_inputs)
    do iBMI = 1, n_inputs
      print*, "Input var = ", trim(names_inputs(iBMI))
    end do

    status = m%get_output_var_names(names_outputs)
    do iBMI = 1, n_outputs
      print*, "Output var = ", trim(names_outputs(iBMI))
    end do
    
    ! Sum input and outputs to get total vars
    count = n_inputs + n_outputs
    
    ! Get other variable info
    do j = 1, count
      if(j <= n_inputs) then
        status = m%get_var_type(trim(names_inputs(j)), var_type)
        status = m%get_var_units(trim(names_inputs(j)), var_units)
        status = m%get_var_itemsize(trim(names_inputs(j)), var_itemsize)
        status = m%get_var_nbytes(trim(names_inputs(j)), var_nbytes)
        print*, "The variable ", trim(names_inputs(j))
      else
        status = m%get_var_type(trim(names_outputs(j - n_inputs)), var_type)
        status = m%get_var_units(trim(names_outputs(j - n_inputs)), var_units)
        status = m%get_var_itemsize(trim(names_outputs(j - n_inputs)), var_itemsize)
        status = m%get_var_nbytes(trim(names_outputs(j - n_inputs)), var_nbytes)
        print*, "The variable ", trim(names_outputs(j - n_inputs))
      end if
      print*, "    has a type of ", var_type
      print*, "    units of ", var_units
      print*, "    a size of ", var_itemsize
      print*, "    and total n bytes of ", var_nbytes
    end do

    
  !---------------------------------------------------------------------
  ! Get time information
  !---------------------------------------------------------------------
    status = m%get_start_time(bmi_time)
    print*, "The start time is ", bmi_time

    status = m%get_current_time(bmi_time)
    print*, "The current time is ", bmi_time

    status = m%get_end_time(bmi_time)
    print*, "The end time is ", bmi_time

    status = m%get_time_step(timestep)
    status = m%get_time_units(ts_units)
    print*, " The time step is ", timestep
    print*, "with a unit of ", ts_units

  !---------------------------------------------------------------------
  ! Run some time steps with the update_until function
  !---------------------------------------------------------------------
    time_until = 3600.0
    status = m%update_until(time_until)
    
  !---------------------------------------------------------------------
  ! Run the rest of the time with update in a loop
  !---------------------------------------------------------------------
    ! get the current and end time for running the execution loop
    status = m%get_current_time(current_time)
    status = m%get_end_time(end_time)
  
    ! loop through while current time <= end time
    print*, "Running..."
    do while (current_time < end_time)
      status = m%update()                       ! run the model one time step
      status = m%get_current_time(current_time) ! update current_time
    end do

  !---------------------------------------------------------------------
  ! Test the get/set_value functionality with BMI
  !---------------------------------------------------------------------
    allocate(var_value_get(1))
    allocate(var_value_set(1))
    
    ! Loop through the input vars
    do iBMI = 1, n_inputs
      status = m%get_value(trim(names_inputs(iBMI)), var_value_get)
      print*, trim(names_inputs(iBMI)), " from get_value = ", var_value_get

      ! Only set a safe subset of inputs to avoid invalid model states
      if (can_set_var(trim(names_inputs(iBMI)))) then
        call get_test_value(trim(names_inputs(iBMI)), var_value_set(1))
        print*, "    our replacement value = ", var_value_set
        status = m%set_value(trim(names_inputs(iBMI)), var_value_set)
        if (status == BMI_SUCCESS) then
          status = m%get_value(trim(names_inputs(iBMI)), var_value_get)
          print*, "    and the new value of ", trim(names_inputs(iBMI)), " = ", var_value_get
        else
          print*, "    set_value returned BMI_FAILURE for ", trim(names_inputs(iBMI))
        end if
      else
        print*, "    SKIP: not setting this input in the test (to avoid invalid states)"
      end if
    end do
    
    ! Loop through the output vars (read-only check)
    do iBMI = 1, n_outputs
      status = m%get_value(trim(names_outputs(iBMI)), var_value_get)
      print*, trim(names_outputs(iBMI)), " from get_value = ", var_value_get
      ! Do not attempt to set output variables; BMI implementations may
      ! legitimately allow it. We treat outputs as read-only in this test.
    end do
    
    ! Test 3-parameter ADC validation specifically
    call test_3param_adc_validation(m)
    
    ! Sanity: verify 3-parameter settings recompute 11-pt ADC values
    call test_adc_recompute(m)
    
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
      end if
    end do

    ! Loop through the output vars
    do iBMI = 1, n_outputs
      status = m%get_value_ptr(trim(names_outputs(iBMI)), var_value_get_ptr)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_outputs(iBMI)), " from get_value_ptr returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_outputs(iBMI)), " from get_value_ptr returned ", status, " TEST FAILED!" 
      end if
    end do

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
      end if
      status = m%set_value_at_indices(trim(names_inputs(iBMI)), grid_indices, var_value_set)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_inputs(iBMI)), " from set_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_inputs(iBMI)), " from set_value_at_indices returned ", status, " TEST FAILED!" 
      end if
    end do
    
    ! Loop through the output vars
    do iBMI = 1, n_outputs
      status = m%get_value_at_indices(trim(names_outputs(iBMI)), var_value_get, grid_indices)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_outputs(iBMI)), " from get_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_outputs(iBMI)), " from get_value_at_indices returned ", status, " TEST FAILED!" 
      end if
      status = m%set_value_at_indices(trim(names_outputs(iBMI)), grid_indices, var_value_set)
      if ( status .eq. BMI_FAILURE ) then
        print*, trim(names_outputs(iBMI)), " from set_value_at_indices returned BMI_FAILURE --- test passed" 
      else
        print*, trim(names_outputs(iBMI)), " from set_value_at_indices returned ", status, " TEST FAILED!" 
      end if
    end do

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
      if (overall_passed) then
        print*, "Unit test status: PASS"
      else
        print*, "Unit test status: FAIL"
      end if
      print*, "Finalizing..."
      status = m%finalize()
      print*, "Model is finalized!"
      ! Clear any sticky floating-point exception flags before exiting
      call clear_fpe()
      if (overall_passed) then
        stop 0
      else
        stop 1
      end if

!  !---------------------------------------------------------------------
!  ! End test
!  !---------------------------------------------------------------------
    print*, "All done testing!"

contains

  !---------------------------------------------------------------------
  ! Helper subroutine to get appropriate test values for each variable
  !---------------------------------------------------------------------
  subroutine get_test_value(var_name, test_value)
    character(len=*), intent(in) :: var_name
    real, intent(out) :: test_value
    
    ! Set appropriate test values based on variable type
    select case (trim(var_name))
      case ('adc_a')
        test_value = 0.15    ! Valid range: 0.0-0.25
      case ('adc_b')
        test_value = 2.0     ! Valid range: 0.05-50.0
      case ('adc_c')
        test_value = 3.0     ! Valid range: 0.5-50.0
      case ('adc1', 'adc2', 'adc3', 'adc4', 'adc5', 'adc6', &
            'adc7', 'adc8', 'adc9', 'adc10', 'adc11')
        test_value = 0.5     ! ADC curve values typically 0.0-1.0
      case default
        test_value = 0.0      ! Safe default for non-ADC inputs
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
    type(bmi_snow17), intent(inout) :: model
    real :: invalid_value(1)
    integer :: status
    
    print*, ""
    print*, "Testing 3-parameter ADC validation..."
    
    ! Test invalid adc_a (outside 0.0-0.25 range)
    invalid_value(1) = -0.1
    status = model%set_value('adc_a', invalid_value)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_a = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to reject invalid adc_a = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    invalid_value(1) = 0.3
    status = model%set_value('adc_a', invalid_value)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_a = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to reject invalid adc_a = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    ! Test invalid adc_b (outside 0.05-50.0 range)
    invalid_value(1) = 0.01
    status = model%set_value('adc_b', invalid_value)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_b = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to reject invalid adc_b = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    invalid_value(1) = 55.0
    status = model%set_value('adc_b', invalid_value)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_b = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to reject invalid adc_b = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    ! Test invalid adc_c (outside 0.5-50.0 range)
    invalid_value(1) = 0.1
    status = model%set_value('adc_c', invalid_value)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_c = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to reject invalid adc_c = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    invalid_value(1) = 55.0
    status = model%set_value('adc_c', invalid_value)
    if (status == BMI_FAILURE) then
      print*, "  PASS: Correctly rejected invalid adc_c = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to reject invalid adc_c = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    ! Test valid values should succeed
    invalid_value(1) = 0.12
    status = model%set_value('adc_a', invalid_value)
    if (status == BMI_SUCCESS) then
      print*, "  PASS: Correctly accepted valid adc_a = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to accept valid adc_a = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    invalid_value(1) = 1.5
    status = model%set_value('adc_b', invalid_value)
    if (status == BMI_SUCCESS) then
      print*, "  PASS: Correctly accepted valid adc_b = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to accept valid adc_b = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    invalid_value(1) = 2.5
    status = model%set_value('adc_c', invalid_value)
    if (status == BMI_SUCCESS) then
      print*, "  PASS: Correctly accepted valid adc_c = ", invalid_value(1)
    else
      print*, "  FAIL: Failed to accept valid adc_c = ", invalid_value(1)
      overall_passed = .false.
    end if
    
    print*, "3-parameter ADC validation testing complete."
    print*, ""
    
  end subroutine test_3param_adc_validation

  !---------------------------------------------------------------------
  ! Test that setting 3-parameter values recomputes 11-pt ADC curve
  !---------------------------------------------------------------------
  subroutine test_adc_recompute(model)
    type(bmi_snow17), intent(inout) :: model
    real :: v_before(1), v_after(1), p(1)
    integer :: status
    real, parameter :: tol = 1.0e-6
    character (len = BMI_MAX_VAR_NAME), pointer :: in_names(:), out_names(:)
    integer :: n_in, n_out, i
    logical :: have_adc5, have_params

    print*, "Testing ADC recomputation after 3-parameter update..."

    have_adc5 = .false.
    have_params = .false.
    status = model%get_input_item_count(n_in)
    status = model%get_output_item_count(n_out)
    status = model%get_input_var_names(in_names)
    status = model%get_output_var_names(out_names)
    do i = 1, n_in
      if (trim(in_names(i)) == 'adc5') have_adc5 = .true.
      if (trim(in_names(i)) == 'adc_a') have_params = .true.
    end do
    do i = 1, n_out
      if (trim(out_names(i)) == 'adc5') have_adc5 = .true.
      if (trim(out_names(i)) == 'adc_a') have_params = .true.
    end do

    if (.not. have_adc5 .or. .not. have_params) then
      print*, '  SKIP: ADC variables not exposed in this configuration; skipping recompute test.'
      return
    end if

    status = model%get_value('adc5', v_before)
    if (status /= BMI_SUCCESS) then
      print*, '  FAIL: Could not get adc5 before update'
      overall_passed = .false.
      return
    end if

    ! Apply a distinct, valid 3-parameter set
    p(1) = 0.20; status = model%set_value('adc_a', p)
    p(1) = 5.00; status = model%set_value('adc_b', p)
    p(1) = 6.00; status = model%set_value('adc_c', p)

    status = model%get_value('adc5', v_after)
    if (status /= BMI_SUCCESS) then
      print*, '  FAIL: Could not get adc5 after update'
      overall_passed = .false.
      return
    end if

    if (abs(v_after(1) - v_before(1)) > tol) then
      print*, '  PASS: adc5 changed after 3-param update: ', v_before(1), ' -> ', v_after(1)
    else
      print*, '  FAIL: adc5 did not change after 3-param update'
      overall_passed = .false.
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
