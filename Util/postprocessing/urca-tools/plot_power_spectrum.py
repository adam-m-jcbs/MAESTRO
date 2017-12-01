#!/usr/bin/env python
import numpy as np
import matplotlib.pyplot as plt
import yt
import argparse

"""
Make a turbulent KE power spectrum.  Since we are stratified, we use
a rho**(1/3) scaling to the velocity to get something that would
look Kolmogorov (if the turbulence were fully developed).

Ultimately, we aim to compute:

                      1  ^      ^*                                           
     E(k) = integral  -  V(k) . V(k) dS                                      
                      2                                                      
 
             n                                                              
where V = rho  U is the density-weighted velocity field.
 
(Note: sometimes we normalize by 1/volume to get a spectral
energy density spectrum).


"""

parser = argparse.ArgumentParser()
parser.add_argument('pltfile', type=str,
                    help='Name of pltfile for which to compute the power spectrum.')
parser.add_argument('-emin', '--energy_min', type=float,
                    help='Minimum E(k) to use for the vertical plot axis.')
parser.add_argument('-emax', '--energy_max', type=float,
                    help='Maximum E(k) to use for the vertical plot axis.')
args = parser.parse_args()

def doit(ds):

    # a FFT operates on uniformly gridded data.  We'll use the yt
    # covering grid for this.

    max_level = ds.index.max_level

    ref = int(np.product(ds.ref_factors[0:max_level]))

    low = ds.domain_left_edge
    dims = ds.domain_dimensions*ref

    nx, ny, nz = dims

    nindex_rho = 1./3.

    Kk = np.zeros( (int(nx/2)+1, int(ny/2)+1, int(nz/2)+1))

    for vel in [("gas", "velocity_x"), ("gas", "velocity_y"), 
                ("gas", "velocity_z")]:

        Kk += 0.5*fft_comp(ds, ("gas", "density"), vel,
                           nindex_rho, max_level, low, dims)

    # wavenumbers
    L = (ds.domain_right_edge - ds.domain_left_edge).d

    kx = np.fft.rfftfreq(nx)*nx/L[0]
    ky = np.fft.rfftfreq(ny)*ny/L[1]
    kz = np.fft.rfftfreq(nz)*nz/L[2]
    
    # physical limits to the wavenumbers
    kmin = np.min(1.0/L)
    kmax = np.min(0.5*dims/L)
    
    kbins = np.arange(kmin, kmax, kmin)
    N = len(kbins)

    # bin the Fourier KE into radial kbins
    kx3d, ky3d, kz3d = np.meshgrid(kx, ky, kz, indexing="ij")
    k = np.sqrt(kx3d**2 + ky3d**2 + kz3d**2)

    whichbin = np.digitize(k.flat, kbins)
    ncount = np.bincount(whichbin)
    
    E_spectrum = np.zeros(len(ncount)-1)

    for n in range(1,len(ncount)):
        E_spectrum[n-1] = np.sum(Kk.flat[whichbin==n])

    k = 0.5*(kbins[0:N-1] + kbins[1:N])
    E_spectrum = E_spectrum[1:N]

    index = np.argmax(E_spectrum)
    kmax = k[index]
    Emax = E_spectrum[index]

    plt.loglog(k, E_spectrum)
    plt.loglog(k, Emax*(k/kmax)**(-5./3.), ls=":", color="0.5")


    ax = plt.gca()

    # Apply vertical axis limits
    ax.set_ylim(bottom=args.energy_min, top=args.energy_max)

    # List the time above the plot
    tart = ax.text(1.0, 1.01, '$time = {}$'.format(float(ds.current_time)),
                   transform=ax.transAxes,
                   verticalalignment='bottom',
                   horizontalalignment='right')
    
    plt.xlabel(r"$k$")
    plt.ylabel(r"$E(k)dk$")

    plt.savefig("{}.powerspectrum.png".format(args.pltfile),
                bbox_extra_artists=(tart,), dpi=300)


def fft_comp(ds, irho, iu, nindex_rho, level, low, delta ):

    cube = ds.covering_grid(level, left_edge=low,
                            dims=delta,
                            fields=[irho, iu])

    rho = cube[irho].d
    u = cube[iu].d

    nx, ny, nz = rho.shape

    # do the FFTs -- note that since our data is real, there will be
    # too much information here.  fftn puts the positive freq terms in
    # the first half of the axes -- that's what we keep.  Our
    # normalization has an '8' to account for this clipping to one
    # octant.
    ru = np.fft.fftn(rho**nindex_rho * u)[0:int(nx/2)+1,0:int(ny/2)+1,0:int(nz/2)+1]
    ru = 8.0*ru/(nx*ny*nz)

    return np.abs(ru)**2


if __name__ == "__main__":

    ds = yt.load(args.pltfile)
    doit(ds)
