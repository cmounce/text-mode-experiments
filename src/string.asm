;; Helpers for working with strings
%ifndef STRING_ASM
%define STRING_ASM

;===============================================================================
; Macros
;-------------------------------------------------------------------------------

; Like db, but adds a single-byte length prefix before the given string.
; Example: 'db_bstring "ABC"' outputs 'db 3, "ABC"'
%macro db_bstring 1
    %strlen %%n %1
    %if %%n > 0xFF
        %error "String too long"
    %endif
    db %%n, %1
%endmacro


;===============================================================================
; Functions
;-------------------------------------------------------------------------------
section .text

;-------------------------------------------------------------------------------
; Advance SI to point to the next wstring in a list.
;
; This function does not stop when it hits the end of a list!
; The caller is responsible for checking [SI] == 0.
;-------------------------------------------------------------------------------
next_wstring:
    add si, [si]
    add si, 2
    ret


; STRING_ASM
%endif
