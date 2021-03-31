;; ZZT All-Purpose TSR (rewrite)
org 100h                ; Adjust addresses for DOS .COM file

section .text                           ; Non-resident code (parameter parsing, etc)
section .data       follows=.text       ; Non-resident data (help text, etc)
section .resident   follows=.data       ; Resident code/data
section .bss        follows=.resident   ; Non-initialized data, as usual


; The first few bytes of the resident section play double duty.
; They initially contain bootstrapping code, but once the TSR is installed, the space
; will be reused for keeping track of a few variables needed by the resident code.
; Here, we lay out those variables ahead of time.
start_tsr_variables:
absolute start_tsr_variables

old_int_10h:    ; previous video interrupt
.segment:   resb 2
.offset:    resb 2

old_int_2fh:    ; TSR multiplex interrupt
.segment:   resb 2
.offset:    resb 2

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime)
tsr_id_num: resb 1

end_tsr_variables:
segment .text

; Parse command-line parameters
segment .bss
cli_params_start:
; Allocate a byte to hold a subcommand enum
SUBCOMMAND_UNKNOWN      equ 0
SUBCOMMAND_PREVIEW      equ 1
SUBCOMMAND_INSTALL      equ 2
SUBCOMMAND_UNINSTALL    equ 3
SUBCOMMAND_RESET        equ 4
SUBCOMMAND_INFO         equ 5
SUBCOMMAND_NEW          equ 6
cli_subcommand: resb 1
; Allocate a bunch of booleans for true/false type options
FLAG_FALSE      equ 0   ; Flag not set
FLAG_TRUE       equ 1   ; Flag set
FLAG_DISALLOWED equ 80h ; Flag not set, and it would be an error to set it,
                        ; e.g., a previously-set flag would conflict with it.
cli_flags:
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
cli_params_end:

; Start parsing
segment .text
; Clear memory
mov cx, cli_params_end - cli_params_start
mov di, cli_params_start
mov al, 0
rep stosb

%include 'debug.asm'

; Parse subcommand
; CL=number of bytes remaining
; SI=offset into string
mov cx, 0
mov si, arg_string_start_addr
debug_args:
call next_token
mov dx, si
describe_byte 'Value of SI after next_token() ', dl
describe_byte 'Value of CL after next_token() ', cl
cmp cx, 0
je .break
mov dl, cl
;call put_hex_byte
jmp debug_args
.break:

mov ah, 0
int 21h


parse_subcommand:
; TODO

; Takes SI/CX as a pointer/length to a token, and returns SI/CX pointing to the next token.
; Tokens are split on control-chars/whitespace and = (so that /foo bar and /foo=bar act the same).
; Once end of string has been reached, returns CX=0.
; Clobbers AX.
next_token:
arg_string_length_addr equ 80h
arg_string_start_addr equ 81h
add si, cx                              ; Go to character following token
mov cx, arg_string_start_addr
add cl, byte [arg_string_length_addr]
sub cx, si                              ; Calculate CX=number of remaining characters, including char pointed at by SI
jle .end_of_string

.skip_loop:             ; Fast-forward past any token-separating characters.
mov al, [si]
call is_token_separator
jne .skip_break
inc si                  ; Advance to next character
dec cx
jz .end_of_string       ; If we run out of characters, quit our token search
jmp .skip_loop
.skip_break:

push si
.count_loop:            ; Advance pointer past all token characters
inc si
dec cx
jz .count_break
mov al, [si]
call is_token_separator
je .count_break
jmp .count_loop
.count_break:

; We found a token! Calculate its size and return it
mov cx, si
pop si
sub cx, si
ret

; We ran out of characters without finding a token
.end_of_string:
mov cx, 0
ret

; Returns ZF=1 if the character in AL is a token separator.
; Clobbers no registers!
is_token_separator:
cmp al, ' ' ; Consider space, tab, etc. to be separator characters. For simplicity, we lump all control characters together.
jle .true   ; Shouldn't really matter, but if you separate your args with vertical tabs... more power to you, I guess.
cmp al, '=' ; Also consider '=' to be a separator.
ret
.true:
cmp al, al
ret
