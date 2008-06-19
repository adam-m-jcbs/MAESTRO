module make_plotfile_module

  use bl_types
  use multifab_module
  use define_bc_module
  use ml_boxarray_module

  implicit none

  private
  public :: get_plot_names, make_plotfile

contains

  subroutine get_plot_names(dm,plot_names)

    use plot_variables_module
    use variables
    use network, only: nspec, short_spec_names
    use probin_module, only: plot_spec, plot_trac, plot_base
    use geometry, only: spherical

    integer          , intent(in   ) :: dm
    character(len=20), intent(inout) :: plot_names(:)

    ! Local variables
    integer :: comp

    plot_names(icomp_vel  ) = "x_vel"
    plot_names(icomp_vel+1) = "y_vel"
    if (dm > 2) then
       plot_names(icomp_vel+2) = "z_vel"
    end if
    plot_names(icomp_rho)  = "density"
    plot_names(icomp_rhoh) = "rhoh"

    if (plot_spec) then
       do comp = 1, nspec
          plot_names(icomp_spec+comp-1) = "X(" // trim(short_spec_names(comp)) // ")"
       end do
    end if

    if (plot_trac) then
       do comp = 1, ntrac
          plot_names(icomp_trac+comp-1) = "tracer"
       end do
    end if

    if (plot_base) then
       plot_names(icomp_w0)   = "w0_x"
       plot_names(icomp_w0+1) = "w0_y"
       if (dm > 2) plot_names(icomp_w0+2) = "w0_z"
       plot_names(icomp_rho0) = "rho0"
       plot_names(icomp_p0)   = "p0"
    end if

    if (spherical .eq. 1) then
       plot_names(icomp_velr) = "radial_velocity"
    endif

    plot_names(icomp_magvel)   = "magvel"
    plot_names(icomp_velplusw0) = "velplusw0"
    plot_names(icomp_mom)      = "momentum"
    plot_names(icomp_vort)     = "vort"
    plot_names(icomp_divu)     = "divu"
    plot_names(icomp_enthalpy) = "enthalpy"
    plot_names(icomp_rhopert)  = "rhopert"
    plot_names(icomp_tfromp)   = "tfromp"
    plot_names(icomp_tfromH)   = "tfromh"
    plot_names(icomp_tpert)    = "tpert"
    plot_names(icomp_machno)   = "Machnumber"
    plot_names(icomp_dp)       = "deltap"
    plot_names(icomp_dg)       = "deltagamma"
    plot_names(icomp_dT)       = "deltaT"
    plot_names(icomp_sponge)   = "sponge"
    plot_names(icomp_gp)       = "gpx"
    plot_names(icomp_gp+1)     = "gpy"
    if (dm > 2) plot_names(icomp_gp+2) = "gpz"

    if (plot_spec) then
       do comp = 1, nspec
          plot_names(icomp_omegadot+comp-1) = &
               "omegadot(" // trim(short_spec_names(comp)) // ")"
       end do
       plot_names(icomp_enuc) = "enucdot"
    end if

  end subroutine get_plot_names

  subroutine make_plotfile(dirname,mla,u,s,gpres,rho_omegadot,Source,sponge,&
                           mba,plot_names,time,dx,the_bc_tower,w0,rho0,p0,tempbar, &
                           gamma1bar,normal)

    use bl_prof_module
    use fabio_module
    use vort_module
    use variables
    use plot_variables_module
    use fill_3d_module
    use probin_module, only: nOutFiles, lUsingNFiles, plot_spec, plot_trac, plot_base
    use probin_module, only: single_prec_plotfiles
    use geometry, only: spherical

    character(len=*) , intent(in   ) :: dirname
    type(ml_layout)  , intent(in   ) :: mla
    type(multifab)   , intent(inout) :: u(:)
    type(multifab)   , intent(inout) :: s(:)
    type(multifab)   , intent(in   ) :: gpres(:)
    type(multifab)   , intent(in   ) :: rho_omegadot(:)
    type(multifab)   , intent(in   ) :: Source(:)
    type(multifab)   , intent(in   ) :: sponge(:)
    type(ml_boxarray), intent(in   ) :: mba
    character(len=20), intent(in   ) :: plot_names(:)
    real(dp_t)       , intent(in   ) :: time,dx(:,:)
    type(bc_tower)   , intent(in   ) :: the_bc_tower
    real(dp_t)       , intent(in   ) :: w0(:,0:)
    real(dp_t)       , intent(in   ) :: rho0(:,0:)
    real(dp_t)       , intent(in   ) :: p0(:,0:)
    real(dp_t)       , intent(in   ) :: tempbar(:,0:)
    real(dp_t)       , intent(in   ) :: gamma1bar(:,0:)
    type(multifab)   , intent(in   ) :: normal(:)

    type(multifab) :: plotdata(mla%nlevel)
    type(multifab) :: tempfab(mla%nlevel)

    integer :: n,dm,nlevs,prec

    type(bl_prof_timer), save :: bpt

    call build(bpt, "make_plotfile")

    dm = get_dim(mba)
    nlevs = size(u)

    if (single_prec_plotfiles) then
       prec = FABIO_SINGLE
    else
       prec = FABIO_DOUBLE
    endif

    do n = 1,nlevs

       call multifab_build(plotdata(n), mla%la(n), n_plot_comps, 0)
       call multifab_build(tempfab(n), mla%la(n), dm, 0)
       
       ! VELOCITY 
       call multifab_copy_c(plotdata(n),icomp_vel,u(n),1,dm)

       ! DENSITY AND (RHO H) 
       call multifab_copy_c(plotdata(n),icomp_rho,s(n),rho_comp,2)

       ! SPECIES
       if (plot_spec) then
          call make_XfromrhoX(plotdata(n),icomp_spec,s(n))
       end if

       ! TRACER
       if (plot_trac .and. ntrac .ge. 1) then
          call multifab_copy_c(plotdata(n),icomp_trac,s(n),trac_comp,ntrac)
       end if

    end do

    if (plot_base) then

       ! w0
       call put_1d_array_on_cart(nlevs,w0,tempfab,1,.true.,.true.,dx, &
                                 the_bc_tower%bc_tower_array,mla,normal=normal)

       do n=1,nlevs
          call multifab_copy_c(plotdata(n),icomp_w0,tempfab(n),1,dm)
       end do

       ! rho0
       call put_1d_array_on_cart(nlevs,rho0,tempfab,dm+rho_comp,.false.,.false.,dx, &
                                 the_bc_tower%bc_tower_array,mla,normal=normal)

       do n=1,nlevs
          call multifab_copy_c(plotdata(n),icomp_rho0,tempfab(n),1,1)
       end do

       ! p0
       call put_1d_array_on_cart(nlevs,p0,tempfab,foextrap_comp,.false.,.false.,dx, &
                                 the_bc_tower%bc_tower_array,mla,normal=normal)
       do n=1,nlevs
          call multifab_copy_c(plotdata(n),icomp_p0,tempfab(n),1,1)
       end do

    end if

    do n = 1,nlevs

       ! MAGVEL & MOMENTUM
       call make_magvel (plotdata(n),icomp_magvel,icomp_mom,u(n),s(n))

       ! RADIAL VELOCITY (spherical only)
       if (spherical .eq. 1) then
          call make_velr (plotdata(n),icomp_velr,u(n),normal(n))
       endif

       ! VEL_PLUS_W0
       call make_velplusw0 (n,plotdata(n),icomp_velplusw0,u(n),w0(n,:),normal(n),dx(n,:))

       ! VORTICITY
       call make_vorticity(plotdata(n),icomp_vort,u(n),dx(n,:), &
                           the_bc_tower%bc_tower_array(n))

       ! DIVU
       call multifab_copy_c(plotdata(n),icomp_divu,Source(n),1,1)

       ! ENTHALPY 
       call make_enthalpy(plotdata(n),icomp_enthalpy,s(n))

       ! RHOPERT & TEMP (FROM RHO) & TPERT & MACHNO & (GAM1 - GAM10)
       call make_tfromp(n,plotdata(n),icomp_tfromp,icomp_tpert,icomp_rhopert, &
                          icomp_machno,icomp_dg,s(n),u(n),rho0(n,:), &
                          tempbar(n,:),gamma1bar(n,:),p0(n,:),dx(n,:))

       ! TEMP (FROM H) & DELTA_P
       call make_tfromH(n,plotdata(n),icomp_tfromH,icomp_dp,s(n),p0(n,:), &
                        tempbar(n,:),dx(n,:))
       
       ! DIFF BETWEEN TFROMP AND TFROMH
       call make_deltaT (plotdata(n),icomp_dT,icomp_tfromp,icomp_tfromH)

       ! PRESSURE GRADIENT
       call multifab_copy_c(plotdata(n),icomp_gp,gpres(n),1,dm)

       ! SPONGE
       call multifab_copy_c(plotdata(n),icomp_sponge,sponge(n),1,1)

    end do

    if (plot_spec) then
       ! OMEGADOT
       do n = 1,nlevs
          call make_omegadot(plotdata(n),icomp_omegadot,icomp_enuc,s(n),rho_omegadot(n))
       end do
    end if

    call fabio_ml_multifab_write_d(plotdata, mba%rr(:,1), dirname, plot_names, &
                                   mba%pd(1), time, dx(1,:), nOutFiles = nOutFiles, &
                                   lUsingNFiles = lUsingNFiles, prec = prec)
    do n = 1,nlevs
       call destroy(plotdata(n))
       call destroy(tempfab(n))
    end do

    call destroy(bpt)

  end subroutine make_plotfile

end module make_plotfile_module
