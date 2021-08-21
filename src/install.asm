;; Code for installing/uninstalling the TSR
%include "string.asm"

;===============================================================================
; Data
;-------------------------------------------------------------------------------

; The install/uninstall routines need a way to tell our TSR apart from any
; other TSRs in memory. This pseudorandom ID is how our TSR identifies itself.
section .data
tsr_id:
    begin_wstring
    ; First bytes of SHA-256 hash: "Quantum's all-purpose ZZT initializer"
    db 88, 175, 157, 250, 178, 228, 109, 45
    end_wstring


;===============================================================================
; Resident globals
;-------------------------------------------------------------------------------

; These memory addresses overlap with parts of the PSP and non-resident code.
; They only become valid after the resident code has been installed.

; When processing an interrupt, we reuse the PSP's command-line space as a
; miniature stack. The last word of the PSP holds the old stack pointer,
; and the 126 bytes preceding it are our temporary stack space.
absolute 80h
resb 126                        ; Stack space
old_stack_pointer:  resw 1      ; Top of stack will contain old SP

; Contains the TSR ID to identify this chunk of memory as our TSR
resident_nametag:   resb tsr_id_length

old_int_10h:        ; previous video interrupt
    .offset:        resw 1
    .segment:       resw 1

old_int_2fh:        ; TSR multiplex interrupt
    .offset:        resw 1
    .segment:       resw 1

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime)
multiplex_id:       resb 1

; End of fixed-location resident globals, start of font/palette data
resident_data:


;===============================================================================
; Non-resident code
;-------------------------------------------------------------------------------

;-------------------------------------------------------------------------------
; Checks to see if our TSR is already resident in memory.
;
; Returns:
; - AL = an available multiplex ID, or 0 if TSR cannot be installed
; - CX = memory segment of our TSR, or 0 if it is not installed
;-------------------------------------------------------------------------------
scan_multiplex_ids:
    .min_id equ 0C0h    ; Range of multiplex IDs reserved for applications
    .max_id equ 0FFh

    push bx
    push es

    mov bh, .max_id     ; BH = the ID we're currently scanning
    xor bl, bl          ; BL = an unoccupied ID (0 if none found)

    ; Scan all multiplex IDs, from high to low
    .loop:
        ; Scan current multiplex ID
        mov ah, bh
        call _check_single_multiplex_id
        cmp es, 0           ; Stop scanning once we find our TSR
        jne .found

        ; If this is the first unoccupied ID we've found, take note of it
        cmp al, 0           ; AL != 0 means some other TSR occupies this ID
        jne .continue
        cmp bl, 0           ; BL != 0 means we already found an available ID
        jne .continue
        mov bl, bh

        ; Continue scanning
        .continue:
        dec bh
        cmp bh, .min_id
        jae .loop

    ; We finished scanning without finding our TSR
    mov al, bl  ; AL = available multiplex ID, if any
    xor cx, cx  ; CX = 0 means our TSR not found
    jmp .ret

    ; We found our TSR
    .found:
    xor al, al  ; AL = 0 means TSR cannot be installed
    mov cx, es  ; CX = segment of our TSR

    .ret:
    pop es
    pop bx
    ret


;-------------------------------------------------------------------------------
; Checks to see if a given multiplex ID is occupied.
;
; Takes AH = the multiplex ID to check.
; Returns AL = 0 if that multiplex ID is available.
; Returns ES = resident segment if our TSR is installed here, 0 otherwise.
;-------------------------------------------------------------------------------
_check_single_multiplex_id:
    ; We're about to call an unknown TSR. Save all 16-bit registers except for:
    ; - Caller-saved registers: AX, CX, DX are acceptable to clobber
    ; - Registers considered to be safe: CS:IP and SS:SP
    ; - ES, because we overwrite it anyway as part of our return value
    push bp
    push bx
    push di
    push ds
    push si

    ; Call multiplex: AX = ??00h, where ?? is the ID to check
    xor al, al
    xor bx, bx      ; Ralf Brown recommends clearing BX through DX
    xor cx, cx
    xor dx, dx
    int 2fh

    ; Is there a TSR at this multiplex ID?
    cmp al, 0       ; This AL is also our return value: 0 means unoccupied.
    je .unoccupied

    ; Is the TSR at this multiplex ID our TSR?
    mov si, cs                  ; DS:SI = expected string (tsr_id)
    mov ds, si
    mov si, tsr_id.contents
    mov cx, tsr_id.length
    mov di, resident_nametag    ; ES:DI = actual string
    rep cmpsb
    jne .not_us

    ; We found our TSR!
    ; No need to set any return registers, because our TSR should have
    ; already set AL = non-zero and ES = resident segment.
    jmp ret

    .unoccupied:
    .not_us:
    xor es, es      ; ES = 0 indicates that our TSR is not installed here

    .ret:
    pop si
    pop ds
    pop di
    pop bx
    pop bp
    ret


