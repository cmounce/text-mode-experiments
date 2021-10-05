;; Routines for printing
%ifndef PRINT_ASM
%define PRINT_ASM

%include 'string.asm'

;==============================================================================
; Macros
;------------------------------------------------------------------------------

; Helper for printing a string literal to stdout.
; This copies the string literal to initialized memory; if the same string is
; used multiple times, it makes more sense to declare it centrally and call
; print_wstring directly instead.
%macro print_literal 1
    section .data
    %%str: db_wstring %1

    section .text
    push bx
    mov bx, %%str
    call print_wstring
    pop bx
%endmacro

; Same as print_literal, except it appends a newline to the end.
%macro println_literal 1
    %strcat %%str %1 `\r\n`
    print_literal %%str
%endmacro

; Helper for terminating with an error message.
; Example: 'die 123, "foo"' prints "foo" to stderr and exits with code 123.
%macro die 2
    %strcat %%str %2 `\r\n`
    section .data
    %%msg: db_wstring %%str

    section .text
    mov al, %1
    mov bx, %%msg
    call die_wstring
%endmacro


;==============================================================================
; Functions
;------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Print wstring in BX to the given handle.
;
; AX = handle to write to
;-------------------------------------------------------------------------------
fprint_wstring:
    push bx

    mov cx, [bx]        ; CX = number of bytes to write
    lea dx, [bx + 2]    ; DX = data to write
    mov bx, ax          ; BX = handle to write to
    mov ah, 40h         ; Write data to handle
    int 21h

    pop bx
    ret


;-------------------------------------------------------------------------------
; Print wstring in BX to stdout.
;-------------------------------------------------------------------------------
print_wstring:
    mov ax, 1
    jmp fprint_wstring


;-------------------------------------------------------------------------------
; Print wstring in BX to stderr.
;-------------------------------------------------------------------------------
eprint_wstring:
    mov ax, 2
    jmp fprint_wstring


;-------------------------------------------------------------------------------
; Print an error message to stderr and quit with an error code.
;
; AL = Process return code
; BX = Error message wstring to print
;-------------------------------------------------------------------------------
die_wstring:
    push ax
    call eprint_wstring
    pop ax                  ; AL = errorlevel
    mov ah, 4ch             ; Terminate with return code
    int 21h


; PRINT_ASM
%endif
