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
    ; TODO: macro "hint_unreachable" that suppressess this jmp
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
    %pop if_block
%endmacro


;-------------------------------------------------------------------------------
; Macros for while loops
;
; Usage:
;   while_condition
;       cmp ax, 123
;   begin_while ne
;       ; Loop body that modifies AX
;       inc ax
;   end_while
;   ; AX = 123 by this point
;-------------------------------------------------------------------------------

%macro while_condition 0
    %push while_block
    push_loop_context
    continue:
%endmacro

%macro begin_while 1
    j%-1 break
%endmacro

%macro end_while 0
    jmp continue
    break:
    %pop while_block
    pop_loop_context
%endmacro


;-------------------------------------------------------------------------------
; Internal macro helpers for loops
;-------------------------------------------------------------------------------
; Counter used for assigning unique IDs to each loop
%assign loop_id_counter 0

; ID of the current loop
%assign loop_id 0

; Define break/continue to be unique names.
; We aren't using NASM's native context stack for this because we don't want
; break/continue to be buried when other macros push onto the context stack
; (e.g., an if macro inside of a loop macro).
%macro push_loop_context 0
    ; Generate a new loop_id
    %assign loop_id_counter loop_id_counter + 1
    %assign loop_%[loop_id_counter]_parent loop_id
    %assign loop_id loop_id_counter

    ; Update common label names
    %define break loop_%[loop_id]_break
    %define continue loop_%[loop_id]_continue
%endmacro

; Revert break/continue to whatever
%macro pop_loop_context 0
    %assign loop_id loop_%[loop_id]_parent
    %define break loop_%[loop_id]_break
    %define continue loop_%[loop_id]_continue

    ; Clean up defines if no parent loop exists
    %if loop_id = 0
        %undef break
        %undef continue
    %endif
%endmacro

; MACROS_ASM
%endif
