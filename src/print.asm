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
; print_bstring directly instead.
%macro print_literal 1
    section .data
    %%bstr: db_bstring %1

    section .text
    push bx
    mov bx, %%bstr
    call print_bstring
    pop bx
%endmacro

; Same as print_literal, except it appends a newline to the end.
%macro println_literal 1
    %strcat %%str %1 `\r\n`
    print_literal %%str
%endmacro


;==============================================================================
; Functions
;------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Print bstring in BX to stdout.
;-------------------------------------------------------------------------------
print_bstring:
    push bx

    xor cx, cx          ; Get string length
    mov cl, [bx]
    .loop:
        inc bx          ; Get next character
        mov dl, [bx]
        mov ax, 0200h   ; Write single character to stdout
        int 21h
        loop .loop

    pop bx
    ret

; PRINT_ASM
%endif
