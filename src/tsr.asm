;; Functions and definitions for TSR-specific stuff

;===============================================================================
; Constants
;-------------------------------------------------------------------------------
; Create a 64-bit identifier by hashing this ID string
%strcat TSR_ID_STRING "Quantum's all-purpose TSR ", VERSION

; Compile-time 32-bit universal hash function
; Usage: univ32_hash DEST_VAR, VARIANT, "string to be hashed"
%macro univ32_hash 3
    %strlen %%num_bytes %3
    %assign %%result 0
    %assign %%i 0
    %rep %%num_bytes
        %assign %%i %%i+1
        %substr %%byte %3 %%i
        %assign %%result (%%result * %2 + %%byte) % 0x10000000F
    %endrep
    %assign %1 %%result & 0xFFFFFFFF
%endmacro

; 64-bit hash functions are difficult because NASM complains about integer
; overflow in macros. So instead, we hash the same string twice, but with
; two different variants of a 32-bit hash function.
univ32_hash TSR_HASH_LO, 40364,    TSR_ID_STRING
univ32_hash TSR_HASH_HI, 1991,     TSR_ID_STRING

segment .data
; Install/uninstall routines use this hash to identify our TSR in memory
tsr_id_hash_value:
dd TSR_HASH_LO, TSR_HASH_HI
.end_of_contents:

;===============================================================================
; Resident header: statically-allocated variables
;-------------------------------------------------------------------------------
; When processing an interrupt, we reuse the PSP's command-line space as a
; miniature stack. The last word of the PSP holds the old stack pointer,
; and the 126 bytes preceding it are our temporary stack space.
absolute 100h - 2
old_stack_pointer:

; The first few bytes following the PSP play double duty.
; They initially contain non-resident code, but after TSR installation,
; the space will be reused for keeping track of a few variables needed
; by the resident code.
absolute 100h

; Contains hash value to identify the resident memory as our TSR
tsr_nametag:  resb 8

old_int_10h:    ; previous video interrupt
    .offset:    resb 2
    .segment:   resb 2

old_int_2fh:    ; TSR multiplex interrupt
    .offset:    resb 2
    .segment:   resb 2

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime)
tsr_multiplex:
    .id:        resb 1
    .interrupt: resb 1

palette_offset: resb 2  ; Location of palette data in resident memory

; End of statically-allocated data; generated resident code follows.
tsr_code_start:

;===============================================================================
; Resident code and code fragments
;-------------------------------------------------------------------------------
segment .text

;-------------------------------------------------------------------------------
; Checks to see if our TSR is already resident in memory.
;
; Returns:
; - AL = an available multiplex ID, or 0 if TSR cannot be installed
; - CL = the multiplex ID of our TSR, or 0 if it is not installed
; - DX = code segment of our TSR, or 0 if it is not installed
;-------------------------------------------------------------------------------
scan_multiplex_ids:
    .min_id equ 0C0h
    .max_id equ 0FFh

    ; When we call int 2Fh, other TSRs might clobber arbitrary registers, so we
    ; save a bunch of them beforehand. This is basically every register except:
    ; - Caller-saved registers: AX, CX, DX are acceptable to clobber
    ; - Registers considered safe after int 2Fh: CS:IP, SS:SP
    push bx
    push bp
    push si
    push di
    push ds
    push es

    mov bp, sp          ; Allocate a stack variable so that if we see an
    push byte 0         ; available multiplex ID, we can store it here

    mov al, 0           ; AL = 0: TSR installation check
    mov ah, .max_id     ; AH: Multiplex ID to check
    .scan_loop:
        ; Check multiplex ID
        push ax
        xor bx, bx  ; Ralf Brown recommends clearing these
        xor cx, cx
        xor dx, dx
        int 2Fh
        cmp al, 0       ; AL = 0 means that AL was untouched;
        pop ax          ; nothing lives at this multiplex ID
        je .available

        ; TSR exists at this multiplex ID: check to see if it's ours
        mov si, cs                  ; Set up DS:SI = expected name.
        mov ds, si                  ; We restore DS from CS because the TSR at
        mov si, tsr_id_hash_value   ; this multiplex might have overwritten it.
        mov cx, tsr_id_hash_value.end_of_contents - tsr_id_hash_value
        rep cmpsb       ; If this is our TSR, calling the multiplex handler
        jne .continue   ; will have already set ES:DI to point to its nametag.

        ; Nametag matches: AH = multiplex ID of our TSR
        mov ch, 0
        mov cl, ah  ; CL = multiplex ID
        xor ax, ax  ; AL = 0: duplicate installation not allowed
        mov dx, es  ; DX = code segment
        jmp .finish

        ; AH = an available multiplex ID (no TSR exists here)
        .available:
        cmp [bp-1], byte 0  ; Only store the multiplex ID
        jne .continue       ; if we don't already have one.
        mov [bp-1], ah

        .continue:
        dec ah
        cmp ah, .min_id
        jge .scan_loop

    ; End of scan loop: our TSR is not installed
    mov ah, 0
    mov al, [bp-1]  ; AL = an available multiplex ID (if we found one)
    xor cx, cx      ; CL = 0: no TSR currently installed, and thus
    xor dx, dx      ; DX = 0: there is no code segment to return

    .finish:
    mov sp, bp
    pop es
    pop ds
    pop di
    pop si
    pop bp
    pop bx
    ret


