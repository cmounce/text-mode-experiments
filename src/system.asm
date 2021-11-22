; Miscellaneous DOS calls
%ifndef SYSTEM_ASM
%define SYSTEM_ASM

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


; SYSTEM_ASM
%endif
