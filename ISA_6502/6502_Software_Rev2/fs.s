; ============================================================================
; fs.s - one set of file calls for LOAD / SAVE / LOADRAW / SAVERAW, LOAD "$",
;        the monitor's L command and SBC_LOAD, on either storage device:
;
;   U:  the CH376 USB drive              (fs_dev = 0)
;   C:  the CF card on the SPI-IDE card  (fs_dev = 1)
;
; A name may start with "U:" or "C:" to switch devices; the choice stays
; until changed (like a DOS drive letter), e.g.  LOAD "C:GAME", SAVE "U:X",
; LOAD "C:$", and in the monitor  L C:  then  L NAME.  At reset it is
; FS_DEFAULT (config.inc).  Switching device in the monitor goes back to
; that device's root directory.
;
; The calls take and return exactly what the CH376 driver does (A/X = name,
; ch_ptr / ch_len / ch_got, CH376 status codes), so the code above them is the
; same for both devices.
; ============================================================================

FS_USB          = 0
FS_CF           = 1

.segment "DRVVARS"
fs_dev:         .res 1

.segment "BIOS"

; fs_boot - from CH_BOOT
fs_boot:
        lda     #FS_DEFAULT
        sta     fs_dev
.if HAS_IDE
        lda     #0
        sta     ide_ready
.endif
        rts

; fs_unready - A = 0: both devices are set up again next time (keeps A)
fs_unready:
        sta     ch_ready
.if HAS_IDE
        sta     ide_ready
.endif
        rts

; fs_letter - A = a device letter (either case): C=0 and fs_dev set, or C=1
; if it isn't U or C.  Y is kept.
fs_letter:
        and     #$DF
        cmp     #'U'
        beq     @u
.if HAS_IDE
        cmp     #'C'
        beq     @c
.endif
        sec
        rts
@u:     lda     #FS_USB
        sta     fs_dev
        clc
        rts
.if HAS_IDE
@c:     lda     #FS_CF
        sta     fs_dev
        clc
        rts
.endif

; ---- the dispatch -------------------------------------------------------------
.if HAS_IDE
  .macro FS_GO usb, cf
        ldy     fs_dev
        bne     :+
        jmp     usb
:       jmp     cf
  .endmacro
.else
  .macro FS_GO usb, cf
        jmp     usb
  .endmacro
.endif

fs_prepare:     FS_GO   ch_prepare,    ide_prepare
fs_dirlist:     FS_GO   ch_dirlist,    ide_dirlist
fs_read:        FS_GO   ch_read,       ide_read
fs_write:       FS_GO   ch_write,      ide_write
fs_close:       FS_GO   ch_file_close, ide_close

; (A/X = name: Y is the only free register)
fs_open:        FS_GO   ch_file_open,  ide_open
fs_create:      FS_GO   ch_file_create, ide_create
fs_erase:       FS_GO   ch_file_erase, ide_erase

; ---- date and time (jump table) -----------------------------------------------
; FS_TIME - A/Y = 18 byte buffer <- "mm/dd/yy hh:mm:ss",0;  C=1 = no clock
; FS_SETTIME - A/Y -> 14 characters "dwyymmddHHMMSS" (dw 01 = Sunday)
.if HAS_IDE
FS_TIME         = ide_time
FS_SETTIME      = ide_settime
.else
FS_TIME:
FS_SETTIME:
        sec
        rts
.endif
