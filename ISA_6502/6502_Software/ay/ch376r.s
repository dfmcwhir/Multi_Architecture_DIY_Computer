; ============================================================================
; ch376r.s - reading files from the USB drive through the CH376 (parallel
; mode, at $7F20 data / $7F21 command and status), for programs loaded from
; the monitor: start the chip, list a directory, open, read, seek, close.
; The same protocol as the firmware's driver (ch376_abs.s), cut down to
; reading.  Every wait has a time-out, so a missing drive can't hang it.
;
;   ch_check    is the chip there?  carry set if not
;   ch_start    check the chip, USB host mode, mount the drive: carry set =
;               failed (A = what failed: 1 no chip, 2 mode, 3 no drive).  This
;               starts the drive afresh, in its top folder.
;   ch_open     open the file whose 0-ended name is at A/Y: "NAME.EXT" in the
;               current folder, "/NAME.EXT" in the top one: A = the CH376
;               status ($14 = open, $42 = not found)
;   ch_read     read ch_len bytes to (ch_ptr): A = $14 when done, ch_got =
;               bytes read (fewer at the end of the file)
;   ch_seek     to the 32 bit offset in ch_off
;   ch_close    close the open file
; With CH_WRITE defined, also writing:
;   ch_create   make the file whose 0-ended name is at A/Y (emptied if it is
;               there), open for writing: A = the status ($14 = made)
;   ch_write    write ch_len bytes from (ch_ptr): A = $14 when done
;   ch_close_w  close it, with its length kept
;   ch_dir      list the files that match the 0-ended name at A/Y ("/*": the
;               top folder, "*": the current one): calls (ch_entry_fn) for
;               each, with the 32 byte FAT entry in ch_ent (0-7 name, 8-10
;               extension, 11 attributes, 28-31 size).  A = $42 when it has
;               listed them all, or the status that stopped it (no drive ...)
;   ch_enter    make the folder whose 0-ended path is at A/Y ("" the top,
;               "/A" or "/A/B") the current one, a level at a time: "/A",
;               then "B".  A = $41 (ERR_OPEN_DIR) when it is in, else the
;               status that stopped it ($42: a folder isn't there)
;
; The current folder: the CH376 keeps the last folder opened as its current
; one, and names without a "/" are found there.  It isn't kept for long:
; opening a file leaves the chip with no current folder that works, so enter
; the folder again before each relative name (as the monitor does).
; ============================================================================

CH_DATA         = $7F20
CH_CMD          = $7F21

CMD_CHECK_EXIST = $06
CMD_SET_USB_MODE= $15
CMD_GET_STATUS  = $22
CMD_RD_USB_DATA0= $27
CMD_SET_FILE_NAME = $2F
CMD_DISK_CONNECT= $30
CMD_DISK_MOUNT  = $31
CMD_FILE_OPEN   = $32
CMD_FILE_ENUM_GO= $33
CMD_FILE_CLOSE  = $36
CMD_BYTE_LOCATE = $39
CMD_BYTE_READ   = $3A
CMD_BYTE_RD_GO  = $3B
CMD_WR_REQ_DATA = $2D
CMD_FILE_CREATE = $34
CMD_BYTE_WRITE  = $3C
CMD_BYTE_WR_GO  = $3D
USB_INT_DISK_WRITE = $1E

USB_INT_SUCCESS = $14
USB_INT_DISK_READ = $1D
ERR_OPEN_DIR    = $41
ERR_MISS_FILE   = $42
CMD_RET_SUCCESS = $51

; wait while the chip is busy (status bit 4), at most ~100 ms.  Keeps X, Y.
ch_wait_busy:
        lda     CH_CMD
        and     #$10
        beq     @r
        txa
        pha
        tya
        pha
        ldy     #CH_BUSY_OUTER
        ldx     #0
@l:     lda     CH_CMD
        and     #$10
        beq     @ok
        dex
        bne     @l
        dey
        bne     @l
@ok:    pla
        tay
        pla
        tax
@r:     rts
CH_BUSY_OUTER = (CLOCK_MHZ * 100000) / 3333 / 10 + 1     ; 256 x 13 cycles a turn

; a command (A).  Keeps X, Y.
ch_cmd: pha
        jsr     ch_wait_busy
        pla
        sta     CH_CMD
        nop                     ; (the chip wants ~1.5 us before the next access)
        nop
        nop
        nop
        rts

; a data byte (A) to the chip.  Keeps X, Y.
ch_wr:  pha
        jsr     ch_wait_busy
        pla
        sta     CH_DATA
        rts

; a data byte from the chip, in A.  Keeps X, Y.
ch_rd:  jsr     ch_wait_busy
        lda     CH_DATA
        rts

; wait for the chip's interrupt (status bit 7 low), at most ~3 s: carry set
; if it never came.  Keeps X, Y.
ch_wait_int:
        txa
        pha
        tya
        pha
        lda     #CH_INT_OUTER
        sta     ch_tmo
        ldy     #0
        ldx     #0
@l:     lda     CH_CMD
        bpl     @got
        inx
        bne     @l
        iny
        bne     @l
        dec     ch_tmo
        bne     @l
        pla
        tay
        pla
        tax
        sec
        rts
@got:   pla
        tay
        pla
        tax
        clc
        rts
CH_INT_OUTER = (CLOCK_MHZ * 3) * 1000000 / 786000 + 1    ; 65536 x 12 cycles a turn

; the interrupt's status in A (and the interrupt cleared); $FF and carry set
; on a time-out.  Keeps X, Y.
ch_status:
        jsr     ch_wait_int
        bcs     @t
        lda     #CMD_GET_STATUS
        jsr     ch_cmd
        jmp     ch_rd
@t:     lda     #$FF
        rts

; ---- is the chip there?  (carry set if not) -------------------------------------------
ch_check:
        lda     #CMD_CHECK_EXIST
        jsr     ch_cmd
        lda     #$55
        jsr     ch_wr
        jsr     ch_rd
        cmp     #$AA
        beq     @ok
        sec
        rts
@ok:    clc
        rts

; ---- start: check the chip, USB host mode, mount --------------------------------------
ch_start:
        lda     #CMD_CHECK_EXIST
        jsr     ch_cmd
        lda     #$55
        jsr     ch_wr
        jsr     ch_rd
        cmp     #$AA
        beq     @mode
        lda     #1              ; no chip
        sec
        rts
@mode:  lda     #CMD_SET_USB_MODE
        jsr     ch_cmd
        lda     #6              ; USB host, generate SOF
        jsr     ch_wr
        lda     #1
        jsr     delay_ms
        jsr     ch_rd
        cmp     #CMD_RET_SUCCESS
        beq     @m0
        lda     #2
        sec
        rts
@m0:    lda     #20             ; (a "drive connected" interrupt may come:
        jsr     delay_ms        ;  clear it)
        lda     CH_CMD
        bmi     @mnt
        lda     #CMD_GET_STATUS
        jsr     ch_cmd
        jsr     ch_rd
