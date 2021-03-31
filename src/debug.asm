%ifndef DEBUG_ASM
%define DEBUG_ASM
jmp hop_over_debug_blob

%macro describe_byte 2
pusha
mov bl, %2
mov ah, 09h
mov dx, %%text
int 21h
mov dl, bl
call put_hex_byte
mov ah, 09h
mov dx, newline
int 21h
popa
jmp %%skip
%%text:
db %1
db '$'
%%skip:
%endmacro

; Prints DX in hex
put_hex_word:
pusha
call put_hex_byte
shr dx, 8
call put_hex_byte
popa
ret


; Prints DL in hex
put_hex_byte:
pusha
mov cx, dx ; Copy data to CX

mov bl, cl
shr bl, 4
call .put_nybble
mov bl, cl
call .put_nybble

mov ah, 02h ; Space
mov dl, 32
int 21h

popa    ; return
ret

.put_nybble:
and bx, 000Fh
mov dl, [bx + hex_chars]
mov ah, 02h
int 21h
ret


hex_chars: db '0123456789ABCDEF'
newline: db 13, 10, '$'

hop_over_debug_blob:
%endif
