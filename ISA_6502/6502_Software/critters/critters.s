; ============================================================================
; critters.s - a Lemmings style puzzle game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal using its
; control code mode (terminal setup item J must be ON).  Written for 115200
; baud; up to 20 creatures.
;
;   build:  make                (needs sbc_api.inc, the ROM's entry points)
;   run:    L CRITTERS 0500     then   R
;
; Header (patchable from the monitor, same layout as INVADERS and SNAKE):
;   $0500  JMP start
;   $0503  speed      delay per game tick, about 1 ms per unit (default 30)
;   $0504  controls   at start: 0 keyboard, 1 gamepad (G on the title
;                     screen switches; A or Start on the pad picks the pad)
;   $0505  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2): a tune and effects, in critters_sound.inc (made by
; ../ay/tools/game_sounds.py).  Without the card the game is just silent.
;
; Keys:  , .  or  <- ->   select the creature to the left / right
;        1..6             give it a skill: 1 climber  2 floater  3 blocker
;                                          4 builder  5 basher   6 digger
;        + -              release rate
;        P pause   K nuke   R restart level   Q back to the title
;        M sound on / off
; Gamepad: left / right select a creature (hold to repeat), up / down pick
;        a skill (marked > on the status line), A gives it.  B + up / down
;        release rate, Start pause, Select + A nuke.
;
; The screen: pixels are 160 x 96.  Rows 0-87 are the playfield, text rows
; 22 and 23 are the status lines.  The terrain is a bitmap in RAM (20 bytes
; per pixel row); it is drawn once per level with block graphics characters.
; A creature is 1 x 2 pixels; it is erased and redrawn every tick, and the
; erase puts back whatever terrain is under each pixel.
; Pixels are not sent one by one: setpix / clrpix change a copy of the screen
; in RAM (block graphics characters) and once per tick flush_px sends the
; characters that changed (no terminal v1.4 features needed).
;
; No zero page is used: tables are indexed with abs,X and the terrain is
; reached with self-modifying code.
; ============================================================================

        .setcpu "6502"

        .include "sbc_api.inc"   ; fixed ROM entry points ($FE00 table)

SPEED_DEFAULT   = 30

; ---- terminal control codes -------------------------------------------------
TC_CURSOR       = $02
TC_SETPIX       = $05
TC_CLRPIX       = $06
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
ATTR_TEXT       = $00
ATTR_RV         = $04
; reverse video is an ANSI sequence (in terminal v1.4, attribute bit 2 is the
; double size font, not reverse)
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
ATTR_GFX        = $80
TERM            = $FF

; ---- playfield ------------------------------------------------------------------
FW              = 160           ; width in pixels
FH              = 88            ; height in pixels (text rows 0-21)
TBW             = FW / 8        ; terrain bytes per row
HUD1            = 22            ; status text rows
HUD2            = 23
MAXC            = 20            ; most creatures in a level
SPLAT_H         = 32            ; a longer fall than this is fatal
BRICKS          = 12
NSKILLS         = 6
NLEVELS         = 6

; creature states
ST_NONE         = 0             ; not released yet
ST_WALK         = 1
ST_FALL         = 2
ST_FLOAT        = 3
ST_CLIMB        = 4
ST_BLOCK        = 5
ST_BUILD        = 6
ST_BASH         = 7
ST_DIG          = 8
ST_SPLAT        = 9
ST_GONE         = 10            ; saved or dead

; creature flags
F_CLIMB         = 1
F_FLOAT         = 2

; ============================================================================
        .segment "CODE"

        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; music and effects on the AY-3-8910 card

; ----------------------------------------------------------------------------
; I/O and helpers
; ----------------------------------------------------------------------------
putc:   jsr     sfx_poll        ; (the sound goes on while drawing)
        jmp     SBC_CHROUT      ; preserves A, X, Y
getc            = SBC_CHRIN     ; carry set = key in A

putblk: cmp     #$20            ; block graphics pattern (00-1F, 7F need 1A)
        bcc     @lit
        cmp     #$7F
        bne     @out
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@out:   jmp     putc

; cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #$FF            ; (text may follow: the cursor isn't tracked)
        sta     cur_y
        lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
        lda     #TC_COL
        jsr     putc
        txa
        jmp     putc

; cursor to column X, row Y, sending only what is needed (the cursor may be
; there already, or on the same row).  Preserves X and Y.
goto_cell:
        cpy     cur_y
        beq     @row
        jsr     gotoxy
        stx     cur_x
        sty     cur_y
        rts
@row:   cpx     cur_x
        beq     @r
        lda     #TC_COL
        jsr     putc
        txa
        stx     cur_x
        jmp     putc
@r:     rts

; ----------------------------------------------------------------------------
; Pixels.  The screen is kept in RAM as block graphics characters: want[]
; is what it should show, shown[] what the terminal shows (80 x 24 each).
; setpix / clrpix change want[] and note the character in a list; flush_px
; sends the characters that differ, one byte each (plus cursor moves), which
; is much less than 3 bytes per pixel when creatures move.
; ----------------------------------------------------------------------------

; set / reset the pixel at X, Y.  Preserves X and Y.
setpix: jsr     px_cell
        sta     pmask
        jsr     want_rd
        sta     pold
        ora     pmask
        jmp     px_put
clrpix: jsr     px_cell
        eor     #$FF
        sta     pmask
        jsr     want_rd
        sta     pold
        and     pmask
px_put: cmp     pold
        beq     @r              ; no change
        pha
        lda     pold            ; already different from the screen: listed
        jsr     shown_cmp
        bne     @w
        ldx     dl_n
        cpx     #DLMAX
        bcs     @full
        lda     pc_col
        sta     dl_c,x
        lda     pc_row
        sta     dl_r,x
        inc     dl_n
        jmp     @w
@full:  lda     #1              ; too many: flush_px looks at everything
        sta     dl_full
@w:     pla
        jsr     want_wr
@r:     ldx     px_x
        ldy     px_y
        rts

; point want_rd / want_wr / shown_cmp / shown_wr at the character holding
; pixel X, Y.  A = the pixel's bit in it.
px_cell:
        stx     px_x
        sty     px_y
        tya
        lsr
        lsr
        tay
        txa
        lsr
        tax
        jsr     cell_ptr
        lda     px_y
        and     #3
        asl
        sta     pmask
        lda     px_x
        and     #1
        ora     pmask
        tay
        lda     bitmask8,y
        rts

; point them at character X, Y (pc_col, pc_row = X, Y)
cell_ptr:
        stx     pc_col
        sty     pc_row
        txa
        clc
        adc     srow_lo,y
        sta     want_rd+1
        sta     want_wr+1
        sta     shown_cmp+1
        sta     shown_wr+1
        lda     srow_hi,y
        adc     #0
        sta     want_rd+2
        sta     want_wr+2
        clc
        adc     #>(shown - want)
        sta     shown_cmp+2
        sta     shown_wr+2
        rts

want_rd:  lda   $FFFF
          rts
want_wr:  sta   $FFFF
          rts
shown_cmp:cmp   $FFFF
          rts
shown_wr: sta   $FFFF
          rts

; send the characters that changed
flush_px:
        lda     dl_full
        bne     @all
        lda     dl_n
        beq     @r
        jsr     gfx_mode
        ldx     #0
@l:     stx     dl_i
        lda     dl_r,x
        tay
        lda     dl_c,x
        tax
        jsr     send_cell
        ldx     dl_i
        inx
        cpx     dl_n
        bne     @l
        lda     #0
        sta     dl_n
@r:     rts
@all:   jsr     gfx_mode        ; every character on the screen
        ldy     #0
@ar:    ldx     #0
@ac:    stx     tmp_c
        sty     tmp_r
        jsr     send_cell
        ldx     tmp_c
        ldy     tmp_r
        inx
        cpx     #80
        bne     @ac
        iny
        cpy     #24
        bne     @ar
        lda     #0
        sta     dl_n
        sta     dl_full
        rts

; character X, Y: send it if the terminal shows something else
send_cell:
        jsr     cell_ptr
        jsr     want_rd
        jsr     shown_cmp
        beq     @r
        jsr     shown_wr
        pha
        ldx     pc_col
        ldy     pc_row
        jsr     goto_cell
        pla
        jsr     putblk
        inc     cur_x
@r:     rts

; the screen was cleared: so is the copy
clear_shadow:
        lda     #0
        sta     dl_n
        sta     dl_full
        tax
@l:     .repeat 8, K
        sta     want + K * 256,x
        sta     shown + K * 256,x
        .endrepeat
        inx
        bne     @l
        lda     #$FF
        sta     cur_y
        rts

gfx_mode:
        lda     #ATTR_GFX
        bne     setattr
txt_mode:
        lda     #ATTR_TEXT
