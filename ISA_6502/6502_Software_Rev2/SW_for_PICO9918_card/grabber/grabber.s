; ============================================================================
; grabber.s - GOLD GRABBER, a treasure grabbing game for the 6502 SBC,
;             CPU Rev2, on the PICO9918 card
;
;   build:  make.bat (make.bat 4 for a 4 MHz clock)
;   run:    L GRABBER 0800   then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  video frames (1/60 s) a frame takes (default 3: 20 a second)
;   $0804  controls at start: 0 keyboard, 1 gamepad (default)
;   $0805  sound at start: 0 on, 1 off (M switches)
;
; The game is the PIC32 terminal version's, unchanged.  The picture (v2) is
; drawn at the screen's own resolution in the F18A's ECM2 colour mode: the
; field's background on tile layer 1, the miner and the things in the pit on
; layer 2 (each thing drawn into patterns of its own when the level starts),
; and everything that moves as sprites (disp2.s; the art: gen_pico.py).  A
; game pixel is 1.5 x 2 screen pixels.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 3             ; video frames a frame (20 a second)
FPS             = 20            ; (frames in a second at that)

; ---- text (print) ------------------------------------------------------------
TC_COL          = $0E           ; print: the next byte is the column
TC_ROW          = $0F           ;   ... the row
.define RV_ON   $11             ;   highlighted text (white on blue) from here
.define RV_OFF  $12
TERM            = $FF
C_TEXT          = $F1
C_TEXT_HI       = $F4

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
        .include "grabber_gfx.inc"      ; colours, font (gen_pico.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines
        .include "disp2.s"      ; the picture

; ----------------------------------------------------------------------------
; I/O helpers
; ----------------------------------------------------------------------------
getc            = SBC_CHRIN     ; carry set = key in A

; called by vdp_frame while it waits
frame_idle:
        jmp     sfx_poll

; the cursor (text) to column X, row Y.  Preserves X and Y.
gotoxy: sty     cur_row
setcol: stx     cur_col
        rts

txt_mode:
gfx_mode:
        rts
set_rep:sta     cur_rep
        rts

; print the string at A (lo) / Y (hi), ended by TERM: characters, and
; TC_ROW r, TC_COL c, RV_ON / RV_OFF
print:  sta     @ld+1
        sty     @ld+2
@nx:    jsr     @ld
        cmp     #TERM
        beq     @done
        cmp     #TC_ROW
        bne     @2
        jsr     @ld
        sta     cur_row
        jmp     @nx
@2:     cmp     #TC_COL
        bne     @3
        jsr     @ld
        sta     cur_col
        jmp     @nx
@3:     cmp     #RV_ON
        bne     @4
        lda     #1
        sta     rv
        bne     @nx
@4:     cmp     #RV_OFF
        bne     @5
        lda     #0
        sta     rv
        beq     @nx
@5:     jsr     putc
        jmp     @nx
@done:  rts
@ld:    lda     $FFFF
        inc     @ld+1
        bne     :+
        inc     @ld+2
:       rts

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
CTRL_COL        = 0
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
        ; the PICO9918?  (CPU Rev2 ROM: a JMP at $FE1B, SBC_SYSINFO)
        lda     SBC_SYSINFO
        cmp     #$4C
        bne     @nopico
        jsr     SBC_SYSINFO
        cmp     #DISP_PICO
        beq     @pico
@nopico:
        ldx     #0
@m:     lda     need_txt,x
        beq     @bye
        jsr     SBC_CHROUT
        inx
        bne     @m
@bye:   jmp     SBC_MENU
@pico:  jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
        jsr     gfx_init

title:  jsr     sfx_off
        jsr     new_screen
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     hi_title
        ldx     #0              ; the pictures for the list of things
@p:     stx     tmp3
        lda     tc_x,x
        sta     tmp4
        ldy     tc_y,x
        lda     tc_id,x
        ldx     tmp4
        jsr     compose
        jsr     upload
        ldx     tmp3
        inx
        cpx     #NTC
        bne     @p
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
        ldx     #2
        ldy     #2
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
        jsr     pal_restore     ; the palette as it was
        jsr     SBC_CONRESET    ; the console's text screen back
        jmp     SBC_MENU

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
        jsr     draw_field
        lda     #1              ; (the field: a space in its sky row clears)
        sta     fieldcol
        jsr     SBC_TICKS
        sta     last_tick
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
        sta     ei_k
        lda     #K_NONE
        sta     it_k,x
        jmp     erase_item
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
        lda     #0              ; (the dots: none yet, nothing hit)
        sta     ls_n
        sta     ls_hit
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
        lda     lstep           ; a dot every step (after the first two)
        cmp     #2
        bcc     @nd
        jsr     ls_dot
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
@hit:   lda     #1              ; (frame_draw puts a ring at tpx, tpy)
        sta     ls_hit
        rts

; a laser dot at px, py: the first and the last kept (screen)
ls_dot: lda     px
        jsr     scr_x
        sta     ls_x1
        lda     py
        asl
        clc
        adc     #8
        sta     ls_y1
        lda     ls_n
        bne     @n
        lda     ls_x1
        sta     ls_x0
        lda     ls_y1
        sta     ls_y0
@n:     inc     ls_n
        rts

; ============================================================================
; input
; ============================================================================
read_input:
        lda     #0
        sta     fire_req
        sta     bomb_req
        jsr     read_pad        ; (any gamepad button: gamepad mode)
        lda     pad
        beq     @nsw
        lda     #1
        sta     ctrl
@nsw:   lda     ctrl
        beq     @keys
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
@np:    cmp     #KEY_DOWN       ; the AVR keyboard's arrows: down grab, up bomb
        beq     @fire
        cmp     #KEY_UP
        beq     @bomb
        ldx     ctrl            ; gamepad mode: ignore what the pad types
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
        lda     #<unpaused_txt
        ldy     #>unpaused_txt
        jsr     print
        lda     #$FF            ; (the status line again)
        sta     hud_dirty
        rts

; the game's pace: speed video frames a frame (the ROM's 60 Hz counter),
; the sound going on meanwhile
pace:   jsr     sfx_poll
        jsr     SBC_TICKS
        sec
        sbc     last_tick
        cmp     speed
        bcc     pace
        jsr     SBC_TICKS
        sta     last_tick
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
        ldx     #0
        ldy     #0
        jsr     gotoxy
        jsr     prmoney
        lda     #7
        jsr     padto
