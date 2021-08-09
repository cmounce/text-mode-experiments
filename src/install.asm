;; Code for installing/uninstalling the TSR
%include "string.asm"

;===============================================================================
; Data
;-------------------------------------------------------------------------------

; The install/uninstall routines need a way to tell our TSR apart from any
; other TSRs in memory. This pseudorandom ID is how our TSR identifies itself.
section .data
tsr_id:
    ; First bytes of SHA-256 hash: "Quantum's all-purpose ZZT initializer"
    db 88, 175, 157, 250, 178, 228, 109, 45
tsr_id_length equ 8


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

; End of globals
dynamic_resident_start:


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
    mov si, tsr_id
    mov cx, tsr_id_length
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


;===============================================================================
; Resident code and code fragments
;-------------------------------------------------------------------------------
section .text

; Plan for organization
; - Non-resident code goes in install.asm
; - Interrupt handlers *also* go in install.asm (but not video code)
; - video.asm contains functions for appending relocatable code to buffer
; - Installer (in install.asm) wraps video code with interrupt handlers
