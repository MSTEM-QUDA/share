program test_interpolate_amr

  use ModInterpolateAMRGrid, test => test_interpolate_on_amr_grid_3

  implicit none

  call test(100000)

end program test_interpolate_amr

subroutine CON_stop(StringError)

  implicit none
  character (len=*), intent(in) :: StringError
  !----------------------------------------------------------------------------

  write(*,'(a)')StringError
  write(*,'(a)')'!!! SWMF_ABORT !!!'
  stop

end subroutine CON_stop
