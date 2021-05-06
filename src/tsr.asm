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
; Allocate buffer on stack
BUFFER_SIZE equ 20*1024
sub sp, BUFFER_SIZE

; Appends code fragment to the memory location pointed to by DI
; Usage: append_to_buffer foo
; The labels foo and foo.end_of_contents must both exist
%macro append_to_buffer 1
mov si, %1
mov cx, %1.end_of_contents - %1
rep movsb
%endmacro

; Assemble TSR code
mov bp, sp  ; BP = Start of buffer = start of resident code
mov di, bp
append_to_buffer int_10h_handler_prefix
append_to_buffer find_resident_palette
append_to_buffer set_palette
append_to_buffer int_10h_handler_suffix
push di     ; Save address of palette in resident memory
append_to_buffer test_palette
mov ax, di
sub ax, bp  ; AX = Number of bytes of resident code

; Run install routine
push di
append_to_buffer finalize_install
mov cx, ax  ; CX = Number of bytes of resident code
mov si, bp  ; SI = Start of resident code
pop bx
pop ax                  ; Calculate AX=offset of palette assuming segment=CS
sub ax, bp              ; This will be the location of the palette when the TSR
add ax, tsr_code_start  ; is installed. This calculation, and the interface with
push ax                 ; the finalization code in general, needs some work.
jmp bx

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
; SI = Start of buffer
; CX = Size in bytes
; Stack: Offset of resident palette
;-------------------------------------------------------------------------------
; Brainstorming an API: What data does this function need?
;   - Blob of resident code/data to install (pointer/length, SI/CX)
;   - TSR multiplex ID (AX)
;   - Location of data tables in the blob (BX) (conflict, used for jmp)
;   - Location of int 10h in the blob   (CX) (conflict)
;   - Location of int 2fh in the blob   (DX)
; Data tables can be chained together. The first routine gets a pointer
; directly to its data. As part of processing, it advances the pointer to the
; byte following the end of its data -- setting things up for the next routine.
;
; The need to pass in locations of 10h/2fh could be eliminated with some
; cleverness: 2fh's handler is constant length, and if it is placed at the
; start of the resident code, 10h would have a known location as well.
; It feels a little inelegant, though.
finalize_install:
; Copy TSR code into place
pop bx
mov [palette_offset], bx
push cx
mov di, tsr_code_start
rep movsb

; Patch TSR code into interrupt
cli
mov     ax, 3510h   ; get and save current 10h vector
int     21h
mov     [old_int_10h.offset], bx
mov     [old_int_10h.segment], es
mov     ax, 2510h   ; replace current 10h vector
mov     dx, tsr_code_start  ; TODO: This will need to be more sophisticated in the future because
                            ; we will have both an int 2Fh handler and an int 10h handler
int     21h
sti

; Free environment block before exiting
mov ah, 49h
mov es, [2ch]   ; Environment segment from PSP
int 21h

; Terminate and stay resident
mov ax, 3100h   ; TSR, return code 0
pop dx          ; Convert the size in bytes
add dx, tsr_code_start
add dx, 16 - 1  ; to the size in 16-byte paragraphs,
mov cl, 4       ; rounding up
shr dx, cl
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
