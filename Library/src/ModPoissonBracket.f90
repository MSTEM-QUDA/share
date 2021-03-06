!  Copyright (C) 2002 Regents of the University of Michigan,
!  portions used with permission
!  For more information, see http://csem.engin.umich.edu/tools/swmf
!
!
!
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
contains
  !============================================================================
  ! A choice of limiter functions
  real function pair_superbee(Arg1, Arg2)

    !  Used to limit only two distribution function variations
    !  \delta^-f in the neighboring cells
    real, intent(in):: Arg1, Arg2
    real :: AbsArg1, AbsArg2

    !--------------------------------------------------------------------------
    if(Arg1*Arg2 <= 0.0)then
       pair_superbee = 0.0
       RETURN
    end if
    AbsArg1 = abs(Arg1)
    AbsArg2 = abs(Arg2)
    pair_superbee = sign(min(min(AbsArg1,AbsArg2), &
                        0.50*max(AbsArg1,AbsArg2)  ),Arg1)
  end function pair_superbee
  !============================================================================
  subroutine explicit2(nI, nJ, VDF_G, Volume_G, Source_C,    &
       Hamiltonian12_N, dHamiltonian01_FX, dHamiltonian02_FY,&
       DVolumeDt_G,                                          &
       DtIn, CFLIn, DtOut, CFLOut, DtRecommend)

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

    real, optional, intent(in) :: DtIn, CFLIn   ! Options to set time step
    real, optional, intent(out):: DtOut, CFLOut ! Options to report time step
    real, optional, intent(out):: DtRecommend   ! Calculated for given CflIn
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
       CFLOut=CFLOut,                                        &
       DtRecommend=DtRecommend)
  end subroutine explicit2
  !============================================================================
  subroutine explicit3(nI, nJ, nK, VDF_G, Volume_G, Source_C,            &
       Hamiltonian12_N, Hamiltonian13_N, Hamiltonian23_N,                &
       dHamiltonian01_FX, dHamiltonian02_FY, dHamiltonian03_FZ,          &
       DVolumeDt_G,                                                      &
       DtIn, CFLIn, DtOut, CFLOut, DtRecommend)

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
    logical :: UseTimeDependentVolume = .false. !=present(DVolumeDt_G)

    ! Inverse volume. One layer of face ghost cells is used
    real :: vInv_G(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK)

    ! Contribution to the conservative source (flux divergence) for
    ! the Poisson Bracket:
    ! send the source_c back to the main code
    real, intent(out) :: Source_C(1:nI, 1:nJ, 1:nK)

    !OPTIONAL PARAMETERS:
    real, optional, intent(in) :: DtIn, CFLIn   ! Options to set time step
    real, optional, intent(out):: DtOut, CFLOut ! Options to report time step
    real, optional, intent(out):: DtRecommend   ! Calculated for given CflIn

    ! Local variables
    ! Loop variables:
    integer :: i, j, k

    ! Variations of VDF (one layer of ghost cell values):
    real :: DeltaMinusF_G(0:nI+1, 0:nJ+1, 0:nK+1)

    ! face-centered vriations of Hamiltonian functions.
    ! one layer of ghost faces
    real :: DeltaH_FX(-1:nI+1,0:nJ+1,1/nK:nK+1-1/nK)
    real :: DeltaH_FY(0:nI+1,-1:nJ+1,1/nK:nK+1-1/nK)
    real :: DeltaH_FZ(0:nI+1,0:nJ+1,-1:nK+1)
    real, dimension(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK) :: &
         SumDeltaHPlus_G, SumDeltaHMinus_G
    ! Fluxes:
    real :: Flux_FX(0:nI,1:nJ,1:nK)
    real :: Flux_FY(1:nI,0:nJ,1:nK)
    real :: Flux_FZ(1:nI,1:nJ,0:nK)

    ! Local CFL number:
    real :: CFLCoef_G(0:nI+1,0:nJ+1,1/nK:nK+1-1/nK)

    ! Time step
    real :: Dt, CFL

    character(len=*), parameter:: NameSub = 'explicit3'
    !--------------------------------------------------------------------------
    if(present(DtIn))then
       Dt = DtIn
    else
       if(.not.present(CflIn))call CON_stop(&
            'Either CflIn or DtIn should be provided in '//NameSub)
    end if
    UseTimeDependentVolume = present(DVolumeDt_G)
    iKStart  = 1/nK ;  iKLast  = nK +    1 - 1/nK
    vInv_G = 1.0/Volume_G

    ! Nullify arrays:
    DeltaH_FX = 0.0; DeltaH_FY = 0.0; DeltaH_FZ = 0.0
    Flux_FX   = 0.0; Flux_FY   = 0.0; Flux_FZ   = 0.0
    SumDeltaHPlus_G = 0.0;     SumDeltaHMinus_G = 0.0

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

    ! Now, for each cell the value of DeltaH for face in positive
    ! directions of i and j may be found in the arrays, for
    ! negative directions the should be taken with opposite sign

    ! Calculate DeltaMinusF and SumDeltaH
    do k=iKStart, iKLast; do j = 0, nJ+1; do i = 0, nI+1
       SumDeltaHPlus_G(i,j,k) = max(0.0, DeltaH_FX(i,  j,  k)) +&
                                max(0.0, DeltaH_FY(i,  j,  k)) +&
                                max(0.0,-DeltaH_FX(i-1,j,  k)) +&
                                max(0.0,-DeltaH_FY(i,j-1,  k))

       if(UseTimeDependentVolume)SumDeltaHMinus_G(i,j,k) =      &
                                min(0.0, DeltaH_FX(i,  j,  k)) +&
                                min(0.0, DeltaH_FY(i,  j,  k)) +&
                                min(0.0,-DeltaH_FX(i-1,j,  k)) +&
                                min(0.0,-DeltaH_FY(i,j-1,  k))

       DeltaMinusF_G(i, j, k) = &
               min(0.0, DeltaH_FX(i,   j,   k))*VDF_G(i+1,j,k) +&
               min(0.0, DeltaH_FY(i,   j,   k))*VDF_G(i,j+1,k) +&
               min(0.0,-DeltaH_FX(i-1, j,   k))*VDF_G(i-1,j,k) +&
               min(0.0,-DeltaH_FY(i, j-1,   k))*VDF_G(i,j-1,k)
       if(nK>1)then
          ! Add three-dimensional effects.
          SumDeltaHPlus_G(i,j,k) = SumDeltaHPlus_G(i,j,k)      +&
                                    max(0.0, DeltaH_FZ(i,j,k)) +&
                                    max(0.0,-DeltaH_FZ(i,j,k-1))

          if(UseTimeDependentVolume)SumDeltaHMinus_G(i,j,k) =   &
                                    SumDeltaHMinus_G(i,j,k)    +&
                                    min(0.0, DeltaH_FZ(i,j,k)) +&
                                    min(0.0,-DeltaH_FZ(i,j,k-1))

          DeltaMinusF_G(i, j, k) = DeltaMinusF_G(i, j, k)      +&
               min(0.0, DeltaH_FZ(i,   j,   k))*VDF_G(i,j,k+1) +&
               min(0.0,-DeltaH_FZ(i,   j, k-1))*VDF_G(i,j,k-1)
       end if
       if(UseTimeDependentVolume)then

          ! Local CFL and \delta^-f are expressed via SumDeltaHMinus
          DeltaMinusF_G(i,j,k) = DeltaMinusF_G(i,j,k)           &
               /max(-SumDeltaHMinus_G(i,j,k), 1.0e-31) + VDF_G(i,j,k)
          CFLCoef_G(i,j,k) = -SumDeltaHMinus_G(i,j,k)
       else
          DeltaMinusF_G(i,j,k) = DeltaMinusF_G(i,j,k)           &
               /max(  SumDeltaHPlus_G(i,j,k), 1.0e-31) + VDF_G(i,j,k)
          CFLCoef_G(i,j,k) = vInv_G(i,j,k)*SumDeltaHPlus_G(i,j,k)
       end if
    end do; end do; end do

    ! Set CFL and time step
    if(UseTimeDependentVolume)then
       if(present(DtRecommend))then
          if(present(CFLIn))then
             CFL = CFLIn
          else
             CFL = CFLMax
          end if
          ! Solve time step from equation
          ! CFLIn = \Delta t*(-\sum\delta^-H)/(\Delta t*dV/dt + V)
          DtRecommend = CFL/maxval(vInv_G(1:nI,1:nJ,1:nK)*&
               (CFLCoef_G(1:nI,1:nJ,1:nK) - CFL*DVolumeDt_G(1:nI,1:nJ,1:nK)))
       end if
       if(present(DtIn))then

          ! Calculate the CFL factor with given Dt:
          vInv_G = 1.0/(Volume_G + Dt*DVolumeDt_G)
          CFLCoef_G = Dt*vInv_G*CFLCoef_G
          CFL = maxval(CFLCoef_G(1:nI,1:nJ,1:nK))

          ! Check if the CFL satisfies the stability criterion
          if(CFL>CFLMax)then

             ! Restore CFLCoef_G and vInv
             CFLCoef_G = CFLCoef_G/(Dt*vInv_G)
             vInv_G = 1/Volume_G

             ! Reduce the time step using equation
             ! CFLMax = \Delta t*(-\sum\delta^-H)/(\Delta t*dV/dt + V)
             CFL = CFLMax
             Dt = CFL/maxval(vInv_G(1:nI,1:nJ,1:nK)*&
                  (CFLCoef_G(1:nI,1:nJ,1:nK) - CFL*DVolumeDt_G(1:nI,1:nJ,1:nK)))

             ! Calculate the CFL factor with given Dt:
             vInv_G = 1.0/(Volume_G + Dt*DVolumeDt_G)
             CFLCoef_G = Dt*vInv_G*CFLCoef_G
          end if
       else
          ! Solve time step from equation
          ! CFLIn = \Delta t*(-\sum\delta^-H)/(\Delta t*dV/dt + V)
          Dt = CFLIn/maxval(vInv_G(1:nI,1:nJ,1:nK)*&
               (CFLCoef_G(1:nI,1:nJ,1:nK) - CFLIn*DVolumeDt_G(1:nI,1:nJ,1:nK)))
          ! Calculate the volume at upper time level
          ! V(+\Delta t):
          vInv_G = 1.0/(Volume_G + Dt*DVolumeDt_G)
          CFLCoef_G = Dt*vInv_G*CFLCoef_G
       end if
    else
       if(.not.present(DtIn))&
            Dt = CFLIn/maxval(CFLCoef_G(1:nI,1:nJ,1:nK))
       CFLCoef_G = Dt*CFLCoef_G
    end if
    if(present(CFLOut))then

       ! The debugging version: normally, the CFL is known by now and there is no need
       ! to calculate it again
       CFLOut = maxval(CFLCoef_G(1:nI,1:nJ,1:nK))
       if(CFLOut > CFLMax*0.99 + 0.01)call CON_stop('CFL is too large')
    end if
    if(present(DtOut ))DtOut  = Dt

    ! First order monotone scheme
    Source_C = -CFLCoef_G(1:nI,1:nJ,1:nK)*DeltaMinusF_G(1:nI,1:nJ,1:nK)

    ! Calculate Face-X fluxes.
    do k=1, nK; do j = 1, nJ; do i = 0, nI
       if(DeltaH_FX(i,j,k) > 0.0)then
          Flux_FX(i,j,k) = DeltaH_FX(i,j,k)*               &
               (1.0 - CFLCoef_G(i,j,k))*pair_superbee(     &
               DeltaMinusF_G(i,j,k), DeltaMinusF_G(i+1,j,k))
       else
          Flux_FX(i,j,k) = DeltaH_FX(i,j,k)*               &
               (1.0 - CFLCoef_G(i+1,j,k))*pair_superbee(   &
               DeltaMinusF_G(i,j,k), DeltaMinusF_G(i+1,j,k))
       end if
    end do; end do; end do

    ! Calculate Face-Y fluxes.
    do k=1, nK; do j = 0, nJ; do i = 1, nI
       if(DeltaH_FY(i,j,k) > 0.0)then
            Flux_FY(i,j,k) = DeltaH_FY(i,j,k)*             &
               (1.0 - CFLCoef_G(i,j,k))*pair_superbee(     &
               DeltaMinusF_G(i,j,k), DeltaMinusF_G(i,j+1,k))
       else
          Flux_FY(i,j,k) = DeltaH_FY(i,j,k)*               &
               (1.0 - CFLCoef_G(i,j+1,k))*pair_superbee(   &
               DeltaMinusF_G(i,j,k), DeltaMinusF_G(i,j+1,k))
       end if
    end do; end do; end do
    if(nK==1)then

       ! Two-dimensional formulation
       Source_C(1:nI,1:nJ,1) = Source_C(1:nI,1:nJ,1) + (&
            Flux_FX(0:nI-1, 1:nJ  , 1) - Flux_FX(1:nI, 1:nJ, 1)  + &
            Flux_FY(1:nI  , 0:nJ-1, 1) - Flux_FY(1:nI, 1:nJ, 1)) * &
            Dt*vInv_G(1:nI,1:nJ,1)
       RETURN
    end if

    ! Calculate Face-Z fluxes.
    do k=0, nK; do j = 1, nJ; do i = 1, nI
       if(DeltaH_FZ(i,j,k) > 0.0)then
          Flux_FZ(i,j,k) = DeltaH_FZ(i,j,k)*               &
               (1.0 - CFLCoef_G(i,j,k))*pair_superbee(     &
               DeltaMinusF_G(i,j,k), DeltaMinusF_G(i,j,k+1))
       else
          Flux_FZ(i,j,k) = DeltaH_FZ(i,j,k)*               &
               (1.0 - CFLCoef_G(i,j,k+1))*pair_superbee(   &
               DeltaMinusF_G(i,j,k), DeltaMinusF_G(i,j,k+1))
       end if
    end do; end do; end do
    Source_C = Source_C + (&
         Flux_FX(0:nI-1, 1:nJ, 1:nK) - Flux_FX(1:nI, 1:nJ, 1:nK) + &
         Flux_FY(1:nI, 0:nJ-1, 1:nK) - Flux_FY(1:nI, 1:nJ, 1:nK) + &
         Flux_FZ(1:nI, 1:nJ, 0:nK-1) - Flux_FZ(1:nI, 1:nJ, 1:nK))* &
         Dt*vInv_G(1:nI,1:nJ,1:nK)
  end subroutine explicit3
  !============================================================================
end module ModPoissonBracket
!==============================================================================
