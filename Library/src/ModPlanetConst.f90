!^CFG COPYRIGHT UM
Module ModPlanetConst
  use ModNumConst
  use ModConst, ONLY: cAU
  use ModKind

  implicit none

  save
  !\
  ! All astronomical bodies other than the Sun are defined below.  
  ! Solar constants are defined in ModConst.
  !
  ! The maximum number of astronomical bodies.  This is set at 100, it can be
  ! increased if necessary
  !/
  integer,parameter :: MaxPlanet = 200

  integer, parameter :: lNamePlanet = 40
  integer, parameter :: lTypeBField = 40

  !\
  ! Declarations for the variables that we are storing to define each body.
  ! 
  ! NOTE THAT ALL VARIABLES IN THIS FILE SHOULD BE IN SI UNITS. 
  !  (m,s,g,m/s, ... )
  !
  ! NOTE THE THE PRECISE DEFINITIONS OF WHAT THE VARIABLES MEAN CAN BE
  ! FOUND AT THE END OF THE FILE AND IN THE CODE DOCUMENTATION (we hope).
  !
  !/
  real,dimension(0:MaxPlanet+1) :: rPlanet_I, mPlanet_I, rOrbitPlanet_I
  real,dimension(0:MaxPlanet+1) :: OrbitalPeriodPlanet_I, RotationPeriodPlanet_I

  integer,dimension(0:MaxPlanet+1) :: iYearEquinoxPlanet_I,iMonthEquinoxPlanet_I, iDayEquinoxPlanet_I
  integer,dimension(0:MaxPlanet+1) :: iHourEquinoxPlanet_I,iMinuteEquinoxPlanet_I,iSecondEquinoxPlanet_I
  real,dimension(0:MaxPlanet+1)    :: FracSecondEquinoxPlanet_I
  real,dimension(0:MaxPlanet+1)    :: TiltPlanet_I

  character (len=lTypeBField) :: TypeBFieldPlanet_I(0:MaxPlanet+1)
  real,dimension(0:MaxPlanet+1) :: DipoleStrengthPlanet_I
  real,dimension(0:MaxPlanet+1) :: bAxisThetaPlanet_I, bAxisPhiPlanet_I

  real,dimension(0:MaxPlanet+1) :: IonoHeightPlanet_I

  character (len=lNamePlanet) :: NamePlanet_I(0:MaxPlanet+1)

  integer :: Planet_ 

  !\
  ! Below are defining constants for all astronomical bodies.  They are
  ! grouped using a system similar to JPL's naif/spice toolkit although
  ! the definitions are not quite the same.
  !/

  !\
  ! First define the storage location for all bodies.  This is so that you
  ! can easily find the index and can also see the naming system
  !/
  ! No Planet (in other words, no body)
  integer,parameter :: NoPlanet_  =  0
  ! New Planet (a body that is not in the database below)
  integer,parameter :: NewPlanet_  =  MaxPlanet+1

  ! Planets and Sun 
  integer,parameter :: Sun_       =  1
  integer,parameter :: Mercury_   = 10
  integer,parameter :: Venus_     = 20
  integer,parameter :: Earth_     = 30
  integer,parameter :: Mars_      = 40
  integer,parameter :: Jupiter_   = 50
  integer,parameter :: Saturn_    = 60
  integer,parameter :: Uranus_    = 70
  integer,parameter :: Neptune_   = 80
  integer,parameter :: Pluto_     = 90

  ! Moons of planets (the order of the moons is not in radial distance)
  integer,parameter :: Moon_      = 31
  integer,parameter :: Io_        = 51
  integer,parameter :: Europa_    = 52
  integer,parameter :: Titan_     = 61

  ! Other solar system bodies (comets, asteroids, extra solar planets) #'s >= 100
  integer,parameter :: Halley_               = 100
  integer,parameter :: Comet1P_              = 100
  integer,parameter :: Borrelly_             = 101
  integer,parameter :: Comet19P_             = 101
  integer,parameter :: ChuryumovGerasimenko_ = 102
  integer,parameter :: Comet67P_             = 102
  integer,parameter :: HaleBopp_             = 103 

