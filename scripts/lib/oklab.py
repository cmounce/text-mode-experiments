import numpy as np
import numpy.linalg

# Consts for OKLAB conversions.
# Based on https://bottosson.github.io/posts/oklab/ -- in particular,
# the matrix m1 uses the trick of combining the XYZ and OKLAB matrixes.
m1 = np.array([
    [0.4122214708, 0.5363325363, 0.0514459929],
    [0.2119034982, 0.6806995451, 0.1073969566],
    [0.0883024619, 0.2817188376, 0.6299787005]])
m2 = np.array([
    [0.2104542553, 0.7936177850, -0.0040720468],
    [1.9779984951, -2.4285922050, 0.4505937099],
    [0.0259040371, 0.7827717662, -0.8086757660]])
m1_inv = np.linalg.inv(m1)
m2_inv = np.linalg.inv(m2)


def to_oklab(rgb):
    """
    Converts an (r, g, b) tuple to (l, a, b).

    RGB channels are floats in the range 0.0 to 1.0, inclusive.
    """
    linear_rgb = [_to_linear(c) for c in rgb]
    rgb = np.transpose([linear_rgb])
    lab = m2 @ (m1 @ rgb)**(1/3)
    return tuple(c for c in np.transpose(lab)[0])


def to_srgb(lab):
    """
    Converts an (l, a, b) tuple to (r, g, b).

    RGB channels are floats in the range 0.0 to 1.0, inclusive.
    """
    lab = np.transpose([lab])
    rgb = m1_inv @ (m2_inv @ lab)**3
    return tuple(_to_gamma(c) for c in np.transpose(rgb)[0])


# See https://entropymine.com/imageworsener/srgbformula/ for sRGB formulas
def _to_linear(x):
    """Converts a sRGB gamma-encoded value to linear"""
    if x <= 0.04045:
        return x/12.92
    else:
        return ((x + 0.055)/1.055)**2.4


def _to_gamma(x):
    """Converts a linear value to sRGB gamma-encoded"""
    if x <= 0.0031308:
        return x*12.92
    else:
        return 1.055 * x**(1/2.4) - 0.055


__all__ = ["to_oklab", "to_srgb"]
