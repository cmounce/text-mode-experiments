#!/usr/bin/env python3
# Generate a color palette by using Martin Roberts's quasirandom sequence R3
# to evenly sample colors within the RGB color cube. Details on R3 here:
# http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/

import itertools
from palette import Palette


def quasirandom_r3():
    """Generate an infinite stream of coordinates sampled from a unit cube."""
    phi_3 = 1.2207440846057596  # Solution to x**4 == x + 1
    alphas = (1/phi_3, 1/phi_3**2, 1/phi_3**3)
    point = (0.5, 0.5, 0.5)
    while True:
        yield point
        point = tuple((val + alpha) % 1 for val, alpha in zip(point, alphas))


colors = itertools.islice(quasirandom_r3(), 16)
scatter = Palette(colors)
with open("../ega.pal", "rb") as f:
    ega = Palette.from_bytes(f.read())
scatter.reorder(ega)
with open("../scatter.pal", "wb") as f:
    f.write(bytes(scatter))