;-------------------------------------------------------------------------------
; Installs TSR and terminates program.
;
; AL = Available multiplex ID to install into (found via scan_multiplex_ids)
;-------------------------------------------------------------------------------
install_and_terminate:
    ; Allocate BX = buffer on stack
    BUFFER_SIZE equ 20*1024
    sub sp, BUFFER_SIZE
    mov bx, sp

    ; Save destination multiplex ID
    push ax

    ; Initialize DI to point to an empty Pascal string
    mov di, bx
    mov word [di], 0

    ; String 0: TSR ID hash
    %macro append_fragment 1
        mov si, %1
        mov cx, %1.end_of_contents - %1
        call .append_to_pstring
    %endmacro
    append_fragment tsr_id_hash_value
    call .new_pstring

    ; String 1: video interrupt handler
    append_fragment int_10h_handler_prefix
    append_fragment find_resident_palette
    append_fragment set_palette
    append_fragment set_font
    append_fragment int_10h_handler_suffix
    call .new_pstring

    ; String 2: TSR multiplex handler
    append_fragment int_2fh_handler
    call .new_pstring

    ; String 3: data blob
    mov si, [parsed_bundle.palette] ; We can't use append_fragment here because
    mov cx, 3*16                    ; the palette comes from the bundle, and it
    call .append_to_pstring         ; doesn't have labels marking start/end

    mov si, parsed_bundle.font_height   ; Likewise for font data.
    mov cx, 1                           ; We append the font height (1 byte)
    call .append_to_pstring             ; before appending the glyph data.
    mov si, [parsed_bundle.font]
    mov ch, [parsed_bundle.font_height]
    xor cl, cl
    call .append_to_pstring
    call .new_pstring

    ; String 4: TSR installation code
    append_fragment finalize_install

    ; Jump to installation code
    mov si, bx          ; SI = start of buffer containing strings
    lea bx, [di + 2]    ; BX = contents of TSR installation string
    pop ax              ; AL = multiplex ID to use
    mov ah, 2Fh         ;
    jmp bx              ; Jump to finalize_install

    ; Helper: Append SI:CX to Pascal string pointed to by DI
    ; Sets CX = 0 but otherwise does not clobber any registers
    .append_to_pstring:
        push bx
        mov bx, di          ; BX = pointer to string header
        add di, 2           ; Skip past string header
        add di, [bx]        ; Skip past string contents
        add [bx], cx        ; Update length of string
        rep movsb           ; Actually append data
        mov di, bx          ; Restore DI = pointer to string header
        pop bx
        ret

    ; Helper: Assuming DI points to an existing Pascal string, create
    ; an empty string right after it and set DI to point to it.
    .new_pstring:
        add di, [di]        ; Skip over string data
        add di, 2           ; and header,
        mov [di], word 0    ; and set new string's length = 0
        ret

;-------------------------------------------------------------------------------
; Safely remove TSR from memory.
;
; DX = Resident segment
; Returns AX=0 on failure, AX=1 on success.
;-------------------------------------------------------------------------------
uninstall_tsr:
    push bx
    push ds
    push es
    cli

    ; Make sure interrupt handlers haven't changed since we were installed.
    ; If they have, it means another TSR is installed on top of us.
    mov ax, 3510h   ; Get current 10h vector
    int 21h
    mov ax, es      ; Make sure segment hasn't changed. Technically, we should
    cmp ax, dx      ; also check the offset, but (1) that's hard to calculate,
    jne .fail       ; and (2) it's unlikely someone else is using our segment.

    mov ax, 352Fh   ; Get current 2Fh vector
    int 21h
    mov ax, es      ; Same as above: make sure segment hasn't changed,
    cmp ax, dx      ; and abort if it has.
    jne .fail

    ; Restore old interrupt handlers
    mov es, dx
    mov ax, 2510h                       ; Set 10h handler
    mov ds, [es:old_int_10h.segment]
    mov dx, [es:old_int_10h.offset]
    int 21h

    mov ax, 252Fh                       ; Set 2Fh handler
    mov ds, [es:old_int_2fh.segment]
    mov dx, [es:old_int_2fh.offset]
    int 21h

    ; Free resident memory
    mov ah, 49h     ; ES = segment to free
    int 21h

    .success:
    mov ax, 1
    jmp .ret

    .fail:
    xor ax, ax

    .ret:
    sti
    pop es
    pop ds
    pop bx
    ret

