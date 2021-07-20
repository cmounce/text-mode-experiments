#!/usr/bin/env python
import argparse
import sys
from typing import List, Optional

import bdfparser
import numpy as np

DRAWING_CHARS = "8,10,176-223"


def main():
    args = parse_args()
    font = bdfparser.Font(args.bdf_file)

    # Choose glyphs from font and convert them to bitmaps
    bitmaps = [get_bitmap_for_character(font, i) for i in range(256)]

    # Make sure we're settled on the desired glyph height
    height = args.height
    if not height:
        height = max(len(b) for b in bitmaps if b is not None)

    # Make sure we have bitmaps for all the characters
    fallback_bitmap = np.zeros((height, 8), dtype=np.uint8)
    for i in range(len(bitmaps)):
        if bitmaps[i] is None:
            print(f"Warning: no glyph for char {i}", file=sys.stderr)
            bitmaps[i] = fallback_bitmap

    # Make the bitmaps all the same size
    for i in range(len(bitmaps)):
        bitmaps[i] = resize(bitmaps[i], 8, height, i in args.extend_chars)

    # Write them to disk
    with open(args.output_file, "wb") as f:
        f.write(b"".join(to_bytes(b) for b in bitmaps))


def parse_args():
    parser = argparse.ArgumentParser(
        description="A tool for converting BDF fonts into DOS font format"
    )
    parser.add_argument(
        "bdf_file", type=str, metavar="BDF-FILE",
        help="BDF font file to convert"
    )
    parser.add_argument(
        "output_file", type=str, metavar="OUTPUT-FILE",
        help="Filename of resulting DOS font file"
    )
    parser.add_argument(
        "--height", type=int, metavar="ROWS",
        help="Target height. Glyphs that are too short will be padded to fit."
    )
    parser.add_argument(
        "--extend-chars", "-x",
        type=parse_byte_ranges, metavar="CHARS",
        default=DRAWING_CHARS,
        help=f"""
            For the given character codes, enlarge the glyphs so that they
            touch the edges of the bounding box. Only has an effect if the
            bounding box is larger than the glyph size. If flag is not present,
            defaults to "{DRAWING_CHARS}" (mostly CP437's box/line chars).
            """
    )
    return parser.parse_args()


def parse_byte_ranges(s):
    """Parses strings like "1,3-5" into set(1,3,4,5)."""
    result = set()
    for term in s.split(","):
        parts = [int(p) for p in term.split("-")]
        if len(parts) == 1:
            hi = parts[0]
            lo = parts[0]
        elif len(parts) == 2:
            lo, hi = min(parts), max(parts)
        else:
            raise ValueError(
                f"""Couldn't parse "{term}" as byte or as a range of bytes"""
            )
        if lo < 0:
            raise ValueError(f"Value out of range: {lo}")
        elif hi > 255:
            raise ValueError(f"Value out of range: {hi}")
        result.update(range(lo, hi + 1))
    return result


def get_bitmap_for_character(
    font: bdfparser.Font,
    char: int
) -> Optional[np.array]:
    """Returns a bitmap from the font that can represent the given CP437 code.

    If no suitable glyph can be found, returns None.
    """
    codepoints = get_codepoints_for_cp437(char)
    available = font.glyphs.keys()
    for codepoint in codepoints:
        if codepoint in available:
            glyph = font.glyphbycp(codepoint)
            bitmap = to_bitmap(glyph)
            return bitmap
    return None


def get_codepoints_for_cp437(x) -> List[int]:
    """Returns possible Unicode codepoints for the given CP437 character.

    This function returns a list because that allows for potential fallback
    codepoints if the font does not have complete coverage. Currently, though,
    this implementation only returns 1 codepoint for each character.
    """
    # Handle printable ASCII chars
    if x >= 32 and x <= 126:
        return [x]

    # Handle control chars, extended ASCII
    LOWER = " ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼"
    UPPER = "⌂" \
        "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒ" \
        "áíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐" \
        "└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀" \
        "αßΓπΣσµτΦϴΩδ∞∅∈∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ "
    if x < 32:
        code = ord(LOWER[x])
    else:
        code = ord(UPPER[x - 127])
    return [code]


def to_bitmap(glyph: bdfparser.Glyph) -> np.array:
    """Converts a Glyph into a 2D array of zeros and ones."""
    lines = glyph.draw().todata()   # Array of strings like "10101"
    return np.array(
        [[int(bit) for bit in line] for line in lines],
        dtype=np.uint8
    )


def resize(bitmap: np.array, new_width, new_height, extend=False):
    height, width = bitmap.shape

    def split(diff):
        x = diff//2
        y = diff - x
        return (x, y)

    add_top, add_bottom = split(new_height - height)
    add_left, add_right = split(new_width - width)

    for add_lines in [add_left, add_top, add_right, add_bottom]:
        bitmap = np.rot90(bitmap)
        if add_lines < 0:
            # Delete lines from base of array
            bitmap = bitmap[:add_lines]
        elif add_lines > 0:
            # Add lines to base of array
            _, current_width = bitmap.shape
            new_lines_shape = (add_lines, current_width)
            if extend:
                pattern_length = max(get_pattern_length(bitmap), 1)
                pattern = bitmap[-pattern_length:]
                new_lines = np.resize(pattern, new_lines_shape)
            else:
                new_lines = np.zeros(new_lines_shape, dtype=np.uint8)
            bitmap = np.concatenate([bitmap, new_lines])

    return bitmap


def get_pattern_length(bitmap: np.array, max_length=4):
    """Measure the length of any repeating pattern at the bottom of the array.

    For example, if the bottom rows were of the form ...ABCDECDE, this
    function would return 3, because the three rows CDE repeat.

    This function returns the length of the longest pattern it finds, not to
    surpass max_length. Returns 0 if no repeating pattern is found.
    """
    height, _ = bitmap.shape
    max_length = min(max_length, height//2)

    for length in range(max_length, 1, -1):
        a = bitmap[-length:]
        b = bitmap[-2*length:-length]
        if np.array_equal(a, b):
            return length
    return 0


def to_bytes(bitmap: np.array):
    height, width = bitmap.shape
    assert(1 <= height <= 32)
    assert(width == 8)

    def to_byte(row):
        result = 0
        for bit in row:
            result = (result << 1) + bit
        return result

    return bytes(to_byte(row) for row in bitmap)


if __name__ == "__main__":
    main()
