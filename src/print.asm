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


;==============================================================================
; Functions
;------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Print wstring in BX to stdout.
;-------------------------------------------------------------------------------
print_wstring:
    push bx

    mov cx, [bx]        ; CX = string length
    add bx, 2           ; BX = string contents
    mov ax, 0200h       ; Prep for int 21h: write single character to stdout
    .loop:
        mov dl, [bx]    ; DL = current character
        int 21h         ; Print DL
        inc bx          ; Advance to next character
        loop .loop

    pop bx
    ret

; PRINT_ASM
%endif
