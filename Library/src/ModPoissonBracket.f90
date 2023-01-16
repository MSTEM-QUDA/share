!  Copyright (C) 2002 Regents of the University of Michigan,
!  portions used with permission
!  For more information, see http://csem.engin.umich.edu/tools/swmf
!
! For a contribution to the Liuville (kinetic) equation:
!
! df/dt + \sum_l{df/dq_l dH_l/dp_l - df/dp_l dH_l/dq_l}=0,
!
! in which f in the (unknown) distribution function,
! q_l and p_l are generalized coordinates,
! H_l are the (known!) Hamiltonian functions.
!
! See	arXiv:1910.12636 [physics.comp-ph]
!

module ModPoissonBracket

  use ModMpi
  use ModUtilities,    ONLY: CON_stop
  implicit none
  SAVE
  private ! except
  interface explicit
     module procedure explicit2
     module procedure explicit3
  end interface explicit
  !PUBLIC MEMBER FUNCTION:
  public :: explicit

  ! If DtIn results in CFL>CflMax, the time step is reduced
  real, parameter :: CflMax = 0.990
  character(LEN=*), parameter:: NameMod = 'ModPoissonBracket'
  logical, parameter :: UseLimiter = .true. ! false: switch off limiters
  ! The second order in time scheme is TVD only with  UseMinmodBeta=.true.,
  ! which scheme produces an extra dissipation  noticeable at 0.5<CFL<1,
  ! where \delta^-f changes sign. With UseMinmodBeta=.false. the TVD
  ! property is proved only at infinitesimal timestep.
  logical, parameter ::  UseMinmodBeta  = .false.
  logical, parameter ::  UseKoren = .false.
  real, parameter :: cTol = 1.0e-14

