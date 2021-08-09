;; Code for parsing command-line arguments
%include 'string.asm'

;==============================================================================
; Consts
;------------------------------------------------------------------------------

; The command-line string in the PSP.
; This is initially a single bstring at program start, but
; tokenize_args_in_place converts it to a list of bstrings.
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
    db_bstring %1
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
    db 0    ; end of list


; Helper for simultaneously declaring a list of variable-length bstrings in
; initialized memory with correspondingly-labeled array elements in BSS.
; This ensures that the two collections are the same length and the exact same
; order, allowing the arg parser to iterate over both in lockstep.
%macro db_option 4
    %define %%array %1
    %define %%size  %2
    %define %%label %3
    %define %%str   %4

    %ifndef %[%%array]_BYTES
        %assign %[%%array]_BYTES 0
    %endif
    .%[%%label]:            db_bstring %%str
    %[%%array].%[%%label]   equ %%array + %[%%array]_BYTES
    %assign %[%%array]_BYTES %[%%array]_BYTES + %%size
%endmacro


; Define a list of all possible boolean flags, along with an array of
; booleans in BSS so we can track which options are enabled.
%macro db_optbool 2
    db_option boolean_args, 1, %1, %2
%endmacro
boolean_options:
    db_optbool nine_dot,    "/9"    ; font width = 9 pixels
    ; TODO: is there any need for disabling Line Graphics mode?
    db_optbool help,        "/?"    ; help
    db_optbool intensity,   "/i"    ; high-intensity backgrounds (no blinking)
    db 0    ; end of list


; Define a list of all possible string options, along with an array of
; bstring pointers in BSS so we can track which options are enabled.
%macro db_optstr 2
    db_option string_args, 2, %1, %2
%endmacro
string_options:
    db_optstr font,             "/f"    ; font file
    db_optstr secondary_font,   "/f2"   ; secondary font file (multi-charset)
    db_optstr init_memory,      "/m"    ; initialize memory (e.g., /m=0)
    db_optstr output,           "/o"    ; write to output file
    db_optstr palette,          "/p"    ; palette file
    db 0    ; end of list


;==============================================================================
; Parsed data
;------------------------------------------------------------------------------
section .bss

; Pointer to a bstring from the subcommands list, e.g., subcommands.install
subcommand_arg:
    resw 1

; Array of one-byte booleans, corresponding to elements of boolean_options.
; Each one has a corresponding label, e.g., "/?" will set boolean_args.help.
boolean_args:
    resb boolean_args_BYTES

; Array of bstring pointers, corresponding to elements of string_options.
; As before, each one has a label, e.g., "/f blah" will set string_args.font
; to point to "blah". If option is not present, the pointer will be 0/null.
string_args:
    resb string_args_BYTES


;==============================
; Subroutines
;------------------------------
section .text
%include "debug.asm"

;-------------------------------------------------------------------------------
; Read command line flags and initialize status variables accordingly.
;
; This is the main subroutine for parsing the command line, from start to
; end. It takes no parameters and returns nothing: it just mutates the global
; variables to match what the command line args specify.
;-------------------------------------------------------------------------------
parse_command_line:
    push si

    call tokenize_args_in_place
    mov si, args_list
    call try_parse_subcommand

    ; TODO: Parsing for options

    pop si
    ret


;-------------------------------------------------------------------------------
; Tries to parse the bstring in SI as a subcommand.
;
; If SI is a valid subcommand, advances SI to point to the next bstring.
; Otherwise, SI is left unchanged and subcommands.preview is set as a default.
;-------------------------------------------------------------------------------
try_parse_subcommand:
    push di

    ; Loop DI over all possible subcommands, comparing each one to SI
    mov di, subcommands
    .loop:
        cmp [di], byte 0            ; Break if we run out of subcommands
        je .break

        ; TODO: Maybe add an iprefix_bstring function to string.asm?
        call icmp_bstring           ; If the strings match...
        je .finish
        call is_short_subcommand    ; ...or if SI is an abbreviation of DI,
        je .finish                  ; then we've found our subcommand.

        next_bstring di             ; Otherwise, advance DI to the next one.
        jmp .loop
    .break:

    ; If we make it all the way through the loop without finding a match,
    ; set "preview" as our default.
    mov di, subcommands.preview

    .finish:
    mov [subcommand_arg], di
    pop di
    ret


