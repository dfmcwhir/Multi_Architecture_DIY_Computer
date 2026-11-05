; ============================================================================
; ymplay.s - YMPLAY: plays chip music from the USB drive on the AY-3-8910 card
;
;   build:  make.bat  (or make)        run:  L YMPLAY 0500   then   R
;
; The songs are .AYS files: .YM files converted on the PC by tools\ym2ays.py
; (the .YM format is packed and needs more RAM to unpack than the SBC has).
; YMPLAY lists the .AYS files in the monitor's current folder (its L command
; changes folders), which it asks the ROM for: SBC_CWD ($FE18) gives the path
; ("" for the top folder, "/MUSIC", "/A/B").  A ROM without SBC_CWD: the top
; folder.  The folder is entered a level at a time before the list and before
; each song (the CH376 forgets its current folder when a file is opened).
; YMPLAY uses the drive as the monitor left it, and starts it afresh only if
; that doesn't work.
;
; The song list:  W/S (or up/down on the gamepad) choose, a number picks one
;                 directly, space/Enter (pad A) plays, Q quits.
; Playing:        space (pad A) pause, N or D (pad right) next song,
;                 A or P (pad left) previous song, L or W (pad up) loop the
;                 song on/off, V the level bars on/off, S or Esc (pad down)
;                 back to the list, Q quits.
; Without looping, the next song starts when one ends.
;
; How it plays: the song is read from the drive into a 4 KB ring buffer, a
; 64 byte block at a time, between frames, while the frames are played from
; the other end; VIA timer 2, polled (its interrupt stays off), times the
; frames (50 a second for most songs).  Timer 1 and the gamepad aren't
; touched.
;
; The level bars: one for each channel, from the registers as they are
; written (there is no sound to measure): the volume, or for a channel on the
; envelope, the envelope's level, worked out from its shape and period.  A bar
; jumps up and falls back slowly, with a peak mark that waits, then falls.
; Only the cells that changed are sent, a few a frame (fewer the more frames a
; second), so the terminal keeps up and the frames stay on time.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

VIA_T2CL        = $7F08
VIA_T2CH        = $7F09
VIA_ACR         = $7F0B
VIA_IFR         = $7F0D
VIA_IER         = $7F0E