setattr:cmp     attr
        beq     @done
        sta     attr
        pha
        lda     #TC_ATTR
        jsr     putc
        pla
        jsr     putc
@done:  rts

; print the string at A (lo) / Y (hi), terminated by $FF.  Assumes the
; string leaves the terminal in text mode if it changes the attribute.
print:  sta     @ld+1
        sty     @ld+2
        sta     @cl+1
        sty     @cl+2
        lda     #$FF            ; (the cursor moves)
        sta     cur_y
@cl:    lda     $FFFF           ; a string that clears the screen?
        cmp     #TC_CLS
        bne     @tm
        jsr     clear_shadow
@tm:    jsr     txt_mode
        ldy     #0
@ld:    lda     $FFFF,y
        cmp     #TERM
        beq     @done
        jsr     putc
        iny
        bne     @ld
        inc     @ld+2           ; strings may be longer than 255 bytes
        jmp     @ld
@done:  rts

; print A (0..99) as two decimal digits.  Preserves Y.
pr_dec2:ldx     #0
@t:     cmp     #10
        bcc     @d
        sbc     #10
        inx
        bne     @t
@d:     pha
        txa
        ora     #'0'
        jsr     putc
        pla
        ora     #'0'
        jmp     putc

; print the low digit of A
pr_digit:
        and     #$0F
        ora     #'0'
        jmp     putc

; print A as two BCD digits
prbcd:  pha
        lsr
        lsr
        lsr
        lsr
        ora     #'0'
        jsr     putc
        pla
        jmp     pr_digit

; wait about A ms.  The inner loop is sized for the clock (CLOCK_MHZ in
; sbc_api.inc): 5 + 4 * (CLOCK_MHZ - 1) cycles a turn, DELAY_N turns a ms.
DELAY_N = (1000 * CLOCK_MHZ - 7) / (5 + 4 * (CLOCK_MHZ - 1))
delay_ms:
        pha                     ; (send what was drawn first)
        jsr     flush_px
        pla
        tax
        beq     @done
@o:     jsr     sfx_poll        ; (the sound goes on while waiting)
        ldy     #DELAY_N
@i:
.repeat CLOCK_MHZ - 1           ; (4 more cycles a turn for each MHz above 1)
        nop
        nop
.endrepeat
        dey
        bne     @i
        dex
        bne     @o
@done:  rts

; wait about A x 50 ms
delay_long:
        sta     tmp
