; ============================================================================
; stacker.s - STACKER, a falling blocks game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal in its
; control code mode (terminal setup item J must be ON).
;
;   build:  make                (needs sbc_api.inc, the ROM's entry points)
;   run:    L STACKER 0500   then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  length of a game tick in ms (default 15; bigger = slower)
;   $0504  controls at start: 0 keyboard, 1 gamepad
;   $0505  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2): music and effects, in stacker_sound.inc (made by
; ../ay/tools/game_sounds.py).  Without the card the game is just silent.
;
; Keys:   A / D or Left / Right   move          W, Up or X   rotate
;         Z                       rotate back   S or Down    drop one row
;         Space                   drop          P pause      Q quit
;         M                       sound on / off
; Gamepad: d-pad left / right move (held: repeats), down drops one row at a
;         time, up drops; A rotates, B rotates back, Start pauses
;
; The board is 10 x 20 squares (plus 2 hidden rows above it).  A square is
; 4 x 4 pixels, two block graphics characters, so square (x, y) of the
; visible board is at text column BX + 2x, row BY + y.
; The board is kept in RAM (0 empty, 1..7 the piece that left it there).
; Each tick the picture of the board (locked squares + the ghost + the
; falling piece) is put together in disp[] and compared with shown[], what
; the terminal shows; only the squares that differ are sent.
; No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 15

; ---- terminal control codes --------------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
TC_TILE         = $0B           ; 0B n: draw tile n (terminal v1.4)
TC_DEFTILE      = $19           ; 19 n c r data: define tile n
T_LEFT          = 11            ; tile slots of the well's sides (1 x 20: slots
T_RIGHT         = 12            ; 11 and 12 of that size are bytes 220-259 of the pool,
                                ; clear of the squares' 0-21)
ATTR_TEXT       = $00
ATTR_RV         = $04
; reverse video is an ANSI sequence (in terminal v1.4, attribute bit 2 is the
; double size font, not reverse)
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
ATTR_GFX        = $80
TERM            = $FF

; ---- layout ------------------------------------------------------------------------
BW              = 10            ; board width
BH              = 22            ; board height, rows 0 and 1 hidden
HIDDEN          = 2
VIS             = 200           ; visible squares (10 x 20)
BX              = 30            ; text column of the board's left edge
BY              = 2             ; text row of its top (visible row 0)
NX              = 56            ; the NEXT box: text column, row
NY              = 4
SX              = 56            ; numbers on the right
G_EMPTY         = 0             ; glyphs (see gen.py)
G_GHOST         = 8
G_FLASH         = 9
G_BLANK         = 10

LOCK_TICKS      = 30            ; grounded this long: the piece locks
LOCK_RESETS     = 15            ; moves that may restart the lock timer
DAS_DELAY       = 12            ; gamepad: ticks before a held move repeats
DAS_RATE        = 3             ; ... and between repeats

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
; I/O helpers
; ----------------------------------------------------------------------------
putc            = SBC_CHROUT    ; preserves A, X, Y
getc            = SBC_CHRIN     ; carry set = key in A

; cursor to column X, row Y (preserves X, Y)
gotoxy: lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
        lda     #TC_COL
        jsr     putc
        txa
        jsr     putc
        lda     #$FF            ; the board's cursor tracking is now unsure
        sta     cur_y
        rts

; cursor to column X of the current row (preserves X, Y)
setcol: lda     #TC_COL
        jsr     putc
        txa
        jmp     putc

; print the string at A (lo) / Y (hi), ended by TERM (any length)
print:  sta     @ld+1
        sty     @ld+2
@ld:    lda     $FFFF
        cmp     #TERM
        beq     @done
        jsr     putc
        inc     @ld+1
        bne     @ld
        inc     @ld+2
        bne     @ld
@done:  lda     #$FF            ; strings may move the cursor or change
        sta     cur_y           ; the attribute: both unknown now
        sta     attr
        rts

txt_mode:
        lda     attr
        beq     @r
        lda     #ATTR_TEXT
        beq     set_attr
@r:     rts
gfx_mode:                       ; block graphics, no repeat
        lda     attr
        cmp     #ATTR_GFX
        bne     @set
        rts
@set:   lda     #ATTR_GFX
set_attr:
        pha                     ; the repeat count that goes with it
        and     #$78
        lsr
        lsr
        lsr
        bne     @rc
        lda     #1
@rc:    sta     cur_rep
        pla
        sta     attr
        pha
        lda     #TC_ATTR
        jsr     putc
        pla
        jmp     putc

; send A as a block graphics character (control codes need the 1A prefix)
putblk: cmp     #$20
        bcc     @lit
        cmp     #$7F
        bne     @put
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@put:   jmp     putc

