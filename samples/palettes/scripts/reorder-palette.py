#!/usr/bin/env python3
from palette import Palette
import argparse

parser = argparse.ArgumentParser()
parser.add_argument(
    "palettes", type=str, nargs="+",
    help="palette file(s) to rearrange")
parser.add_argument(
    "-g", "--goal", type=str,
    help="target palette to try to approximate")
args = parser.parse_args()

with open(args.goal, "rb") as f:
    goal_palette = Palette.from_bytes(f.read())

for filename in args.palettes:
    with open(filename, "r+b") as f:
        palette = Palette.from_bytes(f.read())
        palette.reorder(goal_palette)
        f.seek(0)
        f.truncate()
        f.write(bytes(palette))
