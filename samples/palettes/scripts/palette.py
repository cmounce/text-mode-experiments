#!/usr/bin/env python3
import math
import numpy as np
import oklab
import re
import scipy.optimize


class Palette:
    def __init__(self, colors):
        colors = list(colors)
        if len(colors) != 16:
            raise ValueError("Palette must have 16 entries")
        self.colors = colors

    @classmethod
    def from_bytes(cls, data):
        result = cls._from_vga_bytes(data)
        if result:
            return result
        result = cls._from_ascii_hex(data)
        if result:
            return result
        raise ValueError("Not a supported palette format")

    @classmethod
    def _from_vga_bytes(cls, data):
        "Read 16 colors in VGA palette format (3 bytes/color, range 0-63)"
        if len(data) != 16*3 or any(x > 63 for x in data):
            return None
        floats = [min(1.0, x/63) for x in data]
        colors = [tuple(floats[i:i + 3]) for i in range(0, 16*3, 3)]
        return cls(colors)

    @classmethod
    def _from_ascii_hex(cls, data):
        """
        Read colors as 6-digit hex values from an ASCII text file.

        This function reads Gimp palette files and the HEX format on Lospec.
        It skips stuff that it doesn't understand, so it can probably read
        other formats that have one hex color per line.
        """
        lines = re.split(rb"[\r\n]+", data)
        colors = []
        for line in lines:
            match = re.match(rb"""
                [^a-z]*             # Line must not contain other text.
                                    # Numbers are okay because Gimp palettes
                                    # use them.
                (\b[0-9a-f]{6}\b)   # Hex code must be exactly 6 digits.
                [^a-z]*             # As before: no other text.
            """, line, re.VERBOSE | re.IGNORECASE)
            if match:
                hex_str = match[1]
                components = (hex_str[i:i + 2] for i in range(0, 6, 2))
                floats = (int(x, base=16)/255 for x in components)
                colors.append(tuple(floats))
        return cls(colors) if len(colors) == 16 else None

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