; glyph A (a square, two characters): it is terminal tile A
put_glyph:
        pha
        lda     #TC_TILE
        jsr     putc
        pla
        jmp     putc

; store the squares in the terminal as tiles 0..NGLYPH-1 (2 x 1 characters),
; and the well's sides as tiles (1 x 20)
def_tiles:
        ldx     #0
@g:     lda     #TC_DEFTILE
        jsr     putc
        txa
        jsr     putc            ; slot = glyph number
        lda     #2
        jsr     putc
        lda     #1
        jsr     putc
        lda     glyph_l,x
        jsr     putc            ; (tile data needs no 1A prefix)
        lda     glyph_r,x
        jsr     putc
        inx
        cpx     #NGLYPH
        bne     @g
        lda     #$AA            ; the left side: right hand pixels
        ldx     #T_LEFT
        jsr     @side
        lda     #$55            ; the right side: left hand pixels
        ldx     #T_RIGHT
@side:  sta     tmp
        lda     #TC_DEFTILE
        jsr     putc
        txa
        jsr     putc
        lda     #1
        jsr     putc
        lda     #20
        jsr     putc
        ldx     #20
        lda     tmp
@s:     jsr     putc
        dex
        bne     @s
        rts

; repeat each character (and tile) A times from now on (1..15), block graphics
set_rep:cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        bne     @set
@one:   lda     #ATTR_GFX
@set:   cmp     attr            ; (graphics on and this count already?)
        beq     @r
        jmp     set_attr
@r:     rts

; print A as two BCD digits
prbcd:  pha
        lsr
        lsr
        lsr
        lsr
        ora     #'0'
        jsr     putc
        pla
        and     #$0F
        ora     #'0'
        jmp     putc

; print A (0..99) as two decimal digits
pr_dec2:ldx     #'0'
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     pha
        txa
        jsr     putc
        pla
        ora     #'0'
        jmp     putc

; 16 bit Galois LFSR.  A = a random byte.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait about A ms.  The inner loop is sized for the clock (CLOCK_MHZ in
; sbc_api.inc): 5 + 4 * (CLOCK_MHZ - 1) cycles a turn, DELAY_N turns a ms.
DELAY_N = (1000 * CLOCK_MHZ - 7) / (5 + 4 * (CLOCK_MHZ - 1))
delay_ms:
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

.macro MENU_IDLE
        jsr     rand            ; (waiting for a key stirs the random numbers)
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
; start, title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear the variables (RAM is random at power-up)
        tax
        ldy     #>(bss_end - bss_start + $FF)
@c1:    sta     bss_start,x
        inx
        bne     @c1
        inc     @c1+2
        dey
        bne     @c1
        lda     ctrl_def
        sta     ctrl
        lda     #$5A
        sta     rng
        lda     #$FF
        sta     attr
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute

title:  jsr     sfx_off
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     def_tiles
        jsr     draw_banner
        jsr     show_start_level
        jsr     show_hiscore_title
        jsr     show_ctrl
        jsr     read_pad
        jsr     flush_in
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @notq
        jmp     exit_game
@notq:  cmp     #'M'            ; sound on / off
        bne     @notm
        jsr     sfx_toggle
        jmp     @wait
@notm:  cmp     #'G'            ; switch keyboard / gamepad
        bne     @notg
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@notg:  cmp     #PAD_GO         ; A or Start on the pad: play with the pad
        bne     @notp
        lda     #1
        sta     ctrl
        jmp     new_game
@notp:  cmp     #' '
        bne     @digit
        jmp     new_game
@digit: cmp     #'0'            ; 0..9: the starting level
        bcc     @wait
        cmp     #'9'+1
        bcs     @wait
        and     #$0F
        sta     start_level
        jsr     show_start_level
        jmp     @wait

; the title banner, made of squares
draw_banner:
        jsr     gfx_mode
        lda     #<banner
        sta     @rd+1
        lda     #>banner
        sta     @rd+2
        ldy     #2              ; text row
@row:   sty     tmp2
        ldx     #40 - BANNER_W
        jsr     gotoxy
        lda     #BANNER_W
        sta     tmp3
@sq:
@rd:    lda     $FFFF
        jsr     put_glyph
        inc     @rd+1
        bne     @n
        inc     @rd+2
@n:     dec     tmp3
        bne     @sq
        ldy     tmp2
        iny
        cpy     #2 + BANNER_H
        bne     @row
        rts

show_start_level:
        jsr     txt_mode
        ldx     #48
        ldy     #15
        jsr     gotoxy
        lda     start_level
        clc
        adc     #'0'
        jmp     putc

show_hiscore_title:
        jsr     txt_mode
        ldx     #34
        ldy     #21
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
        jmp     pr_hiscore

pr_hiscore:
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jmp     prbcd

