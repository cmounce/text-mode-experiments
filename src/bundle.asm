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
    .palette:       resw 1
    .font:          resw 1


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

        ; Check against each of the possible keys
        mov di, bundle_keys.palette ; PALETTE
        call try_strip_key_prefix
        jne .palette_key
        mov di, bundle_keys.font    ; FONT
        call try_strip_key_prefix
        jne .font_key
        jmp .continue               ; Unrecognized key: skip it.

        ; Load palette data
        .palette_key:
        cmp [si], word 3*16             ; Make sure we have exactly 16 colors
        jne .failure
        mov [parsed_bundle.palette], dx
        jmp .continue

        ; Load font data
        .font_key:
        mov cx, [si]
        cmp cl, 0       ; Make sure font is a multiple of 256 bytes
        jne .failure
        cmp ch, 1       ; Make sure 1 <= font height <= 32
        jb .failure
        cmp ch, 32
        ja .failure
        mov [parsed_bundle.font], si

        .continue:
        next_wstring si ; Advance to the next key-value pair
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
        next_wstring si
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
; Removes "KEY=" from a key-value string, but only if it matches the given key.
;
; SI = wstring of a key-value pair, e.g., "FOO=123"
; DI = bstring of a key to compare against, e.g., "FOO"
; If keys match, returns ZF = 0 and mutated string in SI.
; If they don't, returns ZF = 1 and leaves SI alone.
;-------------------------------------------------------------------------------
try_strip_key_prefix:
    push di
    push si
    xor cx, cx

    ; Get lengths of the two input strings
    mov ax, [si]        ; AX = length of key-value pair
    mov cl, [di]        ; CX = length of key to compare with
    cmp ax, cx
    jbe .no_match       ; Key-value pair is too short to contain key + '='

    ; Verify that key-value pair starts with our key
    add si, 2           ; Skip past wstring and
    inc di              ; bstring length headers
    repe cmpsb
    jne .no_match       ; Keys don't match
    cmp byte [si], '='
    jne .no_match       ; Key not terminated with delimiter '='

    ; Keys match: remove key prefix from the start of the wstring
    pop si              ; Restore old pointers
    pop di
    mov cl, [di]
    inc cx              ; CX = length of "KEY="
    mov ax, [si]
    sub ax, cx          ; AX = new length of wstring
    add si, cx          ; Mutate SI to remove prefix and
    mov [si], ax        ; write new length header
    xor ax, ax          ; Set ZF=1 (keys matched)
    ret

    ; All jumps here should leave ZF=0 (keys didn't match)
    .no_match:
    pop si
    pop di
    ret