RING            = $6000         ; the ring buffer, $6000-$6FFF
RING_END        = $7000
RING_SIZE       = RING_END - RING
MAX_SONGS       = 60
CWD_MAX         = 31            ; the longest path (the monitor's too)
.ifndef SBC_CWD
SBC_CWD         = $FE18         ; (newer ROMs: A/Y = the monitor's current folder)
.endif

        .segment "CODE"
        jmp     start

        .include "common.s"
        .include "ay.s"
        .include "ch376r.s"

; ---- start ---------------------------------------------------------------------------
start:  cld
        ldx     #$FF
        txs
        jsr     ay_silence
        lda     VIA_ACR         ; timer 2: one shot (the count down mode)
        and     #$DF
        sta     VIA_ACR
        lda     #$20            ; and its interrupt off
        sta     VIA_IER
        PRINT   hello_txt
        lda     #0              ; the monitor's current folder (from the ROM:
        sta     cwd_buf         ; SBC_CWD; without it, the top folder)
        lda     SBC_CWD
        cmp     #$4C            ; (a JMP there?)
        bne     @nocwd
        jsr     SBC_CWD
        sta     @cw+1
        sty     @cw+2
        ldx     #0
@cw:    lda     $FFFF,x
        sta     cwd_buf,x
        beq     @nocwd
        inx
        cpx     #CWD_MAX
        bcc     @cw
        lda     #0              ; (too long: the top folder)
        sta     cwd_buf
@nocwd: jsr     ch_check        ; the chip?
        lda     #1
        bcs     @err
        jsr     list_dir        ; the songs in the current folder
        cmp     #ERR_MISS_FILE  ; (listed to the end: the drive was ready)
        beq     @got
        jsr     ch_start        ; not ready: start it, in the top folder
        bcc     @dir
@err:   pha
        PRINT   err_txt
        pla
        asl
        tax
        lda     start_errs-2,x
        ldy     start_errs-1,x
        jsr     print
        jmp     bye_key
@dir:   jsr     list_dir
@got:   lda     nsongs
        bne     @have
        PRINT   none_txt
        jsr     show_cwd
        PRINT   none2_txt
        jmp     bye_key
@have:  lda     #0
        sta     sel
        sta     loop_on
        sta     scr_up
        lda     #1              ; the bars on
        sta     vis_on

; ---- the song list ---------------------------------------------------------------------
list:   jsr     ay_silence
        PRINT   list_txt
        jsr     show_cwd
        PRINT   colon_txt
        ldx     #0              ; 4 to a line: "nn NAME.EXT   "
@l:     stx     idx
        txa
        clc
        adc     #1
        jsr     prdec2
        lda     #' '
        jsr     SBC_CHROUT
        ldx     idx
        jsr     song_name
        PRINT   name_buf
        ldx     name_len        ; pad to 16
@p:     cpx     #14
        bcs     @pd
        lda     #' '
        jsr     SBC_CHROUT
        inx
        bne     @p
@pd:    ldx     idx
        inx
        txa
        and     #3
        bne     @nl
        jsr     crlf
@nl:    cpx     nsongs
        bne     @l
        txa
        and     #3
        beq     @h
        jsr     crlf
@h:     PRINT   keys_txt
        lda     #0
        sta     digits
@show:  jsr     show_sel
@k:     jsr     waitkey
        cmp     #'Q'
        bne     @k1
        jmp     bye
@k1:    cmp     #'W'
        bne     @k2
        lda     sel             ; up
        beq     @k
        dec     sel
        jmp     @show0
@k2:    cmp     #'S'
        bne     @k3
        ldx     sel             ; down
        inx
        cpx     nsongs
        bcs     @k
        stx     sel
        jmp     @show0
@k3:    cmp     #' '
        beq     @play
        cmp     #13
        beq     @play
        cmp     #'0'            ; a digit: the number so far x 10 + it
        bcc     @k
        cmp     #'9' + 1
        bcs     @k
        and     #$0F
        sta     tmp
        lda     digits
        cmp     #10             ; (a third digit starts again)
        bcc     @d1
        lda     #0
@d1:    asl
        sta     tmp2
        asl
        asl
        adc     tmp2
        adc     tmp
        sta     digits
        beq     @k
        cmp     nsongs
        beq     @d2
        bcs     @k
@d2:    sec
        sbc     #1
        sta     sel
        jmp     @show
@show0: lda     #0
        sta     digits
        jmp     @show
@play:  jsr     crlf
        jmp     play_sel

; the selection line: "> nn NAME.EXT" over the last one
show_sel:
        lda     #13
        jsr     SBC_CHROUT
        PRINT   sel_txt
        lda     sel
        clc
        adc     #1
        jsr     prdec2
        lda     #' '
        jsr     SBC_CHROUT
        ldx     sel
        jsr     song_name
        PRINT   name_buf
        PRINT   spaces_txt
        rts

; the .AYS files in the folder (cwd_buf) into songs, nsongs; A = $42 when
; listed to the end, else the status that stopped it
list_dir:
        lda     #0
        sta     nsongs
        lda     #<add_song
        sta     ch_entry_fn
        lda     #>add_song
        sta     ch_entry_fn+1
        jsr     enter_cwd
        bne     @r
        lda     #<star_txt      ; "*" in it ("/*": the top folder)
        ldy     #>star_txt
        ldx     cwd_buf
        bne     @d
        lda     #<rstar_txt
        ldy     #>rstar_txt
@d:     jmp     ch_dir
@r:     rts

; into the folder cwd_buf: Z set if all went well, else A = the status
enter_cwd:
        lda     #<cwd_buf
        ldy     #>cwd_buf
        jsr     ch_enter
        cmp     #ERR_OPEN_DIR
        rts

; "SONGS IN /MUSIC:"
show_cwd:
        lda     cwd_buf
        bne     @p
        lda     #'/'
        jmp     SBC_CHROUT
@p:     PRINT   cwd_buf
        rts

; A FAT entry from the directory: keep it if it is an .AYS file
add_song:
        lda     ch_ent+11       ; not a folder or the volume name
        and     #$18
        bne     @r
        lda     ch_ent
        beq     @r
        cmp     #$E5            ; (deleted)
        beq     @r
        lda     ch_ent+8
        cmp     #'A'
        bne     @r
        lda     ch_ent+9
        cmp     #'Y'
        bne     @r
        lda     ch_ent+10
        cmp     #'S'
        bne     @r
        lda     nsongs
        cmp     #MAX_SONGS
        bcs     @r
        jsr     song_addr
        sta     @st+1
        sty     @st+2
        ldy     #7
@c:     lda     ch_ent,y
@st:    sta     $FFFF,y
        dey
        bpl     @c
        inc     nsongs
@r:     rts

; A/Y = where the 8 byte name of song A is
song_addr:
        ldy     #0
        sty     tmp2
        asl                     ; x 8
        rol     tmp2
        asl
        rol     tmp2
        asl
        rol     tmp2
        clc
        adc     #<songs
        pha
        lda     tmp2
        adc     #>songs
        tay
        pla
        rts

; name_buf = "NAME.AYS" of song X (path_buf = "/NAME.AYS"); name_len = length
song_name:
        txa
        jsr     song_addr
        sta     @ld+1
        sty     @ld+2
        ldy     #0
        ldx     #1
@c:
@ld:    lda     $FFFF,y
        cmp     #' '
        beq     @e
        sta     path_buf,x
        inx
        iny
        cpy     #8
        bne     @c
@e:     ldy     #0
@x:     lda     ays_ext,y
        sta     path_buf,x
        inx
        iny
        cpy     #5
        bne     @x
        lda     #'/'
        sta     path_buf
        dex
        dex
        stx     name_len
        rts

bye_key:
        PRINT   anykey_txt
        jsr     waitkey
bye:    jsr     ay_silence
        lda     playing
        beq     @b
        jsr     stop_file
@b:     PRINT   bye_txt
        jmp     SBC_MENU

; ---- playing a song ---------------------------------------------------------------------
play_sel:
        lda     #0
        sta     playing
play_again:
        jsr     ay_silence
        jsr     to_msg          ; (below the last song's screen)
        ldx     sel
        jsr     song_name
        PRINT   playing_txt
        PRINT   name_buf
        jsr     crlf
        jsr     enter_cwd       ; into its folder again
        bne     @nop
        lda     #<name_buf      ; in it: no "/" (the top folder: "/NAME.AYS")
        ldy     #>name_buf
        ldx     cwd_buf
        bne     @o
        lda     #<path_buf
        ldy     #>path_buf
@o:     jsr     ch_open
@nop:
        cmp     #USB_INT_SUCCESS
        beq     @op
        jsr     prhex
        PRINT   open_err_txt
        jmp     song_over
@op:    inc     playing
        lda     #<hdr           ; the 128 byte header
        sta     ch_ptr
        lda     #>hdr
        sta     ch_ptr+1
        lda     #128
        sta     ch_len
        lda     #0
        sta     ch_len+1
        jsr     ch_read
        lda     ch_got
        cmp     #128
        bne     @bad
        ldx     #3
@sig:   lda     hdr,x
        cmp     ays_sig,x
        bne     @bad
        dex
        bpl     @sig
        lda     hdr+4           ; frames a second
        beq     @bad
        lda     hdr+6           ; any frames?
        ora     hdr+7
        ora     hdr+8
        ora     hdr+9
        bne     @ok
@bad:   PRINT   bad_txt
        jsr     stop_file
        jmp     song_over

@ok:    jsr     timer_setup
        jsr     vis_song
        jsr     draw_screen
        ; the reader: from the first frame, nframes x 14 bytes to go
        ldx     #3
@n:     lda     hdr+6,x
        sta     acc,x
        dex
        bpl     @n
        jsr     mul14
        ldx     #3
@n2:    lda     acc,x
        sta     rd_left,x
        lda     #0
        sta     play_frame,x
        dex
        bpl     @n2
        lda     #<RING
        sta     wr_ptr
        sta     rp_ptr
        lda     #>RING
        sta     wr_ptr+1
        sta     rp_ptr+1
        lda     #0
        sta     fill
        sta     fill+1
        sta     rd_state        ; idle
        sta     rd_err
        sta     paused
        sta     secs
        sta     secs+1
        sta     sec_frames
        ldx     #8              ; fill the buffer a bit before starting
@pre:   jsr     reader
        jsr     reader
        dex
        bne     @pre
        jsr     show_time
        jsr     timer_start

; once a frame: wait for the timer, write the registers, read ahead, keys
frame:  jsr     timer_wait
        lda     paused
        bne     @keys
        lda     fill+1          ; a whole frame in the buffer?
        bne     @play
        lda     fill
        cmp     #14
        bcs     @play
        lda     rd_state        ; no: the end of the data (or an error)?
        cmp     #RS_STOP
        bne     :+
        jmp     @end
:
        jmp     @read           ; (or not here yet: wait)
@play:  jsr     play_frame_regs
        jsr     count_time
        ldx     #3              ; the end of the song?
@e:     lda     play_frame,x
        cmp     hdr+6,x
        bne     @read
        dex
        bpl     @e
        lda     loop_on
        bne     :+
        jmp     @end
:
        ldx     #3              ; looping: from the loop frame (the reader
@lp:    lda     hdr+10,x        ; has gone back there too)
        sta     play_frame,x
        dex
        bpl     @lp
@read:  jsr     reader          ; read ahead: a block of 64 a frame, 2 when
        lda     fill+1          ; the buffer is under half full
        cmp     #>(RING_SIZE / 2)
        bcs     @keys
        jsr     reader
@keys:  jsr     vis_tick        ; the bars
        jsr     getkey
        bcs     @key
        jmp     frame
@key:
        cmp     #' '
        beq     @pause
        cmp     #'N'
        bne     :+
        jmp     @next
:
        cmp     #'D'
        bne     :+
        jmp     @next
:
        cmp     #'A'
        beq     @prev
        cmp     #'P'
        beq     @prev
        cmp     #'L'
        beq     @loop
        cmp     #'W'
        beq     @loop
        cmp     #'S'
        beq     @list
        cmp     #27
        beq     @list
        cmp     #'Q'
        beq     @quit
        cmp     #'V'
        bne     :+
        jmp     @vis
:       jmp     frame
@quit:  jmp     bye
@pause: lda     paused
        eor     #1
        sta     paused
        beq     @res
        jsr     quiet
        ldx     #15
        ldy     #TIME_ROW
        jsr     goto
        PRINT   pause_txt
        jmp     frame
@res:   jsr     show_time
        jmp     frame
@loop:  lda     loop_on
        eor     #1
        sta     loop_on
        jsr     show_time
        jmp     frame
@vis:   lda     vis_on          ; the bars on/off
        eor     #1
        sta     vis_on
        jsr     draw_screen
        jmp     frame
@list:  jsr     stop_file
        jsr     crlf
        jmp     list
@prev:  jsr     stop_file
        jsr     crlf
        lda     sel
        bne     @p1
        lda     nsongs
@p1:    sec
        sbc     #1
        sta     sel
        jmp     play_again
@end:   jsr     stop_file
        lda     rd_err
        beq     @next1
        jsr     to_msg
        PRINT   read_err_txt
        jmp     @next1
@next:  jsr     stop_file
@next1: jsr     crlf
song_over:
        ldx     sel             ; the next song (after the last: the first)
        inx
        cpx     nsongs
        bcc     @s
        ldx     #0
@s:     stx     sel
        jmp     play_again

; volumes to 0 (a pause)
quiet:  lda     #0
        ldx     #AY_VOL_A
        jsr     ay_write
        inx
        jsr     ay_write
        inx
        jmp     ay_write

; stop: silence, and close the file (first clearing an interrupt the reader
; may have left waiting)
stop_file:
        jsr     ay_silence
        lda     playing
        beq     @r
        lda     #0
        sta     playing
        lda     CH_CMD
        bmi     @c
        lda     #CMD_GET_STATUS
        jsr     ch_cmd
        jsr     ch_rd
@c:     jsr     ch_close
@r:     rts

; the registers of the next frame from the ring buffer to the card (register
; 13 skipped when it is $FF); fill -= 14, play_frame += 1
play_frame_regs:
        lda     rp_ptr
        sta     @ld+1
        lda     rp_ptr+1
        sta     @ld+2
        ldx     #0
@l:
@ld:    lda     $FFFF
        inc     @ld+1
        bne     @w
        ldy     @ld+2
        iny
        cpy     #>RING_END
        bne     @hi
        ldy     #>RING
@hi:    sty     @ld+2
@w:     cpx     #AY_ENV_SHAPE
        bne     @o
        cmp     #$FF
        beq     @n
        inc     env_new         ; (the envelope starts again)
@o:     sta     regs,x          ; (a copy, for the bars)
        stx     AY_ADDR
        sta     AY_DATA
@n:     inx
        cpx     #14
        bne     @l
        lda     @ld+1
        sta     rp_ptr
        lda     @ld+2
        sta     rp_ptr+1
        lda     fill
        sec
        sbc     #14
        sta     fill
        bcs     @f
        dec     fill+1
@f:     inc     play_frame
        bne     @r
        inc     play_frame+1
        bne     @r
        inc     play_frame+2
        bne     @r
        inc     play_frame+3
@r:     rts

; ---- the reader: a step at a time, never waiting for the drive ------------------------
RS_IDLE = 0                     ; no read going: start one (or seek back, or stop)
RS_READ = 1                     ; a BYTE_READ going: take its blocks as they come
RS_STOP = 2                     ; all read (or an error)

reader: lda     rd_state
        beq     @idle
        cmp     #RS_READ
        bne     :+
        jmp     @read
:
        rts
@idle:  lda     rd_left         ; anything left to read?
        ora     rd_left+1
        ora     rd_left+2
        ora     rd_left+3
        bne     @req
        lda     loop_on         ; no: back to the loop frame (if looping:
        bne     @seek           ; it may be turned on later)
        rts
@seek:  ldx     #3              ; offset 128 + loop x 14
@s1:    lda     hdr+10,x
        sta     acc,x
        dex
        bpl     @s1
        jsr     mul14
        lda     acc
        clc
        adc     #128
        sta     ch_off
        ldx     #1
        ldy     #3              ; (counted in Y: CPX would upset the carry)
@s2:    lda     acc,x
        adc     #0
        sta     ch_off,x
        inx
        dey
        bne     @s2
        jsr     ch_seek
        cmp     #USB_INT_SUCCESS
        bne     @err
        ldx     #3              ; (frames - loop) x 14 bytes to go
        sec
        ldy     #0
@s3:    lda     hdr+6,y
        sbc     hdr+10,y
        sta     acc,y
        iny
        dex
        bpl     @s3
        jsr     mul14
        ldx     #3
@s4:    lda     acc,x
        sta     rd_left,x
        dex
        bpl     @s4
        rts
@req:   lda     #<$F000         ; ask for min(rd_left, $F000) bytes
        ldx     #>$F000
        ldy     rd_left+3
        bne     @big
        ldy     rd_left+2
        bne     @big
        ldy     rd_left+1
        cpy     #>$F000
        bcs     @big
        lda     rd_left
        ldx     rd_left+1
@big:   pha
        lda     #CMD_BYTE_READ
        jsr     ch_cmd
        pla
        jsr     ch_wr
        txa
        jsr     ch_wr
        lda     #0
        sta     rd_got
        lda     #RS_READ
        sta     rd_state
        rts
@err:   lda     #1
        sta     rd_err
        lda     #RS_STOP
        sta     rd_state
        rts

@read:  lda     CH_CMD          ; the drive not ready yet: next time
        bmi     @r
        lda     fill+1          ; room for a block? (64 bytes; 255 allowed for)
        cmp     #>(RING_SIZE - 256)
        bcc     @room
        bne     @r
        lda     fill
        cmp     #<(RING_SIZE - 256)
        beq     @room
        bcs     @r
@room:  lda     #CMD_GET_STATUS
        jsr     ch_cmd
        jsr     ch_rd
        cmp     #USB_INT_DISK_READ
        beq     @blk
        cmp     #USB_INT_SUCCESS
        bne     @err
        lda     rd_got          ; the read is done; one that got nothing
        bne     @done           ; means the file ended early
        lda     #RS_STOP
        sta     rd_state
        rts
@done:  lda     #RS_IDLE
        sta     rd_state
@r:     rts
@blk:   lda     #CMD_RD_USB_DATA0
        jsr     ch_cmd
        jsr     ch_rd
        sta     ch_cnt
        sta     rd_got
        tax
        beq     @go
        lda     wr_ptr
        sta     @st+1
        lda     wr_ptr+1
        sta     @st+2
@c:     jsr     ch_rd
@st:    sta     $FFFF
        inc     @st+1
        bne     @c1
        ldy     @st+2
        iny
        cpy     #>RING_END
        bne     @c0
        ldy     #>RING
@c0:    sty     @st+2
@c1:    dex
        bne     @c
        lda     @st+1
        sta     wr_ptr
        lda     @st+2
        sta     wr_ptr+1
        lda     fill            ; fill += n, rd_left -= n
        clc
        adc     ch_cnt
        sta     fill
        bcc     @f
        inc     fill+1
@f:     lda     rd_left
        sec
        sbc     ch_cnt
        sta     rd_left
        ldx     #1
        ldy     #3              ; (counted in Y: CPX would upset the carry)
@f1:    lda     rd_left,x
        sbc     #0
        sta     rd_left,x
        inx
        dey
        bne     @f1
@go:    lda     #CMD_BYTE_RD_GO
        jsr     ch_cmd
        rts

; ---- timing: VIA timer 2, one shot, polled --------------------------------------------------
; the frame time in cycles is CLOCK_MHZ x 1000000 / rate; when that is more
; than the timer holds it is halved (and counted out in 2, 4 ... runs)
timer_setup:
        lda     #<(CLOCK_MHZ * 1000000)
        sta     acc
        lda     #>(CLOCK_MHZ * 1000000)
        sta     acc+1
        lda     #^(CLOCK_MHZ * 1000000)
        sta     acc+2
        lda     #0
        sta     acc+3
        lda     hdr+4
        jsr     div32
        lda     #1
        sta     t_runs
@h:     lda     acc+2
        ora     acc+3
        beq     @fit
        lsr     acc+3
        ror     acc+2
        ror     acc+1
        ror     acc
        asl     t_runs
        jmp     @h
@fit:   lda     acc             ; (the timer runs for its count + 2 cycles)
        sec
        sbc     #2
        sta     t_lo
        lda     acc+1
        sbc     #0
        sta     t_hi
        rts
T2_FIX  = 39                    ; cycles from reading the timer to starting it, -2

timer_start:
        lda     t_runs
        sta     t_left
        lda     t_lo
        sta     VIA_T2CL
        lda     t_hi
        sta     VIA_T2CH        ; (starts it, and clears its flag)
        rts

; wait for the end of the frame, and start the next one
timer_wait:
@w:     lda     VIA_IFR
        and     #$20
        beq     @w
        ; the timer has gone on counting down past 0 ($FFFF, $FFFE ...): it
        ; says how late this is, so the next run is made that much shorter
        ; and the beat doesn't drift
@rd:    ldx     VIA_T2CH
        lda     VIA_T2CL
        cpx     VIA_T2CH        ; (the high byte changed in between: again)
        bne     @rd
        sec                     ; count + 1 + the timer - T2_FIX
        adc     t_lo
        tay
        txa
        adc     t_hi
        bcc     @late           ; (more than a whole run late)
        tax
        tya
        sec
        sbc     #T2_FIX
        bcs     @s
        dex
@s:     sta     VIA_T2CL
        stx     VIA_T2CH
        dec     t_left
        bne     @w
        lda     t_runs
        sta     t_left
        rts
@late:  lda     #100
        sta     VIA_T2CL
        lda     #0
        sta     VIA_T2CH
        dec     t_left
        bne     @w
        lda     t_runs
        sta     t_left
        rts

; ---- the time shown -------------------------------------------------------------------------
count_time:
        inc     sec_frames
        lda     sec_frames
        cmp     hdr+4
        bcc     @r
        lda     #0
        sta     sec_frames
        inc     secs
        bne     @t
        inc     secs+1
@t:     ldx     #2              ; just the time played, over the old one
        ldy     #TIME_ROW
        jsr     goto
        jmp     pr_secs
@r:     rts

; "  mm:ss / mm:ss  LOOP" over the last one
show_time:
        ldx     #0
        ldy     #TIME_ROW
        jsr     goto
        PRINT   time_txt
        jsr     pr_secs
        PRINT   of_txt
        ldx     #3
@c:     lda     hdr+6,x
        sta     acc,x
        dex
        bpl     @c
        lda     hdr+4
        jsr     div32
        jsr     pr_mmss
        lda     loop_on
        beq     @n
        PRINT   loop_txt
        rts
@n:     PRINT   spaces_txt
        rts

; the time played (secs) as mm:ss
pr_secs:lda     secs
        sta     acc
        lda     secs+1
        sta     acc+1
        lda     #0
        sta     acc+2
        sta     acc+3
        ; (on into pr_mmss)

; print the seconds in acc as mm:ss
pr_mmss:
        lda     #60
        jsr     div32
        pha
        lda     acc+1           ; (more than 99 minutes: 99)
        ora     acc+2
        ora     acc+3
        bne     @99
        lda     acc
        cmp     #100
        bcc     @m
@99:    lda     #99
@m:     jsr     prdec2
        lda     #':'
        jsr     SBC_CHROUT
        pla
        jmp     prdec2

; title, author, length
show_info:
        PRINT   title_txt
        ldx     #16
        jsr     pr_field
        PRINT   author_txt
        ldx     #48
        jsr     pr_field
        rts

; print the 32 byte field at hdr+X (to its first 0), then a new line
pr_field:
        ldy     #32
@l:     lda     hdr,x
        beq     @e
        cmp     #' '
        bcc     @sk
        cmp     #127
        bcs     @sk
        jsr     SBC_CHROUT
@sk:    inx
        dey
        bne     @l
@e:     jmp     crlf

; ---- the playing screen ------------------------------------------------------------------
TIME_ROW        = 3             ; "  mm:ss / mm:ss"
BAR_TOP         = 5             ; the bars: rows 5-12, a cell 2 levels high
BAR_ROWS        = 8
LABEL_ROW       = BAR_TOP + BAR_ROWS        ; "A  TNE" under each
KEYS_ROW        = 15
MSG_ROW         = 18            ; where the messages go after a song
BAR_W           = 10            ; columns: each cell is sent once, repeated
G_ATTR          = $80 | (BAR_W << 3)        ; block graphics, repeat BAR_W

; the cursor to column X, row Y (keeps A, X, Y)
goto:   pha
        lda     #$0E
        jsr     SBC_CHROUT
        txa
        jsr     SBC_CHROUT
        lda     #$0F
        jsr     SBC_CHROUT
        tya
        jsr     SBC_CHROUT
        pla
        rts

; the messages after a song go under its screen
to_msg: lda     scr_up
        beq     @r
        lda     #0
        sta     scr_up
        ldx     #0
        ldy     #MSG_ROW
        jmp     goto
@r:     rts

; the whole screen afresh: name, title, author, time, keys (and the bars)
draw_screen:
        lda     #12
        jsr     SBC_CHROUT
        lda     #1
        sta     scr_up
        PRINT   ymp_txt
        PRINT   name_buf
        jsr     crlf
        jsr     show_info       ; (rows 1 and 2)
        jsr     show_time
        ldx     #0
        ldy     #KEYS_ROW
        jsr     goto
        PRINT   keys2_txt
        jsr     vis_clear
        lda     vis_on
        beq     @r
        PRINT   legend_txt
        ldx     #2              ; the labels
@l:     lda     bar_col,x
        clc
        adc     #2
        stx     tmp
        tax
        ldy     #LABEL_ROW
        jsr     goto
        ldx     tmp
        lda     #'A'
        clc
        adc     tmp
        jsr     SBC_CHROUT
        dex
        bpl     @l
@r:     rts

bar_col:    .byte   12, 35, 58  ; the left column of each bar

; nothing drawn yet: all the cells blank, the flags to be shown
vis_clear:
        ldx     #BAR_ROWS * 3 - 1
        lda     #0
@c:     sta     shown,x
        dex
        bpl     @c
        ldx     #2
@b:     lda     #0
        sta     bar,x
        sta     peak,x
        sta     peak_t,x
        lda     #$FF
        sta     flags_shown,x
        dex
        bpl     @b
        lda     #0
        sta     draw_i
        rts

; a song starting: the rates the bars run at, the envelope model reset
vis_song:
        ldx     #13
        lda     #0
@r:     sta     regs,x
        dex
        bpl     @r
        sta     env_new
        sta     env_shape
        sta     env_pos
        sta     env_pos+1
        sta     env_pos+2
        sta     env_ep
        sta     env_ep+1
        lda     hdr+4           ; vis_k = (rate + 49) / 50: the bars every
        clc                     ;  vis_k frames, about 50 times a second
        adc     #49
        sta     acc
        lda     #0
        adc     #0
        sta     acc+1
        lda     #0
        sta     acc+2
        sta     acc+3
        lda     #50
        jsr     div32
        lda     acc
        sta     vis_k
        sta     vis_c
        ; env_k = AY clock x vis_k / rate: the envelope's 1/16 steps in
        ; vis_k frames is env_k / its period
        lda     #0
        sta     env_k
        sta     env_k+1
        sta     env_k+2
        ldx     vis_k
@k:     clc
        lda     env_k
        adc     #<AY_CLOCK
        sta     env_k
        lda     env_k+1
        adc     #>AY_CLOCK
        sta     env_k+1
        lda     env_k+2
        adc     #^AY_CLOCK
        sta     env_k+2
        dex
        bne     @k
        ldx     #2
@c:     lda     env_k,x
        sta     acc,x
        dex
        bpl     @c
        lda     #0
        sta     acc+3
        lda     hdr+4
        jsr     div32
        ldx     #2
@c2:    lda     acc,x
        sta     env_k,x
        sta     env_inc,x       ; (period 0 counts as 1)
        dex
        bpl     @c2
        ; cells_max = 400 / rate (1 to 10): the cells sent in one frame
        lda     #<400
        sta     acc
        lda     #>400
        sta     acc+1
        lda     #0
        sta     acc+2
        sta     acc+3
        lda     hdr+4
        jsr     div32
        lda     acc+1
        bne     @12
        lda     acc
        beq     @1
        cmp     #10
        bcc     @m
@12:    lda     #10
        bne     @m
@1:     lda     #1
@m:     sta     cells_max
        rts
AY_CLOCK        = 2000000

; once a frame (playing or not): the bars every vis_k frames.  At more than
; 100 frames a second (vis_k 3 or more) an update is spread over its frames, so
; no one frame has much more to do: the envelope, then the bars, then sending
; in each of the others.
vis_tick:
        lda     vis_on
        bne     :+
        rts
:       dec     vis_c
        lda     vis_k
        cmp     #3
        bcc     @all
        ldx     vis_c           ; (counts vis_k - 1 down to 0)
        inx
        inx
        cpx     vis_k
        bne     :+
        jmp     vis_env         ; the first frame
:       dex
        cpx     vis_k
        bne     :+
        jmp     vis_bars        ; the second
:       lda     vis_c           ; the others: sending
        bne     :+
        lda     vis_k
        sta     vis_c
:       jmp     vis_send
@all:   lda     vis_c
        bne     @r
        lda     vis_k
        sta     vis_c
        jsr     vis_env
        jsr     vis_bars
        jmp     vis_send
@r:     rts

; the envelope: started again, a new period?  Then its level, and on
vis_env:
        inc     vis_tog
        lda     env_new
        beq     @ep
        lda     #0
        sta     env_new
        sta     env_pos
        sta     env_pos+1
        sta     env_pos+2
        lda     regs+13
        and     #15
        sta     env_shape
@ep:    lda     regs+11
        cmp     env_ep
        bne     @div
        lda     regs+12
        cmp     env_ep+1
        beq     @lev
@div:   lda     regs+11         ; env_inc = env_k / the period
        sta     env_ep
        sta     dv
        lda     regs+12
        sta     env_ep+1
        sta     dv+1
        ora     dv
        bne     @d1
        inc     dv              ; (0 counts as 1)
@d1:    ldx     #2
@q:     lda     env_k,x
        sta     q,x
        dex
        bpl     @q
        jsr     div24
        ldx     #2
@q2:    lda     q,x
        sta     env_inc,x
        dex
        bpl     @q2
@lev:   jsr     env_level
        sta     env_lvl
        clc                     ; then on: env_pos += env_inc, kept under
        lda     env_pos         ; 512 (32 steps) once it is past them, with
        adc     env_inc         ; 512 added to say so
        sta     env_pos
        lda     env_pos+1
        adc     env_inc+1
        sta     env_pos+1
        lda     env_pos+2
        adc     env_inc+2
        sta     env_pos+2
        bne     @past
        lda     env_pos+1
        cmp     #2
        bcc     @chans
@past:  lda     env_pos+1
        and     #1
        ora     #2
        sta     env_pos+1
        lda     #0
        sta     env_pos+2
@chans: rts

; each channel: its level now, the bar and the peak; then the cells
vis_bars:
        ldx     #2
@ch:    lda     regs+8,x
        and     #$10
        beq     @v
        lda     env_lvl
        jmp     @g
@v:     lda     regs+8,x
        and     #15
@g:     ldy     paused
        beq     @h
        lda     #0
@h:     cmp     bar,x           ; up at once, down a level at a time
        bcc     @fall
        sta     bar,x
        bcs     @pk
@fall:  dec     bar,x
@pk:    lda     bar,x
        cmp     peak,x
        bcc     @pf
        sta     peak,x          ; (the peak is reached: hold it)
        lda     #PEAK_HOLD
        sta     peak_t,x
        bne     @fl
@pf:    lda     peak_t,x
        beq     @pd
        dec     peak_t,x
        jmp     @fl
@pd:    lda     vis_tog         ; then down, a level every other time
        lsr
        bcc     @fl
        dec     peak,x
@fl:    lda     #0              ; the flags: tone, noise, envelope (on = 1)
        sta     tmp
        lda     regs+7          ; tone on: bit x clear
        and     bit_tab,x
        bne     @f1
        lda     #1
        sta     tmp
@f1:    lda     regs+7          ; noise on: bit x + 3 clear
        and     bit_tab+3,x
        bne     @f2
        lda     tmp
        ora     #2
        sta     tmp
@f2:    lda     regs+8,x
        and     #$10
        beq     @f3
        lda     tmp
        ora     #4
        sta     tmp
@f3:    lda     tmp
        sta     flags_now,x
        dex
        bmi     @cells
        jmp     @ch

        ; the cells as they should be: tgt, 8 a channel, the bottom one first
@cells: ldx     #2
@cc:    txa
        asl
        asl
        asl
        tay                     ; Y = the channel's first cell
        lda     #1              ; the levels of the cell's lower and upper
        sta     tmp             ;  halves: 1 and 2, then 3 and 4 ...
@cl:    lda     #0
        sta     tmp2
        lda     bar,x
        cmp     tmp
        bcc     @pkc            ; below the lower half: empty
        lda     #$C0
        sta     tmp2
        lda     bar,x
        cmp     tmp
        beq     @pkc            ; just the lower half
        lda     #$CC
        sta     tmp2
@pkc:   lda     peak,x          ; the peak mark, when it is above the bar
        cmp     bar,x
        beq     @st
        bcc     @st
        cmp     tmp
        bne     @pk2
        lda     tmp2
        ora     #$C0
        sta     tmp2
        bne     @st
@pk2:   sec
        sbc     #1
        cmp     tmp
        bne     @st
        lda     tmp2
        ora     #$0C
        sta     tmp2
@st:    lda     tmp2
        sta     tgt,y
        iny
        inc     tmp
        inc     tmp
        tya
        and     #7
        bne     @cl
        dex
        bpl     @cc
        rts

; send what changed, at most cells_max cells, carrying on next time from
; where it stopped; then the flags that changed
vis_send:
        lda     cells_max
        sta     n_left
        lda     #0
        sta     g_on
        lda     #BAR_ROWS * 3
        sta     cnt
        ldx     draw_i
@sc:    lda     tgt,x
        cmp     shown,x
        beq     @sn
        sta     shown,x
        lda     g_on            ; (block graphics, repeated BAR_W times)
        bne     @g1
        inc     g_on
        lda     #$18
        jsr     SBC_CHROUT
        lda     #G_ATTR
        jsr     SBC_CHROUT
@g1:    stx     tmp
        txa
        lsr
        lsr
        lsr
        tay
        lda     bar_col,y
        pha
        txa
        and     #7
        eor     #$FF            ; row = BAR_TOP + 7 - (cell & 7)
        sec
        adc     #BAR_TOP + BAR_ROWS - 1
        tay
        pla
        tax
        jsr     goto
        ldx     tmp
        lda     shown,x
        cmp     #$20            ; (under $20: sent as 1A n)
        bcs     @p
        pha
        lda     #$1A
        jsr     SBC_CHROUT
        pla
@p:     jsr     SBC_CHROUT
        dec     n_left
        beq     @sx
@sn:    inx
        cpx     #BAR_ROWS * 3
        bcc     @sw
        ldx     #0
@sw:    dec     cnt
        bne     @sc
        beq     @sd
@sx:    inx                     ; (the next cell, next time)
        cpx     #BAR_ROWS * 3
        bcc     @sd
        ldx     #0
@sd:    stx     draw_i
        lda     g_on
        beq     @fls
        lda     #$18            ; back to text
        jsr     SBC_CHROUT
        lda     #0
        jsr     SBC_CHROUT

        ; the flags that changed: "TNE", a "." for each that is off
@fls:   ldx     #2
@fx:    lda     n_left          ; (they count as cells too)
        beq     @fr
        lda     flags_now,x
        cmp     flags_shown,x
        beq     @fn
        sta     flags_shown,x
        dec     n_left
        sta     tmp2
        stx     tmp
        lda     bar_col,x
        clc
        adc     #5
        tax
        ldy     #LABEL_ROW
        jsr     goto
        ldy     #0
@fc:    lsr     tmp2
        lda     #'.'
        bcc     @fo
        lda     tne_txt,y
@fo:    jsr     SBC_CHROUT
        iny
        cpy     #3
        bne     @fc
        ldx     tmp
@fn:    dex
        bpl     @fx
@fr:    rts
PEAK_HOLD       = 40            ; updates the peak mark waits (about 0.8 s)

bit_tab:    .byte   1, 2, 4, 8, 16, 32
tne_txt:    .byte   "TNE"

; the envelope's level now (0-15), from its shape and env_pos (1/16 steps)
env_level:
        lda     env_pos+1       ; s = the step: 0-31, or 32-63 when past
        and     #3              ;  the first two cycles
        asl
        asl
        asl
        asl
        sta     tmp
        lda     env_pos
        lsr
        lsr
        lsr
        lsr
        ora     tmp
        sta     tmp             ; s
        and     #15
        sta     tmp2            ; s & 15: the step in this cycle
        ldx     env_shape
        lda     env_tab,x
        sta     tmp3
        bpl     @one
        lda     env_inc+1       ; repeating, at 16 steps or more an update:
        ora     env_inc+2       ;  too fast to follow, shown steady
        beq     @rs
        lda     #11
        rts
@rs:    lda     tmp             ; repeating: the half by bit 4 of the step
        and     #16
        beq     @m0
        bne     @m1
@one:   lda     tmp             ; once: the first cycle, then after it
        cmp     #16
        bcc     @m0
@m1:    lda     tmp3
        and     #3
        jmp     @mode
@m0:    lda     tmp3
        lsr
        lsr
        and     #3
@mode:  beq     @down           ; 0 down, 1 up, 2 zero, 3 full
        cmp     #1
        beq     @up
        cmp     #2
        beq     @zero
        lda     #15
        rts
@zero:  lda     #0
        rts
@up:    lda     tmp2
        rts
@down:  lda     #15
        sec
        sbc     tmp2
        rts

; for each shape: bit 7 repeating, bits 2-3 the first part, 0-1 the second
; (0 down, 1 up, 2 zero, 3 full)
env_tab:    .byte   $02, $02, $02, $02, $06, $06, $06, $06
            .byte   $80, $02, $81, $03, $85, $07, $84, $06

; q (24 bits) = q / dv (16 bits)
div24:  lda     #0
        sta     r
        sta     r+1
        ldx     #24
@l:     asl     q
        rol     q+1
        rol     q+2
        rol     r
        rol     r+1
        bcs     @s              ; (17 bits: more than dv)
        lda     r
        cmp     dv
        lda     r+1
        sbc     dv+1
        bcc     @n
@s:     lda     r
        sbc     dv
        sta     r
        lda     r+1
        sbc     dv+1
        sta     r+1
        inc     q
@n:     dex
        bne     @l
        rts

; ---- arithmetic ------------------------------------------------------------------------------
; acc = acc x 14  (x 16 - x 2)
mul14:  asl     acc
        rol     acc+1
        rol     acc+2
        rol     acc+3
        ldx     #3
@c:     lda     acc,x
        sta     acc2,x
        dex
        bpl     @c
        ldx     #3
@s:     asl     acc
        rol     acc+1
        rol     acc+2
        rol     acc+3
        dex
        bne     @s
        sec
        ldx     #0
        ldy     #4
@sub:   lda     acc,x
        sbc     acc2,x
        sta     acc,x
        inx
        dey
        bne     @sub
        rts

; acc = acc / A, the remainder in A
div32:  sta     tmp
        lda     #0
        ldx     #32
@l:     asl     acc
        rol     acc+1
        rol     acc+2
        rol     acc+3
        rol
        bcs     @sub            ; (9 bits: bigger than any divisor)
        cmp     tmp
        bcc     @n
@sub:   sbc     tmp
        inc     acc
@n:     dex
        bne     @l
        rts

; ---- text ------------------------------------------------------------------------------------
hello_txt:  .byte   13, 10, "YMPLAY - AY-3-8910 MUSIC FROM THE USB DRIVE", 13, 10, 0
err_txt:    .byte   "USB: ", 0
start_errs: .word   e1_txt, e2_txt, e3_txt
e1_txt:     .byte   "NO CH376 FOUND", 13, 10, 0
e2_txt:     .byte   "CH376 WON'T GO INTO USB MODE", 13, 10, 0
e3_txt:     .byte   "NO DRIVE (OR IT CAN'T BE READ)", 13, 10, 0
none_txt:   .byte   "NO .AYS FILES IN ", 0
none2_txt:  .byte   " (MAKE THEM FROM .YM FILES WITH YM2AYS.PY)", 13, 10, 0
anykey_txt: .byte   "PRESS A KEY", 13, 10, 0
bye_txt:    .byte   13, 10, "BYE", 13, 10, 0
list_txt:   .byte   12, "SONGS IN ", 0
colon_txt:  .byte   ":", 13, 10, 0
star_txt:   .byte   "*", 0
rstar_txt:  .byte   "/*", 0
keys_txt:   .byte   "W/S CHOOSE (OR TYPE ITS NUMBER), SPACE PLAYS, Q QUITS", 13, 10, 0
sel_txt:    .byte   "> ", 0
spaces_txt: .byte   "        ", 0
playing_txt:.byte   13, 10, "PLAYING ", 0
open_err_txt:.byte  " - CAN'T OPEN IT", 13, 10, 0
bad_txt:    .byte   "NOT AN .AYS FILE (CONVERT .YM FILES WITH YM2AYS.PY)", 13, 10, 0
read_err_txt:.byte  13, 10, "READ ERROR", 0
title_txt:  .byte   "TITLE:  ", 0
author_txt: .byte   "AUTHOR: ", 0
pause_txt:  .byte   "  PAUSED  ", 0
time_txt:   .byte   "  ", 0
of_txt:     .byte   " / ", 0
loop_txt:   .byte   "  LOOP  ", 0
ymp_txt:    .byte   "YMPLAY - ", 0
keys2_txt:  .byte   "SPACE PAUSE  N NEXT  P BACK  L LOOP  V BARS  S LIST  Q QUIT", 0
legend_txt: .byte   13, 10, "UNDER EACH BAR: T TONE, N NOISE, E ENVELOPE", 0
ays_sig:    .byte   "AYS1"
ays_ext:    .byte   ".AYS", 0

; ---- variables --------------------------------------------------------------------------------
        .segment "BSS"
nsongs:     .res 1
sel:        .res 1
digits:     .res 1
idx:        .res 1
tmp:        .res 1
tmp2:       .res 1
name_len:   .res 1
playing:    .res 1              ; a file is open
paused:     .res 1
loop_on:    .res 1
rd_state:   .res 1
rd_err:     .res 1
rd_got:     .res 1
rd_left:    .res 4              ; bytes of the song still to read before its end
play_frame: .res 4              ; the frame playing
wr_ptr:     .res 2              ; the ring buffer: where the reader writes
rp_ptr:     .res 2              ; and where the player reads
fill:       .res 2              ; bytes in it
t_lo:       .res 1              ; the timer: its count,
t_hi:       .res 1
t_runs:     .res 1              ; runs of it a frame,
t_left:     .res 1              ; and runs left of this frame
secs:       .res 2
sec_frames: .res 1
acc:        .res 4
acc2:       .res 4
cwd_buf:    .res CWD_MAX + 1    ; the folder: "" (the top), "/MUSIC" ...
path_buf:   .res 14             ; "/NAME.AYS"
name_buf    = path_buf + 1
regs:       .res 14             ; the registers as last written (the bars)
scr_up:     .res 1              ; the playing screen is up
vis_on:     .res 1              ; the bars are on (1)
vis_k:      .res 1              ; the bars every vis_k frames
vis_c:      .res 1
vis_tog:    .res 1
cells_max:  .res 1              ; cells sent at most in one update
n_left:     .res 1
g_on:       .res 1
cnt:        .res 1
tmp3:       .res 1
draw_i:     .res 1              ; the cell to look at first next time
bar:        .res 3              ; the level shown, a channel
peak:       .res 3
peak_t:     .res 3
flags_now:  .res 3
flags_shown:.res 3
tgt:        .res BAR_ROWS * 3   ; the cells as they should be
shown:      .res BAR_ROWS * 3   ; and as they are on the screen
env_new:    .res 1              ; register 13 written
env_shape:  .res 1
env_pos:    .res 3              ; where the envelope is, in 1/16 steps
env_inc:    .res 3              ; and how far it goes in an update
env_k:      .res 3
env_ep:     .res 2              ; the period env_inc is for
env_lvl:    .res 1
q:          .res 3
dv:         .res 2
r:          .res 2
hdr:        .res 128            ; the song's header
songs:      .res MAX_SONGS * 8  ; the names (8 bytes each, space padded)
bss_end:
        .assert bss_end <= RING, lderror, "the program has grown into the ring buffer"