contains
  !============================================================================
  real function minmod(Arg1, Arg2)
    real, intent(in) :: Arg1, Arg2
    !--------------------------------------------------------------------------
    if(abs(Arg1)<=cTol)then
       minmod = 0.0
    elseif(.not.UseLimiter)then
       minmod = Arg1
    else
       minmod = (sign(0.5, Arg1) + sign(0.5, Arg2))*min(abs(Arg1), abs(Arg2))
    end if
  end function minmod
  !============================================================================
  real function minmodbeta(DownwindDeltaMinusF, UpwindDeltaMinusF)
    !  To switch between two choices of beta-parameter:
    !  1. minmod, if UseMinmodBeta=.true.
    !  2. DownwindDeltaMinusF  otherwise
    real, intent(in) :: DownwindDeltaMinusF, UpwindDeltaMinusF
    !--------------------------------------------------------------------------
    if(UpwindDeltaMinusF==0.0)then
       minmodbeta  =  0.0
    else
       minmodbeta = minmod(DownwindDeltaMinusF/UpwindDeltaMinusF,1.0)
    end if
  end function minmodbeta
  !============================================================================
  real function half_beta(Cfl, DownwindDeltaMinusF, UpwindDeltaMinusF)
    !  To switch between two choices of beta-parameter:
    !  1. minmod, if UseMinmodBeta=.true.
    !  2. DownwindDeltaMinusF  otherwise
    real, intent(in) :: Cfl, DownwindDeltaMinusF, UpwindDeltaMinusF
    !--------------------------------------------------------------------------
    half_beta = 1.0 - Cfl*(1.0 - minmodbeta( &
               DownwindDeltaMinusF, UpwindDeltaMinusF))
  end function half_beta
  !============================================================================
  real function betalimiter(DeltaF, UpwindDeltaF,&
       Cfl, DownwindDeltaMinusF, UpwindDeltaMinusF)
    !  \delta^-f in the neighboring cells
    real :: HalfBeta
    real, intent(in) :: DeltaF                ! f_j -f
    real, intent(in) :: UpwindDeltaF     ! f - f_j^\prime at the opposite face
    real, intent(in) :: Cfl, DownwindDeltaMinusF, UpwindDeltaMinusF
    real :: SignDeltaF, AbsDeltaF, AbsDeltaFLimited
    !--------------------------------------------------------------------------
    if(abs(DeltaF) <=cTol)then
       betalimiter = 0.0
    elseif(.not.UseLimiter)then
       betalimiter = 0.50*DeltaF
    else
       SignDeltaF = sign(1.0, DeltaF); AbsDeltaF = abs(DeltaF)
       if(UseKoren)then
          AbsDeltaFLimited = max(2*AbsDeltaF + &
               SignDeltaF*UpwindDeltaF,0.0)/6.0
       else
          AbsDeltaFLimited = 0.5*max(AbsDeltaF, SignDeltaF*UpwindDeltaF)
       end if
       if(UseMinmodBeta)then
          HalfBeta = half_beta(Cfl, (1.0 - Cfl)*DownwindDeltaMinusF, &
               Cfl*UpwindDeltaMinusF)
       else
          HalfBeta = 1.0
       end if
       betalimiter = SignDeltaF*min(AbsDeltaF*HalfBeta,AbsDeltaFLimited)
    end if
  end function betalimiter
  !============================================================================
  subroutine explicit2(nI, nJ, VDF_G, Volume_G, Source_C,    &
       Hamiltonian12_N, dHamiltonian01_FX, dHamiltonian02_FY,&
       DVolumeDt_G,                                          &
       DtIn, CFLIn, DtOut, IsPeriodicIn_D)
    ! solve the contribution to the
    ! numerical flux from a single Poisson bracket,
    ! df/dq_l dH/dp_l - df/dp_l dH/dq_l

    integer, intent(in) :: nI    !# of cells along coordinate 1
    integer, intent(in) :: nJ    !# of cells along coord. 2 (momentum)

    ! Distribution function with gc. Two layers of face ghostcels
    ! and one level of corner ghost cells are used
    real, intent(in) :: VDF_G(-1:nI+2,-1:nJ+2)

    ! Hamiltonian function in nodes. One layer of ghost nodes is used
    real, optional, intent(in) :: Hamiltonian12_N(-1:nI+1,-1:nJ+1)

    ! Increment in the Hamiltonian function for the Poisson bracket
    ! with respect to time, \{f,H_{01}\}_{t,x}. Is face-X centered.
    ! One layer of the ghost faces is needed.

    real, optional, intent(in) :: dHamiltonian01_FX(-1:nI+1, 0:nJ+1)
    ! Increment in the Hamiltonian function for the Poisson bracket
    ! with respect to time, \{f,H_{02}\}_{t,y}. Is face-Y centered.
    ! One layer of the ghost faces is needed.
    real, optional, intent(in) :: dHamiltonian02_FY( 0:nI+1,-1:nJ+1)

    ! Cell volume. One layer of face ghost cells is used
    real,           intent(in) :: Volume_G(0:nI+1,0:nJ+1)

    ! If non-canonical variables are used with time-dependent Jacobian,
    ! the cell volume changes in time. Need the volume derivative
    real, optional, intent(in) :: DVolumeDt_G(0:nI+1,0:nJ+1)

    ! Contribution to the conservative source (flux divergence) from
    ! the Poisson Bracket:
    !
    ! f(t+dt) - f(t) = Source_C
    real,           intent(out):: Source_C(1:nI,1:nJ)

    real, optional, intent(inout) :: DtIn   ! Options to set time step
    real, optional, intent(in)    :: CFLIn  ! Options to set time step
    real, optional, intent(out)   :: DtOut  ! Option to report time step
    logical, optional, intent(in) :: IsPeriodicIn_D(:)
    character(len=*), parameter:: NameSub = 'explicit2'
    !--------------------------------------------------------------------------
    call explicit3(nI, nJ, 1, VDF_G, Volume_G, Source_C,     &
       Hamiltonian12_N=Hamiltonian12_N,                      &
       dHamiltonian01_FX= dHamiltonian01_FX,                 &
       dHamiltonian02_FY= dHamiltonian02_FY,                 &
       DVolumeDt_G=DVolumeDt_G,                              &
       DtIn=DtIn,                                            &
       CFLIn=CFLIn,                                          &
       DtOut=DtOut,                                          &
       IsPeriodicIn_D=IsPeriodicIn_D)
  end subroutine explicit2
  !============================================================================
  subroutine explicit3(nI, nJ, nK, VDF_G, Volume_G, Source_C,            &
       Hamiltonian12_N, Hamiltonian13_N, Hamiltonian23_N,                &
       dHamiltonian01_FX, dHamiltonian02_FY, dHamiltonian03_FZ,          &
       DVolumeDt_G,                                                      &
       DtIn, CFLIn, DtOut, IsPeriodicIn_D)

    ! solve the contribution to the numerical flux from multiple Poisson
    ! brackets, 1,2,3 enumerate phase coordinates,  0 relating to time.

    integer, intent(in) :: nI     !# of cells along coordinate 1
    integer, intent(in) :: nJ     !# of cells along coordinate 2
    integer, intent(in) :: nK     !# of cells along coordinate 3
    integer :: iKStart , iKLast

    ! Distribution function with gc. Two layers of face ghostcels
    ! and one level of corner ghost cells are used
    real, intent(in) :: VDF_G(-1:nI+2,-1:nJ+2,&
         -1 + 2*(1/nK):nK + 2*(1 - 1/nK))

    ! Hamiltonian functions in nodes. One layer of ghost nodes is used.
    ! 1. Hamiltonian function for the Poisson bracket \{f,H_{12}}_{x,y}
    !    Node-centered at XY plane, cell-centered with respect to Z
    !    (In other words, Z-aligned-edge-centered)
    real, optional, intent(in) :: Hamiltonian12_N(-1:nI+1,-1:nJ+1,&
         1/nK:nK+1-1/nK)

    ! 2. Hamiltonian function for the Poisson bracket \{f,H_{13}}_{x,z}
    !    Node-centered at XZ plane, cell-centered with respect to Y
    !    (In other words, Y-aligned-edge-centered)
    real, optional, intent(in) :: Hamiltonian13_N(-1:nI+1,0:nJ+1,-1:nK+1)

    ! 3. Hamiltonian function for the Poisson bracket \{f,H_{23}}_{y,z}
    !    Node-centered at YZ plane, cell-centered with respect to X
    !    (In other words, X-aligned-edge-centered)
    real, optional, intent(in) :: Hamiltonian23_N(0:nI+1,-1:nJ+1,-1:nK+1)

    real, optional, intent(in) :: dHamiltonian01_FX(-1:nI+1,0:nJ+1,&
         1/nK:nK+1-1/nK)
    real, optional, intent(in) :: dHamiltonian02_FY(0:nI+1,-1:nJ+1,&
         1/nK:nK+1-1/nK)
    real, optional, intent(in) :: dHamiltonian03_FZ(0:nI+1,0:nJ+1,-1:nK+1)
    ! Total Volume. One layer of face ghost cells is used
    real, intent(in) :: Volume_G(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK)

    ! If non-canonical variables are used with time-dependent Jacobian,
    ! the cell volume changes in time. Need the volume derivative
    real, optional, intent(in) :: DVolumeDt_G(0:nI+1,0:nJ+1,&
         1/nK:nK+1-1/nK)

    ! Contribution to the conservative source (flux divergence) for
    ! the Poisson Bracket:
    ! send the source_c back to the main code
    real, intent(out) :: Source_C(1:nI, 1:nJ, 1:nK)

    !OPTIONAL PARAMETERS:
    real, optional, intent(inout) :: DtIn    ! Options to set time step
    real, optional, intent(in)    :: CFLIn   ! Options to set time step
    real, optional, intent(out)   :: DtOut   ! Option to report time step
    logical, optional, intent(in) :: IsPeriodicIn_D(:)
    ! Local variables
    logical :: UseTimeDependentVolume = .false. !=present(DVolumeDt_G)

    ! Inverse volume. One layer of face ghost cells is used
    real :: vInv_G(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK)
    ! Boundary conddition:
    logical :: IsPeriodic_D(3) = .false.
    ! Loop variables:
    integer :: i, j, k
    ! Variations of VDF (one layer of ghost cell values):
    real,dimension(0:nI+1, 0:nJ+1, 1/nK:nK+1-1/nK) :: &
         DeltaMinusF_G, SumDeltaHPlus_G
    !
    ! face-centered vriations of Hamiltonian functions.
    ! one layer of ghost faces
    real :: DeltaH_FX(-1:nI+1,0:nJ+1,1/nK:nK+1-1/nK)
    real :: DeltaH_FY(0:nI+1,-1:nJ+1,1/nK:nK+1-1/nK)
    real :: DeltaH_FZ(0:nI+1,0:nJ+1,-1:nK+1)
    real :: SumDeltaHMinus
    ! Fluxes:
    ! Sum of \delta^+H fluxes, to be limited
    real :: SumFluxPlus
    ! Sum of all second order fluxes
    real :: SumFlux2_G(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK)
    integer, parameter :: DeltaH_ = 1, Flux_ = 2
    integer, parameter :: iShift_DS(3,6) = reshape(&
                          [-1,  0,  0, &
                            1,  0,  0, &
                            0, -1,  0, &
                            0,  1,  0, &
                            0,  0, -1, &
                            0,  0,  1], [3,6])
    real    :: Buff_VSG(DeltaH_:Flux_,6)
    integer :: nFlux, iFlux, iSide_SG(6), iD_D(3)
    ! Local CFL number:
    real :: CFLCoef_G(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK), CFLLocal
    ! Time step
    real :: Dt
    ! Misc:
    ! Sum of major contributions
    real    :: SumMajor
    ! Misc:
    real    :: VDF
    ! Gamma-limiter
    real    :: DeltaPlusFLimited, Gamma
    character(len=*), parameter:: NameSub = 'explicit3'
    !--------------------------------------------------------------------------
    if(present(DtIn))then
       Dt = DtIn
    else
       if(.not.present(CflIn))call CON_stop(&
            'Either CflIn or DtIn should be provided in '//NameSub)
    end if
    IsPeriodic_D = .false.
    if(present(IsPeriodicIn_D))&
         IsPeriodic_D(1:size(IsPeriodicIn_D)) = IsPeriodicIn_D
    UseTimeDependentVolume = present(DVolumeDt_G)
    iKStart  = 1/nK ;  iKLast  = nK + 1 - 1/nK
    vInv_G = 1.0/Volume_G

    ! Nullify arrays:
    DeltaH_FX = 0.0; DeltaH_FY = 0.0; DeltaH_FZ = 0.0

    ! Bracket {F,H12}_{x,y}   Bracket {F,H13}_{x,z}    Bracket {F,H23}_{y,z}
    ! Hamiltonian 12 (xy)     Hamiltonian 13 (xz)      Hamiltonian 23 (yz)
    ! y                       z                        z
    ! 1---------<---------    1---------<----------    1----------<---------
    ! |                  |    |                   |    |                   |
    ! v       1,1,1      ^    v       1,1,1       |    v       1,1,1       ^
    ! |                  |    |                   |    |                   |
    ! |                  |    |                   |    |                   |
    ! 0--------->--------1x   0---------->--------1x   0---------->--------1y
    if (present(Hamiltonian12_N)) then
       DeltaH_FX = DeltaH_FX(-1:nI+1, 0:nJ+1,iKStart:iKLast) + &
               Hamiltonian12_N(-1:nI+1, 0:nJ+1,iKStart:iKLast) - &
               Hamiltonian12_N(-1:nI+1,-1:nJ  ,iKStart:iKLast)
       DeltaH_FY = DeltaH_FY( 0:nI+1,-1:nJ+1,iKStart:iKLast) + &
               Hamiltonian12_N(-1:nI  ,-1:nJ+1,iKStart:iKLast) - &
               Hamiltonian12_N(0:nI+1 ,-1:nJ+1,iKStart:iKLast)
    end if
    if (present(Hamiltonian13_N)) then
       DeltaH_FX = DeltaH_FX(-1:nI+1, 0:nJ+1, 0:nK+1) + &
             Hamiltonian13_N(-1:nI+1, 0:nJ+1, 0:nK+1) - &
             Hamiltonian13_N(-1:nI+1, 0:nJ+1,-1:nK  )
       DeltaH_FZ = DeltaH_FZ( 0:nI+1, 0:nJ+1,-1:nK+1) + &
             Hamiltonian13_N(-1:nI  , 0:nJ+1,-1:nK+1) - &
             Hamiltonian13_N( 0:nI+1, 0:nJ+1,-1:nK+1)
    end if
    if (present(Hamiltonian23_N)) then
       DeltaH_FY = DeltaH_FY( 0:nI+1,-1:nJ+1, 0:nK+1) + &
             Hamiltonian23_N( 0:nI+1,-1:nJ+1, 0:nK+1) - &
             Hamiltonian23_N( 0:nI+1,-1:nJ+1,-1:nK  )
       DeltaH_FZ = DeltaH_FZ( 0:nI+1, 0:nJ+1,-1:nK+1) + &
             Hamiltonian23_N( 0:nI+1,-1:nJ  ,-1:nK+1) - &
             Hamiltonian23_N( 0:nI+1, 0:nJ+1,-1:nK+1)
    end if
    ! Bracket {F,H01}_t,x    Bracket {F,H02}_t,y      Bracket {F,H03}_t,z
    ! Hamiltonian 01 (tx)    Hamiltonian 02 (ty)      Hamiltonian 03 (tz)
    ! x                      y                        z
    ! ----------<--------    ----------<---------     -----------<-------
    !
    !
    !
    !
    ! ---------->--------t   ---------->---------t    ----------->-------t
    if (present(dHamiltonian01_FX))&
         DeltaH_FX = DeltaH_FX + dHamiltonian01_FX
    if (present(dHamiltonian02_FY))&
         DeltaH_FY = DeltaH_FY + dHamiltonian02_FY
    if (present(dHamiltonian03_FZ))&
         DeltaH_FZ = DeltaH_FZ + dHamiltonian03_FZ
    ! Cleanup
    where(abs(DeltaH_FX)<cTol)DeltaH_FX = 0.0
    where(abs(DeltaH_FY)<cTol)DeltaH_FY = 0.0
    if(nK>1)then
       where(abs(DeltaH_FZ)<cTol)DeltaH_FZ = 0.0
    end if
    ! Now, for each cell the value of DeltaH for face in positive
    ! directions of i and j may be found in the arrays, for
    ! negative directions the should be taken with opposite sign
    ! Calculate DeltaMinusF and SumDeltaH
    do k=iKStart, iKLast; do j = 0, nJ+1; do i = 0, nI+1
       SumDeltaHMinus          =min(0.0, DeltaH_FX(i,  j,  k)) +&
                                min(0.0, DeltaH_FY(i,  j,  k)) +&
                                min(0.0,-DeltaH_FX(i-1,j,  k)) +&
                                min(0.0,-DeltaH_FY(i,j-1,  k))
       SumDeltaHPlus_G(i,j,k) = max(0.0, DeltaH_FX(i,  j,  k)) +&
                                max(0.0, DeltaH_FY(i,  j,  k)) +&
                                max(0.0,-DeltaH_FX(i-1,j,  k)) +&
                                max(0.0,-DeltaH_FY(i,j-1,  k))
       VDF = VDF_G(i,j,k)
       DeltaMinusF_G(i, j, k) = &
               min(0.0, DeltaH_FX(i,   j,   k))*(VDF_G(i+1,j,k) - VDF) +&
               min(0.0, DeltaH_FY(i,   j,   k))*(VDF_G(i,j+1,k) - VDF) +&
               min(0.0,-DeltaH_FX(i-1, j,   k))*(VDF_G(i-1,j,k) - VDF) +&
               min(0.0,-DeltaH_FY(i, j-1,   k))*(VDF_G(i,j-1,k) - VDF)
       if(nK>1)then
          ! Add three-dimensional effects.
          SumDeltaHMinus         = SumDeltaHMinus              +&
                                    min(0.0, DeltaH_FZ(i,j,k)) +&
                                    min(0.0,-DeltaH_FZ(i,j,k-1))
          SumDeltaHPlus_G(i,j,k) = SumDeltaHPlus_G(i,j,k)      +&
                                    max(0.0, DeltaH_FZ(i,j,k)) +&
                                    max(0.0,-DeltaH_FZ(i,j,k-1))
          DeltaMinusF_G(i, j, k) = DeltaMinusF_G(i, j, k)      +&
               min(0.0, DeltaH_FZ(i,   j,   k))*(VDF_G(i,j,k+1) - VDF) +&
               min(0.0,-DeltaH_FZ(i,   j, k-1))*(VDF_G(i,j,k-1) - VDF)
       end if
       if(SumDeltaHMinus==0.0)then
          DeltaMinusF_G(i,j,k) = 0.0
       else
          DeltaMinusF_G(i,j,k) = - DeltaMinusF_G(i,j,k)/SumDeltaHMinus
       end if
       if(UseTimeDependentVolume)then
          ! Local CFLs are expressed via SumDeltaHMinus
          CFLCoef_G(i,j,k) = -SumDeltaHMinus
       else
          CFLCoef_G(i,j,k) = -SumDeltaHMinus*vInv_G(i,j,k)
       end if
    end do; end do; end do
    ! Set CFL and time step
    if(UseTimeDependentVolume)then
       if(present(DtIn))then
          if(present(DtOut).and.present(CFLIn))&
               DtOut = CFLIn/maxval(vInv_G(1:nI,1:nJ,1:nK)*&
               (CFLCoef_G(1:nI,1:nJ,1:nK) - &
               CFLIn*DVolumeDt_G(1:nI,1:nJ,1:nK)))
          ! Calculate the CFL factor with given Dt:
          vInv_G = 1.0/(Volume_G + Dt*DVolumeDt_G)
          CFLCoef_G = Dt*vInv_G*CFLCoef_G

          ! Check if the CFL satisfies the stability criterion
          if(maxval(CFLCoef_G(1:nI,1:nJ,1:nK)) > CFLMax)then

             ! Restore CFLCoef_G and vInv
             CFLCoef_G = CFLCoef_G/(Dt*vInv_G)
             vInv_G = 1/Volume_G

             ! Reduce the time step using equation
             ! CFLMax = \Delta t*(-\sum\delta^-H)/(\Delta t*dV/dt + V)
             DtIn = CFLMax/maxval(vInv_G(1:nI,1:nJ,1:nK)*&
                  ( CFLCoef_G(1:nI,1:nJ,1:nK) &
                  - CFLMax*DVolumeDt_G(1:nI,1:nJ,1:nK)))
             Dt = DtIn
             ! Calculate the CFL factor with given Dt:
             vInv_G = 1.0/(Volume_G + Dt*DVolumeDt_G)
             CFLCoef_G = Dt*vInv_G*CFLCoef_G
          end if
          if(present(DtOut).and..not.present(CFLIn))&
               DtOut = Dt
       else
          ! Solve time step from equation
          ! CFLIn = \Delta t*(-\sum\delta^-H)/(\Delta t*dV/dt + V)
          Dt = CFLIn/maxval(vInv_G(1:nI,1:nJ,1:nK)*&
               (CFLCoef_G(1:nI,1:nJ,1:nK) - CFLIn*DVolumeDt_G(1:nI,1:nJ,1:nK)))
          if(present(DtOut))DtOut = Dt
          ! Calculate the volume at upper time level
          ! V(+\Delta t):
          vInv_G = 1.0/(Volume_G + Dt*DVolumeDt_G)
          CFLCoef_G = Dt*vInv_G*CFLCoef_G
       end if
    else
       if(present(DtIn))then
          if(present(DtOut ))&
               DtOut = CFLIn/maxval(CFLCoef_G(1:nI,1:nJ,1:nK))
          CFLCoef_G = Dt*CFLCoef_G
          if(maxval(CFLCoef_G(1:nI,1:nJ,1:nK)) > CFLMax)then
             ! Adjust time step and local CFL:
             Dt = Dt*CFLMax/maxval(CFLCoef_G(1:nI,1:nJ,1:nK))
             CFLCoef_G = (Dt/DtIn)*CFLCoef_G
             DtIn = Dt
          end if
       else
          Dt = CFLIn/maxval(CFLCoef_G(1:nI,1:nJ,1:nK))
          if(present(DtOut))DtOut = Dt
          CFLCoef_G = Dt*CFLCoef_G
       end if
    end if
    ! Calculate source = f(t+Dt) - f(t):
    ! First order monotone scheme
    Source_C = -CFLCoef_G(1:nI,1:nJ,1:nK)*DeltaMinusF_G(1:nI,1:nJ,1:nK)
    ! Second order correction
    SumFlux2_G = 0.0
    do k=1, nK; do j = 1, nJ; do i = 1, nI
       ! Limit and store fuxes across delta plus H faces ffrom the given cell
       if(SumDeltaHPlus_G(i,j,k)==0.0)CYCLE
       nFlux = 0
       if(DeltaH_FX(i,j,k) > 0.0)then
          nFlux = nFlux + 1; iSide_SG(nFlux) = 2
          Buff_VSG(DeltaH_:Flux_,nFlux) = DeltaH_FX(i,j,k)*&
               [1.0, limiter(2,i,j,k)]
       end if
       if(DeltaH_FX(i-1,j,k) < 0.0 )then
          nFlux = nFlux + 1; iSide_SG(nFlux) = 1
          Buff_VSG(DeltaH_:Flux_,nFlux) = (-DeltaH_FX(i-1,j,k))*&
               [1.0, limiter(1,i,j,k)]
       end if
       if(DeltaH_FY(i,j,k) > 0.0)then
          nFlux = nFlux + 1; iSide_SG(nFlux) = 4
          Buff_VSG(DeltaH_:Flux_,nFlux) = DeltaH_FY(i,j,k)*&
               [1.0, limiter(4,i,j,k)]
       end if
       if(DeltaH_FY(i,j-1,k) < 0.0)then
          nFlux = nFlux + 1; iSide_SG(nFlux) = 3
          Buff_VSG(DeltaH_:Flux_,nFlux) = (-DeltaH_FY(i,j-1,k))*&
               [1.0, limiter(3,i,j,k)]
       end if
       if(nK>1)then
          if(DeltaH_FZ(i,j,k) > 0.0)then
             nFlux = nFlux + 1; iSide_SG(nFlux) = 6
             Buff_VSG(DeltaH_:Flux_,nFlux) = DeltaH_FZ(i,j,k)*&
                  [1.0, limiter(6,i,j,k)]
          end if
          if(DeltaH_FZ(i,j,k-1) < 0.0)then
             nFlux = nFlux + 1; iSide_SG(nFlux) = 5
             Buff_VSG(DeltaH_:Flux_,nFlux) = (-DeltaH_FZ(i,j,k-1))*&
                  [1.0, limiter(5,i,j,k)]
          end if
       end if
       SumFluxPlus = sum(Buff_VSG(Flux_,1:nFlux))
       ! The value of limited \deta^+H/2 to be achieved with gamma-limiter
       DeltaPlusFLimited = minmod(SumFluxPlus/SumDeltaHPlus_G(i,j,k),&
            DeltaMinusF_G(i,j,k))
       ! This is the major flux, having the same sign as SumFluxPlus
       SumMajor =  sum(Buff_VSG(Flux_,1:nFlux),&
            MASK= SumFluxPlus*Buff_VSG(Flux_,1:nFlux) > 0.0)
       if(abs(SumMajor) > 0.0)then
          Gamma = 1.0 + (DeltaPlusFLimited*SumDeltaHPlus_G(i,j,k) - &
               SumFluxPlus)/SumMajor
          where(SumFluxPlus*Buff_VSG(Flux_,1:nFlux) > 0.0)&
               Buff_VSG(Flux_,1:nFlux) = Buff_VSG(Flux_,1:nFlux)*Gamma
       end if
       CFLLocal = CFLCoef_G(i,j,k)
       do iFlux = 1, nFlux
          iD_D = [i,j,k] + iShift_DS(:,iSide_SG(iFlux))
          SumFlux2_G(iD_D(1),iD_D(2),iD_D(3)) =      &
               SumFlux2_G(iD_D(1),iD_D(2),iD_D(3)) + Buff_VSG(Flux_,iFlux) - &
               Buff_VSG(DeltaH_,iFlux)*CFLLocal*DeltaPlusFLimited
       end do
       SumFlux2_G(i,j,k) = SumFlux2_G(i,j,k) - &
            (1 - CFLLocal)*DeltaPlusFLimited*SumDeltaHPlus_G(i,j,k)
    end do; end do; end do
    ! Second order fluxes across the boundary
    if(IsPeriodic_D(1))then
       SumFlux2_G(1,1:nJ,1:nK) = &
            SumFlux2_G(1,1:nJ,1:nK) + SumFlux2_G(nI+1,1:nJ,1:nK)
       SumFlux2_G(nI,1:nJ,1:nK) = &
            SumFlux2_G(nI,1:nJ,1:nK) + SumFlux2_G(0,1:nJ,1:nK)
    else
       do k=1, nK; do j = 1, nJ
          if(DeltaH_FX(0,j,k) > 0.0)then
             SumFlux2_G(1,j,k) = SumFlux2_G(1,j,k) + DeltaH_FX(0,j,k)*&
                  (1.0 - CFLCoef_G(0,j,k))* minmod(&
                  limiter(2,0,j,k), DeltaMinusF_G(0,j,k))
          end if
          if(DeltaH_FX(nI,j,k) < 0.0 )then
             SumFlux2_G(nI,j,k)   = SumFlux2_G(nI,j,k)   - DeltaH_FX(nI,j,k)*&
                  (1.0 - CFLCoef_G(nI+1,j,k))*minmod(&
                  limiter(1,nI+1,j,k), DeltaMinusF_G(nI+1,j,k))
          end if
       end do; end do
    end if
    if(IsPeriodic_D(2))then
       SumFlux2_G(1:nI,1,1:nK) = &
            SumFlux2_G(1:nI,1,1:nK) + SumFlux2_G(1:nI,nJ+1,1:nK)
       SumFlux2_G(1:nI,nJ,1:nK) = &
            SumFlux2_G(1:nI,nJ,1:nK) + SumFlux2_G(1:nI,0,1:nK)
    else
       do k=1, nK; do i = 1, nI
          if(DeltaH_FY(i,0,k) > 0.0)then
             SumFlux2_G(i,1,k) = SumFlux2_G(i,1,k) + DeltaH_FY(i,0,k)*&
                  (1.0 - CFLCoef_G(i,0,k))*minmod( &
                  limiter(4,i,0,k), DeltaMinusF_G(i,0,k))
          end if
          j = nJ
          if(DeltaH_FY(i,nJ,k) < 0.0)then
             SumFlux2_G(i,nJ,k)   = SumFlux2_G(i,nJ,k)   - DeltaH_FY(i,nJ,k)*&
                  (1.0 - CFLCoef_G(i,nJ+1,k))*minmod(  &
                  limiter(3,i,nJ+1,k), DeltaMinusF_G(i,nJ+1,k))
          end if
       end do; end do
    end if
    if(nK > 1)then
       if(IsPeriodic_D(3))then
          SumFlux2_G(1:nI,1:nJ,1) = &
               SumFlux2_G(1:nI,1:nJ,1) + SumFlux2_G(1:nI,1:nJ,nK+1)
          SumFlux2_G(1:nI,1:nJ,nK) = &
               SumFlux2_G(1:nI,1:nJ,nK) + SumFlux2_G(1:nI,1:nJ,0)
       else
          do j = 1, nJ; do i = 1, nI
             if(DeltaH_FZ(i,j,0) > 0.0)then
                SumFlux2_G(i,j,1) = SumFlux2_G(i,j,1) + DeltaH_FZ(i,j,0)*&
                     (1.0 - CFLCoef_G(i,j,0))*minmod( &
                     limiter(6,i,j,0), DeltaMinusF_G(i,j,0))
             end if
             if(DeltaH_FZ(i,j,nK) < 0.0)then
                SumFlux2_G(i,j,nK)   = SumFlux2_G(i,j,nK) - DeltaH_FZ(i,j,nK)*&
                     (1.0 - CFLCoef_G(i,j,nK+1))*minmod( &
                     limiter(5,i,j,nK+1), DeltaMinusF_G(i,j,nK+1))
             end if
          end do; end do
       end if
    end if
    Source_C = Source_C + Dt*vInv_G(1:nI,1:nJ,1:nK)*SumFlux2_G(1:nI,1:nJ,1:nK)
  contains
    !==========================================================================
    real function limiter(iSide,i,j,k)
      integer, intent(in):: iSide,i,j,k
      integer :: iU_D(3)
      !------------------------------------------------------------------------
      iD_D = [i,j,k] + iShift_DS(:,iSide); iU_D = [i,j,k] - iShift_DS(:,iSide) 
      limiter = betalimiter(                                           &
           DeltaF=VDF_G(iD_D(1),iD_D(2),iD_D(3))  - VDF_G(i,j,k),      &
           UpwindDeltaF=VDF_G(i,j,k) - VDF_G(iU_D(1),iU_D(2),iU_D(3)), &
           Cfl = CFLCoef_G(i,j,k),                                     &
           DownwindDeltaMinusF=DeltaMinusF_G(iD_D(1),iD_D(2),iD_D(3)), &
           UpwindDeltaMinusF  =DeltaMinusF_G(i,j,k))
    end function limiter
    !==========================================================================
  end subroutine explicit3
  !============================================================================
end module ModPoissonBracket
!==============================================================================
