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
EXIT_ERROR      equ 1   ; Generic error, in spite of valid user input
EXIT_BAD_ARGS   equ 2   ; Invalid user input
EXIT_BAD_BUNDLE equ 3   ; Bundled palette/font/etc are invalid
EXIT_BAD_CODE   equ 4   ; The .COM file itself is damaged

;==============================================================================
; Program start
;------------------------------------------------------------------------------
section .text

jmp main

%include 'args.asm'
%include 'bundle.asm'
%include 'create.asm'
%include 'help.asm'
%include 'install.asm'
%include 'macros.asm'
%include 'print.asm'
%include 'video.asm'

main:
    call init_bss

    ; Parse/validate the data bundle at the end of the .COM file
    call parse_bundled_data
    cmp ax, 1
    je .bundle_ok
    die EXIT_BAD_BUNDLE, "Bundled data is corrupt"
    .bundle_ok:

    ; Parse/validate our command-line arguments
    call parse_command_line

    ; If the help flag is passed, suppress normal behavior and show help
    cmp byte [parsed_flags.help], 0
    begin_if ne
        jmp show_help
    end_if

    ; Switch based on the parsed subcommand
    mov ax, [subcommand_arg]
    cmp ax, subcommands.install
    begin_if e
        jmp install_tsr
    else
    cmp ax, subcommands.uninstall
    if e
        call uninstall_tsr
    else
    cmp ax, subcommands.reset
    if e
        call reset_video
    else
    cmp ax, subcommands.new
    if e
        call create_new_tsr
    else
        ; Default if no subcommand specified
        call preview_mode
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
