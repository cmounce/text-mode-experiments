; Functionality for creating new TSRs

;-------------------------------------------------------------------------------
; Consts
;-------------------------------------------------------------------------------
section .data

bundle_terminator: dw 0


;-------------------------------------------------------------------------------
; Code
;-------------------------------------------------------------------------------
section .text

; Write a new TSR to a file.
create_new_tsr:
    push bx

    ; General flow:
    ; - For each option on command line, add that item to the bundle in memory
    ; - Open file as new file for writing
    ; - Copy from memory to file

    ; Get DX = file path to create
    mov dx, [parsed_options.output]
    cmp dx, 0
    begin_if e
        die EXIT_BAD_ARGS, "Output file not provided"
    end_if

    ; Create new file and save handle in BX
    call dos_create_new_file
    begin_if c
        die EXIT_ERROR, "Couldn't create file"
    end_if
    mov bx, ax      ; BX = file handle

    ; Write to file
    mov ah, 40h
    mov dx, 100h                    ; End of PSP
    mov cx, start_of_bundle - 100h  ; Copy program code up to bundle
    int 21h
    begin_if c
        die EXIT_ERROR, "Couldn't write to file"
    end_if

    ; Terminate bundle
    mov ah, 40h
    mov dx, bundle_terminator
    mov cx, 2
    int 21h
    begin_if c
        die EXIT_ERROR, "Couldn't write to file"
    end_if

    ; Close file
    mov ah, 3eh
    int 21h
    begin_if c
        die EXIT_ERROR, "Couldn't close file"
    end_if

    pop bx
    ret


; Create a new file and return the handle.
;
; DX = File path, as a wstring
; On success, returns AX = file handle
; On failure, sets CF and returns AX = error code
dos_create_new_file:
    push bp
    push di
    push si
    mov bp, sp

    ; Write zstring to DI = a buffer on the stack
    mov si, dx      ; SI = wstring path
    sub sp, [si]    ; Allocate space on stack for string contents
    dec sp          ; ...and a null terminator.
    mov di, sp      ; DI = buffer
    call copy_as_asciiz

    ; Call DOS with the zstring
    mov ah, 5bh     ; Create new file
    xor cx, cx      ; CX = attribute bits
    mov dx, di      ; DX = asciiz path
    int 21h

    ; Clean up, leaving AX and CF untouched
    mov sp, bp
    pop si
    pop di
    pop bp
    ret


; Convert the given wstring to asciiz and write it to a buffer.
;
; SI = address of wstring to copy
; DI = address of buffer to write asciiz string
copy_as_asciiz:
    push di
    push si

    ; Copy string to buffer
    mov cx, ds          ; Make sure ES = DS
    mov es, cx
    mov cx, [si]        ; CX = number of bytes in the string
    add si, 2           ; SI = contents of wstring (skip the header)
    rep movsb

    ; Write null terminator
    mov byte [di], 0

    pop si
    pop di
    ret
