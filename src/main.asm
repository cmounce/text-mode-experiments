;; ZZT All-Purpose TSR (rewrite)
org 100h                ; Adjust addresses for DOS .COM file

segment .text                           ; Non-resident code (parameter parsing, etc)
segment .data   follows=.text           ; Non-resident data (help text, etc)
segment .append follows=.data   nobits  ; Reserve space for palette/font appended to .COM file
segment .bss    follows=.append         ; Non-initialized data, as usual

; Allow up to 20k of data to be appended to the .COM file
segment .append
resb 20*1024


; The first few bytes of the resident section play double duty.
; They initially contain bootstrapping code, but once the TSR is installed, the space
; will be reused for keeping track of a few variables needed by the resident code.
; Here, we lay out those variables ahead of time.
segment .text
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
segment .text
%include 'debug.asm'
main:
call parse_command_line

mov al, [args_subcommand]
cmp al, SUBCOMMAND_PREVIEW
je .preview
mov ah, 0
int 21h

.preview:
segment .data
test_palette:
db 0,   0,  32
db 0,   21, 32
db 0,   42, 32
db 0,   63, 32
db 21,  0,  32
db 21,  21, 32
db 21,  42, 32
db 21,  63, 32
db 42,  0,  32
db 42,  21, 32
db 42,  42, 32
db 42,  63, 32
db 63,  0,  32
db 63,  21, 32
db 63,  42, 32
db 63,  63, 32
segment .text

mov cx, 16      ; Loop from 16 through 1
.pal_reg_loop:
mov ax, 1000h   ; Set palette register
mov bl, cl      ; Registers 0 through 15...
dec bl
mov bh, bl      ; ...get colors 0 through 15
int 10h
loop .pal_reg_loop
mov cx, 16
.pal_color_loop:
push cx
mov ax, cx
dec ax
mov bx, test_palette
add bx, ax      ; Colors 0 through 15
add bx, ax
add bx, ax
mov dh, [bx]        ; Red
mov ch, [bx + 1]    ; Green
mov cl, [bx + 2]    ; Blue
mov bx, ax
mov ax, 1010h   ; Set colors
int 10h
pop cx
dec cx
jnz .pal_color_loop
;loop .pal_color_loop

.exit:
mov ah, 0
int 21h

%include 'args.asm'

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
