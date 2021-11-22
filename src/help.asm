;------------------------------------------------------------------------------
; Messages
;------------------------------------------------------------------------------
top_level_help:
begin_wstring
    db `All-Purpose TSR -- prototype\r\n`
    db `\r\n`
    db `Subcommands:\r\n`
    db `  install    Install TSR\r\n`
    db `  new        Create a new TSR\r\n`
    db `  preview    Preview effects of TSR without installing it\r\n`
    db `  reset      Clear screen and reset (undoes effects of preview)\r\n`
    db `  uninstall  Uninstall TSR\r\n`
    db `\r\n`
    db `First letter can also be used: FOO I and FOO INSTALL both work.\r\n`
end_wstring

install_help:
begin_wstring
    db `install: Install the TSR\r\n`
    db `\r\n`
    db `No options\r\n`
end_wstring


;------------------------------------------------------------------------------
; Code
;------------------------------------------------------------------------------

; Exits with a help message corresponding to the parsed subcommand
show_help:
    ; Set DX = default help message: top-level list of subcommands
    mov dx, top_level_help

    ; If we have a more specific help message, set it
    mov ax, [subcommand_arg]
    cmp ax, subcommands.install
    begin_if e
        mov dx, install_help
    end_if

    ; Print the message
    push dx
    call print_wstring

    ; Exit successfully
    mov ah, 0
    int 21h