exit_game:
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
        jmp     SBC_MENU        ; back to the boot menu

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        ldx     #BW * BH - 1    ; empty board
@b:     sta     board,x
        dex
        cpx     #$FF
        bne     @b
        ldx     #VIS - 1        ; the terminal shows nothing yet
        lda     #$FF
@s:     sta     shown,x
        dex
        cpx     #$FF
        bne     @s
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     lines
        sta     lines+1
        sta     quit
        sta     dead
        sta     bag_n
        lda     start_level
        sta     level
        lda     #10
        sta     to_next
        jsr     screen_setup
        jsr     bag_next
        sta     next
        jsr     spawn
        jsr     show_stats
        jsr     sfx_off         ; the music
        lda     #MUS_THEME
        jsr     sfx_snd
        lda     #MUS_THEME+1
        jsr     sfx_snd

game_loop:
        jsr     sfx_poll
        inc     ticks
        jsr     input
        lda     quit
        beq     @1
        jmp     title
@1:     lda     need_lock
        bne     @lock
        jsr     gravity
        lda     need_lock
        beq     @2
@lock:  jsr     lock_piece
        lda     dead
        beq     @2
        jmp     game_over
@2:     lda     dirty
        beq     @3
        jsr     compose
        jsr     present
        lda     #0
        sta     dirty
@3:     lda     speed
        jsr     delay_ms
        jmp     game_loop

; ---- the screen around the board ------------------------------------------------
screen_setup:
        lda     #<game_txt
        ldy     #>game_txt
        jsr     print
        lda     ctrl            ; the controls for this game
        beq     @kb
        lda     #<help_pad_txt
        ldy     #>help_pad_txt
        jsr     print
        jmp     @frame
@kb:    lda     #<help_kb_txt
        ldy     #>help_kb_txt
        jsr     print
@frame: jsr     gfx_mode        ; the well: a line each side and below
        ldx     #BX-1
        ldy     #BY
        jsr     gotoxy
        lda     #TC_TILE
        jsr     putc
        lda     #T_LEFT
        jsr     putc
        ldx     #BX+2*BW
        jsr     gotoxy
        lda     #TC_TILE
        jsr     putc
        lda     #T_RIGHT
        jsr     putc
        ldx     #BX-1
        ldy     #BY+20
        jsr     gotoxy
        lda     #$02            ; corner
        jsr     putblk
        lda     #10             ; top pixel row, 20 times (the repeat count
        jsr     set_rep         ; goes up to 15, so twice 10)
        lda     #$03
        jsr     putblk
        lda     #$03
        jsr     putblk
        lda     #1
        jsr     set_rep
        lda     #$01
        jsr     putblk
        rts

; score, lines, level
show_stats:
        jsr     txt_mode
        ldx     #SX
        ldy     #11
        jsr     gotoxy
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        ldx     #SX+2
        ldy     #14
        jsr     gotoxy
        lda     lines+1
        jsr     prbcd
        lda     lines
        jsr     prbcd
        ldx     #SX+4
        ldy     #17
        jsr     gotoxy
        lda     level
        jsr     pr_dec2
        ldx     #SX
        ldy     #20
        jsr     gotoxy
        jmp     pr_hiscore

; the next piece in its box (4 x 2 squares)
draw_next:
        ldx     #7
        lda     #G_BLANK
@c:     sta     nbuf,x
        dex
        bpl     @c
        lda     next
        asl
        asl
        asl
        asl
        tay                     ; rotation 0 of that piece
        ldx     #4
@sq:    lda     pc_y,y
        asl
        asl
        clc
        adc     pc_x,y
        sta     tmp
        lda     next
        clc
        adc     #1
        stx     tmp2
        ldx     tmp
        sta     nbuf,x
        ldx     tmp2
        iny
        dex
        bne     @sq
        jsr     gfx_mode
        ldx     #NX+1
        ldy     #NY+1
        jsr     gotoxy
        ldx     #0
@r0:    stx     tmp2
        lda     nbuf,x
        jsr     put_glyph
        ldx     tmp2
        inx
        cpx     #4
        bne     @r0
        ldx     #NX+1
        ldy     #NY+2
        jsr     gotoxy
        ldx     #4
@r1:    stx     tmp2
        lda     nbuf,x
        jsr     put_glyph
        ldx     tmp2
        inx
        cpx     #8
        bne     @r1
        rts

; ---- pieces -----------------------------------------------------------------------
; the next piece from the bag: each run of 7 has every piece once
bag_next:
        lda     bag_n
        bne     @take
        ldx     #6              ; refill and shuffle (Fisher-Yates)
@f:     txa
        sta     bag,x
        dex
        bpl     @f
        ldx     #6
@sh:    stx     tmp
@r:     jsr     rand            ; j = random 0..x
        and     #7
        cmp     tmp
        beq     @ok
        bcs     @r
