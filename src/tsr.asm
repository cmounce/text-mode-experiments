;; Functions and definitions for TSR-specific stuff

; The first few bytes following the PSP play double duty.
; They initially contain non-resident code, but after TSR installation,
; the space will be reused for keeping track of a few variables needed
; by the resident code.
absolute 100h

tsr_id_hash: resb 4

old_int_10h:    ; previous video interrupt
.segment:   resb 2
.offset:    resb 2

old_int_2fh:    ; TSR multiplex interrupt
.segment:   resb 2
.offset:    resb 2

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime)
tsr_id_num: resb 1

segment .text
install:
;; TODO:
; 0. Make sure TSR can be installed
; 1. Allocate buffer for assembling TSR
; 2. Append TSR code/data to buffer
; 3. Append install routine to buffer
;   a. Byte copier
;   b. Hook-into-interrupts code
;   c. Jump to PSP
; 4. Copy termination code to PSP (optional memory initializer)
; 5. Jump to install routine

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
segment .data
tsr_id_hash: dd TSR_ID_HASH
