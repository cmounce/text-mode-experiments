# ZZT All-Purpose TSR (legacy)
This is the original TSR code as distributed in 2008. It sets font, palette,
and high-intensity text mode, all in one executable.

It is a proof-of-concept. It has bugs. It is here for the sake of preserving
history, and you are probably better off using the 2021 rewrite. But if you
want to use this version, I won't stop you!

## Usage
Customizing the functionality (font, palette, etc) requires you to manually
edit `tsr2.asm` and/or the files it includes. See the "video settings" section
on line 25.

Compile with NASM like so:

```
nasm -f bin tsr2.asm -o TSR2.COM
```

Under DOS (or your favorite emulator, e.g., DOSBox), you can run
`TSR2.COM i` to initialize the text-mode settings and install the TSR,
and `TSR2.COM u` to uninstall the TSR.

## License
This code is provided under the MIT License.

`megazeux.chr` and the compiled artifact `TSR2.COM` both contain the MegaZeux
default font. The MegaZeux project *as a whole* is licensed GPL v2+, but the
font is public domain because Alexis Janson released her Zeux games (including
the font) into the public domain.

(Additionally, as of the time of this writing, bitmapped fonts are likely not
copyrightable in the USA. But I am not a lawyer.)
