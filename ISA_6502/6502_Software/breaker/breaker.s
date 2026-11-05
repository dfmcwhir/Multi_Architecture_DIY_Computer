; ============================================================================
; breaker.s - BYTE BREAKER, a brick breaking game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal in its
; control code mode (setup item J), with the terminal's sprite layer
; (control code 1C: the firmware with the sprite layer, VGA).
;
;   build:  make.bat  (or make)     needs ../sbc_api.inc (CLOCK_MHZ)
;   run:    L BREAKER 0500   then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  frame time in ms (default 30; real ms at any clock)
;   $0504  controls at start: 0 keyboard, 1 gamepad
;   $0505  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2), the sounds in breaker_sound.inc (made by
; ../ay/tools/game_sounds.py).  Without the card the game is just silent.
;
; Keys:    A / D or Left / Right  move      Space  launch / fire
;          P pause   M sound on / off   Q quit
; Gamepad: left / right move, A or B launch / fire, Start pause
;
; The screen: the status line on row 0, the walls round text rows 1-23, the
; bricks (19 across, up to 10 rows, each 4 block graphics characters: 8 x 4
; pixels) in rows 4-13.  Bricks are characters, drawn only when they
; change.  The paddle, the balls (up to 3), the falling capsules and the
; laser shots are the terminal's sprites: each frame only what changed is
; sent, between HOLD and SHOW, then IDENTIFY, whose answer the next frame
; waits for.  Coordinates are the sprite layer's pixels (160 x 96, 3 x 3
; screen pixels each); positions and speeds are 8.8 fixed point.  No zero
; page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 30            ; ms per frame

; ---- terminal --------------------------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
TC_SPR          = $1C
ATTR_TEXT       = $00
ATTR_GFX        = $80
TERM            = $FF
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
SPR_PLACE       = 2
SPR_MOVE        = 3
SPR_PIC         = 4
SPR_HIDE        = 6

; ---- the playing field (sprite pixels) ---------------------------------------------
X_MIN           = 2             ; inside the walls: x 2 .. 157
X_MAX           = 158
Y_MIN           = 8             ; below the top wall (text row 1)
BRICK_X         = 4             ; the bricks' top left
BRICK_Y         = 16            ;   (text row 4, column 2)
PAD_Y           = 87            ; the paddle's top row (3 rows)
BALL_TOP        = PAD_Y - 2     ; a ball on the paddle
PAD_NORMAL      = 16            ; widths
PAD_WIDE        = 24
PAD_STEP        = 3             ; pixels a frame
CAP_Y_STEP      = $C0           ; capsules fall 0.75 pixels a frame
SHOT_STEP       = 3
SERVE_FRAMES    = 100           ; a ball on the paddle goes by itself after this
SPEEDUP_HITS    = 12            ; bricks hit between speed-ups
DULL_MAX        = 6             ; paddle bounces without a brick before the angle changes

NBALL           = 3
NCAP            = 2
NSHOT           = 4
SL_PAD          = 15            ; sprite slots (higher on top)
SL_BALL         = 12            ; 12-14
SL_CAP          = 10            ; 10-11
SL_SHOT         = 6             ; 6-9
NSLOT           = 16

PW_NONE         = 0             ; paddle powers
PW_WIDE         = 1
PW_LASER        = 2
PW_CATCH        = 3

