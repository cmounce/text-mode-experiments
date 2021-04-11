;; Code for parsing command-line arguments


;==============================================================================
; Constants
;------------------------------------------------------------------------------
; The actual command-line string in the PSP
arg_string.length   equ 80h
arg_string.data     equ 81h

; Enum for representing the subcommand
SUBCOMMAND_UNKNOWN      equ 0
SUBCOMMAND_PREVIEW      equ 1
SUBCOMMAND_INSTALL      equ 2
SUBCOMMAND_UNINSTALL    equ 3
SUBCOMMAND_RESET        equ 4
SUBCOMMAND_INFO         equ 5
SUBCOMMAND_NEW          equ 6

; Consts to represent the state of boolean options
FLAG_FALSE      equ 0   ; Flag not set
FLAG_TRUE       equ 1   ; Flag set
FLAG_FORBIDDEN  equ 80h ; A previous command-line option means this flag *must not* be set


;===============================================================================
; Strings
;-------------------------------------------------------------------------------
section .data
; Define a table of subcommands and their corresponding enum values.
; Usage: def_subcommand "foo" SUBCOMMAND_FOO
%macro def_subcommand 2
    %strlen %%n %1
    db %%n, %1  ; Store subcommand name as a Pascal string
    db %2       ; Subcommand's enum value immediately follows the string
%endmacro
subcommand_table:
def_subcommand "preview",   SUBCOMMAND_PREVIEW
def_subcommand "i",         SUBCOMMAND_INSTALL
def_subcommand "install",   SUBCOMMAND_INSTALL
def_subcommand "u",         SUBCOMMAND_UNINSTALL
def_subcommand "uninstall", SUBCOMMAND_UNINSTALL
def_subcommand "reset",     SUBCOMMAND_RESET
def_subcommand "info",      SUBCOMMAND_INFO
def_subcommand "new",       SUBCOMMAND_NEW
db 0    ; End of table


;==============================================================================
; Data structures
;------------------------------------------------------------------------------
segment .bss
parsed_args:
; Subcommand enum
args_subcommand: resb 1

; On/off flags
args_flags:
.help:          resb 1
.font:          resb 1
.palette:       resb 1
.blink_on:      resb 1
.blink_off:     resb 1
.memory_rand:   resb 1
.memory_zero:   resb 1

; Buffers for filenames
cli_font_filename:
.length:    resb 1
.bytes:     resb 12
cli_palette_filename:
.length:    resb 1
.bytes:     resb 12

parsed_args_size equ $-parsed_args


;==============================
; Subroutines
;------------------------------
segment .text
%include "debug.asm"

; The tokenization code in this section uses SI and CX to point to each token
; in the parsed command line. SI points to the first byte of the current token,
; and CX indicates the length of the token in bytes.
;
; Functions that take a token will use these registers to accept it, and in
; general, functions in this section will not clobber these two registers.

;-------------------------------------------------------------------------------
; Read command line flags and initialize status variables accordingly.
;
; This is the main subroutine for parsing the command line, from start to
; end. It takes no parameters and returns nothing: it just mutates the global
; variables to match what the command line args specify.
;-------------------------------------------------------------------------------
parse_command_line:
; Clear memory
mov cx, parsed_args_size
mov di, parsed_args
mov al, 0
rep stosb

; Parse the first token as an optional subcommand
call parse_first_token
call try_consume_subcommand
mov al, [args_subcommand]
inspect "Subcommand enum:", al

; Cycle through the remaining tokens
cmp cx, 0
je .ret
.loop:
call parse_next_token
cmp cx, 0
je .ret
inspect "Parsed token of length", cl
jmp .loop

; TODO: would it be better if there was a single consume_token command?
;   1. If it begins with a /, it tries to parse it as a flag
;       1b. If it's a flag that takes a parameter, parse a parameter as well
;   2. If it doesn't, it tries to parse it as a subcommand
; Advantage: It would always consume a token.

; TODO: How to handle errors? There are multiple:
;   - Invalid argument %s
;   - Flag %s requires a filename
; Maybe return an error enum? Include a string in SI/CX?
; Also TODO: Who should handle printing the error?
; Maybe we just return AL=status and SI/CX the relevant string

.ret:
ret


