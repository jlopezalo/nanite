import lmfit
import numpy as np

from . import weight


def get_parameter_defaults():
    # The order of the parameters must match the order
    # of ´parameter_names´ and ´parameter_keys´.
    params = lmfit.Parameters()
    params.add("E", value=3e3, min=0)
    params.add("R", value=10e-6, min=0, vary=False)
    params.add("nu", value=.5, min=0, max=0.5, vary=False)
    params.add("contact_point", value=0)
    params.add("baseline", value=0)
    return params


def hertz_paraboloidal(delta, E, R, nu, contact_point=0, baseline=0):
    r"""Hertz model for a paraboloidal indenter

    .. math::

        F = \frac{4}{3}
            \frac{E}{1-\nu^2}
            \sqrt{R}
            \delta^{3/2}

    Parameters
    ----------
    E: float
        Young's modulus [N/m²]
    delta: 1d ndarray
        Indentation [m]
    R: float
        Tip radius [m]
    nu: float
        Poisson's ratio
    contact_point: float
        Indentation offset [m]
    baseline: float
        Force offset [N]
    negindent: bool
        If `True`, will assume that the indentation value(s) given by
        `delta` are negative and must be mutlitplied by -1.

    Returns
    -------
    F: float
        Force [N]

    Notes
    -----
    The original model reads

    .. math::

        F = \frac{4}{3}
            \frac{E}{1-\nu^2}
            \sqrt{2k}
            \delta^{3/2},

    where :math:`k` is defined by the paraboloid equation

    .. math::

        \rho^2 = 4kz.

    These approximations are made by the Hertz model:

    - The sample is isotropic.
    - The sample is a linear elastic solid.
    - The sample is extended infinitely in one half space.
    - The indenter is not deformable.
    - There are no additional interactions between sample and indenter.

    Additional assumptions:

    - radius of spherical cell is larger than the indentation

    References
    ----------
    Sneddon (1965) :cite:`Sneddon1965`
    """
    aa = 4/3 * E/(1-nu**2)*np.sqrt(R)
    root = contact_point-delta
    pos = root > 0
    bb = np.zeros_like(delta)
    bb[pos] = (root[pos])**(3/2)
    return aa*bb + baseline


def model(params, x):
    if x[0] < x[-1]:
        revert = True
    else:
        revert = False
    if revert:
        x = x[::-1]
    mf = hertz_paraboloidal(E=params["E"].value,
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


model_doc = hertz_paraboloidal.__doc__
model_func = hertz_paraboloidal
model_key = "hertz_para"
model_name = "parabolic indenter (Hertz)"
parameter_keys = ["E", "R", "nu", "contact_point", "baseline"]
parameter_names = ["Young's Modulus", "Tip Radius",
                   "Poisson's Ratio", "Contact Point", "Force Baseline"]
parameter_units = ["Pa", "m", "", "m", "N"]
valid_axes_x = ["tip position"]
valid_axes_y = ["force"]
