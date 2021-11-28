;; Code related to the bundle of config data appended to the .COM file
%ifndef BUNDLE_ASM
%define BUNDLE_ASM

%include "macros.asm"
%include "string.asm"

;-------------------------------------------------------------------------------
; Consts
;-------------------------------------------------------------------------------
section .data

%define DATA_HEADER " START OF DATA:"
%define PALETTE_KEY "PALETTE"
%define FONT_KEY "FONT"
%define BLINK_KEY "BLINK"

; Define a list of all the valid keys
bundle_keys:
    .palette:   db_wstring PALETTE_KEY
    .font:      db_wstring FONT_KEY
    .blink:     db_wstring BLINK_KEY
    db 0


;-------------------------------------------------------------------------------
; Appended data
;-------------------------------------------------------------------------------
section .append

; Set up data header and save its address
db DATA_HEADER
start_of_bundle:

; Minor hack: initialize the .COM file with some palette data.
; In the future, we won't do this.
db_wstring PALETTE_KEY
begin_wstring
    incbin "../goodies/palettes/rgb332.pal"
end_wstring
db_wstring FONT_KEY
begin_wstring
    incbin "../goodies/fonts/fixed.f14"
end_wstring
db_wstring BLINK_KEY
begin_wstring
    db 0
end_wstring

; Terminate the data bundle
dw 0


;-------------------------------------------------------------------------------
; Parsed data
;-------------------------------------------------------------------------------
section .bss

; Output of parse_bundled_data: the values for each key in the bundle.
; These are each pointers to wstrings, or null if not present.
parsed_bundle:
    .palette:       resw 1
    .font:          resw 1
    .blink:         resw 1


;-------------------------------------------------------------------------------
; Code
;-------------------------------------------------------------------------------
section .text

; Reads bundled data from end of .COM file into BSS structs.
;
; Sets CF on failure.
parse_bundled_data:
    push bx
    push si
    push di

    ; Before we parse the bundle, make sure the overall structure is valid.
    call validate_bundle_structure
    jc .failure

    ; Loop over each key-value pair in the bundle
    mov si, start_of_bundle
    while_condition
        cmp word [si], 0    ; Empty string signals end of list
    begin_while ne
        mov bx, si          ; SI = key
        next_wstring bx     ; BX = value

        mov di, bundle_keys.palette
        call cmp_wstring
        begin_if e
            ; TODO: Validate that all values are in range 0-63
            cmp word [bx], 3*16     ; Make sure we have exactly 16 colors
            jne .failure
            mov [parsed_bundle.palette], bx
        else
        mov di, bundle_keys.font
        call cmp_wstring
        if e
            mov cx, [bx]
            cmp cl, 0       ; Make sure font is a multiple of 256 bytes
            jne .failure
            cmp ch, 1       ; Make sure 1 <= font height <= 32
            jb .failure
            cmp ch, 32
            ja .failure
            mov [parsed_bundle.font], bx
        else
        mov di, bundle_keys.blink
        call cmp_wstring
        if e
            cmp word [bx], 1    ; Make sure our boolean is exactly 1 byte
            jne .failure
            mov [parsed_bundle.blink], bx
        else
            ; Key not recognized
            jmp .failure
        end_if

        ; Advance SI to point to the next key
        mov si, bx          ; SI = value
        next_wstring si     ; SI = key following that value
    end_while

    ; Bundle parsed successfully!
    clc
    jmp .ret

    ; Something about the bundle was bad
    .failure:
    stc

    .ret:
    pop si
    pop di
    pop bx
    ret


;-------------------------------------------------------------------------------
; Internal helpers
;-------------------------------------------------------------------------------
section .text

; Check bundle to make sure it has a valid structure.
;
; This function only checks the overall structure, making sure the bundle fits
; in the allotted space and that every key has a corresponding value. It does
; not validate the keys and values themselves, though.
;
; Sets CF if bundle structure is invalid.
validate_bundle_structure:
    push bx
    push si

    ; Validate the list structure to make sure that it's both
    ; properly formed and not too long.
    xor cx, cx              ; CX = number of list items
    mov si, start_of_bundle ; SI = pointer to current list item
    while_condition
        cmp word [si], 0    ; Loop until we hit the list terminator
    begin_while ne
        ; Advance SI to point to the next string
        mov bx, si          ; BX = old value of pointer
        next_wstring si
        inc cx              ; Count number of list items

        ; Make sure that we didn't advance so far that we wrapped around
        cmp si, bx
        jbe .invalid

        ; Make sure that we didn't hit the BSS section
        cmp si, section..bss.start
        jae .invalid
    end_while

    ; Make sure that each key in the list has a corresponding value
    and cl, 1       ; If CX is even, return successful (CF = 0).
    jz .ret         ; We don't need `clc` because `and` already clears CF.

    ; Something's wrong with the bundle
    .invalid:
    stc

    .ret:
    pop si
    pop bx
    ret


; BUNDLE_ASM
%endif
