!BOP
!MODULE: CON_ray_trace - trace field and stream lines in parallel
!INTERFACE:
module CON_ray_trace

  !DESCRIPTION:
  ! Provides the infrastructure for parallel tracing of a vector field:
  ! for velocity field stream lines, for magnetic field the field lines,
  ! in general rays.
  !
  ! Each processor is working on the ray segments inside their subdomain.
  ! The processors periodically exchange ray information with the other 
  ! processors. The ray information contains the starting position,
  ! the rank of the starting processor, the current position, 
  ! the direction of the ray relative to the vector field (parallel or
  ! antiparallel), the status of the ray tracing (done or in progress).
  ! 
  ! If some variables are integrated along the rays, they are also passed.

  !USES:
  use ModMpi

  implicit none

  save    ! save all variables

  private ! except

  !PUBLIC MEMBER FUNCTIONS:
  public :: ray_init          ! Initialize module
  public :: ray_clean         ! Clean up storage
  public :: ray_put           ! Put information about a ray to be continued
  public :: ray_get           ! Get information about a ray to be continued
  public :: ray_exchange      ! Exchange ray information with other processors
  public :: ray_test          ! Unit tester

  !REVISION HISTORY:
  ! 31Jan04 - Gabor Toth <gtoth@umich.edu> - initial prototype/prolog/code
  ! 26Mar04 - Gabor Toth added the passing of nValue real values
  !EOP

  ! Private constants
  character(len=*),  parameter :: NameMod='CON_ray_trace'

  ! Named indexes for ray position
  integer, parameter :: &
       RayStartX_=1, RayStartY_=2, RayStartZ_=3, RayStartProc_=4, &
       RayEndX_  =5, RayEndY_  =6, RayEndZ_  =7, RayDir_=8, RayDone_  =9, &
       RayValue_ =10

  ! Minimum dimensionality of ray info
  integer, parameter :: MinRayInfo = 9
  integer :: nRayInfo = MinRayInfo
  integer :: nValue   = 0

  ! Private type
  ! Contains nRay rays with full information
  type RayPtr
     integer       :: nRay, MaxRay
     real, pointer :: Ray_VI(:,:)
  end type RayPtr

  ! Private variables

  ! Ray buffers
  type(RayPtr), pointer :: Send_P(:)     ! Rays to send to other PE-s
  type(RayPtr)          :: Recv          ! Rays received from all other PE-s
  integer, pointer      :: nRayRecv_P(:) ! Number of rays recv from other PE-s

  ! MPI variables
  integer               :: iComm, nProc, iProc ! MPI group info
  integer               :: nRequest
  integer, allocatable  :: iRequest_I(:), iStatus_II(:,:)

  integer               :: iError              ! generic MPI error value