@ok:    tay
        lda     bag,x
        pha
        lda     bag,y
        sta     bag,x
        pla
        sta     bag,y
        dex
        bne     @sh
        lda     #7
        sta     bag_n
@take:  dec     bag_n
        ldx     bag_n
        lda     bag,x
        rts

; the next piece comes in at the top
spawn:  inc     npieces
        lda     next
        sta     ptype
        jsr     bag_next
        sta     next
        lda     #3
        sta     px
        lda     #1
        sta     py
        lda     #0
        sta     prot
        sta     ltimer
        sta     lresets
        sta     gcount
        sta     need_lock
        lda     #1
        sta     dirty
        jsr     draw_next
        jsr     fits_here
        bcc     @ok
        lda     #1              ; no room: the game is over
        sta     dead
@ok:    rts

; carry clear if the piece fits at px, py, prot
fits_here:
        lda     px
        sta     tx
        lda     py
        sta     ty
        lda     prot
        sta     trot
; carry clear if piece ptype fits at tx, ty, trot
fits:   lda     ptype
        asl
        asl
        adc     trot            ; (carry clear: ptype < 64)
        asl
        asl
        sta     pidx            ; ptype * 16 + trot * 4
        tay
        ldx     #4
@sq:    lda     pc_x,y
        clc
        adc     tx
        cmp     #BW             ; off the side (or < 0: >= 128)
        bcs     @no
        sta     tmp
        lda     pc_y,y
        clc
        adc     ty
        cmp     #BH             ; below the floor
        bcs     @no
        stx     tmp2
        tax
        lda     rowoff,x
        clc
        adc     tmp
        tax
        lda     board,x
        bne     @no2
        ldx     tmp2
        iny
        dex
        bne     @sq
        clc
        rts
@no2:   ldx     tmp2
@no:    sec
        rts

; a move or turn worked: if the piece is on the ground, it gets a little
; more time before it locks (but not for ever)
moved:  lda     #1
        sta     dirty
        lda     lresets
        cmp     #LOCK_RESETS
        bcs     @r
        inc     lresets
        lda     #0
        sta     ltimer
@r:     rts

; move sideways by A (1 or -1)
move:   clc
        adc     px
        sta     tx
        lda     py
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcs     @r
        lda     tx
        sta     px
        lda     #SND_MOVE
        jsr     sfx_snd
        jmp     moved
@r:     rts

; turn by A (1 clockwise, 3 back); if it doesn't fit, try nudging it sideways
rotate: clc
        adc     prot
        and     #3
        sta     trot
        lda     py
        sta     ty
        ldx     #0
@k:     stx     kick
        lda     px
        clc
        adc     kicks,x
        sta     tx
        jsr     fits
        bcc     @ok
        ldx     kick
        inx
        cpx     #3              ; I pieces may go 2 squares
        bne     @k2
        lda     ptype
        bne     @r              ; (I is piece 0)
@k2:    cpx     #5
        bne     @k
@r:     rts
@ok:    lda     tx
        sta     px
        lda     trot
        sta     prot
        lda     #SND_ROTATE
        jsr     sfx_snd
        jmp     moved

; one row down (a soft drop): if it can't, it locks now
soft_drop:
        jsr     down1
        bcs     @lock
        lda     #1
        jsr     add_score
        lda     #0
        sta     gcount
        rts
@lock:  lda     #1
        sta     need_lock
        rts

; all the way down, and lock
hard_drop:
        lda     #0
        sta     tmp3
@l:     jsr     down1
        bcs     @done
        inc     tmp3
        bne     @l
@done:  lda     tmp3
        asl
        jsr     add_score
        lda     #SND_DROP
        jsr     sfx_snd
        lda     #1
        sta     need_lock
        rts

; move the piece down a row if it can (carry clear)
down1:  lda     px
        sta     tx
        lda     py
        clc
        adc     #1
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcs     @r
        inc     py
        lda     #1
        sta     dirty
        clc
@r:     rts

; the piece falls a row every so often; on the ground the lock timer runs
gravity:
        inc     gcount
        ldx     level
        cpx     #NSPEED
        bcc     @l
        ldx     #NSPEED-1
@l:     lda     gcount
        cmp     fall_ticks,x
        bcc     @ground
        lda     #0
        sta     gcount
        jsr     down1
        bcs     @ground
        lda     #0              ; a fresh row: a fresh lock timer
        sta     ltimer
        rts
@ground:lda     px              ; standing on something?
        sta     tx
        lda     py
        clc
        adc     #1
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcc     @air
        inc     ltimer
        lda     ltimer
        cmp     #LOCK_TICKS
        bcc     @r
        lda     #1
        sta     need_lock
@r:     rts
@air:   lda     #0
        sta     ltimer
        rts

