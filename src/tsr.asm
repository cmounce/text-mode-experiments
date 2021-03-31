;; ZZT All-Purpose TSR (rewrite)
org 100h                ; Adjust addresses for DOS .COM file

;; Overview
; This TSR is composed of the following parts, in this order:
; 1. TSR variables
; 2. Video data (font, palette)
; 3. Resident code
; 4. Non-resident data (help text, etc)
; 5. Non-resident code
; All resident code is written to be relocatable. During TSR installation,
; unneeded parts are removed and memory is compacted, in order to keep the
; resident portion (and conventional memory usage) to a minimum.

;; 1. TSR variables
start_resident:
; The first few bytes of the resident section play double duty.
; They initially contain code: a jmp to the main part of the program.
jmp main
; However, once the TSR is fully bootstrapped, we reuse the first bytes
; of the resident section as storage for TSR-specific variables.
; The variables don't exist yet, though, so we need a macro to give
; them names and locations.
%assign reserved_bytes 0
%macro reserve_with_name 2
    ; Usage: reserve_with_name VARIABLE_NAME, NUMBER_OF_BYTES
    %1 equ start_resident+reserved_bytes
    %assign reserved_bytes reserved_bytes+%2
%endmacro

; Allocate space to store the old 10h (video) interrupt
reserve_with_name old_int_10h.segment, 2
reserve_with_name old_int_10h.offset, 2

; Allocate space to store the old 2fh (TSR multiplex) interrupt
reserve_with_name old_int_2fh.segment, 2
reserve_with_name old_int_2fh.offset, 2

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime).
reserve_with_name tsr_id_num, 1

; This string ID identifies the TSR in memory, so that the utility
; can find out if the TSR is installed or not.
%define TSR_ID 'ZapT2' ; ZZT all-purpose TSR, v2.0
%strlen TSR_ID_SIZE TSR_ID

;; 2. Video data
font_data:
times 256*14 db 0
palette_data:
times 16*3 db 0

;; 3. Resident code

;; 4. Non-resident data
data:
db TSR_ID

;; 5. Non-resident code
; Tasks
; - Parse subcommand: (none)/i/u/r/info/new
main:
mov bx, old_int_10h.segment
mov [bx], byte 1
mov bx, old_int_2fh.segment
mov [bx], byte 1

mov ah, 0
int 21h