@mnt:   lda     #5              ; mount: up to 5 tries
        sta     ch_try
@m1:    lda     #CMD_DISK_CONNECT
        jsr     ch_cmd
        jsr     ch_status
        lda     #CMD_DISK_MOUNT
        jsr     ch_cmd
        jsr     ch_status
        cmp     #USB_INT_SUCCESS
        beq     @ok
        lda     #200
        jsr     delay_ms
        dec     ch_try
        bne     @m1
        lda     #3              ; no drive
        sec
        rts
@ok:    clc
        rts

; the file name: the 0-ended string at A/Y
ch_name:
        sta     @ld+1
        sty     @ld+2
        lda     #CMD_SET_FILE_NAME
        jsr     ch_cmd
        ldx     #0
@l:
@ld:    lda     $FFFF,x
        jsr     ch_wr
        beq     @r
        inx
        cpx     #14
        bne     @l
        lda     #0
        jsr     ch_wr
@r:     rts

ch_open:
        jsr     ch_name
        lda     #CMD_FILE_OPEN
        jsr     ch_cmd
        jmp     ch_status

ch_close:
        lda     #CMD_FILE_CLOSE
        jsr     ch_cmd
        lda     #0              ; (no length update: read only)
        jsr     ch_wr
        jmp     ch_status

.ifdef CH_WRITE
ch_create:
        jsr     ch_name
        lda     #CMD_FILE_CREATE
        jsr     ch_cmd
        jmp     ch_status

ch_close_w:
        lda     #CMD_FILE_CLOSE
        jsr     ch_cmd
        lda     #1              ; (the length kept)
        jsr     ch_wr
        jmp     ch_status

; write ch_len bytes from (ch_ptr), in the chunks the chip asks for
ch_write:
        lda     ch_ptr
        sta     @ld+1
        lda     ch_ptr+1
        sta     @ld+2
        lda     #CMD_BYTE_WRITE
        jsr     ch_cmd
        lda     ch_len
        jsr     ch_wr
        lda     ch_len+1
        jsr     ch_wr
