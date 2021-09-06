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
; miniature stack. The last 2 words of the PSP holds the old stack pointer,
; and the 124 bytes preceding them are our temporary stack space.
absolute 80h
resb 124                        ; Stack space
resident_stack_start:
old_stack_pointer:  resw 1      ; Top of stack will contain old SP/SS
old_stack_segment:  resw 1

; Contains the TSR ID to identify this chunk of memory as our TSR
resident_nametag:   resb tsr_id.length

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
section .text

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
        mov dx, es          ; TODO: _check_single_multiplex_id to return DX?
        cmp dx, 0           ; Stop scanning once we find our TSR
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
    jmp .ret

    .unoccupied:
    .not_us:
    xor cx, cx      ; Set ES = 0 to indicate our TSR is not installed here
    mov es, cx

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
    ; Save AL = multiplex ID so we can use it later
    push ax

    ; Initialize buffer to empty string
    mov di, global_buffer
    mov [di], word 0

    ; TODO: Does this belong in string.asm? What should it be called?
    %macro append_empty_wstring 0
        next_wstring di
        mov [di], word 0
    %endmacro

    ; String 1: TSR ID hash
    mov si, tsr_id
    call concat_wstring
    append_empty_wstring

    ; String 2: video data
    call concat_video_data_wstring
    append_empty_wstring

    ; String 3: int 10h handler
    mov si, int_10h_handler_prefix          ; Handler consists of prefix...
    call concat_wstring
    call concat_resident_video_code_wstring ; video code...
    mov si, int_10h_handler_suffix          ; and suffix, all in one wstring.
    call concat_wstring
    append_empty_wstring

    ; String 4: int 2fh handler
    mov si, int_2fh_handler
    call concat_wstring
    append_empty_wstring

    ; Copy installer to global buffer.
    ; This is to guarantee that the installation code will be located in
    ; memory at a location where it won't accidentally overwrite itself.
    mov si, finalize_install
    call concat_wstring

    ; Call installer
    pop ax              ; AL = TSR multiplex ID
    lea bx, [si + 2]    ; BX = start of install code
    jmp bx


;-------------------------------------------------------------------------------
; Install code: Overwrite in-memory code with buffer and terminate
;
; AL = TSR ID to use for multiplex identification
; global_buffer = list of 4 wstrings:
;   0. TSR ID hash value
;   1. Data blob (palette/font)
;   2. Code for video interrupt handler
;   3. Code for TSR multiplex handler
;-------------------------------------------------------------------------------
finalize_install:
begin_wstring
    ; Save TSR handler ID in resident global
    mov [multiplex_id], ax

    ; Copy TSR ID hash value to resident header
    mov si, global_buffer
    mov di, resident_nametag
    call .transfer_wstring

    ; Copy data blob
    mov di, resident_data
    call .transfer_wstring

    ; Copy interrupt handlers and save their addresses
    push di
    call .transfer_wstring  ; Video interrupt handler
    push di
    call .transfer_wstring  ; TSR multiplex handler

    cli     ; Install interrupts...

    ; Patch TSR multiplex interrupt
    mov     ax, 352Fh                   ; Get old 2Fh vector
    int     21h
    mov     [old_int_2fh.offset], bx    ; Save old vector
    mov     [old_int_2fh.segment], es
    mov     ax, 252Fh                   ; Set new 2Fh vector
    pop     dx
    int     21h

    ; Patch video interrupt
    mov     ax, 3510h                   ; Get old 10h vector
    int     21h
    mov     [old_int_10h.offset], bx    ; Save old vector
    mov     [old_int_10h.segment], es
    mov     ax, 2510h                   ; Set new 10h vector
    pop     dx
    int     21h

    sti     ; Interrupts installed.

    ; Free environment block before exiting
    mov ah, 49h
    mov es, [2ch]   ; Environment segment from PSP
    int 21h

    ; Terminate and stay resident
    mov ax, 3100h   ; TSR, return code 0
    mov dx, di      ; DX = number of bytes that should remain resident
    add dx, 16 - 1  ; Make sure division by 16 gets rounded up
    shr dx, 4       ; DX = number of paragraphs
    int 21h

    ; Helper: Given SI = wstring, copy its raw contents to DI.
    ; Advances SI to next wstring in list, DI to next location to write to.
    .transfer_wstring:
        mov cx, [si]
        add si, 2
        rep movsb
        ret
end_wstring


;===============================================================================
; Resident code and code fragments
;-------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Code fragments for int 10h (video) handler
;-------------------------------------------------------------------------------
int_10h_handler_prefix:
begin_wstring
    ; Make sure that this call is changing the video mode
    cmp ah, 0
    je .set_video_mode
    jmp far [cs:old_int_10h]    ; It isn't; defer to the old int 10h handler
    .set_video_mode:

    ; Switch to our own stack, so we don't depend on the caller's
    mov [cs:old_stack_pointer], sp  ; Save old SS:SP
    mov [cs:old_stack_segment], ss
    mov sp, cs                      ; New SS:SP = CS:resident_stack_start
    mov ss, sp
    mov sp, resident_stack_start

    ; Call the old handler as if it was a regular subroutine
    pushf
    call far [cs:old_int_10h]

    ; Prepare registers for running resident code
    pusha           ; Save clobber-able registers returned from old handler
    push ds         ; Set DS = CS
    mov ax, cs
    mov ds, ax
end_wstring
    ; Video code goes here...
int_10h_handler_suffix:
begin_wstring
    pop ds                          ; Restore registers, including whatever the
    popa                            ; old int 10h handler returned.
    mov sp, [cs:old_stack_pointer]  ; Restore stack.
    mov ss, [cs:old_stack_segment]
    iret
end_wstring

;-------------------------------------------------------------------------------
; TSR multiplex handler (int 2Fh)
;
; Returns the resident code segment in ES and the TSR nametag in ES:DI.
;-------------------------------------------------------------------------------
int_2fh_handler:
begin_wstring
    ; Make sure this call is for us
    cmp ah, [cs:multiplex_id]
    je .match
    jmp far [cs:old_int_2fh]
    .match:

    ; Identify ourselves
    mov al, 0ffh        ; Indicate installed status
    mov di, cs          ; Set ES:DI = CS:resident_nametag
    mov es, di
    mov di, resident_nametag
    ; TODO: we could save a couple bytes by only setting ES
    iret
end_wstring
