import lmfit
import numpy as np
from . import weight
cimport numpy as np


def get_parameter_defaults():
    # The order of the parameters must match the order 
    # of ´parameter_names´ and ´parameter_keys´.
    params = lmfit.Parameters()
    params.add("E", value=3e3, min=0)
    params.add("R", value=10e-6, vary=False)
    params.add("nu", value=.5, vary=False)
    params.add("contact_point", value=0)
    params.add("baseline", value=0, vary=False)
    return params


def hertz_spherical(double E, delta, double R, double nu, double contact_point=0, double baseline=0):
    """Hertz model for Spherical indenter - modified by Sneddon

    F = E/(1-nu**2)*((R^2+a^2)/2*ln((R+a)/(R-a))-a*R)
    delta - contact_point = a/2*ln((R+a)/(R-a))
    
    Parameters
    ----------
    E: float
        Young's modulus [N/m²]
    delta: 1d ndarray
        Point of maximal indentation at given force [m]
    R: float
        Radius of tip curvature [m]
    nu: float
        Poisson's ratio; incompressible materials have nu=0.5 (rubber)
    contact_point: float
        Indentation offset
    baseline: float
        Force offset
    negindent: bool
        If `True`, will assume that the indentation value(s) given by
        `delta` are negative and must be multiplied by -1.

    Returns
    -------
    F: float
        Force [N]

    Notes
    -----
    These approximations are made by the Hertz model:
    - sample is isotropic
    - sample is linear elastic solid
    - sample extended infinitely in half space
    - indenter is not deformable
    - no additional interactions between sample and indenter   
    """
    cdef double a
    cdef int ii
    FF = np.zeros_like(delta)
    root = delta-contact_point
    root[root >0]=0
    root=-1*root
    for ii in range(root.shape[0]):
        if root[ii]==0:
            FF[ii]=0
        else:
            a=_get_a(R, root[ii])
            FF[ii]=E/(1-nu**2)*((R**2+a**2)/2*np.log((R+a)/(R-a))-a*R) 
    return FF + baseline


cdef double _get_a(double R, double delta, double accuracy=1e-12):
    cdef double a_left, a_center, a_right, d_delta, delta_predict
    a_left=0
    a_center=0.5*R
    a_right=R
    d_delta=1e200 #np.inf
    while d_delta>accuracy:
        delta_predict=_delta_of_a(a_center, R)
        if delta_predict>delta:
            a_left,a_right=a_left,a_center
            a_center=a_left+(a_right-a_left)/2
        elif delta_predict<delta:
            a_left,a_right=a_center,a_right
            a_center=a_left+(a_right-a_left)/2
        else:
            break
        d_delta=abs((delta_predict-delta)/delta)
    return a_center


def get_a(R, delta, accuracy=1e-12):
    """Makes method _get_a available for pytest"""
    return _get_a(R, delta, accuracy)


cdef double _delta_of_a(double a, double R):
    cdef double delta
    delta=a/2*np.log((R+a)/(R-a))
    return delta


def delta_of_a(a, R):
    """Makes method _delta_of_a available for pytest"""
    return _delta_of_a(a, R)


def model(params, x):
    if x[0]<x[-1]:
        revert = True
    else:
        revert = False
    if revert:
        x = x[::-1]
    mf = hertz_spherical(E=params["E"].value,
                         delta=x,
                         R=params["R"].value,
                         nu=params["nu"].value,
                         contact_point=params["contact_point"].value,
                         baseline=params["baseline"].value)
    if revert:
        return mf[::-1]
    return mf


def residual(params, delta, force, weight_cp=5e-7):
    """ Compute residuals for fitting
    
    Parameters
    ----------
    params: lmfit.Parameters
        The fitting parameters for `model`
    delta: 1D ndarray of lenght M
        The indentation distances
    force: 1D ndarray of length M
        The corresponding force data
    weight_cp: positive float or zero/False
        The distance from the contact point until which
        linear weights will be applied. Set to zero to
        disable weighting.
    """
    md = model(params, delta)
    resid = force-md

    if weight_cp:
        # weight the curve so that the data around the contact_point do
        # not affect the fit so much.
        weights = weight.weight_cp(cp=params["contact_point"].value,
                                   delta=delta,
                                   weight_dist=weight_cp)
        resid *= weights
    return resid


model_name = "spherical indenter (Sneddon)"
model_key = "sneddon_spher"
parameter_keys = ["E", "R", "nu", "contact_point", "baseline"]
parameter_names = ["Young's Modulus", "Tip Radius", "Poisson Ratio", "Contact Point", "Force Baseline"]
valid_axes_x = ["tip position"]
valid_axes_y = ["force"]
doc = hertz_spherical.__doc__
