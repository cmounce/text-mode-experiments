;; Code related to the bundle of config data appended to the .com file
%include "string.asm"

;===============================================================================
; Consts
;-------------------------------------------------------------------------------
section .data

%define DATA_HEADER "DATA:"
%define PALETTE_KEY "PALETTE"
%define FONT_KEY "FONT"

; Define a list of all the valid keys
bundle_keys:
    .palette:   db_bstring PALETTE_KEY
    .font:      db_bstring FONT_KEY
    db 0


;===============================================================================
; Appended data
;-------------------------------------------------------------------------------
section .append

; Set up data header and save its address
db DATA_HEADER
start_of_bundle:

; Minor hack: initialize the .com file with some palette data.
; In the future, we won't do this.
dw 8+(3*16)
db PALETTE_KEY, "="
incbin "../goodies/palettes/rgb332.pal"

dw 5+(14*256)
db FONT_KEY, "="
incbin "../goodies/fonts/fixed.f14"

; Terminate the data bundle
dw 0


;===============================================================================
; Variables
;-------------------------------------------------------------------------------
section .bss
parsed_bundle:
    .palette:       resb 2
    .font:          resb 2
    .font_height:   resb 1


;===============================================================================
; Code
;-------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Reads bundled data from end of .com file into BSS structs.
;
; Returns AX=1 on success, AX=0 on failure.
;-------------------------------------------------------------------------------
parse_bundled_data:
    push si
    push di

    ; Before we parse the bundle, make sure the overall structure is valid.
    call validate_bundle_structure
    cmp ax, 0
    je .failure

    ; Loop over each key-value pair in the bundle
    mov si, start_of_bundle
    .loop:
        cmp [si], word 0    ; Stop at the end of the list
        je .break

        ; Do if/else if/else if... for each of the possible keys
        mov di, bundle_keys.palette ; Key == PALETTE?
        call get_value_for_key
        cmp dx, 0
        jne .palette_key
        mov di, bundle_keys.font    ; Key == FONT?
        call get_value_for_key
        cmp dx, 0
        jne .font_key
        jmp .continue               ; Unrecognized key: skip it.

        ; Load palette data
        .palette_key:
        cmp cx, 3*16                    ; Make sure we have exactly 16 colors
        jne .failure
        mov [parsed_bundle.palette], dx
        jmp .continue

        ; Load font data
        .font_key:
        cmp cl, 0       ; Make sure font is a multiple of 256 bytes
        jne .failure
        cmp ch, 1       ; Make sure 1 <= font height <= 32
        jb .failure
        cmp ch, 32
        ja .failure
        mov [parsed_bundle.font], dx
        mov [parsed_bundle.font_height], ch

        .continue:
        call next_wstring   ; Advance to the next key-value pair
    jmp .loop
    .break:

    ; Bundle parsed successfully!
    .success:
    mov ax, 1
    jmp .ret

    ; Something about the bundle was bad
    .failure:
    xor ax, ax

    .ret:
    pop si
    pop di
    ret


;-------------------------------------------------------------------------------
; Returns AX = 1 if the bundled data has a valid structure, AX = 0 otherwise.
;-------------------------------------------------------------------------------
validate_bundle_structure:
    push bx
    push si

    ; Validate the list structure to make sure that it's both
    ; properly formed and not too long.
    mov si, start_of_bundle
    .loop:
        cmp [si], word 0            ; Loop until we hit the end of the list
        je .break
        mov bx, si                  ; BX = old string, SI = next string
        call next_wstring
        cmp si, bx                  ; Make sure we moved forward relative to
        jbe .invalid                ; BX, and that we didn't wrap around.
        cmp si, section..bss.start  ; Make sure we didn't hit the BSS section.
        jae .invalid
    jmp .loop
    .break:

    ; We reached the end of the list without finding any structural issues
    mov ax, 1
    jmp .ret

    ; Something's wrong with the bundle
    .invalid:
    xor ax, ax

    .ret:
    pop si
    pop bx
    ret


;-------------------------------------------------------------------------------
; Checks the given key-value pair to see if it starts with the given key.
;
; SI = wstring of a key-value pair, e.g., "FOO=123"
; DI = bstring of a key, e.g., "FOO"
; If the key matches, returns DX = pointer to value and CX = length of value.
; If it doesn't, returns CX = DX = 0.
;-------------------------------------------------------------------------------
get_value_for_key:
    push si
    push di

    ; Get the lengths of the two strings
    mov ax, [si]    ; AX = length of KEY=VALUE
    xor cx, cx
    mov cl, [di]    ; CX = length of KEY
    cmp ax, cx
    jle .no_match   ; KEY=VALUE has to be longer than KEY because of the '='

    ; Verify that KEY=VALUE starts with our KEY
    add si, 2       ; Skip length prefixes
    inc di          ; of the two strings
    repe cmpsb
    jne .no_match

    ; Verify that KEY is followed by '='
    cmp byte [si], '='
    jne .no_match

    ; Input matches KEY=. Return VALUE in DX/CX.
    mov dx, si      ; SI points to the '=' separating key and value
    inc dx          ; DX = start of value
    pop di
    pop si
    mov cx, si      ; Set CX to point past the end of the KEY=VALUE string
    add cx, 2       ; by jumping past the length prefix
    add cx, [si]    ; and the contents of the wstring.
    sub cx, dx      ; Then, calculate CX = (end of value - start of value).
    ret

    ; Input didn't match! Restore everything and return.
    .no_match:
    xor cx, cx
    xor dx, dx
    pop di
    pop si
    ret
