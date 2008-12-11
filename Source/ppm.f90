module ppm_module

  use bl_types

  implicit none

  private

  public :: ppm_2d, ppm_fpu_2d, ppm_3d, ppm_fpu_3d

contains

  ! characteristics based on u
  subroutine ppm_2d(s,ng_s,u,ng_u,Ip,Im,lo,hi,bc,dx,dt)

    use bc_module
    use bl_constants_module

    integer        , intent(in   ) :: lo(:),hi(:),ng_s,ng_u
    real(kind=dp_t), intent(in   ) ::   s(lo(1)-ng_s:,lo(2)-ng_s:)
    real(kind=dp_t), intent(in   ) ::   u(lo(1)-ng_u:,lo(2)-ng_u:,:)
    real(kind=dp_t), intent(inout) ::  Ip(lo(1)-1   :,lo(2)-1   :,:) 
    real(kind=dp_t), intent(inout) ::  Im(lo(1)-1   :,lo(2)-1   :,:) 
    integer        , intent(in   ) :: bc(:,:,:)
    real(kind=dp_t), intent(in   ) :: dx(:),dt

    ! local
    integer :: i,j

    real(kind=dp_t) :: dsl, dsr, dsc, sigma, s6

    ! cell-centered indexing
    ! s_{\ib,+}, s_{\ib,-}
    real(kind=dp_t) :: sp(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+1,2)
    real(kind=dp_t) :: sm(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+1,2)

    ! \delta s_{\ib}^{vL}
    real(kind=dp_t) :: dsvl_x(lo(1)-2:hi(1)+2,lo(2)-1:hi(2)+1)
    real(kind=dp_t) :: dsvl_y(lo(1)-1:hi(1)+1,lo(2)-2:hi(2)+2)

    ! edge-centered indexing
    real(kind=dp_t) :: sedgex(lo(1)-1:hi(1)+2,lo(2)-1:hi(2)+1)
    real(kind=dp_t) :: sedgey(lo(1)-1:hi(1)+1,lo(2)-1:hi(2)+2)

    ! compute van Leer slopes in x-direction
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-2,hi(1)+2
          dsc = HALF * (s(i+1,j) - s(i-1,j))
          dsl = TWO  * (s(i  ,j) - s(i-1,j))
          dsr = TWO  * (s(i+1,j) - s(i  ,j))
          dsvl_x(i,j) = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
       end do
    end do

    ! interpolate s to x-edges
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-1,hi(1)+2
          sedgex(i,j) = HALF*(s(i,j)+s(i-1,j)) - SIXTH*(dsvl_x(i,j)-dsvl_x(i-1,j))
          ! make sure sedgex lies in between adjacent cell-centered values
          sedgex(i,j) = max(sedgex(i,j),min(s(i,j),s(i-1,j)))
          sedgex(i,j) = min(sedgex(i,j),max(s(i,j),s(i-1,j)))
       end do
    end do

    ! fill x-component of sp and sm
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-1,hi(1)+1
          sp(i,j,1) = sedgex(i+1,j)
          sm(i,j,1) = sedgex(i  ,j)
       end do
    end do

    ! different stencil needed for EXT_DIR and HOEXTRAP bc's
    !
    !
    !

    ! modify sp and sm using quadratic limiters
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-1,hi(1)+1
          if ((sp(i,j,1)-s(i,j))*(s(i,j)-sm(i,j,1)) .le. ZERO) then
             sp(i,j,1) = s(i,j)
             sm(i,j,1) = s(i,j)
          end if
          if (abs(sp(i,j,1)-s(i,j)) .ge. TWO*abs(sm(i,j,1)-s(i,j))) then
             sp(i,j,1) = THREE*s(i,j) - TWO*sm(i,j,1)
          end if
          if (abs(sm(i,j,1)-s(i,j)) .ge. TWO*abs(sp(i,j,1)-s(i,j))) then
             sm(i,j,1) = THREE*s(i,j) - TWO*sp(i,j,1)
          end if
       end do
    end do

    ! compute Ip and Im
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-1,hi(1)+1
          sigma = abs(u(i,j,1))*dt/dx(1)
          s6 = SIX*s(i,j) - THREE*(sm(i,j,1)+sp(i,j,1))
          Ip(i,j,1) = sp(i,j,1) - (sigma/TWO)*(sp(i,j,1)-sm(i,j,1)-(ONE-TWO3RD*sigma)*s6)
          Im(i,j,1) = sm(i,j,1) + (sigma/TWO)*(sp(i,j,1)-sm(i,j,1)+(ONE-TWO3RD*sigma)*s6)
       end do
    end do

    ! compute van Leer slopes in y-direction
    do j=lo(2)-2,hi(2)+2
       do i=lo(1)-1,hi(1)+1
          dsc = HALF * (s(i,j+1) - s(i,j-1))
          dsl = TWO  * (s(i,j  ) - s(i,j-1))
          dsr = TWO  * (s(i,j+1) - s(i,j  ))
          dsvl_y(i,j) = sign(ONE,dsc)*min(abs(dsc),abs(dsl),abs(dsr))
       end do
    end do

    ! interpolate s to y-edges
    do j=lo(2)-1,hi(2)+2
       do i=lo(1)-1,hi(1)+1
          sedgey(i,j) = HALF*(s(i,j)+s(i,j-1)) - SIXTH*(dsvl_y(i,j)-dsvl_y(i,j-1))
          ! make sure sedgey lies in between adjacent cell-centered values
          sedgey(i,j) = max(sedgey(i,j),min(s(i,j),s(i,j-1)))
          sedgey(i,j) = min(sedgey(i,j),max(s(i,j),s(i,j-1)))
       end do
    end do

    ! fill sedgey
    do j=lo(2)-1,hi(2)+2
       do i=lo(1)-1,hi(1)+1
          sp(i,j,2) = sedgex(i,j+1)
          sm(i,j,2) = sedgex(i,j  )
       end do
    end do

    ! different stencil needed for EXT_DIR and HOEXTRAP bc's
    !
    !
    !

    ! modify sp and sm using quadratic limiters
    ! modify sp and sm using quadratic limiters
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-1,hi(1)+1
          if ((sp(i,j,2)-s(i,j))*(s(i,j)-sm(i,j,2)) .le. ZERO) then
             sp(i,j,2) = s(i,j)
             sm(i,j,2) = s(i,j)
          end if
          if (abs(sp(i,j,2)-s(i,j)) .ge. TWO*abs(sm(i,j,2)-s(i,j))) then
             sp(i,j,2) = THREE*s(i,j) - TWO*sm(i,j,2)
          end if
          if (abs(sm(i,j,2)-s(i,j)) .ge. TWO*abs(sp(i,j,2)-s(i,j))) then
             sm(i,j,2) = THREE*s(i,j) - TWO*sp(i,j,2)
          end if
       end do
    end do

    ! compute Ip and Im
    do j=lo(2)-1,hi(2)+1
       do i=lo(1)-1,hi(1)+1
          sigma = abs(u(i,j,2))*dt/dx(2)
          s6 = SIX*s(i,j) - THREE*(sm(i,j,2)+sp(i,j,2))
          Ip(i,j,2) = sp(i,j,2) - (sigma/TWO)*(sp(i,j,2)-sm(i,j,2)-(ONE-TWO3RD*sigma)*s6)
          Im(i,j,2) = sm(i,j,2) + (sigma/TWO)*(sp(i,j,2)-sm(i,j,2)+(ONE-TWO3RD*sigma)*s6)
       end do
    end do

  end subroutine ppm_2d

  ! characteristics based on umac
  subroutine ppm_fpu_2d(s,ng_s,umac,ng_u,Ip,Im,lo,hi,bc,dx,dt)

    use bc_module
    use bl_constants_module

    integer        , intent(in   ) :: lo(:),hi(:),ng_s,ng_u
    real(kind=dp_t), intent(in   ) ::    s(lo(1)-ng_s:,lo(2)-ng_s:)
    real(kind=dp_t), intent(in   ) :: umac(lo(1)-ng_u:,lo(2)-ng_u:,:)
    real(kind=dp_t), intent(inout) ::   Ip(lo(1)-1   :,lo(2)-1   :,:) 
    real(kind=dp_t), intent(inout) ::   Im(lo(1)-1   :,lo(2)-1   :,:) 
    integer        , intent(in   ) :: bc(:,:,:)
    real(kind=dp_t), intent(in   ) :: dx(:),dt

    ! local



  end subroutine ppm_fpu_2d

  ! characteristics based on u
  subroutine ppm_3d(s,ng_s,u,ng_u,Ip,Im,slz,lo,hi,bc,dx,dt)

    use bc_module
    use bl_constants_module

    integer        , intent(in   ) :: lo(:),hi(:),ng_s,ng_u
    real(kind=dp_t), intent(in   ) ::   s(lo(1)-ng_s:,lo(2)-ng_s:,hi(3)-ng_s:)
    real(kind=dp_t), intent(in   ) ::   u(lo(1)-ng_u:,lo(2)-ng_u:,hi(3)-ng_u:,:)
    real(kind=dp_t), intent(inout) ::  Ip(lo(1)-1   :,lo(2)-1   :,hi(3)-1   :,:) 
    real(kind=dp_t), intent(inout) ::  Im(lo(1)-1   :,lo(2)-1   :,hi(3)-1   :,:)  
    real(kind=dp_t), intent(inout) :: slz(lo(1)-1   :,lo(2)-1   :,hi(3)-1   :,:)
    integer        , intent(in   ) :: bc(:,:,:)
    real(kind=dp_t), intent(in   ) :: dx(:),dt

    ! local



  end subroutine ppm_3d

  ! characteristics based on umac
  subroutine ppm_fpu_3d(s,ng_s,umac,ng_u,Ip,Im,slz,lo,hi,bc,dx,dt)

    use bc_module
    use bl_constants_module

    integer        , intent(in   ) :: lo(:),hi(:),ng_s,ng_u
    real(kind=dp_t), intent(in   ) ::    s(lo(1)-ng_s:,lo(2)-ng_s:,hi(3)-ng_s:)
    real(kind=dp_t), intent(in   ) :: umac(lo(1)-ng_u:,lo(2)-ng_u:,hi(3)-ng_u:,:)
    real(kind=dp_t), intent(inout) ::   Ip(lo(1)-1   :,lo(2)-1   :,hi(3)-1   :,:) 
    real(kind=dp_t), intent(inout) ::   Im(lo(1)-1   :,lo(2)-1   :,hi(3)-1   :,:)  
    real(kind=dp_t), intent(inout) ::  slz(lo(1)-1   :,lo(2)-1   :,hi(3)-1   :,:)
    integer        , intent(in   ) :: bc(:,:,:)
    real(kind=dp_t), intent(in   ) :: dx(:),dt

    ! local



  end subroutine ppm_fpu_3d


end module ppm_module
