# text-mode-initializer
A DOS TSR that changes the font, palette, and toggles high-intensity colors,
all in one command.

This is a rewrite of the original 2008 project, which is located under
`legacy/` for historical purposes.

## Usage
Change to the `src/` folder and compile with NASM like so:

```
nasm -f bin main.asm -o TSR.COM
```

Under DOS (or your favorite emulator, e.g., DOSBox), you can run
`TSR.COM i` to initialize the text-mode settings and install the TSR,
and `TSR.COM u` to uninstall the TSR.

## License
Everything is under the MIT License, unless otherwise noted.
