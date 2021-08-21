;; Functions and definitions for TSR-specific stuff

;===============================================================================
; Resident code and code fragments
;-------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Safely remove TSR from memory.
;
; DX = Resident segment
; Returns AX=0 on failure, AX=1 on success.
;-------------------------------------------------------------------------------
uninstall_tsr:
    push bx
    push ds
    push es
    cli

    ; Make sure interrupt handlers haven't changed since we were installed.
    ; If they have, it means another TSR is installed on top of us.
    mov ax, 3510h   ; Get current 10h vector
    int 21h
    mov ax, es      ; Make sure segment hasn't changed. Technically, we should
    cmp ax, dx      ; also check the offset, but (1) that's hard to calculate,
    jne .fail       ; and (2) it's unlikely someone else is using our segment.

    mov ax, 352Fh   ; Get current 2Fh vector
    int 21h
    mov ax, es      ; Same as above: make sure segment hasn't changed,
    cmp ax, dx      ; and abort if it has.
    jne .fail

    ; Restore old interrupt handlers
    mov es, dx
    mov ax, 2510h                       ; Set 10h handler
    mov ds, [es:old_int_10h.segment]
    mov dx, [es:old_int_10h.offset]
    int 21h

    mov ax, 252Fh                       ; Set 2Fh handler
    mov ds, [es:old_int_2fh.segment]
    mov dx, [es:old_int_2fh.offset]
    int 21h

    ; Free resident memory
    mov ah, 49h     ; ES = segment to free
    int 21h

    .success:
    mov ax, 1
    jmp .ret

    .fail:
    xor ax, ax

    .ret:
    sti
    pop es
    pop ds
    pop bx
    ret

;-------------------------------------------------------------------------------
; Code fragment: Intercept int 10h and establish our own stack
;-------------------------------------------------------------------------------
int_10h_handler_prefix:
cmp ah, 0                       ; Verify that this call is setting the video mode
je .set_video_mode
jmp far [cs:old_int_10h]        ; Otherwise, let the old handler handle it
.set_video_mode:
mov [cs:old_stack_pointer], sp  ; Replace caller's stack with our miniature stack
mov sp, old_stack_pointer
pushf                       ; Call the old int 10h as if it was
call far [cs:old_int_10h]   ; a regular subroutine
pusha
push ds
mov ax, cs
mov ds, ax
.end_of_contents:

;-------------------------------------------------------------------------------
; Code fragment: Clean up/restore environment and return from interrupt
;-------------------------------------------------------------------------------
int_10h_handler_suffix:
pop ds
popa
mov sp, [cs:old_stack_pointer]
iret
.end_of_contents:

;-------------------------------------------------------------------------------
; Code fragment: Set DX = pointer to palette in resident code
;-------------------------------------------------------------------------------
find_resident_palette:
mov dx, [palette_offset]
.end_of_contents:

;-------------------------------------------------------------------------------
; Install code: Overwrite in-memory code with buffer and terminate
;
; AH = TSR multiplex interrupt (usually 2Fh)
; AL = TSR ID
; SI = Pointer to array of Pascal strings, in order:
;   0. TSR ID hash value
;   1. Code for video interrupt handler
;   2. Code for TSR multiplex handler
;   3. Data blob (palette/font)
;-------------------------------------------------------------------------------
finalize_install:
    ; Save TSR handler ID in resident global
    mov [tsr_multiplex], ax

    ; Copy TSR ID hash value to resident header
    mov di, tsr_nametag
    call .process_pstring

    ; Copy interrupt handlers and save their addresses
    mov di, tsr_code_start
    call .process_pstring   ; Video interrupt handler
    push ax
    call .process_pstring   ; TSR multiplex handler
    push ax

    ; Copy data blob and write its address to resident global
    call .process_pstring
    mov [palette_offset], ax

    ; Install interrupts
    cli

    ; Patch TSR multiplex interrupt
    mov     ax, 352Fh   ; get and save current 2Fh vector
    int     21h
    mov     [old_int_2fh.offset], bx
    mov     [old_int_2fh.segment], es
    mov     ax, 252Fh   ; replace current 2Fh vector
    pop     dx
    int     21h

    ; Patch video interrupt
    mov     ax, 3510h   ; get and save current 10h vector
    int     21h
    mov     [old_int_10h.offset], bx
    mov     [old_int_10h.segment], es
    mov     ax, 2510h   ; replace current 10h vector
    pop     dx
    int     21h

    sti

    ; Free environment block before exiting
    mov ah, 49h
    mov es, [2ch]   ; Environment segment from PSP
    int 21h

    ; Terminate and stay resident
    mov ax, 3100h   ; TSR, return code 0
    mov dx, di      ; Number of bytes that should remain resident
    add dx, 16 - 1  ; Make sure division by 16 gets rounded up
    shr dx, 4       ; DX = number of paragraphs
    int 21h

    ; Helper: Given SI = Pascal-style string, copy its raw contents to DI.
    ; Advances SI to next string in array, DI to next location to write to.
    ; Returns AX = start of the copy that was created.
    .process_pstring:
        mov cx, [si]
        add si, 2
        mov ax, di
        rep movsb
        ret
.end_of_contents:

;-------------------------------------------------------------------------------
; TSR multiplex handler (int 2Fh)
;
; Returns the resident code segment in ES and the TSR nametag in ES:DI.
;-------------------------------------------------------------------------------
int_2fh_handler:
cmp ah, [cs:tsr_multiplex.id]
je .match
jmp far [cs:old_int_2fh]
.match:
mov al, 0ffh        ; Indicate installed status
mov di, cs
mov es, di
mov di, tsr_nametag ; TODO: save a couple bytes by setting DI outside the TSR
iret
.end_of_contents:
