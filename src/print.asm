;; Routines for printing
%ifndef PRINT_ASM
%define PRINT_ASM

%include 'string.asm'

;==============================================================================
; Constants
;==============================================================================

_newline:
    db_wstring `\r\n`

;==============================================================================
; Macros
;------------------------------------------------------------------------------

; Helper for println and friends.
; Usage:
;   ; Push C, B, A to the stack, then call some_function 3 times
;   _multipush_multicall some_function, A, B, C
%macro _multipush_multicall 2-*
    ; Push parameters onto the stack, in reverse order
    %assign %%num_strings %0 - 1
    %assign %%i 0
    %rep %%num_strings
        %rotate -1
        %assign %%i %%i + 1
        %ifstr %1
            ; Save string to .data and push its address to stack
            section .data
            %%str%[%%i]: db_wstring %1
            section .text
            push %%str%[%%i]
        %else
            ; Push register/constant (address of a wstring) to stack
            push %1
        %endif
    %endrep

    ; Rotate a final time to restore %1 to the actual first argument
    %rotate -1

    ; Call the given function for each string
    %if %%num_strings * 3 <= 10
        ; Size: 3 bytes per call
        %rep %%num_strings
            call %1
        %endrep
    %else
        ; Size: fixed cost of 10 bytes
        mov cx, %%num_strings
        %%loop:
            push cx
            call %1
            pop cx
            loop %%loop
    %endif
%endmacro

; Print one or more strings to stdout.
; Examples:
;   println "Hello, world!"
;   println "BX's string value is: ", bx
;   println ptr_to_str, " is somewhere in the data segment."
%macro println 1-*
    _multipush_multicall print_wstring, %{1:-1}, _newline
%endmacro

; Helper for terminating with an error message.
; Example: 'die 123, "foo"' prints "foo" to stderr and exits with code 123.
%macro die 2-*
    _multipush_multicall eprint_wstring, %{2:-1}, _newline
    mov al, %1
    jmp _die_exit
%endmacro


;==============================================================================
; Functions
;------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Pops wstring from stack and prints it to the given handle.
;
; AX = handle to write to
;-------------------------------------------------------------------------------
fprint_wstring:
    push bp
    mov bp, sp
    push bx

    ; Load BX = wstring that was on top of the stack before the function call
    mov bx, [bp + 4]        ; BX = wstring to be printed

    mov cx, [bx]            ; CX = number of bytes in the wstring
    lea dx, [bx + 2]        ; DX = contents of the wstring
    mov bx, ax              ; BX = handle to write to
    mov ah, 40h             ; Write data to handle
    int 21h

    pop bx
    pop bp
    ret 2                   ; Remove printed wstring from stack


;-------------------------------------------------------------------------------
; Pops wstring from stack and prints it to stdout.
;-------------------------------------------------------------------------------
print_wstring:
    mov ax, 1
    jmp fprint_wstring


;-------------------------------------------------------------------------------
; Pops wstring from stack and prints it to stderr.
;-------------------------------------------------------------------------------
eprint_wstring:
    mov ax, 2
    jmp fprint_wstring


;-------------------------------------------------------------------------------
; Helper for die macro: exit with return code.
;
; AL = Process return code
;-------------------------------------------------------------------------------
_die_exit:
    mov ah, 4ch             ; Terminate with return code
    int 21h


; PRINT_ASM
%endif
