; ============================================================================
; rocks.s - SPACE ROCKS, a game in the style of the arcade rock shooter,
; for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal in its
; control code mode (setup item J), terminal firmware v1.4 or later.
;
;   build:  make.bat  (or make)     needs ../sbc_api.inc (CLOCK_MHZ)
;   run:    L ROCKS 0500   then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  frame time in ms (default 55; real ms at any clock)
;   $0504  controls at start: 0 keyboard, 1 gamepad
;   $0505  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2), the sounds in rocks_sound.inc (made by
; ../ay/tools/game_sounds.py).  Without the card the game is just silent.
;
; Keys:   A / D or Left / Right  turn      W or Up   thrust
;         Space                  fire      S or Down hyperspace
;         P pause   M sound on / off   Q quit
; Gamepad: left / right turn, up thrust, A fire, B hyperspace, Start pause
;
; The playfield is text rows 1-23: 160 x 92 pixels.  Every frame it is drawn
; in RAM (fb, one byte per character cell, 2 x 4 pixels each) and compared
; with what the terminal shows (sb); only the characters that changed are
; sent, runs of the same character with the terminal's repeat count.  Only
; rows that had something drawn on them this frame or the last are looked at.
;
; Everything that moves is an "object": the ship (0), 4 bullets, 24 rocks,
; 16 bits of debris, a flying saucer and its 2 bullets.  Positions and speeds are 8.8 fixed point pixels;
; the field wraps round at the edges.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 55            ; ms per frame

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

; ---- objects -----------------------------------------------------------------------
NOBJ            = 48
O_SHIP          = 0
O_BUL           = 1             ; 1-4
NBUL            = 4
O_ROCK          = 5             ; 5-28
NROCK           = 24
O_PART          = 29            ; 29-44
NPART           = 16
O_UFO           = 45            ; the saucer
O_EB            = 46            ; 46-47: its bullets
NEB             = 2
K_NONE          = 0             ; o_kind
K_SHIP          = 1
K_BUL           = 2
K_ROCK          = 3
K_PART          = 4
K_UFO           = 5
K_EBUL          = 6

BUL_LIFE        = 28            ; frames
FIRE_GAP        = 3
INVULN          = 50            ; frames after (re)appearing
RESPAWN_WAIT    = 40

