;; ZZT All-Purpose TSR (rewrite)
%define VERSION "2.0.0-rewrite-in-progress"
org 100h                ; Adjust addresses for DOS .COM file

segment .text                           ; Non-resident code (parameter parsing, etc)
segment .data   follows=.text           ; Non-resident data (help text, etc)
segment .append follows=.data   nobits  ; Reserve space for palette/font appended to .COM file
segment .bss    follows=.append         ; Non-initialized data, as usual

; Allow up to 20k of data to be appended to the .COM file
segment .append
resb 20*1024

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
cmp al, SUBCOMMAND_INSTALL
je .install
jmp .exit

.preview:
mov dx, test_palette
call set_palette
jmp .exit

.install:
call scan_multiplex_ids
cmp al, 0
je .install_fail
call install_and_terminate
.install_fail:
inspect "install failed:", al, cl, dx

.exit:
mov ah, 0
int 21h

%include 'args.asm'
%include 'tsr.asm'
%include 'video.asm'