contains

   subroutine init_planet_const

     use ModUtilities,     ONLY: upper_case   

     implicit none

     save

     integer :: i

     !\
     ! Set all values to zero - below set only the non-zero values
     !/
     NamePlanet_I(:)                     = ''

     rPlanet_I(:)                        = 0.0                           ! [ m]
     mPlanet_I(:)                        = 0.0                           ! [kg]
     rOrbitPlanet_I(:)                   = 0.0                           ! [ m]
     OrbitalPeriodPlanet_I(:)            = 0.0                           ! [ s]
     RotationPeriodPlanet_I(:)           = 0.0                           ! [ s]
                                            
     iYearEquinoxPlanet_I(:)             =2000                           ! [yr]
     iMonthEquinoxPlanet_I(:)            =   1                           ! [mo]
     iDayEquinoxPlanet_I(:)              =   1                           ! [dy]
     iHourEquinoxPlanet_I(:)             =   0                           ! [hr]
     iMinuteEquinoxPlanet_I(:)           =   0                           ! [mn]
     iSecondEquinoxPlanet_I(:)           =   0                           ! [ s]
     FracSecondEquinoxPlanet_I(:)        = 0.0                           ! [ s]
     TiltPlanet_I(:)                     = 0.0 * cDegToRad               ! [rad]
                         
     TypeBFieldPlanet_I(:)               = "NONE"                
     DipoleStrengthPlanet_I(:)           = 0.0                           ! [ T]
     bAxisThetaPlanet_I(:)               = 0.0 * cDegToRad               ! [rad]
     bAxisPhiPlanet_I(:)                 = 0.0 * cDegToRad               ! [rad]
                                          
     IonoHeightPlanet_I(:)               = 0.0                           ! [ m]
   
                                         
     !\                                
     ! Mercury (10)                        
     !/                                
                                       
     !\                                
     ! Venus (20)                          
     !/                                
     NamePlanet_I(Venus_)                = 'VENUS'

     rPlanet_I(Venus_)                   = 6052.0*cE3                     ! [ m]
     mPlanet_I(Venus_)                   = 4.865*cE24                     ! [kg]
     OrbitalPeriodPlanet_I(Venus_)       = 224.7   * 24.0 * 3600.0        ! [ s]
     RotationPeriodPlanet_I(Venus_)      = 243.0185* 24.0 * 3600.0        ! [ s]
                                       
     IonoHeightPlanet_I(Venus_)          =  0.0                           ! [ m]
   
     !\                                
     ! Earth (30)                         
     !/                                
     NamePlanet_I(Earth_)                = 'EARTH'

     rPlanet_I(Earth_)                   = 6378.00*cThousand              ! [ m]
     mPlanet_I(Earth_)                   = 5.976*cE24                     ! [kg]
     rOrbitPlanet_I(Earth_)              = cAU                            ! [ m]
     OrbitalPeriodPlanet_I(Earth_)       = 365.24218967 * 24.0 * 3600.0   ! [ s]
     RotationPeriodPlanet_I(Earth_)      = 24.0 * 3600.0                  ! [ s]
                                       
     iYearEquinoxPlanet_I(Earth_)        = 2000                           ! [yr]
     iMonthEquinoxPlanet_I(Earth_)       =    3                           ! [mo]
     iDayEquinoxPlanet_I(Earth_)         =   20                           ! [dy]
     iHourEquinoxPlanet_I(Earth_)        =    7                           ! [hr]
     iMinuteEquinoxPlanet_I(Earth_)      =   35                           ! [mn]
     iSecondEquinoxPlanet_I(Earth_)      =    0                           ! [ s]
     FracSecondEquinoxPlanet_I(Earth_)   =  0.0                           ! [ s]
     TiltPlanet_I(Earth_)                = 23.5 * cDegToRad               ! [rad]
   
     TypeBFieldPlanet_I(:)               = "DIPOLE"                
     DipoleStrengthPlanet_I(Earth_)      = -31100.0 * 1.0e-9              ! [ T]
     bAxisThetaPlanet_I(Earth_)          =  11.0 * cDegToRad              ! [rad]
     bAxisPhiPlanet_I(Earth_)            = 289.1 * cDegToRad              ! [rad]
                                       
     IonoHeightPlanet_I(Earth_)          = 110000.0                       ! [ m]
   
     !\                               
     ! Mars (40)                         
     !/                               
     NamePlanet_I(Mars_)                 = 'MARS'

     rPlanet_I(Mars_)                    = 3396.00*cE3                    ! [ m]
     mPlanet_I(Mars_)                    = 0.6436*cE24                    ! [kg]
     OrbitalPeriodPlanet_I(Mars_)        = 686.98* 24.0 * 3600.0          ! [ s]
     RotationPeriodPlanet_I(Mars_)       = 1.026 * 24.0 * 3600.0          ! [ s]
                                        
     IonoHeightPlanet_I(Mars_)           =  0.0                           ! [ m]
   
     !\
     ! Jupiter (50)
     !/
     NamePlanet_I(Jupiter_)              = 'JUPITER'

     rPlanet_I(Jupiter_)                 = 71492.00*cE3                   ! [ m]
     mPlanet_I(Jupiter_)                 = 1.8980*cE27                    ! [kg]
     OrbitalPeriodPlanet_I(Jupiter_)     = 4330.60 * 24.0 * 3600.0        ! [ s]
     RotationPeriodPlanet_I(Jupiter_)    = 9.925 * 3600.0                 ! [ s]

     TypeBFieldPlanet_I(:)               = "DIPOLE"                
     DipoleStrengthPlanet_I(Jupiter_)    =   428000.0 * 1.0e-9                 ! [ T]
     bAxisThetaPlanet_I(Jupiter_)        =   0.0 * cDegToRad              ! [rad]
     bAxisPhiPlanet_I(Jupiter_)          =   0.0 * cDegToRad              ! [rad]
                                       
     IonoHeightPlanet_I(Jupiter_)        = 1000.0 *1.0e3                  ! [ m]
   
     !\                               
     ! Saturn (60)                        
     !/                               
     NamePlanet_I(Saturn_)               = 'SATURN'

     rPlanet_I(Saturn_)                  = 60268.00*cE3                   ! [ m]
     mPlanet_I(Saturn_)                  = 0.5685*cE27                    ! [kg]
     OrbitalPeriodPlanet_I(Saturn_)      = 10746.94 * 24.0 * 3600.0       ! [ s]
     RotationPeriodPlanet_I(Saturn_)     = 10.5 * 3600.0                  ! [ s]
                                       
     TypeBFieldPlanet_I(:)               = "DIPOLE"                
     DipoleStrengthPlanet_I(Saturn_)     = 20800.0 * 1.0e-9               ! [ T]
     bAxisThetaPlanet_I(Saturn_)         =   0.0 * cDegToRad              ! [rad]
     bAxisPhiPlanet_I(Saturn_)           =   0.0 * cDegToRad              ! [rad]
                                       
     IonoHeightPlanet_I(Saturn_)         = 1000.0 *1.0e3                  ! [ m]
   
     !\
     ! Uranus (70)
     !/
   
     !\
     ! Neptune (80)
     !/
   
     !\
     ! Pluto (90)
     !/
   
     !\
     ! Io (51)
     !/
     NamePlanet_I(Io_)                   = 'IO'

     rPlanet_I(Io_)                      = 1821.00*cE3                    ! [ m]
     mPlanet_I(Io_)                      = 0.0                            ! [kg]
     OrbitalPeriodPlanet_I(Io_)          = 0.0                            ! [ s]
     RotationPeriodPlanet_I(Io_)         = 0.0                            ! [ s]
   
     !\
     ! Titan (61)
     !/
     NamePlanet_I(Titan_)                = 'TITAN'

     rPlanet_I(Titan_)                   = 2575.00*cE3                    ! [ m]
     mPlanet_I(Titan_)                   = 0.1346*cE24                    ! [kg]
     rOrbitPlanet_I(Titan_)              = 1.222E9                        ! [ m]
     OrbitalPeriodPlanet_I(Titan_)       = 15.945 * 24.0 * 3600.0         ! [ s]
     RotationPeriodPlanet_I(Titan_)      = 15.945 * 24.0 * 3600.0         ! [ s]
                                       
     IonoHeightPlanet_I(Titan_)          =   0.0                          ! [ m]

     !\
     ! No Planet (0)
     !     - No Planet and no body - defaults for everything, just set name.
     !/
     NamePlanet_I(NoPlanet_)             = 'NONE'

     !\
     ! New Planet (MaxPlanet+1)
     !     - A planet whose parameters are not defined in the database above.
     !       A few values are set to clearly meaningless values to prevent
     !       a users from using the values incorrectly. 
     !/
     NamePlanet_I(NewPlanet_)            = 'NEW/UNKNOWN'
     rPlanet_I(NewPlanet_)               = -1.0
     mPlanet_I(NewPlanet_)               = -1.0

     ! make all the planet names upper case
     do i=NoPlanet_,MaxPlanet+1
        call upper_case(NamePlanet_I(i))  ! make all the names upper case
     end do

   end subroutine init_planet_const

end module ModPlanetConst
   

!====================================================================
! Documentation
!====================================================================


! The orbital period belongs to the TROPICAL YEAR, which is
! relative to the vernal equinox which is slowly moving 
! due to the precession of the Earth's rotation axis.

! The rotational angular velocity is relative to an inertial frame

! Reference equinox time taken from 
! http://aa.usno.navy.mil/data/docs/Planet(Earth_)Seasons.html

! The angle between the zero meridian and the eqinox direction at 
! equinox time. For Earth this can be calculated from the time of day.
! For other planets there is no analogous method to calculate this angle.
   

