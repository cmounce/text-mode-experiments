; Miscellaneous DOS calls
%ifndef SYSTEM_ASM
%define SYSTEM_ASM


;-------------------------------------------------------------------------------
; Process termination
;-------------------------------------------------------------------------------

; Define some exit codes in rough order of severity
EXIT_OK         equ 0
EXIT_BAD_ARGS   equ 1   ; Invalid user input
EXIT_ERROR      equ 2   ; Generic error, in spite of valid user input
EXIT_BAD_BUNDLE equ 3   ; Bundled palette/font/etc are invalid
EXIT_BAD_CODE   equ 4   ; The .COM file itself is damaged

; Exit with return code
%macro exit 1
    %if %1 < 0 || %1 > 255
        %error Exit code out of range
    %endif
    mov ax, (4ch << 8) | %1 ; AH = 4ch: Exit with return code
    int 21h
%endmacro


;-------------------------------------------------------------------------------
; File IO
;-------------------------------------------------------------------------------
section .text

; Create a new file and return the handle.
;
; DX = File path, as a wstring
; On success, returns AX = file handle
; On failure, sets CF and returns AX = error code
dos_create_new_file:
    mov ah, 5bh             ; Create new file
    xor cx, cx              ; CX = attribute bits
    call dos_asciiz_wrapper
    ret


; Open an existing file for reading.
;
; DX = File path, as a wstring
; On success, returns AX = file handle
; On failure, sets CF and returns AX = error code
dos_open_existing_file:
    mov ax, 3d00h   ; Open file with AL = 0, read only
    call dos_asciiz_wrapper
    ret


; Close a file handle.
;
; BX = handle
; On failure, returns CF = 1, AX = error code
dos_close_file:
    mov ah, 3eh
    int 21h
    ret


;-------------------------------------------------------------------------------
; Internal helpers
;-------------------------------------------------------------------------------
section .text

; Calls int 21h after changing DX to point to a asciiz string.
;
; Takes DX = pointer to a wstring.
; All other registers are as if int 21h is being called directly.
; Returns whatever int 21h returns.
dos_asciiz_wrapper:
    push bp
    mov bp, sp

    ; Allocate buffer for asciiz string
    .BUFFER_SIZE equ 127 + 1        ; Max arg length plus null terminator
    sub sp, .BUFFER_SIZE

    ; Write asciiz string to buffer without disturbing registers
    pusha
    lea di, [bp - .BUFFER_SIZE]     ; DI = buffer to write to
    mov si, dx                      ; SI = wstring header
    mov cx, [si]                    ; CX = wstring size
    add si, 2                       ; SI = wstring contents
    rep movsb
    mov byte [di], 0                ; Write null terminator
    popa

    ; Call DOS with DX = asciiz string
    mov dx, sp                      ; DX = SP = start of buffer
    int 21h

    ; Restore original stack, returning whatever registers/flags DOS returned
    mov sp, bp
    pop bp
    ret


; SYSTEM_ASM
%endif