@1:     lda     hud_dirty
        and     #HD_REST
        beq     @2
        ldx     #9
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
        lda     #7
        jsr     padto
        ldx     #19
        ldy     #0
        jsr     gotoxy
        lda     level
        jsr     pr8
        lda     #3
        jsr     padto
        ldx     #28
        ldy     #0
        jsr     gotoxy
        lda     #<strong_s_txt
        ldy     #>strong_s_txt
        ldx     strong
        bne     @s1
        lda     #<blank7_txt+6
        ldy     #>blank7_txt
@s1:    jsr     print
        ldx     #29
        ldy     #0
        jsr     gotoxy
        lda     #<gx2_s_txt
        ldy     #>gx2_s_txt
        ldx     gx2
        bne     @s2
        lda     #<blank7_txt+6
        ldy     #>blank7_txt
@s2:    jsr     print
        ldx     #30
        ldy     #0
        jsr     gotoxy
        jsr     laser_on
        bne     @s3
        lda     #<blank7_txt+6
        ldy     #>blank7_txt
        jmp     @s4
@s3:    lda     #<laser_s_txt
        ldy     #>laser_s_txt
@s4:    jsr     print
@2:     lda     hud_dirty
        and     #HD_TIME
        beq     @3
        ldx     #23
        ldy     #0
        jsr     gotoxy
        lda     tsec
        jsr     pr8
        lda     #2
        jsr     padto
@3:     lda     hud_dirty
        and     #HD_BOMBS
        beq     @4
        ldx     #27
        ldy     #0
        jsr     gotoxy
        lda     bombs
        ora     #'0'
        jsr     putc
