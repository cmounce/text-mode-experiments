segment .data
test_palette:
; ; 3*3*2 RGB combinations, with black and white omitted
; db   0,  0, 63
; db   0, 32,  0
; db   0, 32, 63
; db   0, 63,  0
; db   0, 63, 63
; db  32,  0,  0
; db  32,  0, 63
; db  32, 32,  0
; db  32, 32, 63
; db  32, 63,  0
; db  32, 63, 63
; db  63,  0,  0
; db  63,  0, 63
; db  63, 32,  0
; db  63, 32, 63
; db  63, 63,  0
incbin "../samples/palettes/sweetie.pal"
.end_of_contents:

segment .text
;-------------------------------------------------------------------------------
; Set text-mode palette to the given 16 color palette.
;
; Takes a pointer DS:DX to palette data.
;-------------------------------------------------------------------------------
set_palette:
push bx
push es

; Set palette colors 0-15
mov ax, 1012h           ; Set block of DAC registers
mov bx, ds              ; from palette data at DS:DX
mov es, bx
mov bx, 0               ; Set DAC registers 0 through 15
mov cx, 16              ; (start = 0, count = 16)
int 10h

; Make sure registers 0-15 point to colors 0-15
mov cx, 16
.register_loop:
mov ax, 1000h   ; Set palette register
mov bl, cl
dec bl          ; BL = register number (0-15)
mov bh, bl      ; BH = corresponding color index (0-15)
int 10h
loop .register_loop

pop es
pop bx
.end_of_contents:   ; Marks code copyable by TSR installation routine
ret
