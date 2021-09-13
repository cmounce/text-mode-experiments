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
    call parse_bundled_data
    cmp ax, 1
    je .bundle_ok
    println_literal "bundled data is corrupt"
    jmp .exit
    .bundle_ok:

    call parse_command_line
    print_literal "Subcommand: "
    mov bx, [subcommand_arg]
    call print_bstring
    print_literal `\r\n`

    mov ax, [subcommand_arg]
    cmp ax, subcommands.preview
    je .preview
    cmp ax, subcommands.install
    je .install
    cmp ax, subcommands.uninstall
    je .uninstall
    cmp ax, subcommands.reset
    je .reset
    jmp .exit

    .preview:
    call preview_mode
    jmp .exit

    .install:
    call scan_multiplex_ids
    cmp al, 0
    je .install_fail
    push ax                     ; Save multiplex ID
    call preview_mode
    pop ax
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
    call reset_video
    jmp .exit
    .uninstall_not_found:
    println_literal "TSR not in memory"
    jmp .exit
    .uninstall_failed:
    println_literal "uninstall failed"
    jmp .exit

    .reset:
    call reset_video
    jmp .exit

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