;-------------------------------------------------------------------------------
; Code fragment: Intercept int 10h and establish our own stack
;-------------------------------------------------------------------------------
int_10h_handler_prefix:
cmp ah, 0                       ; Verify that this call is setting the video mode
je .set_video_mode
jmp far [cs:old_int_10h]        ; Otherwise, let the old handler handle it
.set_video_mode:
mov [cs:old_stack_pointer], sp  ; Replace caller's stack with our miniature stack
mov sp, old_stack_pointer
pushf                       ; Call the old int 10h as if it was
call far [cs:old_int_10h]   ; a regular subroutine
pusha
push ds
mov ax, cs
mov ds, ax
.end_of_contents:

;-------------------------------------------------------------------------------
; Code fragment: Clean up/restore environment and return from interrupt
;-------------------------------------------------------------------------------
int_10h_handler_suffix:
pop ds
popa
mov sp, [cs:old_stack_pointer]
iret
.end_of_contents:

;-------------------------------------------------------------------------------
; Code fragment: Set DX = pointer to palette in resident code
;-------------------------------------------------------------------------------
find_resident_palette:
mov dx, [palette_offset]
.end_of_contents:

;-------------------------------------------------------------------------------
; Install code: Overwrite in-memory code with buffer and terminate
;
; AH = TSR multiplex interrupt (usually 2Fh)
; AL = TSR ID
; SI = Pointer to array of Pascal strings, in order:
;   0. TSR ID hash value
;   1. Code for video interrupt handler
;   2. Code for TSR multiplex handler
;   3. Data blob (palette/font)
;-------------------------------------------------------------------------------
finalize_install:
    ; Save TSR handler ID in resident global
    mov [tsr_multiplex], ax

    ; Copy TSR ID hash value to resident header
    mov di, tsr_nametag
    call .process_pstring

    ; Copy interrupt handlers and save their addresses
    mov di, tsr_code_start
    call .process_pstring   ; Video interrupt handler
    push ax
    call .process_pstring   ; TSR multiplex handler
    push ax

    ; Copy data blob and write its address to resident global
    call .process_pstring
    mov [palette_offset], ax

    ; Install interrupts
    cli

    ; Patch TSR multiplex interrupt
    mov     ax, 352Fh   ; get and save current 2Fh vector
    int     21h
    mov     [old_int_2fh.offset], bx
    mov     [old_int_2fh.segment], es
    mov     ax, 252Fh   ; replace current 2Fh vector
    pop     dx
    int     21h

    ; Patch video interrupt
    mov     ax, 3510h   ; get and save current 10h vector
    int     21h
    mov     [old_int_10h.offset], bx
    mov     [old_int_10h.segment], es
    mov     ax, 2510h   ; replace current 10h vector
    pop     dx
    int     21h

    sti

    ; Free environment block before exiting
    mov ah, 49h
    mov es, [2ch]   ; Environment segment from PSP
    int 21h

    ; Terminate and stay resident
    mov ax, 3100h   ; TSR, return code 0
    mov dx, di      ; Number of bytes that should remain resident
    add dx, 16 - 1  ; Make sure division by 16 gets rounded up
    shr dx, 4       ; DX = number of paragraphs
    int 21h

    ; Helper: Given SI = Pascal-style string, copy its raw contents to DI.
    ; Advances SI to next string in array, DI to next location to write to.
    ; Returns AX = start of the copy that was created.
    .process_pstring:
        mov cx, [si]
        add si, 2
        mov ax, di
        rep movsb
        ret
.end_of_contents:

;-------------------------------------------------------------------------------
; TSR multiplex handler (int 2Fh)
;
; Returns the resident code segment in ES and the TSR nametag in ES:DI.
;-------------------------------------------------------------------------------
int_2fh_handler:
cmp ah, [cs:tsr_multiplex.id]
je .match
jmp far [cs:old_int_2fh]
.match:
mov al, 0ffh        ; Indicate installed status
mov di, cs
mov es, di
mov di, tsr_nametag
iret
.end_of_contents:
