module make_S_module

  use bl_types
  use bl_constants_module
  use multifab_module
  use eos_module
  use fill_3d_module
  use network
  use geometry
  use variables

  implicit none

  private
  public :: make_S

contains


!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

  subroutine make_S(nlevs,Source,gamma1_term,state,rho_omegadot,rho_Hext, &
                    thermal,t0,gam1,dx)

    integer        , intent(in   ) :: nlevs
    type(multifab) , intent(inout) :: Source(:)
    type(multifab) , intent(inout) :: gamma1_term(:)
    type(multifab) , intent(in   ) :: state(:)
    type(multifab) , intent(in   ) :: rho_omegadot(:)
    type(multifab) , intent(in   ) :: rho_Hext(:)
    type(multifab) , intent(in   ) :: thermal(:)
    real(kind=dp_t), intent(in   ) :: t0(:,0:)
    real(kind=dp_t), intent(in   ) :: gam1(:,0:)
    real(kind=dp_t), intent(in   ) :: dx(:,:)
    
    real(kind=dp_t), pointer:: srcp(:,:,:,:),gp(:,:,:,:),sp(:,:,:,:)
    real(kind=dp_t), pointer:: tp(:,:,:,:)
    real(kind=dp_t), pointer:: omegap(:,:,:,:), hp(:,:,:,:)
    integer :: lo(state(1)%dim),hi(state(1)%dim),ng,dm
    integer :: i,n
    
    ng = state(1)%ng
    dm = state(1)%dim

    do n = 1, nlevs

       do i = 1, state(n)%nboxes
          if ( multifab_remote(state(n), i) ) cycle
          srcp => dataptr(Source(n), i)
          gp     => dataptr(gamma1_term(n), i)
          sp     => dataptr(state(n), i)
          omegap => dataptr(rho_omegadot(n), i)
          hp     => dataptr(rho_Hext(n), i)
          tp     => dataptr(thermal(n), i)
          lo = lwb(get_box(state(n), i))
          hi = upb(get_box(state(n), i))
          select case (dm)
          case (2)
             call make_S_2d(lo,hi,srcp(:,:,1,1),gp(:,:,1,1),sp(:,:,1,:), &
                            omegap(:,:,1,:), hp(:,:,1,1), &
                            tp(:,:,1,1), ng, gam1(n,:), dx(n,:))
          case (3)
             call make_S_3d(lo,hi,srcp(:,:,:,1),gp(:,:,:,1),sp(:,:,:,:), &
                            omegap(:,:,:,:), hp(:,:,:,1), &
                            tp(:,:,:,1), ng, t0(n,:), gam1(n,:), dx(n,:))
          end select
       end do

       call multifab_fill_boundary(Source(n))

    enddo

   end subroutine make_S

   subroutine make_S_2d (lo,hi,Source,gamma1_term,s, &
                         rho_omegadot,rho_Hext,thermal,ng,gam1,dx)

      implicit none

      integer         , intent(in   ) :: lo(:), hi(:), ng
      real (kind=dp_t), intent(  out) :: Source(lo(1):,lo(2):)
      real (kind=dp_t), intent(  out) :: gamma1_term(lo(1):,lo(2):)
      real (kind=dp_t), intent(in   ) :: s(lo(1)-ng:,lo(2)-ng:,:)
      real (kind=dp_t), intent(in   ) :: rho_omegadot(lo(1):,lo(2):,:)
      real (kind=dp_t), intent(in   ) :: rho_Hext(lo(1):,lo(2):)
      real (kind=dp_t), intent(in   ) :: thermal(lo(1)-1:,lo(2)-1:)
      real (kind=dp_t), intent(in   ) :: gam1(0:)
      real (kind=dp_t), intent(in   ) :: dx(:)

