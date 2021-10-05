;; ZZT All-Purpose TSR (rewrite)
org 100h                ; Adjust addresses for DOS .COM file
cpu 286

section .text                           ; Non-resident code (parameter parsing, etc)
section .data   follows=.text           ; Non-resident data (help text, etc)
section .append follows=.data           ; Reserve space for palette/font appended to .COM file
section .bss    start=20*1024           ; Non-initialized data, as usual

; Define a buffer that begins just after .bss and stretches until the stack.
global_buffer equ section..bss.start + bss_size

; - 0K to 3K-ish: Program code
; - 3K-ish to 20K: Space for appended data
; - 20K to 60K: BSS; Buffer space for assembling installable
; - 60K to 64K: Stack space

; Define some exit codes in rough order of severity
EXIT_OK         equ 0
EXIT_BAD_ARGS   equ 1
EXIT_BAD_BUNDLE equ 2
EXIT_BAD_CODE   equ 3

;==============================================================================
; Program start
;------------------------------------------------------------------------------
section .text
jmp main

%include 'args.asm'
%include 'bundle.asm'
%include 'debug.asm'
%include 'install.asm'
%include 'print.asm'
%include 'video.asm'

main:
    call init_bss

    ; Parse/validate the data bundle at the end of the .COM file
    call parse_bundled_data
    cmp ax, 1
    je .bundle_ok
    die EXIT_BAD_BUNDLE, "bundled data is corrupt"
    .bundle_ok:

    ; Parse/validate our command-line arguments
    call parse_command_line

    ; Switch based on the parsed subcommand
    mov ax, [subcommand_arg]
    cmp ax, subcommands.preview
    begin_if e
        call preview_mode
    else
    cmp ax, subcommands.install
    if e
        call scan_multiplex_ids
        cmp al, 0
        je .install_fail
        push ax                     ; Save multiplex ID
        call preview_mode
        pop ax
        call install_and_terminate
        .install_fail:
        inspect "install failed:", al, cl, dx
    else
    cmp ax, subcommands.uninstall
    if e
        call scan_multiplex_ids
        cmp dx, 0
        je .uninstall_not_found
        call uninstall_tsr
        cmp ax, 0
        je .uninstall_failed
        call reset_video
        jmp .exit
        .uninstall_not_found:
        println_literal "TSR not in memory"
        jmp .exit
        .uninstall_failed:
        println_literal "uninstall failed"
    else
    cmp ax, subcommands.reset
    if e
        call reset_video
    end_if

    .exit:
    mov ah, 0
    int 21h


;-------------------------------------------------------------------------------
; Initializes BSS section to zeros
;-------------------------------------------------------------------------------
init_bss:
    mov cx, bss_size
    mov di, section..bss.start
    mov al, 0
    rep stosb
    ret


; Measure the size of .bss.
; In order for this to include everything, nothing can be added to .bss after
; this point, which is why we compute this at the end of main.asm.
section .bss
bss_size equ $ - $$