@next:  jsr     ch_status
        cmp     #USB_INT_DISK_WRITE
        bne     @done           ; $14: all of it
        lda     #CMD_WR_REQ_DATA
        jsr     ch_cmd
        jsr     ch_rd           ; how many it takes
        sta     ch_cnt
        beq     @go
        ldy     #0
@ld:    lda     $FFFF
        jsr     ch_wr
        inc     @ld+1
        bne     :+
        inc     @ld+2
:       iny
        cpy     ch_cnt
        bne     @ld
@go:    lda     #CMD_BYTE_WR_GO
        jsr     ch_cmd
        jmp     @next
@done:  rts
.endif

ch_seek:
        lda     #CMD_BYTE_LOCATE
        jsr     ch_cmd
        ldx     #0
@l:     lda     ch_off,x
        jsr     ch_wr
        inx
        cpx     #4
        bne     @l
        jmp     ch_status

; read ch_len (up to 65535) bytes to (ch_ptr): in chunks of up to 64 the chip
; hands over
ch_read:
        lda     #0
        sta     ch_got
        sta     ch_got+1
        lda     ch_ptr
        sta     @st+1
        lda     ch_ptr+1
        sta     @st+2
        lda     #CMD_BYTE_READ
        jsr     ch_cmd
        lda     ch_len
        jsr     ch_wr
        lda     ch_len+1
        jsr     ch_wr
@next:  jsr     ch_status
        cmp     #USB_INT_DISK_READ
        bne     @done           ; $14: all of it (or the end of the file)
        lda     #CMD_RD_USB_DATA0
        jsr     ch_cmd
        jsr     ch_rd           ; how many
        sta     ch_cnt
        beq     @go
        ldy     #0
@c:     jsr     ch_rd
@st:    sta     $FFFF
        inc     @st+1
        bne     @c1
        inc     @st+2
@c1:    iny
        cpy     ch_cnt
        bne     @c
        lda     ch_got
        clc
        adc     ch_cnt
        sta     ch_got
        bcc     @go
        inc     ch_got+1
@go:    lda     #CMD_BYTE_RD_GO
        jsr     ch_cmd
        jmp     @next
@done:  rts

; list the files matching the name at A/Y: (ch_entry_fn) for each entry
; (ch_ent); A = $42 at the end, or an error status
ch_dir: jsr     ch_name
        lda     #CMD_FILE_OPEN
        jsr     ch_cmd
@next:  jsr     ch_status
        cmp     #USB_INT_DISK_READ
        bne     @r
        lda     #CMD_RD_USB_DATA0
        jsr     ch_cmd
        jsr     ch_rd
        sta     ch_cnt
        ldy     #0
@rd:    cpy     ch_cnt
        bcs     @got
        jsr     ch_rd
        cpy     #32
        bcs     @sk
        sta     ch_ent,y
@sk:    iny
        bne     @rd
@got:   lda     ch_cnt
        cmp     #32
        bcc     @more
        jsr     @call
@more:  lda     #CMD_FILE_ENUM_GO
        jsr     ch_cmd
        jmp     @next
@r:     rts
@call:  jmp     (ch_entry_fn)

; enter the folder whose path is at A/Y ("" / "/A" / "/A/B"), a level at a
; time; A = $41 when in it
ch_enter:
        sta     ce_get+1
        sty     ce_get+2
        ldy     #0
@part:  ldx     #0              ; the next part: "/A" the first time, then "B"
        jsr     ce_get
        beq     @in             ; (the end of the path)
        cpy     #0
        bne     @skip
        sta     ch_part         ; (only the first keeps its "/")
        inx
@skip:  iny
@cp:    jsr     ce_get
        beq     @end
        cmp     #'/'
        beq     @end
        sta     ch_part,x
        inx
        iny
        cpx     #14
        bcc     @cp
@end:   lda     #0
        sta     ch_part,x
        sty     ch_py           ; (where we are in the path)
        lda     #<ch_part
        ldy     #>ch_part
        jsr     ch_open
        ldy     ch_py
        cmp     #ERR_OPEN_DIR
        bne     @r              ; not a folder (or not there)
        jsr     ce_get          ; more?
        bne     @part
@in:    lda     #ERR_OPEN_DIR
@r:     rts
ce_get: lda     $FFFF,y         ; (the path's next character)
        rts

        .segment "BSS"
ch_ptr:     .res 2
ch_len:     .res 2
ch_got:     .res 2
ch_cnt:     .res 1
ch_off:     .res 4
ch_tmo:     .res 1
ch_try:     .res 1
ch_entry_fn:.res 2
ch_ent:     .res 32
ch_part:    .res 16             ; (ch_enter: one part of a path,
ch_py:      .res 1              ;  and where it is in the path)
        .segment "CODE"