@l:     lda     #50
        jsr     delay_ms
        jsr     flush_in        ; keys pressed meanwhile are dropped (so the
        dec     tmp             ; ROM's keyboard buffer never fills up)
        bne     @l
        rts

; wait for a key, return it in A (upper case for letters).  The gamepad's
; A or Start button counts as a space.
waitkey:jsr     menu_key
        cmp     #PAD_GO
        bne     @r
        lda     #' '
@r:     rts

; throw away waiting keys
flush:  jsr     getc
        bcs     flush
        rts

; ============================================================================
; terrain bitmap
; ============================================================================

; point tb_rd / tb_wr at the byte holding pixel X, Y and set t_mask.
; Preserves X and Y.  X < 160, Y < 88.
t_ptr:  sty     t_y
        txa
        lsr
        lsr
        lsr
        clc
        adc     trow_lo,y
        sta     tb_rd+1
        sta     tb_wr+1
        lda     trow_hi,y
        adc     #0
        sta     tb_rd+2
        sta     tb_wr+2
        txa
        and     #7
        tay
        lda     mask_hi,y
        sta     t_mask
        ldy     t_y
        rts
tb_rd:  lda     $FFFF
        rts
tb_wr:  sta     $FFFF
        rts

; carry set if pixel X, Y is solid.  Off the left/right edges and above the
; top count as solid, below the bottom is empty.  Preserves X and Y.
solid:  cpx     #FW
        bcs     @yes
        cpy     #128
        bcs     @yes
        cpy     #FH
        bcs     @no
        jsr     t_ptr
        jsr     tb_rd
        and     t_mask
        beq     @no
@yes:   sec
        rts
@no:    clc
        rts

; remove terrain pixel X, Y (bitmap and screen).  Carry set if there was
; one.  Preserves X and Y.
dig_px: cpx     #FW
        bcs     @no
        cpy     #FH
        bcs     @no
        jsr     t_ptr
        jsr     tb_rd
        and     t_mask
        beq     @no
        jsr     tb_rd
        eor     t_mask
        jsr     tb_wr
        jsr     clrpix
        sec
        rts
@no:    clc
        rts

; add terrain pixel X, Y (bitmap and screen).  Preserves X and Y.
build_px:
        cpx     #FW
        bcs     @r
        cpy     #FH
        bcs     @r
        jsr     t_ptr
        jsr     tb_rd
        and     t_mask
        bne     @r
        jsr     tb_rd
        ora     t_mask
        jsr     tb_wr
        jmp     setpix
@r:     rts

; set the bitmap bit only (level building).  Preserves X and Y.
t_setbit:
        jsr     t_ptr
        jsr     tb_rd
        ora     t_mask
        jmp     tb_wr

; ============================================================================
; drawing creatures.  A creature's pixels are drawn with draw_px; erase_px
; restores the terrain (or the background) under a pixel, and notes when the
; hatch or the exit door decoration needs to be drawn again.
; ============================================================================
draw_px:cpx     #FW
        bcs     @r
        cpy     #FH
        bcs     @r
        jmp     setpix
@r:     rts

erase_px:
        cpx     #FW
        bcs     @r
        cpy     #FH
        bcs     @r
        txa                     ; inside the hatch box?
        sec
        sbc     hx
        clc
        adc     #3
        cmp     #7
        bcs     @door
        tya
        sec
        sbc     hy
        clc
        adc     #7
        cmp     #5
        bcs     @door
        lda     #1
        sta     dirty_h
@door:  txa                     ; inside the door box?
        sec
        sbc     ex
        clc
        adc     #3
        cmp     #7
        bcs     @t
        tya
        sec
        sbc     ey
        clc
        adc     #7
        cmp     #5
        bcs     @t
        lda     #1
        sta     dirty_d
@t:     jsr     t_ptr
        jsr     tb_rd
        and     t_mask
        beq     @clr
        jmp     setpix
@clr:   jmp     clrpix
@r:     rts

; draw (s_op = 0) or erase (s_op = 1) shape Y at sx, sy
shape_op:
        lda     shp_ofs,y
        tay
@l:     lda     shp_data,y
        cmp     #$80
        beq     @done
        clc
        adc     sx
        tax
        lda     shp_data+1,y
        clc
        adc     sy
        sty     s_i
        tay
        lda     s_op
        bne     @e
        jsr     draw_px
        jmp     @n
@e:     jsr     erase_px
@n:     ldy     s_i
        iny
        iny
        bne     @l
@done:  rts

; the hatch: a box open at the bottom, above the release point
draw_hatch:
        lda     hx
        sec
        sbc     #3
        tax
        lda     hy
        sec
        sbc     #7
        tay
        lda     #7
        jsr     hline
        lda     hx
        sec
        sbc     #3
        tax
        lda     hy
        sec
        sbc     #6
        tay
        lda     #3
        jsr     vline
        lda     hx
        clc
        adc     #3
        tax
        lda     hy
        sec
        sbc     #6
        tay
        lda     #3
        jmp     vline

; the exit: a door frame whose posts stop above the creatures' heads
draw_door:
        lda     ex
        sec
        sbc     #3
        tax
        lda     ey
        sec
        sbc     #7
        tay
        lda     #7
        jsr     hline
        lda     ex
        sec
        sbc     #3
        tax
        lda     ey
        sec
        sbc     #6
        tay
        lda     #4
        jsr     vline
        lda     ex
        clc
        adc     #3
        tax
        lda     ey
        sec
        sbc     #6
        tay
        lda     #4
        jsr     vline
        ldx     ex              ; and a flag on top
        lda     ey
        sec
        sbc     #8
        tay
        jsr     setpix
        dey
        jsr     setpix
        inx
        jmp     setpix

; lines of pixels: X, Y start, A = length
hline:  sta     tmp
@l:     jsr     draw_px
        inx
        dec     tmp
        bne     @l
        rts
vline:  sta     tmp
@l:     jsr     draw_px
        iny
        dec     tmp
        bne     @l
        rts

.macro MENU_IDLE
        jsr     flush_px
        jsr     sfx_poll
.endmacro
CTRL_COL        = 19
CTRL_ROW        = 18

; ============================================================================
; gamepad and menu input (shared by the SBC games)
; ============================================================================
PAD_A           = $01           ; bits returned by SBC_PADSTATE
PAD_B           = $02
PAD_SELECT      = $04
PAD_START       = $08
PAD_UP          = $10
PAD_DOWN        = $20
PAD_LEFT        = $40
PAD_RIGHT       = $80
PAD_GO          = $80           ; menu_key's answer for gamepad A or Start

; read the gamepad: pad = buttons held now, padnew = buttons pressed since
; the last call.  Preserves X and Y (SBC_PADSTATE only changes A).
read_pad:
        jsr     SBC_PADSTATE
        cmp     #$FF            ; every button "pressed" = no pad
        bne     @ok
        lda     #0
@ok:    sta     pad
        lda     padold
        eor     #$FF
        and     pad
        sta     padnew
        lda     pad
        sta     padold
        rts

; throw away waiting characters
flush_in:
        jsr     getc
        bcs     flush_in
        rts

; carry set if A is one of the characters the gamepad driver types for the
; pad (W A S D and space).  Those are ignored in gamepad mode so that one
; press doesn't act twice.  Preserves A.
pad_typed:
        cmp     #' '
        beq     @y
        cmp     #'W'
        beq     @y
        cmp     #'A'
        beq     @y
        cmp     #'S'
        beq     @y
        cmp     #'D'
        beq     @y
        clc
        rts
@y:     sec
        rts

; wait for a menu choice.  Returns a key (letters in upper case), or
; PAD_GO for the gamepad's A or Start button.
menu_key:
@l:     MENU_IDLE
        jsr     read_pad
        lda     padnew
        and     #PAD_A | PAD_START
        bne     @pad
        jsr     getc
        bcc     @l
        cmp     #' '            ; a space typed by the pad's A button?
        bne     @up
        jsr     read_pad
        lda     pad
        and     #PAD_A
        bne     @pad
        lda     #' '
        rts
@up:    cmp     #'a'
        bcc     @r
        cmp     #'z'+1
        bcs     @r
        and     #$DF
@r:     rts
@pad:   jsr     flush_in        ; the space the driver typed for it
        lda     #PAD_GO
        rts

; print the controls line (CTRL_COL, CTRL_ROW)
show_ctrl:
        jsr     txt_mode
        ldx     #CTRL_COL
        ldy     #CTRL_ROW
        jsr     gotoxy
        lda     ctrl
        beq     @kb
        lda     #<ctrl_pad_txt
        ldy     #>ctrl_pad_txt
        jmp     print
@kb:    lda     #<ctrl_kb_txt
        ldy     #>ctrl_kb_txt
        jmp     print

; ============================================================================
; start / title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear every variable: RAM is random at power-up
        tax
        ldy     #>(bss_end - bss_start + $FF)   ; whole pages (past the end is free RAM)
@clr:   sta     bss_start,x
        inx
        bne     @clr
        inc     @clr+2
        dey
        bne     @clr
        lda     ctrl_def
        sta     ctrl
        lda     #0
        sta     cur_skill
        jsr     read_pad
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
  lda     #0
        sta     level

title:  jsr     sfx_off
        lda     #$FF
        sta     attr
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        ; a few creatures marching under the title
        lda     #0
        sta     s_op
        lda     #6
        sta     tmp2
@demo:  lda     tmp2
        asl
        asl
        asl
        clc
        adc     #50
        sta     sx
        lda     #30
        sta     sy
        ldy     #0
        lda     tmp2
        cmp     #3
        bne     @d1
        ldy     #2              ; one of them is a blocker
@d1:    jsr     shape_op
        dec     tmp2
        bne     @demo
        ldx     #44             ; the ground they walk on
        ldy     #31
        lda     #72
        jsr     hline
        jsr     show_ctrl
        jsr     show_start
        jsr     read_pad
@wait:  jsr     sfx_poll
        jsr     read_pad        ; gamepad: up / down choose the level,
        lda     padnew          ; A or Start plays (with the pad)
        and     #PAD_UP | PAD_RIGHT
        beq     @pdn
        lda     level
        cmp     #NLEVELS-1
        bcs     @wait
        inc     level
        jsr     show_start
        jmp     @wait
@pdn:   lda     padnew
        and     #PAD_DOWN | PAD_LEFT
        beq     @pgo
        lda     level
        beq     @wait
        dec     level
        jsr     show_start
        jmp     @wait
@pgo:   lda     padnew
        and     #PAD_A | PAD_START
        beq     @key
        lda     #1
        sta     ctrl
        jsr     flush_in
        jmp     play_level
@key:   jsr     getc
        bcc     @wait
        cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'Q'
        bne     @nq
        jmp     exit_game
@nq:    cmp     #'M'            ; sound on / off
        bne     @nm
        jsr     sfx_toggle
        jmp     @wait
@nm:    cmp     #'G'            ; switch keyboard / gamepad
        bne     @ng
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@ng:    cmp     #' '
        beq     @go
        cmp     #'1'
        bcc     @w2
        cmp     #'1'+NLEVELS
        bcc     @lv
@w2:    jmp     @wait
@lv:
        sec
        sbc     #'1'
        sta     level
@go:    jmp     play_level

; "START AT LEVEL n" on the title screen
show_start:
        jsr     txt_mode
        ldx     #CTRL_COL
        ldy     #CTRL_ROW+2
        jsr     gotoxy
        lda     #<startlv_txt
        ldy     #>startlv_txt
        jsr     print
        lda     level
        clc
        adc     #'1'
        jmp     putc

exit_game:
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
exit_menu:
        jmp     SBC_MENU        ; back to the boot menu

; ============================================================================
; a level
; ============================================================================
play_level:
        jsr     load_level
        jsr     intro           ; shows the level; carry set = Q pressed
        bcc     @go
        jmp     title
@go:    jsr     draw_level
        jsr     sfx_off         ; the tune, and off they go
        lda     #MUS_STROLL
        jsr     sfx_snd
        lda     #MUS_STROLL+1
        jsr     sfx_snd
        lda     #SND_START
        jsr     sfx_snd
        jmp     game_loop

; read the header of level `level` and build its terrain bitmap
load_level:
        ldx     level
        lda     lv_tab_lo,x
        ldy     lv_tab_hi,x
        jsr     lv_set
        jsr     lv_get
        sta     total
        jsr     lv_get
        sta     need
        jsr     lv_get
        sta     rate
        sta     min_rate
        jsr     lv_get
        sta     time_bcd        ; seconds, BCD, low byte first
        jsr     lv_get
        sta     time_bcd+1
        ldx     #0
@sk:    jsr     lv_get
        sta     skills,x
        inx
        cpx     #NSKILLS
        bne     @sk
        jsr     lv_get
        sta     hx
        jsr     lv_get
        sta     hy
        jsr     lv_get
        sta     ex
        jsr     lv_get
        sta     ey
        lda     lv_rd+1         ; the name starts here
        sta     name_ptr
        lda     lv_rd+2
        sta     name_ptr+1
@nm:    jsr     lv_get          ; skip it
        cmp     #TERM
        bne     @nm
        ; clear the bitmap (7 pages)
        lda     #>terrain
        sta     @st+2
        lda     #0
        tax
@st:    sta     terrain,x
        inx
        bne     @st
        inc     @st+2
        ldy     @st+2
        cpy     #>terrain + 7
        bcc     @st
        ; terrain commands
@cmd:   jsr     lv_get
        beq     @end
        sta     cmd
        jsr     lv_get
        sta     rx
        jsr     lv_get
        sta     ry
        jsr     lv_get
        sta     rw
        lda     cmd
        cmp     #'R'
        bne     @ramp
        jsr     lv_get
        sta     rh
        jsr     fill_rect
        jmp     @cmd
@ramp:  jsr     fill_ramp
        jmp     @cmd
@end:   ; reset the game state
        ldx     #MAXC-1
        lda     #0
@cl:    sta     c_st,x
        sta     d_on,x
        dex
        bpl     @cl
        lda     #0
        sta     released
        sta     saved
        sta     out
        sta     tdiv
        sta     nuking
        lda     #$FF
        sta     sel
        lda     #10
        sta     rel_t
        rts

; level data reader (self-modifying pointer).  Preserves X and Y.
lv_set: sta     lv_rd+1
        sty     lv_rd+2
        rts
lv_get:
lv_rd:  lda     $FFFF
        inc     lv_rd+1
        bne     @r
        inc     lv_rd+2
@r:     cmp     #0              ; flags reflect the byte
        rts

; fill rx, ry, rw x rh
fill_rect:
        lda     ry
        sta     fy
        lda     rh
        sta     fh
@row:   ldx     rx
        lda     rw
        sta     fw
        ldy     fy
@px:    jsr     t_setbit
        inx
        dec     fw
        bne     @px
        inc     fy
        dec     fh
        bne     @row
        rts

; ramp: rw columns starting at rx; 'U' rises to the right, 'D' falls.
; Column i is filled from its top down to row ry.
fill_ramp:
        lda     #0
        sta     fw              ; column counter
@col:   lda     cmd
        cmp     #'U'
        beq     @up
        lda     rw              ; D: top = ry - (rw-1-i)
        sec
        sbc     #1
        sec
        sbc     fw
        jmp     @top
@up:    lda     fw              ; U: top = ry - i
@top:   sta     tmp
        lda     ry
        sec
        sbc     tmp
        tay
        lda     rx
        clc
        adc     fw
        tax
@px:    jsr     t_setbit
        iny
        cpy     ry
        bcc     @px
        beq     @px
        inc     fw
        lda     fw
        cmp     rw
        bne     @col
        rts

; the level's title page; carry set if Q was pressed
intro:  lda     #$FF
        sta     attr
        lda     #<intro_txt
        ldy     #>intro_txt
        jsr     print
        lda     level
        clc
        adc     #'1'
        jsr     putc
        lda     #':'
        jsr     putc
        lda     #' '
        jsr     putc
        lda     name_ptr
        ldy     name_ptr+1
        jsr     print
        ldx     #26
        ldy     #11
        jsr     gotoxy
        lda     #<save_txt
        ldy     #>save_txt
        jsr     print
        lda     need
        jsr     pr_dec2
        lda     #<of_txt
        ldy     #>of_txt
        jsr     print
        lda     total
        jsr     pr_dec2
        lda     #<intro2_txt
        ldy     #>intro2_txt
        jsr     print
        jsr     flush
@w:     jsr     waitkey
        cmp     #'Q'
        beq     @q
        cmp     #' '
        bne     @w
        clc
        rts
@q:     sec
        rts

; draw the playfield and the status lines
draw_level:
        lda     #$FF
        sta     attr
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        jsr     render
        jsr     draw_hatch
        jsr     draw_door
        lda     #<hud_txt
        ldy     #>hud_txt
        jsr     print
        ldx     #NSKILLS-1
@sk:    stx     tmp2
        jsr     show_skill
        ldx     tmp2
        dex
        bpl     @sk
        ldx     #21             ; need
        ldy     #HUD2
        jsr     gotoxy
        lda     need
        jsr     pr_dec2
        jsr     show_time
        lda     #$FF
        sta     sh_mark
        jsr     show_marker
        lda     #$FF
        sta     sh_out
        sta     sh_saved
        sta     sh_rate
        sta     sh_sel
        rts

; draw the terrain bitmap with block graphics characters, skipping empty cells
render: jsr     gfx_mode
        lda     #0
        sta     rr
@row:   lda     #0
        sta     rc
        lda     #1
        sta     rgap
@col:   lda     #0
        sta     pat
        lda     rr              ; pixel rows 4rr+3 down to 4rr
        asl
        asl
        clc
        adc     #3
        sta     fy
        lda     #4
        sta     fh
@k:     lda     rc
        asl
        tax
        ldy     fy
        jsr     t_ptr
        jsr     tb_rd
        sta     tmp
        asl     pat
        asl     pat
        lda     tmp
        and     t_mask
        beq     @nl
        lda     pat
        ora     #1              ; left pixel -> even bit
        sta     pat
@nl:    lsr     t_mask
        lda     tmp
        and     t_mask
        beq     @nr
        lda     pat
        ora     #2              ; right pixel -> odd bit
        sta     pat
@nr:    dec     fy
        dec     fh
        bne     @k
        lda     pat
        beq     @empty
        lda     rgap
        beq     @put
        ldx     rc
        ldy     rr
        jsr     gotoxy
        lda     #0
        sta     rgap
@put:   lda     pat
        jsr     putblk
        ldx     rc              ; (and in the copy of the screen)
        ldy     rr
        jsr     cell_ptr
        lda     pat
        jsr     want_wr
        jsr     shown_wr
        lda     #$FF
        sta     cur_y
        jmp     @next
@empty: lda     #1
        sta     rgap
@next:  inc     rc
        lda     rc
        cmp     #80
        beq     @eol
        jmp     @col
@eol:   inc     rr
        lda     rr
        cmp     #FH/4
        beq     @eof
        jmp     @row
@eof:   jmp     txt_mode

; ---- status lines ------------------------------------------------------------
show_skill:                     ; X = skill
        lda     skill_col,x
        tay
        lda     skills,x
        pha
        tya
        tax
        ldy     #HUD1
        jsr     gotoxy
        pla
        jmp     pr_dec2

show_time:
        jsr     txt_mode
        ldx     #39
        ldy     #HUD2
        jsr     gotoxy
        lda     time_bcd+1
        jsr     pr_digit
        lda     time_bcd
        jmp     prbcd

update_hud:
        jsr     txt_mode
        lda     out
        cmp     sh_out
        beq     @1
        sta     sh_out
        ldx     #5
        ldy     #HUD2
        jsr     gotoxy
        lda     out
        jsr     pr_dec2
@1:     lda     saved
        cmp     sh_saved
        beq     @2
        sta     sh_saved
        ldx     #12
        ldy     #HUD2
        jsr     gotoxy
        lda     saved
        jsr     pr_dec2
@2:     lda     rate
        cmp     sh_rate
        beq     @3
        sta     sh_rate
        ldx     #30
        ldy     #HUD2
        jsr     gotoxy
        lda     rate
        jsr     pr_dec2
@3:     ; the selected creature: what it is doing and its abilities
        lda     #0
        sta     tmp
        ldx     sel
        bmi     @show
        lda     c_fl,x
        asl
        asl
        asl
        asl
        ora     c_st,x
        sta     tmp
@show:  lda     tmp
        cmp     sh_sel
        beq     @done
        sta     sh_sel
        ldx     #49
        ldy     #HUD2
        jsr     gotoxy
        lda     tmp
        and     #$0F
        asl
        asl
        asl                     ; 8 characters per name
        tax
        ldy     #8
@nm:    lda     st_names,x
        jsr     putc
        inx
        dey
        bne     @nm
        lda     #' '
        jsr     putc
        lda     tmp
        and     #F_CLIMB << 4
        beq     @nc
        lda     #'C'
        bne     @pc
@nc:    lda     #' '
@pc:    jsr     putc
        lda     tmp
        and     #F_FLOAT << 4
        beq     @nf
        lda     #'F'
        bne     @pf
@nf:    lda     #' '
@pf:    jsr     putc
@done:  rts

; ============================================================================
; the game loop
; ============================================================================
game_loop:
        jsr     sfx_poll
        jsr     read_keys
        lda     action
        beq     @play
        cmp     #'Q'
        bne     @nq
        jmp     title
@nq:    jmp     play_level      ; 'R' restart
@play:  jsr     release
        jsr     update_all
        jsr     redraw_all
        jsr     flush_px        ; send what changed on the screen
        jsr     update_hud
        jsr     clock
        lda     released       ; finished? (blockers can't go anywhere,
        cmp     total           ;  so they don't count)
        bcc     @more
        lda     out
        cmp     nblock
        beq     level_end
@more:  lda     time_bcd
        ora     time_bcd+1
        beq     level_end
        lda     speed
        jsr     delay_ms
        jmp     game_loop

; ---- end of a level -----------------------------------------------------------
level_end:
        jsr     sfx_off         ; the tune stops
        lda     #20
        jsr     delay_long
        lda     #<end_txt
        ldy     #>end_txt
        jsr     print
        lda     saved
        jsr     pr_dec2
        lda     #<end2_txt
        ldy     #>end2_txt
        jsr     print
        lda     need
        jsr     pr_dec2
        lda     saved
        cmp     need
        lda     #SND_WELL       ; (the flags stay from the CMP)
        bcs     @s
        lda     #SND_FAIL
@s:     jsr     sfx_snd
        lda     saved
        cmp     need
        bcc     @fail
        lda     level
        cmp     #NLEVELS-1
        bcc     @next
        lda     #<alldone_txt   ; that was the last level
        ldy     #>alldone_txt
        jsr     print
        jsr     flush
@w0:    jsr     waitkey
        cmp     #' '
        beq     @t0
        cmp     #'Q'
        bne     @w0
@t0:    lda     #0
        sta     level
        jmp     title
@next:  lda     #<well_txt
        ldy     #>well_txt
        jsr     print
        jsr     flush
@w1:    jsr     waitkey
        cmp     #'Q'
        beq     @title
        cmp     #' '
        bne     @w1
        inc     level
        jmp     play_level
@fail:  lda     #<fail_txt
        ldy     #>fail_txt
        jsr     print
        jsr     flush
@w2:    jsr     waitkey
        cmp     #'Q'
        beq     @title
        cmp     #' '
        bne     @w2
        jmp     play_level
@title: jmp     title

; ---- the clock: one "second" every 10 ticks ----------------------------------
clock:  inc     tdiv
        lda     tdiv
        cmp     #10
        bcc     @r
        lda     #0
        sta     tdiv
        lda     time_bcd
        ora     time_bcd+1
        beq     @r
        sed
        lda     time_bcd
        sec
        sbc     #1
        sta     time_bcd
        lda     time_bcd+1
        sbc     #0
        sta     time_bcd+1
        cld
        jmp     show_time
@r:     rts

; ---- releasing creatures from the hatch ---------------------------------------
release:lda     nuking
        bne     @r
        lda     released
        cmp     total
        bcs     @r
        dec     rel_t
        bne     @r
        lda     #120            ; ticks between creatures = (120 - rate) / 4
        sec
        sbc     rate
        lsr
        lsr
        sta     rel_t
        lda     #SND_DROP
        jsr     sfx_snd
        ldx     released
        lda     hx
        sta     c_x,x
        lda     hy
        sta     c_y,x
        lda     #1
        sta     c_dir,x
        lda     #ST_FALL
        sta     c_st,x
        lda     #0
        sta     c_fl,x
        sta     c_fa,x
        sta     c_t,x
        sta     c_n,x
        inc     released
@r:     rts

; ============================================================================
; keyboard
; ============================================================================
read_keys:
        lda     #0
        sta     action
        lda     ctrl
        beq     @l
        jsr     pad_input
@l:     jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @l
@done:  rts

handle_key:
        ldx     esc_st          ; ESC [ C / ESC [ D are the arrow keys
        beq     @plain
        cpx     #1
        bne     @esc2
        cmp     #'['
        beq     @br
        cmp     #'O'
        beq     @br
        lda     #0
        sta     esc_st
        rts
@br:    inc     esc_st
        rts
@esc2:  ldx     #0
        stx     esc_st
        cmp     #'C'
        bne     @nr
        jmp     sel_next
@nr:    cmp     #'D'
        bne     @x
        jmp     sel_prev
@x:     rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    cmp     #'.'
        bne     @n1
        jmp     sel_next
@n1:    cmp     #','
        bne     @n2
        jmp     sel_prev
@n2:    cmp     #'1'
        bcc     @n3
        cmp     #'1'+NSKILLS
        bcs     @n3
        sec
        sbc     #'1'
        jmp     assign
@n3:    cmp     #'+'
        beq     @faster
        cmp     #'='
        beq     @faster
        cmp     #'-'
        beq     @slower
        and     #$DF
        cmp     #'Q'
        beq     @act
        cmp     #'R'
        beq     @act
        cmp     #'K'
        beq     @nuke
        cmp     #'P'
        beq     @pause
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@act:   sta     action
        rts
@faster:jmp     rate_up
@slower:jmp     rate_down
@pause: jsr     sfx_hush        ; (quiet while paused)
@pw:    jsr     getc
        bcc     @pw
        rts
@nuke:  jmp     nuke

rate_up:lda     rate
        clc
        adc     #5
        cmp     #100
        bcc     setrate
        lda     #99
        bne     setrate
rate_down:
        lda     rate
        sec
        sbc     #5
        bcc     @min
        cmp     min_rate
        bcs     setrate
@min:   lda     min_rate
setrate:sta     rate
        rts

nuke:   lda     #SND_NUKE
        jsr     sfx_snd
        lda     #1              ; everyone out there goes splat
        sta     nuking
        lda     total
        sta     released
        ldx     #MAXC-1
@nk:    lda     c_st,x
        beq     @nn
        cmp     #ST_SPLAT
        bcs     @nn
        lda     #ST_SPLAT
        sta     c_st,x
        lda     #8
        sta     c_t,x
@nn:    dex
        bpl     @nk
        rts

; ---- the gamepad ------------------------------------------------------------------
pad_input:
        jsr     read_pad
        lda     padnew
        and     #PAD_START
        beq     @nopause
        jmp     pad_pause
@nopause:
        lda     pad             ; Select + A: nuke
        and     #PAD_SELECT
        beq     @nosel
        lda     padnew
        and     #PAD_A
        bne     @nk
        rts
@nk:    jmp     nuke
@nosel: lda     pad             ; B + up / down: release rate
        and     #PAD_B
        beq     @skill
        lda     padnew
        and     #PAD_UP
        beq     @rd
        jsr     rate_up
@rd:    lda     padnew
        and     #PAD_DOWN
        beq     @lr
        jsr     rate_down
        jmp     @lr
@skill: lda     padnew          ; up / down: the skill to give
        and     #PAD_UP
        beq     @sd
        dec     cur_skill
        bpl     @show
        lda     #NSKILLS-1
        sta     cur_skill
        bne     @show
@sd:    lda     padnew
        and     #PAD_DOWN
        beq     @lr
        inc     cur_skill
        lda     cur_skill
        cmp     #NSKILLS
        bcc     @show
        lda     #0
        sta     cur_skill
@show:  jsr     show_marker
@lr:    lda     padnew          ; left / right: select, repeating when held
        and     #PAD_LEFT | PAD_RIGHT
        beq     @held
        lda     #8
        sta     rep_t
        bne     @move
@held:  lda     pad
        and     #PAD_LEFT | PAD_RIGHT
        beq     @a
        dec     rep_t
        bne     @a
        lda     #3
        sta     rep_t
@move:  lda     pad
        and     #PAD_RIGHT
        beq     @ml
        jsr     sel_next
        jmp     @a
@ml:    jsr     sel_prev
@a:     lda     padnew          ; A: give the skill
        and     #PAD_A
        beq     @r
        lda     cur_skill
        jmp     assign
@r:     rts

; pause until Start is pressed again (or a key)
pad_pause:
        jsr     sfx_hush
@l:     jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @done
        jsr     getc
        bcc     @l
@done:  jmp     flush_in

; the > in front of the chosen skill on the status line (gamepad only)
show_marker:
        lda     ctrl
        beq     @r
        jsr     txt_mode
        ldx     sh_mark
        bmi     @new
        lda     skill_col,x
        sec
        sbc     #9
        tax
        ldy     #HUD1
        jsr     gotoxy
        lda     #' '
        jsr     putc
@new:   ldx     cur_skill
        stx     sh_mark
        lda     skill_col,x
        sec
        sbc     #9
        tax
        ldy     #HUD1
        jsr     gotoxy
        lda     #'>'
        jsr     putc
@r:     rts

; ---- selecting a creature ------------------------------------------------------
; Creatures are ordered by x, then by number: key = x * 32 + number.
; sel_next picks the smallest key above the selected one (or the smallest of
; all), sel_prev the largest key below it (or the largest of all).

; key of creature X -> kh, kl
key_of: lda     c_x,x
        lsr
        lsr
        lsr
        sta     kh
        lda     c_x,x
        and     #7
        asl
        asl
        asl
        asl
        asl
        stx     tmp
        ora     tmp
        sta     kl
        rts

; carry set if creature X can be selected
selectable:
        lda     c_st,x
        beq     @no
        cmp     #ST_SPLAT
        bcs     @no
        sec
        rts
@no:    clc
        rts

sel_next:
        lda     #$FF            ; best = none
        sta     bh
        sta     bl
        lda     #0              ; current key (or -1 if none)
        sta     ch
        sta     cl
        ldx     sel
        bmi     @scan0
        jsr     key_of
        lda     kh
        sta     ch
        lda     kl
        sta     cl
@scan0: ldx     #0
@scan:  jsr     selectable
        bcc     @nx
        jsr     key_of
        ldy     sel             ; nothing selected: any key counts
        bmi     @ok
        lda     kh              ; key > current?
        cmp     ch
        bcc     @nx
        bne     @ok
        lda     kl
        cmp     cl
        bcc     @nx
        beq     @nx
@ok:    lda     kh              ; key < best?
        cmp     bh
        bcc     @take
        bne     @nx
        lda     kl
        cmp     bl
        bcs     @nx
@take:  lda     kh
        sta     bh
        lda     kl
        sta     bl
        stx     best
@nx:    inx
        cpx     #MAXC
        bne     @scan
        lda     bh
        cmp     #$FF
        bne     @found
        lda     sel             ; nothing to the right: wrap around
        bmi     @r
        lda     #$FF
        sta     sel
        jmp     sel_next
@found: lda     best
        sta     sel
@r:     rts

sel_prev:
        lda     #0              ; best = none (keys are never negative,
        sta     bh              ; so track "found" separately)
        sta     bl
        sta     found
        ldx     sel
        bmi     @scan0
        jsr     key_of
        lda     kh
        sta     ch
        lda     kl
        sta     cl
@scan0: ldx     #0
@scan:  jsr     selectable
        bcc     @nx
        jsr     key_of
        ldy     sel
        bmi     @ok
        lda     kh              ; key < current?
        cmp     ch
        bcc     @ok
        bne     @nx
        lda     kl
        cmp     cl
        bcs     @nx
@ok:    lda     found           ; key > best?
        beq     @take
        lda     kh
        cmp     bh
        bcc     @nx
        bne     @take
        lda     kl
        cmp     bl
        bcc     @nx
@take:  lda     kh
        sta     bh
        lda     kl
        sta     bl
        stx     best
        lda     #1
        sta     found
@nx:    inx
        cpx     #MAXC
        bne     @scan
        lda     found
        bne     @got
        lda     sel             ; nothing to the left: wrap around
        bmi     @r
        lda     #$FF
        sta     sel
        jmp     sel_prev
@got:   lda     best
        sta     sel
@r:     rts

; ---- giving the selected creature a skill (A = 0..5) ---------------------------
assign: sta     skl
        ldx     sel
        bmi     @no
        jsr     selectable
        bcc     @no
        ldy     skl
        lda     skills,y
        beq     @no
        lda     skl
        cmp     #2
        bcs     @job
        ; climber / floater: an ability, kept for good
        lda     ab_flag,y
        and     c_fl,x
        bne     @no             ; already has it
        lda     ab_flag,y
        ora     c_fl,x
        sta     c_fl,x
        jmp     @used
@job:   lda     c_st,x          ; jobs: only when on the ground
        cmp     #ST_WALK
        beq     @ok
        cmp     #ST_BUILD
        bcc     @no             ; falling, floating, climbing, blocking
        cmp     #ST_DIG+1
        bcs     @no
        cmp     job_state,y     ; already doing it
        beq     @no
@ok:    lda     job_state,y
        sta     c_st,x
        lda     job_timer,y
        sta     c_t,x
        lda     #BRICKS
        sta     c_n,x
@used:  lda     #SND_ASSIGN
        jsr     sfx_snd
        ldx     skl
        dec     skills,x
        jsr     txt_mode
        jmp     show_skill
@no:    rts

; ============================================================================
; moving the creatures
; ============================================================================
update_all:
        ldx     #0
@l:     stx     ci
        lda     c_st,x
        beq     @nx
        cmp     #ST_GONE
        beq     @nx
        ; copy into the work variables
        sta     cs
        lda     c_x,x
        sta     cx
        lda     c_y,x
        sta     cy
        lda     c_dir,x
        sta     cd
        lda     c_t,x
        sta     ct
        lda     c_fl,x
        sta     cf
        lda     c_fa,x
        sta     cfa
        lda     c_n,x
        sta     cn
        ldy     cs              ; run the handler for its state
        lda     st_lo,y
        sta     @j+1
        lda     st_hi,y
        sta     @j+2
@j:     jsr     $FFFF
        ldx     ci              ; copy back
        lda     cs
        sta     c_st,x
        lda     cx
        sta     c_x,x
        lda     cy
        sta     c_y,x
        lda     cd
        sta     c_dir,x
        lda     ct
        sta     c_t,x
        lda     cf
        sta     c_fl,x
        lda     cfa
        sta     c_fa,x
        lda     cn
        sta     c_n,x
@nx:    ldx     ci
        inx
        cpx     #MAXC
        beq     @end
        jmp     @l
@end:   rts

start_fall:
        lda     #ST_FALL
        sta     cs
        lda     #0
        sta     cfa
        rts

turn:   lda     cd
        eor     #$FE            ; 1 <-> $FF
        sta     cd
        rts

; carry set if the ground under the creature is solid
on_ground:
        ldx     cx
        ldy     cy
        iny
        jmp     solid

; ---- walking ----------------------------------------------------------------
h_walk: jsr     on_ground
        bcs     @ground
        jmp     start_fall
@ground:lda     cx              ; at the exit?
        cmp     ex
        bne     @noexit
        lda     cy
        cmp     ey
        bne     @noexit
        lda     #ST_GONE
        sta     cs
        inc     saved
        lda     #SND_SAVED
        jmp     sfx_snd
@noexit:lda     cx
        clc
        adc     cd
        sta     nx
        jsr     blocker_ahead
        bcs     @turn
        ldx     nx
        ldy     cy
        jsr     solid
        bcc     @flat
        dey                     ; something at foot level: step up?
        jsr     solid
        bcs     @up2
        dey
        jsr     solid
        bcs     @wall
        lda     nx              ; up 1
        sta     cx
        dec     cy
        rts
@up2:   dey
        jsr     solid
        bcs     @wall
        dey
        jsr     solid
        bcs     @wall
        lda     nx              ; up 2
        sta     cx
        dec     cy
        dec     cy
        rts
@wall:  lda     cf
        and     #F_CLIMB
        beq     @turn
        lda     #ST_CLIMB
        sta     cs
        rts
@turn:  jmp     turn
@flat:  dey                     ; room for the head?
        jsr     solid
        bcs     @wall
        lda     nx
        sta     cx
        ldx     cx              ; a 1 pixel step down?
        ldy     cy
        iny
        jsr     solid
        bcs     @r
        iny
        jsr     solid
        bcc     @r
        inc     cy
@r:     rts

; carry set if a blocker stands at column nx, near this creature's height
blocker_ahead:
        ldx     #MAXC-1
@l:     cpx     ci
        beq     @nx
        lda     c_st,x
        cmp     #ST_BLOCK
        bne     @nx
        lda     c_x,x
        cmp     nx
        bne     @nx
        lda     c_y,x
        sec
        sbc     cy
        clc
        adc     #4
        cmp     #9
        bcc     @yes
@nx:    dex
        bpl     @l
        clc
        rts
@yes:   sec
        rts

; ---- falling: 2 pixels per tick ------------------------------------------------
h_fall: lda     #2
        sta     tmp
@l:     jsr     on_ground
        bcs     @land
        inc     cy
        lda     cfa
        cmp     #250
        bcs     @capped
        inc     cfa
@capped:lda     cy
        cmp     #FH
        bcs     @out
        lda     cf              ; floaters open their umbrella after a bit
        and     #F_FLOAT
        beq     @nf
        lda     cfa
        cmp     #8
        bcc     @nf
        lda     #ST_FLOAT
        sta     cs
        rts
@nf:    dec     tmp
        bne     @l
        rts
@land:  lda     cfa
        cmp     #SPLAT_H+1
        bcs     @splat
        lda     #ST_WALK
        sta     cs
        rts
@splat: lda     #SND_SPLAT
        jsr     sfx_snd
        lda     #ST_SPLAT
        sta     cs
        lda     #8
        sta     ct
        rts
@out:   lda     #ST_GONE        ; fell off the bottom
        sta     cs
        rts

; ---- floating: 1 pixel every other tick ----------------------------------------
h_float:jsr     on_ground
        bcc     @air
        lda     #ST_WALK
        sta     cs
        rts
@air:   lda     ct
        eor     #1
        sta     ct
        beq     @r
        inc     cy
        lda     cy
        cmp     #FH
        bcc     @r
        lda     #ST_GONE
        sta     cs
@r:     rts

; ---- climbing: 1 pixel per tick ------------------------------------------------
h_climb:lda     cx
        clc
        adc     cd
        tax
        ldy     cy
        jsr     solid
        bcs     @still
        stx     cx              ; over the top
        lda     #ST_WALK
        sta     cs
        rts
@still: ldx     cx
        ldy     cy
        dey
        dey
        jsr     solid
        bcs     @ceil
        dec     cy
        rts
@ceil:  jsr     turn            ; hit a ceiling: let go
        jmp     start_fall

; ---- blocking ------------------------------------------------------------------
h_block:jsr     on_ground
        bcs     @r
        jmp     start_fall
@r:     rts

; ---- building: a brick every 2 ticks, BRICKS of them -----------------------------
h_build:jsr     on_ground
        bcs     @g
        jmp     start_fall
@g:     dec     ct
        bne     @r
        lda     #2
        sta     ct
        lda     cn
        beq     @done
        lda     cx              ; head room for the next step?
        clc
        adc     cd
        sta     nx
        tax
        ldy     cy
        dey
        jsr     solid
        bcs     @blocked
        dey
        jsr     solid
        bcs     @blocked
        lda     #SND_BRICK
        jsr     sfx_snd
        ldy     cy              ; lay a 3 pixel brick at foot level ahead
        ldx     nx
        jsr     build_px
        txa
        clc
        adc     cd
        tax
        jsr     build_px
        txa
        clc
        adc     cd
        tax
        jsr     build_px
        lda     nx              ; and step up onto it
        sta     cx
        dec     cy
        dec     cn
        rts
@blocked:
        jsr     turn
@done:  lda     #ST_WALK
        sta     cs
@r:     rts

; ---- bashing: one column every 2 ticks ----------------------------------------
h_bash: jsr     on_ground
        bcs     @g
        jmp     start_fall
@g:     dec     ct
        bne     @r
        lda     #2
        sta     ct
        lda     #6              ; anything to bash in the next 6 pixels?
        sta     tmp
        lda     cx
        sta     nx
@scan:  lda     nx
        clc
        adc     cd
        sta     nx
        tax
        cpx     #FW
        bcs     @none           ; the edge of the screen isn't bashable
        ldy     cy
        jsr     solid
        bcs     @found
        dey
        jsr     solid
        bcs     @found
        dec     tmp
        bne     @scan
@none:  lda     #ST_WALK
        sta     cs
@r:     rts
@found: lda     #SND_DIG
        jsr     sfx_snd
        lda     cx              ; clear the column in front, 3 pixels high
        clc
        adc     cd
        tax
        ldy     cy
        jsr     dig_px
        dey
        jsr     dig_px
        dey
        jsr     dig_px
        stx     cx
        rts

; ---- digging: one row every 3 ticks -------------------------------------------
h_dig:  dec     ct
        bne     @r
        lda     #3
        sta     ct
        ldy     cy
        iny
        cpy     #FH
        bcs     @fall
        lda     #0
        sta     tmp
        ldx     cx
        dex
        jsr     dig_px
        rol     tmp
        inx
        jsr     dig_px
        rol     tmp
        inx
        jsr     dig_px
        rol     tmp
        lda     tmp
        beq     @fall           ; dug through
        lda     #SND_DIG
        jsr     sfx_snd
        inc     cy
@r:     rts
@fall:  jmp     start_fall

; ---- splat: shown for a few ticks ------------------------------------------------
h_splat:dec     ct
        bne     @r
        lda     #ST_GONE
        sta     cs
@r:     rts

; ============================================================================
; redraw: erase every creature where it was drawn, then draw them all where
; they are now (so overlapping creatures come out right)
; ============================================================================
redraw_all:
        lda     #0
        sta     dirty_h
        sta     dirty_d
        lda     #1
        sta     s_op
        ldx     #MAXC-1
@er:    lda     d_on,x
        beq     @en
        stx     ci
        lda     d_x,x
        sta     sx
        lda     d_y,x
        sta     sy
        ldy     d_shp,x
        jsr     shape_op
        ldx     ci
        lda     d_on,x
        and     #2
        beq     @nm
        ldy     #SHP_MARK
        jsr     shape_op
        ldx     ci
@nm:    lda     #0
        sta     d_on,x
@en:    dex
        bpl     @er
        lda     dirty_h
        beq     @dh
        jsr     draw_hatch
@dh:    lda     dirty_d
        beq     @dd
        jsr     draw_door
@dd:    ; drop the selection if that creature has gone
        ldx     sel
        bmi     @draw
        jsr     selectable
        bcs     @draw
        lda     #$FF
        sta     sel
@draw:  lda     #0
        sta     s_op
        sta     out
        sta     nblock
        ldx     #MAXC-1
@dr:    lda     c_st,x
        beq     @dn
        cmp     #ST_GONE
        beq     @dn
        stx     ci
        inc     out
        cmp     #ST_BLOCK
        bne     @nb
        inc     nblock
@nb:    tay
        lda     st_shape,y
        sta     d_shp,x
        tay
        lda     c_x,x
        sta     sx
        sta     d_x,x
        lda     c_y,x
        sta     sy
        sta     d_y,x
        jsr     shape_op
        ldx     ci
        lda     #1
        cpx     sel
        bne     @ns
        ldy     #SHP_MARK
        jsr     shape_op
        ldx     ci
        lda     #3
@ns:    sta     d_on,x
@dn:    dex
        bpl     @dr
        rts

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
        .include "critters_sound.inc"   ; the tune and effects (game_sounds.py)

; handlers by state
st_lo:  .byte   0, <h_walk, <h_fall, <h_float, <h_climb, <h_block
        .byte   <h_build, <h_bash, <h_dig, <h_splat
st_hi:  .byte   0, >h_walk, >h_fall, >h_float, >h_climb, >h_block
        .byte   >h_build, >h_bash, >h_dig, >h_splat

; shapes: (dx, dy) pairs, $80 ends
SHP_NORMAL = 0
SHP_FLOAT  = 1
SHP_BLOCK  = 2
SHP_SPLAT  = 3
SHP_MARK   = 4
shp_ofs:.byte   s0-shp_data, s1-shp_data, s2-shp_data, s3-shp_data, s4-shp_data
shp_data:
s0:     .byte   0,0, 0,$FF, $80                         ; standing
s1:     .byte   0,0, 0,$FF, 0,$FE, $FF,$FD, 0,$FD, 1,$FD, $80 ; umbrella
s2:     .byte   0,0, 0,$FF, $FF,$FF, 1,$FF, $80         ; arms out
s3:     .byte   $FF,0, 0,0, 1,0, $80                    ; splat
s4:     .byte   0,$FB, $80                              ; selection mark
st_shape:
        .byte   0, SHP_NORMAL, SHP_NORMAL, SHP_FLOAT, SHP_NORMAL, SHP_BLOCK
        .byte   SHP_NORMAL, SHP_NORMAL, SHP_NORMAL, SHP_SPLAT

st_names:
        .byte   "--------", "WALKER  ", "FALLER  ", "FLOATER ", "CLIMBER "
        .byte   "BLOCKER ", "BUILDER ", "BASHER  ", "DIGGER  ", "SPLAT   "

; skills 0..5: climber, floater (abilities), blocker, builder, basher, digger
ab_flag:   .byte F_CLIMB, F_FLOAT
job_state = * - 2
           .byte ST_BLOCK, ST_BUILD, ST_BASH, ST_DIG
job_timer = * - 2
           .byte 1, 2, 2, 3
skill_col: .byte 9, 22, 35, 48, 61, 74

mask_hi:.byte   $80, $40, $20, $10, $08, $04, $02, $01

trow_lo:
.repeat FH, I
        .byte   <(terrain + I * TBW)
.endrepeat
trow_hi:
.repeat FH, I
        .byte   >(terrain + I * TBW)
.endrepeat

; ---- text ----------------------------------------------------------------------
cls_txt:.byte   TC_CLS, TC_CURSOR, 0, TERM
title_txt:
        .byte   TC_CLS, TC_CURSOR, 0
        .byte   TC_ROW, 2, TC_COL, 34, RV_ON, " CRITTERS ", RV_OFF, TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 4, TC_COL, 18, "GUIDE THE CRITTERS FROM THE HATCH TO THE EXIT"
        .byte   TC_ROW, 10, TC_COL, 14, ",  .  OR  <- ->  SELECT THE CRITTER TO THE LEFT/RIGHT"
        .byte   TC_ROW, 11, TC_COL, 14, "1 CLIMBER  2 FLOATER  3 BLOCKER"
        .byte   TC_ROW, 12, TC_COL, 14, "4 BUILDER  5 BASHER   6 DIGGER"
        .byte   TC_ROW, 13, TC_COL, 14, "+ -  RELEASE RATE      P PAUSE   K NUKE"
        .byte   TC_ROW, 14, TC_COL, 14, "R  RESTART THE LEVEL   M SOUND   Q QUIT"
        .byte   TC_ROW, 15, TC_COL, 5, "GAMEPAD: LEFT/RIGHT SELECT  UP/DOWN PICK A SKILL  A GIVE IT  START PAUSE"
        .byte   TC_ROW, 16, TC_COL, 14, "B + UP/DOWN RELEASE RATE   SELECT + A NUKE"
        .byte   TC_ROW, 22, TC_COL, 13, "SPACE OR START TO PLAY, 1-6 OR UP/DOWN FOR A LEVEL", TERM
startlv_txt:
        .byte   "START AT LEVEL ", TERM
bye_txt:.byte   TC_CLS, TC_CURSOR, '_', TERM

ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM
intro_txt:
        .byte   TC_CLS, TC_CURSOR, 0, TC_ROW, 9, TC_COL, 26, "LEVEL ", TERM
save_txt:
        .byte   "SAVE ", TERM
of_txt: .byte   " OF ", TERM
intro2_txt:
        .byte   TC_ROW, 14, TC_COL, 26, "SPACE/A: GO    Q: TITLE", TERM
hud_txt:
        .byte   TC_ROW, HUD1, TC_COL, 1,  "1 CLIMB"
        .byte   TC_COL, 14, "2 FLOAT"
        .byte   TC_COL, 27, "3 BLOCK"
        .byte   TC_COL, 40, "4 BUILD"
        .byte   TC_COL, 53, "5 BASH"
        .byte   TC_COL, 66, "6 DIG"
        .byte   TC_ROW, HUD2, TC_COL, 1, "OUT"
        .byte   TC_COL, 9, "IN"
        .byte   TC_COL, 16, "NEED"
        .byte   TC_COL, 25, "RATE"
        .byte   TC_COL, 34, "TIME"
        .byte   TC_COL, 45, "SEL", TERM
end_txt:
        .byte   TC_ROW, 8, TC_COL, 26, RV_ON, "                            "
        .byte   TC_ROW, 9, TC_COL, 26, "  SAVED ", TERM
end2_txt:
        .byte   "   NEEDED ", TERM
well_txt:
        .byte   "      "
        .byte   TC_ROW, 10, TC_COL, 26, "                            "
        .byte   TC_ROW, 11, TC_COL, 26, "  WELL DONE!                "
        .byte   TC_ROW, 12, TC_COL, 26, "  SPACE/A: NEXT    Q: QUIT  "
        .byte   TC_ROW, 13, TC_COL, 26, "                            ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM
fail_txt:
        .byte   "      "
        .byte   TC_ROW, 10, TC_COL, 26, "                            "
        .byte   TC_ROW, 11, TC_COL, 26, "  NOT ENOUGH SAVED          "
        .byte   TC_ROW, 12, TC_COL, 26, "  SPACE/A: RETRY   Q: QUIT  "
        .byte   TC_ROW, 13, TC_COL, 26, "                            ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM
alldone_txt:
        .byte   "      "
        .byte   TC_ROW, 10, TC_COL, 26, "                            "
        .byte   TC_ROW, 11, TC_COL, 26, "  ALL LEVELS DONE - BRAVO!  "
        .byte   TC_ROW, 12, TC_COL, 26, "  SPACE/A: TITLE            "
        .byte   TC_ROW, 13, TC_COL, 26, "                            ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM

; ============================================================================
; levels
;   total, need, release rate, time (seconds, BCD, low byte first),
;   skills: climber, floater, blocker, builder, basher, digger,
;   hatch x, y (where creatures appear), exit x, y (where they stand),
;   name ($FF), then terrain commands, 0:
;     'R', x, y, w, h     filled rectangle
;     'U', x, y, w        ramp of w columns rising to the right, base row y
;     'D', x, y, w        ramp falling to the right
; The playfield is 160 x 88 pixels.
; ============================================================================
lv_tab_lo: .byte <lv1, <lv2, <lv3, <lv4, <lv5, <lv6
lv_tab_hi: .byte >lv1, >lv2, >lv3, >lv4, >lv5, >lv6

lv1:    .byte   10, 7, 50, $00, $02
        .byte   0, 0, 0, 0, 0, 3
        .byte   40, 20, 120, 55
        .byte   "JUST DIG", TERM
        .byte   'R', 20, 30, 120, 6     ; the upper floor
        .byte   'R', 16, 8, 4, 28       ; its walls
        .byte   'R', 140, 8, 4, 28
        .byte   'R', 0, 56, 160, 32     ; the ground
        .byte   'R', 0, 36, 4, 20       ; its walls
        .byte   'R', 156, 36, 4, 20
        .byte   'U', 60, 55, 8          ; a little hill
        .byte   'D', 68, 55, 8
        .byte   0

lv2:    .byte   10, 8, 50, $00, $02
        .byte   0, 0, 2, 0, 0, 0
        .byte   70, 40, 20, 59
        .byte   "HOLD THE LINE", TERM
        .byte   'R', 0, 60, 110, 28     ; the ground ends in a cliff
        .byte   'R', 0, 30, 4, 30
        .byte   'U', 26, 59, 4
        .byte   'R', 30, 56, 4, 4
        .byte   'D', 34, 59, 4
        .byte   0

lv3:    .byte   10, 8, 30, $00, $03
        .byte   0, 0, 0, 0, 2, 0
        .byte   20, 50, 130, 59
        .byte   "BASH IT", TERM
        .byte   'R', 0, 60, 160, 28
        .byte   'R', 0, 30, 4, 30
        .byte   'R', 156, 30, 4, 30
        .byte   'R', 70, 16, 20, 44     ; the rock
        .byte   'U', 62, 59, 8
        .byte   0

lv4:    .byte   10, 7, 20, $00, $03
        .byte   0, 0, 0, 4, 0, 0
        .byte   20, 40, 130, 45
        .byte   "MIND THE GAP", TERM
        .byte   'R', 0, 50, 60, 38      ; left cliff
        .byte   'R', 68, 46, 92, 42     ; right cliff, a bit higher
        .byte   'R', 0, 20, 4, 30
        .byte   'R', 156, 16, 4, 30
        .byte   0

lv5:    .byte   10, 6, 30, $00, $04
        .byte   10, 10, 0, 0, 0, 0
        .byte   15, 60, 140, 83
        .byte   "UP AND OVER", TERM
        .byte   'R', 0, 70, 80, 18      ; left ground
        .byte   'R', 0, 40, 4, 30
        .byte   'R', 80, 30, 8, 58      ; the pillar
        .byte   'R', 88, 84, 72, 4      ; far below on the right
        .byte   'R', 156, 60, 4, 24
        .byte   0

lv6:    .byte   15, 10, 30, $00, $06
        .byte   0, 0, 0, 3, 2, 2
        .byte   15, 20, 140, 55
        .byte   "THE WORKS", TERM
        .byte   'R', 0, 30, 50, 6       ; upper left ledge
        .byte   'R', 0, 10, 4, 20
        .byte   'R', 58, 30, 70, 6      ; the plateau, across a gap
        .byte   'R', 58, 25, 2, 5       ; a lip so they don't walk back off it
        .byte   'R', 90, 12, 8, 18      ; a rock on it
        .byte   'R', 124, 10, 4, 20     ; its end wall
        .byte   'R', 62, 56, 98, 32     ; the floor below
        .byte   'R', 156, 36, 4, 20
        .byte   0

; ============================================================================
; variables (not in the file)
; ============================================================================
bitmask8:   .byte   $01, $02, $04, $08, $10, $20, $40, $80
srow_lo:
.repeat 24, R
        .byte   <(want + R * 80)
.endrepeat
srow_hi:
.repeat 24, R
        .byte   >(want + R * 80)
.endrepeat

        .segment "BSS"
bss_start:
attr:       .res 1
ctrl:       .res 1              ; 0 keyboard, 1 gamepad
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
cur_skill:  .res 1              ; gamepad: the skill A gives
sh_mark:    .res 1
rep_t:      .res 1
level:      .res 1
total:      .res 1
need:       .res 1
rate:       .res 1
min_rate:   .res 1
time_bcd:   .res 2
skills:     .res NSKILLS
hx:         .res 1
hy:         .res 1
ex:         .res 1
ey:         .res 1
name_ptr:   .res 2
released:   .res 1
saved:      .res 1
out:        .res 1
nblock:     .res 1
rel_t:      .res 1
tdiv:       .res 1
nuking:     .res 1
action:     .res 1
esc_st:     .res 1
sel:        .res 1
skl:        .res 1
; creatures
c_x:        .res MAXC
c_y:        .res MAXC
c_dir:      .res MAXC
c_st:       .res MAXC
c_t:        .res MAXC
c_fl:       .res MAXC
c_fa:       .res MAXC
c_n:        .res MAXC
d_x:        .res MAXC       ; where it was last drawn
d_y:        .res MAXC
d_shp:      .res MAXC
d_on:       .res MAXC       ; bit 0 drawn, bit 1 with the selection mark
; the creature being moved
ci:         .res 1
cs:         .res 1
cx:         .res 1
cy:         .res 1
cd:         .res 1
ct:         .res 1
cf:         .res 1
cfa:        .res 1
cn:         .res 1
nx:         .res 1
; status line values on screen
sh_out:     .res 1
sh_saved:   .res 1
sh_rate:    .res 1
sh_sel:     .res 1
; selection search
kh:         .res 1
kl:         .res 1
ch:         .res 1
cl:         .res 1
bh:         .res 1
bl:         .res 1
best:       .res 1
found:      .res 1
; drawing
sx:         .res 1
sy:         .res 1
s_op:       .res 1
s_i:        .res 1
dirty_h:    .res 1
dirty_d:    .res 1
t_y:        .res 1
t_mask:     .res 1
; level building / rendering
cmd:        .res 1
rx:         .res 1
ry:         .res 1
rw:         .res 1
rh:         .res 1
fy:         .res 1
fh:         .res 1
fw:         .res 1
rr:         .res 1
rc:         .res 1
rgap:       .res 1
pat:        .res 1
tmp:        .res 1
tmp2:       .res 1
DLMAX = 200
dl_n:       .res 1              ; characters changed since the last flush
dl_full:    .res 1
dl_i:       .res 1
dl_c:       .res DLMAX
dl_r:       .res DLMAX
px_x:       .res 1
px_y:       .res 1
pc_col:     .res 1
pc_row:     .res 1
pmask:      .res 1
pold:       .res 1
tmp_c:      .res 1
tmp_r:      .res 1
cur_x:      .res 1              ; where the cursor is (cur_y $FF: unknown)
cur_y:      .res 1
bss_end:

        .segment "TERRAIN"
want:       .res 2048           ; the screen as it should be (80 x 24 characters)
shown:      .res 2048           ; the screen as the terminal shows it
terrain:    .res 7 * 256        ; 88 rows x 20 bytes (1760) in 7 pages