;-------------------------------------------------------------------------------
; Sets args_subcommand based on the token currently pointed to by SI/CX
;-------------------------------------------------------------------------------
try_consume_subcommand:
mov [args_subcommand], byte SUBCOMMAND_PREVIEW  ; Default subcommand if none is provided
cmp cx, 0               ; No token to read
je .ret
cmp [si], byte '/'      ; Token is a flag, not a subcommand
je .ret
; TODO: Would this be any more elegant with a different table structure?
push di
mov di, subcommand_table    ; Walk through every entry in subcommand_table,
.loop:                      ; looking for something that equals SI/CX
mov dh, 0
mov dl, [di]
cmp dx, 0                   ; We hit the end of the table
je .no_match
inc di                      ; DI/DX now point to the next string in the table
call icompare_str           ; If DI/DX == SI/CX, we found our subcommand
je .match
add di, dx                  ; DI/DX != SI/CX, so advance past the string
inc di                      ; and the enum at the end of the string
jmp .loop
.no_match:
mov [args_subcommand], byte SUBCOMMAND_UNKNOWN
jmp .restore
.match:
add di, dx                  ; Advance DI to point to enum that follows string
mov dl, [di]
mov [args_subcommand], dl
.restore:
pop di
call parse_next_token
.ret:
ret

;-------------------------------------------------------------------------------
; Compares strings in SI/CX and DI/DX, case-insensitively.
;
; Sets ZF=1 if equal, ZF=0 if not.
; Clobbers AX.
;-------------------------------------------------------------------------------
icompare_str:
cmp cx, dx      ; Return ZF=0 if lengths don't match.
jne .ret        ; The cmp sets ZF for us, so we can return right away.
push si
push di
.loop:          ; Loop CX times over chars
mov al, [si]    ; Read/advance SI pointer
inc si
call to_lower
mov ah, al
mov al, [di]    ; Read/advance DI pointer
inc di
call to_lower
cmp ah, al      ; Return ZF=0 if any pair of chars doesn't match.
jne .restore    ; Again, the cmp sets ZF for us.
loop .loop
; If we reach this point, all chars match, so the strings match.
; The loop instruction set CX to 0 (and thus ZF=1, which we return with).
.restore:
pop di
pop si
mov cx, dx      ; We've already verified the strings are the same length
.ret:
ret

;-------------------------------------------------------------------------------
; Makes character in AL lowercase.
; Clobbers no registers!
;-------------------------------------------------------------------------------
to_lower:
cmp al, 'A'
jl .ret
cmp al, 'Z'
jg .ret
add al, ('a' - 'A')
.ret:
ret

;-------------------------------------------------------------------------------
; Sets up SI/CX to point to the first token in the argument string.
;
; Returns CX=0 if there are no tokens.
;-------------------------------------------------------------------------------
parse_first_token:
mov cx, 1
mov si, arg_string.data - 1
call parse_next_token
ret

;-------------------------------------------------------------------------------
; Advances SI/CX to point to the next token in the argument string.
;
; Call with CX=0 to start parsing from the beginning.
; Call with SI/CX pointing to the previously-parsed token to get the next one.
;
; Returns CX=0 once the end of the string has been reached.
;
; Clobbers AX.
;-------------------------------------------------------------------------------
parse_next_token:
cmp cx, 0                           ; Make sure we have a previous token before continuing
je .ret

; Move SI to point to the first char following the previous token.
; We also repurpose CX within this function: CX = number of bytes remaining.
add si, cx                          ; Go to character following previous token
mov cx, arg_string.data
add cl, [arg_string.length]         ; CX = pointer to end of string
sub cx, si                          ; CX = number of remaining characters, including char pointed at by SI
jle .end_of_string

; Skip SI past any token-separating characters
.skip_loop:
mov al, [si]
call is_token_separator
jne .token_start
inc si                  ; Advance to next character
dec cx
jnz .skip_loop
.end_of_string:
mov cx, 0               ; We hit the end of the string
ret

; SI = the start of a token. Now find where the token ends.
.token_start:
push si
.count_loop:
inc si
dec cx
jz .count_break
mov al, [si]
call is_token_separator
je .count_break
jmp .count_loop
.count_break:

; We found both ends of the token! Calculate its size and return it
mov cx, si
pop si
sub cx, si
.ret:
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
