! a module for storing the geometric information so we don't have to pass it
!
! This module provides the coordinate value for the left edge of a base-state
! zone (r_edge_loc) and the zone center (r_cc_loc).  As always, it is assumed that 
! the base state arrays begin with index 0, not 1.

module geometry

  use bl_types
  use ml_layout_module

  implicit none

  integer   , save :: nlevs
  integer   , save :: spherical
  integer   , save :: dm
  real(dp_t), save :: center(3)
  integer   , save :: nr_fine
  real(dp_t), save :: dr_fine
  real(dp_t), allocatable, save :: dr(:), r_cc_loc(:,:), r_edge_loc(:,:)
  integer   , allocatable, save :: numdisjointchunks(:)
  integer   , allocatable, save :: r_start_coord(:,:), r_end_coord(:,:), nr(:)
  integer   , allocatable, save :: anelastic_cutoff_coord(:)
  integer   , allocatable, save :: base_cutoff_density_coord(:)
  integer   , allocatable, save :: burning_cutoff_density_coord(:)
  real(dp_t), save :: sin_theta, cos_theta, omega, centrifugal_term(3)

  private

  public :: nlevs, spherical, dm, center, nr_fine, dr_fine
  public :: dr, r_cc_loc, r_edge_loc
  public :: numdisjointchunks
  public :: r_start_coord, r_end_coord, nr
  public :: anelastic_cutoff_coord
  public :: base_cutoff_density_coord
  public :: burning_cutoff_density_coord
  public :: sin_theta, cos_theta, omega, centrifugal_term

  public :: init_dm, init_spherical, init_center, init_radial, init_cutoff, &
       init_multilevel, init_rotation, destroy_geometry

contains

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_dm()

    use probin_module, only: dm_in

    dm = dm_in

  end subroutine init_dm

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_spherical()

    use probin_module, only: spherical_in

    spherical = spherical_in

  end subroutine init_spherical

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_center()

    use probin_module, only: prob_lo, prob_hi
    use bl_constants_module

    center(1:dm) = HALF * (prob_lo(1:dm) + prob_hi(1:dm))

  end subroutine init_center

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_radial(num_levs,mba)

    ! computes dr, nr, r_cc_loc, r_edge_loc

    use probin_module, only: prob_lo, prob_hi
    use bl_constants_module

    integer          , intent(in   ) :: num_levs
    type(ml_boxarray), intent(inout) :: mba

    ! local
    integer :: n,i

    if (spherical .eq. 0) then
       
       allocate(dr(num_levs))
       allocate(nr(num_levs))

       allocate(  r_cc_loc(num_levs,0:nr_fine-1))
       allocate(r_edge_loc(num_levs,0:nr_fine))
       
       nr(num_levs) = nr_fine
       dr(num_levs) = dr_fine
       do n=num_levs-1,1,-1
          nr(n) = nr(n+1)/mba%rr(n,dm)
          dr(n) = dr(n+1)*dble(mba%rr(n,dm))
       enddo
       
       do n=1,num_levs
          do i = 0,nr(n)-1
             r_cc_loc(n,i) = prob_lo(dm) + (dble(i)+HALF)*dr(n)
          end do
          do i = 0,nr(n)
             r_edge_loc(n,i) = prob_lo(dm) + (dble(i))*dr(n)
          end do
       enddo

    else

       allocate(dr(1))
       allocate(nr(1))

       allocate(  r_cc_loc(1,0:nr_fine-1))
       allocate(r_edge_loc(1,0:nr_fine))
       
       nr(1) = nr_fine
       dr(1) = dr_fine

       do i=0,nr_fine-1
          r_cc_loc(1,i) = prob_lo(dm) + (dble(i)+HALF)*dr(1)
       end do
       
       do i=0,nr_fine
          r_edge_loc(1,i) = prob_lo(dm) + (dble(i))*dr(1)
       end do

    end if

  end subroutine init_radial

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_cutoff(num_levs)

    ! allocates the cutoff coordinate arrays

    integer, intent(in)    :: num_levs

    if (spherical .eq. 0) then
       allocate(      anelastic_cutoff_coord(num_levs))
       allocate(   base_cutoff_density_coord(num_levs))
       allocate(burning_cutoff_density_coord(num_levs))
    else
       allocate(      anelastic_cutoff_coord(1))
       allocate(   base_cutoff_density_coord(1))
       allocate(burning_cutoff_density_coord(1))
    end if

  end subroutine init_cutoff

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_multilevel(mf)

    ! computes numdisjointchunks, r_start_coord, r_end_coord

    use bl_constants_module
    use probin_module, only: prob_lo

    type(multifab) , intent(in   ) :: mf(:)

    ! local
    integer :: i,j,n,maxdisjointchunks,temp

    integer :: lo(dm),hi(dm)

    type(boxarray) :: validboxarr(nlevs)
    type(boxarray) :: diffboxarray(nlevs)
    type(box)      :: boundingbox(nlevs)
    
    if (spherical .eq. 0) then
    
       ! create a "bounding box" for each level
       ! this the smallest possible box that fits every grid at a particular level
       ! this even includes the empty spaces if there are gaps between grids
       do n=1,nlevs
          boundingbox(n) = get_box(mf(n),1)
          do i=2, mf(n)%nboxes
             boundingbox(n) = box_bbox(boundingbox(n),get_box(mf(n),i))
          end do
       end do
       
       ! compute diffboxarray
       ! each box in diffboxarray corresponds to an "empty space" between valid regions
       ! at each level, excluding the coarsest level.
       ! I am going to use this to compute all of the intermediate r_start_coord and 
       ! r_end_coord
       do n=1,nlevs
          call boxarray_build_copy(validboxarr(n),get_boxarray(mf(n)))
          call boxarray_boxarray_diff(diffboxarray(n),boundingbox(n),validboxarr(n))
          call boxarray_simplify(diffboxarray(n))
       end do
       
       if (allocated(numdisjointchunks)) then
          deallocate(numdisjointchunks)
       end if
       allocate(numdisjointchunks(nlevs))
       
       do n=1,nlevs
          numdisjointchunks(n) = diffboxarray(n)%nboxes + 1
       end do
       
       maxdisjointchunks = 1
       do n=2,nlevs
          maxdisjointchunks = max(maxdisjointchunks,numdisjointchunks(n))
       end do
       
       if (allocated(r_start_coord)) then
          deallocate(r_start_coord)
       end if
       allocate(r_start_coord(nlevs,maxdisjointchunks))
       if (allocated(r_end_coord)) then
          deallocate(r_end_coord)
       end if
       allocate(r_end_coord(nlevs,maxdisjointchunks))
       
       do n=1,nlevs

          lo = lwb(boundingbox(n))
          hi = upb(boundingbox(n))
          r_start_coord(n,1) = lo(dm)
          r_end_coord(n,1)   = hi(dm)

          if (diffboxarray(n)%nboxes .gt. 0) then
             do i=1,diffboxarray(n)%nboxes
                lo = lwb(boxarray_get_box(diffboxarray(n),i))
                hi = upb(boxarray_get_box(diffboxarray(n),i))
                r_start_coord(n,i+1) = hi(dm)+1
                r_end_coord(n,i+1)   = lo(dm)-1
             end do

             ! sort start and end coords
             do i=1,diffboxarray(n)%nboxes+1
                do j=1,diffboxarray(n)%nboxes+1-i

                   if (r_start_coord(n,j) .gt. r_start_coord(n,j+1)) then
                      temp = r_start_coord(n,j+1)
                      r_start_coord(n,j+1) = r_start_coord(n,j)
                      r_start_coord(n,j)   = temp
                   end if
                   if (r_end_coord(n,j) .gt. r_end_coord(n,j+1)) then
                      temp = r_end_coord(n,j+1)
                      r_end_coord(n,j+1) = r_end_coord(n,j)
                      r_end_coord(n,j)   = temp
                   end if

                end do
             end do
          end if

       end do

       do n=1,nlevs
          call destroy(validboxarr(n))
          call destroy(diffboxarray(n))
       end do

    else

       if (allocated(numdisjointchunks)) deallocate(numdisjointchunks)
       if (allocated(r_start_coord)) deallocate(r_start_coord)
       if (allocated(r_end_coord)) deallocate(r_end_coord)

       allocate(numdisjointchunks(1))
       allocate(r_start_coord(1,1))
       allocate(r_end_coord(1,1))

       numdisjointchunks(1) = 1
       r_start_coord(1,1) = 0
       r_end_coord(1,1) = nr_fine-1

    end if
  end subroutine init_multilevel

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine init_rotation()

    use probin_module, only: rotational_frequency, co_latitude, radius
    use bl_constants_module, only: M_PI, ZERO

    real(dp_t) :: theta_in_rad

    theta_in_rad = M_PI * co_latitude / 180_dp_t
    
    sin_theta = sin(theta_in_rad)
    cos_theta = cos(theta_in_rad)

    omega = 2 * M_PI * rotational_frequency

    centrifugal_term(1) = - omega * omega * radius * sin_theta * cos_theta
    centrifugal_term(2) = ZERO
    centrifugal_term(3) = - omega * omega * radius * sin_theta * sin_theta

  end subroutine init_rotation

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine destroy_geometry()

    deallocate(dr,r_cc_loc,r_edge_loc,r_start_coord,r_end_coord,nr,numdisjointchunks)
    deallocate(anelastic_cutoff_coord,base_cutoff_density_coord,burning_cutoff_density_coord)

  end subroutine destroy_geometry

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

end module geometry
