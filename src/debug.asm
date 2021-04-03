%ifndef DEBUG_ASM
%define DEBUG_ASM
jmp hop_over_debug_blob

%macro inspect 1-*
pushf
pusha
%rep %0
    %rotate -1
    %ifid %1 ; Only push registers onto the stack
        %defstr %%name %1
        %substr %%char %%name 2
        %assign %%char (%%char | 20h)
        %if %%char == 'l' || %%char == 'h'
            %substr %%char %%name 1
            %strcat %%name %%char, "x" ; We can only push full registers, not half-regs
        %endif
        %deftok %%id %%name
        push %%id
    %endif
%endrep
%assign %%i 1
%rep %0
    ; Print space if between parameters
    %if %%i > 1
        mov ah, 02h
        mov dl, ' '
        int 21h
    %endif

    ; Print the next parameter that we were given
    %ifstr %1
        %push
        jmp %$skip
        %$text:
        db %1
        db '$'
        %$skip:
        mov ah, 09h
        mov dx, %$text
        int 21h
        %pop
    %elifid %1
        %defstr %%id %1
        %substr %%char %%id 2
        %assign %%char (%%char | 20h)
        %if %%char == 'l' || %%char == 'h'
            pop dx
            %if %%char == 'h'
                shr dx, 8
            %endif
            call put_hex_byte
        %else
            pop dx
            call put_hex_word
        %endif
    %else
        mov dx, %1
        call put_hex_word
    %endif

    ; Advance to the next item
    %assign %%i %%i+1
    %rotate 1
%endrep

; Finish with a newline
mov ah, 09h
mov dx, newline
int 21h

popa
popf
%endmacro

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
