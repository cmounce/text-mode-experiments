#!/usr/bin/env python3
import argparse
from PIL import Image, UnidentifiedImageError


def main():
    # Read args
    parser = argparse.ArgumentParser(
        description="Convert bitmap images to EGA fonts, and vice-versa"
    )
    parser.add_argument('input', type=str, help='an existing font/image file')
    parser.add_argument('output', type=str, help='name for the converted file')
    parser.add_argument(
        '--dim', '-d', action='store_true',
        help='generate a dimmed image, useful for creating a template')
    args = parser.parse_args()

    # Do the conversion
    input_file = open_file(args.input)
    if isinstance(input_file, Image.Image):
        image_to_font(input_file, args.output)
    else:
        font_to_image(input_file, args.output, args.dim)


class Font:
    def __init__(self, data):
        if len(data) % 256 != 0:
            raise ValueError('Font data not a multiple of 256')
        height = len(data) // 256
        if height < 1 or height > 32:
            raise ValueError(f'Font height {height} out of range')
        self.data = bytes(data)
        self.height = height
        self.width = 8

    def char(self, i):
        return self.data[i*self.height:(i + 1)*self.height]


def open_file(filename):
    """Open a file as either a PIL.Image.Image or as a Font object"""
    try:
        return Image.open(filename)
    except UnidentifiedImageError:
        with open(filename, 'rb') as f:
            return Font(f.read())


def image_to_font(im: Image.Image, output_name: str):
    """Writes a font file derived from the given Image object"""
    # Figure out the font size and character grid
    num_pixels = im.width * im.height
    if num_pixels % (256 * 8) != 0 or im.width % 8 != 0:
        raise ValueError('Image does not contain an EGA text font')
    font_width = 8
    font_height = num_pixels // font_width // 256
    if font_height < 1 or font_height > 32:
        raise ValueError(f'Font height {font_height} out of range')
    cols = im.width // 8

    # Convert image to black-and-white, 1-bit color
    bw = im.convert(mode='1')

    # Read characters out of the image data
    font_data = bytearray(256 * font_height)
    for char_code in range(256):
        row = char_code // cols
        col = char_code % cols
        x = col * font_width
        y = row * font_height
        char = bw.crop((x, y, x + font_width, y + font_height))
        bits = [pixel//255 for pixel in char.getdata()]
        for i in range(font_height):
            byte = 0
            for bit in bits[i*8:(i + 1)*8]:
                byte = (byte << 1) | bit
            font_data[char_code*font_height + i] = byte

    # Write font to disk
    with open(output_name, 'wb') as f:
        f.write(font_data)


def font_to_image(font: Font, output_name: str, dim=False):
    """Writes an image file derived from the given Font object"""
    # Set up a grid of characters
    ROWS = 8
    COLS = 256 // ROWS

    # Set up raw pixel data (1 byte per pixel, indexed)
    width = COLS * font.width
    height = ROWS * font.height
    pixels = bytearray(width * height)

    # Write font characters, one character per grid cell
    for i in range(256):
        # Find position in grid
        row = i // COLS
        col = i % COLS

        # Find pixel offset of the grid cell's top-left corner
        x = col * font.width
        y = row * font.height
        top_left_offset = y * width + x

        # Write character
        checkerboard = (row & 1) ^ (col & 1)
        fg = checkerboard + 2
        bg = checkerboard
        offset = top_left_offset
        for scanline in font.char(i):
            bits = [(scanline >> i) & 1 for i in range(7, -1, -1)]
            colors = [[bg, fg][bit] for bit in bits]
            pixels[offset: offset + 8] = colors
            offset += width

    # Create image with palette
    result = Image.frombytes('P', (width, height), bytes(pixels))
    BG1 = [0x00, 0x00, 0x00]
    BG2 = [0x22, 0x22, 0x22]
    FG1 = [0xDD, 0xDD, 0xDD]
    FG2 = [0xFF, 0xFF, 0xFF]
    if dim:
        FG1 = [x//3 for x in FG1]
        FG2 = [x//3 for x in FG2]
    palette = BG1 + BG2 + FG1 + FG2
    result.putpalette(palette)

    # Save image
    result.save(output_name)


main()
