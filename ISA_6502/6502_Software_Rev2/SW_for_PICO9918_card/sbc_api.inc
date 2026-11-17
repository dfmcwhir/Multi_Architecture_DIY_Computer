; sbc_api.inc - fixed ROM entry points of the SBC (see jumptable.s), and the
; CPU clock.  Use in your own ca65 programs:  .include "sbc_api.inc"
; (the games find it one folder up: their make.bat passes  -I ..  to ca65)
SBC_CHRIN       = $FE00         ; carry set + A = char, carry clear = none waiting
SBC_CHROUT      = $FE03         ; print A (A, X, Y preserved)
SBC_MENU        = $FE06         ; boot menu
SBC_COLD        = $FE09         ; BASIC cold start
SBC_WARM        = $FE0C         ; BASIC warm start
SBC_MONITOR     = $FE0F         ; monitor prompt (or JMP $FF00)
SBC_PADSTATE    = $FE12         ; A = gamepad buttons held: bit0 A,1 B,2 Select,3 Start,4 Up,5 Down,6 Left,7 Right
SBC_LOAD        = $FE15         ; load a file from the current device (U: or C:): A/Y = parameter block (.word addr, .word max, "NAME.EXT",0)
                                ;   carry clear = loaded, X/Y = length; carry set = failed, A = error code
SBC_CWD         = $FE18         ; A/Y = the monitor's current folder: 0-ended, "" (the top) or "/A/B"
                                ;   (newer ROMs: check for a JMP ($4C) at $FE18 first)

; ---- CPU Rev2 ROMs (API version 2).  Check first:  LDA $FE1B / CMP #$4C,
;      then JSR SBC_SYSINFO and check Y >= 2.
SBC_SYSINFO     = $FE1B         ; A = display type (DISP_...), X = device status, Y = API version
SBC_SEROUT      = $FE1E         ; send A out of the serial console port (A, X, Y preserved)
SBC_MOUSEON     = $FE21         ; A = 1 mouse reports on, 0 off (off at reset); C=1 = no mouse
SBC_MOUSE       = $FE24         ; A = buttons (bit0 L, 1 R, 2 M), X/Y = signed movement since
                                ;   the last call (right/down +); C=1 = a report arrived
SBC_BANKSET     = $FE27         ; A = RAM bank 0-15 for $1000-$7EFF (X, Y kept).  Your code that
                                ;   calls it must be in $0000-$0FFF, or it switches itself out!
SBC_BANKGET     = $FE2A         ; A = bank selected, X = number of banks fitted
SBC_TICKS       = $FE2D         ; A/X/Y = 60 Hz counter, low/middle/high
SBC_ACIAIN      = $FE30         ; serial card 6551: C=1 + A = byte, C=0 none
SBC_ACIAOUT     = $FE33         ; serial card 6551: send A (A, X, Y preserved)
SBC_VSYNC       = $FE36         ; C=1 if a frame ended since the last call (PICO9918 / ESP32_VGA),
                                ;   A = the VDP status / ESP32 STATUS
SBC_CONRESET    = $FE39         ; display back to the text console, cleared (call it when
                                ;   your game exits after changing the display mode)
SBC_SNDNOTE     = $FE3C         ; A/Y -> 5 bytes: voice (AY 0-2, ESP32 0-3), note (0-95, 36 = C4),
                                ;   volume (0-15; AY 16 = envelope), time (16 bit, 1/60 s,
                                ;   0 = hold).  Doesn't wait.  C=1 = bad values
SBC_SNDQUIET    = $FE3F         ; all sound off
SBC_SNDBUSY     = $FE42         ; A = voice: C=1 while its timed note is still playing
SBC_SAY         = $FE45         ; A/Y -> SPO256 allophones (0-63) ended by $FF; queued
SBC_SAYBUSY     = $FE48         ; C=1 while the SPO256 is speaking
SBC_AYREAD      = $FE4B         ; X = AY register (14/15 = I/O ports A/B) -> A
SBC_AYWRITE     = $FE4E         ; AY register X = A (register 7 bits 6/7 = ports A/B output)
SBC_TIME        = $FE51         ; A/Y -> 18 byte buffer <- "mm/dd/yy hh:mm:ss",0 (CF card's DS1302);
                                ;   C=1 = no clock
SBC_SETTIME     = $FE54         ; A/Y -> 14 characters "dwyymmddHHMMSS" (dw 01 = Sunday)
SBC_DIR         = $FE57         ; stage 6: A/Y -> block: .word table, .byte most entries, .byte device
                                ;   ('U', 'C' or 0 = as it is): the current folder (SBC_CWD) into the
                                ;   table, 16 bytes an entry: name 8, ext 3 (space padded), attributes
                                ;   ($10 = folder), size 4.  C=0: A = entries; C=1: A = error code
SBC_RUN         = $FE5A         ; stage 6: A/Y -> block: .byte 0 = .BIN (bank 0, $0800) / 1 = BASIC
                                ;   program, .byte device, "NAME.EXT",0 (in the current folder).
                                ;   Returns only on an error: C=1, A = code
SBC_SHELL       = $FE5D         ; stage 6: A = the RAM bank of a shell ($1000 JMP, $1003 "SH65"):
                                ;   SBC_MENU then goes back to it.  A = 0: none.  C=1: no shell there
SBC_COPY        = $FE60         ; stage 6b: A/Y -> block: .byte source device ('U'/'C'), .word -> source
                                ;   path "/A/NAME.EXT",0, .byte destination device, .word -> its path.
                                ;   Uses every RAM bank but yours as the buffer (bank 0 is lost).
                                ;   C=0 copied; C=1, A = error ($F0 too big)
SBC_DELETE      = $FE63         ; stage 6b: A/Y -> block: .byte device, .word -> path.  C=1, A = error
                                ;   ($42 not found, $FD the drive can't delete)
SBC_DISPTYPE    = $FEFF         ; a byte: the display type (DISP_...)

; SBC_SYSINFO display types
DISP_NONE       = 0
DISP_TERM       = 1             ; KB_MONITOR_TERM (PIC32 terminal)
DISP_PICO       = 2             ; PICO9918
DISP_ESP32      = 3             ; ESP32_VGA

; SBC_SYSINFO device status bits (X)
DEV_VIA         = $01
DEV_ACIA        = $02
DEV_DISPLAY     = $04
DEV_AVRKBD      = $08

; Key codes from the AVR keyboard interface (Serial Rev3 / PICO9918 card)
KEY_UP          = $05           ; ^E  (WordStar)
KEY_DOWN        = $18           ; ^X
KEY_LEFT        = $10           ; ^P
KEY_RIGHT       = $04           ; ^D
KEY_ESC         = $03           ; Esc sends ^C
KEY_F1          = 129           ; F1-F12 = 129-140, shifted 141-152

; First RAM address for loaded programs (CPU Rev2 ROM)
SBC_USER_RAM    = $0800

; The CPU clock in MHz (whole numbers, 1 to 8).  Programs size their delay
; loops from it, so a millisecond stays a millisecond.  To build for another
; clock, change it here or give it on the command line:  make.bat 1
.ifndef CLOCK_MHZ
CLOCK_MHZ       = 2
.endif
