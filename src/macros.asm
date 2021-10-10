;; General-purpose macros that don't belong anywhere else
%ifndef MACROS_ASM
%define MACROS_ASM

;-------------------------------------------------------------------------------
; Macros for generating if/else blocks
;
; Usage:
;   cmp ax, 123
;   begin_if e
;       ; Code that runs if AX == 123
;   else
;   cmp ax, 456
;   if e
;       ; Code that runs if AX == 456
;   else
;       ; Code that runs if AX is some other value.
;   end_if
;-------------------------------------------------------------------------------
%macro begin_if 1
    %push if_block
    %assign %$num_skip 0
    if %+1
%endmacro

%macro else 0
    jmp %$end_if
    %$skip%$num_skip:
    %assign %$num_skip %$num_skip + 1
%endmacro

%macro if 1
    j%-1 %$skip%$num_skip
%endmacro

%macro end_if 0
    %$skip%$num_skip:
    %$end_if:
    %pop
%endmacro


; TODO: while-loop macros?


; MACROS_ASM
%endif
