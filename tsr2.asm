org     100h ; this is a .COM file -- adjust addresses accordingly

;;
;;  RESIDENT CODE
;;

beginResident:
jmp     parseCommandLineArgs


;; TSR data
oldInt10:
.offset:    dw 0
.segment:   dw 0

oldInt2F:
.offset:    dw 0
.segment:   dw 0

ID_number:  db  0
ID_string:  db  'ZZT initializer', 0



;; video settings
db  'DATA'
setHighIntensity:   db  1
setFont:            db  1
setPalette:         db  1

font:       incbin  "megazeux.chr"
palette:    incbin  "invert.pal"




;; Initialize the video settings (font, palette, etc)
;; Assumes that default settings are already in place (i.e., there have been no
;; changes to video settings since the last screen mode change)
setVideoSettings:
pusha               ; store registers
push    ds
push    es
mov     bx, cs      ; initialize ds and es for convenience
mov     ds, bx
mov     es, bx

; set high intensity backgrounds if we want them
mov     bl, [setHighIntensity]
cmp     bl, 0
je      setVideoSettings.highIntensityOff
mov     bl, 1
.highIntensityOff:
not     bl
mov     ax, 1003h   ; turn intensity on or off (depending on bl)
int     10h

; set a custom color palette if we want it
mov     bl, [setPalette]
cmp     bl, 0
je      setVideoSettings.skipPalette
mov     ax, 1012h   ; load palette
mov     bx, 0
mov     cx, 16
mov     dx, palette
int     10h
.skipPalette:

; set a custom font if we want it
mov     al, [setFont]
cmp     al, 0
je      setVideoSettings.skipFont

mov     ax, 1201h   ; set scanlines = 350
mov     bl, 30h
int     10h

mov     ax, 1110h   ; set character table
mov     bh, 14      ; 14 bytes per character
mov     bl, 0       ; page 0
mov     cx, 256     ; 256 characters
mov     dx, 0       ; start at ASCII char 0
mov     bp, font
int     10h
.skipFont:

pop     es          ; restore registers
pop     ds
popa
ret





;;; DEBUG FUNCTION
;;; prints the contents of dx, in binary
;print_dx:
;push    ax
;push    bx
;push    cx
;
;mov     ah, 0eh ; BIOS print char
;mov     bx, 000Fh
;mov     cx, 16
;.loop:
;rol     dx, 1
;mov     al, dl
;and     al, 01h
;add     al, '0'
;int     10h
;loop    .loop, cx
;
;mov     al, 13 ; newline
;int     10h
;mov     al, 10 ; newline
;int     10h
;
;pop     cx
;pop     bx
;pop     ax
;ret





;; Custom interrupt for int 10h, video services
;; Initializes video settings after a change in screen mode.
;; If the screen mode is not being changed, it passes the interrupt on.
newInt10:
cmp     ah, 0                   ; if the user trying to change screen mode
je      newInt10.setScreenMode  ; do it for them
jmp far [cs:oldInt10]           ; otherwise, just pass the call along
iret
.setScreenMode:
pushf                   ; use the old interrupt like a subroutine
call far [cs:oldInt10]
call setVideoSettings   ; do our stuff after screen mode set is complete
iret





;; Custom interrupt for int 2Fh, DOS multiplex
;; Does one of two things:
;;  (1) If asked if we are installed, put FF in al and our ID string in es:di
;;  (2) If asked to uninstall self, try to do so and put 0 in al on success
;; If asked to do neither of these things, it passes the interrupt on.
newInt2F:
; check to see if the interrupt call was for us
push    ax
mov     al, [cs:ID_number]
cmp     al, ah              ; compare ID numbers
pop     ax
je     newInt2F.isForUs     ; if it's our ID, handle the interrupt
.pass:
jmp far [cs:oldInt2F]       ; otherwise, pass it on

