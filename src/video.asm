segment .data
test_palette:
db 0,   0,  32
db 0,   21, 32
db 0,   42, 32
db 0,   63, 32
db 21,  0,  32
db 21,  21, 32
db 21,  42, 32
db 21,  63, 32
db 42,  0,  32
db 42,  21, 32
db 42,  42, 32
db 42,  63, 32
db 63,  0,  32
db 63,  21, 32
db 63,  42, 32
db 63,  63, 32

segment .text
;-------------------------------------------------------------------------------
; Initialize text-mode palette.
;
; TODO: This is using a hard-coded test palette right now. It will eventually
; need to find and load palette data from its block of resident memory.
;-------------------------------------------------------------------------------
set_palette:
push bx
push es

; Make sure registers 0-15 point to colors 0-15
mov cx, 16
.register_loop:
mov ax, 1000h   ; Set palette register
mov bl, cl      ; Registers 0 through 15...
dec bl
mov bh, bl      ; ...get colors 0 through 15
int 10h

; Set colors 0-15
mov ax, 1012h           ; Set block of DAC registers
mov bx, 0               ; from register 0
mov cx, 16              ; through register 15.
mov dx, ds
mov es, dx              ; TODO: Figure out how to load this address
mov dx, test_palette    ; in a TSR-safe, relocatable-safe manner
; One possibility: dedicate 2 bytes per table at the start of the TSR.
; These are 00 00 if the table doesn't exist, or the table's offset if it does.
; Either this function would read the offsets directly, or wrapper code in the
; TSR would pass it in (BX) to enable calling from non-resident code.
int 10h

pop es
pop bx
ret
