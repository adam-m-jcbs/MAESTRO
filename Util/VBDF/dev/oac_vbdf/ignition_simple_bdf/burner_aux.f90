module network_indices

  ! this module is for use only within this network -- these
  ! quantities should not be accessed in general MAESTRO routines.
  ! Instead the species indices should be queried via
  ! network_species_index()

  implicit none

  integer, parameter :: ic12_ = 1
  integer, parameter :: io16_ = 2
  integer, parameter :: img24_ = 3

end module network_indices

module rpar_indices

  implicit none

  integer, save :: n_rpar_comps = 0
  !$acc declare copyin(n_rpar_comps)

  integer, save :: irp_dens, irp_cp, irp_dhdx, irp_o16
  integer, save :: irp_rate, irp_dratedt, irp_sc1212, irp_dsc1212dt, irp_xc12tmp
  !$acc declare create(irp_dens, irp_cp, irp_dhdx, irp_o16, irp_rate, &
  !$acc    irp_dratedt, irp_sc1212, irp_dsc1212dt, irp_xc12tmp)

contains

  function get_next_rpar_index(num) result (next)

    ! return the next starting index for a plotfile quantity,
    ! and increment the counter of plotfile quantities by num
    integer :: num, next

    next = n_rpar_comps + 1
    n_rpar_comps = n_rpar_comps + num

    return
  end function get_next_rpar_index


  subroutine init_rpar_indices(nspec)

    integer, intent(in) :: nspec

    irp_dens  = get_next_rpar_index(1)
    !$acc update device(irp_dens)
    irp_cp    = get_next_rpar_index(1)
    !$acc update device(irp_cp)
    irp_dhdX  = get_next_rpar_index(nspec)
    !$acc update device(irp_dhdX)
    irp_o16   = get_next_rpar_index(1)
    !$acc update device(irp_o16)

    irp_rate      = get_next_rpar_index(1)
    !$acc update device(irp_rate)
    irp_dratedt   = get_next_rpar_index(1)
    !$acc update device(irp_dratedt)
    irp_sc1212    = get_next_rpar_index(1)
    !$acc update device(irp_sc1212)
    irp_dsc1212dt = get_next_rpar_index(1)
    !$acc update device(irp_dsc1212dt)
    irp_xc12tmp   = get_next_rpar_index(1)
    !$acc update device(irp_xc12tmp)

  end subroutine init_rpar_indices

end module rpar_indices
