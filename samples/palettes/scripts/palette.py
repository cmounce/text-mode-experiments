#!/usr/bin/env python3
import math
import numpy as np
import oklab
import scipy.optimize


class Palette:
    def __init__(self, colors):
        colors = list(colors)
        if len(colors) != 16:
            raise ValueError("Palette must have 16 entries")
        self.colors = colors

    @classmethod
    def from_bytes(cls, data):
        if len(data) != 16*3:
            raise ValueError("Palette data must be exactly 16*3 bytes")
        floats = [min(1.0, x/63) for x in data]
        colors = [tuple(floats[i:i + 3]) for i in range(0, 16*3, 3)]
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
