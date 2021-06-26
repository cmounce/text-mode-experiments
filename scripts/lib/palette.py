#!/usr/bin/env python3
import math
import numpy as np
from . import oklab
import re
import scipy.optimize

COLOR_PATTERNS = [re.compile(s) for s in [
    # Whitespace-separated decimal numbers at the start of a line
    # Matches: GIMP palettes, JASC palettes, PPM images
    r"^\s*(\d{1,3})\s+(\d{1,3})\s+(\d{1,3})\b",

    # Paint.NET
    r"^FF([0-9A-Fa-f]{6})\b",

    # .hex file
    r"^([0-9A-Fa-f]{6})\b",

    # CSS color code (with optional alpha channel)
    r"#([0-9A-Fa-f]{6})(?:[0-9A-Fa-f]{2})?\b"
]]


class Palette:
    def __init__(self, colors):
        colors = list(colors)
        if len(colors) != 16:
            raise ValueError("Palette must have 16 entries")
        self.colors = colors

    @classmethod
    def from_bytes(cls, data):
        "Read 16 colors in VGA palette format (3 bytes/color, range 0-63)"
        if len(data) != 16*3 or any(x > 63 for x in data):
            raise ValueError("Invalid binary palette format")
        floats = [min(1.0, x/63) for x in data]
        colors = [tuple(floats[i:i + 3]) for i in range(0, 16*3, 3)]
        return cls(colors)

    @classmethod
    def from_text(cls, text: str):
        """Import a palette from any number of text-based formats.

        This function expects a line-based format with one color per line,
        skipping lines that don't contain a color (headers, comments, etc).

        Many palette formats have one color per line, plus a few other lines
        for headers, comments, etc. This function takes advantage of this
        common design by throwing a bunch of regexes at each line, ignoring
        any lines that don't match; it's not a *proper* parser of any one
        format, but it works on the following formats provided by Lospec:

        - GIMP palette files
        - JASC/Paintshop Pro
        - Paint.NET
        - .hex files

        It can also import other things that match these regexes, such as
        PPM images, or text files with copy/pasted CSS hex codes.

        Raises ValueError if it doesn't find exactly 16 colors in the palette.
        """
        global COLOR_PATTERNS
        colors = []
        for line in text.splitlines():
            # Match the line against each of our regexes
            match = None
            for pattern in COLOR_PATTERNS:
                match = pattern.search(line)
                if match:
                    break

            # If we got a match, this line represents a color
            if match:
                if len(match.groups()) == 1:
                    # Read hex string
                    hex_str = match[1]
                    components = (hex_str[i:i + 2] for i in range(0, 6, 2))
                    floats = (int(x, base=16)/255 for x in components)
                    colors.append(tuple(floats))
                elif len(match.groups()) == 3:
                    # Read decimal triplet
                    ints = [int(x) for x in match.groups()]
                    if all(x < 256 for x in ints):
                        floats = (x/255 for x in ints)
                        colors.append(tuple(floats))

        if len(colors) != 16:
            raise ValueError("Couldn't interpret data as 16-color palette")
        return cls(colors)

    def reorder(self, target):
        """
        Reorder the palette's colors to more closely match the target's colors
        """
        lab_self = [oklab.to_oklab(c) for c in self.colors]
        lab_target = [oklab.to_oklab(c) for c in target.colors]

        def dist(x, y):
            """
            Return distance between two LAB colors.

            This uses the hybrid distance formula as described here:
            https://en.wikipedia.org/wiki/Color_difference#Other_geometric_constructions
            """ # noqa
            lightness = abs(x[0] - y[0])
            chroma = math.sqrt((x[1] - y[1])**2 + (x[2] - y[2])**2)
            return lightness + chroma

        # Calculate costs matrix.
        # Each column represents a color in our own palette.
        # Each row represents a color in the target palette.
        costs = np.array([
            [dist(target_color, our_color) for our_color in lab_self]
            for target_color in lab_target
        ])

        # Reorder self
        _, col_indexes = scipy.optimize.linear_sum_assignment(costs)
        self.colors = [self.colors[i] for i in col_indexes]

    def __bytes__(self):
        floats = (chan for color in self.colors for chan in color)
        ints = (round(x*63) for x in floats)
        return bytes(max(0, min(x, 63)) for x in ints)
