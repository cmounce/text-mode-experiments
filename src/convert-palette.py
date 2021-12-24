#!/usr/bin/env python3
import sys

from lib.palette import Palette

infile = sys.argv[1]
outfile = sys.argv[2]

with open(infile, "r") as f:
    palette = Palette.from_text(f.read())
with open(outfile, "wb") as f:
    f.write(bytes(palette))
