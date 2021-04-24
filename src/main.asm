;; ZZT All-Purpose TSR (rewrite)
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
jmp .exit

.preview:
call set_palette
jmp .exit

.exit:
mov ah, 0
int 21h

%include 'args.asm'
%include 'video.asm'
