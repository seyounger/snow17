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
    this%adc_b(:) = 1.0    ! valid in range 0.05-50.0
    this%adc_c(:) = 2.0    ! valid in range 0.5-50.0
    
  end subroutine initParams

  ! Compute 11-point ADC from 3-parameter form
  ! Formula: snow_cover = a*we_ratio^b + (1-a)*we_ratio^c
  ! where we_ratio = WE/AI ratio [0.0, 0.1, 0.2, ..., 1.0] (independent variable)
  !       snow_cover = areal snow-covered extent (dependent variable, computed ADC values)
  subroutine compute_adc_from_3param(this, hru_idx, success)
    class(parameters_type), intent(inout) :: this
    integer, intent(in) :: hru_idx
    logical, intent(out), optional :: success
    
    real :: a, b, c      ! 3-parameter ADC coefficients
    real :: we_ratio     ! Independent variable: WE/AI ratio [0.0, 0.1, ..., 1.0]
    real :: snow_cover   ! Dependent variable: areal snow-covered extent
    integer :: i
    
    ! Get the 3 parameters for this HRU
    a = this%adc_a(hru_idx)
    b = this%adc_b(hru_idx)
    c = this%adc_c(hru_idx)
    
    ! Validate parameter ranges
    if (a < 0.0 .or. a > 0.25) then
      if (present(success)) success = .false.
      print *, 'Error: adc_a must be between 0.0 and 0.25, got:', a
      return
    end if
    
    if (b < 0.05 .or. b > 50.0) then
      if (present(success)) success = .false.
      print *, 'Error: adc_b must be between 0.05 and 50.0, got:', b
      return
    end if
    
    if (c < 0.5 .or. c > 50.0) then
      if (present(success)) success = .false.
      print *, 'Error: adc_c must be between 0.5 and 50.0, got:', c
      return
    end if
    
    ! Set success if validation passed
    if (present(success)) success = .true.
    
    ! Compute adc: compute snow_cover = a*we_ratio^b + (1-a)*we_ratio^c
    ! where we_ratio represents the WE/AI ratio from 0.0 to 1.0
    do i = 1, 11
      ! we_ratio values from 0.0 to 1.0 in 0.1 increments
      we_ratio = real(i - 1) / 10.0
      
      ! Compute areal extent: snow_cover = a*we_ratio^b + (1-a)*we_ratio^c
      snow_cover = a * we_ratio**b + (1.0 - a) * we_ratio**c
      
      ! Apply minimum threshold of 0.05 as per Snow17 manual
      if (snow_cover < 0.05) snow_cover = 0.05
      if (snow_cover > 1.0) snow_cover = 1.0
      
      ! Store the computed value
      this%adc(i, hru_idx) = snow_cover
    end do
    
  end subroutine compute_adc_from_3param

end module parametersType