@4:     lda     hud_dirty       ; "+$123" for a moment after cashing in
        and     #HD_POP
        beq     @5
        ldx     #25
        ldy     #1
        jsr     gotoxy
        lda     #1
        sta     rv
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
        lda     #1              ; (print ends RV: keep it for the next pop)
        sta     rv
        jmp     @5
@pc:    lda     #<blank7_txt+1
        ldy     #>blank7_txt
        jsr     print
@5:     lda     #0
        sta     hud_dirty
        sta     rv
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
        beq     :+
        jmp     @up
:       lda     padnew
        and     #PAD_DOWN
        beq     :+
        jmp     @down
:       lda     padnew
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
        bne     :+
        jmp     @up
:
        cmp     #'B'
        beq     @down
        jmp     @l
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        jmp     @l
@np:    cmp     #KEY_UP         ; (the AVR keyboard's arrows)
        bne     :+
        jmp     @up
:       cmp     #KEY_DOWN
        bne     :+
        jmp     @down
:       ldx     ctrl            ; (gamepad mode: not what the pad types)
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
        ldx     #9
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
        ldx     #0
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
        ldx     #21
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
        ldx     #0              ; bombs held, and the message
        ldy     #19
        jsr     gotoxy
        lda     #<sh_bombs_txt
        ldy     #>sh_bombs_txt
        jsr     print
        lda     bombs
        ora     #'0'
        jsr     putc
        ldx     #0
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
; the pictures on the title screen (screen places of the game's 44,20 ...)
.define SXG(xx) (8 + (xx) + (xx) / 2)
.define SYG(yy) (8 + 2 * (yy))
tc_id:  .byte   CP_GEM, CP_CHEST_L, CP_CHEST_S, CP_ROCK_L, CP_ROCK_S, CP_GOPHER1, CP_GOPHER1, CP_GEM, CP_TNT
tc_x:   .byte   SXG(44), SXG(40), SXG(56), SXG(40), SXG(56), SXG(40), SXG(56), SXG(56) + 15, SXG(44)
tc_y:   .byte   SYG(20), SYG(30), SYG(31), SYG(42), SYG(44), SYG(55), SYG(55), SYG(55) + 1, SYG(65)
NTC = 9
bitmask_l:
        .byte   $80, $40, $20, $10, $08, $04, $02, $01
cls_txt:.byte   TERM
need_txt:
        .byte   13, 10, "GOLD GRABBER NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
title_txt:
        .byte   TC_ROW, 1, TC_COL, 9, RV_ON, " GOLD GRABBER ", RV_OFF
        .byte   TC_ROW, 3, TC_COL, 0, "SWING THE GRABBER, REEL IN WHAT"
        .byte   TC_ROW, 4, TC_COL, 0, "IT CATCHES, MEET THE MONEY GOAL."
        .byte   TC_ROW, 6, TC_COL, 16, "GEM  $250"
        .byte   TC_ROW, 9, TC_COL, 16, "CHESTS $100-800"
        .byte   TC_ROW, 10, TC_COL, 16, "(BIG ONES HEAVY)"
        .byte   TC_ROW, 12, TC_COL, 16, "ROCKS  $11-29"
        .byte   TC_ROW, 13, TC_COL, 16, "(VERY HEAVY)"
        .byte   TC_ROW, 15, TC_COL, 16, "GOPHERS $7,"
        .byte   TC_ROW, 16, TC_COL, 16, "WITH A GEM $257"
        .byte   TC_ROW, 18, TC_COL, 16, "TNT: BLOWS UP"
        .byte   TC_ROW, 19, TC_COL, 16, "WHAT'S NEAR IT"
        .byte   TC_ROW, 20, TC_COL, 0, "SPACE GRAB B BOMB P PAUSE Q QUIT"
        .byte   TC_ROW, 21, TC_COL, 0, "PAD: A GRAB B BOMB START PAUSE"
        .byte   TC_ROW, 23, TC_COL, 0, "SPACE OR START: PLAY  M: SOUND", TERM
hi_txt: .byte   "BEST: ", TERM
hi2_txt:.byte   " AT LEVEL ", TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 8, "/"
        .byte   TC_COL, 18, "L"
        .byte   TC_COL, 22, "T"
        .byte   TC_COL, 26, "B", TERM
lvl_txt:.byte   TC_ROW, 9, TC_COL, 12, "LEVEL ", TERM
goal_txt:
        .byte   TC_ROW, 11, TC_COL, 9, "GOAL   $", TERM
have_txt:
        .byte   TC_ROW, 13, TC_COL, 9, "MONEY  ", TERM
strong_txt:
        .byte   TC_ROW, 16, TC_COL, 2, "STRENGTH: REELING IN FASTER", TERM
gx2_txt:.byte   TC_ROW, 17, TC_COL, 5, "GEMS ARE WORTH DOUBLE", TERM
strong_s_txt:
        .byte   "S", TERM
gx2_s_txt:
        .byte   "G", TERM
laser_s_txt:
        .byte   "L", TERM
laser_txt:
        .byte   TC_ROW, 18, TC_COL, 0, "LASER POINTER: FIRST 30 SECONDS", TERM
blank7_txt:
        .byte   "       ", TERM
met_txt:.byte   TC_ROW, 10, TC_COL, 6, RV_ON, "                    "
        .byte   TC_ROW, 11, TC_COL, 6, "   GOAL REACHED!    "
        .byte   TC_ROW, 12, TC_COL, 6, "                    ", RV_OFF, TERM
paused_txt:
        .byte   TC_ROW, 1, TC_COL, 2, RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   TC_ROW, 1, TC_COL, 2, RV_ON, "        ", RV_OFF, TERM
over_txt:
        .byte   TC_ROW, 8, TC_COL, 0, RV_ON, "                                "
        .byte   TC_ROW, 9, TC_COL, 0, "           GAME  OVER           "
        .byte   TC_ROW, 10, TC_COL, 0, "                                ", RV_OFF
        .byte   TC_ROW, 11, TC_COL, 0, "                                "
        .byte   TC_ROW, 12, TC_COL, 0, "                                "
        .byte   TC_ROW, 13, TC_COL, 0, "                                "
        .byte   TC_ROW, 14, TC_COL, 0, "                                "
        .byte   TC_ROW, 11, TC_COL, 2, "YOU HAD      ", TERM
over2_txt:
        .byte   TC_ROW, 12, TC_COL, 2, "THE GOAL WAS $", TERM
over3_txt:
        .byte   TC_ROW, 14, TC_COL, 2, "SPACE/A: AGAIN     Q: TITLE", TERM
shop_txt:
        .byte   TC_ROW, 1, TC_COL, 11, RV_ON, " THE SHOP ", RV_OFF
        .byte   TC_ROW, 5, TC_COL, 0, "YOU HAVE", TC_ROW, 3, TC_COL, 0, "LEVEL ", TERM
shop2_txt:
        .byte   " DONE!"
        .byte   TC_ROW, 9, TC_COL, 4, "REEL IN FASTER, NEXT LEVEL"
        .byte   TC_ROW, 11, TC_COL, 4, "GEMS WORTH 2X, NEXT LEVEL"
        .byte   TC_ROW, 13, TC_COL, 4, "B BLOWS UP WHAT YOU HOLD"
        .byte   TC_ROW, 15, TC_COL, 4, "FIRST HALF OF NEXT LEVEL"
        .byte   TC_ROW, 22, TC_COL, 0, "UP/DOWN: CHOOSE  A/SPACE: BUY"
        .byte   TC_ROW, 23, TC_COL, 0, "1-4: BUY   N: NEXT LEVEL", TERM
sh_n0:  .byte   "1 STRENGTH", TERM
sh_n1:  .byte   "2 DOUBLE GEMS", TERM
sh_n2:  .byte   "3 A BOMB", TERM
sh_n3:  .byte   "4 LASER POINTER", TERM
sh_go_txt:
        .byte   "  NEXT LEVEL", TERM
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
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD (G: KEYBOARD)", TERM

; the display: R0-R7 (Graphics II: patterns $0000, colours $2000, names
; $3800, sprite attributes $3B00; display off; black)
vdp_regs:       ; Graphics I; display off; names, attributes, patterns, sprites
        .byte   $00, $80, V_NAME1 / $400, V_ATT1 / $40, V_TP0 / $800, V_SATTR / $80, V_SP0 / $800, $00
f18a_regs:      ; register, value
        .byte   10, V_NAME2 / $400      ; layer 2's names
        .byte   11, V_ATT2 / $40        ; ... attributes
        .byte   24, 0
        .byte   29, $40                 ; sprite planes 1K apart, tile planes 2K
        .byte   30, 31                  ; 31 sprites a line
        .byte   50, 1                   ; layer 2 under the sprites
        .byte   49, $A2                 ; layer 2 on, ECM2 tiles and sprites
F18A_N = 7

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
; the display
fieldcol:   .res 1              ; 0 text pages (black), 1 the field's colours
spr_c:      .res 1              ; the colour of the picture being drawn
pf_c:       .res 1              ; ... of the rope / laser pixels
rv:         .res 1
cur_col:    .res 1
cur_row:    .res 1
pu_x:       .res 1
pu_y:       .res 1
pu_hi:      .res 1
t_col:      .res 1
t_row:      .res 1
t_ca:       .res 2
pgrp:       .res 1
grp:        .res 8
dg_k:       .res 1
dg_t:       .res 1
dg_p:       .res 1
dg_i:       .res 1
dg_b0:      .res 4
dg_b1:      .res 4
dg_b2:      .res 4
sp_t:       .res 1
last_tick:  .res 1
tmp:        .res 2
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
wshown: .res 1
font_gone:.res 1
pu_c:   .res 1
pu_a:   .res 2
ur_x0:  .res 1
ur_x1:  .res 1
ur_y0:  .res 1
ur_y1:  .res 1
er_x0:  .res 1
er_x1:  .res 1
er_y0:  .res 1
er_y1:  .res 1
er_j:   .res 1
ei_i:   .res 1
ei_k:   .res 1
cm_x:   .res 1
cm_y:   .res 1
cm_w:   .res 1
cm_h:   .res 1
cm_ps:  .res 1
cm_nb:  .res 1
cm_yy:  .res 1
cm_b0:  .res 4
cm_b1:  .res 4
cm_c:   .res 2
cm_cx:  .res 1
cm_j:   .res 1
cm_p:   .res 2
up_y:   .res 1
up_c:   .res 2
up_x:   .res 1
up_xx:  .res 1
up_n:   .res 1
up_s:   .res 2
ns:     .res 1
ap_x:   .res 2
ap_y:   .res 1
ap_n:   .res 1
as_x:   .res 2
as_y:   .res 1
as_p:   .res 1
as_a:   .res 1
so_p:   .res 1
so_s:   .res 1
lp_src: .res 2
rope_md:.res 1
laser_md:.res 1
rd_d:   .res 1
rd_left:.res 1
mp_kind:.res 1
mp_x:   .res 2
mp_y:   .res 2
mp_t:   .res 1
sp_v:   .res 1
sp_m:   .res 1
sg_x:   .res 2
sg_y:   .res 2
sg_x0:  .res 1
sg_y0:  .res 1
sg_x1:  .res 1
sg_y1:  .res 1
sg_end: .res 1
sg_k:   .res 1
sg_a:   .res 1
rp_x1:  .res 1
rp_y1:  .res 1
ls_n:   .res 1
ls_hit: .res 1
ls_x0:  .res 1
ls_y0:  .res 1
ls_x1:  .res 1
ls_y1:  .res 1
bss_end:

        .segment "BUFS"
l2n:        .res 768            ; layer 2's names (as on the screen)
pool_p0:    .res NPOOL * 8      ; the things' patterns: plane 0
pool_p1:    .res NPOOL * 8      ;   plane 1
pool_used:  .res NPOOL
pool_at:    .res NPOOL          ;   their attributes
sat:        .res 128            ; the sprite attribute table, made each frame
lp_buf:     .res 64             ; the rope's (or the laser's) pattern
sl_part:    .res NSLOT          ; the part in each sprite pattern slot
sl_used:    .res NSLOT          ;   the frame it was last used