;-------------------------------------------------------------------------------
; Installs TSR and terminates program.
;
; AL = Available multiplex ID to install into (found via scan_multiplex_ids)
;-------------------------------------------------------------------------------
install_and_terminate:
    ; WHAT DOES THIS FUNCTION DO? It's been a long time and I forgot.
    ; - Set up buffer = empty wstring list
    ; - Append stuff to list:
    ;   - TSR ID string
    ;   - Video handler (prefix, video, suffix)
    ;   - Multiplex handler
    ;   - Data blob
    ;   - Relocatable installer
    ; - Jump to installer

    ; Question: what to do with the data blob?
    ;   - Video code generates it
    ;   - Video code needs to know its offset
    ;   - Feeling: install code shouldn't know anything about it
    ; Options:
    ;   A. Keep separate video-code and video-data blobs, and installer knows
    ;   B. Bundle video code/data together (and make it truly relocatable)
    ; Size cost of current approach ("resw 1" + "mov dx, [addr]")
    ;   - resw: 2 bytes
    ;   - mov: 4 bytes
    ; Latest position:
    ;   - Hard-code the address of the data blob: first thing after globals
    ;   - When video.asm builds the video blob, it appends "mov si, (addr)"
    ;   - Install routine still knows there's separate code/data blobs
    ;   - video.asm can still do previews: just append "mov si, (other addr)"


    ; Initialize buffer to empty string
    mov di, global_buffer
    mov [di], 0

    ; TODO: Does this belong in string.asm? What should it be called?
    %macro append_empty_wstring
        next_wstring di
        mov [di], 0
    %endmacro

    ; String 1: TSR ID hash
    mov si, tsr_id
    call concat_wstring
    append_empty_wstring



    ; String 2: video data
    ; TODO

    ; String 3: int 10h handler
    ; TODO: prefix
    call concat_resident_video_code_wstring
    ; TODO: suffix

    ; String 4: int 2fh handler
    ; TODO


    ; Allocate BX = buffer on stack
    BUFFER_SIZE equ 20*1024
    sub sp, BUFFER_SIZE
    mov bx, sp

    ; Save destination multiplex ID
    push ax

    ; Initialize DI to point to an empty Pascal string
    mov di, bx
    mov word [di], 0

    ; String 0: TSR ID hash
    %macro append_fragment 1
        mov si, %1
        mov cx, %1.end_of_contents - %1
        call .append_to_pstring
    %endmacro
    append_fragment tsr_id_hash_value
    call .new_pstring

    ; String 1: video interrupt handler
    append_fragment int_10h_handler_prefix
    append_fragment find_resident_palette
    append_fragment set_palette
    append_fragment set_font
    append_fragment int_10h_handler_suffix
    call .new_pstring

    ; String 2: TSR multiplex handler
    append_fragment int_2fh_handler
    call .new_pstring

    ; String 3: data blob
    mov si, [parsed_bundle.palette] ; We can't use append_fragment here because
    mov cx, 3*16                    ; the palette comes from the bundle, and it
    call .append_to_pstring         ; doesn't have labels marking start/end

    mov si, parsed_bundle.font_height   ; Likewise for font data.
    mov cx, 1                           ; We append the font height (1 byte)
    call .append_to_pstring             ; before appending the glyph data.
    mov si, [parsed_bundle.font]
    mov ch, [parsed_bundle.font_height]
    xor cl, cl
    call .append_to_pstring
    call .new_pstring

    ; String 4: TSR installation code
    append_fragment finalize_install

    ; Jump to installation code
    mov si, bx          ; SI = start of buffer containing strings
    lea bx, [di + 2]    ; BX = contents of TSR installation string
    pop ax              ; AL = multiplex ID to use
    mov ah, 2Fh         ;
    jmp bx              ; Jump to finalize_install

    ; Helper: Append SI:CX to Pascal string pointed to by DI
    ; Sets CX = 0 but otherwise does not clobber any registers
    .append_to_pstring:
        push bx
        mov bx, di          ; BX = pointer to string header
        add di, 2           ; Skip past string header
        add di, [bx]        ; Skip past string contents
        add [bx], cx        ; Update length of string
        rep movsb           ; Actually append data
        mov di, bx          ; Restore DI = pointer to string header
        pop bx
        ret

    ; Helper: Assuming DI points to an existing Pascal string, create
    ; an empty string right after it and set DI to point to it.
    .new_pstring:
        add di, [di]        ; Skip over string data
        add di, 2           ; and header,
        mov [di], word 0    ; and set new string's length = 0
        ret



;===============================================================================
; Resident code and code fragments
;-------------------------------------------------------------------------------
section .text

; Plan for organization
; - Non-resident code goes in install.asm
; - Interrupt handlers *also* go in install.asm (but not video code)
; - video.asm contains functions for appending relocatable code to buffer
; - Installer (in install.asm) wraps video code with interrupt handlers