; ---- locking, lines ------------------------------------------------------------------
lock_piece:
        lda     #SND_LOCK       ; (a hard drop's sound wins: it's louder)
        jsr     sfx_snd
        lda     #0
        sta     need_lock
        lda     px              ; write the piece into the board
        sta     tx
        lda     py
        sta     ty
        lda     prot
        sta     trot
        jsr     fits            ; (sets pidx)
        ldy     pidx
        ldx     #4
@sq:    stx     tmp2
        lda     pc_y,y
        clc
        adc     py
        tax
        lda     rowoff,x
        clc
        adc     pc_x,y
        adc     px
        tax
        lda     ptype
        clc
        adc     #1
        sta     board,x
        ldx     tmp2
        iny
        dex
        bne     @sq
        ; full rows?
        lda     #0
        sta     nfull
        ldx     #BH-1
@row:   stx     tmp
        lda     rowoff,x
        tay
        ldx     #BW
@c:     lda     board,y
        beq     @notfull
        iny
        dex
        bne     @c
        ldx     nfull
        lda     tmp
        sta     full,x
        inc     nfull
@notfull:
        ldx     tmp
        dex
        bpl     @row
        lda     nfull
        beq     @next
        jsr     clear_lines
@next:  jmp     spawn

; flash the full rows, remove them, score
clear_lines:
        lda     nfull           ; 4 lines: a bigger sound
        cmp     #4
        lda     #SND_LINE
        bcc     @s
        lda     #SND_LINES
@s:     jsr     sfx_snd
        jsr     compose_board   ; the board without a falling piece
        ldx     nfull           ; show the full rows as solid
@f:     dex
        bmi     @show
        lda     full,x
        sec
        sbc     #HIDDEN
        bcc     @f
        tay
        lda     rowoff,y
        tay
        lda     #BW
        sta     tmp
        lda     #G_FLASH
@fc:    sta     disp,y
        iny
        dec     tmp
        bne     @fc
        jmp     @f
@show:  jsr     present
        lda     #200
        jsr     delay_ms
        ; remove them: full[] is from the bottom up, so take the highest first
        ldx     nfull
@rm:    dex
        bmi     @scored
        stx     tmp3
        lda     full,x
        jsr     remove_row
        ldx     tmp3
        jmp     @rm
@scored:lda     nfull           ; points: 40, 100, 300, 1200 x (level + 1)
        asl
        asl                     ; *4 (3 bytes each, the first unused)
        sec
        sbc     #4
        tax
        lda     level
        sta     tmp3
@pts:   php
        sei
        sed
        clc
        lda     score
        adc     line_pts,x
        sta     score
        lda     score+1
        adc     line_pts+1,x
        sta     score+1
        lda     score+2
        adc     line_pts+2,x
        sta     score+2
        bcc     @nc
        lda     #$99            ; (999999 is the most)
        sta     score
        sta     score+1
        sta     score+2
@nc:    cld
        plp
        dec     tmp3
        bpl     @pts
        lda     nfull           ; lines, level
        sta     tmp3
@ln:    php
        sei
        sed
        clc
        lda     lines
        adc     #1
        sta     lines
        lda     lines+1
        adc     #0
        sta     lines+1
        cld
        plp
        dec     to_next
        bne     @nl
        lda     #10
        sta     to_next
        lda     level
        cmp     #99
        bcs     @nl
        inc     level
        lda     #SND_LEVEL
        jsr     sfx_snd
@nl:    dec     tmp3
        bne     @ln
        jmp     show_stats

; remove board row A: everything above it moves down one
remove_row:
        tax
        lda     rowoff,x
        clc
        adc     #BW-1
        tax                     ; last square of the row
@m:     cpx     #BW
        bcc     @top
        lda     board-BW,x
        sta     board,x
        dex
        bne     @m              ; (X >= BW here, so never 0)
@top:   lda     #0              ; a new empty row at the top
@t:     sta     board,x
        dex
        bpl     @t
        rts

; add A (0..99, binary) to the score
add_score:
        tax
        beq     @r
@l:     php
        sei
        sed
        clc
        lda     score
        adc     #1
        sta     score
        lda     score+1
        adc     #0
        sta     score+1
        lda     score+2
        adc     #0
        sta     score+2
        cld
        plp
        dex
        bne     @l
        lda     #1
        sta     score_dirty
@r:     rts

; ---- drawing the board ---------------------------------------------------------
; disp = the visible board
compose_board:
        ldx     #VIS-1
@c:     lda     board + HIDDEN * BW,x
        sta     disp,x
        dex
        cpx     #$FF
        bne     @c
        rts

; disp = the board + the ghost + the falling piece
compose:
        jsr     compose_board
        lda     px              ; the ghost: as far down as it goes
        sta     tx
        lda     py
        sta     gy
