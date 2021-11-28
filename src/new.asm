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
    push si

    ; General flow:
    ; - For each option on command line, add that item to the bundle in memory
    ; - Open file as new file for writing
    ; - Copy from memory to file

    ; Before we begin, make sure we have an output file
    cmp word [parsed_options.output], 0
    begin_if e
        die EXIT_BAD_ARGS, "Output file not provided"
    end_if

    ; Build our bundle
    call build_new_bundle
    mov si, cx

    ; Create new file and save handle in BX
    mov dx, [parsed_options.output]
    call dos_create_new_file
    begin_if c
        die EXIT_ERROR, "Couldn't create file"
    end_if
    mov bx, ax      ; BX = file handle

    ; Write program code to file
    mov ah, 40h
    ; TODO: Create a global file with memory layout defines?
    mov dx, 100h                    ; End of PSP
    mov cx, start_of_bundle - 100h  ; Copy program code up to bundle
    int 21h
    ; TODO: It would be slightly more correct to check AX == CX as well
    begin_if c
        die EXIT_ERROR, "Couldn't write to file"
    end_if

    ; Write bundle data to file
    mov ah, 40h
    mov dx, global_buffer   ; DX = start of bundle to write
    mov cx, si              ; CX = size of bundle
    int 21h
    begin_if c
        ; TODO: Combine error messages/move this to a helper function
        die EXIT_ERROR, "Couldn't write to file"
    end_if

    ; Close file
    call dos_close_file
    begin_if c
        die EXIT_ERROR, "Couldn't close file"
    end_if

    pop si
    pop bx
    ret


;-------------------------------------------------------------------------------
; Internal helpers
;-------------------------------------------------------------------------------
section .text

; Build a new bundle in global_buffer based on the parsed command-line args.
;
; Returns CX = size of the bundle in bytes
build_new_bundle:
    push bx
    push di
    push si

    mov di, global_buffer

    mov dx, [parsed_options.palette]
    cmp dx, 0
    begin_if ne
        ; TODO: Make a proper string-copy routine
        mov cx, [bundle_keys.palette]           ; CX = size
        mov [di], cx                            ; Write string header
        push di
        add di, 2                               ; DI = contents of string
        lea si, [bundle_keys.palette + 2]       ; SI = "PALETTE" raw bytes
        rep movsb
        pop di
        next_wstring di

        ; Open palette file
        mov dx, [parsed_options.palette]
        call dos_open_existing_file
        begin_if c
            mov dx, [parsed_options.palette]
            die EXIT_ERROR, "Couldn't open ", dx
        end_if
        mov bx, ax  ; BX = handle

        ; Read palette data
        ; TODO: helper that reads up to a certain number of bytes as a wstring
        mov ah, 3fh
        mov cx, 48 + 1
        lea dx, [di + 2]
        int 21h
        begin_if c
            die EXIT_ERROR, "Error reading palette"
        end_if
        mov [di], ax        ; Write length header

        ; Check palette size
        ; TODO: Have a central "validate this wstring"
        cmp ax, 48
        begin_if ne
            die EXIT_BAD_ARGS, "Invalid palette file"
        end_if

        ; Close file handle BX
        call dos_close_file

        next_wstring di
    end_if

    ; Terminate wstring list
    mov word [di], 0

    lea cx, [di + 2]        ; CX = end of buffer - start of buffer
    sub cx, global_buffer

    pop si
    pop di
    pop bx
    ret
