; Functionality for creating new TSRs
%include 'system.asm'

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