; ============================================================================
        .segment "RODATA"
        .include "breaker_data.inc"
        .include "breaker_sound.inc"    ; the sounds (game_sounds.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound on the AY-3-8910 card

; ----------------------------------------------------------------------------
; I/O helpers
; ----------------------------------------------------------------------------
; carry set = key in A.  After IDENTIFY (1C 0C) the terminal answers S P 1:
; those are taken as its answer (rp_got), not as keys, until the 1 comes or
; the next IDENTIFY.  (Keys come in lower case; any one of the three will do.)
getc:   jsr     SBC_CHRIN
        bcc     @r
        pha
        lda     rp_on
        beq     @key
        pla
        cmp     #'S'
        beq     @rep
        cmp     #'P'
        beq     @rep
        cmp     #'1'
        bne     @k2
        lda     #0
        sta     rp_on
@rep:   lda     #1
        sta     rp_got
        jmp     getc
@k2:    sec
        rts
@key:   pla
        sec
@r:     rts

; send A (counts the bytes, for the frame timing).  Preserves A, X, Y.
putc:   inc     nbytes
        bne     @p
        inc     nbytes+1
@p:     jsr     sfx_poll        ; (the sound goes on while drawing)
        jmp     SBC_CHROUT

; cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
        lda     #TC_COL
        jsr     putc
        txa
        jmp     putc

txt_mode:
        lda     #ATTR_TEXT
        beq     setattr
gfx_mode:
        lda     #ATTR_GFX
setattr:cmp     attr
        beq     @r
        sta     attr
        pha
        lda     #TC_ATTR
        jsr     putc
        pla
        jmp     putc
@r:     rts

; a block graphics character (00-1F and 7F need the 1A prefix)
putblk: cmp     #$20
        bcc     @lit
        cmp     #$7F
        bne     @out
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@out:   jmp     putc

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
@done:  lda     #$FF            ; (strings may change the attribute)
        sta     attr
        rts

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

; print A (0-99) as two decimal digits
prdec2: ldx     #'0'
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
@o:     jsr     sfx_poll        ; (and while waiting)
        ldy     #DELAY_N
@i:
.repeat CLOCK_MHZ - 1
        nop
        nop
.endrepeat
        dey
        bne     @i
        dex
        bne     @o
@done:  rts

; wait about A x 50 ms, dropping keys pressed meanwhile
delay_long:
        sta     tmp
@l:     lda     #50
        jsr     delay_ms
        jsr     flush_in
        dec     tmp
        bne     @l
        rts

.macro MENU_IDLE
        jsr     rand            ; (waiting stirs the random numbers)
        jsr     sfx_poll
.endmacro
CTRL_COL        = 19
CTRL_ROW        = 21

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
        jsr     spr_setup       ; the terminal's sprites (or back to the menu)

title:  jsr     sfx_off
        lda     #0
        sta     rp_on
        jsr     new_screen
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     txt_mode        ; the high score
        ldx     #34
        ldy     #19
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jsr     prbcd
        ldx     #NCAPTYPE-1     ; the capsules beside their words
@cp:    stx     hs_i
        txa
        clc
        adc     #PIC_CAP
        sta     des_n
        lda     title_cx,x
        sta     des_x
        lda     title_cy,x
        sta     des_y
        lda     #TC_SPR
        jsr     putc
        lda     #SPR_PLACE
        jsr     putc
        lda     hs_i
        jsr     putc
        lda     des_n
        jsr     putc
        lda     des_x
        jsr     putc
        lda     des_y
        jsr     putc
        lda     #0
        jsr     putc
        ldx     hs_i
        dex
        bpl     @cp
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
@notm:  cmp     #'G'
        bne     @notg
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@notg:  cmp     #PAD_GO
        bne     @notp
        lda     #1
        sta     ctrl
        jmp     new_game
@notp:  cmp     #' '
        bne     @wait
        jmp     new_game

exit_game:
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
        jmp     SBC_MENU

; clear the screen (which hides the sprites) and forget what it showed
new_screen:
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        ldx     #NSLOT-1
        lda     #0
@f:     sta     sl_on,x
        sta     des_on,x
        dex
        bpl     @f
        lda     #1              ; (nothing to wait for)
        sta     rp_got
        rts

; ============================================================================
; the terminal's sprite layer: IDENTIFY, then the pictures; without it, a
; word and back to the boot menu
; ============================================================================
spr_setup:
        jsr     flush_in
        lda     #<ident_txt
        ldy     #>ident_txt
        jsr     print
        lda     #200            ; up to 200 ms
        sta     rp_t
@w:     jsr     SBC_CHRIN
        bcs     @c
@w1:    lda     #1
        jsr     delay_ms
        dec     rp_t
        bne     @w
        lda     #<nospr_txt     ; no answer
        ldy     #>nospr_txt
        jsr     print
        jsr     menu_key
        jmp     SBC_MENU
@c:     cmp     #'S'
        beq     @yes
        cmp     #'P'
        beq     @yes
        cmp     #'1'
        bne     @w1
@yes:   lda     #20             ; (the rest of the answer)
        jsr     delay_ms
        jsr     flush_in
        ldx     #0
@d:     lda     spr_defs,x
        jsr     SBC_CHROUT
        inx
        cpx     #SPR_DEFS
        bne     @d
        rts

; ---- pacing: IDENTIFY after each frame; the next waits for the answer ----
ASK_MS          = 60
ask_send:
        lda     #1
        sta     rp_on
        lda     #0
        sta     rp_got
        lda     #<ident_txt
        ldy     #>ident_txt
        jmp     print

ask_wait:
        lda     rp_got
        bne     @r
        lda     #ASK_MS
        sta     rp_t
@l:     jsr     getc
        bcc     @none
        jsr     handle_key      ; (a key meanwhile)
        jmp     @chk
@none:  lda     #1
        jsr     delay_ms
        dec     rp_t
        beq     @r
@chk:   lda     rp_got
        beq     @l
@r:     rts

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     level
        sta     quit
        lda     #3
        sta     lives
next_level:
        inc     level
        jsr     new_screen
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        jsr     draw_walls
        lda     #<clip_txt      ; sprites only inside the walls' rows
        ldy     #>clip_txt
        jsr     print
        ldx     level           ; the level's bricks (they go round after
        dex                     ; the last one, a little faster)
@m:     cpx     #NLEVEL
        bcc     @m1
        txa
        sbc     #NLEVEL
        tax
        jmp     @m
@m1:    lda     lv_lo,x
        sta     @rd+1
        lda     lv_hi,x
        sta     @rd+2
        lda     #0
        sta     bricks_left
        ldx     #NBRICK-1
@rd:    lda     $FFFF,x
        sta     map,x
        beq     @cn
        cmp     #3
        beq     @cn
        inc     bricks_left
@cn:    dex
        cpx     #$FF
        bne     @rd
        jsr     draw_bricks
        lda     level           ; the speed to start with: faster each
        sec                     ; time round the levels
        sbc     #1
        lsr
        lsr
        lsr
        cmp     #4
        bcc     @s
        lda     #4
@s:     sta     base_spd
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        jsr     serve
        lda     #1
        sta     msg_on
        lda     #SND_START
        jsr     sfx_snd
        lda     #<ready_txt     ; "LEVEL nn"
        ldy     #>ready_txt
        jsr     print
        lda     level
        jsr     prdec2
        jmp     game_loop

; a new ball on the paddle (a new level, or after one is lost)
serve:  ldx     #NBALL-1
        lda     #0
@b:     sta     b_on,x
        dex
        bpl     @b
        ldx     #NCAP-1
@c:     sta     c_on,x
        dex
        bpl     @c
        ldx     #NSHOT-1
@s:     sta     s_on,x
        dex
        bpl     @s
        sta     pw
        sta     hits
        lda     #PAD_NORMAL
        sta     pad_w
        lda     #80 - PAD_NORMAL / 2
        sta     pad_x
        lda     base_spd
        sta     spd
        ldx     #0
        lda     #1
        sta     b_on
        lda     #PAD_NORMAL / 2 - 1
        sta     b_off
        jsr     stick_ball
        lda     #SERVE_FRAMES
        sta     serve_t
        rts

; ball X on the paddle (b_off from its left end)
stick_ball:
        lda     #1
        sta     b_stuck,x
        lda     pad_x
        clc
        adc     b_off,x
        sta     b_xh,x
        lda     #BALL_TOP
        sta     b_yh,x
        lda     #0
        sta     b_xl,x
        sta     b_yl,x
        rts

