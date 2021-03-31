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
mov di, cli_subcommand
rep movsb di, 0

; Parse subcommand
; CL=number of bytes remaining
; SI=offset into string
mov cl, [80h]
mov si, 81h
call ltrim
call parse_subcommand

; Advance SI/CL until non-whitespace or end-of-string.
; Clobbers: AL
ltrim:
.loop:
cmp cl, 0
je .break
mov al, [si]
cmp al, ' '
je .next_char
cmp al, '\t'
je .next_char
cmp al, '\r'
je .next_char
cmp al, '\n'
je .next_char
jmp .break
.next_char:
dec cl
inc si
jmp .loop
.break:
ret
; TODO
parse_subcommand:
ret
;
try_consume_prefix:
; Compares AL with [SI], case-insensitively
; Sets the same flags as "cmp al, [si]"
; TODO: Is this the right approach?
; If this were Python, I would parse into a list of whitespace-stripped strings,
; because I don't actually want to consume a prefix: I want to consume a token.


mov ah, 0
int 21h
