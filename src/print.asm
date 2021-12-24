;; Routines for printing
%ifndef PRINT_ASM
%define PRINT_ASM

%include 'string.asm'
%include 'system.asm'


;------------------------------------------------------------------------------
; Macros
;------------------------------------------------------------------------------

; Internal macro for making print macros (e.g., printf) easier to write.
; Code outside of print.asm should not call this directly.
%macro process_fprintf_args 1-*
    ; Process all macro arguments in backward order
    %assign %%i %0
    %rep %0
        ; Update current argument, loop variable
        ; %%i takes values n-1 through 0
        %rotate -1
        %assign %%i %%i - 1

        %ifstr %1
            ; Save string to .data
            section .data
            %%str%[%%i]: db_wstring %1
            section .text
            %define %%val %%str%[%%i]
        %else
            %define %%val %1
        %endif

        ; Generate code
        %if %%i == 0
            ; TODO: How many bytes does this special-case save, if any?
            mov dx, %%val           ; Format string goes in DX
        %else
            push %%val              ; Format arguments go on stack
        %endif
    %endrep
%endmacro


; Print a formatted string to stdout
; Examples:
;   - printf "Hello, world!"
;   - printf "BX's string value is: %s", bx
%macro printf 1-*
    process_fprintf_args %{1:-1}
    call printf_raw
%endmacro


; Like printf, but prints to stderr
%macro eprintf 1-*
    process_fprintf_args %{1:-1}
    call eprintf_raw
%endmacro


; Like printf, but prints to AX = file handle
%macro fprintf 1-*
    process_fprintf_args %{1:-1}
    call fprintf_raw
%endmacro


; Helper for terminating with an error message.
; Example: 'die 123, "foo"' prints "foo" to stderr and exits with code 123.
%macro die 2-*
    %strcat %%fmt_str %2, `\r\n`
    %if %0 == 2
        eprintf %%fmt_str
    %else
        eprintf %%fmt_str, %{3:-1}
    %endif
    exit %1
%endmacro


;------------------------------------------------------------------------------
; Functions
;------------------------------------------------------------------------------
section .text

; Wrapper around fprintf_raw for printing to stdout
printf_raw:
    mov ax, 1
    jmp fprintf_raw


; Wrapper around fprintf_raw for printing to stderr
eprintf_raw:
    mov ax, 2
    jmp fprintf_raw


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
                ; TODO: save a few bytes by deduplicating this
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
                ; TODO: Advance past format specifier in a more elegant way.
                ; Maybe a separate parsing function that advances SI?
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
    ; Save DX = start of bytes to print
    mov dx, si

    ; Advance SI past all bytes we're printing
    while_condition
        cmp si, di          ; Iterate SI as far as the end of the format string
    begin_while b
        cmp byte [si], '%'  ; Break early if we hit a format specifier
        je break
        inc si
    end_while

    ; Print bytes from DX to SI
    mov cx, si      ; CX = number of bytes to print = SI - DX
    sub cx, dx
    mov ah, 40h     ; Write data to handle in BX
    int 21h

    ret


; PRINT_ASM
%endif