;-------------------------------------------------------------------------------
; Returns whether SI is a one-character abbreviation of the bstring in DI.
;
; Examples: "i" or "I" would match "install", but "x" or "inst" would not.
; Returns ZF = 0 if there's a match, nonzero otherwise.
;-------------------------------------------------------------------------------
is_short_subcommand:
    cmp byte [si], 1            ; Is the input string one character long?
    jne .ret
    mov al, [si+1]              ; Get the only character of SI
    call tolower_accumulator
    mov ah, al
    mov al, [di+1]              ; Get first character of DI
    call tolower_accumulator
    cmp ah, al                  ; Do a case-insensitive comparison
    .ret:
    ret


;-------------------------------------------------------------------------------
; Convert standard PSP argument string into a list of bstrings, in place.
;-------------------------------------------------------------------------------
tokenize_args_in_place:
    push bx
    push di
    push si

    ; Set up all our pointers
    mov si, args_list   ; SI = pointer to copy data from
    inc si              ;   (skipping the length header)
    mov di, args_list   ; DI = destination for resulting bstring list
    xor bx, bx          ; BX = pointer to last character of PSP string,
    mov bl, [args_list] ;   used for bounds checking
    add bx, args_list

    ; Copy all tokens
    .loop:
        call fast_forward_to_token  ; Advance SI to point to next token.
        cmp ax, 1                   ; If we run out of tokens, break.
        jne .break
        call copy_token_to_bstring  ; Otherwise, copy the token to DI.
    .break:

    mov [di], byte 0    ; Terminate list with a zero-length bstring.

    pop si
    pop di
    pop bx
    ret


;-------------------------------------------------------------------------------
; Advances SI to point to the start of the next token in the PSP string.
;
; For bounds checking, takes BX = last character of PSP string.
; Returns AX = 1 on success, 0 on end of PSP string.
;-------------------------------------------------------------------------------
fast_forward_to_token:
    .loop:
        cmp si, bx              ; Make sure we're still in bounds
        ja .end_of_string
        lodsb                   ; AL = next character
        call is_token_separator ; ZF = is this character a separator?
        je .loop                ;   If so, keep looking.

    mov ax, 1   ; Return success
    dec si      ; SI = first character of token (undo lodsb's last increment)
    ret

    .end_of_string:
    xor ax, ax
    ret


;-------------------------------------------------------------------------------
; Copy token characters from SI into a bstring at DI.
;
; For bounds checking, takes BX = last character of PSP string.
; Assumes SI already points to the first character of a token.
; Advances SI to point to the byte immediately following the copied data,
; and likewise for DI.
;-------------------------------------------------------------------------------
copy_token_to_bstring:
    inc di  ; Leave a byte to write the token's length

    ; Copy token characters
    xor cx, cx                  ; CX = number of characters copied
    .loop:
        cmp si, bx              ; Break if we're out of bounds
        ja .break
        lodsb                   ; Read character
        call is_token_separator ; Break if we hit a token separator
        jz .break
        stosb                   ; Write character and increment count
        inc cx
        jmp .loop
    .break:

    sub di, cx          ; Temporarily set DI = pointer to first character
    mov [di - 1], cl    ; Write length header
    add di, cx          ; Restore DI
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
is_token_separator:
    cmp al, ' ' ; Is it an ASCII control character or a space?
    jle .true
    cmp al, '=' ; Is it a '='?
    ret
    .true:
    cmp al, al
    ret