@g:     inc     gy
        lda     gy
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcc     @g
        dec     gy
        lda     gy
        ldx     #G_GHOST
        jsr     put_piece
        lda     ptype
        clc
        adc     #1
        tax
        lda     py
        ; fall through
; put glyph X at the squares of the piece (at px, row A, prot) in disp
put_piece:
        sta     tmp
        stx     tmp3
        lda     ptype
        asl
        asl
        clc
        adc     prot
        asl
        asl
        tay
        ldx     #4
@sq:    stx     tmp2
        lda     pc_y,y
        clc
        adc     tmp
        sec
        sbc     #HIDDEN
        bcc     @n              ; in the hidden rows
        tax
        lda     rowoff,x
        clc
        adc     pc_x,y
        adc     px
        tax
        lda     tmp3
        sta     disp,x
@n:     ldx     tmp2
        iny
        dex
        bne     @sq
        rts

; send the squares that differ from what the terminal shows.  A run of the
; same square is sent once with the repeat count (18 n, then 0B tile).
present:
        lda     score_dirty
        beq     @p
        lda     #0
        sta     score_dirty
        jsr     show_score
@p:     lda     attr            ; block graphics (keep a repeat count it has)
        cmp     #$FF            ; (unknown)
        beq     @gm
        tax
        bmi     @g
@gm:    jsr     gfx_mode
@g:     ldx     #0              ; square index
        lda     #0
        sta     prow
@row:   lda     #0
        sta     pcol
@sq:    lda     disp,x
        cmp     shown,x
        bne     @diff
@same:  inx
        inc     pcol
        lda     pcol
        cmp     #BW
        bne     @sq
        inc     prow
        lda     prow
        cmp     #20
        bne     @row
        rts
@diff:  sta     val
        stx     tmp2            ; the run of this square to the end of the row,
        lda     #1              ; and how far into it the last change is
        sta     need
        ldy     pcol
        iny
@rl:    cpy     #BW
        bcs     @rend
        inx
        lda     disp,x
        cmp     val
        bne     @rend
        cmp     shown,x
        beq     @rs1
        tya
        sec
        sbc     pcol
        clc
        adc     #1
        sta     need
@rs1:   iny
        bne     @rl
@rend:  tya
        sec
        sbc     pcol
        sta     runl
        lda     cur_rep         ; draw how many: the repeat count already set
        cmp     need            ; if it fits, one square for a single change,
        bcc     @nofit          ; else the whole run
        cmp     runl
        beq     @setk
        bcc     @setk
@nofit: lda     need
        cmp     #1
        beq     @setk
        lda     runl
@setk:  sta     kcnt
        lda     pcol            ; the cursor: text column BX + 2 * pcol
        asl
        clc
        adc     #BX
        tax
        lda     prow
        clc
        adc     #BY
        tay
        cpy     cur_y
        bne     @go
        cpx     cur_x
        beq     @put
        jsr     setcol
        jmp     @put
@go:    jsr     gotoxy
        sty     cur_y
@put:   lda     kcnt            ; where the cursor will be
        asl
        sta     tmp
        txa
        clc
        adc     tmp
        sta     cur_x
        lda     kcnt
        jsr     set_rep
        lda     val
        jsr     put_glyph
        ldx     tmp2            ; the terminal shows them now
        ldy     kcnt
        lda     val
@sw:    sta     shown,x
        inx
        dey
        bne     @sw
        dex                     ; (the loop steps on to the next)
        lda     pcol
        clc
        adc     kcnt
        sec
        sbc     #1
        sta     pcol
        jmp     @same

show_score:
        jsr     txt_mode
        ldx     #SX
        ldy     #11
        jsr     gotoxy
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jmp     prbcd

; ============================================================================
; input
; ============================================================================
input:  lda     ctrl
        beq     @keys
        jsr     read_pad
        lda     padnew          ; left / right: move now, repeat when held
        and     #PAD_LEFT | PAD_RIGHT
        beq     @held
        lda     #0
        sta     das
        jsr     pad_move
        jmp     @rot
@held:  lda     pad
        and     #PAD_LEFT | PAD_RIGHT
        beq     @rot
        inc     das
        lda     das
        cmp     #DAS_DELAY
        bcc     @rot
        lda     #DAS_DELAY - DAS_RATE
        sta     das
        jsr     pad_move
@rot:   lda     padnew
        and     #PAD_A
        beq     @b
        lda     #1
        jsr     rotate
@b:     lda     padnew
        and     #PAD_B
        beq     @up
        lda     #3
        jsr     rotate
@up:    lda     padnew
        and     #PAD_UP
        beq     @dn
        jsr     hard_drop
        jmp     @st