contains

  !===========================================================================

  subroutine ray_init(iCommIn, nValueIn)

    ! Initialize the ray tracing form the MPI communicator iCommIn

    integer, intent(in) :: iCommIn
    integer, intent(in), optional :: nValueIn

    character (len=*), parameter :: NameSub = NameMod//'::ray_init'
    integer :: jProc
    !------------------------------------------------------------------------

    ! Store MPI information
    iComm = iCommIn
    call MPI_COMM_SIZE (iComm, nProc,  iError)
    call MPI_COMM_RANK (iComm, iProc,  iError)

    ! Store the number of values to pass around with basic ray information
    if(present(nValueIn))then
       nValue   = nValueIn
       nRayInfo = MinRayInfo + nValue
    end if

    ! Allocate MPI variables for non-blocking exchange
    ! At most nProc messages are sent
    allocate(iRequest_I(nProc), iStatus_II(MPI_STATUS_SIZE, nProc))

    ! Initialize send buffers
    allocate(Send_P(0:nProc-1))
    do jProc=0, nProc-1
       Send_P(jProc) % nRay   = 0
       Send_P(jProc) % MaxRay = 0
       nullify(Send_P(jProc) % Ray_VI)
    end do

    ! Initialize receive buffer
    allocate(nRayRecv_P(0:nProc-1))
    Recv % nRay   = 0
    Recv % MaxRay = 0
    nullify(Recv % Ray_VI)

  end subroutine ray_init

  !===========================================================================

  subroutine ray_clean

    character (len=*), parameter :: NameSub = NameMod//'::ray_clean'
    integer :: jProc
    !------------------------------------------------------------------------

    ! Deallocate MPI variables
    deallocate(iRequest_I, iStatus_II)

    ! Deallocate send buffers
    if(associated(Send_P))then
       do jProc = 0, nProc-1
          if(associated(Send_P(jProc) % Ray_VI)) &
               deallocate(Send_P(jProc) % Ray_VI)
       end do
    end if
    deallocate(Send_P)

    ! Deallocate recv buffer
    if(associated(nRayRecv_P))deallocate(nRayRecv_P)
    if(associated(Recv % Ray_VI))deallocate(Recv % Ray_VI)
    Recv % nRay   = 0
    Recv % MaxRay = 0

  end subroutine ray_clean

  !===========================================================================

  subroutine ray_put(&
       iProcStart,XyzStart_D,iProcEnd,XyzEnd_D,IsParallel,DoneRay,RayValue_V)

    integer, intent(in) :: iProcStart,iProcEnd ! PE-s for start and end pos.
    real,    intent(in) :: XyzStart_D(3), XyzEnd_D(3) ! Start and end pos.
    logical, intent(in) :: IsParallel,DoneRay  ! Direction and status of trace

    real,    intent(in), optional :: RayValue_V(nValue) ! nValue reals to be passed

    character (len=*), parameter :: NameSub = NameMod//'::ray_put'

    integer :: iProcTo
    !-------------------------------------------------------------------------
    ! Where should we send the ray
    if(DoneRay)then
       iProcTo = iProcStart  ! Send back result to the PE that started tracing
    else
       iProcTo = iProcEnd    ! Send to PE which can continue the tracing
    end if

    if(iProcTo<0)&
         call CON_stop(NameSub//' SWMF_error: PE lookup to be implemented')

    call append_ray(Send_P(iProcTo))

  contains

    !========================================================================
    subroutine append_ray(Send)

      ! Append a new element to the Send buffer

      type(RayPtr) :: Send
      integer      :: iRay
      !---------------------------------------------------------------------
      iRay = Send % nRay + 1
      if(iRay > Send % MaxRay) call extend_buffer(Send, iRay+100)

      Send % Ray_VI(RayStartX_:RayStartZ_,iRay) = XyzStart_D
      Send % Ray_VI(RayStartProc_,iRay)         = iProcStart
      Send % Ray_VI(RayEndX_  :RayEndZ_,iRay)   = XyzEnd_D

      if(IsParallel)then
         Send % Ray_VI(RayDir_,iRay)            = 1
      else
         Send % Ray_VI(RayDir_,iRay)            = -1
      end if

      if(DoneRay)then
         Send % Ray_VI(RayDone_,iRay)            = 1
      else
         Send % Ray_VI(RayDone_,iRay)            = 0
      end if

      if(present(RayValue_V)) &
           Send % Ray_VI(RayValue_:RayValue_+nValue-1,iRay) = RayValue_V

      Send % nRay = iRay

    end subroutine append_ray

  end subroutine ray_put

  !===========================================================================

  subroutine ray_get(&
       IsFound,iProcStart,XyzStart_D,XyzEnd_D,IsParallel,DoneRay,RayValue_V)

    ! Provide the last ray for the component to store or to work on

    logical, intent(out) :: IsFound             ! true if there are still rays
    integer, intent(out) :: iProcStart          ! PE-s for start and end pos.
    real,    intent(out) :: XyzStart_D(3), XyzEnd_D(3) ! Start and end pos.
    logical, intent(out) :: IsParallel,DoneRay  ! Direction and status of trace

    real,    intent(out), optional :: RayValue_V(nValue)

    character (len=*), parameter :: NameSub = NameMod//'::ray_get'

    integer :: iRay
    !-------------------------------------------------------------------------

    iRay    = Recv%nRay 
    IsFound = iRay > 0

    if(.not.IsFound) RETURN  ! No more rays in the buffer

    ! Copy last ray into output arguments
    XyzStart_D = Recv % Ray_VI(RayStartX_:RayStartZ_,iRay)
    iProcStart = nint(Recv % Ray_VI(RayStartProc_,iRay))
    XyzEnd_D   = Recv % Ray_VI(RayEndX_  :RayEndZ_,iRay)
    IsParallel = Recv % Ray_VI(RayDir_,iRay)  > 0.0
    DoneRay    = Recv % Ray_VI(RayDone_,iRay) > 0.5

    if(present(RayValue_V)) &
         RayValue_V = Recv % Ray_VI(RayValue_:RayValue_+nValue-1,iRay) 

    ! Remove ray from buffer
    Recv % nRay = iRay - 1

  end subroutine ray_get

  !===========================================================================

  subroutine ray_exchange(DoneMe,DoneAll)

    ! Send the Send_P buffers to Recv buffers, empty the Send_P buffers
    ! Also check if there is more work to do. If the input argument DoneMe 
    ! is false on any PE-s (i.e. it has more rays to do), 
    ! or if there are any rays passed, the output argument DoneAll is 
    ! set to .false. for all PE-s. 
    ! If all PE-s have DoneMe true and all send buffers are
    ! empty then DoneAll is set to .true.

    character (len=*), parameter :: NameSub = NameMod//'::ray_exchange'

    logical, intent(in) :: DoneMe
    logical, intent(out):: DoneAll

    logical :: DoneLocal

    integer, parameter :: iTag = 1
    integer :: jProc, iRay, nRayRecv

    !-------------------------------------------------------------------------

    ! Exchange number of rays in the send buffer

    ! Local copy (in case ray remains on the same PE)
    nRayRecv_P(iProc)=Send_P(iProc) % nRay

    nRequest = 0
    iRequest_I = MPI_REQUEST_NULL
    do jProc = 0, nProc-1
       if(jProc==iProc)CYCLE
       nRequest = nRequest + 1
       call MPI_irecv(nRayRecv_P(jProc),1,MPI_INTEGER,jProc,&
            iTag,iComm,iRequest_I(nRequest),iError)
    end do

    ! Wait for all receive commands to be posted for all processors
    call MPI_barrier(iComm,iError)

    ! Use ready-send
    do jProc = 0, nProc-1
       if(jProc==iProc)CYCLE
       call MPI_rsend(Send_P(jProc) % nRay,1,MPI_INTEGER,jProc,&
            iTag,iComm,iError)
    end do

    ! Wait for all messages to be received
    if(nRequest > 0)call MPI_waitall(nRequest,iRequest_I,iStatus_II,iError)

    nRayRecv = Recv % nRay + sum(nRayRecv_P)

    ! Extend receive buffer as needed
    if(nRayRecv > Recv % MaxRay) call extend_buffer(Recv,nRayRecv+100)

    ! Exchange ray information
    iRay = Recv % nRay + 1

    ! Local copy if any
    if(nRayRecv_P(iProc) > 0)then
       Recv % Ray_VI(:,iRay:iRay+nRayRecv_P(iProc)-1) = &
            Send_P(iProc) % Ray_VI
       iRay = iRay + nRayRecv_P(iProc)
    end if

    nRequest   = 0
    iRequest_I = MPI_REQUEST_NULL
    do jProc = 0, nProc-1
       if(jProc==iProc)CYCLE
       if(nRayRecv_P(jProc)==0)CYCLE
       nRequest = nRequest + 1

       call MPI_irecv(Recv % Ray_VI(1,iRay),nRayRecv_P(jProc)*nRayInfo,&
               MPI_REAL,jProc,iTag,iComm,iRequest_I(nRequest),iError)
       iRay = iRay + nRayRecv_P(jProc)
    end do

    ! Wait for all receive commands to be posted for all processors
    call MPI_barrier(iComm, iError)

    do jProc = 0, nProc-1
       if(jProc==iProc)CYCLE
       if(Send_P(jProc) % nRay == 0) CYCLE

       call MPI_rsend(Send_P(jProc) % Ray_VI(1,1),&
            Send_P(jProc) % nRay*nRayInfo,MPI_REAL,jProc,iTag,iComm,iError)
    enddo

    ! Wait for all messages to be received
    if(nRequest > 0)call MPI_waitall(nRequest,iRequest_I,iStatus_II,iError)

    ! Update number of received rays
    Recv % nRay = nRayRecv

    ! Reset send buffers
    do jProc = 0, nProc-1
       Send_P(jProc) % nRay = 0
    end do

    ! Check if there is more work to do on this PE
    DoneLocal = DoneMe .and. (Recv % nRay == 0)

    ! Check if all PE-s are done
    call MPI_allreduce(DoneLocal, DoneAll, 1, MPI_LOGICAL, MPI_LAND, &
         iComm, iError)

  end subroutine ray_exchange

  !===========================================================================

  subroutine extend_buffer(Buffer, nRayNew)

    ! Extend buffer size to nRayNew (or more)

    type(RayPtr)        :: Buffer
    integer, intent(in) :: nRayNew

    real, pointer :: OldRay_VI(:,:)
    !------------------------------------------------------------------------
    if(.not.associated(Buffer % Ray_VI))then
       allocate(Buffer % Ray_VI(nRayInfo,nRayNew))    ! allocatenew buffer
       Buffer % nRay   = 0                            ! buffer is empty
       Buffer % MaxRay = nRayNew                      ! set buffer size
    else
       OldRay_VI => Buffer % Ray_VI                   ! store old values
       allocate(Buffer % Ray_VI(nRayInfo,nRayNew))    ! allocate new buffer
       Buffer % Ray_VI(:,1:Buffer % nRay) = &
            OldRay_VI(:,1:Buffer % nRay)              ! copy old values
       deallocate(OldRay_VI)                          ! free old storage
       Buffer % MaxRay = nRayNew                      ! change buffer size
    end if

  end subroutine extend_buffer

  !===========================================================================

  subroutine ray_test

    ! Test this module

    logical :: IsFound
    integer :: iProcStart
    real    :: XyzStart_D(3),XyzEnd_D(3)
    logical :: IsParallel,DoneRay, DoneAll
    integer :: jProc
    integer, parameter :: nValueTest=3
    real :: ValueTest_V(nValueTest)
    !------------------------------------------------------------------------

    call ray_init(MPI_COMM_WORLD,nValueTest)

    write(*,*)'ray_init done, iProc,nProc,nValue=',iProc,nProc,nValue

    write(*,"(a,i2,a,3f5.0,a,i2,a,3f5.0,a,2l2,a,3f5.1)") &
         " Sending from iProc=",iProc,&
         " XyzStart=",(/110.+iProc,120.+iProc,130.+iProc/),&
         " to jProc=",mod(iProc+1,nProc),&
         " XyzEnd=",(/210.+iProc,220.+iProc,230.+iProc/), &
         " IsParallel, DoneRay=",.true.,.false., &
         " RayValue_V=",(/1.,2.,3./)

    call ray_put(iProc, (/110.+iProc,120.+iProc,130.+iProc/), &
         mod(iProc+1,nProc), (/210.+iProc,220.+iProc,230.+iProc/), &
         .true.,.false.,(/1.,2.,3./))

    write(*,"(a,i2,a,3f5.0,a,i2,a,3f5.0,a,2l2,a,3f5.1)") &
         " Sending from iProc=",iProc,&
         " XyzStart=",(/110.+iProc,120.+iProc,130.+iProc/),&
         " to jProc=",mod(iProc-1,nProc),&
         " XyzEnd=",(/210.+iProc,220.+iProc,230.+iProc/), &
         " IsParallel, DoneRay=",.false.,.false., &
         " RayValue_V=",(/-1.,-2.,-3./)

    call ray_put(iProc, (/110.+iProc,120.+iProc,130.+iProc/), &
         mod(nProc+iProc-1,nProc), (/210.+iProc,220.+iProc,230.+iProc/), &
         .false.,.false.,(/-1.,-2.,-3./))

    do jProc = 0, nProc-1
       write(*,"(a,i2,i2,i4,i4,100f5.0)")'iProc,jProc,Send_P(jProc)=',&
            iProc,jProc,Send_P(jProc) % MaxRay,&
            Send_P(jProc) % nRay, &
            Send_P(jProc) % Ray_VI(:,1:Send_P(jProc) % nRay)
    end do

    write(*,*)'ray_put done'

    call ray_exchange(.true., DoneAll)

    write(*,*)'ray_exchange done, DoneAll=',DoneAll

    do
       call ray_get(IsFound,iProcStart,XyzStart_D,XyzEnd_D,IsParallel,DoneRay,&
            ValueTest_V)
       if(.not.IsFound) EXIT
       write(*,"(a,i2,a,3f5.0,a,i2,a,3f5.0,a,2l2,a,3f5.1)")&
            'iProc ',iProc,' received XyzStart=',XyzStart_D,&
            ' iProcStart=',iProcStart,' XyzEnd=',XyzEnd_D,&
            ' Isparallel,DoneRay=',IsParallel,DoneRay,&
            ' ValueTest_V=',ValueTest_V
    end do

    write(*,*)'ray_get done'

    call ray_exchange(.true., DoneAll)

    write(*,*)'ray_exchange repeated, DoneAll=',DoneAll

    call ray_clean

    write(*,*)'ray_clean done'

  end subroutine ray_test

  !===========================================================================

end module CON_ray_trace
