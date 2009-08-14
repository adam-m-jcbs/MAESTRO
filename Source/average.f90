! Given a multifab of data (phi), average down to a base state quantity, phibar.
! If we are in plane-parallel, the averaging is at constant height.  
! If we are spherical, then the averaging is done at constant radius.  

module average_module
  
  use bl_types
  use multifab_module
  use ml_layout_module

  implicit none

  private
  public :: average, average_one_level

contains

  subroutine average(mla,phi,phibar,dx,incomp)

    use geometry, only: nr_fine, r_start_coord, r_end_coord, spherical, numdisjointchunks, &
         dm, nlevs, dr
    use bl_prof_module
    use bl_constants_module
    use restrict_base_module
    use probin_module, only: drdxfac

    type(ml_layout), intent(in   ) :: mla
    integer        , intent(in   ) :: incomp
    type(multifab) , intent(in   ) :: phi(:)
    real(kind=dp_t), intent(inout) :: phibar(:,0:)
    real(kind=dp_t), intent(in   ) :: dx(:,:)

    ! local
    real(kind=dp_t), pointer     :: pp(:,:,:,:)
    logical, pointer             :: mp(:,:,:,:)

    type(box)                    :: domain
    integer                      :: domlo(dm),domhi(dm),lo(dm),hi(dm)
    integer                      :: i,j,r,n,ng,nr_crse
    real(kind=dp_t)              :: w_lo,w_hi,del_w,wsix,theta,w_min,w_max
    real(kind=dp_t)              :: Y,Z,coord

    real(kind=dp_t) ::   ncell_proc(nlevs,0:nr_fine-1)
    real(kind=dp_t) ::        ncell(nlevs,0:nr_fine-1)
    real(kind=dp_t) ::  phisum_proc(nlevs,0:nr_fine-1)
    real(kind=dp_t) ::       phisum(nlevs,0:nr_fine-1)

    real(kind=dp_t) :: source_buffer(0:nr_fine-1)
    real(kind=dp_t) :: target_buffer(0:nr_fine-1)

    real(kind=dp_t), allocatable :: ncell_crse(:)
    real(kind=dp_t), allocatable :: phibar_crse(:)

    type(bl_prof_timer), save :: bpt

    call build(bpt, "average")

    ng = phi(1)%ng

    phibar = ZERO

    ncell        = ZERO
    ncell_proc   = ZERO
    phisum       = ZERO       
    phisum_proc  = ZERO

    if (spherical .eq. 0) then
       
       do n=1,nlevs

          domain = layout_get_pd(phi(n)%la)
          domlo  = lwb(domain)
          domhi  = upb(domain)

          if (dm .eq. 1) then
             ncell(n,:) = 1
          else if (dm .eq. 2) then
             ncell(n,:) = domhi(1)-domlo(1)+1
          else if (dm .eq. 3) then
             ncell(n,:) = (domhi(1)-domlo(1)+1)*(domhi(2)-domlo(2)+1)
          end if

          do i=1,phi(n)%nboxes
             if ( multifab_remote(phi(n), i) ) cycle
             pp => dataptr(phi(n), i)
             lo =  lwb(get_box(phi(n), i))
             hi =  upb(get_box(phi(n), i))
             select case (dm)
             case (1)
                call sum_phi_1d(pp(:,1,1,:),phisum_proc(n,:),lo,hi,ng,incomp)
             case (2)
                call sum_phi_2d(pp(:,:,1,:),phisum_proc(n,:),lo,hi,ng,incomp)
             case (3)
                call sum_phi_3d(pp(:,:,:,:),phisum_proc(n,:),lo,hi,ng,incomp)
             end select
          end do

          ! gather phisum
          source_buffer = phisum_proc(n,:)
          call parallel_reduce(target_buffer, source_buffer, MPI_SUM)
          phisum(n,:) = target_buffer
          do i=1,numdisjointchunks(n)
             do r=r_start_coord(n,i),r_end_coord(n,i)
                phibar(n,r) = phisum(n,r) / dble(ncell(n,r))
             end do
          end do

       end do

       call restrict_base(phibar,.true.)
       call fill_ghost_base(phibar,.true.)

    else if(spherical .eq. 1) then

       ! The spherical case is tricky because the base state only exists at 
       ! one level with dr(1) = dx(nlevs) / drdxfac.

       ! Therefore, for each level, we compute a volume weighted
       ! contribution to each radial bin.  Then we sum the
       ! contributions to a coarse radial bin with dr_coarse =
       ! dx(nlevs), then interpolate to fill the fine radial bin.

       ! phisum(nlevs,:) will be the volume weighted sum over all
       ! levels.  ncell(nlevs,:) will be the volume weighted number of
       ! cells over all levels.  we use the convention that a cell
       ! volume of 1.0 corresponds to dx(n=1)**3

       ! We make sure to use mla%mask to not double count cells, i.e.,
       ! we only sum up cells that are not covered by finer cells.

       do n=nlevs,1,-1

          ! First we compute ncell(nlevs,:) and phisum(nlevs,:) as if
          ! the finest level were the only level in existence.  Then
          ! we compute ncell(n,:) and phisum(n,:) for each non-finest
          ! level cell that is not covered by a finer cell
          do i=1,phi(n)%nboxes
             if ( multifab_remote(phi(n), i) ) cycle
             pp => dataptr(phi(n), i)
             lo =  lwb(get_box(phi(n), i))
             hi =  upb(get_box(phi(n), i))

             if (n .eq. nlevs) then
                call sum_phi_3d_sphr(n,pp(:,:,:,:),phisum_proc(n,:), &
                                     lo,hi,ng,dx(n,:),ncell_proc(n,:),incomp)
             else
                mp => dataptr(mla%mask(n), i)
                call sum_phi_3d_sphr(n,pp(:,:,:,:),phisum_proc(n,:), &
                                     lo,hi,ng,dx(n,:),ncell_proc(n,:),incomp, &
                                     mp(:,:,:,1))
             end if
          end do

          source_buffer = ncell_proc(n,:)
          call parallel_reduce(target_buffer, source_buffer, MPI_SUM)
          ncell(n,:) = target_buffer

          source_buffer = phisum_proc(n,:)
          call parallel_reduce(target_buffer, source_buffer, MPI_SUM)
          phisum(n,:) = target_buffer

       end do

       ! now gather ncell and phisum from all the levels and store
       ! them in ncell(nlevs,:) and phisum(nlevs,:)
       do n=nlevs-1,1,-1
          ncell(nlevs,:) = ncell(nlevs,:) + ncell(n,:)
          phisum(nlevs,:) = phisum(nlevs,:) + phisum(n,:)
       end do

       ! fixes the fact that for any given fine radial bin, you get
       ! more contributions from cells which map to the outer half of
       ! the fine radial bin
       do r=0,nr_fine-1
         if (ncell(nlevs,r) .ne. 0) then
             phisum(nlevs,r) = phisum(nlevs,r) / ncell(nlevs,r)
             ncell(nlevs,r) = ONE
          end if
       end do

       ! now compute phibar_crse
       if (drdxfac .ne. 1) then

          if ( mod(nr_fine,drdxfac) .eq. 0 ) then
             nr_crse = nr_fine / drdxfac
          else
             nr_crse = nr_fine / drdxfac + 1
          end if

          ! phibar_crse will have 2 "ghost cells"
          allocate( ncell_crse(0:nr_crse-1))
          allocate(phibar_crse(-2:nr_crse+1))

          ! Sum fine data onto the crse grid
          do r=0,nr_crse-1

             phibar_crse(r) = 0.d0
              ncell_crse(r) = 0.d0

             do j = drdxfac*r, min(drdxfac*r+(drdxfac-1),nr_fine-1)
                phibar_crse(r) = phibar_crse(r) + phisum(nlevs,j)
                 ncell_crse(r) =  ncell_crse(r) +  ncell(nlevs,j)
             end do

          end do

          do r=0,nr_crse-1

             ! Now compute the average
             if (ncell_crse(r) .gt. ZERO) then
                phibar_crse(r) = phibar_crse(r) / ncell_crse(r)
             else
                ! if this is ever the case, it means we are in a very
                ! coarse region far away from the center of the star
                ! so assuming the average stays constant is a
                ! reasonable assumption
                phibar_crse(r) = phibar_crse(r-1)
             end if

          end do

          ! "ghost cells" needed to compute 4th order profiles
          ! Reflect (even) across origin
          phibar_crse(-1) = phibar_crse(0)
          phibar_crse(-2) = phibar_crse(1)

          ! "ghost cells" needed to compute 4th order profiles
          ! Extend using 1st order extrapolation at high r
          phibar_crse(nr_crse  ) = phibar_crse(nr_crse-1)
          phibar_crse(nr_crse+1) = phibar_crse(nr_crse-1)

          ! Put the average back onto the fine grid
          do r=0,nr_crse-1
   
             ! compute the edge states using the PPM reconstruction
             w_lo = ( 7.d0 * (phibar_crse(r  ) + phibar_crse(r-1)) &
                     -1.d0 * (phibar_crse(r+1) + phibar_crse(r-2)) ) / 12.d0
             w_hi = ( 7.d0 * (phibar_crse(r  ) + phibar_crse(r+1)) &
                     -1.d0 * (phibar_crse(r-1) + phibar_crse(r+2)) ) / 12.d0

             w_min = min(phibar_crse(r),phibar_crse(r-1))
             w_max = max(phibar_crse(r),phibar_crse(r-1))
             w_lo = max(w_lo,w_min)
             w_lo = min(w_lo,w_max)

             w_min = min(phibar_crse(r),phibar_crse(r+1))
             w_max = max(phibar_crse(r),phibar_crse(r+1))
             w_hi = max(w_hi,w_min)
             w_hi = min(w_hi,w_max)

             del_w = w_hi - w_lo

             wsix = 6.d0 * ( phibar_crse(r) - 0.5d0 * (w_lo + w_hi) )

             w_min = min(w_lo,w_hi)
             w_max = max(w_lo,w_hi)

             do j = 0, min(drdxfac-1,nr_fine-drdxfac*r-1)

                ! piecewise constant
                ! phibar(1,drdxfac*r+j) = phibar_crse(r)
   
                ! parabolic interpolation
                theta = (dble(j)+0.5d0) / dble(drdxfac)
                phibar(1,drdxfac*r+j) = &
                       w_lo + &
                       theta * del_w + &
                       theta * (1.d0 - theta) * wsix

                phibar(1,drdxfac*r+j) = max(phibar(1,drdxfac*r+j),w_min)
                phibar(1,drdxfac*r+j) = min(phibar(1,drdxfac*r+j),w_max)

             end do

          end do

          ! FIX THE INNER CELLS 
          if (drdxfac .eq. 5) then

             ! fill the inner 8 cells using a quadratic polynomial.
             ! If we know that drdxfac = 5, then we see that the first
             ! two valid data values are radial bins 4 and 8 (using
             ! 0-based indexing).  Together with a Neumann BC at the
             ! center, we fit the quadratic y = a x**2 + c (the 'b x'
             ! term of the general quadratic = 0 by Neumann BC).  
             Y = phisum(nlevs,4)   ! at r = sqrt(3/4) dr
             Z = phisum(nlevs,8)   ! at r = sqrt(11/4) dr
             do j = 0,7
                coord = (dble(j)+HALF) / dble(drdxfac)
                phibar(1,j) = (-HALF*Y+HALF*Z)*dble(coord)**2 &
                     + (11.d0/8.d0)*Y - (3.d0/8.d0)*Z
             end do

             ! for the next set of cells, any 'holes' are guaranteed to
             ! have valid data on either side -- just average
             do j = 8,24
                if (ncell(nlevs,j) .eq. ONE) then
                   phibar(1,j) = phisum(nlevs,j)
                else if (ncell(nlevs,j-1) .eq. ONE .and. &
                         ncell(nlevs,j+1) .eq. ONE) then
                   phibar(1,j) = HALF * (phisum(nlevs,j-1) + phisum(nlevs,j+1))
                else
                   call bl_error("ERROR in average: didnt catch this j")
                end if
             end do
          end if

       else 

          ! if drdxfac = 1 then divide the total phisum by the number
          ! of cells to get phibar
          do r=0,nr_fine-1
             if (ncell(nlevs,r) .gt. ZERO) then
                phibar(1,r) = phisum(nlevs,r) / ncell(nlevs,r)
             else if (r .eq. nr_fine-1) then
                phibar(1,r) = phibar(nlevs,r-1)
             else
                call bl_error("ERROR: ncell_crse=0 in average for drdxfac=1 case")
             end if
          end do

       end if

    endif

    call destroy(bpt)

  end subroutine average

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine sum_phi_1d(phi,phisum,lo,hi,ng,incomp)

    integer         , intent(in   ) :: lo(:), hi(:), ng, incomp
    real (kind=dp_t), intent(in   ) :: phi(lo(1)-ng:,:)
    real (kind=dp_t), intent(inout) :: phisum(0:)

    integer :: i

    do i=lo(1),hi(1)
       phisum(i) = phi(i,incomp)
    end do

  end subroutine sum_phi_1d

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine sum_phi_2d(phi,phisum,lo,hi,ng,incomp)

    integer         , intent(in   ) :: lo(:), hi(:), ng, incomp
    real (kind=dp_t), intent(in   ) :: phi(lo(1)-ng:,lo(2)-ng:,:)
    real (kind=dp_t), intent(inout) :: phisum(0:)

    integer :: i,j

    do j=lo(2),hi(2)
       do i=lo(1),hi(1)
          phisum(j) = phisum(j) + phi(i,j,incomp)
       end do
    end do

  end subroutine sum_phi_2d

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine sum_phi_3d(phi,phisum,lo,hi,ng,incomp)

    integer         , intent(in   ) :: lo(:), hi(:), ng, incomp
    real (kind=dp_t), intent(in   ) :: phi(lo(1)-ng:,lo(2)-ng:,lo(3)-ng:,:)
    real (kind=dp_t), intent(inout) :: phisum(0:)

    integer :: i,j,k

    do k=lo(3),hi(3)
       do j=lo(2),hi(2)
          do i=lo(1),hi(1)
             phisum(k) = phisum(k) + phi(i,j,k,incomp)
          end do
       end do
    end do

  end subroutine sum_phi_3d

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine sum_phi_3d_sphr(n,phi,phisum,lo,hi,ng,dx,ncell,incomp,mask)

    use geometry, only: dr, center
    use ml_layout_module
    use bl_constants_module

    integer         , intent(in   )           :: n, lo(:), hi(:), ng, incomp
    real (kind=dp_t), intent(in   )           :: phi(lo(1)-ng:,lo(2)-ng:,lo(3)-ng:,:)
    real (kind=dp_t), intent(inout)           :: phisum(0:)
    real (kind=dp_t), intent(in   )           :: dx(:)
    real (kind=dp_t), intent(inout)           :: ncell(0:)
    logical         , intent(in   ), optional :: mask(lo(1):,lo(2):,lo(3):)

    ! local
    real (kind=dp_t) :: x, y, z, radius
    integer          :: i, j, k, idx
    real (kind=dp_t) :: cell_weight
    logical          :: cell_valid

    cell_weight = ONE / EIGHT**(n-1)

    do k=lo(3),hi(3)
       z = (dble(k) + HALF)*dx(3) - center(3)

       do j=lo(2),hi(2)
          y = (dble(j) + HALF)*dx(2) - center(2)

          do i=lo(1),hi(1)
             x = (dble(i) + HALF)*dx(1) - center(1)

             cell_valid = .true.
             if ( present(mask) ) then
                if ( (.not. mask(i,j,k)) ) cell_valid = .false.
             end if

             if (cell_valid) then
                radius = sqrt(x**2 + y**2 + z**2)
                idx  = int(radius / dr(1))
                
                phisum(idx) = phisum(idx) + cell_weight*phi(i,j,k,incomp)
                ncell(idx) = ncell(idx) + cell_weight
             end if

          end do
       end do
    end do

  end subroutine sum_phi_3d_sphr

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine average_one_level(n,phi,phibar,incomp)

    use geometry, only: nr_fine, nr, spherical, dm
    use bl_prof_module
    use bl_constants_module

    integer        , intent(in   ) :: n,incomp
    type(multifab) , intent(in   ) :: phi(:)
    real(kind=dp_t), intent(inout) :: phibar(:,0:)

    ! local
    real(kind=dp_t), pointer :: pp(:,:,:,:)
    type(box)                :: domain
    integer                  :: domlo(dm),domhi(dm)
    integer                  :: lo(dm),hi(dm)
    integer                  :: i,r,ng,ncell

    real(kind=dp_t) ::   phisum_proc(0:nr_fine-1)
    real(kind=dp_t) ::        phisum(0:nr_fine-1)
    real(kind=dp_t) :: source_buffer(0:nr_fine-1)
    real(kind=dp_t) :: target_buffer(0:nr_fine-1)

    type(bl_prof_timer), save :: bpt

    call build(bpt, "average_one_level")

    ng = phi(1)%ng

    phibar = ZERO

    ncell        = ZERO
    phisum       = ZERO       
    phisum_proc  = ZERO

    if (spherical .eq. 0) then
       
       domain = layout_get_pd(phi(n)%la)
       domlo  = lwb(domain)
       domhi  = upb(domain)

       if (dm .eq. 1) then
          ncell = 1
       else if (dm .eq. 2) then
          ncell = domhi(1)-domlo(1)+1
       else if (dm .eq. 3) then
          ncell = (domhi(1)-domlo(1)+1)*(domhi(2)-domlo(2)+1)
       end if

       do i=1,phi(n)%nboxes
          if ( multifab_remote(phi(n), i) ) cycle
          pp => dataptr(phi(n), i)
          lo =  lwb(get_box(phi(n), i))
          hi =  upb(get_box(phi(n), i))
          select case (dm)
          case (1)
             call sum_phi_1d(pp(:,1,1,:),phisum_proc,lo,hi,ng,incomp)
          case (2)
             call sum_phi_2d(pp(:,:,1,:),phisum_proc,lo,hi,ng,incomp)
          case (3)
             call sum_phi_3d(pp(:,:,:,:),phisum_proc,lo,hi,ng,incomp)
          end select
       end do

       ! gather phisum
       source_buffer = phisum_proc
       call parallel_reduce(target_buffer, source_buffer, MPI_SUM)
       phisum = target_buffer
       do r=0,nr(n)-1
          phibar(n,r) = phisum(r) / dble(ncell)
       end do

    else if(spherical .eq. 1) then

       call bl_error("average_one_level not written for multilevel spherical")

    end if

    call destroy(bpt)

  end subroutine average_one_level

end module average_module
