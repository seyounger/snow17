module parametersType

use namelistModule, only: namelist_type

implicit none
save

! -- variable declarations

type, public :: parameters_type

  ! Snow17 model params in the snow param file
  character(len = 20), dimension(:), allocatable :: hru_id     ! local hru ids for multiple hrus
  real, dimension(:), allocatable                :: hru_area   ! sq-km, needed for combination & routing conv.
  real, dimension(:), allocatable                :: latitude   ! centroid latitude of hru (decimal degrees)
  real, dimension(:), allocatable                :: elev       ! mean elevation of hru (m)
  real, dimension(:), allocatable                :: scf, mfmax, mfmin, uadj, si, pxtemp
  real, dimension(:), allocatable                :: nmf, tipm, mbase, plwhc, daygm
  real, dimension(:,:), allocatable              :: adc        ! snow depletion curve (hrus, ordinates)
  
  ! 3-parameter ADC option (alternative to 11-point ADC)
  real, dimension(:), allocatable                :: adc_a, adc_b, adc_c ! 3-param ADC: a*x^b+(1-a)*x^c
  logical, dimension(:), allocatable             :: use_3param_adc      ! flag to use 3-param vs 11-point ADC
  
  ! derived vars
  real                                           :: total_area  ! total basin area used in averaging outputs

  contains

    procedure, public  :: initParams
    procedure, public  :: compute_adc_from_3param

end type parameters_type

contains

  subroutine initParams(this, namelist)
  
    use defNamelist

    class(parameters_type), intent(inout)    :: this
    type(namelist_type), intent(in)          :: namelist
    
    ! allocate variables
    allocate(this%hru_id(n_hrus))
    allocate(this%hru_area(n_hrus))
    allocate(this%latitude(n_hrus))
    allocate(this%elev(n_hrus))
    allocate(this%scf(n_hrus))
    allocate(this%mfmax(n_hrus))
    allocate(this%mfmin(n_hrus))
    allocate(this%uadj(n_hrus))
    allocate(this%si(n_hrus))
    allocate(this%pxtemp(n_hrus))
    allocate(this%nmf(n_hrus))
    allocate(this%tipm(n_hrus))
    allocate(this%mbase(n_hrus))
    allocate(this%plwhc(n_hrus))
    allocate(this%daygm(n_hrus))    

    ! Reversed the row and column for this `adc' array such that
    ! we can pass a slice of the array to other subroutines in
    ! a contiguous memory. Otherwise, we will receive warnings
    ! at runtime about creation of a temporary array and the performance
    ! is impaired. The reason is that
    ! Fortran stores arrays as 'column major'. 

    allocate(this%adc(11, n_hrus))    ! 11 points (0.0 to 1.0 in 0.1 increments)
    
    ! allocate 3-parameter ADC arrays
    allocate(this%adc_a(n_hrus))
    allocate(this%adc_b(n_hrus))
    allocate(this%adc_c(n_hrus))
    allocate(this%use_3param_adc(n_hrus))
    
    ! assign defaults (if any)
    this%total_area = huge(1.0)
    this%use_3param_adc(:) = .false.  ! default to 11-point ADC mode
    ! Initialize 3-parameter ADC values to valid defaults
    this%adc_a(:) = 0.125  ! mid-range of 0.0-0.25
    this%adc_b(:) = 1.0    ! valid in range 0.05-8.0
    this%adc_c(:) = 2.0    ! valid in range 0.5-8.0
    
  end subroutine initParams

  ! Compute 11-point ADC from 3-parameter form: adc = a*x^b + (1-a)*x^c
  subroutine compute_adc_from_3param(this, hru_idx)
    class(parameters_type), intent(inout) :: this
    integer, intent(in) :: hru_idx
    
    real :: a, b, c
    real :: x_vals(11)
    real :: adc_step_crawl, adc_sf, adc_x_crawl, adc_y_crawl
    integer :: i, safety_counter
    integer, parameter :: max_iterations = 100000
    
    ! Get the 3 parameters for this HRU
    a = this%adc_a(hru_idx)
    b = this%adc_b(hru_idx)
    c = this%adc_c(hru_idx)
    
    ! Parameter validation against valid ranges
    if (a < 0.0 .or. a > 0.25 .or. b < 0.05 .or. b > 8.0 .or. c < 0.5 .or. c > 8.0) then
      ! Invalid parameters - set valid defaults
      print *, 'Warning: Invalid 3-param ADC parameters detected. Using valid defaults.'
      print *, 'adc_a must be 0.0-0.25, adc_b must be 0.05-8.0, adc_c must be 0.5-8.0'
      a = 0.125  ! mid-range of valid 0.0-0.25
      b = 1.0    ! valid in range 0.05-8.0
      c = 2.0    ! valid in range 0.5-8.0
      this%adc_a(hru_idx) = a
      this%adc_b(hru_idx) = b
      this%adc_c(hru_idx) = c
    end if
    
    ! Standard x values from 0.0 to 1.0 in 0.1 increments
    x_vals = (/ 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 /)
    
    ! Use the NWRFC reverse lookup method to ensure monotonicity
    ! This matches the algorithm in nwsrfs-hydro-models/model-source/sac_snow.f90
    adc_step_crawl = 0.0001
    adc_sf = 1.0 / adc_step_crawl
    adc_x_crawl = 1.0 + adc_step_crawl
    adc_y_crawl = 1.0 + adc_step_crawl
    
    do i = 11, 1, -1
      safety_counter = 0
      do while (int(adc_y_crawl*adc_sf) > int(x_vals(i)*adc_sf) .and. &
                int(adc_x_crawl*adc_sf) > int(0.05*adc_sf) .and. &
                safety_counter < max_iterations)
        adc_x_crawl = adc_x_crawl - adc_step_crawl
        ! Ensure x_crawl stays positive to avoid issues with fractional powers
        if (adc_x_crawl <= 0.0) then
          adc_x_crawl = 0.001
          adc_y_crawl = 0.0
          exit
        else
          adc_y_crawl = a * adc_x_crawl**b + (1.0 - a) * adc_x_crawl**c
        end if
        safety_counter = safety_counter + 1
      end do
      
      if (safety_counter >= max_iterations) then
        print *, 'Warning: ADC computation did not converge for point', i
        this%adc(i, hru_idx) = 0.05 + real(i-1) * 0.95 / 10.0  ! Linear fallback
      else
        this%adc(i, hru_idx) = adc_x_crawl
      end if
    end do
    
    ! Ensure minimum value of 0.05 as per Snow17 manual
    do i = 1, 11
      if (this%adc(i, hru_idx) < 0.05) this%adc(i, hru_idx) = 0.05
      if (this%adc(i, hru_idx) > 1.0) this%adc(i, hru_idx) = 1.0
    end do
    
  end subroutine compute_adc_from_3param

end module parametersType