; ---- the frame loop --------------------------------------------------------------
game_loop:
        jsr     sfx_poll
        lda     #0
        sta     nbytes
        sta     nbytes+1
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     ask_wait        ; the terminal has drawn the last frame
        lda     #<hold_txt
        ldy     #>hold_txt
        jsr     print
        jsr     move_paddle
        jsr     launch
        jsr     balls_update
        jsr     caps_update
        jsr     shots_update
        jsr     set_sprites
        jsr     spr_send
        lda     #<show_txt
        ldy     #>show_txt
        jsr     print
        jsr     ask_send
        jsr     hud_update
        jsr     pace
        inc     frame
        ldx     #NBALL-1        ; any ball left?
@b:     lda     b_on,x
        bne     @2
        dex
        bpl     @b
        jmp     life_lost
@2:     lda     bricks_left     ; the level cleared?
        bne     game_loop
        jmp     level_done

; wait out the rest of the frame: about (speed - what the frame took) ms:
; the bytes at 115200 baud (87 us each) and the 6502's work (about 4 ms at
; 1 MHz, measured in the emulator)
WORK_MS         = 4 / CLOCK_MHZ
pace:   lda     nbytes+1
        bne     @r
        lda     nbytes          ; bytes * 0.087 ~ bytes / 16 + bytes / 32
        lsr
        lsr
        lsr
        lsr
        sta     tmp
        lsr
        adc     tmp
        adc     #WORK_MS
        sta     tmp
        lda     speed
        sec
        sbc     tmp
        bcc     @r
        beq     @r
        jmp     delay_ms
@r:     rts

life_lost:
        lda     #SND_LOST
        jsr     sfx_snd
        lda     #<hideall_txt   ; (the sprites go)
        ldy     #>hideall_txt
        jsr     print
        ldx     #NSLOT-1
        lda     #0
@f:     sta     sl_on,x
        dex
        bpl     @f
        lda     #20
        jsr     delay_long
        dec     lives
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        lda     lives
        bne     @more
        jmp     game_over
@more:  jsr     serve
        jmp     game_loop

level_done:
        lda     #SND_CLEAR
        jsr     sfx_snd
        lda     #<hideall_txt
        ldy     #>hideall_txt
        jsr     print
        lda     #<clear_txt
        ldy     #>clear_txt
        jsr     print
        lda     #30
        jsr     delay_long
        jmp     next_level

game_over:
        ldx     #2              ; new high score?
@hc:    lda     score,x
        cmp     hiscore,x
        bcc     @nohi
        bne     @hi
        dex
        bpl     @hc
        bmi     @nohi
@hi:    ldx     #2
@hs:    lda     score,x
        sta     hiscore,x
        dex
        bpl     @hs
        lda     #1
        sta     hud_dirty
        jsr     hud_update
@nohi:  lda     #SND_OVER
        jsr     sfx_snd
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        lda     #20
        jsr     delay_long
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
; drawing the field
; ============================================================================
draw_walls:
        lda     #<nowrap_txt
        ldy     #>nowrap_txt
        jsr     print
        jsr     gfx_mode
        ldx     #0              ; the top: text row 1, all across
        ldy     #1
        jsr     gotoxy
        lda     #(15 << 3) | ATTR_GFX   ; (repeat 15)
        jsr     setattr
        ldx     #5
@t:     lda     #$FF
        jsr     putc
        dex
        bne     @t
        lda     #(5 << 3) | ATTR_GFX
        jsr     setattr
        lda     #$FF
        jsr     putc
        jsr     gfx_mode
        ldy     #2              ; the sides: columns 0 and 79, rows 2-23
@s:     ldx     #0
        jsr     gotoxy
        lda     #$FF
        jsr     putc
        ldx     #79
        jsr     gotoxy
        lda     #$FF
        jsr     putc
        iny
        cpy     #24
        bne     @s
        rts

draw_bricks:
        ldx     #0
@b:     stx     bidx
        lda     map,x
        beq     @n
        jsr     draw_brick
@n:     ldx     bidx
        inx
        cpx     #NBRICK
        bne     @b
        rts

; draw brick bidx as map says
draw_brick:
        ldx     bidx
        lda     b_row,x
        clc
        adc     #BRICK_Y / 4    ; its text row
        tay
        lda     b_col,x
        asl
        asl
        adc     #BRICK_X / 2    ; its column
        tax
        jsr     gfx_mode
        jsr     gotoxy
        ldx     bidx
        lda     map,x
        asl
        asl
        tax
        lda     #4
        sta     tmp
@c:     lda     brick_ch,x
        jsr     putblk
        inx
        dec     tmp
        bne     @c
        rts

hud_update:
        lda     hud_dirty
        bne     @go
        rts
@go:    lda     #0
        sta     hud_dirty
        jsr     txt_mode
        ldx     #6
        ldy     #0
        jsr     gotoxy
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        ldx     #25
        ldy     #0
        jsr     gotoxy
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jsr     prbcd
        ldx     #45
        ldy     #0
        jsr     gotoxy
        lda     lives
        ora     #'0'
        jsr     putc
        ldx     #59
        ldy     #0
        jsr     gotoxy
        lda     level
        jmp     prdec2

; add A (BCD tens, low) / Y (BCD, high) to the score.  Every 10000: a ball.
add_score:
        ldx     score+2
        stx     tmp
        php
        sei
        sed
        clc
        adc     score
        sta     score
        tya
        adc     score+1
        sta     score+1
        lda     score+2
        adc     #0
        sta     score+2
        cld
        plp
        lda     score+2         ; the 10000s changed: a ball
        cmp     tmp
        beq     @n
        jsr     extra_life
@n:     lda     #1
        sta     hud_dirty
        rts

extra_life:
        lda     #SND_LIFE
        jsr     sfx_snd
        lda     lives
        cmp     #9
        bcs     @n
        inc     lives
@n:     lda     #1
        sta     hud_dirty
        rts

; ============================================================================
; input
; ============================================================================
read_input:
        lda     #0
        sta     fire
        sta     mv
        lda     ctrl
        beq     @keys
        jsr     read_pad
        lda     pad
        and     #PAD_LEFT
        beq     @r
        lda     #<-PAD_STEP
        sta     mv
