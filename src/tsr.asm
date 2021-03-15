;; ZZT All-Purpose TSR (rewrite)
org 100h                ; Adjust addresses for DOS .COM file

;; Overview
; This TSR is composed of the following parts, in this order:
; 1. Data required by the TSR itself
; 2. Video data (font, palette)
; 3. Resident code
; 4. Non-resident data (help text, etc)
; 5. Non-resident code
; All resident code is written to be relocatable. During TSR installation,
; unneeded parts are removed and memory is compacted, in order to keep the
; resident portion (and conventional memory usage) to a minimum.

;; 1. TSR data
start_resident:
; This string ID identifies the TSR in memory, so that the utility
; can find out if the TSR is installed or not.
%define TSR_ID 'ZapT2' ; ZZT all-purpose TSR, v2.0
%strlen TSR_ID_SIZE TSR_ID
; This piece of memory does double duty: it initially contains code
; to jump to main, but we overwrite it with the ID string later on.
; This is a hack to reduce resident size by a few bytes.
tsr_id_str:
jmp main
times TSR_ID_SIZE-$+tsr_id_str db 0

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime).
tsr_id_num:
db 0

%define man.addr (start_resident + 5)

%assign bytes_of_data 0
%assign bytes_of_data bytes_of_data + TSR_ID_SIZE
%assign bytes_of_data bytes_of_data + 1
%define start_of_data (start_resident + bytes_of_data)

main:
mov bx, tsr_id_num
mov [bx], byte 1
mov bx, man.addr
mov [bx], byte 1

mov ah, 0
int 21h

data:
db TSR_ID