; if the interrupt call was for us, do something
.isForUs:
cmp     al, 0               ; if we need to check installation state, do so
je      newInt2F.checkInstalled
cmp     al, 1               ; if asked to uninstall ourselves, do so
je      newInt2F.uninstall
jmp     .pass               ; otherwise, pass the interrupt along





;; get installed state -- part of newInt2F
.checkInstalled:
mov     ax, cs              ; store our ID string in es:di
mov     es, ax
mov     ax, ID_string
mov     di, ax
mov     al, 0xFF            ; now, store our installed state and ID number
mov     ah, [cs:ID_number]
iret





;; uninstall TSR -- part of newInt2F
.uninstall:
; make sure it's safe to uninstall the TSR
pusha
cli
mov     ax, 3510h           ; get current int 10h vector
int     21h
cmp     bx, newInt10        ; make sure the current int 10h vector is still ours
jne     newInt2F.abortUninstall
mov     bx, es
mov     ax, cs
cmp     ax, bx
jne     newInt2F.abortUninstall

mov     ax, 352Fh           ; get current int 2Fh vector
int     21h
cmp     bx, newInt2F        ; make sure the current int 2Fh vector is still ours
jne     newInt2F.abortUninstall
mov     bx, es
mov     ax, cs
cmp     ax, bx
jne     newInt2F.abortUninstall

; it's safe -- restore interrupt vectors to their previous values
mov     ax, 2510h           ; restore int 10h vector
mov     dx, [cs:oldInt10.segment]
mov     ds, dx
mov     dx, [cs:oldInt10.offset]
int     21h

mov     ax, 252Fh           ; restore int 2Fh vector
mov     dx, [cs:oldInt2F.segment]
mov     ds, dx
mov     dx, [cs:oldInt2F.offset]
int     21h
sti

; now, release memory occupied by the TSR
mov     ah, 49h             ; free allocated memory
mov     es, [cs:2Ch]        ; environment block
int     21h
mov     ah, 49h             ; free allocated memory
mov     bx, cs
mov     es, bx              ; PSP
int     21h

; we're uninstalled -- finish up    
popa
mov     al, 0               ; indicate a successful uninstallation
iret
.abortUninstall:
popa
mov     al, 1               ; uninstallation failed
iret





;; End of TSR stuff
endResident:










;;
;;  NON-RESIDENT CODE
;;

