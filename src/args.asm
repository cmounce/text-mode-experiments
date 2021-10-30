;; Code for parsing command-line arguments
%include 'macros.asm'
%include 'print.asm'
%include 'string.asm'

;==============================================================================
; Consts
;------------------------------------------------------------------------------

; The command-line string in the PSP.
; TODO: Rename to something more accurate.
args_list           equ 80h


;===============================================================================
; Strings
;-------------------------------------------------------------------------------
section .data

; Define a list of all the subcommand strings, with a named label for each one.
; These labels are used like enum values, allowing storage in registers and
; convenient comparisons: e.g., does AX == subcommands.install?
%macro db_subcommand 1
    %deftok %%t %1
    .%[%%t]:
    db_wstring %1
%endmacro
subcommands:
    ; Each subcommand begins with a different letter, in order to allow the
    ; user to make single-character abbreviations (e.g., "foo i" to install).
    db_subcommand "about"
    db_subcommand "install"
    db_subcommand "new"
    db_subcommand "preview"
    db_subcommand "reset"
    db_subcommand "uninstall"
    dw 0    ; end of list


;==============================================================================
; Parsed data
;------------------------------------------------------------------------------
section .bss

; String list representing the tokenized argument string.
; How much space do we need? The arg string could be up to 127 bytes long,
; which means in the worst case we could have 64 one-character tokens (i.e.,
; every other byte is a delimiter). Each of those tokens would take up 3 bytes
; (2 byte header, 1 byte content), and the list itself would be terminated by
; an empty string (2 byte header, 0 bytes content).
MAX_TOKENS equ (127 + 1)/2
_arg_tokens:
    resb (MAX_TOKENS * 3) + 2

; Pointer to a wstring from the subcommands list, e.g., subcommands.install
subcommand_arg:
    resw 1


;==============================
; Subroutines
;------------------------------
section .text

;-------------------------------------------------------------------------------
; Read command line flags and initialize status variables accordingly.
;
; This is the main subroutine for parsing the command line, from start to
; end. It takes no parameters and returns nothing: it just mutates the global
; variables to match what the command line args specify.
;-------------------------------------------------------------------------------
parse_command_line:
    push si

    ; Set up SI = start of token list
    call _tokenize_args         ; _arg_tokens = string list of tokens
    mov si, _arg_tokens         ; SI = first token

    ; Parse first word as a subcommand, if it exists
    call _parse_subcommand
    cmp word [subcommand_arg], 0
    begin_if e
        ; No subcommand present: default to subcommand.preview
        mov word [subcommand_arg], subcommands.preview
    end_if

    ; Assert that we've parsed everything
    cmp word [si], 0
    begin_if ne
        die EXIT_BAD_ARGS, "Unexpected extra args"
    end_if

    ; TODO: Parsing for options
    ; TODO: Return a bool for arg validation?

    pop si
    ret

;-------------------------------------------------------------------------------
; Tries to consume the token in SI as a subcommand.
;
; On success: sets subcommand_arg and consumes the token, advancing SI.
; On failure: leaves subcommand_arg untouched (should be zero).
;-------------------------------------------------------------------------------
_parse_subcommand:
    push di

    mov di, subcommands             ; Loop DI = each possible subcommand
    .for_each:
        cmp word [di], 0            ; Break if we run out of subcommands
        je .not_found

        call icmp_wstring           ; If SI == DI, this is a full subcommand.
        je .found
        call _is_short_subcommand   ; If the first letters of SI and DI match,
        je .found                   ; this is an abbreviated subcommand.

        next_wstring di             ; Otherwise, advance DI to the next one.
        jmp .for_each

    .found:
    mov [subcommand_arg], di        ; SI is a valid subcommand. Record it and
    next_wstring si                 ; advance to the next token.

    .not_found:
    pop di
    ret


;-------------------------------------------------------------------------------
; Returns whether SI is a one-character abbreviation of the string in DI.
;
; Examples: "i" or "I" would match "install", but "x" or "inst" would not.
; Returns ZF = 0 if there's a match, nonzero otherwise.
;-------------------------------------------------------------------------------
_is_short_subcommand:
    cmp word [si], 1            ; Is the input string one character long?
    jne .ret
    mov al, [si+2]              ; Get the only character of SI
    call tolower_accumulator
    mov ah, al
    mov al, [di+2]              ; Get first character of DI
    call tolower_accumulator
    cmp ah, al                  ; Do a case-insensitive comparison
    .ret:
    ret


;-------------------------------------------------------------------------------
; Tokenize the PSP argument string and store the result in _arg_tokens.
;-------------------------------------------------------------------------------
_tokenize_args:
    push bx
    push di
    push si

    ; Set up all our pointers
    mov si, args_list   ; SI = pointer to copy data from
    inc si              ;   (skipping the length header)
    mov di, _arg_tokens ; DI = destination for resulting string list
    xor bx, bx          ; BX = pointer to last character of PSP string,
    mov bl, [args_list] ;   used for bounds checking
    add bx, args_list

    ; Loop over each char in the arg string
    .for_each:
        ; Make sure SI is still within bounds
        cmp si, bx
        ja .break

        lodsb                       ; AL = next character from SI
        call _is_token_separator
        begin_if ne
            ; AL is part of a token: append it to the current string in DI.
            ; Note that lists are terminated by an empty string, so DI should
            ; always point to a valid string.
            call concat_byte_wstring
        else
            ; AL is not part of a token.
            ; Does DI point to an in-progress token?
            cmp word [di], 0
        if ne
            ; DI points to an in-progress token, which we need to wrap up.
            next_wstring di     ; Advance DI past the latest token on the list
            mov word [di], 0    ; Write empty string/list terminator to DI
        end_if

        jmp .for_each
    .break:

    ; Terminate the list if it isn't terminated already
    cmp word [di], 0
    begin_if ne
        next_wstring di     ; Advance DI past the last token
        mov word [di], 0    ; Write empty string/list terminator to DI
    end_if

    pop si
    pop di
    pop bx
    ret


;-------------------------------------------------------------------------------
; Returns ZF=1 if the character in AL is a token separator.
;
; Token separators are spaces, tabs, and any other ASCII control characters.
; Additionally, '=' is counted as a separator character: this is so that
; arguments like "/foo=bar" are separated into two tokens.
;
; Clobbers no registers!
;-------------------------------------------------------------------------------
_is_token_separator:
    cmp al, ' ' ; Is it an ASCII control character or a space?
    jbe .true
    cmp al, '=' ; Is it a '='?
    ret
    .true:
    cmp al, al
    ret
