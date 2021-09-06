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
