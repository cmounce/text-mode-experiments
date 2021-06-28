#!/usr/bin/env python3
# Generate some color palettes with code.
import itertools
import pathlib

from lib.palette import Palette

PALETTES_DIR = pathlib.Path(__file__).parent.parent / "goodies" / "palettes"


def main():
    # Generate some procedural palettes
    palettes = {
        "scatter.pal": generate_quasirandom_r3(),
        "rgb332.pal": generate_rgb332()
    }

    # Get CGA palette so we can reorder our procedural palettes
    with open(PALETTES_DIR / "cga.pal", "rb") as f:
        cga = Palette.from_bytes(f.read())

    # Write palettes to disk
    for filename, palette in palettes.items():
        palette.reorder(cga)
        with open(PALETTES_DIR / filename, "wb") as f:
            f.write(bytes(palette))


def generate_quasirandom_r3():
    """Returns a color palette from Martin Roberts's quasirandom sequence R3.

    Martin's R3 sequence is a roughly-even sampling of the unit cube, here
    mapped to the RGB color cube. See his website for details on R3:
    http://extremelearning.com.au/unreasonable-effectiveness-of-quasirandom-sequences/
    """
    colors = []

    phi_3 = 1.2207440846057596  # Solution to x**4 == x + 1
    alphas = (1/phi_3, 1/phi_3**2, 1/phi_3**3)
    point = (0.5, 0.5, 0.5)
    for i in range(16):
        colors.append(point)
        point = tuple((val + alpha) % 1 for val, alpha in zip(point, alphas))
    return Palette(colors)


def generate_rgb332():
    """Generates a 3-3-2 level RGB palette.

    3*3*2 is 18 colors, so we leave out white and black to make an even 16.
    """
    it = itertools.product([0.0, 0.5, 1.0], [0.0, 0.5, 1.0], [0.0, 1.0])
    it = filter(lambda x: x != (0.0, 0.0, 0.0) and x != (1.0, 1.0, 1.0), it)
    colors = list(it)
    return Palette(colors)


if __name__ == "__main__":
    main()
