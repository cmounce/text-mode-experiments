;; ZZT All-Purpose TSR (rewrite)
%define VERSION "2.0.0-rewrite-in-progress"
org 100h                ; Adjust addresses for DOS .COM file

segment .text                           ; Non-resident code (parameter parsing, etc)
segment .data   follows=.text           ; Non-resident data (help text, etc)
segment .append follows=.data           ; Reserve space for palette/font appended to .COM file
segment .bss    start=20*1024           ; Non-initialized data, as usual

; - 0K to 1K-ish: Program code
; - 1K-ish to 20K: Space for appended data
; - 20K to 60K: BSS; Buffer space for assembling installable
; - 60K to 64K: Stack space

;
; Program start
;
segment .text
%include 'debug.asm'
main:
; TODO: initialize BSS centrally
call parse_bundled_data
cmp ax, 1
je .bundle_ok
inspect "bundled data is corrupt"
jmp .exit
.bundle_ok:

call parse_command_line

mov al, [args_subcommand]
cmp al, SUBCOMMAND_PREVIEW
je .preview
cmp al, SUBCOMMAND_INSTALL
je .install
cmp al, SUBCOMMAND_UNINSTALL
je .uninstall
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
jmp .exit

.uninstall:
call scan_multiplex_ids
cmp dx, 0
je .uninstall_not_found
call uninstall_tsr
cmp ax, 0
je .uninstall_failed
jmp .exit
.uninstall_not_found:
inspect "TSR not in memory"
jmp .exit
.uninstall_failed:
inspect "uninstall failed"
jmp .exit

.exit:
mov ah, 0
int 21h

%include 'args.asm'
%include 'bundle.asm'
%include 'tsr.asm'
%include 'video.asm'
