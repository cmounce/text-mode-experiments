;; Routines for printing
%ifndef PRINT_ASM
%define PRINT_ASM

%include 'string.asm'
%include 'system.asm'


;------------------------------------------------------------------------------
; Constants
;------------------------------------------------------------------------------

newline_string:
    db_wstring `\r\n`


;------------------------------------------------------------------------------
; Macros
;------------------------------------------------------------------------------

; Helper for println and friends.
; Usage:
;   ; Push C, B, A to the stack, then call some_function 3 times
;   multipush_multicall some_function, A, B, C
%macro multipush_multicall 2-*
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
    multipush_multicall print_wstring, %{1:-1}, newline_string
%endmacro


; Helper for terminating with an error message.
; Example: 'die 123, "foo"' prints "foo" to stderr and exits with code 123.
%macro die 2-*
    multipush_multicall eprint_wstring, %{2:-1}, newline_string
    exit %1
%endmacro


%macro test_printf 1-*
    ; Process all macro arguments in backward order
    %assign %%i %0
    %rep %0
        ; Update current argument, loop variable
        ; %%i takes values n-1 through 0
        %rotate -1
        %assign %%i %%i - 1

        ; Save string to .data
        section .data
        %%str%[%%i]: db_wstring %1
        section .text

        ; Generate code
        %if %%i == 0
            mov dx, %%str%[%%i]     ; Format string goes in DX
        %else
            push %%str%[%%i]        ; Format arguments go on stack
        %endif
    %endrep
    mov ax, 1                       ; Use stdout (TODO: should go in helper fn)
    call fprintf_raw
%endmacro


;------------------------------------------------------------------------------
; Functions
;------------------------------------------------------------------------------
section .text

; Print a format string to the given file handle
;
; AX = handle to write to
; DX = wstring containing format-string data
; Format string arguments should be pushed to the stack in reverse order.
fprintf_raw:
    push bp
    mov bp, sp
    push bx
    push di
    push si

    ; Set BX = handle to write to
    mov bx, ax

    ; Set BP = address of first format string argument
    add bp, 4           ; Skip old value of BP + return address

    ; Set SI/DI = start/end of format string contents
    mov si, dx
    mov di, [si]        ; Get length of format string
    add si, 2           ; SI = start of format string
    add di, si          ; DI = just past end of format string

    ; Print contents of format string
    while_condition
        cmp si, di
    begin_while b
        cmp byte [si], '%'
        begin_if e
            ; This is a format specifier.
            ; Advance SI to point past the percent sign.
            inc si
            cmp si, di  ; Make sure SI is still in bounds
            jae break

            cmp byte [si], 's'
            begin_if e
                ; Format specifier: print string
                push bp
                mov bp, [bp]        ; BP = address of wstring
                mov cx, [bp]        ; CX = length of wstring
                lea dx, [bp + 2]    ; DX = contents of wstring
                pop bp
                mov ah, 40h         ; Write to handle
                int 21h

                add bp, 2           ; BP = next format arg
                inc si              ; SI = character following "%s"
            else
                ; Format specifier not recognized: print literal character
                mov cx, 1       ; Print 1 byte
                mov dx, si      ; Print from SI
                mov ah, 40h     ; Write to handle
                int 21h
                inc si          ; Move SI past this byte
            end_if
        else
            call fprintf_print_literals
        end_if
    end_while

    pop si
    pop di
    pop bx
    pop bp
    ret


; Helper for fprintf_raw: print literal characters up to the next percent sign.
;
; BX = file handle to print to
; SI = memory location to start printing
; DI = end of format string (exclusive)
; Advances SI past the last byte printed.
fprintf_print_literals:
    push di

    ; Set DI = first byte that shouldn't be printed
    push si
    while_condition
        cmp si, di          ; Loop SI over remaining bytes of format string
    begin_while be
        cmp byte [si], '%'  ; Break early if we hit a format specifier.
        je break
        inc si
    end_while
    mov di, si              ; DI = end of printable area (exclusive)
    pop si                  ; Restore SI = start of area to print

    ; Print byte range delimited by SI, DI
    mov cx, di      ; CX = number of bytes to print
    sub cx, si
    mov dx, si      ; DX = start of what to print
    mov ah, 40h     ; Write data to handle
    int 21h

    ; Advance SI past all bytes printed
    mov si, di

    pop di
    ret


; Pops wstring from stack and prints it to the given handle.
;
; AX = handle to write to
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


; Pops wstring from stack and prints it to stdout.
print_wstring:
    mov ax, 1
    jmp fprint_wstring


; Pops wstring from stack and prints it to stderr.
eprint_wstring:
    mov ax, 2
    jmp fprint_wstring


; PRINT_ASM
%endif
