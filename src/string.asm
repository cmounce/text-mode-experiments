;; Helpers for working with strings
%ifndef STRING_ASM
%define STRING_ASM

;===============================================================================
; Macros
;-------------------------------------------------------------------------------

; Prepend a wstring length header to arbitrary assembly. Usage:
;       foo:
;       begin_wstring
;           ; Arbitrary assembly...
;       end_wstring
; In the above example, foo points to a wstring containing the assembled bytes
; of the code between the delimiters. Additionally, the macro defines a label
; foo.contents pointing to the raw bytes (skipping the length header).
%macro begin_wstring 0
    %push fragment
    dw %$fragment_size
    %$fragment_start:
    .contents:
%endmacro
%macro end_wstring 0
    %$fragment_size equ $ - %$fragment_start
    %pop
%endmacro

; Like db, but adds a single-byte length prefix before the given string.
; Example: 'db_bstring "ABC"' outputs 'db 3, "ABC"'
%macro db_bstring 1
    %strlen %%n %1
    %if %%n > 0xFF
        %error "String too long"
    %endif
    db %%n, %1
%endmacro

; Advance a register to point to the next bstring in a list.
; Usage: next_bstring si
; Does not stop at end of list; caller is responsible for checking [reg] == 0.
%macro next_bstring 1
    mov ax, %1
    inc ax          ; Add header length
    add al, [%1]    ; Add string length
    adc ah, 0
    mov %1, ax
%endmacro


;===============================================================================
; Functions
;-------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Performs a case-insensitive comparison of SI and DI.
;
; Sets ZF = 0 if the two strings are equal.
;-------------------------------------------------------------------------------
icmp_bstring:
    push di
    push si

    ; Make sure the two strings are the same size
    xor cx, cx
    mov cl, [si]
    cmp cl, [di]    ; Compare the two sizes,
    jne .ret        ; returning ZF = non-zero if they are different

    ; Compare the next CX characters
    .loop:
        lodsb                       ; Load character from SI
        call tolower_accumulator    ; and lower-case it
        mov ah, al
        mov al, [di]                ; Load character from DI
        inc di                      ; and lower-case it
        call tolower_accumulator
        cmp al, ah                  ; Compare the two characters,
        jne .ret                    ; returning ZF = non-zero if different.
        loop .loop

    ; If the above loop finishes, then our final comparison set ZF = 0,
    ; which we reuse as our return value when we return below.

    .ret:
    pop si
    pop di
    ret


;-------------------------------------------------------------------------------
; Advance SI to point to the next wstring in a list.
;
; This function does not stop when it hits the end of a list!
; The caller is responsible for checking [SI] == 0.
;-------------------------------------------------------------------------------
next_wstring:
    ; TODO: Would this be better as a macro?
    add si, [si]
    add si, 2
    ret


;-------------------------------------------------------------------------------
; Make the character in AL lowercase.
; Clobbers no registers!
;-------------------------------------------------------------------------------
tolower_accumulator:
    cmp al, 'A'
    jb .ret
    cmp al, 'Z'
    ja .ret
    add al, ('a' - 'A')
    .ret:
    ret


; STRING_ASM
%endif
