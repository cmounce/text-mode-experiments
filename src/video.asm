;; Routines for setting font, palette, etc.
%include 'string.asm'

;===============================================================================
; Non-resident code
;-------------------------------------------------------------------------------
section .text

preview_mode:
    ; TODO: Implement preview by executing data in global_buffer
    ret

;-------------------------------------------------------------------------------
; Append resident font/palette code to the wstring in DI.
;
; This code looks for video data starting at resident_data, which means in most
; cases this code cannot be executed directly: the TSR must be installed first.
;
; The generated code clobbers SI when run (though this function doesn't).
;-------------------------------------------------------------------------------
concat_resident_video_code_wstring:
    push si

    ; Append header: initialize SI = resident data
    mov si, _initialize_si_code
    call concat_wstring

    ; Append palette-setting code
    cmp [parsed_bundle.palette], word 0
    je .skip_palette
    mov si, _palette_code
    call concat_wstring
    .skip_palette:

    ; Append font-setting code
    cmp [parsed_bundle.font], word 0
    je .skip_font
    mov si, _font_code
    call concat_wstring
    .skip_font:

    pop si
    ret

;-------------------------------------------------------------------------------
; Append resident font/palette data to the wstring in DI.
;-------------------------------------------------------------------------------
concat_video_data_wstring:
    push si

    ; Copy palette data
    mov si, [parsed_bundle.palette]
    cmp si, 0
    je .skip_palette
    call concat_wstring
    .skip_palette:

    ; Copy font data
    mov si, [parsed_bundle.font]
    cmp si, 0
    je .skip_font
    mov ax, [si]                ; AX = number of bytes in font
    mov al, ah
    call concat_byte_wstring    ; Concat AL = pixel height of font
    call concat_wstring         ; Concat SI = actual font data
    .skip_font:

    pop si
    ret


;-------------------------------------------------------------------------------
; Reset video mode
;-------------------------------------------------------------------------------
reset_video:
    ; TODO: Get the original video mode and store it somewhere, so we can
    ; return to the exact same settings (resolution, 8-vs-9 dot, etc)?
    ; Probably just a call to int 10, AH=1B
    mov ax, 0003h
    int 10h
    ret


;===============================================================================
; Resident code
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Sets SI to point to the resident_data label.
;-------------------------------------------------------------------------------
_initialize_si_code:
begin_wstring
    mov si, resident_data
end_wstring

;-------------------------------------------------------------------------------
; Set text-mode palette to the given 16 color palette.
;
; Takes a pointer DS:SI to palette data.
; Advances SI to point just past the end of the palette data.
;-------------------------------------------------------------------------------
_palette_code:
begin_wstring
    push bx
    push es

    ; Set palette colors 0-15
    mov ax, 1012h           ; Set block of DAC registers
    mov dx, ds              ; ES:DX = palette data located at DS:SI
    mov es, dx
    mov dx, si
    xor bx, bx              ; Starting color = 0
    mov cx, 16              ; Number of colors = 16
    int 10h

    ; Set palette registers 0-15 to point to colors 0-15.
    ; From the previous interrupt, BH/BL should still be 0,
    ; and CX should still be 16.
    .loop:
        mov ax, 1000h   ; Set palette register
        int 10h
        inc bh          ; Advance to next palette color
        inc bl          ; and next palette register
        loop .loop

    pop es
    pop bx
    add si, 3*16    ; Advance past all palette data
end_wstring

;-------------------------------------------------------------------------------
; Set font to the given font data
;
; Takes a pointer DS:SI to font data.
; Expects the first byte of data to represent the font height, to be followed
; by height*256 bytes worth of bitmap data.
; Advances SI to point just past the end of the video data.
;-------------------------------------------------------------------------------
_font_code:
begin_wstring
    push bp
    push bx
    push es

    ; Set font
    mov ax, 1110h   ; Load font data
    mov bl, 0       ; BL = table to load into
    mov bh, [si]    ; Read BH = height of font, advancing data pointer
    inc si
    mov cx, 256     ; CX = number of characters to write
    xor dx, dx      ; DX = first character to write
    mov bp, ds      ; Set ES:BP to our font data (DS:SI)
    mov es, bp
    mov bp, si
    int 10h

    ; Advance data pointer
    mov ax, si
    add ah, bh  ; AX += 256*height
    mov si, ax

    pop es
    pop bx
    pop bp
end_wstring