;; Look at the command line and decide to try one of the following:
;;  (1) install the TSR (<progname> i)
;;  (2) uninstall the TSR (<progname> u)
;;  (3) change the screen font without installing the TSR component (no args)
;;  (4) print a usage message and quit (anything else
parseCommandLineArgs:
mov     al, [80h] ; get length of argument string

; if we have no arguments, just set the screen mode and exit
cmp     al, 0
jne     parseCommandLineArgs.haveArgs
call    setVideoSettings
jmp     quit

; quit with an error if the arguments are obviously invalid
.haveArgs:
cmp     al, 2 ; if we do not have exactly two characters, quit with usage info
mov     dx, usage
jne     quitWithErrorMessage
mov     al, [81h] ; if the first char is not a space, quit with usage info
cmp     al, ' '
jne     quitWithErrorMessage

; if the user wants to install the TSR, do so
mov     al, [82h]
cmp     al, 'i'
je      installTSR
cmp     al, 'I'
je      installTSR

; if the user wants to uninstall the TSR, do so
cmp     al, 'u'
je      uninstallTSR
cmp     al, 'U'
je      uninstallTSR

; we don't know what the user wants -- print usage info
mov     dx, usage
jmp     quitWithErrorMessage





;; Install the TSR and set the screen mode.
;; If the TSR is already installed, print an error message and exit.
installTSR:
; abort if TSR installed
call    detectTSR
cmp     ah, 0
mov     dx, alreadyInstalled
jne     quitWithErrorMessage

; obtain first unused TSR ID
mov     cx, 00FFh
.loop:
mov     al, 0   ; get installed state
mov     ah, cl  ; of TSR with ID cl
push    cx
int     2Fh
pop     cx
cmp     al, 0   ; if the ID isn't taken, take it
je      installTSR.takeID
loop    .loop   ; otherwise, try the next one
mov     dx, installFailed ; if there is no next one, give an error message and exit
jmp     quitWithErrorMessage
.takeID:
mov     [ID_number], ah  ; store our ID

; patch interrupt vector 10h -- video BIOS
cli
mov     ax, 3510h   ; get and save current 10h vector
int     21h
mov     [oldInt10.offset], bx
mov     [oldInt10.segment], es
mov     ax, 2510h   ; replace current 10h vector
mov     dx, newInt10
int     21h

; patch interrupt vector 2Fh -- DOS multiplex interrupt
mov     ax, 352Fh   ; get and save current 2Fh vector
int     21h
mov     [oldInt2F.offset], bx
mov     [oldInt2F.segment], es
mov     ax, 252Fh   ; replace current 10h vector
mov     dx, newInt2F
int     21h
sti

; finish up
call    setVideoSettings
mov     ax, 3100h   ; terminate and remain resident
; calculate memory used by resident portion of code, in paragraphs
; the 100h is to account for the size of the Program Segment Prefix
; the + 1 at the end is to account for rounding errors
mov     dx, (endResident - beginResident + 100h)/16 + 1
int     21h         ; And now we're done.





;; Print what's pointed to by dx and quit
quitWithErrorMessage:
mov     ah, 9       ; print message
int     21h
mov     ax, 4c01h   ; quit
int     21h





;; Uninstall TSR and reset the screen mode.
;; If the TSR is not already installed, print an error message and exit
uninstallTSR:
; make sure there's a TSR to uninstall
call    detectTSR   ; get TSR ID in ah
cmp     ah, 0
mov     dx, notInstalled
je      quitWithErrorMessage

; uninstall the TSR
mov     al, 1   ; uninstall TSR
int     2Fh
cmp     al, 0   ; make sure it uninstalled successfully
mov     dx, uninstallFailed
jne     quitWithErrorMessage

; reset the screen mode
mov     ax, 0002h
int     10h

quit:
mov     ax, 4c00h
int     21h







;; messages
alreadyInstalled:       db  'Already installed!', 13, 10, '$'
notInstalled:           db  'Not installed!', 13, 10, '$'
installFailed:          db  'Install failed!', 13, 10, '$'
uninstallFailed:        db  'Uninstall failed!', 13, 10, '$'
usage:                  db  'Usage: <program name> [i|u]', 13, 10, '$'





;;
;;  SUBROUTINES
;;



;; Detects whether or not our TSR is installed.
;; Sets ah equal to the TSR's id number
;; If not installed, ah is set to 0
detectTSR:
mov     cl, 0xFF    ; start at ID = FF

; loop through all the possible ID numbers
.loop:
mov     al, 0   ; check installed status
mov     ah, cl  ; of TSR with ID cl
push    cx
int     2Fh     ; do the check
pop     cx

; if nothing is installed, go to the next ID
cmp     al, 0
je      detectTSR.checkNextID

; otherwise, test what is installed to see if it's our TSR
; we do this by comparing the ID string our TSR gave us with the real thing
mov     si, ID_string            ; the name we'll comapre es:di to
.strcmp
mov     bh, [es:di]
mov     bl, [si]
cmp     bh, bl                  ; are the next characters the same?
jne     detectTSR.checkNextID   ; if not, move on to the next TSR
cmp     bl, 0                   ; have we reached the end of the string?
je      detectTSR.return        ; if so, we found our TSR
inc     si
inc     di
jmp     .strcmp

.checkNextID:
cmp     cl, 0xC0                ; C0 is the lowest TSR ID we can use
loopne  .loop                   ; END loop through all the possible ID numbers
mov     cl, 0                   ; set cl to 0 if we didn't find the TSR

; By this point, cl will either be 0 (meaning we didn't find anything)
; or the ID of our TSR. Move it into position and return.
.return:
mov     ah, cl
ret