!     Local variables
      integer :: i, j, comp

      real(kind=dp_t) :: sigma, react_term, pres_term

      Source = zero

      do_diag = .false.

      do j = lo(2), hi(2)
        do i = lo(1), hi(1)

           den_eos(1) = s(i,j,rho_comp)
           temp_eos(1) = s(i,j,temp_comp)
           xn_eos(1,:) = s(i,j,spec_comp:spec_comp+nspec-1)/den_eos(1)
           
           ! dens, temp, and xmass are inputs
           call eos(eos_input_rt, den_eos, temp_eos, &
                    npts, nspec, &
                    xn_eos, &
                    p_eos, h_eos, e_eos, & 
                    cv_eos, cp_eos, xne_eos, eta_eos, pele_eos, &
                    dpdt_eos, dpdr_eos, dedt_eos, dedr_eos, &
                    dpdX_eos, dhdX_eos, &
                    gam1_eos, cs_eos, s_eos, &
                    dsdt_eos, dsdr_eos, &
                    do_diag)

           sigma = dpdt_eos(1) / (den_eos(1) * cp_eos(1) * dpdr_eos(1))

           react_term = ZERO
           pres_term = ZERO
           do comp = 1, nspec
              react_term = react_term - &
                   (dhdX_eos(1,comp) + ebin(comp))*rho_omegadot(i,j,comp)/den_eos(1)

              pres_term = pres_term + &
                   dpdX_eos(1,n)*rho_omegadot(i,j,n)/den_eos(1)
           enddo

           Source(i,j) = (sigma/den_eos(1)) * ( rho_Hext(i,j) + thermal(i,j) ) &
                        + sigma*react_term &
                        + pres_term/(den_eos(1)*dpdr_eos(1))

           gamma1_term(i,j) = 0.0_dp_t

        enddo
      enddo
 
   end subroutine make_S_2d

   subroutine make_S_3d (lo,hi,Source,gamma1_term,s, &
                         rho_omegadot,rho_Hext,thermal,ng,t0,gam1,dx)

      implicit none

      integer         , intent(in   ) :: lo(:), hi(:), ng
      real (kind=dp_t), intent(  out) :: Source(lo(1):,lo(2):,lo(3):)  
      real (kind=dp_t), intent(  out) :: gamma1_term(lo(1):,lo(2):,lo(3):)  
      real (kind=dp_t), intent(in   ) :: s(lo(1)-ng:,lo(2)-ng:,lo(3)-ng:,:)
      real (kind=dp_t), intent(in   ) :: rho_omegadot(lo(1):,lo(2):,lo(3):,:)
      real (kind=dp_t), intent(in   ) :: rho_Hext(lo(1):,lo(2):,lo(3):)
      real (kind=dp_t), intent(in   ) :: thermal(lo(1)-1:,lo(2)-1:,lo(3)-1:)
      real (kind=dp_t), intent(in   ) :: t0(0:)
      real (kind=dp_t), intent(in   ) :: gam1(0:)
      real (kind=dp_t), intent(in   ) :: dx(:)

!     Local variables
      integer :: i, j, k, comp

      real(kind=dp_t), allocatable :: t0_cart(:,:,:)
      real(kind=dp_t) :: sigma, react_term, pres_term

      if (spherical .eq. 1) then
        allocate(t0_cart(lo(1):hi(1),lo(2):hi(2),lo(3):hi(3)))
        call fill_3d_data(t0_cart,t0,lo,hi,dx,0)
      end if

      Source = zero

      do_diag = .false.

      do k = lo(3), hi(3)
        do j = lo(2), hi(2)
           do i = lo(1), hi(1)

              den_eos(1) = s(i,j,k,rho_comp)
              if (spherical .eq. 0) then
                temp_eos(1) = s(i,j,k,temp_comp)
              else
                temp_eos(1) = t0_cart(i,j,k)
              end if
              xn_eos(1,:) = s(i,j,k,spec_comp:spec_comp+nspec-1)/den_eos(1)

              ! dens, temp, and xmass are inputs
              call eos(eos_input_rt, den_eos, temp_eos, &
                       npts, nspec, &
                       xn_eos, &
                       p_eos, h_eos, e_eos, & 
                       cv_eos, cp_eos, xne_eos, eta_eos, pele_eos, &
                       dpdt_eos, dpdr_eos, dedt_eos, dedr_eos, &
                       dpdX_eos, dhdX_eos, &
                       gam1_eos, cs_eos, s_eos, &
                       dsdt_eos, dsdr_eos, &
                       do_diag)

              sigma = dpdt_eos(1) / (den_eos(1) * cp_eos(1) * dpdr_eos(1))

              react_term = ZERO
              pres_term = ZERO
              do comp = 1, nspec
                 react_term = react_term - &
                      (dhdX_eos(1,comp) + ebin(comp))*rho_omegadot(i,j,k,comp)/den_eos(1)

                 pres_term = pres_term + &
                      dpdX_eos(1,n)*rho_omegadot(i,j,k,n)/den_eos(1)
              enddo

              Source(i,j,k) = (sigma/den_eos(1)) * ( rho_Hext(i,j,k) + thermal(i,j,k) ) &
                           + sigma*react_term &
                           + pres_term/(den_eos(1)*dpdr_eos(1))

              gamma1_term(i,j,k) = 0.0_dp_t
           enddo
        enddo
      enddo

      if (spherical .eq. 1) then
        deallocate(t0_cart)
      end if
 
   end subroutine make_S_3d

end module make_S_module