@r:     lda     pad
        and     #PAD_RIGHT
        beq     @a
        lda     #PAD_STEP
        sta     mv
@a:     lda     padnew
        and     #PAD_A | PAD_B
        beq     @st
        lda     #1
        sta     fire
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  jsr     getc
        bcc     @held
        jsr     handle_key
        jmp     @keys
@held:  lda     ctrl            ; keyboard: a key goes on for a few frames
        bne     @done           ; (key repeat is slower than the frames)
        lda     mv_hold
        beq     @done
        dec     mv_hold
        lda     mv_dir
        sta     mv
@done:  rts
HOLD_MOVE       = 3

handle_key:
        ldx     esc_st          ; arrow keys: ESC [ C / D
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
        cmp     #' '
        beq     @fire
        cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@left:  lda     #<-PAD_STEP
        bne     @mv
@right: lda     #PAD_STEP
@mv:    sta     mv_dir
        sta     mv
        lda     #HOLD_MOVE
        sta     mv_hold
        rts
@fire:  lda     #1
        sta     fire
        rts
@pause: jmp     pause
@quit:  lda     #1
        sta     quit
        rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        jsr     txt_mode
        ldx     #70
        ldy     #0
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
        jsr     txt_mode
        ldx     #70
        ldy     #0
        jsr     gotoxy
        lda     #<unpaused_txt
        ldy     #>unpaused_txt
        jmp     print

; ============================================================================
; the paddle
; ============================================================================
move_paddle:
        lda     mv
        beq     @r
        bmi     @left
        clc                     ; right, up to the wall
        adc     pad_x
        sta     pad_x
        lda     #X_MAX
        sec
        sbc     pad_w
        cmp     pad_x
        bcs     @st
        sta     pad_x
        jmp     @st
@left:  clc
        adc     pad_x
        bcc     @lw             ; (went below 0)
        cmp     #X_MIN
        bcs     @ok
@lw:    lda     #X_MIN
@ok:    sta     pad_x
@st:    ldx     #NBALL-1        ; balls on it go with it
@b:     lda     b_on,x
        beq     @n
        lda     b_stuck,x
        beq     @n
        lda     pad_x
        clc
        adc     b_off,x
        sta     b_xh,x
@n:     dex
        bpl     @b
@r:     rts

; fire: balls on the paddle go (also by themselves after a while); with the
; laser, two shots
launch: lda     serve_t
        beq     @f
        dec     serve_t
        bne     @f
        lda     #1              ; (time's up)
        sta     fire
@f:     lda     fire
        bne     @go
        rts
@go:    lda     #0
        sta     serve_t
        ldx     #NBALL-1
@b:     lda     b_on,x
        beq     @n
        lda     b_stuck,x
        beq     @n
        lda     #0
        sta     b_stuck,x
        lda     b_off,x         ; the angle from where it sits
        jsr     bounce_from
        lda     msg_on          ; ("LEVEL nn" off)
        beq     @n
        lda     #0
        sta     msg_on
        stx     tmp4
        lda     #<unready_txt
        ldy     #>unready_txt
        jsr     print
        ldx     tmp4
@n:     dex
        bpl     @b
        lda     pw              ; the laser
        cmp     #PW_LASER
        bne     @r
        lda     s_on            ; (one pair at a time on each side)
        ora     s_on+1
        beq     @p0
        lda     s_on+2
        ora     s_on+3
        bne     @r
        ldx     #2
        bne     @p
@p0:    ldx     #0
@p:     lda     #SND_LASER
        jsr     sfx_snd
        lda     #1
        sta     s_on,x
        sta     s_on+1,x
        lda     pad_x
        clc
        adc     #1
        sta     s_x,x
        adc     pad_w
        sec
        sbc     #3
        sta     s_x+1,x
        lda     #PAD_Y - 3
        sta     s_y,x
        sta     s_y+1,x
@r:     rts

; ball X leaves the paddle upwards, at an angle from A = where on the
; paddle (0 .. pad_w - 1 from its left end, its middle pixel): the left
; quarter steeply ... the left end flat to the left, the same to the right
bounce_from:
        pha
        lda     #SND_PADDLE
        jsr     sfx_snd
        pla
        ldy     pad_w           ; zone 0-7 = A * 8 / width
        cpy     #PAD_WIDE
        bne     @n
        ldy     #0              ; (wide: A / 3)
@d3:    cmp     #3
        bcc     @z
        sbc     #3
        iny
        bne     @d3
@z:     tya
        jmp     @zz
@n:     lsr                     ; (normal: A / 2)
@zz:    cmp     #8
        bcc     @ok
        lda     #7
@ok:    cmp     #4
        bcs     @rt
        sta     b_ang,x         ; 0-3: to the left, 0 flat .. 3 steep
        lda     #1
        sta     b_sx,x
        bne     @up
@rt:    eor     #7              ; 4-7: to the right, 7 flat .. 4 steep
        sta     b_ang,x
        lda     #0
        sta     b_sx,x
@up:    inc     dull            ; no brick hit for a while: another angle,
        lda     dull            ; so the ball can't go round the same way
        cmp     #DULL_MAX       ; for ever
        bcc     @up1
        lda     #0
        sta     dull
        jsr     rand
        and     #1
        sec
        adc     b_ang,x
        and     #3
        sta     b_ang,x
@up1:   lda     #1
        sta     b_sy,x
        lda     #BALL_TOP
        sta     b_yh,x
        lda     #0
        sta     b_yl,x
        ; fall through: its speed

; ball X's speed parts from spd and its angle
set_vel:
        lda     spd
        asl
        asl
        ora     b_ang,x
        tay
        lda     vx_lo,y
        sta     b_vxl,x
        lda     vx_hi,y
        sta     b_vxh,x
        lda     vy_lo,y
        sta     b_vyl,x
        lda     vy_hi,y
        sta     b_vyh,x
        rts

; every ball's speed again (after spd changed)
all_vel:
        ldx     #NBALL-1
@b:     lda     b_on,x
        beq     @n
        jsr     set_vel
@n:     dex
        bpl     @b
        rts

; ============================================================================
; the balls: each moves in 4 quarter steps, x then y, bouncing off the walls,
; the bricks (which they hit) and the paddle
; ============================================================================
balls_update:
        ldx     #NBALL-1
@b:     stx     bi
        lda     b_on,x
        beq     @n
        lda     b_stuck,x
        bne     @n
        jsr     ball_move
@n:     ldx     bi
        dex
        bpl     @b
        rts

ball_move:
        lda     b_vxh,x         ; a quarter of the speed
        sta     qxh
        lda     b_vxl,x
        lsr     qxh
        ror
        lsr     qxh
        ror
        sta     qxl
        lda     b_vyh,x
        sta     qyh
        lda     b_vyl,x
        lsr     qyh
        ror
        lsr     qyh
        ror
        sta     qyl
        lda     #4
        sta     qn
@step:  ldx     bi
        jsr     step_x
        ldx     bi
        jsr     step_y
        ldx     bi
        lda     b_on,x
        beq     @r
        dec     qn
        bne     @step
@r:     rts

; x: move, then the side walls or a brick in the way
step_x: jsr     add_x
        lda     b_xh,x
        cmp     #X_MIN
        bcs     @rw
        lda     #SND_WALL
        jsr     sfx_snd
        lda     #X_MIN          ; the left wall
        sta     b_xh,x
        lda     #0
        sta     b_xl,x
        sta     b_sx,x
        rts
@rw:    cmp     #X_MAX - 2 + 1
        bcc     @br
        lda     #SND_WALL
        jsr     sfx_snd
        lda     #X_MAX - 2      ; the right wall
        sta     b_xh,x
        lda     #0
        sta     b_xl,x
        lda     #1
        sta     b_sx,x
        rts
@br:    lda     b_xh,x          ; the leading edge
        ldy     b_sx,x
        bne     @l
        clc
        adc     #1
@l:     sta     tpx
        lda     b_yh,x
        sta     tpy
        jsr     brick_at
        bcs     @hit
        inc     tpy
        jsr     brick_at
        bcc     @r
@hit:   jsr     hit_brick
        ldx     bi
        jsr     sub_x           ; back, and the other way
        lda     b_sx,x
        eor     #1
        sta     b_sx,x
@r:     rts

; y: move, then the top wall, a brick, the paddle or the bottom
step_y: jsr     add_y
        lda     b_yh,x
        cmp     #Y_MIN
        bcs     @br
        lda     #SND_WALL
        jsr     sfx_snd
        lda     #Y_MIN          ; the top wall
        sta     b_yh,x
        lda     #0
        sta     b_yl,x
        sta     b_sy,x
        rts
@br:    cmp     #96             ; gone at the bottom
        bcc     @in
        lda     #0
        sta     b_on,x
        rts
@in:    ldy     b_sy,x          ; the leading edge
        bne     @u
        clc
        adc     #1
@u:     sta     tpy
        lda     b_xh,x
        sta     tpx
        jsr     brick_at
        bcs     @hit
        inc     tpx
        jsr     brick_at
        bcc     @pad
@hit:   jsr     hit_brick
        ldx     bi
        jsr     sub_y
        lda     b_sy,x
        eor     #1
        sta     b_sy,x
        rts
@pad:   lda     b_sy,x          ; going down onto the paddle's top?
        bne     @r
        lda     b_yh,x
        clc
        adc     #1
        cmp     #PAD_Y
        bcc     @r
        cmp     #PAD_Y + 2
        bcs     @r
        lda     b_xh,x          ; ball x + 1 >= pad_x and ball x < pad_x + w
        clc
        adc     #1
        cmp     pad_x
        bcc     @r
        lda     pad_x
        clc
        adc     pad_w
        cmp     b_xh,x
        bcc     @r
        beq     @r
        lda     b_xh,x          ; where on it
        sec
        sbc     pad_x
        bcs     @w
        lda     #0
@w:     sta     b_off,x
        jsr     bounce_from
        lda     pw              ; catch: it stays there
        cmp     #PW_CATCH
        bne     @r
        jsr     stick_ball
        lda     #SERVE_FRAMES
        sta     serve_t
        lda     #1              ; (no more steps)
        sta     qn
@r:     rts

add_x:  lda     b_sx,x
        bne     sub_x1
add_x1: lda     b_xl,x
        clc
        adc     qxl
        sta     b_xl,x
        lda     b_xh,x
        adc     qxh
        sta     b_xh,x
        rts
sub_x:  lda     b_sx,x
        bne     add_x1
sub_x1: lda     b_xl,x
        sec
        sbc     qxl
        sta     b_xl,x
        lda     b_xh,x
        sbc     qxh
        sta     b_xh,x
        rts
add_y:  lda     b_sy,x
        bne     sub_y1
add_y1: lda     b_yl,x
        clc
        adc     qyl
        sta     b_yl,x
        lda     b_yh,x
        adc     qyh
        sta     b_yh,x
        rts
sub_y:  lda     b_sy,x
        bne     add_y1
sub_y1: lda     b_yl,x
        sec
        sbc     qyl
        sta     b_yl,x
        lda     b_yh,x
        sbc     qyh
        sta     b_yh,x
        rts

; ---- the bricks ------------------------------------------------------------------
; carry set if pixel tpx, tpy is in a brick: bidx = which, A = its kind
brick_at:
        lda     tpy
        sec
        sbc     #BRICK_Y
        bcc     @no
        cmp     #BH * 4
        bcs     @no
        lsr
        lsr
        tay
        lda     tpx
        sec
        sbc     #BRICK_X
        bcc     @no
        cmp     #BW * 8
        bcs     @no
        lsr
        lsr
        lsr
        clc
        adc     row_off,y
        sta     bidx
        tay
        lda     map,y
        beq     @no
        sec
        rts
@no:    clc
        rts

; brick bidx is hit (A = its kind): steel stands, two hits becomes one, one
; hit goes (points by its row, maybe a capsule); every SPEEDUP_HITS the balls
; speed up
hit_brick:
        cmp     #3
        bne     @nst
        lda     #SND_CLANK      ; (it never breaks)
        jmp     sfx_snd
@nst:   ldx     #0
        stx     dull
        ldx     bidx
        cmp     #2
        bne     @one
        lda     #SND_CLANK
        jsr     sfx_snd
        lda     #1
        sta     map,x
        jsr     draw_brick
        lda     #$50            ; 50 points
        ldy     #$00
        jsr     add_score
        jmp     @sp
@one:   lda     b_row,x         ; higher for the top rows
        lsr
        clc
        adc     #SND_BRICK0
        jsr     sfx_snd
        lda     #0
        sta     map,x
        jsr     draw_brick
        dec     bricks_left
        ldx     bidx
        ldy     b_row,x
        lda     row_pts,y
        ldy     #0
        jsr     add_score
        jsr     maybe_capsule
@sp:    inc     hits
        lda     hits
        cmp     #SPEEDUP_HITS
        bcc     @r
        lda     #0
        sta     hits
        lda     spd
        cmp     #NSPEED-1
        bcs     @r
        inc     spd
        jsr     all_vel
@r:     rts

; ---- capsules ----------------------------------------------------------------------
; a broken brick (bidx) lets one fall, 1 time in 6, if there is room
maybe_capsule:
        jsr     rand
        cmp     #43             ; (43 / 256)
        bcs     @r
        ldx     #NCAP-1
@f:     lda     c_on,x
        beq     @new
        dex
        bpl     @f
@r:     rts
@new:   lda     #1
        sta     c_on,x
        jsr     rand            ; which: wide 5, multi 4, slow 4, laser 3,
        and     #$1F            ; catch 3, extra ball 1 (in 20)
        cmp     #20
        bcc     @k
        sbc     #12
@k:     tay
        lda     cap_kind,y
        sta     c_kind,x
        ldy     bidx
        lda     b_col,y
        asl
        asl
        asl
        adc     #BRICK_X
        sta     c_x,x
        lda     b_row,y
        asl
        asl
        adc     #BRICK_Y
        sta     c_yh,x
        lda     #0
        sta     c_yl,x
        rts

caps_update:
        ldx     #NCAP-1
@c:     lda     c_on,x
        beq     @n
        lda     c_yl,x          ; down
        clc
        adc     #CAP_Y_STEP
        sta     c_yl,x
        lda     c_yh,x
        adc     #0
        sta     c_yh,x
        cmp     #96
        bcc     @in
        lda     #0              ; missed
        sta     c_on,x
        beq     @n
@in:    clc                     ; caught: its bottom at the paddle's rows,
        adc     #5              ; and over it
        cmp     #PAD_Y + 1
        bcc     @n
        cmp     #PAD_Y + 5
        bcs     @n
        lda     c_x,x
        clc
        adc     #7
        cmp     pad_x
        bcc     @n
        beq     @n
        lda     pad_x
        clc
        adc     pad_w
        cmp     c_x,x
        bcc     @n
        beq     @n
        lda     #0
        sta     c_on,x
        stx     tmp4
        jsr     catch_cap
        ldx     tmp4
@n:     dex
        bpl     @c
        rts

; the capsule X was caught: 100 points and its power
catch_cap:
        lda     #SND_CAPSULE
        jsr     sfx_snd
        lda     c_kind,x
        pha
        lda     #$00            ; (100)
        ldy     #$01
        jsr     add_score
        pla
        beq     @wide
        cmp     #1
        beq     @multi
        cmp     #2
        beq     @slow
        cmp     #3
        beq     @laser
        cmp     #4
        beq     @catch
        jmp     extra_life
@wide:  lda     pw
        cmp     #PW_WIDE
        beq     @r
        lda     #PW_WIDE
        sta     pw
        lda     #PAD_WIDE       ; 4 more each side, inside the walls
        sta     pad_w
        lda     pad_x
        sec
        sbc     #4
        bcc     @w0
        cmp     #X_MIN
        bcs     @w1
@w0:    lda     #X_MIN
@w1:    cmp     #X_MAX - PAD_WIDE + 1
        bcc     @w2
        lda     #X_MAX - PAD_WIDE
@w2:    sta     pad_x
        jmp     unstick_far
@laser: lda     #PW_LASER
        bne     @narrow
@catch: lda     #PW_CATCH
@narrow:ldx     pw
        sta     pw
        cpx     #PW_WIDE        ; (from wide: back to the normal width)
        bne     @r
        lda     #PAD_NORMAL
        sta     pad_w
        lda     pad_x
        clc
        adc     #4
        sta     pad_x
        jmp     unstick_far
@slow:  lda     #0
        sta     spd
        sta     hits
        jmp     all_vel
@multi: jmp     multi_ball
@r:     rts

; balls on the paddle stay on it when its width changes
unstick_far:
        ldx     #NBALL-1
@b:     lda     b_on,x
        beq     @n
        lda     b_stuck,x
        beq     @n
        lda     pad_w
        lsr
        sta     b_off,x
        jsr     stick_ball
@n:     dex
        bpl     @b
        rts

; three balls: the free places get copies of a ball in play, at other angles
multi_ball:
        ldx     #NBALL-1        ; one to copy (one in the air if there is)
@f:     lda     b_on,x
        beq     @fn
        stx     tmp3
        lda     b_stuck,x
        beq     @got
@fn:    dex
        bpl     @f
        ldx     tmp3
@got:   stx     tmp3
        ldy     #NBALL-1
@c:     lda     b_on,y
        bne     @cn
        lda     #1
        sta     b_on,y
        lda     #0
        sta     b_stuck,y
        ldx     tmp3
        lda     b_xh,x
        sta     b_xh,y
        lda     b_xl,x
        sta     b_xl,y
        lda     b_yh,x
        sta     b_yh,y
        lda     b_yl,x
        sta     b_yl,y
        lda     #1              ; going up, one each way, at angles 1 and 2
        sta     b_sy,y
        tya
        and     #1
        sta     b_sx,y
        tya
        and     #1
        clc
        adc     #1
        sta     b_ang,y
        sty     tmp2
        ldx     tmp2
        jsr     set_vel
        ldy     tmp2
@cn:    dey
        bpl     @c
        rts

; ---- laser shots -------------------------------------------------------------------
shots_update:
        ldx     #NSHOT-1
@s:     stx     si
        lda     s_on,x
        beq     @n
        lda     #SHOT_STEP
        sta     qn
@st:    ldx     si
        dec     s_y,x
        lda     s_y,x
        cmp     #Y_MIN
        bcc     @off
        sta     tpy
        lda     s_x,x
        sta     tpx
        jsr     brick_at
        bcc     @nx
        jsr     hit_brick
        ldx     si
@off:   lda     #0
        sta     s_on,x
        beq     @n
@nx:    dec     qn
        bne     @st
@n:     ldx     si
        dex
        bpl     @s
        rts

; ============================================================================
; the sprites: where each slot should be (des_*), and what changed is sent
; ============================================================================
set_sprites:
        ldx     #NSLOT-1
        lda     #0
@c:     sta     des_on,x
        dex
        bpl     @c
        lda     #1              ; the paddle
        sta     des_on+SL_PAD
        ldx     pw
        lda     pad_pic,x
        sta     des_n+SL_PAD
        lda     pad_x
        clc
        adc     #32
        sta     des_x+SL_PAD
        lda     #PAD_Y + 32
        sta     des_y+SL_PAD
        ldx     #NBALL-1        ; the balls
@b:     lda     b_on,x
        beq     @bn
        lda     #1
        sta     des_on+SL_BALL,x
        lda     #PIC_BALL
        sta     des_n+SL_BALL,x
        lda     b_xh,x
        clc
        adc     #32
        sta     des_x+SL_BALL,x
        lda     b_yh,x
        clc
        adc     #32
        sta     des_y+SL_BALL,x
@bn:    dex
        bpl     @b
        ldx     #NCAP-1         ; the capsules
@k:     lda     c_on,x
        beq     @kn
        lda     #1
        sta     des_on+SL_CAP,x
        lda     c_kind,x
        clc
        adc     #PIC_CAP
        sta     des_n+SL_CAP,x
        lda     c_x,x
        clc
        adc     #32
        sta     des_x+SL_CAP,x
        lda     c_yh,x
        clc
        adc     #32
        sta     des_y+SL_CAP,x
@kn:    dex
        bpl     @k
        ldx     #NSHOT-1        ; the shots
@s:     lda     s_on,x
        beq     @sn
        lda     #1
        sta     des_on+SL_SHOT,x
        lda     #PIC_SHOT
        sta     des_n+SL_SHOT,x
        lda     s_x,x
        clc
        adc     #32
        sta     des_x+SL_SHOT,x
        lda     s_y,x
        clc
        adc     #32
        sta     des_y+SL_SHOT,x
@sn:    dex
        bpl     @s
        rts

; send what changed in the slots (des_* against sl_*, what the terminal shows)
spr_send:
        ldx     #NSLOT-1
@l:     stx     hs_i
        lda     des_on,x
        beq     @off
        lda     sl_on,x
        beq     @place
        lda     des_n,x
        cmp     sl_n,x
        beq     @samen
        lda     #SPR_PIC
        jsr     spr_cmd
        lda     des_n,x
        jsr     putc
@samen: lda     des_x,x
        cmp     sl_x,x
        bne     @move
        lda     des_y,x
        cmp     sl_y,x
        beq     @keep
@move:  lda     #SPR_MOVE
        jsr     spr_cmd
        lda     des_x,x
        jsr     putc
        lda     des_y,x
        jsr     putc
        jmp     @keep
@place: lda     #SPR_PLACE
        jsr     spr_cmd
        lda     des_n,x
        jsr     putc
        lda     des_x,x
        jsr     putc
        lda     des_y,x
        jsr     putc
        lda     #0
        jsr     putc
@keep:  lda     #1
        sta     sl_on,x
        lda     des_n,x
        sta     sl_n,x
        lda     des_x,x
        sta     sl_x,x
        lda     des_y,x
        sta     sl_y,x
        jmp     @n
@off:   lda     sl_on,x
        beq     @n
        lda     #0
        sta     sl_on,x
        lda     #SPR_HIDE
        jsr     spr_cmd
@n:     ldx     hs_i
        dex
        bmi     *+5
        jmp     @l
        rts

; send 1C, command A, slot hs_i.  X = hs_i after.
spr_cmd:pha
        lda     #TC_SPR
        jsr     putc
        pla
        jsr     putc
        lda     hs_i
        jsr     putc
        ldx     hs_i
        rts

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
row_off:
        .repeat BH, K
        .byte   K * BW
        .endrepeat
b_row:                          ; each brick's row and column
        .repeat NBRICK, K
        .byte   K / BW
        .endrepeat
b_col:
        .repeat NBRICK, K
        .byte   K .mod BW
        .endrepeat
row_pts:.byte   $70, $70, $60, $50, $40, $30, $20, $20, $10, $10  ; BCD: 70 .. 10 points
cap_kind:.byte  0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 4, 4, 4, 5
pad_pic:.byte   PIC_PAD, PIC_WIDE, PIC_LASER, PIC_PAD
title_cx:.byte  32 + 28, 32 + 86, 32 + 28, 32 + 86, 32 + 28, 32 + 86   ; (columns 14 and 43)
title_cy:.byte  32 + 40, 32 + 44, 32 + 52, 32 + 56, 32 + 64, 32 + 68   ; (rows 10, 11, 13 ...)
nowrap_txt:
        .byte   $1B, "[?7l", TERM       ; no line wrap: the last column is safe

cls_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, 0, TERM
ident_txt:
        .byte   TC_SPR, $0C, TERM       ; IDENTIFY (the answer: S P 1)
hold_txt:
        .byte   TC_SPR, $09, TERM
show_txt:
        .byte   TC_SPR, $0A, TERM
hideall_txt:
        .byte   TC_SPR, $07, TERM
clip_txt:                               ; sprites only in text rows 1-23
        .byte   TC_SPR, $0B, 1, 23, TERM
title_txt:
        .byte   TC_ROW, 2, TC_COL, 33, RV_ON, " BYTE  BREAKER ", RV_OFF
        .byte   TC_ROW, 5, TC_COL, 14, "KNOCK OUT EVERY BRICK WITH THE BALL; DON'T LET IT FALL."
        .byte   TC_ROW, 6, TC_COL, 14, "OUTLINED BRICKS TAKE TWO HITS, CHECKED ONES NEVER BREAK."
        .byte   TC_ROW, 8, TC_COL, 26, "CATCH THE CAPSULES THAT FALL:"
        .byte   TC_ROW, 10, TC_COL, 18, "WIDE PADDLE"
        .byte   TC_ROW, 11, TC_COL, 47, "THREE BALLS"
        .byte   TC_ROW, 13, TC_COL, 18, "SLOWER BALL"
        .byte   TC_ROW, 14, TC_COL, 47, "LASER: FIRE TO SHOOT"
        .byte   TC_ROW, 16, TC_COL, 18, "CATCH THE BALL"
        .byte   TC_ROW, 17, TC_COL, 47, "AN EXTRA BALL"
        .byte   TC_ROW, 23, TC_COL, 13, "SPACE OR START: PLAY   G: KEYBOARD / GAMEPAD   M: SOUND   Q: QUIT", TERM
hi_txt: .byte   "HIGH SCORE ", TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "SCORE"
        .byte   TC_COL, 19, "HIGH"
        .byte   TC_COL, 39, "BALLS"
        .byte   TC_COL, 53, "LEVEL", TERM
ready_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_ROW, 16, TC_COL, 36, "LEVEL ", TERM
unready_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_ROW, 16, TC_COL, 36, "        ", TERM
clear_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_ROW, 16, TC_COL, 33, RV_ON, " LEVEL CLEARED ", RV_OFF, TERM
paused_txt:
        .byte   RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   "        ", TERM
over_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 15, TC_COL, 31, RV_ON, "                  "
        .byte   TC_ROW, 16, TC_COL, 31, "    GAME  OVER    "
        .byte   TC_ROW, 17, TC_COL, 31, "                  "
        .byte   TC_ROW, 18, TC_COL, 31, " SPACE/A: AGAIN   "
        .byte   TC_ROW, 19, TC_COL, 31, " Q: TITLE         "
        .byte   TC_ROW, 20, TC_COL, 31, "                  ", RV_OFF, TERM
bye_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, '_', $1B, "[?7h", TERM
nospr_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS
        .byte   TC_ROW, 8, TC_COL, 12, "BYTE BREAKER NEEDS THE TERMINAL'S SPRITE LAYER (CODE 1C)."
        .byte   TC_ROW, 10, TC_COL, 12, "THE TERMINAL DIDN'T ANSWER: LOAD THE FIRMWARE WITH SPRITES."
        .byte   TC_ROW, 13, TC_COL, 12, "PRESS A KEY.", TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM

; ============================================================================
; variables
; ============================================================================
        .segment "BSS"
bss_start:
ctrl:       .res 1
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed
rng:        .res 2
attr:       .res 1
nbytes:     .res 2              ; bytes sent this frame
esc_st:     .res 1
quit:       .res 1
frame:      .res 1
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
lives:      .res 1
level:      .res 1
hud_dirty:  .res 1
msg_on:     .res 1              ; "LEVEL nn" showing
fire:       .res 1              ; this frame's controls
mv:         .res 1
mv_dir:     .res 1
mv_hold:    .res 1
rp_on:      .res 1              ; IDENTIFY sent: S P 1 are its answer
rp_got:     .res 1              ; ... and it came
rp_t:       .res 1
pad_x:      .res 1              ; the paddle's left end
pad_w:      .res 1
pw:         .res 1              ; its power (PW_*)
spd:        .res 1              ; the balls' speed, 0 .. NSPEED-1
base_spd:   .res 1
hits:       .res 1
dull:       .res 1              ; paddle bounces since a brick was hit
serve_t:    .res 1              ; frames until a ball on the paddle goes
bricks_left:.res 1
bidx:       .res 1
tpx:        .res 1
tpy:        .res 1
bi:         .res 1
si:         .res 1
qxl:        .res 1              ; a quarter of the ball's speed
qxh:        .res 1
qyl:        .res 1
qyh:        .res 1
qn:         .res 1
b_on:       .res NBALL          ; the balls
b_stuck:    .res NBALL          ;   on the paddle
b_off:      .res NBALL          ;   ... where on it
b_xl:       .res NBALL
b_xh:       .res NBALL
b_yl:       .res NBALL
b_yh:       .res NBALL
b_vxl:      .res NBALL          ;   speed (sizes)
b_vxh:      .res NBALL
b_vyl:      .res NBALL
b_vyh:      .res NBALL
b_sx:       .res NBALL          ;   1: going left
b_sy:       .res NBALL          ;   1: going up
b_ang:      .res NBALL          ;   0-3: 30, 45, 60, 72 degrees
c_on:       .res NCAP           ; the capsules
c_kind:     .res NCAP
c_x:        .res NCAP
c_yl:       .res NCAP
c_yh:       .res NCAP
s_on:       .res NSHOT          ; the laser shots
s_x:        .res NSHOT
s_y:        .res NSHOT
des_on:     .res NSLOT          ; the slots as they should be ...
des_n:      .res NSLOT
des_x:      .res NSLOT
des_y:      .res NSLOT
sl_on:      .res NSLOT          ; ... and as the terminal shows them
sl_n:       .res NSLOT
sl_x:       .res NSLOT
sl_y:       .res NSLOT
hs_i:       .res 1
map:        .res NBRICK         ; the bricks (0 none, 1, 2, 3 steel)
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
bss_end:
