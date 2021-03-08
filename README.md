# text-mode-initializer
A prototype all-purpose text-mode initializer for DOS: it can change the
font, palette, and toggle high-intensity colors, all in one command.

I originally wrote this in 2008 as a proof-of-concept for tweaking
the display mode for the DOS game ZZT. I never polished it into an
official release, but it became known as the "ZZT All-Purpose TSR"
in the ZZT community, and despite its bugs and warts, it's currently
the only thing that does what it does.

Now, in 2021, ZZT is experiencing a renaissance, and people are asking
me permission to use/adapt this code. So I'm placing this project under
the MIT License: go forth and adapt! The only thing not covered by the
new license is megazeux.chr, and the only reason that's in there is
because I needed an alternate character set for testing purposes. This
is still just a prototype, after all.

## Usage
Compile with NASM like so:

```
nasm -f bin tsr.asm -o TSR.COM
```

Under DOS (or your favorite emulator, e.g., DOSBox), you can run
`TSR.COM i` to initialize the text-mode settings and install the TSR,
and `TSR.COM u` to uninstall the TSR.
