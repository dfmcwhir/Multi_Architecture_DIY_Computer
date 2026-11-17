; ============================================================================
; jumptable.s - FIXED entry points for programs you load with the monitor
;
; Every entry is a 3 byte JMP at a fixed address from $FE00, so programs built
; separately keep working when the ROM is rebuilt.  sbc_api.inc has the same
; addresses as ca65 equates.  Add new entries at the END only.
;
;   $FE00  SBC_CHRIN     C=1 + A = character, C=0 nothing waiting
;   $FE03  SBC_CHROUT    print A (A, X, Y preserved)
;   $FE06  SBC_MENU      boot menu
;   $FE09  SBC_COLD      EhBASIC cold start
;   $FE0C  SBC_WARM      EhBASIC warm start
;   $FE0F  SBC_MONITOR   monitor prompt
;   $FE12  SBC_PADSTATE  A = gamepad buttons held now
;   $FE15  SBC_LOAD      load a file (see sbc_api.inc)
;   $FE18  SBC_CWD       A/Y = monitor's current folder
;   ---- new for CPU Rev2 (check SBC_SYSINFO: Y = API version >= 2) ----
;   $FE1B  SBC_SYSINFO   A = display type, X = device status, Y = API version
;   $FE1E  SBC_SEROUT    send A out of the serial console port (A, X, Y kept)
;   $FE21  SBC_MOUSEON   A = 1 mouse reports on / 0 off.  C=1: no mouse
;   $FE24  SBC_MOUSE     A = buttons, X/Y = movement since last call;
;                        C=1 if a report arrived since the last call
;   $FE27  SBC_BANKSET   A = RAM bank (0-15) for $1000-$7EFF   (*)
;   $FE2A  SBC_BANKGET   A = bank selected, X = number of banks
;   $FE2D  SBC_TICKS     A/X/Y = 60 Hz counter, low/middle/high
;   $FE30  SBC_ACIAIN    serial card 6551: C=1 + A = byte, C=0 none
;   $FE33  SBC_ACIAOUT   serial card 6551: send A
;   $FE36  SBC_VSYNC     C=1 if a frame ended since the last call
;                        (PICO9918 / ESP32_VGA; A = the status)
;   $FE39  SBC_CONRESET  display back to the text console, cleared
;   $FE3C  SBC_SNDNOTE   A/Y -> voice, note, volume, time lo, time hi; C=1 bad
;   $FE3F  SBC_SNDQUIET  all sound off
;   $FE42  SBC_SNDBUSY   A = voice: C=1 while its timed note plays
;   $FE45  SBC_SAY       A/Y -> allophones ended by $FF (queued)
;   $FE48  SBC_SAYBUSY   C=1 while speaking
;   $FE4B  SBC_AYREAD    X = AY register -> A
;   $FE4E  SBC_AYWRITE   AY register X = A
;   $FE51  SBC_TIME      A/Y -> 18 bytes <- "mm/dd/yy hh:mm:ss",0; C=1 no clock
;   $FE54  SBC_SETTIME   A/Y -> "dwyymmddHHMMSS"; C=1 no clock
;   $FE57  SBC_DIR       A/Y -> block: the current folder into a table (shell.s)
;   $FE5A  SBC_RUN       A/Y -> block: load and start a program or BASIC program
;   $FE5D  SBC_SHELL     A = the shell's RAM bank (0 = none)
;   $FEFF  (a byte)      display type, for PEEK(65279) from BASIC
;
; (*) code that switches banks must itself be in ROM or $0000-$0FFF.
; ============================================================================
.segment "JUMPTAB"
JT_CHRIN:       jmp     CHRIN
JT_CHROUT:      jmp     CHROUT
JT_MENU:        jmp     shell_menu      ; (the shell if there is one)
JT_COLD:        jmp     LAB_COLD
JT_WARM:        jmp     LAB_WARM
JT_MONITOR:     jmp     WOZ_ENTRY
JT_PADSTATE:    jmp     PAD_STATE
JT_LOAD:        jmp     SBC_LOAD
JT_CWD:         jmp     sbc_cwd
JT_SYSINFO:     jmp     SYSINFO
JT_SEROUT:      jmp     SER_OUT
JT_MOUSEON:     jmp     jt_mouseon
JT_MOUSE:       jmp     jt_mouse
JT_BANKSET:     jmp     BANK_SET
JT_BANKGET:     jmp     BANK_GET
JT_TICKS:       jmp     jt_ticks
JT_ACIAIN:      jmp     jt_aciain
JT_ACIAOUT:     jmp     jt_aciaout
JT_VSYNC:       jmp     jt_vsync
JT_CONRESET:    jmp     jt_conreset
JT_SNDNOTE:     jmp     SND_API_NOTE
JT_SNDQUIET:    jmp     BI_QUIET
JT_SNDBUSY:     jmp     SND_API_BUSY
JT_SAY:         jmp     jt_say
JT_SAYBUSY:     jmp     jt_saybusy
JT_AYREAD:      jmp     SND_AYREAD
JT_AYWRITE:     jmp     SND_AYWRITE
JT_TIME:        jmp     FS_TIME
JT_SETTIME:     jmp     FS_SETTIME
JT_DIR:         jmp     sbc_dir         ; stage 6
JT_RUN:         jmp     sbc_run
JT_SHELL:       jmp     sbc_shell
JT_COPY:        jmp     sbc_copy        ; stage 6b
JT_DELETE:      jmp     sbc_delete

.segment "SYSBYTE"
                .byte   CON_DISPLAY     ; $FEFF

.assert JT_CWD = $FE18, error, "jumptable.s: an old entry moved"
.assert JT_DIR = $FE57, error, "jumptable.s: SBC_DIR moved"
.assert JT_DELETE = $FE63, error, "jumptable.s: SBC_DELETE moved"

.segment "BIOS"

; Entries whose driver may not be in this build get a harmless stand-in.
.if MOUSE_SRC = MOUSE_AVR
jt_mouseon      = MOUSE_ON
jt_mouse        = MOUSE_READ
.elseif MOUSE_SRC = MOUSE_ESP32
jt_mouseon      = esp_mouse_on
jt_mouse        = esp_mouse_read
.else
jt_mouseon:
        sec                             ; no mouse interface
        rts
jt_mouse:
        lda     #0
        tax
        tay
        clc
        rts
.endif

.if GFX_OK
jt_vsync        = gfx_vsync
.else
jt_vsync:
        lda     #0
        clc
        rts
.endif

.if CON_DISPLAY <> DISP_NONE
jt_conreset:
        jsr     disp_reset
        clc
        rts
.else
jt_conreset:
        rts
.endif

.if HAS_SPO
jt_say          = SPO_SAY
jt_saybusy      = SPO_BUSY
.else
jt_say:
        rts
jt_saybusy:
        clc
        rts
.endif

.if HAS_VIA
jt_ticks        = TICKS_GET
.else
jt_ticks:
        lda     #0
        tax
        tay
        rts
.endif

.if HAS_ACIA
jt_aciain       = acia_getc
jt_aciaout:                             ; A, X, Y preserved
        pha
        txa
        pha
        tya
        pha
        tsx
        lda     $0103,x                 ; the byte
        jsr     acia_putc
        pla
        tay
        pla
        tax
        pla
        rts
.else
jt_aciain:
        lda     #0
        clc
        rts
jt_aciaout:
        rts
.endif
