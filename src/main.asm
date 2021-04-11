;; ZZT All-Purpose TSR (rewrite)
org 100h                ; Adjust addresses for DOS .COM file

section .text                           ; Non-resident code (parameter parsing, etc)
section .data       follows=.text       ; Non-resident data (help text, etc)
section .resident   follows=.data       ; Resident code/data
section .bss        follows=.resident   ; Non-initialized data, as usual


; The first few bytes of the resident section play double duty.
; They initially contain bootstrapping code, but once the TSR is installed, the space
; will be reused for keeping track of a few variables needed by the resident code.
; Here, we lay out those variables ahead of time.
start_tsr_variables:
absolute start_tsr_variables

old_int_10h:    ; previous video interrupt
.segment:   resb 2
.offset:    resb 2

old_int_2fh:    ; TSR multiplex interrupt
.segment:   resb 2
.offset:    resb 2

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime)
tsr_id_num: resb 1

end_tsr_variables:
segment .text

;
; Program start
;
%include 'args.asm'
segment .text
call parse_command_line
mov ah, 0
int 21h

; Calculates the 32-bit FNV-1a hash of a string and assigns it to a macro variable.
; Usage: fnv_hash variable_to_assign, 'string to be hashed'
%macro fnv_hash 2
%strlen %%num_bytes %2
%assign %%hash 0x811c9dc5
%assign %%i 0
%rep %%num_bytes
    %assign %%i %%i+1
    %substr %%byte %2 %%i
    %assign %%hash ((%%hash ^ %%byte) * 0x01000193) & 0xFFFFFFFF
%endrep
%assign %1 %%hash
%endmacro

%define TSR_ID_STRING "Quantum's all-purpose TSR, version rewrite-in-progress"
fnv_hash TSR_ID_HASH, TSR_ID_STRING
segment .text
tsr_id_hash: dd TSR_ID_HASH
