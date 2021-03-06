#!/usr/bin/env python3
# Generate some color palettes with code.
import itertools
import pathlib

from lib.palette import Palette
from lib.oklab import to_oklab, to_srgb

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

    # Generate some non-reordered palettes
    ramp8 = generate_ramp8()
    with open(PALETTES_DIR / 'ramp8.pal', 'wb') as f:
        f.write(bytes(ramp8))


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


def generate_ramp8():
    """Generates a 8-color ramp"""
    # Make an 8-color palette in CGA order
    off_on = [0.0, 1.0]
    rgb_colors = sorted(itertools.product(off_on, off_on, off_on))

    # Sort the colors by brightness, but remember their original indexes
    lab_colors = sorted((to_oklab(rgb), i) for i, rgb in enumerate(rgb_colors))

    # Even out the brightness
    for i, (color, old_i) in enumerate(lab_colors):
        brightness = i/7
        lab_colors[i] = ((brightness, color[1], color[2]), old_i)

    # Change the colors back to RGB and put them in their original order
    for lab_color, old_i in lab_colors:
        rgb_colors[old_i] = to_srgb(lab_color)

    # Double the result to 16 colors
    return Palette(rgb_colors + rgb_colors)


if __name__ == "__main__":
    main()
