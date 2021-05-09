;; Functions and definitions for TSR-specific stuff

;===============================================================================
; Constants
;-------------------------------------------------------------------------------
; Calculates the 32-bit FNV-1a hash of a string and assigns it to a macro variable.
; Usage: fnv_hash variable_to_assign, 'string to be hashed'
%macro fnv_hash 2
%strlen %%num_bytes %2
%assign %%hash 0x811c9dc5
%assign %%i 0
%rep %%num_bytes
    %assign %%i %%i+1
    %substr %%byte %2 %%i
    %assign %%hash ((%%hash ^ %%byte) * 0x01000193) & 0xFFFFFFFF
%endrep
%assign %1 %%hash
%endmacro

; Calculate a somewhate-unique 32-bit identifier for our TSR
%define TSR_ID_STRING "Quantum's all-purpose TSR, version rewrite-in-progress"
fnv_hash TSR_ID_HASH, TSR_ID_STRING
TSR_HASH_LO equ TSR_ID_HASH & 0xFFFF
TSR_HASH_HI equ TSR_ID_HASH >> 16


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

old_int_10h:    ; previous video interrupt
.offset:    resb 2
.segment:   resb 2

old_int_2fh:    ; TSR multiplex interrupt
.offset:    resb 2
.segment:   resb 2

; Allocate space to store the TSR's 1-byte numeric ID (assigned at runtime)
tsr_id_num: resb 1

palette_offset: resb 2  ; Location of palette data in resident memory

; End of statically-allocated data; generated resident code follows.
tsr_code_start:

;===============================================================================
; Resident code and code fragments
;-------------------------------------------------------------------------------
segment .text
; TODO for full install routine:
; 0. Make sure TSR can be installed
; 1. Allocate buffer for assembling TSR
; 2. Append TSR code/data to buffer
; 3. Append install routine to buffer
;   a. Byte copier
;   b. Hook-into-interrupts code
;   c. Jump to PSP
; 4. Copy termination code to PSP (optional memory initializer)
; 5. Jump to install routine


;-------------------------------------------------------------------------------
; Installs TSR with no pre-installation check and no way to uninstall.
; Always "succeeds" and never returns.
;-------------------------------------------------------------------------------
impolite_install:
    ; Allocate BX = buffer on stack
    BUFFER_SIZE equ 20*1024
    sub sp, BUFFER_SIZE
    mov bx, sp

    ; Initialize DI to point to an empty Pascal string
    mov di, bx
    mov word [di], 0

    ; String 1: video interrupt handler
    %macro append_fragment 1
        mov si, %1
        mov cx, %1.end_of_contents - %1
        call .append_to_pstring
    %endmacro
    append_fragment int_10h_handler_prefix
    append_fragment find_resident_palette
    append_fragment set_palette
    append_fragment int_10h_handler_suffix
    call .new_pstring

    ; String 2: TSR multiplex handler
    append_fragment int_2fh_handler
    call .new_pstring

    ; String 3: data blob
    append_fragment test_palette
    call .new_pstring

    ; String 4: TSR installation code
    append_fragment finalize_install

    ; Jump to installation code
    mov si, bx          ; SI = start of buffer containing strings
    lea bx, [di + 2]    ; BX = contents of TSR installation string
                        ; Later, we will set AX = TSR multiplex ID here.
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
;   1. Code for video interrupt handler
;   2. Code for TSR multiplex handler
;   3. Data blob (palette/font)
;-------------------------------------------------------------------------------
finalize_install:
    ; Copy contents of strings to their final location, concatenating them
    mov di, tsr_code_start
    mov dx, 3
    .copy_strings:
        mov cx, [si]
        add si, 2
        push di         ; Save pointer to start of each string's data
        rep movsb
        dec dx
        jnz .copy_strings

    ; Stack now holds: (data ptr)(multiplex ptr)(video ptr)
    ; Write pointer to data blob
    pop word [palette_offset]

    ; TODO: Install DX as pointer to TSR multiplex interrupt
    cli
    pop dx  ; Throw away value for now

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
.end_of_contents:

;-------------------------------------------------------------------------------
; TSR multiplex handler (int 2Fh)
;
; Returns the resident code's segment in BX and the TSR hash in CX:DX.
;-------------------------------------------------------------------------------
int_2fh_handler:
cmp ah, [cs:tsr_id_num]
je .match
jmp far [cs:old_int_2fh]
.match:
mov al, 0ffh        ; Indicate installed status
mov bx, cs
mov cx, TSR_HASH_LO
mov dx, TSR_HASH_HI
iret
.end_of_contents:
