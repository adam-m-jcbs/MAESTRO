! The sponge acts to damp the velocities at the edge of the star.

module sponge_module

  use bl_types
  use bl_constants_module
  use multifab_module
  use ml_layout_module

  implicit none

  real(dp_t), save :: r_sp, r_md, r_tp
  real(dp_t), save :: r_sp_outer, r_tp_outer

  private

  public :: init_sponge, make_sponge

contains

  subroutine init_sponge(rho0,dx,prob_lo_r)

    ! The sponge has a HALF * ( 1 - cos( (r - r_sp)/L)) profile, where
    ! the width, L, is r_tp - r_sp.
    !
    ! The center of the sponge, r_md, is set to the radius where r =
    ! sponge_center_density
    !
    ! The start of the sponge, r_sp, (moving outward from the center)
    ! is the radius where r = sponge_start_factor * sponge_center_density
    ! 
    ! The top of the sponge is then 2 * r_md - r_tp

    use geometry, only: dr, r_end_coord
    use bl_constants_module
    use probin_module, only: anelastic_cutoff, prob_hi, verbose, &
         sponge_start_factor, sponge_center_density

    real(kind=dp_t), intent(in   ) :: rho0(0:),prob_lo_r
    real(kind=dp_t), intent(in   ) :: dx(:)

    real (kind = dp_t) :: rloc
    real (kind = dp_t) :: r_top
    integer            :: r

    r_top = prob_lo_r + dble(r_end_coord(1,1)+1) * dr(1)
    r_sp = r_top

    ! set r_sp
    do r=0,r_end_coord(1,1)
       rloc = prob_lo_r + (dble(r)+HALF) * dr(1)
       if (rho0(r) < sponge_start_factor*sponge_center_density) then
          r_sp = rloc
          exit
       endif
    enddo

    ! set r_md
    r_md = r_top
    do r=0,r_end_coord(1,1)
       rloc = prob_lo_r + (dble(r)+HALF) * dr(1)
       if (rho0(r) < sponge_center_density) then
          r_md = rloc
          exit
       endif
    enddo

    ! set r_tp
    r_tp = TWO * r_md - r_sp

    ! outer sponge parameters
    r_tp_outer = HALF * max(prob_hi(1),prob_hi(2)) 
    if (size(prob_hi,dim=1) .eq. 2) then
       r_sp_outer = r_tp_outer - 4.d0 * dx(2)
    else
       r_tp_outer = max(r_tp_outer, HALF * prob_hi(3)) 
       r_sp_outer = r_tp_outer - 4.d0 * dx(3)
    end if

    if ( parallel_IOProcessor() .and. verbose .ge. 1) write(6,1000) r_sp, r_tp
    if ( parallel_IOProcessor() .and. verbose .ge. 1) write(6,1001) r_sp_outer, r_tp_outer
    if ( parallel_IOProcessor() .and. verbose .ge. 1) print*,""

1000 format('inner sponge: r_sp      , r_tp      : ',e20.12,2x,e20.12)
1001 format('outer sponge: r_sp_outer, r_tp_outer: ',e20.12,2x,e20.12)

  end subroutine init_sponge

  subroutine make_sponge(sponge,dx,dt,mla)

    use bl_constants_module
    use ml_restriction_module, only: ml_cc_restriction
    use geometry, only: dm, nlevs

    type(multifab) , intent(inout) :: sponge(:)
    real(kind=dp_t), intent(in   ) :: dx(:,:),dt
    type(ml_layout), intent(in   ) :: mla

    ! Local variables
    real(kind=dp_t), pointer :: sp(:,:,:,:)
    integer :: i,n,ng_sp
    integer :: lo(dm),hi(dm)

    ng_sp = sponge(1)%ng

    do n=1,nlevs

       do i = 1, sponge(n)%nboxes
          if ( multifab_remote(sponge(n), i) ) cycle
          sp => dataptr(sponge(n), i)
          lo =  lwb(get_box(sponge(n), i))
          hi =  upb(get_box(sponge(n), i))
          select case (dm)
          case (2)
             call bl_error("ERROR: no 2-D sponge implemented")
          case (3)
             call mk_sponge_3d(sp(:,:,:,1),ng_sp,lo,hi,dx(n,:),dt)
          end select
       end do

    end do

    ! the loop over nlevs must count backwards to make sure the finer grids are done first
    do n=nlevs,2,-1
       ! set level n-1 data to be the average of the level n data covering it
       call ml_cc_restriction(sponge(n-1),sponge(n),mla%mba%rr(n-1,:))
    end do

  end subroutine make_sponge


  subroutine mk_sponge_3d(sponge,ng_sp,lo,hi,dx,dt)

    use geometry, only: spherical, center
    use bl_constants_module
    use probin_module, only: prob_lo, sponge_kappa

    integer        , intent(in   ) :: lo(:),hi(:), ng_sp
    real(kind=dp_t), intent(inout) :: sponge(lo(1)-ng_sp:,lo(2)-ng_sp:,lo(3)-ng_sp:)
    real(kind=dp_t), intent(in   ) :: dx(:),dt

    integer         :: i,j,k
    real(kind=dp_t) :: x,y,z,r,smdamp

    sponge = ONE

    if (spherical .eq. 0) then
       call bl_error("ERROR: 3-D Cartesian sponge not implemented")

    else

       do k = lo(3),hi(3)
          z = prob_lo(3) + (dble(k)+HALF)*dx(3)

          do j = lo(2),hi(2)
             y = prob_lo(2) + (dble(j)+HALF)*dx(2)

             do i = lo(1),hi(1)
                x = prob_lo(1) + (dble(i)+HALF)*dx(1)

                r = sqrt( (x-center(1))**2 + (y-center(2))**2 + (z-center(3))**2 )

                ! Inner sponge: damps velocities at edge of star
                if (r >= r_sp) then
                   if (r < r_tp) then
                      smdamp = HALF*(ONE - cos(M_PI*(r - r_sp)/(r_tp - r_sp)))
                   else
                      smdamp = ONE
                   endif
                   sponge(i,j,k) = ONE / (ONE + dt * smdamp * sponge_kappa)
                endif

                ! Outer sponge: damps velocities at edge of domain
                if (r >= r_sp_outer) then
                   if (r < r_tp_outer) then
                      smdamp = &
                           HALF*(ONE - cos(M_PI*(r - r_sp_outer)/(r_tp_outer - r_sp_outer)))
                   else
                      smdamp = ONE
                   endif
                   sponge(i,j,k) = sponge(i,j,k) / (ONE + dt * smdamp * 10.d0 * sponge_kappa)
                endif

             end do
          end do
       end do

    end if

  end subroutine mk_sponge_3d

end module sponge_module