; ============================================================================
        .segment "RODATA"
        .include "rocks_data.inc"
        .include "rocks_sound.inc"      ; the sounds (game_sounds.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound on the AY-3-8910 card

; ----------------------------------------------------------------------------
; I/O helpers
; ----------------------------------------------------------------------------
; carry set = key in A.  After IDENTIFY (1C 0C) the terminal answers S P 1:
; while IDENTIFYs are unanswered (rp_out) those are taken as answers, not
; keys (nor ever, with this terminal: keys come in lower case, and an answer
; coming late must not be taken as P = pause or S = hyperspace).  Each answer
; counts once, at the first of its characters that comes
; (the 6502 can miss some of the three, back to back at 115200): an S always
; starts one; a P or 1 does if no S came; the 1 ends it.
getc:   jsr     SBC_CHRIN
        bcc     @r
        pha
        lda     hwspr           ; (with the sprite terminal capital S P 1 are
        beq     @key            ;  never keys: a late answer isn't a pause)
        pla
        cmp     #'S'
        beq     @new
        cmp     #'P'
        beq     @p
        cmp     #'1'
        bne     @k2
        lda     rp_in           ; 1: the end (an answer, if nothing else of it came)
        bne     @e
        jsr     rp_one
@e:     lda     #0
        sta     rp_in
        jmp     getc
@p:     lda     rp_in
        bne     getc
@new:   jsr     rp_one
        lda     #1
        sta     rp_in
        jmp     getc
@k2:    sec
        rts
@key:   pla
        sec
@r:     rts

; an answer came: one fewer to wait for
rp_one: lda     rp_out
        beq     @r
        dec     rp_out
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
        jsr     spr_setup       ; the terminal's sprites, if it has them

title:  jsr     sfx_off
        jsr     new_screen
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     hi_title
        ; a few rocks for decoration
        jsr     clear_objects
        ldx     #0
@r:     stx     tmp2
        lda     deco_x,x
        sta     tmp3
        lda     deco_y,x
        tay
        lda     deco_s,x
        ldx     tmp3
        jsr     add_rock_at
        ldx     tmp2
        inx
        cpx     #NDECO
        bne     @r
        jsr     frame_draw
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
        jsr     txt_mode
        ldx     #34
        ldy     #21
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
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
        .endrepeat
        inx
        bne     @c
        ldx     #FROWS-1
@d:     sta     rd_lo,x
        sta     rd_hi,x
        sta     rp_lo,x
        sta     rp_hi,x
        dex
        bpl     @d
        lda     hwspr           ; (the clear hid the sprites)
        beq     @r
        lda     #<clip_txt
        ldy     #>clip_txt
        jsr     print
        jmp     spr_forget
@r:     rts

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     wave
        sta     quit
        lda     #3
        sta     lives
        lda     #0
        sta     ufo_wait
        lda     #90             ; the first saucer comes after a while
        sta     ufo_next
        jsr     new_screen
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        jsr     clear_objects
        jsr     spawn_ship
new_wave:
        inc     wave
        lda     wave            ; 3 + wave big rocks, up to 8
        clc
        adc     #3
        cmp     #9
        bcc     @n
        lda     #8
@n:     sta     tmp2
@r:     jsr     rand            ; along the left or top edge, away from the ship
        and     #1
        beq     @left
        jsr     rand
        cmp     #FW
        bcs     @r
        tax
        ldy     #0
        jmp     @add
@left:  jsr     rand
        and     #$7F
        cmp     #FH
        bcs     @left
        tay
        ldx     #0
@add:   lda     #0              ; big
        jsr     add_rock_at
        dec     tmp2
        bne     @r
        lda     #1
        sta     hud_dirty
        sta     beat_t          ; the heartbeat: slow again
        lda     #BEAT_SLOW
        sta     beat_gap
        lda     #0
        sta     wave_t
        lda     o_kind+O_SHIP   ; (the ship gets a moment to see them)
        beq     game_loop
        lda     #30
        sta     inv_t

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
@1:     jsr     ship_control
        jsr     ufo_update
        jsr     move_all
        jsr     collide
        jsr     ship_life
        jsr     frame_draw
        jsr     hud_update
        lda     dead_t          ; game over?
        cmp     #1
        bne     @2
        lda     lives
        bne     @2
        jmp     game_over
@2:     jsr     snd_frame
        jsr     wave_check
        jsr     pace
        inc     frame
        jmp     game_loop

; ---- the sounds that go on: the engine, the saucer's hum, the heartbeat ----
snd_frame:
        lda     flame           ; thrust: its rumble, every frame
        beq     @nt
        lda     #SND_THRUST
        jsr     sfx_snd
@nt:    lda     o_kind+O_UFO    ; a saucer: its hum (big or small)
        cmp     #K_UFO
        bne     @nu
        lda     ufo_hum
        bne     @beat
        inc     ufo_hum
        lda     o_size+O_UFO
        clc
        adc     #SND_UFOBIG
        jsr     sfx_snd
        jmp     @beat
@nu:    lda     ufo_hum
        beq     @beat
        lda     #0
        sta     ufo_hum
        ldx     #1
        jsr     sfx_stop
@beat:  lda     wave_t          ; the heartbeat, while there are rocks: it
        bne     @r              ; gets faster as the wave goes on
        dec     beat_t
        bne     @r
        lda     beat_gap
        sta     beat_t
        cmp     #BEAT_FAST+1
        bcc     @b
        dec     beat_gap
@b:     lda     beat_n
        eor     #1
        sta     beat_n
        clc
        adc     #SND_BEAT1
        jmp     sfx_snd
@r:     rts
BEAT_SLOW       = 18            ; frames between beats at the start of a wave
BEAT_FAST       = 6             ; ... at the quickest

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
        lda     hwspr
        beq     @fb
        ; with the terminal's sprites (fit.py): about 16 ms + 1.5 ms per
        ; row compared + 0.11 ms per byte, at 1 MHz
        lda     nrows_seen
        lsr
        adc     nrows_seen
        adc     #16
        adc     tmp
        bcs     @none
        jmp     @cp
@fb:
        ; the 6502's work, measured in the emulator (test/fit.py): about
        ; 0.39 ms per thing drawn + 1.3 ms per row compared + 0.12 ms per
        ; byte - 13 ms, at 1 MHz
        lda     npix            ; things drawn * 3 / 8
        sta     tmp2
        lda     npix+1
        lsr
        ror     tmp2
        lsr
        ror     tmp2
        lsr
        ror     tmp2
        lda     tmp2
        asl
        bcs     @none
        adc     tmp2
        bcs     @none
        adc     tmp             ; + bytes / 8
        bcs     @none
        adc     nrows_seen      ; + rows * 1.3
        bcs     @none
        sta     used
        lda     nrows_seen
        lsr
        lsr
        adc     used
        bcs     @none
        sec
        sbc     #13
        bcs     @cp
        lda     #0
@cp:
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
        lda     hwspr
        bne     pace_hw
        lda     speed           ; the rest of the frame time
        sec
        sbc     used
        bcc     @none
        beq     @none
        jmp     delay_ms
@none:  lda     hwspr
        beq     @r
        lda     #255
        sta     used
        jmp     pace_hw
@r:     rts

; with the terminal's sprites: half a frame time after this frame's SHOW
; (which came near the end of the work) the sprites move on by half their
; speed (mid_frame), so the ship, the saucer, the rocks and bullets the
; terminal draws move twice a frame, evenly.  used = ms taken so far.
pace_hw:
        lda     speed           ; first wait: half the frame time less the
        lsr                     ; work after the SHOW and before the next
        sec                     ; (the HUD, the half-way frame's own), but
        sbc     #MID_MS + 2     ; no more than leaves room for the rest
        sta     tmp3
        lda     speed
        sec
        sbc     used
        bcc     @w0
        sbc     #MID_MS
        bcs     @w1
@w0:    lda     #0
@w1:    cmp     tmp3
        bcc     @w2
        lda     tmp3
@w2:    sta     tmp3
        jsr     delay_ms        ; (0: none)
        lda     used
        clc
        adc     tmp3
        bcs     @r
        sta     used
        lda     nbytes          ; the half-way frame (bytes: serial time)
        sta     tmp4
        jsr     mid_frame
        lda     nbytes
        sec
        sbc     tmp4
        lsr                     ; bytes * 87 us ~ bytes / 16 + bytes / 32
        lsr
        lsr
        lsr
        sta     tmp4
        lsr
        adc     tmp4
        adc     #MID_MS         ; + its work
        adc     used
        bcs     @r
        sta     used
        lda     speed           ; and the rest
        sec
        sbc     used
        bcc     @r
        beq     @r
        jmp     delay_ms
@r:     rts


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

; ---- the ship ---------------------------------------------------------------------
spawn_ship:
        lda     #K_SHIP
        sta     o_kind+O_SHIP
        lda     #FW/2
        sta     o_x_hi+O_SHIP
        lda     #FH/2
        sta     o_y_hi+O_SHIP
        lda     #0
        sta     o_x_lo+O_SHIP
        sta     o_y_lo+O_SHIP
        sta     o_vx_lo+O_SHIP
        sta     o_vx_hi+O_SHIP
        sta     o_vy_lo+O_SHIP
        sta     o_vy_hi+O_SHIP
        sta     dead_t
        lda     #192            ; pointing up
        sta     sdir
        lda     #INVULN
        sta     inv_t
        rts

; turn, thrust, fire, hyperspace
ship_control:
        lda     o_kind+O_SHIP
        bne     @alive
        rts
@alive: lda     turn            ; turn: 8 = one of the 32 headings
        beq     @th
        clc
        adc     sdir
        sta     sdir
@th:    lda     #0
        sta     flame
        lda     thrust
        beq     @fr
        lda     #1
        sta     flame
        lda     sdir            ; v += (cos, sin) / 8
        lsr
        lsr
        lsr
        tay
        lda     sin_tab+8,y
        jsr     sext8
        jsr     sar3
        ldx     #O_SHIP
        jsr     add_vx
        lda     sin_tab,y
        jsr     sext8
        jsr     sar3
        ldx     #O_SHIP
        jsr     add_vy
        jsr     clamp_ship
@fr:    lda     fire_gap
        beq     @f2
        dec     fire_gap
@f2:    lda     fire
        beq     @hy
        lda     fire_gap
        bne     @hy
        jsr     fire_bullet
@hy:    lda     hyper
        beq     @fric
        jsr     rand            ; hyperspace: somewhere else at random
        cmp     #FW
        bcs     @fric
        sta     o_x_hi+O_SHIP
        lda     #SND_HYPER
        jsr     sfx_snd
@hr:    jsr     rand
        and     #$7F
        cmp     #FH
        bcs     @hr
        sta     o_y_hi+O_SHIP
        lda     #0
        sta     o_vx_lo+O_SHIP
        sta     o_vx_hi+O_SHIP
        sta     o_vy_lo+O_SHIP
        sta     o_vy_hi+O_SHIP
@fric:  ldx     #O_SHIP         ; friction: v -= v / 64
        jsr     friction
        rts

; w = A sign extended
sext8:  sta     w_lo            ; (preserves X and Y)
        cmp     #$80
        lda     #0
        bcc     @p
        lda     #$FF
@p:     sta     w_hi
        rts
; w = w / 8 (arithmetic)
sar3:   ldx     #3
@l:     lda     w_hi
        cmp     #$80
        ror     w_hi
        ror     w_lo
        dex
        bne     @l
        rts
add_vx: lda     o_vx_lo,x
        clc
        adc     w_lo
        sta     o_vx_lo,x
        lda     o_vx_hi,x
        adc     w_hi
        sta     o_vx_hi,x
        rts
add_vy: lda     o_vy_lo,x
        clc
        adc     w_lo
        sta     o_vy_lo,x
        lda     o_vy_hi,x
        adc     w_hi
        sta     o_vy_hi,x
        rts

; keep the ship's speed under 2 pixels a frame in each direction
clamp_ship:
        lda     o_vx_hi+O_SHIP
        jsr     @c
        sta     o_vx_hi+O_SHIP
        bcc     @y
        lda     #0
        sta     o_vx_lo+O_SHIP
@y:     lda     o_vy_hi+O_SHIP
        jsr     @c
        sta     o_vy_hi+O_SHIP
        bcc     @r
        lda     #0
        sta     o_vy_lo+O_SHIP
@r:     rts
@c:     bmi     @neg            ; A = high byte: clamp to -2 .. 1 (+ fraction)
        cmp     #2
        bcc     @ok
        lda     #1
        sec
        rts
@neg:   cmp     #$FE
        bcs     @ok
        lda     #$FE
        sec
        rts
@ok:    clc
        rts

; v -= v / 64 for object X
friction:
        lda     o_vx_lo,x
        sta     w_lo
        lda     o_vx_hi,x
        sta     w_hi
        jsr     sar6
        lda     o_vx_lo,x
        sec
        sbc     w_lo
        sta     o_vx_lo,x
        lda     o_vx_hi,x
        sbc     w_hi
        sta     o_vx_hi,x
        lda     o_vy_lo,x
        sta     w_lo
        lda     o_vy_hi,x
        sta     w_hi
        jsr     sar6
        lda     o_vy_lo,x
        sec
        sbc     w_lo
        sta     o_vy_lo,x
        lda     o_vy_hi,x
        sbc     w_hi
        sta     o_vy_hi,x
        rts
sar6:   ldy     #6
@l:     lda     w_hi
        cmp     #$80
        ror     w_hi
        ror     w_lo
        dey
        bne     @l
        lda     w_hi            ; (round towards zero: a tiny negative
        cmp     #$FF            ;  speed would never stop)
        bne     @r
        lda     w_lo
        cmp     #$FF
        bne     @r
        lda     #0
        sta     w_lo
        sta     w_hi
@r:     rts

fire_bullet:
        ldx     #O_BUL          ; a free bullet?
@f:     lda     o_kind,x
        beq     @got
        inx
        cpx     #O_BUL+NBUL
        bne     @f
        rts
@got:   lda     #SND_FIRE
        jsr     sfx_snd
        lda     #FIRE_GAP
        sta     fire_gap
        lda     #K_BUL
        sta     o_kind,x
        lda     #BUL_LIFE
        sta     o_t,x
        lda     sdir            ; from the nose, 2.5 pixels a frame + the ship's speed
        lsr
        lsr
        lsr
        tay
        lda     sin_tab+8,y     ; nose: 4 pixels out
        jsr     nose_ofs
        clc
        adc     o_x_hi+O_SHIP
        jsr     wrap_x
        sta     o_x_hi,x
        lda     sin_tab,y
        jsr     nose_ofs
        clc
        adc     o_y_hi+O_SHIP
        jsr     wrap_y
        sta     o_y_hi,x
        lda     #$80
        sta     o_x_lo,x
        sta     o_y_lo,x
        lda     sin_tab+8,y
        jsr     times5
        lda     w_lo
        clc
        adc     o_vx_lo+O_SHIP
        sta     o_vx_lo,x
        lda     w_hi
        adc     o_vx_hi+O_SHIP
        sta     o_vx_hi,x
        lda     sin_tab,y
        jsr     times5
        lda     w_lo
        clc
        adc     o_vy_lo+O_SHIP
        sta     o_vy_lo,x
        lda     w_hi
        adc     o_vy_hi+O_SHIP
        sta     o_vy_hi,x
        rts
; A = s.7 sine -> A = sine * 4 / 128 rounded (about -4..4)
nose_ofs:
        clc
        adc     #$80            ; 0..255 offset by 128
        lsr
        lsr
        lsr
        lsr
        lsr                     ; 0..7
        sec
        sbc     #4
        rts
; w = A (s.7) * 5 / 2  (a 2.5 pixels a frame speed component, 8.8)
times5: stx     t5x
        jsr     sext8
        lda     w_lo            ; w * 5
        sta     tmp
        lda     w_hi
        sta     tmp+1
        asl     w_lo
        rol     w_hi
        asl     w_lo
        rol     w_hi
        lda     w_lo
        clc
        adc     tmp
        sta     w_lo
        lda     w_hi
        adc     tmp+1
        sta     w_hi
        asl     w_lo            ; * 2: s.7 * 10 / 256 * 256 ... = 2.5 px at 127
        rol     w_hi
        ldx     t5x
        rts

; A = an x that may be off the field by a little -> back on it
wrap_x: cmp     #FW
        bcc     @r
        cmp     #FW + 48
        bcc     @hi
        clc
        adc     #FW
        rts
@hi:    sec
        sbc     #FW
@r:     rts
wrap_y: cmp     #FH
        bcc     @r
        cmp     #FH + 48
        bcc     @hi
        clc
        adc     #FH
        rts
@hi:    sec
        sbc     #FH
@r:     rts

; the ship blinks while it can't be hit; after a crash it comes back
ship_life:
        lda     inv_t
        beq     @d
        dec     inv_t
@d:     lda     o_kind+O_SHIP
        bne     @r
        lda     dead_t          ; waiting to come back
        beq     @r
        cmp     #1
        beq     @r              ; (1: stays, the game is over)
        dec     dead_t
        lda     dead_t
        cmp     #1
        bne     @r
        lda     lives
        beq     @r
        jsr     centre_clear    ; only into a clear space
        bcs     @wait
        jmp     spawn_ship
@wait:  lda     #2
        sta     dead_t
@r:     rts

; carry clear if no rock is near the middle
centre_clear:
        ldx     #O_ROCK
@l:     lda     o_kind,x
        cmp     #K_ROCK
        bne     @n
        lda     o_x_hi,x
        sec
        sbc     #FW/2
        jsr     absa
        cmp     #24
        bcs     @n
        lda     o_y_hi,x
        sec
        sbc     #FH/2
        jsr     absa
        cmp     #20
        bcs     @n
        sec
        rts
@n:     inx
        cpx     #O_ROCK+NROCK
        bne     @l
        clc
        rts

absa:   bpl     @r
        eor     #$FF
        clc
        adc     #1
@r:     rts

; ---- the saucer -------------------------------------------------------------------
; Now and then (while the ship is out) a saucer crosses the field from one
; side, drifting up and down, and shoots: the big one anywhere, the small one
; (from wave 3, or 10000 points) at the ship.
ufo_update:
        lda     o_kind+O_UFO
        cmp     #K_UFO
        beq     @on
        lda     o_kind+O_SHIP   ; none: count towards the next one
        beq     @r
        lda     frame
        and     #3
        bne     @r
        inc     ufo_wait
        lda     ufo_wait
        cmp     ufo_next
        bcc     @r
        jmp     ufo_start
@r:     rts
@on:    lda     frame           ; a new up / down drift now and then
        and     #31
        bne     @f
        jsr     rand
        and     #3
        tax
        lda     drift_lo,x
        sta     o_vy_lo+O_UFO
        lda     drift_hi,x
        sta     o_vy_hi+O_UFO
@f:     dec     ufo_fire
        bne     @r
        ldx     o_size+O_UFO
        lda     ufo_gap,x
        sta     ufo_fire
        jmp     ufo_shoot

ufo_start:
        lda     #0
        sta     ufo_wait
        jsr     rand            ; the next one in 64-127 x 4 frames
        and     #63
        ora     #64
        sta     ufo_next
        ldx     #0              ; big, or small?
        lda     score+2
        bne     @maybe          ; 10000 points or more
        lda     wave
        cmp     #3
        bcc     @size
@maybe: jsr     rand
        cmp     #110
        bcs     @size
        inx
@size:  stx     o_size+O_UFO
        lda     #K_UFO
        sta     o_kind+O_UFO
        txa
        clc
        adc     #SH_UFO_BIG
        sta     o_shape+O_UFO
        lda     ufo_life,x      ; frames to cross the field
        sta     o_t+O_UFO
        lda     ufo_gap,x
        sta     ufo_fire
        lda     ufo_spd,x       ; speed (fraction of a pixel a frame, or 1)
        sta     tmp2
        lda     #0
        sta     o_x_lo+O_UFO
        sta     o_y_lo+O_UFO
        sta     o_vy_lo+O_UFO
        sta     o_vy_hi+O_UFO
        jsr     rand            ; which side
        and     #1
        beq     @left
        lda     #FW-1           ; from the right, going left
        sta     o_x_hi+O_UFO
        lda     #0
        sec
        sbc     tmp2
        sta     o_vx_lo+O_UFO
        lda     #$FF
        ldx     tmp2
        bne     @vh
        lda     #$FF            ; (speed 1: -1.0)
@vh:    sta     o_vx_hi+O_UFO
        jmp     @y
@left:  lda     #0
        sta     o_x_hi+O_UFO
        lda     tmp2
        sta     o_vx_lo+O_UFO
        lda     #0
        ldx     tmp2
        bne     @vl
        lda     #1              ; (speed 1: +1.0)
@vl:    sta     o_vx_hi+O_UFO
@y:     jsr     rand            ; a height away from the very edges
        and     #$7F
        cmp     #FH-16
        bcs     @y
        adc     #8
        sta     o_y_hi+O_UFO
        rts

; the saucer fires a bullet: 2 pixels a frame for 30 frames
ufo_shoot:
        ldx     #O_EB
@f:     lda     o_kind,x
        beq     @got
        inx
        cpx     #O_EB+NEB
        bne     @f
        rts
@got:   stx     ebx
        lda     o_size+O_UFO    ; big: any way; small: at the ship
        beq     @rnd
        lda     o_kind+O_SHIP
        beq     @rnd
        jsr     aim
        sta     tmp2
        lda     wave            ; a little off before wave 6
        cmp     #6
        bcs     @dir
        jsr     rand
        and     #3
        sec
        sbc     #1              ; -1 .. 2 -> mostly -1 .. 1
        cmp     #2
        bne     @j
        lda     #0
@j:     clc
        adc     tmp2
        and     #NDIR-1
        jmp     @dir2
@rnd:   jsr     rand
        and     #NDIR-1
        jmp     @dir2
@dir:   lda     tmp2
@dir2:  tay
        ldx     ebx
        lda     #K_EBUL
        sta     o_kind,x
        lda     #30
        sta     o_t,x
        lda     o_x_hi+O_UFO
        sta     o_x_hi,x
        lda     o_y_hi+O_UFO
        sta     o_y_hi,x
        lda     #$80
        sta     o_x_lo,x
        sta     o_y_lo,x
        lda     sin_tab+8,y     ; v = (cos, sin) * 4 / 256 * 128 ~ 2 pixels
        jsr     times4
        sta     o_vx_lo,x
        lda     w_hi
        sta     o_vx_hi,x
        lda     sin_tab,y
        jsr     times4
        sta     o_vy_lo,x
        lda     w_hi
        sta     o_vy_hi,x
        rts
; A = s.7 -> A (lo), w_hi = A * 4 (sign extended).  Preserves X, Y.
times4: jsr     sext8
        asl     w_lo
        rol     w_hi
        asl     w_lo
        rol     w_hi
        lda     w_lo
        rts

; A = the heading (0-31) from the saucer that points nearest the ship: the
; one with the biggest dx * cos + dy * sin
aim:    lda     o_x_hi+O_SHIP   ; dx round the wrap, -80 .. 79
        sec
        sbc     o_x_hi+O_UFO
        bcs     @x1
        adc     #FW
@x1:    cmp     #FW/2
        bcc     @x2
        sbc     #FW
@x2:    sta     adx
        lda     o_y_hi+O_SHIP   ; dy, -46 .. 45
        sec
        sbc     o_y_hi+O_UFO
        bcs     @y1
        adc     #FH
@y1:    cmp     #FH/2
        bcc     @y2
        sbc     #FH
@y2:    sta     ady
        lda     #0
        sta     abest
        lda     #$80            ; best so far: the most negative
        sta     abv_hi
        lda     #0
        sta     abv_lo
        ldy     #NDIR-1
@d:     lda     sin_tab+8,y     ; dx * cos
        ldx     adx
        jsr     smul8
        lda     ml
        sta     adot_lo
        lda     mh
        sta     adot_hi
        lda     sin_tab,y       ; + dy * sin
        ldx     ady
        jsr     smul8
        lda     ml
        clc
        adc     adot_lo
        sta     adot_lo
        lda     mh
        adc     adot_hi
        sta     adot_hi
        lda     adot_lo         ; bigger than the best? (signed)
        cmp     abv_lo
        lda     adot_hi
        sbc     abv_hi
        bvc     @nv
        eor     #$80
@nv:    bmi     @nb
        lda     adot_lo
        sta     abv_lo
        lda     adot_hi
        sta     abv_hi
        sty     abest
@nb:    dey
        bpl     @d
        lda     abest
        rts

; mh:ml = A * X, both signed.  Preserves Y.
smul8:  sta     ma
        stx     ml
        eor     ml              ; the sign of the product
        sta     msign
        lda     ma
        bpl     @a
        eor     #$FF
        clc
        adc     #1
        sta     ma
@a:     lda     ml
        bpl     @b
        eor     #$FF
        clc
        adc     #1
        sta     ml
@b:     lda     #0              ; ma * ml, shift and add
        ldx     #8
        lsr     ml
@l:     bcc     @n
        clc
        adc     ma
@n:     ror
        ror     ml
        dex
        bne     @l
        sta     mh
        lda     msign
        bpl     @r
        lda     #0
        sec
        sbc     ml
        sta     ml
        lda     #0
        sbc     mh
        sta     mh
@r:     rts

; ---- moving everything ---------------------------------------------------------------
move_all:
        ldx     #NOBJ-1
@l:     lda     o_kind,x
        beq     @n
        cmp     #K_BUL          ; bullets and debris don't last
        bcc     @mv
        cmp     #K_ROCK
        beq     @mv
        dec     o_t,x
        bne     @mv
        lda     #K_NONE
        sta     o_kind,x
        jmp     @n
@mv:    lda     o_x_lo,x
        clc
        adc     o_vx_lo,x
        sta     o_x_lo,x
        lda     o_x_hi,x
        adc     o_vx_hi,x
        jsr     wrap_x
        sta     o_x_hi,x
        lda     o_y_lo,x
        clc
        adc     o_vy_lo,x
        sta     o_y_lo,x
        lda     o_y_hi,x
        adc     o_vy_hi,x
        jsr     wrap_y
        sta     o_y_hi,x
@n:     dex
        bpl     @l
        rts

; ---- hits ----------------------------------------------------------------------------
collide:
        ldx     #O_BUL          ; bullets against rocks
@b:     lda     o_kind,x
        cmp     #K_BUL
        bne     @bn
        stx     ci
        ldy     #O_ROCK
@r:     lda     o_kind,y
        cmp     #K_ROCK
        bne     @rn
        lda     o_size,y
        tax
        lda     rock_r,x
        clc
        adc     #1
        sta     hr
        ldx     ci
        jsr     near            ; X, Y within hr?
        bcs     @rn
        lda     #K_NONE         ; hit
        sta     o_kind,x
        sty     ri
        jsr     rock_hit
        ldx     ci
        jmp     @bn
@rn:    iny
        cpy     #O_ROCK+NROCK
        bne     @r
        ldx     ci
@bn:    inx
        cpx     #O_BUL+NBUL
        bne     @b
        ; the ship against rocks
        lda     o_kind+O_SHIP
        beq     @done
        lda     inv_t
        bne     @done
        ldy     #O_ROCK
@s:     lda     o_kind,y
        cmp     #K_ROCK
        bne     @sn
        lda     o_size,y
        tax
        lda     rock_r,x
        clc
        adc     #2
        sta     hr
        ldx     #O_SHIP
        jsr     near
        bcs     @sn
        sty     ri
        jsr     ship_hit
        ldy     ri
        jsr     rock_hit_y
        jmp     ufo_collide
@sn:    iny
        cpy     #O_ROCK+NROCK
        bne     @s
@done:  jmp     ufo_collide

; the saucer and its bullets
ufo_collide:
        lda     o_kind+O_UFO
        cmp     #K_UFO
        beq     *+5
        jmp     @eb
        ldx     o_size+O_UFO    ; its size for the hit box
        lda     ufo_hx,x
        sta     hr
        lda     ufo_hy,x
        sta     hry
        ldx     #O_BUL          ; the player's bullets
@b:     lda     o_kind,x
        cmp     #K_BUL
        bne     @bn
        ldy     #O_UFO
        jsr     near_xy
        bcs     @bn
        lda     #K_NONE
        sta     o_kind,x
        lda     #1              ; shot down: points
        jmp     ufo_down
@bn:    inx
        cpx     #O_BUL+NBUL
        bne     @b
        lda     o_kind+O_SHIP   ; the ship flies into it
        beq     @rk
        lda     inv_t
        bne     @rk
        inc     hr
        inc     hry
        ldx     #O_SHIP
        ldy     #O_UFO
        jsr     near_xy
        dec     hr
        dec     hry
        bcs     @rk
        jsr     ship_hit
        lda     #1
        jmp     ufo_down
@rk:    ldy     #O_ROCK         ; it flies into a rock
@r:     lda     o_kind,y
        cmp     #K_ROCK
        bne     @rn
        lda     o_size,y
        tax
        lda     rock_r,x
        clc
        adc     hr
        sta     hr2
        lda     rock_r,x
        clc
        adc     hry
        sta     hry2
        ldx     #O_UFO
        lda     hr
        pha
        lda     hry
        pha
        lda     hr2
        sta     hr
        lda     hry2
        sta     hry
        jsr     near_xy
        pla
        sta     hry
        pla
        sta     hr
        bcs     @rn
        sty     ri
        lda     #1
        sta     nopts
        jsr     rock_hit
        lda     #0
        sta     nopts
        lda     #0              ; no points for that
        jmp     ufo_down
@rn:    iny
        cpy     #O_ROCK+NROCK
        bne     @r
@eb:    lda     o_kind+O_SHIP   ; its bullets against the ship
        beq     @r2
        lda     inv_t
        bne     @r2
        lda     #3
        sta     hr
        sta     hry
        ldx     #O_EB
@e:     lda     o_kind,x
        cmp     #K_EBUL
        bne     @en
        ldy     #O_SHIP
        jsr     near_xy
        bcs     @en
        lda     #K_NONE
        sta     o_kind,x
        jmp     ship_hit
@en:    inx
        cpx     #O_EB+NEB
        bne     @e
@r2:    rts

; the saucer goes, in pieces; A = 1: the player gets the points
ufo_down:
        pha
        lda     #SND_BANG0
        jsr     sfx_snd
        lda     #K_NONE
        sta     o_kind+O_UFO
        lda     o_x_hi+O_UFO
        sta     sx
        lda     o_y_hi+O_UFO
        sta     sy
        lda     #8
        jsr     debris
        pla
        beq     @r
        ldx     o_size+O_UFO
        lda     #0
        ldy     ufo_pts_hi,x
        jsr     add_score
@r:     rts

; carry clear if objects X and Y are within hr pixels in x and hry in y
; (round the wrap).  Preserves X and Y.
near_xy:lda     o_x_hi,x
        sec
        sbc     o_x_hi,y
        jsr     wdist_x
        cmp     hr
        bcs     @no
        lda     o_y_hi,x
        sec
        sbc     o_y_hi,y
        jsr     wdist_y
        cmp     hry
        bcs     @no
        clc
        rts
@no:    sec
        rts

; carry clear if objects X and Y are within hr pixels in x and in y
; (taking the wrap-round into account).  Preserves X and Y.
near:   lda     o_x_hi,x
        sec
        sbc     o_x_hi,y
        jsr     wdist_x
        cmp     hr
        bcs     @no
        lda     o_y_hi,x
        sec
        sbc     o_y_hi,y
        jsr     wdist_y
        cmp     hr
        bcs     @no
        clc
        rts
@no:    sec
        rts
; A = a difference of two x's -> the distance round the field
wdist_x:bcs     @p              ; (carry from the subtraction: no borrow)
        eor     #$FF
        adc     #1
@p:     cmp     #FW/2
        bcc     @r
        sta     tmp
        lda     #FW
        sec
        sbc     tmp
@r:     rts
wdist_y:bcs     @p
        eor     #$FF
        adc     #1
@p:     cmp     #FH/2
        bcc     @r
        sta     tmp
        lda     #FH
        sec
        sbc     tmp
@r:     rts

rock_hit_y:
        sty     ri
; rock ri is hit: points, debris, and two smaller rocks (or none)
rock_hit:
        ldy     ri
        lda     o_size,y        ; a bang by its size
        clc
        adc     #SND_BANG0
        jsr     sfx_snd
        lda     o_size,y
        tax
        lda     nopts           ; (a rock the saucer hits scores nothing)
        bne     @np
        ldy     rock_pts_hi,x
        lda     rock_pts,x
        jsr     add_score
@np:
        ldy     ri
        lda     #K_NONE
        sta     o_kind,y
        lda     o_x_hi,y
        sta     sx
        lda     o_y_hi,y
        sta     sy
        lda     #4
        jsr     debris
        ldy     ri
        lda     o_size,y
        cmp     #2
        bcs     @r              ; the small ones just go
        clc
        adc     #1
        sta     tmp3
        lda     #2
        sta     tmp2
@two:   ldx     sx
        ldy     sy
        lda     tmp3
        jsr     add_rock_at
        dec     tmp2
        bne     @two
@r:     rts

ship_hit:
        lda     #SND_BOOM
        jsr     sfx_snd
        lda     #K_NONE
        sta     o_kind+O_SHIP
        lda     o_x_hi+O_SHIP
        sta     sx
        lda     o_y_hi+O_SHIP
        sta     sy
        lda     #12
        jsr     debris
        dec     lives
        lda     #RESPAWN_WAIT
        sta     dead_t
        lda     #1
        sta     hud_dirty
        rts

; A bits of debris flying out from sx, sy
debris: sta     tmp
@d:     ldx     #O_PART
@f:     lda     o_kind,x
        beq     @got
        inx
        cpx     #O_PART+NPART
        bne     @f
        rts
@got:   lda     #K_PART
        sta     o_kind,x
        jsr     rand
        and     #15
        clc
        adc     #10
        sta     o_t,x
        lda     sx
        sta     o_x_hi,x
        lda     sy
        sta     o_y_hi,x
        jsr     rand
        and     #NDIR-1
        tay
        jsr     rand
        and     #1
        sta     tmp2
        lda     sin_tab+8,y
        jsr     part_v
        sta     o_vx_lo,x
        lda     w_hi
        sta     o_vx_hi,x
        lda     sin_tab,y
        jsr     part_v
        sta     o_vy_lo,x
        lda     w_hi
        sta     o_vy_hi,x
        dec     tmp
        bne     @d
        rts
; A = s.7 -> A (lo) / w_hi = 0.5 or 1 pixel a frame in that direction
part_v: jsr     sext8
        lda     tmp2
        beq     @h
        asl     w_lo
        rol     w_hi
@h:     lda     w_lo
        rts

; add a rock of size A (0 big, 1, 2 small) at X, Y, going a random way
add_rock_at:
        sta     tmp3
        stx     sx
        sty     sy
        ldx     #O_ROCK
@f:     lda     o_kind,x
        beq     @got
        inx
        cpx     #O_ROCK+NROCK
        bne     @f
        rts
@got:   lda     #K_ROCK
        sta     o_kind,x
        lda     tmp3
        sta     o_size,x
        lda     sx
        sta     o_x_hi,x
        lda     sy
        sta     o_y_hi,x
        jsr     rand
        sta     o_x_lo,x
        jsr     rand
        sta     o_y_lo,x
        jsr     rand            ; one of 3 shapes
        and     #3
        cmp     #3
        bne     @s
        lda     #0
@s:     sta     tmp
        lda     tmp3            ; shape = SH_ROCK0_0 + size * 3 + variant
        asl
        adc     tmp3
        adc     tmp
        adc     #SH_ROCK0_0
        sta     o_shape,x
        jsr     rand            ; direction
        and     #NDIR-1
        tay
        lda     sin_tab+8,y
        jsr     rock_v
        sta     o_vx_lo,x
        lda     w_hi
        sta     o_vx_hi,x
        lda     sin_tab,y
        jsr     rock_v
        sta     o_vy_lo,x
        lda     w_hi
        sta     o_vy_hi,x
        rts
; A = s.7 (a sine) -> A (lo) / w_hi = a rock's speed in that direction:
; |sine| * k / 16 / 256 pixels a frame, k = 16 big (0.5 pixels a frame at
; most), 24 medium, 32 small, + 1 a wave (up to 8).  Preserves X and Y.
rock_v: sta     rv_s
        bpl     @p
        eor     #$FF
        clc
        adc     #1
@p:     sta     rv_a            ; |sine| (0..127)
        lda     wave
        cmp     #8
        bcc     @w
        lda     #8
@w:     sty     rv_y
        ldy     tmp3
        clc
        adc     rock_k,y
        sta     rv_k
        ldy     rv_y
        lda     #0              ; w = rv_a * rv_k (shift and add)
        sta     w_lo
        sta     w_hi
        lda     rv_a
        sta     rv_m
        lda     #0
        sta     rv_mh
@m:     lsr     rv_k
        bcc     @n
        lda     w_lo
        clc
        adc     rv_m
        sta     w_lo
        lda     w_hi
        adc     rv_mh
        sta     w_hi
@n:     asl     rv_m
        rol     rv_mh
        lda     rv_k
        bne     @m
        lsr     w_hi            ; / 16
        ror     w_lo
        lsr     w_hi
        ror     w_lo
        lsr     w_hi
        ror     w_lo
        lsr     w_hi
        ror     w_lo
        lda     rv_s            ; the sign back
        bpl     @r
        lda     #0
        sec
        sbc     w_lo
        sta     w_lo
        lda     #0
        sbc     w_hi
        sta     w_hi
@r:     lda     w_lo
        rts

; all the rocks gone: the next wave after a moment
wave_check:
        ldx     #O_ROCK
@l:     lda     o_kind,x
        cmp     #K_ROCK
        beq     @some
        inx
        cpx     #O_ROCK+NROCK
        bne     @l
        inc     wave_t
        lda     wave_t
        cmp     #40
        bcc     @r
        lda     #0
        sta     wave_t
        jsr     new_wave_rocks
@r:     rts
@some:  lda     #0
        sta     wave_t
        rts
new_wave_rocks:
        pla                     ; (new_wave sets up the rocks; return to the
        pla                     ;  game loop from there)
        pla
        pla
        jmp     new_wave

clear_objects:
        lda     #K_NONE
        ldx     #NOBJ-1
@l:     sta     o_kind,x
        dex
        bpl     @l
        rts

; ---- score ---------------------------------------------------------------------
; score += Y:A (BCD: Y the thousands and hundreds, A the tens and units);
; an extra ship every 10000
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
        lda     score+2         ; the 10000s changed: a ship
        cmp     tmp
        beq     @n
        lda     lives
        cmp     #9
        bcs     @n
        inc     lives
        lda     #SND_LIFE
        jsr     sfx_snd
@n:     lda     #1
        sta     hud_dirty
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
        lda     wave
        ldx     #'0'
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
@nohi:  lda     hwspr           ; (the sprites off the box)
        beq     @ns
        lda     #<hideall_txt
        ldy     #>hideall_txt
        jsr     print
        jsr     spr_forget
@ns:    jsr     sfx_off
        lda     #SND_OVER
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
; drawing
; ============================================================================
; clear what was drawn last time, draw everything, send the changes
frame_draw:
        lda     hwspr
        beq     @fb0
        jsr     ask_wait        ; the terminal has drawn the last frame
        lda     #<hold_txt
        ldy     #>hold_txt
        jsr     print
        jsr     spr_assign      ; which objects the terminal draws
        lda     frame           ; every 64 frames (~3.5 s): all of them again
        and     #63
        bne     @fb0
        jsr     spr_refresh
@fb0:   ldx     #FROWS-1        ; blocks drawn on last frame: clear them
@c:     lda     rd_lo,x
        sta     rp_lo,x
        lda     rd_hi,x
        sta     rp_hi,x
        ora     rd_lo,x
        beq     @cn
        lda     fbrow_lo,x
        sta     @w+1
        lda     fbrow_hi,x
        sta     @w+2
        stx     tmp4
        ldy     #0              ; block (8 columns)
@b:     cpy     #8
        bcs     @bh
        lda     rd_lo,x
        and     blkbit,y
        jmp     @bt
@bh:    lda     rd_hi,x
        and     blkbit,y
@bt:    beq     @bn
        sty     tmp2
        tya
        asl
        asl
        asl
        tax                     ; its first column
        lda     #0
        ldy     #8
@w:     sta     $FFFF,x
        inx
        dey
        bne     @w
        ldy     tmp2
        ldx     tmp4
@bn:    iny
        cpy     #10
        bne     @b
        lda     #0
        sta     rd_lo,x
        sta     rd_hi,x
@cn:    dex
        bpl     @c
        ldx     #NOBJ-1         ; draw the objects
@o:     stx     di
        lda     o_kind,x
        beq     @on
        cmp     #K_SHIP
        beq     @ship
        ldy     o_sl,x          ; (a sprite: the terminal draws it)
        bne     @on
        cmp     #K_ROCK
        beq     @rock
        cmp     #K_UFO
        beq     @ufo
        lda     o_x_hi,x        ; a bullet or debris: one pixel
        sta     px
        lda     o_y_hi,x
        sta     py
        jsr     plot
        jmp     @on
@rock:  jsr     draw_rock
        jmp     @on
@ufo:   lda     o_x_hi,x
        sta     ox
        lda     o_y_hi,x
        sta     oy
        lda     o_shape,x
        jsr     draw_shape
        jmp     @on
@ship:  lda     inv_t           ; blinking while it can't be hit
        and     #4
        bne     @on
        lda     o_x_hi,x
        sta     ox
        lda     o_y_hi,x
        sta     oy
        lda     o_sl,x          ; (a sprite: only the flame here)
        bne     @flm
        lda     sdir
        lsr
        lsr
        lsr
        jsr     draw_shape      ; (SH_SHIP0 = 0)
@flm:   lda     flame
        beq     @on
        lda     frame           ; the flame flickers
        and     #1
        beq     @on
        lda     sdir
        lsr
        lsr
        lsr
        clc
        adc     #SH_FLAME0
        jsr     draw_shape
@on:    ldx     di
        dex
        bmi     *+5
        jmp     @o
        jsr     present
        lda     hwspr
        beq     @r
        jsr     spr_send        ; the sprites' changes, then SHOW
        lda     #<show_txt
        ldy     #>show_txt
        jsr     print
        jmp     ask_send
@r:     rts

; draw rock X from its pre-rendered characters (gen.py): a list of
; (column + 8, row + 4, character) for the way it sits in its cell.  The
; field is exactly 80 x 23 characters, so wrapping round works by whole
; characters.
draw_rock:
        lda     o_x_hi,x
        lsr
        sta     rcol            ; its character column
        lda     #0
        rol
        sta     tmp4            ; x & 1
        lda     o_y_hi,x
        and     #3
        asl
        ora     tmp4
        sta     tmp4            ; the alignment, 0-7
        lda     o_y_hi,x
        lsr
        lsr
        sta     rrow
        lda     o_shape,x
        sec
        sbc     #SH_ROCK0_0
        asl
        asl
        asl
        ora     tmp4
        tay
        lda     rk_lo,y
        clc
        adc     #<rk_data
        sta     @p1+1
        sta     @p2+1
        sta     @p3+1
        lda     rk_hi,y
        adc     #>rk_data
        sta     @p1+2
        sta     @p2+2
        sta     @p3+2
        ldy     #0
@l:
@p1:    lda     $FFFF,y         ; column
        cmp     #$FF
        beq     @done
        inc     npix
        clc
        adc     rcol
        sec
        sbc     #8
        bcs     @c1
        adc     #COLS           ; (off the left: round to the right)
        jmp     @cok
@c1:    cmp     #COLS
        bcc     @cok
        sbc     #COLS
@cok:   sta     rcc
        iny
@p2:    lda     $FFFF,y         ; row
        clc
        adc     rrow
        sec
        sbc     #4
        bcs     @r1
        adc     #FROWS
        jmp     @rok
@r1:    cmp     #FROWS
        bcc     @rok
        sbc     #FROWS
@rok:   tax
        iny
        lda     fbrow_lo,x
        clc
        adc     rcc
        sta     @o+1
        sta     @w+1
        lda     fbrow_hi,x
        adc     #0
        sta     @o+2
        sta     @w+2
        sty     rky
        lda     rcc             ; mark its block
        lsr
        lsr
        lsr
        tay
        lda     blkbit,y
        cpy     #8
        bcs     @bh
        ora     rd_lo,x
        sta     rd_lo,x
        jmp     @bd
@bh:    ora     rd_hi,x
        sta     rd_hi,x
@bd:    ldy     rky
@p3:    lda     $FFFF,y         ; the character
@o:     ora     $FFFF
@w:     sta     $FFFF
        iny
        beq     *+5
        jmp     @l
@done:  rts

; draw shape A at ox, oy (its pixels wrap round the edges)
draw_shape:
        tax
        lda     shp_lo,x
        clc
        adc     #<shp_dx
        sta     @dx+1
        lda     shp_hi,x
        adc     #>shp_dx
        sta     @dx+2
        lda     shp_lo,x
        clc
        adc     #<shp_dy
        sta     @dy+1
        lda     shp_hi,x
        adc     #>shp_dy
        sta     @dy+2
        ldy     #0
@l:
@dx:    lda     $FFFF,y         ; dx + 8
        cmp     #$FF
        beq     @done
        clc
        adc     ox
        sec
        sbc     #8
        bcs     @x1
        adc     #FW             ; (was < 0)
        jmp     @xok
@x1:    cmp     #FW
        bcc     @xok
        sbc     #FW
@xok:   sta     px
@dy:    lda     $FFFF,y         ; dy + 8
        clc
        adc     oy
        sec
        sbc     #8
        bcs     @y1
        adc     #FH
        jmp     @yok
@y1:    cmp     #FH
        bcc     @yok
        sbc     #FH
@yok:   sta     py
        sty     shp_i
        jsr     plot
        ldy     shp_i
        iny
        bne     @l
@done:  rts

; set pixel px, py of the field in fb, and note its row
plot:   inc     npix
        bne     @c
        inc     npix+1
@c:     lda     py
        lsr
        lsr
        tay
        lda     px              ; mark its block of 8 columns (16 pixels)
        lsr
        lsr
        lsr
        lsr
        tax
        lda     blkbit,x
        cpx     #8
        bcs     @bh
        ora     rd_lo,y
        sta     rd_lo,y
        jmp     @bd
@bh:    ora     rd_hi,y
        sta     rd_hi,y
@bd:    lda     px
        lsr
        clc
        adc     fbrow_lo,y
        sta     @rd+1
        sta     @wr+1
        lda     fbrow_hi,y
        adc     #0
        sta     @rd+2
        sta     @wr+2
        lda     py
        and     #3
        asl
        sta     tmp4
        lda     px
        and     #1
        ora     tmp4
        tay
        lda     bitmask,y
@rd:    ora     $FFFF
@wr:    sta     $FFFF
        rts


; ============================================================================
; the terminal's sprite layer (control code 1C), when it has one
; ============================================================================
; The ship (slot 15, on top), the saucer (14) and up to 14 rocks (0-13, the
; big ones first) are the terminal's sprites, as long as they are wholly in
; the field; the rest (bullets, debris, the flame, more rocks, and anything
; going over an edge, which wraps round) is drawn in fb as before.  Each
; frame spr_assign chooses them (o_sl: slot + 1) and sets where each slot
; should be (des_*); spr_send sends only what changed (MOVE, PICTURE, PLACE,
; HIDE) between HOLD and SHOW.  Half way through the frame time mid_frame
; moves them on by half their speed, so they move twice a frame.  After each
; of these IDENTIFY goes out, and the next waits for its answer (pacing).
NSLOT           = 16
SL_SHIP         = 15
SL_UFO          = 14
NRSL            = 14            ; slots for rocks
ASK_MS          = 150           ; (the most to wait for the terminal: then go on)
MID_MS          = 5 / CLOCK_MHZ + 1     ; the half-way frame's work, ms

; at start: IDENTIFY, and if it answers, the pictures (SPR_DEFS bytes)
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
        rts                     ; no answer: the game draws everything
@c:     cmp     #'S'
        beq     @yes
        cmp     #'P'
        beq     @yes
        cmp     #'1'
        bne     @w1
@yes:   lda     #1
        sta     hwspr
        lda     #20             ; (the rest of the answer)
        jsr     delay_ms
        jsr     flush_in
        lda     #<spr_defs
        sta     @ld+1
        lda     #>spr_defs
        sta     @ld+2
        lda     #<SPR_DEFS
        sta     rp_cnt
        lda     #>SPR_DEFS
        sta     rp_cnt+1
@ld:    lda     $FFFF
        jsr     SBC_CHROUT
        inc     @ld+1
        bne     @n
        inc     @ld+2
@n:     lda     rp_cnt
        bne     @d
        dec     rp_cnt+1
@d:     dec     rp_cnt
        lda     rp_cnt
        ora     rp_cnt+1
        bne     @ld
        rts

; the screen was cleared (that hid the sprites): none show
spr_forget:
        lda     #0              ; (nothing to wait for)
        sta     rp_out
        sta     rp_in
        ldx     #NSLOT-1
        lda     #0
@f:     sta     sl_on,x
        sta     sl_obj,x
        sta     des_on,x
        dex
        bpl     @f
        ldx     #NOBJ-1
@o:     sta     o_sl,x
        dex
        bpl     @o
        rts

; ---- pacing: IDENTIFY after each update; the next waits for the answer ----
ask_send:
        inc     rp_out
        lda     #<ident_txt
        ldy     #>ident_txt
        jmp     print

ask_wait:
        lda     #ASK_MS
        sta     rp_t
@chk:   lda     rp_out          ; all answered?
        beq     @r
        jsr     getc
        bcc     @none
        jsr     handle_key      ; (a key meanwhile)
        jmp     @chk
@none:  lda     #1
        jsr     delay_ms
        dec     rp_t
        bne     @chk
        lda     #0              ; no answer: lost; go on, counting afresh
        sta     rp_out
        sta     rp_in
@r:     rts

; any answers (or keys) waiting now, without waiting for more
ask_poll:
        jsr     getc
        bcc     @r
        jsr     handle_key
        jmp     ask_poll
@r:     rts

; pos_x, pos_y = where object X will be half a frame on (not wrapped round)
half_pos:
        lda     o_vx_hi,x       ; speed / 2
        cmp     #$80
        ror
        sta     hv_hi
        lda     o_vx_lo,x
        ror
        clc
        adc     o_x_lo,x
        lda     o_x_hi,x
        adc     hv_hi
        sta     pos_x
        lda     o_vy_hi,x
        cmp     #$80
        ror
        sta     hv_hi
        lda     o_vy_lo,x
        ror
        clc
        adc     o_y_lo,x
        lda     o_y_hi,x
        adc     hv_hi
        sta     pos_y
        rts

; slot Y should show picture hp_n at hp_x, hp_y
set_des:
        lda     #1
        sta     des_on,y
        lda     hp_n
        sta     des_n,y
        lda     hp_x
        sta     des_x,y
        lda     hp_y
        sta     des_y,y
        rts

; Object X with picture hp_n: where its sprite goes, on the wire (+ 32; the
; field starts at sprite row 4): hp_x, hp_y.  A (and cl_need) = how many slots
; it needs: 1 wholly in the field; 2 over one edge (the second, cp_x, cp_y,
; is the part that wraps round to the other side); 0 over two edges (a
; corner: drawn in fb).  Preserves X.
classify:
        ldy     hp_n
        lda     o_x_hi,x        ; x - ox + 32: 26 .. 191
        sec
        sbc     pic_ox,y
        clc
        adc     #32
        sta     hp_x
        sta     cp_x
        lda     o_y_hi,x        ; y - oy + 36: 30 .. 127
        sec
        sbc     pic_oy,y
        clc
        adc     #36
        sta     hp_y
        sta     cp_y
        lda     #1
        sta     cl_need
        lda     hp_x            ; over the left edge?
        cmp     #32
        bcs     @xr
        adc     #FW
        sta     cp_x
        inc     cl_need
        bne     @y
@xr:    clc                     ; ... or the right?
        adc     pic_w,y
        cmp     #32+FW+1
        bcc     @y
        lda     hp_x
        sbc     #FW             ; (carry set)
        sta     cp_x
        inc     cl_need
@y:     lda     hp_y            ; over the top?
        cmp     #36
        bcs     @yb
        adc     #FH
        sta     cp_y
        inc     cl_need
        bne     @e
@yb:    clc                     ; ... or the bottom?
        adc     pic_h,y
        cmp     #36+FH+1
        bcc     @e
        lda     hp_y
        sbc     #FH
        sta     cp_y
        inc     cl_need
@e:     lda     cl_need
        cmp     #3
        bcc     @r
        lda     #0              ; (a corner)
        sta     cl_need
@r:     rts

; the picture of object X (a rock, the saucer or a bullet) -> hp_n
obj_pic:
        lda     o_kind,x
        cmp     #K_BUL
        beq     @dot
        cmp     #K_EBUL
        beq     @dot
        lda     o_shape,x       ; rocks and the saucer
        sec
        sbc     #SH_ROCK0_0 - PIC_ROCK
        sta     hp_n
        rts
@dot:   lda     #PIC_DOT
        sta     hp_n
        rts

; which objects are sprites this frame (o_sl), and where the slots should be
; (des_*).  The ship has slot 15 and the saucer 14 while they are wholly in
; the field.  Slots 0-13 go to the rocks (big ones first) and then the
; bullets; a rock over an edge has two (sl_part 1: the part round the other
; side).  A thing keeps its slots while it can.
spr_assign:
        ldx     #NOBJ-1
        lda     #0
@c:     sta     o_sl,x
        sta     o_have,x
        dex
        bpl     @c
        ldx     #NSLOT-1
@d:     sta     des_on,x
        dex
        bpl     @d
        ldx     #O_SHIP         ; the ship
        lda     o_kind,x
        cmp     #K_SHIP
        bne     @nship
        lda     sdir
        lsr
        lsr
        lsr
        sta     hp_n
        jsr     classify
        cmp     #1
        bne     @nship
        lda     #1
        sta     o_sl+O_SHIP
        lda     inv_t           ; (blinking: not this frame)
        and     #4
        bne     @nship
        ldy     #SL_SHIP
        jsr     set_des
@nship: ldx     #O_UFO          ; the saucer
        lda     o_kind,x
        cmp     #K_UFO
        bne     @nufo
        jsr     obj_pic
        jsr     classify
        cmp     #1
        bne     @nufo
        lda     #1
        sta     o_sl+O_UFO
        ldy     #SL_UFO
        jsr     set_des
@nufo:  ldy     #NRSL-1         ; slots kept by what still needs them
@k:     sty     hs_i
        lda     sl_obj,y
        beq     @kn
        tax
        dex
        lda     o_kind,x
        cmp     #K_ROCK
        beq     @kr
        cmp     #K_BUL
        beq     @kr
        cmp     #K_EBUL
        bne     @kfree
@kr:    jsr     obj_pic
        jsr     classify
        ldy     hs_i
        lda     sl_part,y       ; the main part: needs 1 or 2; the other: 2
        clc
        adc     #1
        cmp     cl_need
        beq     @keep
        bcs     @kfree
        lda     sl_part,y
        beq     @keep
        bne     @kfree
@keep:  lda     sl_part,y       ; (o_have bit 0: the main part, bit 1: the other)
        tay
        lda     bit01,y
        ora     o_have,x
        sta     o_have,x
        jmp     @kn
@kfree: ldy     hs_i
        lda     #0
        sta     sl_obj,y
@kn:    ldy     hs_i
        dey
        bpl     @k
        lda     #0              ; then the free slots: rocks big first, bullets
        sta     hp_sz
@sz:    ldx     #O_ROCK
        lda     hp_sz
        cmp     #3
        bcc     @r
        ldx     #O_BUL
@r:     lda     o_kind,x
        cmp     #K_ROCK
        bne     @nr
        lda     o_size,x
        cmp     hp_sz
        beq     @go
        bne     @rn
@nr:    ldy     hp_sz           ; (bullets in the last round)
        cpy     #3
        bne     @rn
        cmp     #K_BUL
        beq     @go
        cmp     #K_EBUL
        bne     @rn
@go:    jsr     obj_pic
        jsr     classify
        lda     cl_need
        beq     @drop           ; (a corner: fb)
        lda     o_have,x        ; slots still wanted: need - have
        tay
        lda     cl_need
        sec
        sbc     have_n,y
        beq     @rn             ; (it has them)
        sta     tmp3
        ldy     #NRSL-1         ; free slots enough?
        lda     #0
        sta     tmp2
@cf:    lda     sl_obj,y
        bne     @cn
        inc     tmp2
@cn:    dey
        bpl     @cf
        lda     tmp2
        cmp     tmp3
        bcc     @drop           ; no: fb (and the slots it has go)
        ldy     #NRSL-1         ; take them
@tk:    lda     sl_obj,y
        bne     @tn
        lda     o_have,x        ; the main part first, then the other
        and     #1
        sta     sl_part,y
        lda     o_have,x
        lsr
        lda     o_have,x
        bcs     @t2
        ora     #1
        bne     @t3
@t2:    ora     #2
@t3:    sta     o_have,x
        txa
        clc
        adc     #1
        sta     sl_obj,y
        dec     tmp3
        beq     @rn
@tn:    dey
        bpl     @tk
        bmi     @rn
@drop:  jsr     free_obj
@rn:    inx
        lda     hp_sz
        cmp     #3
        bcs     @bl
        cpx     #O_ROCK+NROCK
        beq     *+5
        jmp     @r
        inc     hp_sz
        jmp     @sz
@bl:    cpx     #O_BUL+NBUL     ; bullets: 1-4, then 46-47
        bne     @b2
        ldx     #O_EB
@b2:    cpx     #O_EB+NEB
        beq     @set
        jmp     @r
@set:   ldy     #NRSL-1         ; where the slots go; o_sl for what has them all
@s:     sty     hs_i
        lda     sl_obj,y
        beq     @sn
        tax
        dex
        jsr     obj_pic
        jsr     classify
        ldy     hs_i
        lda     sl_part,y
        beq     @sm
        lda     cp_x            ; (the part round the other side)
        sta     hp_x
        lda     cp_y
        sta     hp_y
@sm:    jsr     set_des
        lda     #1
        sta     o_sl,x
@sn:    ldy     hs_i
        dey
        bpl     @s
        rts

; object X can't be all sprites: free its slots (it is drawn in fb)
free_obj:
        stx     tmp4
        inc     tmp4
        ldy     #NRSL-1
@f:     lda     sl_obj,y
        cmp     tmp4
        bne     @n
        lda     #0
        sta     sl_obj,y
@n:     dey
        bpl     @f
        lda     #0
        sta     o_have,x
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
        lda     #4              ; PICTURE
        jsr     spr_cmd
        lda     des_n,x
        jsr     putc
@samen: lda     des_x,x
        cmp     sl_x,x
        bne     @move
        lda     des_y,x
        cmp     sl_y,x
        beq     @keep
@move:  lda     #3              ; MOVE
        jsr     spr_cmd
        lda     des_x,x
        jsr     putc
        lda     des_y,x
        jsr     putc
        jmp     @keep
@place: lda     #2              ; PLACE
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
        lda     #6              ; HIDE
        jsr     spr_cmd
@n:     ldx     hs_i
        dex
        bmi     *+5
        jmp     @l
        rts

; all the sprites again, whole (CLIP, HIDE ALL, then a PLACE for each): if
; the terminal ever lost them (a byte dropped in a command, a clear screen),
; they are back within a few seconds.  Called between HOLD and SHOW.
spr_refresh:
        lda     #<clip_txt
        ldy     #>clip_txt
        jsr     print
        lda     #<hideall_txt
        ldy     #>hideall_txt
        jsr     print
        ldx     #NSLOT-1
        lda     #0
@l:     sta     sl_on,x
        dex
        bpl     @l
        rts

; send 1C, command A, slot hs_i.  X = hs_i after.
spr_cmd:pha
        lda     #$1C
        jsr     putc
        pla
        jsr     putc
        lda     hs_i
        jsr     putc
        ldx     hs_i
        rts

; half way through the frame: each sprite moves on by half its thing's speed
mid_frame:
        jsr     ask_poll        ; the terminal still busy with the frame: no
        lda     rp_out          ;  half-way update this time (it would only
        beq     @go             ;  fall further behind)
        rts
@go:    lda     #<hold_txt
        ldy     #>hold_txt
        jsr     print
        ldx     #NSLOT-1
@l:     stx     hs_i
        lda     des_on,x
        beq     @n
        lda     #O_SHIP         ; its object
        cpx     #SL_SHIP
        beq     @o
        lda     #O_UFO
        cpx     #SL_UFO
        beq     @o
        lda     sl_obj,x
        sec
        sbc     #1
@o:     tax
        jsr     half_pos
        ldy     hs_i
        lda     pos_x           ; + (half way - now)
        sec
        sbc     o_x_hi,x
        clc
        adc     des_x,y
        sta     des_x,y
        lda     pos_y
        sec
        sbc     o_y_hi,x
        clc
        adc     des_y,y
        sta     des_y,y
@n:     ldx     hs_i
        dex
        bpl     @l
        jsr     spr_send
        lda     #<show_txt
        ldy     #>show_txt
        jsr     print
        jmp     ask_send

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
        sta     fire
        sta     hyper
        sta     turn
        sta     thrust
        lda     ctrl
        beq     @keys
        jsr     read_pad
        lda     pad
        and     #PAD_LEFT
        beq     @r
        lda     #<-TURN_STEP
        sta     turn
@r:     lda     pad
        and     #PAD_RIGHT
        beq     @u
        lda     #TURN_STEP
        sta     turn
@u:     lda     pad
        and     #PAD_UP
        beq     @a
        lda     #1
        sta     thrust
@a:     lda     padnew
        and     #PAD_A
        beq     @b
        lda     #1
        sta     fire
@b:     lda     padnew
        and     #PAD_B | PAD_DOWN
        beq     @st
        lda     #1
        sta     hyper
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
        lda     turn_hold
        beq     @th
        dec     turn_hold
        lda     turn_dir
        sta     turn
@th:    lda     thr_hold
        beq     @done
        dec     thr_hold
        lda     #1
        sta     thrust
@done:  rts
TURN_STEP       = 8             ; one of the 32 headings a frame

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
        beq     @thr
        cmp     #'B'
        beq     @hyp
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
        beq     @thr
        cmp     #'S'
        beq     @hyp
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
@left:  lda     #<-TURN_STEP
        bne     @turn
@right: lda     #TURN_STEP
@turn:  sta     turn_dir
        ldx     turn_hold       ; (a fresh press turns at once)
        bne     @th
        sta     turn
@th:    lda     #HOLD_TURN
        sta     turn_hold
        rts
@thr:   lda     #HOLD_THRUST
        sta     thr_hold
        rts
@hyp:   lda     #1
        sta     hyper
        rts
@fire:  lda     #1
        sta     fire
        rts
@pause: jmp     pause
@quit:  lda     #1
        sta     quit
        rts
HOLD_TURN       = 2
HOLD_THRUST     = 4

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
; data
; ============================================================================
        .segment "RODATA"
bitmask:.byte   $01, $02, $04, $08, $10, $20, $40, $80
blkbit: .byte   $01, $02, $04, $08, $10, $20, $40, $80, $01, $02
rock_pts:.byte  $20, $50, $00   ; BCD: 20, 50, 100
rock_pts_hi:.byte $00, $00, $01
rock_k: .byte   16, 24, 32      ; rock speeds by size (see rock_v)
; the saucers: big, small
ufo_hx: .byte   6, 4            ; hit box: half width, half height
ufo_hy: .byte   3, 2
ufo_pts_hi:.byte $02, $10       ; points (BCD hundreds): 200, 1000
ufo_spd:.byte   $C0, $00        ; speed: 0.75, 1 pixel a frame
ufo_life:.byte  213, 160        ; frames to cross the field
ufo_gap:.byte   40, 30          ; frames between shots
drift_lo:.byte  $80, $00, $80, $00  ; up 0.5, none, down 0.5, none
drift_hi:.byte  $FF, $00, $00, $00
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
deco_x: .byte   12, 148, 10, 150, 14
deco_y: .byte   16, 36, 60, 72, 82
deco_s: .byte   0, 0, 1, 1, 2
NDECO = 5

cls_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, 0, TERM
title_txt:
        .byte   TC_ROW, 3, TC_COL, 34, RV_ON, " SPACE ROCKS ", RV_OFF
        .byte   TC_ROW, 6, TC_COL, 22, "SHOOT THE ROCKS BEFORE THEY HIT YOU"
        .byte   TC_ROW, 9, TC_COL, 12, "KEYS: A/D TURN   W THRUST   SPACE FIRE   S HYPERSPACE"
        .byte   TC_ROW, 10, TC_COL, 12, "      (OR THE ARROW KEYS)   P PAUSE   M SOUND   Q QUIT"
        .byte   TC_ROW, 12, TC_COL, 12, "PAD:  LEFT/RIGHT TURN   UP THRUST   A FIRE   B HYPERSPACE"
        .byte   TC_ROW, 13, TC_COL, 12, "      START PAUSE"
        .byte   TC_ROW, 15, TC_COL, 14, "ROCKS: BIG 20  MEDIUM 50  SMALL 100    SAUCERS: 200, 1000"
        .byte   TC_ROW, 16, TC_COL, 30, "A SHIP EVERY 10000"
        .byte   TC_ROW, 23, TC_COL, 21, "SPACE OR START: PLAY      Q: QUIT", TERM
hi_txt: .byte   "HIGH SCORE ", TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "SCORE"
        .byte   TC_COL, 19, "HIGH"
        .byte   TC_COL, 39, "SHIPS"
        .byte   TC_COL, 54, "WAVE", TERM
bit01:  .byte   1, 2
have_n: .byte   0, 1, 1, 2
ident_txt:
        .byte   $1C, $0C, TERM  ; IDENTIFY (the answer: S P 1)
hold_txt:
        .byte   $1C, $09, TERM
show_txt:
        .byte   $1C, $0A, TERM
hideall_txt:
        .byte   $1C, $07, TERM
clip_txt:                       ; sprites only in the field: text rows 1-23
        .byte   $1C, $0B, 1, 23, TERM
paused_txt:
        .byte   RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   "        ", TERM
over_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 10, TC_COL, 31, RV_ON, "                  "
        .byte   TC_ROW, 11, TC_COL, 31, "    GAME  OVER    "
        .byte   TC_ROW, 12, TC_COL, 31, "                  "
        .byte   TC_ROW, 13, TC_COL, 31, " SPACE/A: AGAIN   "
        .byte   TC_ROW, 14, TC_COL, 31, " Q: TITLE         "
        .byte   TC_ROW, 15, TC_COL, 31, "                  ", RV_OFF, TERM
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
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
lives:      .res 1
wave:       .res 1
wave_t:     .res 1
beat_t:     .res 1              ; frames to the next heartbeat
beat_gap:   .res 1              ; ... and between beats now
beat_n:     .res 1              ; which of its two notes
ufo_hum:    .res 1              ; the saucer's hum is on
hud_dirty:  .res 1
sdir:       .res 1              ; the ship's heading, 0-255 (8 per heading)
inv_t:      .res 1              ; frames it can't be hit
dead_t:     .res 1              ; frames until it comes back (1 = not again)
flame:      .res 1
fire_gap:   .res 1
fire:       .res 1              ; this frame's controls
hyper:      .res 1
turn:       .res 1
thrust:     .res 1
turn_dir:   .res 1
turn_hold:  .res 1
thr_hold:   .res 1
o_kind:     .res NOBJ
o_x_lo:     .res NOBJ
o_x_hi:     .res NOBJ
o_y_lo:     .res NOBJ
o_y_hi:     .res NOBJ
o_vx_lo:    .res NOBJ
o_vx_hi:    .res NOBJ
o_vy_lo:    .res NOBJ
o_vy_hi:    .res NOBJ
o_t:        .res NOBJ           ; frames left (bullets, debris)
o_sl:       .res NOBJ           ; the terminal draws it: its sprite slot + 1
hwspr:      .res 1              ; the terminal has sprites (1C)
rp_out:     .res 1              ; IDENTIFYs not answered yet (S P 1 are answers)
rp_in:      .res 1              ; in an answer (its S or P came, not its 1)
rp_t:       .res 1
rp_cnt:     .res 2
sl_obj:     .res NSLOT          ; rock slots: the object + 1
des_on:     .res NSLOT          ; the slots as they should be ...
des_n:      .res NSLOT
des_x:      .res NSLOT
des_y:      .res NSLOT
sl_on:      .res NSLOT          ; ... and as the terminal shows them
sl_n:       .res NSLOT
sl_x:       .res NSLOT
sl_y:       .res NSLOT
hs_i:       .res 1
hp_n:       .res 1
hp_x:       .res 1
hp_y:       .res 1
hp_sz:      .res 1
pos_x:      .res 1
pos_y:      .res 1
hv_hi:      .res 1
o_have:     .res NOBJ           ; (spr_assign: its slots, bit 0 main, 1 other)
sl_part:    .res NSLOT          ; 1: the part of a rock round the other side
cp_x:       .res 1
cp_y:       .res 1
cl_need:    .res 1
o_size:     .res NOBJ           ; rocks: 0 big .. 2 small
o_shape:    .res NOBJ
w_lo:       .res 1
w_hi:       .res 1
t5x:        .res 1
t5h:        .res 1
rv_s:       .res 1
rv_a:       .res 1
rv_k:       .res 1
rv_m:       .res 1
rv_mh:      .res 1
rv_y:       .res 1
hry:        .res 1
hr2:        .res 1
hry2:       .res 1
nopts:      .res 1
ufo_wait:   .res 1              ; counts (every 4 frames) to the next saucer
ufo_next:   .res 1
ufo_fire:   .res 1              ; frames to its next shot
ebx:        .res 1
adx:        .res 1
ady:        .res 1
abest:      .res 1
abv_lo:     .res 1
abv_hi:     .res 1
adot_lo:    .res 1
adot_hi:    .res 1
ma:         .res 1
ml:         .res 1
mh:         .res 1
msign:      .res 1
sx:         .res 1
sy:         .res 1
ci:         .res 1
ri:         .res 1
di:         .res 1
hr:         .res 1
ox:         .res 1
oy:         .res 1
px:         .res 1
py:         .res 1
shp_i:      .res 1
rcol:       .res 1
rrow:       .res 1
rcc:        .res 1
rky:        .res 1
rd_lo:      .res FROWS          ; per row: blocks of 8 columns drawn on, this
rd_hi:      .res FROWS          ;   frame (bits: blocks 0-7, 8-9)
rp_lo:      .res FROWS          ;   ... and the last frame
rp_hi:      .res FROWS
bm_lo:      .res 1
bm_hi:      .res 1
blk_end:    .res 1
force:      .res 1
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
