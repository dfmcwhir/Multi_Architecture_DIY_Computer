; ============================================================================
; grabber.s - GOLD GRABBER, a treasure grabbing game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal in its
; control code mode (setup item J), terminal firmware v1.4 or later.
;
;   build:  make.bat  (or make)     needs ../sbc_api.inc (CLOCK_MHZ)
;   run:    L GRABBER 0500   then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  frame time in ms (default 50; real ms at any clock)
;   $0504  controls at start: 0 keyboard, 1 gamepad (default)
;   $0505  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2), the sounds in grabber_sound.inc (made by
; ../ay/tools/game_sounds.py).  Without the card the game is just silent.
;
; The miner stands on a platform at the top; below him a grabber on a rope
; swings to and fro over a pit of treasure, rocks, gophers and TNT.  Fire
; it, and it goes out at its angle until it grabs something (and reels it
; in, slower the heavier it is) or reaches the edge.  Each level has a money
; goal; the money adds up over the levels, and so do the goals.  Between
; levels a shop sells strength, gems worth double and bombs.
;
; Keys:   Space (or S / Down) grab    B (or W / Up) bomb what's held
;         P pause   M sound on / off   Q quit
; Gamepad: A grab, B bomb, Start pause
;
; The field is text rows 1-23: 160 x 92 pixels, drawn in RAM as block
; graphics characters (2 x 4 pixels each).  bg holds what stands still (the
; platform, the dirt, the treasure lying in the pit), fb the picture with
; the things that move drawn over it, sb what the terminal shows.  Each
; frame the blocks of 8 columns that had moving things on them are copied
; back from bg, the moving things drawn again, and the characters that
; differ from sb sent.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 50            ; ms per frame
FPS             = 20            ; (frames in a second at that)

; ---- terminal --------------------------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
ATTR_TEXT       = $00
ATTR_GFX        = $80
TERM            = $FF
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'

; ---- the field ---------------------------------------------------------------------
FW              = 160           ; pixels
FH              = 92
FROWS           = 23            ; text rows 1-23
COLS            = 80
PIVX            = 80            ; where the rope hangs from
PIVY            = 17
REST            = 4             ; the rope's length when the grabber is home
MINER_X         = 68
MINER_Y         = 1
WINCH_X         = 84
WINCH_Y         = 6
PLAT_X          = 60
PLAT_Y          = 14
PIT_TOP         = 24            ; nothing lies higher than this

; ---- the things in the pit ----------------------------------------------------------
NITEM           = 24
K_NONE          = 0
K_GEM           = 1
K_CHEST_S       = 2
K_CHEST_L       = 3
K_ROCK_S        = 4
K_ROCK_L        = 5
K_TNT           = 6
K_GOPHER        = 7
GEM_V           = 250           ; a gem's value
GOPHER_V        = 7
GOPHER_SPD      = $60           ; 0.375 pixels a frame
NEXP            = 6             ; explosions at a time
EXP_T           = 12            ; frames
BLAST_R         = 22            ; TNT reaches this far (pixels, centre to centre)

; ---- the grabber ---------------------------------------------------------------------
H_SWING         = 0
H_OUT           = 1
H_BACK          = 2
OUT_SPD         = $0300         ; pixels a frame (8.8)
BACK_SPD        = $0400         ; ... coming back empty
LEVEL_TIME      = 60            ; seconds

; ============================================================================
        .segment "RODATA"
        .include "grabber_data.inc"
        .include "grabber_sound.inc"    ; the sounds (game_sounds.py)

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
getc            = SBC_CHRIN     ; carry set = key in A

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
setcol: lda     #TC_COL
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

; repeat every character A times from now on (1..15), block graphics
set_rep:sta     cur_rep
        cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        jmp     setattr         ; (sends it only if it changes)
@one:   lda     #ATTR_GFX
        jmp     setattr

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
CTRL_ROW        = 22

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
        jsr     new_screen
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     hi_title
        lda     #1              ; the pictures for the list of things
        sta     pmode
        ldx     #0
@p:     stx     tmp3
        lda     tp_x,x
        sta     ox
        lda     tp_y,x
        sta     oy
        lda     tp_spr,x
        jsr     draw_spr
        ldx     tmp3
        inx
        cpx     #NTP
        bne     @p
        jsr     show_all
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

hi_title:
        lda     hi_money        ; (none yet: nothing)
        ora     hi_money+1
        ora     hi_money+2
        bne     @go
        rts
@go:    jsr     txt_mode
        ldx     #24
        ldy     #20
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
        ldx     #2
@c:     lda     hi_money,x
        sta     num,x
        dex
        bpl     @c
        jsr     prnum
        lda     #<hi2_txt
        ldy     #>hi2_txt
        jsr     print
        lda     hi_level
        jmp     pr8

exit_game:
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
        jmp     SBC_MENU

; clear the screen and forget what it showed
new_screen:
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        lda     #0
        tax
@c:     .repeat 8, K
        sta     fb + K * 256,x
        sta     sb + K * 256,x
        sta     bg + K * 256,x
        .endrepeat
        inx
        bne     @c
clear_marks:
        lda     #0
        ldx     #FROWS-1
@d:     sta     rd_lo,x
        sta     rd_hi,x
        sta     rp_lo,x
        sta     rp_hi,x
        sta     bd_lo,x
        sta     bd_hi,x
        dex
        bpl     @d
        rts

; fb = bg everywhere, and send all of it
show_all:
        ldx     #0
@c:     .repeat 8, K
        lda     bg + K * 256,x
        sta     fb + K * 256,x
        .endrepeat
        inx
        bne     @c
        jsr     clear_marks
        lda     #1
        sta     force
        jmp     present

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        ldx     #2
@z:     sta     money,x
        sta     target,x
        dex
        bpl     @z
        sta     level
        sta     bombs
        sta     strong
        sta     gx2
        sta     has_laser
        sta     quit

; ---- a level: make the pit, raise the goal, show it, play ----------------------------
next_level:
        inc     level
        jsr     gen_level
        lda     #21             ; the goal goes up by 50-70% of what's in the pit
        jsr     rnd
        clc
        adc     #50
        sta     pct
        lda     total           ; num = total * pct / 100
        ldx     pct
        jsr     mul8
        sta     num
        stx     num+1
        lda     total+1
        ldx     pct
        jsr     mul8
        clc
        adc     num+1
        sta     num+1
        txa
        adc     #0
        sta     num+2
        lda     #100
        jsr     div24
        clc                     ; target += num
        ldx     #0
        ldy     #3
@t:     lda     target,x
        adc     num,x
        sta     target,x
        inx
        dey
        bne     @t
        ; "LEVEL n  GOAL $..."
        jsr     new_screen
        lda     #<lvl_txt
        ldy     #>lvl_txt
        jsr     print
        lda     level
        jsr     pr8
        lda     #<goal_txt
        ldy     #>goal_txt
        jsr     print
        ldx     #2
@g:     lda     target,x
        sta     num,x
        dex
        bpl     @g
        jsr     prnum
        lda     #<have_txt
        ldy     #>have_txt
        jsr     print
        jsr     prmoney
        lda     strong
        beq     @ns
        lda     #<strong_txt
        ldy     #>strong_txt
        jsr     print
@ns:    lda     gx2
        beq     @ng
        lda     #<gx2_txt
        ldy     #>gx2_txt
        jsr     print
@ng:    lda     has_laser
        beq     @nl
        lda     #<laser_txt
        ldy     #>laser_txt
        jsr     print
@nl:    lda     #50
        jsr     delay_long
        ; the field
        jsr     new_screen
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        jsr     draw_bg
        jsr     show_all
        lda     #H_SWING
        sta     hst
        lda     #0
        sta     ang
        sta     ang+1
        sta     angv
        sta     angv+1
        sta     hl
        sta     carry
        sta     pop_t
        sta     fire_req
        sta     bomb_req
        lda     #REST
        sta     hl+1
        lda     #0
        ldx     #NEXP-1
@e2:    sta     ex_t,x
        dex
        bpl     @e2
        lda     #LEVEL_TIME
        sta     tsec
        lda     #FPS
        sta     tfr
        lda     #$FF
        sta     hud_dirty
        jsr     calc_hook

; ---- the frame loop --------------------------------------------------------------
game_loop:
        jsr     sfx_poll
        lda     #0
        sta     nbytes
        sta     nbytes+1
        sta     npix
        sta     npix+1
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     hook_update
        lda     hst             ; reeling in: a click every 4 frames
        cmp     #H_BACK
        bne     @nr
        lda     frame
        and     #3
        bne     @nr
        lda     #SND_REEL
        jsr     sfx_snd
@nr:    jsr     gophers
        jsr     tnt_update
        jsr     clock
        jsr     frame_draw
        jsr     hud_update
        jsr     pace
        inc     frame
        lda     tsec            ; the end of the level: out of time,
        beq     level_end
        lda     hst             ; or nothing left worth having
        bne     game_loop
        jsr     count_left
        bne     game_loop
        ldx     #NEXP-1         ; (once the bangs are over)
@x:     lda     ex_t,x
        bne     game_loop
        dex
        bpl     @x

; ---- the end of a level: the goal met, or not ----------------------------------------
level_end:
        lda     #0              ; strength, double gems and the laser last one level
        sta     strong
        sta     gx2
        sta     has_laser
        lda     money+2         ; money >= target?
        cmp     target+2
        bne     @c
        lda     money+1
        cmp     target+1
        bne     @c
        lda     money
        cmp     target
@c:     bcs     @met
        jmp     game_over
@met:   lda     #SND_MET
        jsr     sfx_snd
        lda     #<met_txt
        ldy     #>met_txt
        jsr     print
        lda     #40
        jsr     delay_long
        jsr     shop
        jmp     next_level

game_over:
        lda     #SND_OVER
        jsr     sfx_snd
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        jsr     prmoney
        lda     #<over2_txt
        ldy     #>over2_txt
        jsr     print
        ldx     #2
@g:     lda     target,x
        sta     num,x
        dex
        bpl     @g
        jsr     prnum
        lda     #<over3_txt
        ldy     #>over3_txt
        jsr     print
        lda     money+2         ; the best so far?
        cmp     hi_money+2
        bne     @c
        lda     money+1
        cmp     hi_money+1
        bne     @c
        lda     money
        cmp     hi_money
@c:     bcc     @nohi
        ldx     #2
@h:     lda     money,x
        sta     hi_money,x
        dex
        bpl     @h
        lda     level
        sta     hi_level
@nohi:  lda     #20
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

; the things left in the pit worth grabbing (not TNT).  Z set if none.
count_left:
        ldx     #NITEM-1
        ldy     #0
@l:     lda     it_k,x
        beq     @n
        cmp     #K_TNT
        beq     @n
        iny
@n:     dex
        bpl     @l
        tya
        rts

; the clock: a second every FPS frames
clock:  dec     tfr
        bne     @r
        lda     #FPS
        sta     tfr
        lda     tsec
        beq     @r
        dec     tsec
        lda     tsec            ; the last 10 seconds tick
        cmp     #10
        bcs     @nt
        lda     #SND_TICK
        jsr     sfx_snd
@nt:    lda     hud_dirty
        ora     #HD_TIME
        ldx     tsec            ; (half way: the laser's flag goes)
        cpx     #LEVEL_TIME / 2 - 1
        bne     @t
        ora     #HD_REST
@t:     sta     hud_dirty
@r:     rts

; wait out the rest of the frame: about (speed - what the frame took) ms.
; The frame took roughly: the bytes sent at 115200 baud (87 us each) plus
; the 6502's work (counted in pixels drawn and rows compared) / CLOCK_MHZ.
pace:   lda     nbytes          ; tmp = bytes / 8 (at most 255)
        sta     tmp
        lda     nbytes+1
        sta     tmp+1
        ldx     #3
@s:     lsr     tmp+1
        ror     tmp
        dex
        bne     @s
        lda     tmp+1
        beq     *+5
        jmp     @none
        ; the 6502's work, measured in the emulator (test/fit.py): about
        ; PACE_PIX ms per 8 pixels drawn + PACE_ROW per row compared +
        ; 0.12 ms per byte + PACE_BASE, at 1 MHz
        lda     npix            ; pixels / 8
        sta     tmp2
        lda     npix+1
        lsr
        ror     tmp2
        lsr
        ror     tmp2
        lsr
        ror     tmp2
        cmp     #0
        bne     @none
        lda     tmp2
        ldx     #PACE_PIX
        jsr     mul8            ; * PACE_PIX / 16
        stx     tmp3
        lsr     tmp3
        ror
        lsr     tmp3
        ror
        lsr     tmp3
        ror
        lsr     tmp3
        ror
        ldx     tmp3
        bne     @none
        clc
        adc     tmp             ; + bytes / 8
        bcs     @none
        sta     used
        lda     nrows_seen      ; + rows * PACE_ROW / 16
        ldx     #PACE_ROW
        jsr     mul8
        stx     tmp3
        lsr     tmp3
        ror
        lsr     tmp3
        ror
        lsr     tmp3
        ror
        lsr     tmp3
        ror
        clc
        adc     used
        bcs     @none
        adc     #PACE_BASE
        bcs     @none
.if CLOCK_MHZ > 1
        ldx     #CLOCK_MHZ
        jsr     div_ax          ; / the clock
.endif
        sta     used
        lda     tmp             ; serial: bytes * 87 us = bytes / 8 * 0.7
        lsr                     ;   ~ bytes / 8 * (1/2 + 1/4)
        sta     tmp2
        lsr
        adc     tmp2
        adc     used
        bcs     @none
        sta     used
        lda     speed           ; the rest of the frame time
        sec
        sbc     used
        bcc     @none
        beq     @none
        jmp     delay_ms
@none:  rts
PACE_PIX        = 17            ; (ms per 8 pixels at 1 MHz) * 16
PACE_ROW        = 17           ; (ms per row compared at 1 MHz) * 16
PACE_BASE       = 6             ; ms at 1 MHz

; A = A / X (unsigned)
div_ax: stx     tmp4
        ldx     #0
@l:     cmp     tmp4
        bcc     @d
        sbc     tmp4
        inx
        bne     @l
@d:     txa
        rts

; A (lo), X (hi) = A * X.  Preserves Y.
mul8:   sta     ma
        stx     ml
        lda     #0
        ldx     #8
        lsr     ml
@l:     bcc     @n
        clc
        adc     ma
@n:     ror
        ror     ml
        dex
        bne     @l
        tax
        lda     ml
        rts

; A = a random number 0 .. A-1 (A = 1 .. 255).  Preserves Y.
rnd:    sta     rn
        jsr     rand
        ldx     rn
        jsr     mul8
        txa
        rts

; num (3 bytes) = num / A, A = 2..255; the remainder in A
div24:  sta     dv
        lda     #0
        ldx     #24
@l:     asl     num
        rol     num+1
        rol     num+2
        rol
        bcs     @s              ; (more than 8 bits: certainly >= dv)
        cmp     dv
        bcc     @n
@s:     sbc     dv
        inc     num
@n:     dex
        bne     @l
        rts

; ============================================================================
; the grabber
; ============================================================================
hook_update:
        lda     hst
        beq     @swing
        cmp     #H_OUT
        bne     @back
        jmp     @out
@back:  jmp     h_back
@swing: ; a pendulum: the swing speed changes by (32 - angle) * 25 / 2048
        ; a frame (a swing to and fro in about 2.9 s)
        lda     #32
        sec
        sbc     ang+1
        sta     tmp             ; d (-32 .. 32)
        asl
        clc
        adc     tmp
        sta     tmp2            ; 3d
        lda     tmp             ; + d / 8
        cmp     #$80
        ror
        cmp     #$80
        ror
        cmp     #$80
        ror
        clc
        adc     tmp2            ; (-100 .. 100)
        tax
        clc
        adc     angv
        sta     angv
        txa
        and     #$80            ; (its sign, into the high byte)
        beq     @p
        lda     #$FF
@p:     adc     angv+1
        sta     angv+1
        clc
        lda     ang
        adc     angv
        sta     ang
        lda     ang+1
        adc     angv+1
        sta     ang+1
        bpl     @hi             ; (gone past the left end: back at it)
        lda     #0
        sta     ang
        sta     ang+1
        sta     angv
        sta     angv+1
        beq     @f
@hi:    cmp     #NDIR
        bcc     @f
        lda     #NDIR-1         ; (past the right end)
        sta     ang+1
        lda     #0
        sta     ang
        sta     angv
        sta     angv+1
@f:     lda     fire_req        ; fire: out it goes
        beq     @c
        lda     #SND_SHOOT
        jsr     sfx_snd
        lda     #H_OUT
        sta     hst
@c:     jmp     calc_hook
@out:   clc                     ; out, until it hits something or an edge
        lda     hl
        adc     #<OUT_SPD
        sta     hl
        lda     hl+1
        adc     #>OUT_SPD
        sta     hl+1
        jsr     calc_hook
        lda     hedge
        bne     h_empty
        jsr     tip_at_hook
        jsr     hook_hit        ; X = what it touches, or carry clear
        bcs     @hit
        rts
@hit:   lda     it_k,x
        cmp     #K_TNT
        bne     grab
        jsr     explode         ; TNT: bang, and back with nothing
h_empty:lda     #<BACK_SPD
        sta     rsp
        lda     #>BACK_SPD
        sta     rsp+1
        lda     #0
        sta     carry
        lda     #H_BACK
        sta     hst
        rts

; grab item X: out of the pit and onto the grabber
grab:   stx     gi
        sta     ck
        cmp     #K_GEM          ; a gem sparkles, the rest thump
        beq     @sg
        lda     #SND_GRAB
        bne     @sn
@sg:    lda     #SND_GEM
@sn:    jsr     sfx_snd
        lda     ck
        tay
        lda     k_spd_lo,y      ; how fast it comes up
        sta     rsp
        lda     k_spd_hi,y
        sta     rsp+1
        lda     strong          ; (strength: half as fast again)
        beq     @ns
        lda     rsp+1
        lsr
        sta     tmp+1
        lda     rsp
        ror
        clc
        adc     rsp
        sta     rsp
        lda     tmp+1
        adc     rsp+1
        sta     rsp+1
@ns:    lda     k_w,y
        sta     cw
        lda     k_h,y
        sta     ch
        lda     it_vl,x         ; its value
        sta     cval
        lda     it_vh,x
        sta     cval+1
        cpy     #K_GEM          ; a gem: double with the upgrade
        bne     @ng
        lda     gx2
        beq     @ng
        asl     cval
        rol     cval+1
@ng:    lda     k_spr,y
        sta     cspr
        cpy     #K_GOPHER       ; a gopher: as it was going, and its gem
        bne     @take
        jsr     gopher_pic
        sta     cspr
        lda     it_gem,x
        beq     @take
        lda     #14
        sta     cw
        lda     #<GEM_V
        ldy     #>GEM_V
        ldx     gx2
        beq     @g1
        lda     #<(GEM_V * 2)
        ldy     #>(GEM_V * 2)
@g1:    clc
        adc     cval
        sta     cval
        tya
        adc     cval+1
        sta     cval+1
@take:  ldx     gi
        jsr     remove
        lda     #1
        sta     carry
        lda     #H_BACK
        sta     hst
        rts

; coming back up, with something or not
h_back: lda     bomb_req        ; a bomb: blow up what it holds
        beq     @nb
        lda     carry
        beq     @nb
        lda     bombs
        beq     @nb
        dec     bombs
        lda     hud_dirty
        ora     #HD_BOMBS
        sta     hud_dirty
        lda     hx              ; a bang where it was
        sec
        sbc     #7
        sta     tmp
        lda     hy
        sec
        sbc     #2
        tay
        ldx     tmp
        jsr     add_boom
        lda     #0
        sta     carry
        lda     #<BACK_SPD
        sta     rsp
        lda     #>BACK_SPD
        sta     rsp+1
@nb:    sec
        lda     hl
        sbc     rsp
        sta     hl
        lda     hl+1
        sbc     rsp+1
        sta     hl+1
        bcc     @home
        cmp     #REST
        bcs     @c
@home:  lda     #0              ; home: cash in what it brought
        sta     hl
        lda     #REST
        sta     hl+1
        lda     #H_SWING
        sta     hst
        lda     carry
        beq     @c
        lda     #SND_CASH
        jsr     sfx_snd
        lda     #0
        sta     carry
        clc
        lda     money
        adc     cval
        sta     money
        lda     money+1
        adc     cval+1
        sta     money+1
        bcc     @m
        inc     money+2
@m:     lda     cval
        sta     popv
        lda     cval+1
        sta     popv+1
        lda     #40
        sta     pop_t
        lda     hud_dirty
        ora     #HD_MONEY | HD_POP
        sta     hud_dirty
@c:     jmp     calc_hook

; hx, hy: the grabber at angle ang+1 and length hl+1; hedge = 1 at an edge
calc_hook:
        lda     #0
        sta     hedge
        ldy     ang+1
        lda     hl+1
        ldx     dir_sx,y
        jsr     mul8            ; length * |sin| / 128
        asl
        txa
        rol
        sta     tmp
        lda     dir_neg,y
        bne     @l
        lda     tmp             ; to the right
        cmp     #FW - PIVX - 2
        bcc     @r1
        inc     hedge
        lda     #FW - PIVX - 2
@r1:    clc
        adc     #PIVX
        jmp     @x
@l:     lda     tmp             ; to the left
        cmp     #PIVX - 1
        bcc     @l1
        inc     hedge
        lda     #PIVX - 1
@l1:    sta     tmp
        lda     #PIVX
        sec
        sbc     tmp
@x:     sta     hx
        lda     hl+1            ; down: length * cos / 128
        ldx     dir_cy,y
        jsr     mul8
        asl
        txa
        rol
        clc
        adc     #PIVY
        cmp     #FH - 4
        bcc     @y
        inc     hedge
        lda     #FH - 4
@y:     sta     hy
        rts

; tpx, tpy: the claw's tip (what grabs), a little way along the rope from
; its end
tip_at_hook:
        ldy     ang+1
        lda     hx
        clc
        adc     tip_dx,y
        sta     tpx
        lda     hy
        clc
        adc     tip_dy,y
        sta     tpy
        rts

; carry set and X = the thing at the claw's tip (tpx, tpy)
hook_hit:
        ldx     #NITEM-1
@l:     ldy     it_k,x
        beq     @n
        lda     tpx             ; across: tpx + 2 - x in 0 .. w + 3
        clc
        adc     #2
        sec
        sbc     it_x,x
        bcc     @n
        sta     tmp
        lda     k_w,y
        adc     #3              ; (carry set: + 4)
        cmp     tmp
        bcc     @n
        beq     @n
        lda     tpy             ; down: tpy - y in 0 .. h - 1
        sec
        sbc     it_y,x
        bcc     @n
        cmp     k_h,y
        bcs     @n
        sec
        rts
@n:     dex
        bpl     @l
        clc
        rts

; ============================================================================
; the things in the pit
; ============================================================================
; take item X out of the pit (rubbed out of bg if it lies still)
remove: lda     it_k,x
        beq     @r
        cmp     #K_GOPHER
        beq     @g
        stx     tmp3
        tay
        lda     it_x,x
        sta     ox
        lda     it_y,x
        sta     oy
        lda     #2
        sta     pmode
        lda     k_spr,y
        jsr     draw_spr
        lda     #0
        sta     pmode
        ldx     tmp3
@g:     lda     #K_NONE
        sta     it_k,x
@r:     rts

; the middle of item X: tmp (x), tmp2 (y)
centre: ldy     it_k,x
        lda     k_w,y
        lsr
        clc
        adc     it_x,x
        sta     tmp
        lda     k_h,y
        lsr
        clc
        adc     it_y,x
        sta     tmp2
        rts

; TNT X goes off: a bang, and everything near it goes; other TNT near it
; goes off a moment later
explode:stx     ei
        jsr     centre
        lda     tmp
        sta     ecx
        lda     tmp2
        sta     ecy
        lda     ecx
        sec
        sbc     #7
        tax
        lda     ecy
        sec
        sbc     #5
        tay
        jsr     add_boom
        ldx     ei
        jsr     remove
        ldx     #NITEM-1
@l:     stx     ej
        lda     it_k,x
        beq     @n
        jsr     centre
        lda     tmp             ; |dx|, |dy| < 32
        sec
        sbc     ecx
        bcs     @x1
        eor     #$FF
        adc     #1
@x1:    cmp     #32
        bcs     @n
        tay
        lda     tmp2
        sec
        sbc     ecy
        bcs     @y1
        eor     #$FF
        adc     #1
@y1:    cmp     #32
        bcs     @n
        tax
        clc                     ; dx^2 + dy^2 < BLAST_R^2?
        lda     sq_lo,y
        adc     sq_lo,x
        sta     tmp
        lda     sq_hi,y
        adc     sq_hi,x
        cmp     #>(BLAST_R * BLAST_R)
        bcc     @hit
        bne     @n
        lda     tmp
        cmp     #<(BLAST_R * BLAST_R)
        bcs     @n
@hit:   ldx     ej
        lda     it_k,x
        cmp     #K_TNT
        bne     @gone
        lda     it_fuse,x       ; (TNT: in a moment)
        bne     @n
        lda     #5
        sta     it_fuse,x
        bne     @n
@gone:  jsr     remove
@n:     ldx     ej
        dex
        bpl     @l
        rts

; lit TNT: off it goes when its fuse runs out
tnt_update:
        ldx     #NITEM-1
@l:     lda     it_k,x
        cmp     #K_TNT
        bne     @n
        lda     it_fuse,x
        beq     @n
        dec     it_fuse,x
        bne     @n
        stx     tu_i
        jsr     explode
        ldx     tu_i
@n:     dex
        bpl     @l
        ldx     #NEXP-1         ; and the bangs fade
@e:     lda     ex_t,x
        beq     @en
        dec     ex_t,x
@en:    dex
        bpl     @e
        rts

; a bang with its top left at X, Y
add_boom:
        lda     #SND_BOOM
        jsr     sfx_snd
        stx     tmp4
        ldx     #NEXP-1
@l:     lda     ex_t,x
        beq     @f
        dex
        bpl     @l
        rts
@f:     lda     tmp4
        sta     ex_x,x
        tya
        sta     ex_y,x
        lda     #EXP_T
        sta     ex_t,x
        rts

; the gophers run to and fro
gophers:ldx     #NITEM-1
@l:     lda     it_k,x
        cmp     #K_GOPHER
        bne     @n
        lda     it_dir,x
        bne     @left
        clc
        lda     it_xf,x
        adc     #GOPHER_SPD
        sta     it_xf,x
        bcc     @n
        inc     it_x,x
        lda     it_x,x
        cmp     it_x1,x
        bcc     @n
        lda     #1
        sta     it_dir,x
        bne     @n
@left:  sec
        lda     it_xf,x
        sbc     #GOPHER_SPD
        sta     it_xf,x
        bcs     @n
        dec     it_x,x
        lda     it_x0,x
        cmp     it_x,x
        bcc     @n
        lda     #0
        sta     it_dir,x
@n:     dex
        bpl     @l
        rts

; A = gopher X's picture (going left or right, legs, with a gem or not)
gopher_pic:
        lda     frame
        lsr
        lsr
        and     #1
        sta     tmp4
        lda     it_dir,x
        asl
        ora     tmp4
        ldy     it_gem,x
        beq     @n
        clc
        adc     #SP_GOPHERG_R1 - SP_GOPHER_R1
@n:     clc
        adc     #SP_GOPHER_R1
        rts

; ============================================================================
; drawing
; ============================================================================
; the blocks moving things were drawn on last frame (and blocks where bg
; changed) get bg back; then the moving things are drawn and the changes sent
frame_draw:
        ldx     #FROWS-1
@r:     lda     rd_lo,x
        sta     rp_lo,x
        ora     bd_lo,x
        sta     bm_lo
        lda     rd_hi,x
        sta     rp_hi,x
        ora     bd_hi,x
        sta     bm_hi
        ora     bm_lo
        beq     @nx
        lda     fbrow_lo,x
        sta     @w+1
        lda     fbrow_hi,x
        sta     @w+2
        lda     bgrow_lo,x
        sta     @rd+1
        lda     bgrow_hi,x
        sta     @rd+2
        stx     fd_r
        ldy     #0              ; block (8 columns)
@b:     cpy     #8
        bcs     @bh
        lda     bm_lo
        and     blkbit,y
        jmp     @bt
@bh:    lda     bm_hi
        and     blkbit,y
@bt:    beq     @bn
        sty     fd_b
        tya
        asl
        asl
        asl
        tax                     ; its first column
        ldy     #8
@rd:    lda     $FFFF,x
@w:     sta     $FFFF,x
        inx
        dey
        bne     @rd
        ldy     fd_b
@bn:    iny
        cpy     #10
        bne     @b
        ldx     fd_r
@nx:    lda     bd_lo,x         ; (bg changes: compared this frame)
        sta     rd_lo,x
        lda     bd_hi,x
        sta     rd_hi,x
        lda     #0
        sta     bd_lo,x
        sta     bd_hi,x
        dex
        bmi     *+5
        jmp     @r
        lda     #0              ; the moving things, into fb
        sta     pmode
        lda     #WINCH_X        ; the winch turns while reeling in
        sta     ox
        lda     #WINCH_Y
        sta     oy
        lda     #SP_WINCH1
        ldx     hst
        cpx     #H_BACK
        bne     @w1
        lda     frame
        lsr
        and     #1
        clc
        adc     #SP_WINCH1
@w1:    jsr     draw_spr
        ldx     #NITEM-1        ; the gophers
@g:     lda     it_k,x
        cmp     #K_GOPHER
        bne     @gn
        stx     fd_i
        lda     it_x,x
        sta     ox
        lda     it_y,x
        sta     oy
        jsr     gopher_pic
        jsr     draw_spr
        ldx     fd_i
@gn:    dex
        bpl     @g
        ldx     #NEXP-1         ; the bangs
@e:     lda     ex_t,x
        beq     @en
        stx     fd_i
        and     #2
        lsr
        clc
        adc     #SP_BOOM1
        pha
        lda     ex_x,x
        sta     ox
        lda     ex_y,x
        sta     oy
        pla
        jsr     draw_spr
        ldx     fd_i
@en:    dex
        bpl     @e
        jsr     rope            ; the rope and the grabber
        ldy     ang+1           ; the claw, turned the way the rope points
        lda     dir_claw,y
        ldx     carry
        beq     @cl
        clc
        adc     #NCLAW
@cl:    pha
        sec
        sbc     #SP_CLAW0
        tax
        lda     hx
        clc
        adc     claw_ox,x
        sta     ox
        lda     hy
        clc
        adc     claw_oy,x
        sta     oy
        pla
        jsr     draw_spr
        lda     carry           ; what it holds, its middle 3 + h/2 along the rope
        beq     @lz
        jsr     held_at
        lda     cspr
        jsr     draw_spr
@lz:    lda     hst             ; the laser pointer: where it would go
        bne     @p
        jsr     laser_on
        beq     @p
        jsr     draw_laser
@p:     jmp     present

; ox, oy for what the grabber holds: its middle 3 + h / 2 pixels along the
; rope from the rope's end
held_at:
        lda     ch
        lsr
        clc
        adc     #3
        sta     tmp3
        ldy     ang+1
        ldx     dir_sx,y        ; across
        jsr     mul8
        asl
        txa
        rol
        sta     tmp
        lda     cw
        lsr
        sta     tmp4
        ldy     ang+1
        lda     dir_neg,y
        bne     @l
        lda     hx
        clc
        adc     tmp
        jmp     @x
@l:     lda     hx
        sec
        sbc     tmp
@x:     sec
        sbc     tmp4
        sta     ox
        lda     tmp3            ; down
        ldx     dir_cy,y
        jsr     mul8
        asl
        txa
        rol
        clc
        adc     hy
        sta     tmp
        lda     ch
        lsr
        sta     tmp4
        lda     tmp
        sec
        sbc     tmp4
        sta     oy
        rts

; Z clear if the laser pointer is on (bought, and the first half of the level)
laser_on:
        lda     has_laser
        beq     @r
        lda     tsec
        cmp     #LEVEL_TIME / 2
        lda     #0
        rol                     ; (carry: tsec >= half)
@r:     rts

; the laser pointer: a dotted line from the grabber the way it would go out,
; to the edge, or to what it would grab (marked with a little ring).  It
; follows the grabber's own path: the rope end is at length * dir / 128,
; the length going 7, 10, 13 ... as it would going out; worked out here by
; adding 3 * dir / 128 (8.8) each step, which comes to the same pixels.
draw_laser:
        ldy     ang+1
        lda     dir_sx,y        ; the start (length 7) and the step (3), 8.8
        ldx     #14
        jsr     mul8
        sta     lx88
        stx     lx88+1
        lda     dir_sx,y
        ldx     #6
        jsr     mul8
        sta     lsx
        stx     lsx+1
        lda     dir_cy,y
        ldx     #14
        jsr     mul8
        sta     ly88
        stx     ly88+1
        lda     dir_cy,y
        ldx     #6
        jsr     mul8
        sta     lsy
        stx     lsy+1
        lda     dir_neg,y
        sta     lneg
        lda     tip_dx,y
        sta     ltx
        lda     tip_dy,y
        sta     lty
        lda     #$FF
        sta     pf_row
        lda     #0
        sta     lstep
@l:     lda     lx88+1          ; the rope end at this length (as calc_hook)
        ldx     lneg
        bne     @left
        cmp     #FW - PIVX - 2
        bcc     *+5
        jmp     @r
        clc
        adc     #PIVX
        jmp     @x
@left:  cmp     #PIVX - 1
        bcs     @r
        sta     tmp
        lda     #PIVX
        sec
        sbc     tmp
@x:     sta     px
        lda     ly88+1
        clc
        adc     #PIVY
        cmp     #FH - 4
        bcs     @r
        sta     py
        lda     px              ; anything at the claw's tip?
        clc
        adc     ltx
        sta     tpx
        lda     py
        clc
        adc     lty
        sta     tpy
        jsr     hook_hit
        bcs     @hit
        lda     npix            ; (for the frame timing: a step costs about
        clc                     ; as much as 4 pixels)
        adc     #4
        sta     npix
        bcc     @c
        inc     npix+1
@c:     lda     lstep           ; a dot every step (after the first two)
        cmp     #2
        bcc     @nd
        jsr     pfast
@nd:    inc     lstep
        clc
        lda     lx88
        adc     lsx
        sta     lx88
        lda     lx88+1
        adc     lsx+1
        sta     lx88+1
        clc
        lda     ly88
        adc     lsy
        sta     ly88
        lda     ly88+1
        adc     lsy+1
        sta     ly88+1
        jmp     @l
@r:     rts
@hit:   lda     tpx             ; a ring where it would grab
        sec
        sbc     #2
        sta     ox
        lda     tpy
        sec
        sbc     #2
        sta     oy
        lda     #SP_TARGET
        jmp     draw_spr

; the rope: a line from (PIVX, PIVY) down to (hx, hy), always in the field
rope:   lda     #$FF
        sta     pf_row
        lda     #PIVX
        sta     px
        lda     #PIVY
        sta     py
        lda     hy
        sec
        sbc     #PIVY
        sta     ln_dy
        lda     hx
        sec
        sbc     #PIVX
        bcs     @rt
        eor     #$FF            ; (carry clear: + 1)
        adc     #1
        sta     ln_dx
        lda     #$FF
        bne     @g
@rt:    sta     ln_dx
        lda     #1
@g:     sta     ln_sx
        lda     ln_dx
        cmp     ln_dy
        bcc     @steep
        lsr                     ; mostly across
        sta     ln_err
        ldx     ln_dx
        inx
        stx     ln_n
@sl:    jsr     pfast
        lda     px
        clc
        adc     ln_sx
        sta     px
        lda     ln_err
        sec
        sbc     ln_dy
        bcs     @s1
        adc     ln_dx
        inc     py
@s1:    sta     ln_err
        dec     ln_n
        bne     @sl
        rts
@steep: lda     ln_dy           ; mostly down
        lsr
        sta     ln_err
        ldx     ln_dy
        inx
        stx     ln_n
@tl:    jsr     pfast
        inc     py
        lda     ln_err
        sec
        sbc     ln_dx
        bcs     @t1
        adc     ln_dy
        tax
        lda     px
        clc
        adc     ln_sx
        sta     px
        txa
@t1:    sta     ln_err
        dec     ln_n
        bne     @tl
        rts

; set pixel px, py (in the field) in fb, quickly: the row's address is kept
; from the last pixel when it is on the same text row (pf_row)
pfast:  lda     py
        lsr
        lsr
        cmp     pf_row
        beq     @same
        sta     pf_row
        tay
        lda     fbrow_lo,y
        sta     @o+1
        sta     @w+1
        lda     fbrow_hi,y
        sta     @o+2
        sta     @w+2
@same:  ldy     pf_row          ; its block, in rd
        lda     px
        lsr
        lsr
        lsr
        lsr
        tax
        lda     blkbit,x
        cpx     #8
        bcs     @h
        ora     rd_lo,y
        sta     rd_lo,y
        jmp     @b
@h:     ora     rd_hi,y
        sta     rd_hi,y
@b:     lda     py
        and     #3
        asl
        sta     pl_t
        lda     px
        and     #1
        ora     pl_t
        tay
        lda     px
        lsr
        tax
        lda     bitmask,y
@o:     ora     $FFFF,x
@w:     sta     $FFFF,x
        inc     npix
        bne     @r
        inc     npix+1
@r:     rts

; draw picture A with its top left at ox, oy (pmode: 0 into fb, 1 into bg,
; 2 rubbed out of bg).  Pixels off the field are left out.
draw_spr:
        ldx     pmode
        bne     @slow
        jmp     spr_fast
@slow:  tax
        lda     spr_lo,x
        sta     @d+1
        lda     spr_hi,x
        sta     @d+2
        jsr     @get            ; width (not needed), height, bytes a row
        jsr     @get
        sta     ds_h
        jsr     @get
        sta     ds_nb
        lda     oy
        sta     py
@row:   lda     ox
        sta     ds_x
        lda     ds_nb
        sta     ds_k
@byte:  jsr     @get
        sta     ds_bits
        ldx     #8
        lda     ds_bits
        bne     @bit
        lda     ds_x            ; (nothing in these 8: skip)
        clc
        adc     #8
        sta     ds_x
        jmp     @nb
@bit:   asl     ds_bits
        bcc     @nx
        lda     ds_x
        sta     px
        stx     ds_i
        jsr     plot
        ldx     ds_i
@nx:    inc     ds_x
        dex
        bne     @bit
@nb:    dec     ds_k
        bne     @byte
        inc     py
        dec     ds_h
        bne     @row
        rts
@get:
@d:     lda     $FFFF
        inc     @d+1
        bne     @g
        inc     @d+2
@g:     rts

; draw picture A into fb at ox, oy: a row at a time, its blocks marked in rd
; for each text row it covers
spr_fast:
        tax
        lda     spr_lo,x
        sta     @d+1
        lda     spr_hi,x
        sta     @d+2
        jsr     @get            ; width, height, bytes a row
        sta     ds_w
        jsr     @get
        sta     ds_h
        jsr     @get
        sta     ds_nb
        lda     ox              ; the columns it covers, clipped: xl .. xr
        ldx     #0
        cmp     #FW
        bcc     @l1
        txa                     ; (starts off the left: from 0)
@l1:    sta     ds_xl
        lda     ox
        clc
        adc     ds_w
        sec
        sbc     #1
        cmp     #FW
        bcc     @r1
        ldx     ox              ; (off the right, unless it wrapped from the left)
        cpx     #FW
        bcs     @r1
        lda     #FW - 1
@r1:    sta     ds_xr
        lda     #$FF
        sta     pf_row
        lda     oy
        sta     py
@row:   lda     py
        cmp     #FH
        bcc     @in
        lda     ds_nb           ; (off the field: skip the row)
        sta     ds_k
@sk:    jsr     @get
        dec     ds_k
        bne     @sk
        jmp     @nr
@in:    lsr
        lsr
        cmp     pf_row          ; a new text row: its address, its blocks
        beq     @same
        sta     pf_row
        tay
        lda     fbrow_lo,y
        sta     @o+1
        sta     @w+1
        lda     fbrow_hi,y
        sta     @o+2
        sta     @w+2
        jsr     mark_span
@same:  lda     py
        and     #3
        asl
        sta     ds_sh
        lda     ox
        sta     ds_x
        lda     ds_nb
        sta     ds_k
@byte:  jsr     @get
        bne     @bits
        lda     ds_x            ; (nothing in these 8)
        clc
        adc     #8
        sta     ds_x
        jmp     @nb
@bits:  sta     ds_bits
        lda     #8
        sta     ds_cnt
@bit:   asl     ds_bits
        bcc     @nx
        lda     ds_x
        cmp     #FW
        bcs     @nx
        lsr
        tax
        lda     ds_x
        and     #1
        ora     ds_sh
        tay
        lda     bitmask,y
@o:     ora     $FFFF,x
@w:     sta     $FFFF,x
        inc     npix
@nx:    inc     ds_x
        dec     ds_cnt
        bne     @bit
@nb:    dec     ds_k
        bne     @byte
@nr:    inc     py
        dec     ds_h
        beq     *+5
        jmp     @row
        rts
@get:
@d:     lda     $FFFF
        inc     @d+1
        bne     @g
        inc     @d+2
@g:     cmp     #0
        rts

; mark the blocks of text row Y from column ds_xl to ds_xr (pixels) in rd
mark_span:
        lda     ds_xr
        cmp     ds_xl
        bcc     @r              ; (nothing on the field)
        lsr
        lsr
        lsr
        lsr
        sta     ms_end
        lda     ds_xl
        lsr
        lsr
        lsr
        lsr
        tax
@l:     lda     blkbit,x
        cpx     #8
        bcs     @h
        ora     rd_lo,y
        sta     rd_lo,y
        jmp     @n
@h:     ora     rd_hi,y
        sta     rd_hi,y
@n:     cpx     ms_end
        inx
        bcc     @l
@r:     rts

; set pixel px, py: pmode 0 in fb (noting its block in rd), 1 in bg, 2 clear
; it in bg (noting the block in bd).  Off the field: nothing.
plot:   lda     px
        cmp     #FW
        bcs     @out
        lda     py
        cmp     #FH
        bcs     @out
        inc     npix
        bne     @c
        inc     npix+1
@c:     lsr
        lsr
        tay                     ; the text row
        lda     px              ; its block of 8 columns (16 pixels)
        lsr
        lsr
        lsr
        lsr
        tax
        lda     pmode
        bne     @bgm
        lda     blkbit,x
        cpx     #8
        bcs     @h0
        ora     rd_lo,y
        sta     rd_lo,y
        jmp     @a0
@h0:    ora     rd_hi,y
        sta     rd_hi,y
@a0:    lda     fbrow_lo,y
        sta     pl_lo
        lda     fbrow_hi,y
        jmp     @adr
@out:   rts
@bgm:   lda     blkbit,x
        cpx     #8
        bcs     @h1
        ora     bd_lo,y
        sta     bd_lo,y
        jmp     @a1
@h1:    ora     bd_hi,y
        sta     bd_hi,y
@a1:    lda     bgrow_lo,y
        sta     pl_lo
        lda     bgrow_hi,y
@adr:   sta     pl_hi
        lda     px
        lsr
        clc
        adc     pl_lo
        sta     @r1+1
        sta     @w1+1
        sta     @r2+1
        sta     @w2+1
        lda     pl_hi
        adc     #0
        sta     @r1+2
        sta     @w1+2
        sta     @r2+2
        sta     @w2+2
        lda     py
        and     #3
        asl
        sta     pl_t
        lda     px
        and     #1
        ora     pl_t
        tay
        lda     bitmask,y
        ldx     pmode
        cpx     #2
        beq     @clr
@r1:    ora     $FFFF
@w1:    sta     $FFFF
        rts
@clr:   eor     #$FF
@r2:    and     $FFFF
@w2:    sta     $FFFF
        rts

; send the characters that differ from what the terminal shows, in the rows
; drawn on this frame or the last.  A run of the same character goes once,
; with the repeat count.
present:
        lda     attr            ; block graphics (keep a repeat count it has)
        cmp     #$FF
        beq     @gm
        tax
        bmi     @g
@gm:    jsr     gfx_mode
        lda     #1
        sta     cur_rep
@g:     lda     #$FF
        sta     cur_r
        lda     #0
        sta     prow
        sta     nrows_seen
@row:   ldx     prow
        lda     rd_lo,x         ; the blocks drawn on this frame or the last
        ora     rp_lo,x
        sta     bm_lo
        lda     rd_hi,x
        ora     rp_hi,x
        sta     bm_hi
        ora     bm_lo
        ora     force
        bne     @scan
        jmp     @nrow
@scan:  inc     nrows_seen
        lda     force
        beq     @nf
        lda     #$FF            ; (everything)
        sta     bm_lo
        sta     bm_hi
@nf:    lda     fbrow_lo,x
        sta     @fb+1
        sta     @f2+1
        lda     fbrow_hi,x
        sta     @fb+2
        sta     @f2+2
        lda     sbrow_lo,x
        sta     @sb+1
        sta     @s2+1
        sta     @sw+1
        lda     sbrow_hi,x
        sta     @sb+2
        sta     @s2+2
        sta     @sw+2
        ldx     #0
@blk:   txa                     ; the next marked block at or after column X
        lsr
        lsr
        lsr
        tay
@nb:    cpy     #10
        bcc     @nb1
        jmp     @nrow
@nb1:   cpy     #8
        bcs     @nbh
        lda     bm_lo
        and     blkbit,y
        jmp     @nbt
@nbh:   lda     bm_hi
        and     blkbit,y
@nbt:   bne     @got
        iny
        jmp     @nb
@got:   tya
        asl
        asl
        asl
        sta     tmp4
        clc
        adc     #8
        sta     blk_end
        cpx     tmp4
        bcs     @c
        ldx     tmp4
@c:
@fb:    lda     $FFFF,x
@sb:    cmp     $FFFF,x
        bne     @diff
        inx
        cpx     blk_end
        bcc     @c
        jmp     @blk
@diff:  sta     val
        stx     pcol
        lda     #1              ; the run of this character, and how far
        sta     need            ; into it the last changed one is
        txa
        tay
        iny
@rl:    cpy     #COLS
        bcs     @rend
        tya
        sec
        sbc     pcol
        cmp     #15
        bcs     @rend
        sta     tmp4
@f2:    lda     $FFFF,y
        cmp     val
        bne     @rend
@s2:    cmp     $FFFF,y
        beq     @rs1
        ldx     tmp4
        inx
        stx     need
@rs1:   iny
        bne     @rl
@rend:  tya
        sec
        sbc     pcol
        sta     runl
        lda     cur_rep         ; how many: the count already set if it fits,
        cmp     need            ; one for a single change, else the run
        bcc     @nofit
        cmp     runl
        beq     @setk
        bcc     @setk
@nofit: lda     need
        cmp     #1
        beq     @setk
        cmp     #4
        bcs     @whole
        lda     cur_rep
        cmp     #1
        beq     @setk
@whole: lda     runl
@setk:  sta     kcnt
        lda     cur_r           ; the cursor
        cmp     prow
        bne     @goto
        lda     pcol
        cmp     cur_c
        beq     @put
        ldx     pcol
        jsr     setcol
        jmp     @put
@goto:  ldx     pcol
        ldy     prow
        iny                     ; (the field starts on text row 1)
        jsr     gotoxy
        lda     prow
        sta     cur_r
@put:   lda     kcnt
        jsr     set_rep
        lda     val
        jsr     putblk
        ldx     pcol            ; the terminal shows them now
        ldy     kcnt
        lda     val
@sw:    sta     $FFFF,x
        inx
        dey
        bne     @sw
        stx     cur_c
        cpx     #COLS
        bcs     @end
        cpx     blk_end
        bcs     @nxt
        jmp     @c
@nxt:   jmp     @blk
@end:   lda     #$FF            ; the cursor wrapped: position unknown
        sta     cur_r
@nrow:  inc     prow
        lda     prow
        cmp     #FROWS
        beq     @done
        jmp     @row
@done:  lda     #0
        sta     force
        lda     #1              ; (back to single characters for text)
        jmp     set_rep

; ============================================================================
; input
; ============================================================================
read_input:
        lda     #0
        sta     fire_req
        sta     bomb_req
        lda     ctrl
        beq     @keys
        jsr     read_pad
        lda     padnew
        and     #PAD_A | PAD_DOWN
        beq     @b
        lda     #1
        sta     fire_req
@b:     lda     padnew
        and     #PAD_B | PAD_UP
        beq     @st
        lda     #1
        sta     bomb_req
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @keys
@done:  rts

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
        cmp     #'A'            ; up: bomb
        beq     @bomb
        cmp     #'B'            ; down: grab
        beq     @fire
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
@uc:    cmp     #' '
        beq     @fire
        cmp     #'S'
        beq     @fire
        cmp     #'B'
        beq     @bomb
        cmp     #'W'
        beq     @bomb
        cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@fire:  lda     #1
        sta     fire_req
        rts
@bomb:  lda     #1
        sta     bomb_req
        rts
@pause: jmp     pause
@quit:  lda     #1
        sta     quit
        rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        jsr     txt_mode
        ldx     #72
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
        lda     #$FF            ; (the status line again)
        sta     hud_dirty
        rts

; ============================================================================
; numbers and the status line
; ============================================================================
; print num (3 bytes) in decimal, no leading zeros; ndig = digits printed
prnum:  lda     #0
        sta     ndig
        ldy     #0              ; the power of ten (3 bytes each)
@p:     ldx     #0              ; the digit
@s:     lda     num             ; num -= 10^k while it can
        sec
        sbc     pow10,y
        sta     tmp
        lda     num+1
        sbc     pow10+1,y
        sta     tmp+1
        lda     num+2
        sbc     pow10+2,y
        bcc     @d
        sta     num+2
        lda     tmp+1
        sta     num+1
        lda     tmp
        sta     num
        inx
        bne     @s
@d:     txa
        bne     @out
        lda     ndig            ; (a leading zero: not printed, but the
        bne     @out            ; last digit always is)
        cpy     #6 * 3
        bne     @nx
@out:   txa
        ora     #'0'
        jsr     putc
        inc     ndig
@nx:    iny
        iny
        iny
        cpy     #7 * 3
        bne     @p
        rts

; print "$" and the money
prmoney:lda     #'$'
        jsr     putc
        ldx     #2
@c:     lda     money,x
        sta     num,x
        dex
        bpl     @c
        jmp     prnum

; print A (0..255) in decimal
pr8:    sta     num
        lda     #0
        sta     num+1
        sta     num+2
        jmp     prnum

; spaces to fill a field A wide after ndig characters
padto:  sec
        sbc     ndig
        beq     @r
        bcc     @r
        tax
        lda     #' '
@l:     jsr     putc
        dex
        bne     @l
@r:     rts

HD_MONEY        = $01
HD_TIME         = $02
HD_BOMBS        = $04
HD_POP          = $08
HD_REST         = $10           ; the goal, the level, strength, double gems

hud_update:
        lda     pop_t           ; (the "+$" goes after a while)
        beq     @nd
        dec     pop_t
        bne     @nd
        lda     hud_dirty
        ora     #HD_POP
        sta     hud_dirty
@nd:    lda     hud_dirty
        bne     @go
        rts
@go:    jsr     txt_mode
        lda     hud_dirty
        and     #HD_MONEY
        beq     @1
        ldx     #7
        ldy     #0
        jsr     gotoxy
        jsr     prmoney
        lda     #8
        jsr     padto
@1:     lda     hud_dirty
        and     #HD_REST
        beq     @2
        ldx     #22
        ldy     #0
        jsr     gotoxy
        lda     #'$'
        jsr     putc
        ldx     #2
@t:     lda     target,x
        sta     num,x
        dex
        bpl     @t
        jsr     prnum
        lda     #8
        jsr     padto
        ldx     #38
        ldy     #0
        jsr     gotoxy
        lda     level
        jsr     pr8
        lda     #3
        jsr     padto
        ldx     #58
        ldy     #0
        jsr     gotoxy
        lda     #<strong_s_txt
        ldy     #>strong_s_txt
        ldx     strong
        bne     @s1
        lda     #<blank7_txt+4
        ldy     #>blank7_txt
@s1:    jsr     print
        ldx     #62
        ldy     #0
        jsr     gotoxy
        lda     #<gx2_s_txt
        ldy     #>gx2_s_txt
        ldx     gx2
        bne     @s2
        lda     #<blank7_txt+2
        ldy     #>blank7_txt
@s2:    jsr     print
        ldx     #68
        ldy     #0
        jsr     gotoxy
        jsr     laser_on
        bne     @s3
        lda     #<blank7_txt+2
        ldy     #>blank7_txt
        jmp     @s4
@s3:    lda     #<laser_s_txt
        ldy     #>laser_s_txt
@s4:    jsr     print
@2:     lda     hud_dirty
        and     #HD_TIME
        beq     @3
        ldx     #47
        ldy     #0
        jsr     gotoxy
        lda     tsec
        jsr     pr8
        lda     #2
        jsr     padto
@3:     lda     hud_dirty
        and     #HD_BOMBS
        beq     @4
        ldx     #56
        ldy     #0
        jsr     gotoxy
        lda     bombs
        ora     #'0'
        jsr     putc
@4:     lda     hud_dirty       ; "+$123" for a moment after cashing in
        and     #HD_POP
        beq     @5
        ldx     #74
        ldy     #0
        jsr     gotoxy
        lda     pop_t
        beq     @pc
        lda     #'+'
        jsr     putc
        lda     #'$'
        jsr     putc
        lda     popv
        sta     num
        lda     popv+1
        sta     num+1
        lda     #0
        sta     num+2
        jsr     prnum
        lda     #4
        jsr     padto
        jmp     @5
@pc:    lda     #<blank7_txt+1
        ldy     #>blank7_txt
        jsr     print
@5:     lda     #0
        sta     hud_dirty
        rts

; ============================================================================
; the shop, between levels
; ============================================================================
shop:   ldx     #NSHOP-1        ; what's for sale today, and the prices
@o:     stx     sh_i
        lda     #100
        jsr     rnd
        ldx     sh_i
        cmp     sh_prob,x
        lda     #0
        rol                     ; (carry clear below 65: offered)
        eor     #1
        sta     sh_av,x
        lda     sh_span,x       ; base + rnd(span) + level * step
        jsr     rnd
        ldx     sh_i
        clc
        adc     sh_base,x
        sta     sh_pl,x
        lda     #0
        adc     #0
        sta     sh_ph,x
        lda     level
        ldy     sh_step,x
        tax
        tya
        jsr     mul8
        ldy     sh_i
        clc
        adc     sh_pl,y
        sta     sh_pl,y
        txa
        adc     sh_ph,y
        sta     sh_ph,y
        ldx     sh_i
        dex
        bpl     @o
        lda     sh_av           ; (always something)
        ora     sh_av+1
        ora     sh_av+2
        ora     sh_av+3
        bne     @some
        lda     #3
        jsr     rnd
        tax
        lda     #1
        sta     sh_av,x
@some:  lda     #0
        sta     sel
        sta     esc_st
        lda     #<sh_none_txt   ; (no message yet)
        sta     sh_msg
        lda     #>sh_none_txt
        sta     sh_msg+1
        jsr     new_screen
        lda     #<shop_txt
        ldy     #>shop_txt
        jsr     print
        lda     level
        jsr     pr8
        lda     #<shop2_txt
        ldy     #>shop2_txt
        jsr     print
@show:  jsr     shop_show
        jsr     read_pad
        jsr     flush_in
@l:     jsr     rand            ; (waiting stirs the random numbers)
        jsr     sfx_poll
        jsr     read_pad
        lda     padnew
        and     #PAD_UP
        bne     @up
        lda     padnew
        and     #PAD_DOWN
        bne     @down
        lda     padnew
        and     #PAD_A | PAD_START
        beq     *+5
        jmp     @pick
        jsr     getc
        bcc     @l
        ldx     esc_st          ; arrow keys: ESC [ A / B
        beq     @plain
        cpx     #1
        bne     @e2
        inc     esc_st
        jmp     @l
@e2:    ldx     #0
        stx     esc_st
        cmp     #'A'
        beq     @up
        cmp     #'B'
        beq     @down
        jmp     @l
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        jmp     @l
@np:    ldx     ctrl            ; (gamepad mode: not what the pad types)
        beq     @kb
        jsr     pad_typed
        bcs     @l
@kb:    cmp     #'a'
        bcc     @uc
        and     #$DF
@uc:    cmp     #'1'
        bcc     @k2
        cmp     #'1' + NSHOP
        bcs     @k2
        sbc     #'1' - 1        ; (carry clear: - '1')
        sta     sel
        jmp     @pick
@k2:    cmp     #'W'
        beq     @up
        cmp     #'S'
        beq     @down
        cmp     #' '
        beq     @pick
        cmp     #$0D
        beq     @pick
        cmp     #'N'
        beq     @next
        jmp     @l
@up:    lda     sel
        bne     *+5
        jmp     @l
        dec     sel
        jmp     @show
@down:  lda     sel
        cmp     #NSHOP
        bcc     *+5
        jmp     @l
        inc     sel
        jmp     @show
@next:  lda     #NSHOP
        sta     sel
@pick:  ldx     sel
        cpx     #NSHOP
        bne     @buy
        rts                     ; on to the next level
@buy:   lda     sh_av,x
        bne     @av
        lda     #<sh_no_txt
        ldy     #>sh_no_txt
        jmp     @no
@av:    cpx     #2              ; bombs: 9 at most
        bne     @ok9
        lda     bombs
        cmp     #9
        bcc     @ok9
        lda     #<sh_full_txt
        ldy     #>sh_full_txt
        jmp     @no
@ok9:   lda     money           ; enough money?
        sec
        sbc     sh_pl,x
        sta     tmp
        lda     money+1
        sbc     sh_ph,x
        sta     tmp+1
        lda     money+2
        sbc     #0
        bcs     @pay
        lda     #<sh_poor_txt
        ldy     #>sh_poor_txt
        jmp     @no
@pay:   sta     money+2
        lda     tmp
        sta     money
        lda     tmp+1
        sta     money+1
        lda     #0
        sta     sh_av,x         ; (sold)
        lda     #1
        cpx     #0
        bne     @b1
        sta     strong
@b1:    cpx     #1
        bne     @b2
        sta     gx2
@b2:    cpx     #2
        bne     @b3
        inc     bombs
@b3:    cpx     #3
        bne     @b4
        sta     has_laser
@b4:    lda     #SND_BUY
        jsr     sfx_snd
        lda     #<sh_bought_txt
        ldy     #>sh_bought_txt
        jmp     @msg
@no:    pha                     ; (can't: a buzz)
        lda     #SND_NO
        jsr     sfx_snd
        pla
@msg:   sta     sh_msg
        sty     sh_msg+1
        jmp     @show

; the shop's changing lines: the money, the three things and the cursor
shop_show:
        jsr     txt_mode
        ldx     #36
        ldy     #5
        jsr     gotoxy
        jsr     prmoney
        lda     #10
        jsr     padto
        ldx     #0
@i:     stx     sh_i
        txa                     ; row 8 + 2i
        asl
        adc     #8
        tay
        ldx     #14
        jsr     gotoxy
        lda     #' '            ; the cursor
        ldx     sh_i
        cpx     sel
        bne     @c
        lda     #'>'
@c:     jsr     putc
        lda     #' '
        jsr     putc
        ldx     sh_i
        cpx     #NSHOP
        beq     @next
        lda     sh_name_lo,x
        ldy     sh_name_hi,x
        jsr     print
        ldx     #62
        ldy     sh_i
        tya
        asl
        adc     #8
        tay
        jsr     gotoxy
        ldx     sh_i
        lda     sh_av,x
        beq     @na
        lda     #'$'
        jsr     putc
        lda     sh_pl,x
        sta     num
        lda     sh_ph,x
        sta     num+1
        lda     #0
        sta     num+2
        jsr     prnum
        lda     #10
        jsr     padto
        jmp     @n
@na:    lda     #<sh_sold_txt
        ldy     #>sh_sold_txt
        jsr     print
        jmp     @n
@next:  lda     #<sh_go_txt
        ldy     #>sh_go_txt
        jsr     print
@n:     ldx     sh_i
        inx
        cpx     #NSHOP + 1
        bne     @i
        ldx     #16             ; bombs held, and the message
        ldy     #19
        jsr     gotoxy
        lda     #<sh_bombs_txt
        ldy     #>sh_bombs_txt
        jsr     print
        lda     bombs
        ora     #'0'
        jsr     putc
        ldx     #16
        ldy     #20
        jsr     gotoxy
        lda     sh_msg
        ldy     sh_msg+1
        jmp     print

; ============================================================================
; a new pit
; ============================================================================
gen_level:
        lda     #0
        sta     total
        sta     total+1
        ldx     #NITEM-1
@c:     sta     it_k,x
        sta     it_fuse,x
        sta     it_gem,x
        sta     it_xf,x
        dex
        bpl     @c
        lda     level           ; (the counts stop growing at level 10)
        cmp     #10
        bcc     @l
        lda     #10
@l:     sta     lvc
        ; gophers from level 2: 0-1, +1 from level 4, +1 from level 7
        lda     level
        cmp     #2
        bcc     @ng
        lda     #2
        jsr     rnd
        ldx     level
        cpx     #4
        adc     #0
        cpx     #7
        adc     #0
        ldx     #K_GOPHER
        jsr     place_n
@ng:    ; big chests: 0-1, +1 from level 3
        lda     #2
        jsr     rnd
        ldx     level
        cpx     #3
        adc     #0
        ldx     #K_CHEST_L
        jsr     place_n
        ; big rocks: 1-2 + level / 3
        lda     lvc
        ldx     #3
        jsr     div_ax
        sta     tmp4
        lda     #2
        jsr     rnd
        sec
        adc     tmp4
        ldx     #K_ROCK_L
        jsr     place_n
        ; small chests: 1-3
        lda     #3
        jsr     rnd
        clc
        adc     #1
        ldx     #K_CHEST_S
        jsr     place_n
        ; TNT from level 2: 0-1, +1 from level 5
        lda     level
        cmp     #2
        bcc     @nt
        lda     #2
        jsr     rnd
        ldx     level
        cpx     #5
        adc     #0
        ldx     #K_TNT
        jsr     place_n
@nt:    ; gems: 1-2 + level / 4
        lda     lvc
        lsr
        lsr
        sta     tmp4
        lda     #2
        jsr     rnd
        sec
        adc     tmp4
        ldx     #K_GEM
        jsr     place_n
        ; small rocks: 2-4
        lda     #3
        jsr     rnd
        clc
        adc     #2
        ldx     #K_ROCK_S
        jmp     place_n

; place A things of kind X
place_n:stx     pk
        sta     pn
@l:     lda     pn
        beq     @r
        jsr     place
        dec     pn
        jmp     @l
@r:     rts

; put a thing of kind pk somewhere free (40 tries, else not at all)
place:  lda     #40
        sta     tries
@try:   dec     tries
        bne     @go
        rts
@go:    ldy     pk
        lda     #0
        sta     glen
        cpy     #K_GOPHER       ; a gopher: its run, 40-119 pixels
        bne     @ng
        lda     #80
        jsr     rnd
        clc
        adc     #40
        sta     glen
@ng:    lda     #FW - 4         ; x: 2 .. FW - 2 - w - run
        sec
        sbc     k_w,y
        sec
        sbc     glen
        jsr     rnd
        clc
        adc     #2
        sta     nbx
        lda     k_w,y
        clc
        adc     glen
        sta     nbw
        lda     #FH - 2         ; y: ymin .. FH - 2 - h
        sec
        sbc     k_h,y
        sec
        sbc     k_ymin,y
        jsr     rnd
        clc
        adc     k_ymin,y
        sta     nby
        ldx     #NITEM-1        ; clear of everything else (3 pixels apart)?
@ov:    ldy     it_k,x
        beq     @on
        lda     it_bx,x         ; nbx < bx + bw + 3
        clc
        adc     it_bw,x
        adc     #3
        cmp     nbx
        bcc     @on
        beq     @on
        lda     nbx             ; bx < nbx + nbw + 3
        clc
        adc     nbw
        adc     #3
        cmp     it_bx,x
        bcc     @on
        beq     @on
        lda     it_y,x          ; nby < y + h + 3
        clc
        adc     k_h,y
        adc     #3
        cmp     nby
        bcc     @on
        beq     @on
        ldy     pk              ; y < nby + nh + 3
        lda     nby
        clc
        adc     k_h,y
        adc     #3
        cmp     it_y,x
        bcc     @on
        beq     @on
        jmp     @try            ; (in the way)
@on:    dex
        bpl     @ov
        ldx     #NITEM-1        ; a free slot
@f:     lda     it_k,x
        beq     @slot
        dex
        bpl     @f
        rts
@slot:  ldy     pk
        tya
        sta     it_k,x
        lda     nbx
        sta     it_bx,x
        sta     it_x,x
        sta     it_x0,x
        lda     nbw
        sta     it_bw,x
        lda     nby
        sta     it_y,x
        stx     pi
        lda     #0              ; its value
        sta     it_vh,x
        lda     k_val,y
        sta     it_vl,x
        lda     k_vrnd,y        ; + rnd(n) * step
        beq     @v
        jsr     rnd
        ldy     pk
        ldx     k_vstep,y
        jsr     mul8
        ldy     pi
        clc
        adc     it_vl,y
        sta     it_vl,y
        txa
        adc     it_vh,y
        sta     it_vh,y
        ldx     pi
        ldy     pk
@v:     cpy     #K_CHEST_L      ; (big chests: 300 and up)
        bne     @v2
        clc
        lda     it_vl,x
        adc     #<200
        sta     it_vl,x
        lda     it_vh,x
        adc     #>200
        sta     it_vh,x
@v2:    cpy     #K_GOPHER
        bne     @tot
        lda     nbx             ; a gopher: its run, where it starts, which way
        clc
        adc     glen
        sta     it_x1,x
        lda     glen
        jsr     rnd
        ldx     pi
        clc
        adc     it_x0,x
        sta     it_x,x
        lda     #2
        jsr     rnd
        ldx     pi
        sta     it_dir,x
        lda     #100            ; a gem in its mouth: 35%
        jsr     rnd
        ldx     pi
        cmp     #35
        lda     #0
        rol
        eor     #1
        sta     it_gem,x
        beq     @tot
        clc
        lda     total
        adc     #<GEM_V
        sta     total
        lda     total+1
        adc     #>GEM_V
        sta     total+1
@tot:   ldx     pi
        clc
        lda     total
        adc     it_vl,x
        sta     total
        lda     total+1
        adc     it_vh,x
        sta     total+1
        rts

; the still things into bg: the platform, the miner, the dirt and what lies
; in the pit
draw_bg:lda     #1
        sta     pmode
        lda     #PLAT_X
        sta     ox
        lda     #PLAT_Y
        sta     oy
        lda     #SP_PLATFORM
        jsr     draw_spr
        lda     #MINER_X
        sta     ox
        lda     #MINER_Y
        sta     oy
        lda     #SP_MINER
        jsr     draw_spr
        lda     #DIRT           ; specks of dirt, clear of the things
        sta     tries
@d:     lda     #FW
        jsr     rnd
        sta     px
        lda     #FH - PIT_TOP + 4
        jsr     rnd
        clc
        adc     #PIT_TOP - 4
        sta     py
        ldx     #NITEM-1
@db:    ldy     it_k,x
        beq     @dn
        lda     px              ; px + 1 - bx < bw + 2?
        clc
        adc     #1
        sec
        sbc     it_bx,x
        bcc     @dn
        sta     tmp
        lda     it_bw,x
        adc     #1              ; (carry set: + 2)
        cmp     tmp
        bcc     @dn
        beq     @dn
        lda     py
        clc
        adc     #1
        sec
        sbc     it_y,x
        bcc     @dn
        sta     tmp
        lda     k_h,y
        adc     #1
        cmp     tmp
        bcc     @dn
        beq     @dn
        jmp     @dx             ; (on something: not here)
@dn:    dex
        bpl     @db
        jsr     plot
@dx:    dec     tries
        bne     @d
        ldx     #NITEM-1        ; the things that lie still
@i:     lda     it_k,x
        beq     @in
        cmp     #K_GOPHER
        beq     @in
        stx     tmp3
        tay
        lda     it_x,x
        sta     ox
        lda     it_y,x
        sta     oy
        lda     k_spr,y
        jsr     draw_spr
        ldx     tmp3
@in:    dex
        bpl     @i
        lda     #0
        sta     pmode
        rts
DIRT            = 90

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
bitmask:.byte   $01, $02, $04, $08, $10, $20, $40, $80
blkbit: .byte   $01, $02, $04, $08, $10, $20, $40, $80, $01, $02
; the kinds of thing: none, gem, small chest, big chest, small rock, big
; rock, TNT, gopher
k_spr:  .byte   0, SP_GEM, SP_CHEST_S, SP_CHEST_L, SP_ROCK_S, SP_ROCK_L, SP_TNT, SP_GOPHER_R1
k_w:    .byte   0, 5, 9, 13, 7, 12, 8, 11
k_h:    .byte   0, 5, 7, 9, 5, 9, 10, 6
.define K_SPD 0, $0300, $01C0, $00C0, $0140, $0080, $0400, $0280
k_spd_lo:.lobytes K_SPD         ; how fast it comes up (pixels a frame, 8.8)
k_spd_hi:.hibytes K_SPD
k_ymin: .byte   0, 30, 32, 50, 26, 30, 32, 30   ; the highest it lies
k_val:  .byte   0, <GEM_V, 100, 100, 11, 20, 0, GOPHER_V   ; value: this
k_vrnd: .byte   0, 0, 26, 51, 5, 10, 0, 0       ; ... + rnd(this)
k_vstep:.byte   0, 0, 10, 10, 1, 1, 0, 0        ;     * this (big chests + 200)
; the shop: strength, double gems, a bomb, the laser pointer.  For sale:
; this % of the time.  Price: base + rnd(span) + level * step
NSHOP = 4
sh_prob:.byte   65, 65, 65, 25
sh_base:.byte   50, 100, 30, 250
sh_span:.byte   101, 151, 71, 201
sh_step:.byte   10, 15, 5, 25
sh_name_lo:.byte <sh_n0, <sh_n1, <sh_n2, <sh_n3
sh_name_hi:.byte >sh_n0, >sh_n1, >sh_n2, >sh_n3
pow10:  .byte   $40, $42, $0F   ; 1000000
        .byte   $A0, $86, $01   ; 100000
        .byte   $10, $27, $00   ; 10000
        .byte   $E8, $03, $00
        .byte   $64, $00, $00
        .byte   $0A, $00, $00
        .byte   $01, $00, $00
; the pictures on the title screen
tp_spr: .byte   SP_GEM, SP_CHEST_L, SP_CHEST_S, SP_ROCK_L, SP_ROCK_S, SP_GOPHER_R1, SP_GOPHERG_R1, SP_TNT
tp_x:   .byte   44, 40, 56, 40, 56, 40, 56, 44
tp_y:   .byte   20, 30, 31, 42, 44, 55, 55, 65
NTP = 8
fbrow_lo:
.repeat FROWS, R
        .byte   <(fb + R * COLS)
.endrepeat
fbrow_hi:
.repeat FROWS, R
        .byte   >(fb + R * COLS)
.endrepeat
sbrow_lo:
.repeat FROWS, R
        .byte   <(sb + R * COLS)
.endrepeat
sbrow_hi:
.repeat FROWS, R
        .byte   >(sb + R * COLS)
.endrepeat
bgrow_lo:
.repeat FROWS, R
        .byte   <(bg + R * COLS)
.endrepeat
bgrow_hi:
.repeat FROWS, R
        .byte   >(bg + R * COLS)
.endrepeat

cls_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, 0, TERM
title_txt:
        .byte   TC_ROW, 1, TC_COL, 33, RV_ON, " GOLD GRABBER ", RV_OFF
        .byte   TC_ROW, 3, TC_COL, 10, "SWING THE GRABBER OVER THE PIT AND REEL IN WHAT IT CATCHES."
        .byte   TC_ROW, 4, TC_COL, 10, "MEET EACH LEVEL'S MONEY GOAL; BETWEEN LEVELS, SHOP FOR HELP."
        .byte   TC_ROW, 6, TC_COL, 38, "GEM          $250"
        .byte   TC_ROW, 9, TC_COL, 38, "CHESTS       $100 - $800 (BIG ONES: HEAVY)"
        .byte   TC_ROW, 12, TC_COL, 38, "ROCKS        $11 - $29 (VERY HEAVY)"
        .byte   TC_ROW, 15, TC_COL, 38, "GOPHERS      $7, WITH A GEM $257"
        .byte   TC_ROW, 18, TC_COL, 38, "TNT          BLOWS UP WHAT'S NEAR IT"
        .byte   TC_ROW, 21, TC_COL, 0, "SPACE GRAB  B BOMB  P PAUSE  M SOUND  Q QUIT   PAD: A GRAB  B BOMB  START PAUSE"
        .byte   TC_ROW, 23, TC_COL, 23, "SPACE OR START: PLAY      Q: QUIT", TERM
hi_txt: .byte   "BEST: ", TERM
hi2_txt:.byte   " AT LEVEL ", TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "MONEY"
        .byte   TC_COL, 16, "GOAL"
        .byte   TC_COL, 32, "LEVEL"
        .byte   TC_COL, 42, "TIME"
        .byte   TC_COL, 50, "BOMBS", TERM
lvl_txt:.byte   TC_ROW, 9, TC_COL, 35, "LEVEL ", TERM
goal_txt:
        .byte   TC_ROW, 11, TC_COL, 31, "GOAL   $", TERM
have_txt:
        .byte   TC_ROW, 13, TC_COL, 31, "MONEY  ", TERM
strong_txt:
        .byte   TC_ROW, 16, TC_COL, 27, "STRENGTH: REELING IN FASTER", TERM
gx2_txt:.byte   TC_ROW, 17, TC_COL, 27, "GEMS ARE WORTH DOUBLE", TERM
strong_s_txt:
        .byte   "STR", TERM
gx2_s_txt:
        .byte   "GEMX2", TERM
laser_s_txt:
        .byte   "LASER", TERM
laser_txt:
        .byte   TC_ROW, 18, TC_COL, 27, "LASER POINTER: THE FIRST 30 SECONDS", TERM
blank7_txt:
        .byte   "       ", TERM
met_txt:.byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 10, TC_COL, 30, RV_ON, "                    "
        .byte   TC_ROW, 11, TC_COL, 30, "   GOAL REACHED!    "
        .byte   TC_ROW, 12, TC_COL, 30, "                    ", RV_OFF, TERM
paused_txt:
        .byte   RV_ON, " PAUSED ", RV_OFF, TERM
over_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 8, TC_COL, 24, RV_ON, "                                "
        .byte   TC_ROW, 9, TC_COL, 24, "           GAME  OVER           "
        .byte   TC_ROW, 10, TC_COL, 24, "                                ", RV_OFF
        .byte   TC_ROW, 11, TC_COL, 24, "                                "
        .byte   TC_ROW, 12, TC_COL, 24, "                                "
        .byte   TC_ROW, 13, TC_COL, 24, "                                "
        .byte   TC_ROW, 14, TC_COL, 24, "                                "
        .byte   TC_ROW, 11, TC_COL, 26, "YOU HAD      ", TERM
over2_txt:
        .byte   TC_ROW, 12, TC_COL, 26, "THE GOAL WAS $", TERM
over3_txt:
        .byte   TC_ROW, 14, TC_COL, 26, "SPACE/A: AGAIN     Q: TITLE", TERM
shop_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 2, TC_COL, 35, RV_ON, " THE SHOP ", RV_OFF
        .byte   TC_ROW, 5, TC_COL, 27, "YOU HAVE", TC_ROW, 4, TC_COL, 27, "LEVEL ", TERM
shop2_txt:
        .byte   " DONE!  THE NEXT GOAL IS HIGHER."
        .byte   TC_ROW, 22, TC_COL, 4, "UP/DOWN: CHOOSE   A/SPACE: BUY (OR GO ON)   1-4: BUY   N: NEXT LEVEL", TERM
sh_n0:  .byte   "1  STRENGTH: REEL IN FASTER (NEXT LEVEL)", TERM
sh_n1:  .byte   "2  GEMS WORTH DOUBLE (NEXT LEVEL)", TERM
sh_n2:  .byte   "3  A BOMB: B BLOWS UP WHAT YOU HOLD", TERM
sh_n3:  .byte   "4  LASER POINTER (FIRST HALF OF NEXT LEVEL)", TERM
sh_go_txt:
        .byte   "   NEXT LEVEL", TERM
sh_sold_txt:
        .byte   "SOLD OUT   ", TERM
sh_bombs_txt:
        .byte   "BOMBS: ", TERM
sh_none_txt:
        .byte   "                              ", TERM
sh_no_txt:
        .byte   "NOT FOR SALE NOW              ", TERM
sh_poor_txt:
        .byte   "NOT ENOUGH MONEY              ", TERM
sh_full_txt:
        .byte   "YOU CAN'T CARRY MORE BOMBS    ", TERM
sh_bought_txt:
        .byte   "BOUGHT!                       ", TERM
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
ctrl:       .res 1
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
attr:       .res 1
cur_rep:    .res 1
nbytes:     .res 2              ; bytes sent this frame
npix:       .res 2              ; pixels drawn this frame
nrows_seen: .res 1
used:       .res 1
esc_st:     .res 1
quit:       .res 1
frame:      .res 1
hud_dirty:  .res 1
force:      .res 1
money:      .res 3              ; binary, low byte first
target:     .res 3              ; the goal
num:        .res 3              ; a number being printed or worked on
ndig:       .res 1
level:      .res 1
lvc:        .res 1
bombs:      .res 1
strong:     .res 1              ; strength (this level)
gx2:        .res 1              ; gems worth double (this level)
has_laser:  .res 1              ; the laser pointer (the first half of this level)
tpx:        .res 1              ; the claw's tip
tpy:        .res 1
ch:         .res 1              ; the height of what the grabber holds
lx88:       .res 2              ; the laser: where it has got to (8.8, from the pivot)
ly88:       .res 2
lsx:        .res 2              ;   its step
lsy:        .res 2
lneg:       .res 1
ltx:        .res 1
lty:        .res 1
lstep:      .res 1
total:      .res 2              ; the worth of the pit
pct:        .res 1
hi_money:   .res 3
hi_level:   .res 1
hst:        .res 1              ; the grabber: swinging, out, coming back
ang:        .res 2              ; its angle (8.8; 0 .. NDIR - 1)
angv:       .res 2              ; ... and its swing speed
hl:         .res 2              ; the rope's length (8.8)
hx:         .res 1              ; where the grabber is
hy:         .res 1
hedge:      .res 1              ; at an edge of the field
carry:      .res 1              ; holding something
ck:         .res 1              ; ... its kind,
cw:         .res 1              ; width,
cspr:       .res 1              ; picture
cval:       .res 2              ; and value
rsp:        .res 2              ; coming back this fast
gi:         .res 1
fire_req:   .res 1
bomb_req:   .res 1
tsec:       .res 1              ; seconds left
tfr:        .res 1              ; frames to the next second
popv:       .res 2              ; "+$" this much
pop_t:      .res 1              ; ... for this many frames
it_k:       .res NITEM          ; the things in the pit: kind,
it_x:       .res NITEM          ;   top left,
it_y:       .res NITEM
it_bx:      .res NITEM          ;   the room it takes across (a gopher: its run)
it_bw:      .res NITEM
it_vl:      .res NITEM          ;   value
it_vh:      .res NITEM
it_gem:     .res NITEM          ;   a gopher with a gem
it_fuse:    .res NITEM          ;   TNT going off in this many frames
it_dir:     .res NITEM          ;   a gopher: 0 right, 1 left,
it_xf:      .res NITEM          ;     x fraction,
it_x0:      .res NITEM          ;     its run
it_x1:      .res NITEM
ex_t:       .res NEXP           ; bangs: frames left,
ex_x:       .res NEXP           ;   top left
ex_y:       .res NEXP
ei:         .res 1
ej:         .res 1
ecx:        .res 1
ecy:        .res 1
tu_i:       .res 1
ma:         .res 1
ml:         .res 1
rn:         .res 1
dv:         .res 1
sh_av:      .res 4              ; the shop: for sale,
sh_pl:      .res 4              ;   prices
sh_ph:      .res 4
sh_i:       .res 1
sel:        .res 1
sh_msg:     .res 2
pk:         .res 1              ; making the pit
pn:         .res 1
pi:         .res 1
tries:      .res 1
glen:       .res 1
nbx:        .res 1
nbw:        .res 1
nby:        .res 1
pmode:      .res 1              ; drawing: 0 fb, 1 bg, 2 rub out of bg
px:         .res 1
py:         .res 1
ox:         .res 1
oy:         .res 1
pl_lo:      .res 1
pl_hi:      .res 1
pl_t:       .res 1
ds_h:       .res 1
ds_w:       .res 1
ds_xl:      .res 1
ds_xr:      .res 1
ds_sh:      .res 1
ds_cnt:     .res 1
ms_end:     .res 1
pf_row:     .res 1
ds_nb:      .res 1
ds_x:       .res 1
ds_k:       .res 1
ds_bits:    .res 1
ds_i:       .res 1
ln_dx:      .res 1
ln_dy:      .res 1
ln_sx:      .res 1
ln_err:     .res 1
ln_n:       .res 1
fd_r:       .res 1
fd_b:       .res 1
fd_i:       .res 1
rd_lo:      .res FROWS          ; per row: blocks of 8 columns drawn on, this
rd_hi:      .res FROWS          ;   frame (bits: blocks 0-7, 8-9)
rp_lo:      .res FROWS          ;   ... and the last frame
rp_hi:      .res FROWS
bd_lo:      .res FROWS          ;   ... and where bg changed
bd_hi:      .res FROWS
bm_lo:      .res 1
bm_hi:      .res 1
blk_end:    .res 1
prow:       .res 1
pcol:       .res 1
cur_r:      .res 1
cur_c:      .res 1
val:        .res 1
need:       .res 1
runl:       .res 1
kcnt:       .res 1
tmp:        .res 2
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
bss_end:

        .segment "BUFS"
fb:         .res 2048           ; the field as it should be (80 x 23 characters)
sb:         .res 2048           ; the field as the terminal shows it
bg:         .res 2048           ; what stands still
