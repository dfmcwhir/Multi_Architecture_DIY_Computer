; ============================================================================
; drv_ide.s - Daryl Rictor's SPI to IDE/CF interface (FAT16), on 65SPI SS0
;
; Protocol (SPI mode 0, MSB first).  Every transaction is two shifts, SS0 held
; low across both, with at least 1.75 us (20 MHz AVR; 2.2 us with your 16 MHz
; ATmega32) between them:
;       Send Data   $01, byte          (host -> interface)
;       Get Status  $02, $00 -> status
;       Get Data    $03, $00 -> byte   (interface -> host)
; Status: b7 = ready for a command, b6 = data ready for the host, b5 = 0 when
; it can take data from the host, b4-b0 = the error code of the last command.
;
; This file makes the interface look like the CH376 to the LOAD / SAVE code
; and the monitor (fs.s picks one or the other):
;   ide_prepare    mount drive 0                      C=1 = no drive
;   ide_open       A/X = path; $14 file opened, $41 it was a directory (and
;                  it is now the current one), $42 not found, other = error
;   ide_create     A/X = path; create / replace it for writing
;   ide_read       ch_len bytes to (ch_ptr): ch_got = what there was, ch_ptr
;                  advanced (the interface itself pads with 0 past the end)
;   ide_write      ch_len bytes from (ch_ptr)
;   ide_close      close the file
;   ide_dirlist    list the directory named by ch_name ("/*", "*", "/A/*")
;   ide_time       A/Y -> 18 bytes: "mm/dd/yy hh:mm:ss",0  (DS1302)
;   ide_settime    A/Y -> 14 characters "dwyymmddHHMMSS"
; Paths: "/" at the start = from the root; the directories are entered one
; level at a time (the interface's own rule).  The interface's errors are
; turned into the CH376's codes where there is one ($42 not found, $B1 full),
; otherwise $E0 + its code.  $FF = it never answered (timeout).
; ============================================================================

IDE_SS          = $FE                   ; SS0 low
IDE_HANDLE      = $00                   ; the one file handle used

IDE_C_CD        = $C3
IDE_C_DIR       = $C1
IDE_C_OPEN      = $C9
IDE_C_READ      = $CA
IDE_C_WRITE     = $CB
IDE_C_CLOSE     = $CE
IDE_C_CLOSEALL  = $C0
IDE_C_SIZE      = $D0
IDE_C_GETTIME   = $E0
IDE_C_SETTIME   = $E1
IDE_C_MOUNT     = $F4
; "erase file/directory" (the interface's command list, from the user):
; sent like CD, the command then the 0-ended name, in the folder entered.
; (0 here would make SBC_DELETE on C: answer $FD.)
.ifndef IDE_C_DELETE
IDE_C_DELETE    = $C4
.endif

; 5-cycle loops for the gap between the two shifts: 2.2 us at CPU_KHZ
IDE_GAP         = CPU_KHZ * 22 / 50000 + 1

.if CPU_KHZ > 8000
  .error "drv_ide.s: the 65SPI clocks at CPU/2 and the IDE interface (16 MHz AVR) takes at most 4 MHz"
.endif

.segment "DRVVARS"
ide_ready:      .res 1                  ; 1 = drive mounted
ide_st:         .res 1                  ; last status
ide_m:          .res 1                  ; ide_wait: mask / value
ide_v:          .res 1
ide_to:         .res 3                  ; timeout counter
ide_n:          .res 2                  ; byte counter
ide_size:       .res 4                  ; open file: size
ide_pos:        .res 4                  ;            position
ide_comp:       .res 14                 ; one part of a path
ide_t:          .res 1

.segment "BIOS"

; ============================================================================
; Transactions
; ============================================================================

; ide_tx - one transaction: A = type ($01 / $02 / $03), X = byte to send.
; Returns the byte from the second shift in A.  Clobbers Y.
ide_tx:
        pha
        lda     #IDE_SS
        sta     SPI_SS
        pla
        jsr     spi_xfer
        ldy     #IDE_GAP
@g:     dey
        bne     @g
        txa
        jsr     spi_xfer
        ldy     #$FF
        sty     SPI_SS
        rts

; ide_status - A = the status byte.  Clobbers X, Y.
ide_status:
        lda     #$02
        ldx     #$00
        jsr     ide_tx
        sta     ide_st
        rts

; ide_wait - wait until (status AND ide_m) = ide_v, about 3 s at most (one
; status poll is roughly 130 CPU cycles; IDE_POLLS x 256 polls).
; C=0: A = the status;  C=1: timed out (A = $FF).  Clobbers X, Y.
IDE_POLLS       = 90 * CPU_MHZ
ide_wait:
        lda     #0
        sta     ide_to
        lda     #<IDE_POLLS
        sta     ide_to+1
        lda     #>IDE_POLLS
        sta     ide_to+2
@l:     jsr     ide_status
        and     ide_m
        cmp     ide_v
        beq     @ok
        lda     ide_to
        bne     @d0
        lda     ide_to+1
        bne     @d1
        lda     ide_to+2
        beq     @out
        dec     ide_to+2
@d1:    dec     ide_to+1
@d0:    dec     ide_to
        jmp     @l
@ok:    lda     ide_st
        clc
        rts
@out:   lda     ide_st                  ; for ?DISK ERROR $FF (CMD $xx, PORT $yy)
        sta     ch_laststs
        lda     #$FF
        sec
        rts

; ide_cmd - start command A (waits until the interface is ready for one)
; C=1 timeout.  Clobbers A, X, Y.
ide_cmd:
        sta     ch_lastcmd
        lda     #$80
        sta     ide_m
        sta     ide_v
        jsr     ide_wait
        bcs     @x
        lda     ch_lastcmd
        jmp     ide_put
@x:     rts

; ide_put - send byte A to the interface (waits until it can take it).
; C=1 timeout.  Clobbers X, Y; preserves A.
ide_put:
        pha
        lda     #$20
        sta     ide_m
        lda     #$00
        sta     ide_v
        jsr     ide_wait
        bcs     @to
        pla
        pha
        tax
        lda     #$01
        jsr     ide_tx
        pla
        clc
        rts
@to:    pla
        sec
        rts

; ide_get - A = the next byte from the interface.  C=1 timeout.
; Clobbers X, Y.
ide_get:
        lda     #$40
        sta     ide_m
        sta     ide_v
        jsr     ide_wait
        bcs     @x
        lda     #$03
        ldx     #$00
        jsr     ide_tx
        clc
@x:     rts

; ide_end - wait for the command to finish; A = its result as a CH376 code
; ($14 = fine).  Clobbers X, Y.
ide_end:
        lda     #$80
        sta     ide_m
        sta     ide_v
        jsr     ide_wait
        bcs     @x                      ; (A = $FF)
        and     #$1F                    ; interface error -> CH376-style code
        beq     @ok
        cmp     #$04
        beq     @nf
        cmp     #$0F                    ; read past the end: not an error here
        beq     @ok
        cmp     #$0B
        beq     @full
        cmp     #$0C
        beq     @full
        ora     #$E0
        rts
@ok:    lda     #USB_INT_SUCCESS
        rts
@nf:    lda     #ERR_MISS_FILE
        rts
@full:  lda     #ERR_DISK_FULL
@x:     rts

; ide_putz - send the zero-ended string at (zp_ptr), the 0 too.  C=1 timeout.
ide_putz:
        ldy     #0
@l:     lda     (zp_ptr),y
        sty     ide_t
        jsr     ide_put
        bcs     @x
        ldy     ide_t
        lda     (zp_ptr),y
        beq     @x                      ; (carry clear)
        iny
        bne     @l
@x:     rts

; ide_named - command A with the name in ide_comp; A = the result
ide_named:
        jsr     ide_cmd
        bcs     @to
        lda     #<ide_comp
        sta     zp_ptr
        lda     #>ide_comp
        sta     zp_ptr+1
        jsr     ide_putz
        bcs     @to
        jmp     ide_end
@to:    lda     #$FF
        rts

; ============================================================================
; Paths
; ============================================================================

; ide_walk - A/X = a path.  A leading "/" goes to the root; every part
; followed by "/" is entered.  The last part is left in ide_comp ("" if the
; path ends in "/").  A = $14 if all went well, else the error.
ide_walk:
        sta     strptr                  ; (zero page: free while no message prints)
        stx     strptr+1
        ldy     #0
        lda     (strptr),y
        cmp     #'/'
        bne     @part
        lda     #'/'                    ; cd "/"
        sta     ide_comp
        lda     #0
        sta     ide_comp+1
        lda     #IDE_C_CD
        jsr     ide_named
        cmp     #USB_INT_SUCCESS
        bne     @x
        ldy     #1
@part:  ldx     #0                      ; one part into ide_comp
@c:     lda     (strptr),y
        beq     @last
        cmp     #'/'
        beq     @dir
        cpx     #13
        bcs     @c2                     ; (too long: cut off)
        sta     ide_comp,x
        inx
@c2:    iny
        bne     @c
@dir:   lda     #0                      ; a directory on the way: enter it
        sta     ide_comp,x
        iny
        sty     ide_t
        cpx     #0
        beq     @skip                   ; ("//")
        lda     #IDE_C_CD
        jsr     ide_named
        cmp     #USB_INT_SUCCESS
        bne     @x
@skip:  ldy     ide_t
        jmp     @part
@last:  lda     #0
        sta     ide_comp,x
        lda     #USB_INT_SUCCESS
@x:     rts

; ============================================================================
; The CH376-like calls
; ============================================================================

; ide_prepare - mount drive 0 (once).  C=0 ready, C=1 no interface / drive.
ide_prepare:
        lda     ide_ready
        bne     @ok
        bit     spi_ok
        bpl     @no
        lda     #IDE_C_MOUNT
        jsr     ide_cmd
        bcs     @no
        lda     #0                      ; drive 0
        jsr     ide_put
        bcs     @no
        jsr     ide_end
        cmp     #USB_INT_SUCCESS
        bne     @no
        lda     #1
        sta     ide_ready
@ok:    clc
        rts
@no:    sec
        rts

; ide_open - A/X = path: open the file for reading, or enter the directory
ide_open:
        jsr     ide_walk
        cmp     #USB_INT_SUCCESS
        bne     @x
        lda     ide_comp
        beq     @dir                    ; "/" or "A/": a directory
        lda     #IDE_C_CD               ; a directory?  then we are in it now
        jsr     ide_named
        cmp     #USB_INT_SUCCESS
        beq     @dir
        cmp     #$FF
        beq     @x
        lda     #IDE_C_OPEN             ; else open the file, read only
        jsr     ide_cmd
        bcs     @to
        lda     #($10 | IDE_HANDLE)
        jsr     ide_put
        bcs     @to
        lda     #<ide_comp
        sta     zp_ptr
        lda     #>ide_comp
        sta     zp_ptr+1
        jsr     ide_putz
        bcs     @to
        jsr     ide_end
        cmp     #USB_INT_SUCCESS
        bne     @x
        lda     #IDE_C_SIZE             ; its size, for ide_read
        jsr     ide_cmd
        bcs     @to
        lda     #IDE_HANDLE
        jsr     ide_put
        bcs     @to
        ldx     #0
@s:     stx     ide_t
        jsr     ide_get
        bcs     @to
        ldx     ide_t
        sta     ide_size,x
        lda     #0
        sta     ide_pos,x
        inx
        cpx     #4
        bne     @s
        jmp     ide_end
@dir:   lda     #ERR_OPEN_DIR
        rts
@to:    lda     #$FF
@x:     rts

; ide_create - A/X = path: create or replace the file, for writing
ide_create:
        jsr     ide_walk
        cmp     #USB_INT_SUCCESS
        bne     @x
        lda     ide_comp
        beq     @dir
        lda     #IDE_C_OPEN
        jsr     ide_cmd
        bcs     @to
        lda     #($20 | IDE_HANDLE)     ; read/write: replaces a file
        jsr     ide_put
        bcs     @to
        lda     #<ide_comp
        sta     zp_ptr
        lda     #>ide_comp
        sta     zp_ptr+1
        jsr     ide_putz
        bcs     @to
        jmp     ide_end
@dir:   lda     #ERR_OPEN_DIR
        rts
@to:    lda     #$FF
@x:     rts

; ide_erase - A/X = path: delete the file
ide_erase:
.if IDE_C_DELETE
        jsr     ide_walk
        cmp     #USB_INT_SUCCESS
        bne     @x
        lda     ide_comp
        beq     @dir
        lda     #IDE_C_DELETE
        jmp     ide_named
@dir:   lda     #ERR_OPEN_DIR
@x:     rts
.else
        lda     #$FD
        rts
.endif

; ide_close - close the file (A, the CH376's "update the length" flag, is not
; needed)
ide_close:
        lda     #IDE_C_CLOSE
        jsr     ide_cmd
        bcs     @to
        lda     #IDE_HANDLE
        jsr     ide_put
        bcs     @to
        jmp     ide_end
@to:    lda     #$FF
        rts

; ide_count - send the 4-byte count ide_n (16 bit) after command A + handle
ide_count:
        jsr     ide_cmd
        bcs     @to
        lda     #IDE_HANDLE
        jsr     ide_put
        bcs     @to
        lda     ide_n
        jsr     ide_put
        bcs     @to
        lda     ide_n+1
        jsr     ide_put
        bcs     @to
        lda     #0
        jsr     ide_put
        bcs     @to
        lda     #0
        jsr     ide_put
@to:    rts

; ide_read - read up to ch_len bytes into (ch_ptr); ch_got = how many there
; were (the rest of the file, or ch_len); ch_ptr advanced
ide_read:
        lda     #0
        sta     ch_got
        sta     ch_got+1
        sec                             ; what is left: size - pos
        lda     ide_size
        sbc     ide_pos
        sta     ide_n
        lda     ide_size+1
        sbc     ide_pos+1
        sta     ide_n+1
        lda     ide_size+2
        sbc     ide_pos+2
        tax
        lda     ide_size+3
        sbc     ide_pos+3
        bcs     :+
        jmp     @none                   ; (past the end)
:       bne     @len                    ; 16 MB or more left: ch_len
        txa
        bne     @len                    ; 64K or more left: ch_len
        lda     ide_n+1                 ; less than ch_len left?
        cmp     ch_len+1
        bcc     @go
        bne     @len
        lda     ide_n
        cmp     ch_len
        bcc     @go
@len:   lda     ch_len
        sta     ide_n
        lda     ch_len+1
        sta     ide_n+1
@go:    lda     ide_n
        ora     ide_n+1
        bne     :+
        jmp     @none
:
        lda     ide_n                   ; ch_got = count; pos += count
        sta     ch_got
        lda     ide_n+1
        sta     ch_got+1
        clc
        lda     ide_pos
        adc     ide_n
        sta     ide_pos
        lda     ide_pos+1
        adc     ide_n+1
        sta     ide_pos+1
        bcc     :+
        inc     ide_pos+2
        bne     :+
        inc     ide_pos+3
:       lda     #IDE_C_READ
        jsr     ide_count
        bcs     @to
        ZP_ENTER
        ldy     #0
@b:     sty     ide_t
        jsr     ide_get
        bcs     @to2
        ldy     ide_t
        sta     (zp_ptr),y
        iny
        bne     :+
        inc     zp_ptr+1
:       lda     ide_n
        bne     :+
        dec     ide_n+1
:       dec     ide_n
        lda     ide_n
        ora     ide_n+1
        bne     @b
        tya                             ; zp_ptr += the last partial page
        clc
        adc     zp_ptr
        sta     zp_ptr
        bcc     :+
        inc     zp_ptr+1
:       ZP_LEAVE
        jmp     ide_end
@to2:   ZP_LEAVE
@to:    lda     #$FF
        rts
@none:  lda     #USB_INT_SUCCESS
        rts

; ide_write - write ch_len bytes from (ch_ptr)
ide_write:
        lda     ch_len
        sta     ide_n
        lda     ch_len+1
        sta     ide_n+1
        ora     ide_n
        beq     @ok
        lda     #IDE_C_WRITE
        jsr     ide_count
        bcs     @to
        ZP_ENTER
        ldy     #0
@b:     lda     (zp_ptr),y
        sty     ide_t
        jsr     ide_put
        bcs     @to2
        ldy     ide_t
        iny
        bne     :+
        inc     zp_ptr+1
:       lda     ide_n
        bne     :+
        dec     ide_n+1
:       dec     ide_n
        lda     ide_n
        ora     ide_n+1
        bne     @b
        tya
        clc
        adc     zp_ptr
        sta     zp_ptr
        bcc     :+
        inc     zp_ptr+1
:       ZP_LEAVE
        jmp     ide_end
@to2:   ZP_LEAVE
@to:    lda     #$FF
        rts
@ok:    lda     #USB_INT_SUCCESS
        rts

; ide_dirlist - list the directory named by ch_name ("/*", "*", "/A/*", or
; with a pattern after the last "/" - the interface lists everything)
ide_dirlist:
        jsr     ide_prepare
        bcc     :+
        lda     #CH_E_NODISK
        jmp     ch_fail
:       lda     #<ch_name
        ldx     #>ch_name
        jsr     ide_walk
        cmp     #USB_INT_SUCCESS
        bne     @fail
        lda     #IDE_C_DIR
        jsr     ide_cmd
        bcs     @to
@c:     jsr     ide_get
        bcs     @to
        cmp     #0
        beq     @end
        jsr     ch_putc
        jmp     @c
@end:   jsr     ide_end
        cmp     #USB_INT_SUCCESS
        bne     @fail
        rts
@to:    lda     #$FF
@fail:  jmp     ch_fail

; ============================================================================
; The DS1302 clock on the interface
; ============================================================================

; ide_time - A/Y = a buffer of 18 bytes: "mm/dd/yy hh:mm:ss",0.
; C=1 if the interface didn't answer.
ide_time:
        sta     zp_ptr
        sty     zp_ptr+1
        bit     spi_ok
        bpl     @no
        lda     #IDE_C_GETTIME
        jsr     ide_cmd
        bcs     @no
        ldy     #0
@c:     sty     ide_t
        jsr     ide_get
        bcs     @no
        ldy     ide_t
        cpy     #17
        bcs     :+
        sta     (zp_ptr),y
:       iny
        cmp     #0
        bne     @c
        ldy     #17
        lda     #0
        sta     (zp_ptr),y
        jsr     ide_end
        clc
        rts
@no:    sec
        rts

; ide_settime - A/Y = 14 characters "dwyymmddHHMMSS" (dw: 01 = Sunday)
; C=1 if the interface didn't answer.
ide_settime:
        sta     zp_ptr
        sty     zp_ptr+1
        bit     spi_ok
        bpl     @no
        lda     #IDE_C_SETTIME
        jsr     ide_cmd
        bcs     @no
        ldy     #0
@c:     lda     (zp_ptr),y
        sty     ide_t
        jsr     ide_put
        bcs     @no
        ldy     ide_t
        iny
        cpy     #14
        bne     @c
        jsr     ide_end
        clc
        rts
@no:    sec
        rts