@dn:    lda     pad
        and     #PAD_DOWN
        beq     @st
        inc     sdcount
        lda     sdcount
        and     #1
        beq     @st
        jsr     soft_drop
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  lda     need_lock       ; (stop once the piece is down)
        bne     @done
        jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @keys
@done:  rts

pad_move:
        lda     pad
        and     #PAD_LEFT
        beq     @r
        lda     #$FF
        jmp     move
@r:     lda     #1
        jmp     move

handle_key:
        ldx     esc_st          ; arrow keys: ESC [ A..D
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
        cmp     #'A'
        beq     @rot
        cmp     #'B'
        beq     @down
        cmp     #'C'
        beq     @right
        cmp     #'D'
        beq     @left
        rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    ldx     ctrl            ; gamepad mode: ignore what the pad types
        beq     @kb
        jsr     pad_typed
        bcc     @kb
        rts
@kb:    cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #'W'
        beq     @rot
        cmp     #'X'
        beq     @rot
        cmp     #'Z'
        beq     @back
        cmp     #'S'
        beq     @down
        cmp     #' '
        beq     @drop
        cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@left:  lda     #$FF
        jmp     move
@right: lda     #1
        jmp     move
@rot:   lda     #1
        jmp     rotate
@back:  lda     #3
        jmp     rotate
@down:  jmp     soft_drop
@drop:  jmp     hard_drop
@pause: jmp     pause
@quit:  lda     #1
        sta     quit
        rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        jsr     txt_mode
        ldx     #SX
        ldy     #8
        jsr     gotoxy
        lda     #<paused_txt
        ldy     #>paused_txt
        jsr     print
        jsr     flush_in
@w:     jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @go
        jsr     getc
        bcc     @w
@go:    jsr     flush_in
        ldx     #SX
        ldy     #8
        jsr     gotoxy
        lda     #<unpaused_txt
        ldy     #>unpaused_txt
        jmp     print

; ============================================================================
; game over
; ============================================================================
game_over:
        jsr     sfx_off         ; the music stops
        lda     #SND_OVERA
        jsr     sfx_snd
        lda     #SND_OVERB
        jsr     sfx_snd
        jsr     compose         ; show where it ended
        jsr     present
        lda     #VIS - BW       ; fill the well from the bottom up
        sta     tmp3
@fill:  ldx     tmp3
        ldy     #BW
        lda     #G_FLASH
@f:     sta     disp,x
        inx
        dey
        bne     @f
        jsr     present
        lda     #30
        jsr     delay_ms
        lda     tmp3
        sec
        sbc     #BW
        sta     tmp3
        bcs     @fill
        ldx     #2              ; new high score?
@hc:    lda     score,x
        cmp     hiscore,x
        bcc     @nohi
        bne     @hi
        dex
        bpl     @hc
        bmi     @nohi           ; equal
@hi:    ldx     #2
@hs:    lda     score,x
        sta     hiscore,x
        dex
        bpl     @hs
        jsr     show_stats
@nohi:  lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        lda     #10
        jsr     delay_long      ; ignore keys for half a second
        jsr     flush_in
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @nq
        jmp     title
@nq:    cmp     #'M'
        bne     @nm
        jsr     sfx_toggle
        jmp     @wait
@nm:    cmp     #' '
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
        .include "stacker_data.inc"
        .include "stacker_sound.inc"    ; the music and effects (game_sounds.py)

rowoff:
.repeat BH, R
        .byte   R * BW
.endrepeat
kicks:  .byte   0, $FF, 1, $FE, 2       ; sideways nudges when turning
; ticks per row by level (a tick is about 17 ms)
fall_ticks:
        .byte   48, 43, 38, 33, 28, 23, 18, 13, 8, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2
NSPEED = * - fall_ticks
line_pts:       ; BCD, 4 bytes each (1 to 4 lines)
        .byte   $40, $00, $00, 0
        .byte   $00, $01, $00, 0
        .byte   $00, $03, $00, 0
        .byte   $00, $12, $00, 0

cls_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, 0, TERM
title_txt:
        .byte   TC_ROW, 9, TC_COL, 20, "A FALLING BLOCKS GAME FOR THE 6502 SBC"
        .byte   TC_ROW, 11, TC_COL, 12, "KEYS: A/D MOVE   W ROTATE   Z ROTATE BACK   S DOWN   SPACE DROP"
        .byte   TC_ROW, 12, TC_COL, 12, "PAD:  LEFT/RIGHT MOVE   A/B ROTATE   DOWN DOWN   UP DROP"
        .byte   TC_ROW, 13, TC_COL, 12, "P OR START PAUSES, M SOUND, Q QUITS"
        .byte   TC_ROW, 15, TC_COL, 26, "STARTING LEVEL (0-9):"
        .byte   TC_ROW, 23, TC_COL, 21, "SPACE OR START: PLAY      Q: QUIT", TERM
hi_txt: .byte   "HIGH SCORE ", TERM
game_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, 0
        .byte   TC_ROW, 0, TC_COL, 36, "STACKER"
        .byte   TC_ROW, NY, TC_COL, NX, "NEXT"
        .byte   TC_ROW, 10, TC_COL, SX, "SCORE"
        .byte   TC_ROW, 13, TC_COL, SX, "LINES"
        .byte   TC_ROW, 16, TC_COL, SX, "LEVEL"
        .byte   TC_ROW, 19, TC_COL, SX, "HIGH", TERM
help_kb_txt:
        .byte   TC_ROW, 4, TC_COL, 3, "A D    MOVE"
        .byte   TC_ROW, 5, TC_COL, 3, "W X    ROTATE"
        .byte   TC_ROW, 6, TC_COL, 3, "Z      ROTATE BACK"
        .byte   TC_ROW, 7, TC_COL, 3, "S      DOWN"
        .byte   TC_ROW, 8, TC_COL, 3, "SPACE  DROP"
        .byte   TC_ROW, 10, TC_COL, 3, "ARROWS WORK TOO"
        .byte   TC_ROW, 12, TC_COL, 3, "P      PAUSE"
        .byte   TC_ROW, 13, TC_COL, 3, "Q      QUIT"
        .byte   TC_ROW, 14, TC_COL, 3, "M      SOUND", TERM
help_pad_txt:
        .byte   TC_ROW, 4, TC_COL, 3, "LEFT RIGHT  MOVE"
        .byte   TC_ROW, 5, TC_COL, 3, "A           ROTATE"
        .byte   TC_ROW, 6, TC_COL, 3, "B           ROTATE BACK"
        .byte   TC_ROW, 7, TC_COL, 3, "DOWN        DOWN"
        .byte   TC_ROW, 8, TC_COL, 3, "UP          DROP"
        .byte   TC_ROW, 12, TC_COL, 3, "START       PAUSE"
        .byte   TC_ROW, 13, TC_COL, 3, "Q (KEY)     QUIT"
        .byte   TC_ROW, 14, TC_COL, 3, "M (KEY)     SOUND", TERM
paused_txt:
        .byte   RV_ON, " PAUSED ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM
unpaused_txt:
        .byte   "        ", TERM
over_txt:
        .byte   RV_ON
        .byte   TC_ROW, 9, TC_COL, BX, "                    "
        .byte   TC_ROW, 10, TC_COL, BX, "     GAME  OVER     "
        .byte   TC_ROW, 11, TC_COL, BX, "                    "
        .byte   TC_ROW, 12, TC_COL, BX, "  SPACE / A: AGAIN  "
        .byte   TC_ROW, 13, TC_COL, BX, "  Q: TITLE          "
        .byte   TC_ROW, 14, TC_COL, BX, "                    "
        .byte   RV_OFF, TC_ATTR, ATTR_TEXT, TERM
bye_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, '_', TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM

; ============================================================================
; variables (not in the file; cleared at start)
; ============================================================================
        .segment "BSS"
bss_start:
ctrl:       .res 1              ; 0 keyboard, 1 gamepad
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
attr:       .res 1              ; the terminal's attribute ($FF = unknown)
cur_x:      .res 1              ; where the cursor is (cur_y $FF = unknown)
cur_y:      .res 1
esc_st:     .res 1
quit:       .res 1
ticks:      .res 1              ; counts game ticks
npieces:    .res 1              ; counts pieces
dead:       .res 1
start_level:.res 1
level:      .res 1
to_next:    .res 1              ; lines to the next level
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
lines:      .res 2              ; BCD
score_dirty:.res 1
ptype:      .res 1              ; the falling piece: 0..6
px:         .res 1              ; its box's square (may be < 0)
py:         .res 1              ; its box's row (0 = the top hidden row)
prot:       .res 1
next:       .res 1
tx:         .res 1              ; a place to test
ty:         .res 1
trot:       .res 1
pidx:       .res 1
gy:         .res 1              ; the ghost's row
kick:       .res 1
gcount:     .res 1              ; ticks since the last fall
ltimer:     .res 1              ; ticks on the ground
lresets:    .res 1
need_lock:  .res 1
dirty:      .res 1              ; the board picture changed
das:        .res 1
sdcount:    .res 1
bag:        .res 7
bag_n:      .res 1
nfull:      .res 1
full:       .res 4              ; full rows, bottom first
nbuf:       .res 8
prow:       .res 1
cur_rep:    .res 1              ; the terminal's repeat count now
val:        .res 1
need:       .res 1
runl:       .res 1
kcnt:       .res 1
pcol:       .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
board:      .res BW * BH
disp:       .res VIS
shown:      .res VIS
bss_end:
