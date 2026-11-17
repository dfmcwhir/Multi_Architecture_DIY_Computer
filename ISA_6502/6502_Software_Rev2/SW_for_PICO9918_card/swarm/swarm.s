; ============================================================================
; swarm.s - SWARM, a shooter in the style of the arcade swarm games, for
;           the 6502 SBC, CPU Rev2, on the PICO9918 card
;
;   build:  make.bat (make.bat 4 for a 4 MHz clock)
;   run:    L SWARM 0800   then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  video frames (1/60 s) a frame (default 2: 30 frames a second)
;   $0804  controls at start: 0 keyboard, 1 gamepad (default)
;   $0805  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card, through ../ay/sfx.s.  Without it, silence.
;
; Keys:    A / D or Left / Right  move      Space  fire
;          P pause   M sound on / off   Q quit
; Gamepad: left / right move, A or B fire, Start pause
;
; The game is the PIC32 terminal version's: the flight paths, the
; formation, the dives, the challenging stages, the scoring, the sound.
; Changed: the aliens dive more often and more at once, and each fires more
; shots; up to 20 aliens and bullets fly at once; the formation's places are
; 16 screen pixels apart and it sways a pixel at a time.
;
; The screen (PICO9918, F18A features: ECM2, two tile layers, scrolling):
;   - every sprite is 16 x 16 in 3 colours of its own (ECM2), one per object:
;     the ship, the aliens in flight (16 headings, both wing positions), the
;     bullets, the explosions.
;   - tile layer 1: the formation, 3 colours a tile too; it sways with the
;     hardware scroll.
;   - tile layer 2 (under the sprites): the status line, the messages, the
;     stars, the ships in reserve.
;
; Coordinates are the old sprite layer's ("wire"): x 32-191, y 32-127 for
; the screen, a pixel 1.5 x 2 screen pixels.  Positions and speeds are 8.8
; fixed point.  Headings are 0-63: 0 up, 16 right, 32 down, 48 left.  No
; zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 2             ; video frames a frame (30 a second)

; ---- text (print) ------------------------------------------------------------
TC_COL          = $0E           ; print: the next byte is the column
TC_ROW          = $0F           ;   ... the row
.define RV_ON   $11             ;   red from here
.define RV_OFF  $12
TERM            = $FF

; ---- VRAM (Graphics I, two tile layers, ECM2) -------------------------------
V_TP0           = $0000         ; tile patterns, plane 0
V_TP1           = $0800         ;   plane 1
V_SP0           = $1000         ; sprite patterns, plane 0 (sprite k: names 4 k)
V_SP1           = $1800         ;   plane 1
V_NAME1         = $2000         ; layer 1 names: the formation
V_ATT1          = $2400         ; layer 1 attributes (one per pattern)
V_ATT2          = $2500         ; layer 2 attributes
V_SATTR         = $2600         ; sprite attributes
V_NAME2         = $2800         ; layer 2 names: text, stars, ships waiting
VDP_NAME        = V_NAME2
HIDE_Y          = $C0           ; a sprite's Y off the screen
SA_FLIPX        = $40           ; sprite attribute 3: mirrored,
SA_EC           = $80           ;   32 pixels left

; ---- the field (wire coordinates) ---------------------------------------------------
SHIP_Y          = 112           ; the ship's top (text rows 20-21)
SHIP_XMIN       = 33
SHIP_XMAX       = 184
SHIP_STEP       = 2
SHOT_STEP       = 5
SHOT_TOP        = 36
EBUL_VY         = $0280         ; enemy bullets: 2.5 pixels a frame down
FM_ROW          = 3             ; the formation's first text row
FM_Y            = 32 + FM_ROW * 4       ; its top: 44
FM_BOT          = FM_Y + 40     ; the bottom of its last row
FM_COL          = 9             ; the formation's layer 1 name column
FXS_MIN         = 30            ; its screen x sways 30 .. 66
FXS_MAX         = 66
SWAY_N          = 3             ; frames a pixel
MSG_ROW         = 15            ; messages (STAGE 1, READY ...)
STAR_TOP        = 4             ; the stars' rows: pixel y 4 .. 87 (rows 1-21)
STAR_BOT        = 88
NSTAR           = 16

; ---- objects (= sprite slots) ------------------------------------------------------
NOBJ            = 26
OB_BOOM         = 0             ; 0-2 explosions
NBOOM           = 3
OB_FLY          = 3             ; 3-22 aliens in flight, their bullets
NFLY            = 20
OB_SHOT         = 23            ; 23-24
SL_SHIP         = 25
K_NONE          = 0
K_ALIEN         = 1
K_EBUL          = 2
K_BOOM          = 3
K_SHOT          = 4
M_PATH          = 0             ; an alien's modes: following a path
M_HOME          = 1             ;   flying back to its place
M_LAND          = 2             ;   nearly there
M_ATTACK        = 3             ;   diving at the ship
M_EXIT          = 4             ;   (challenging stage) flying away
T_BEE           = 0             ; kinds
T_BFLY          = 1
T_BOSS          = 2
T_HURT          = 3             ; (a boss hit once: its pictures)
NGRID           = 50            ; 5 rows x 10
NONE            = $FF
P_HOME          = $FF           ; the ends of a flight path (gen.py)
P_ATTACK        = $FE
P_EXIT          = $FD

; ============================================================================
        .segment "RODATA"
        .include "swarm_data.inc"
        .include "swarm_sound.inc"      ; the sounds (game_sounds.py)
        .include "swarm_gfx.inc"        ; the PICO9918 graphics (gen_pico.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines

; ----------------------------------------------------------------------------
; I/O helpers
; ----------------------------------------------------------------------------
getc            = SBC_CHRIN     ; carry set = key in A

; while vdp_frame waits (not used)
frame_idle:
        jmp     sfx_poll

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

; print A (0-99) as two digits
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

; print the 3 BCD bytes at score+X (X = 0: the score, 3: the high score)
prscore:lda     score+2,x
        jsr     prbcd
        lda     score+1,x
        jsr     prbcd
        lda     score,x
        jmp     prbcd

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
CTRL_ROW        = 20

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
        ldx     #2              ; the aliens beside their points (sprites)
@tl:    stx     dv_k
        lda     title_y,x
        sta     tmp4
        lda     #48
        sta     tmp3
        lda     title_pic,x
        jsr     title_spr
        ldx     dv_k
        dex
        bpl     @tl
        ldx     #3
        jsr     title_sat
        ldx     #6              ; the high score
        ldy     #18
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
        ldx     #3
        jsr     prscore
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
        lda     #$C0            ; the PICO9918 back to its defaults (VR50:
        ldx     #50             ; a reset, the palette too), then the
        jsr     vdp_reg         ; console's text screen
        jsr     SBC_CONRESET
        jmp     SBC_MENU

; clear the screen (which hides the sprites) and forget what it showed
new_screen:
        jsr     cls
        ldx     #NSTAR-1        ; no star shows
        lda     #0
@s:     sta     st_on,x
        dex
        bpl     @s
        rts

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     stage
        sta     quit
        sta     extra1
        sta     extra2
        sta     n_norm
        sta     ship_st
        sta     dead_t
        lda     #3
        sta     lives

; ---- a stage -------------------------------------------------------------------------
next_stage:
        inc     stage
        jsr     sfx_off
        jsr     new_screen
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        jsr     clear_objects
        ldx     #NSTAR-1        ; the stars, anywhere
@st:    jsr     rand
        cmp     #160
        bcs     @st
        sta     st_x,x
@sy:    jsr     rand
        and     #$7F
        cmp     #STAR_BOT
        bcs     @sy
        cmp     #STAR_TOP
        bcc     @sy
        sta     st_y,x
        dex
        bpl     @st
        ldx     #NGRID-1        ; nobody in the formation yet
        lda     #0
@g:     sta     fm,x
        sta     fhurt,x
        dex
        bpl     @g
        lda     #48             ; the formation in the middle
        sta     fxs
        jsr     set_sway
        jsr     fm_draw         ; (nobody there yet: blank)
        lda     #1
        sta     fdir
        lda     #SWAY_N
        sta     sway_t
        lda     #0
        sta     ent_g
        sta     ent_i
        sta     hits
        sta     chal
        lda     #40
        sta     left
        sta     ent_t
        lda     stage           ; every third stage is a challenging stage
@m3:    cmp     #3
        bcc     @nm3
        sbc     #3
        bne     @m3
        lda     #1
        sta     chal
        bne     @diff
@nm3:   inc     n_norm
@diff:  lda     n_norm          ; how hard: by the normal stages played
        cmp     #9
        bcc     @d1
        lda     #9
@d1:    sta     tmp
        asl
        asl
        adc     #56             ; speed 56 + 4 n (/32 pixels a frame)
        sta     fly_sp
        lda     tmp             ; aliens diving at once: 3 + n / 2
        lsr
        clc
        adc     #3
        sta     max_div
        lda     tmp             ; frames between dives: 40 - 3 n
        asl
        adc     tmp
        sta     tmp2
        lda     #40
        sec
        sbc     tmp2
        sta     dive_gap
        lda     #3              ; shots a diver fires: 3, from the third
        ldx     tmp             ; normal stage 4
        cpx     #3
        bcc     @d3
        lda     #4
@d3:    sta     div_shots
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        jsr     draw_lives
        lda     ship_st         ; (a new game, or the ship was lost on the
        cmp     #2              ;  last stage's end: it comes back now)
        bne     @sh
        lda     #0
        sta     ship_st
@sh:    lda     #80 + 32 - 4
        sta     ship_x
        lda     #60
        sta     dive_t
        lda     #<stage_txt     ; "STAGE n" (or the challenging stage)
        ldy     #>stage_txt
        jsr     print
        lda     stage
        jsr     prdec2
        lda     chal
        beq     @nc
        lda     #<chal_txt
        ldy     #>chal_txt
        jsr     print
@nc:    lda     #1
        sta     msg_on
        lda     #70
        sta     msg_t
        lda     #SND_START
        jsr     sfx_snd
        lda     #SND_STARTB
        jsr     sfx_snd
        jsr     put_sprites     ; (the ship)
        jsr     SBC_TICKS       ; (the pace counts from here)
        sta     last_tick
        lda     chal            ; a challenging stage: its tune
        beq     game_loop
        lda     #MUS_CHAL
        jsr     sfx_snd
        lda     #MUS_CHAL+1
        jsr     sfx_snd

; ---- the frame loop --------------------------------------------------------------
game_loop:
        jsr     sfx_poll
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     ship_update
        jsr     shots_update
        jsr     fly_update
        jsr     booms_update
        jsr     ship_hits
        jsr     entries
        jsr     dives
        jsr     sway
        jsr     put_sprites
        jsr     stars
        jsr     msg_update
        jsr     hud_update
        jsr     pace
        inc     frame
        lda     ship_st         ; game over: the ship gone, and no more
        cmp     #2
        bne     @2
        lda     lives
        bne     @2
        lda     dead_t
        bne     @2
        jmp     game_over
@2:     lda     left            ; the stage is over: every alien gone, and
        bne     game_loop       ; the explosions done
        ldx     #NOBJ-1
@b:     lda     o_kind,x
        cmp     #K_BOOM
        bne     *+5
        jmp     game_loop
        cmp     #K_EBUL
        bne     *+5
        jmp     game_loop
        dex
        bpl     @b
        lda     ship_st         ; (not while the ship is blowing up)
        cmp     #1
        bne     *+5
        jmp     game_loop
        jmp     stage_done

; the stage is over: (a challenging stage) the hits and the bonus; then the next
stage_done:
        jsr     no_sprites
        jsr     clear_objects
        lda     chal
        bne     @c
        lda     #15
        jsr     delay_long
        jmp     next_stage
@c:     lda     #<hits_txt      ; NUMBER OF HITS nn
        ldy     #>hits_txt
        jsr     print
        lda     hits
        jsr     prdec2
        lda     #20
        jsr     delay_long
        lda     hits
        cmp     #40
        bne     @nperf
        lda     #<perfect_txt   ; all 40: 10000
        ldy     #>perfect_txt
        jsr     print
        lda     #SND_PERFECT
        jsr     sfx_snd
        lda     #0
        ldy     #0
        ldx     #1
        jsr     add_score_x
        jmp     @show
@nperf: lda     #<bonus_txt     ; else 100 each
        ldy     #>bonus_txt
        jsr     print
        lda     hits            ; hits in BCD
        jsr     to_bcd
        pha
        jsr     prbcd
        lda     #'0'
        jsr     putc
        lda     #'0'
        jsr     putc
        pla
        tay
        lda     #0
        jsr     add_score
@show:  jsr     hud_update
        lda     #40
        jsr     delay_long
        jmp     next_stage

; A (0-99) in BCD
to_bcd: ldx     #0
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     sta     tmp
        txa
        asl
        asl
        asl
        asl
        ora     tmp
        rts

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
@nohi:  jsr     sfx_off
        lda     #SND_OVER
        jsr     sfx_snd
        jsr     no_sprites
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

clear_objects:
        ldx     #NOBJ-1
        lda     #0
@o:     sta     o_kind,x
        dex
        bpl     @o
        rts

; ============================================================================
; the status line, the ships in reserve, messages
; ============================================================================
hud_update:
        lda     hud_dirty
        bne     @go
        rts
@go:    lda     #0
        sta     hud_dirty
        ldx     #4
        ldy     #0
        jsr     gotoxy
        ldx     #0
        jsr     prscore
        ldx     #16
        ldy     #0
        jsr     gotoxy
        ldx     #3
        jsr     prscore
        ldx     #29
        ldy     #0
        jsr     gotoxy
        lda     stage
        jmp     prdec2

; the message (row MSG_ROW) goes when its time is up
msg_update:
        lda     msg_on
        beq     @r
        dec     msg_t
        bne     @r
        lda     #0
        sta     msg_on
        lda     #<unmsg_txt
        ldy     #>unmsg_txt
        jmp     print
@r:     rts

; add A (BCD, the tens and ones) / Y (BCD, hundreds) to the score.  At
; 20000 and 70000: a ship.
add_score:
        ldx     #0
add_score_x:                    ; (X: BCD ten thousands, for the 10000 bonus)
        stx     tmp4
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
        adc     tmp4
        sta     score+2
        cld
        plp
        lda     #1
        sta     hud_dirty
        lda     extra1          ; the extra ships
        bne     @e2
        lda     score+2
        cmp     #$02
        bcc     @r
        inc     extra1
        jmp     extra_life
@e2:    lda     extra2
        bne     @r
        lda     score+2
        cmp     #$07
        bcc     @r
        inc     extra2
        jmp     extra_life
@r:     rts

extra_life:
        lda     #SND_LIFE
        jsr     sfx_snd
        lda     lives
        cmp     #6
        bcs     @n
        inc     lives
@n:     jmp     draw_lives

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
        lda     #<-SHIP_STEP
        sta     mv
@r:     lda     pad
        and     #PAD_RIGHT
        beq     @a
        lda     #SHIP_STEP
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
HOLD_MOVE       = 4

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
        bne     @ar
        inc     esc_st
        rts
@ar:    cmp     #KEY_LEFT       ; the ROM's arrow key codes
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
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
@left:  lda     #<-SHIP_STEP
        bne     @mv
@right: lda     #SHIP_STEP
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
        ldx     #12
        ldy     #MSG_ROW
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
        lda     #<unmsg_txt     ; (any message goes too)
        ldy     #>unmsg_txt
        jsr     print
        lda     #0
        sta     msg_on
        jsr     SBC_TICKS       ; (no hurry to catch up)
        sta     last_tick
        rts

; ============================================================================
; the ship and its shots
; ============================================================================
ship_update:
        lda     ship_st
        beq     @alive
        lda     dead_t          ; blowing up, or gone: waiting to come back
        beq     @back
        dec     dead_t
        bne     @r
        lda     #2              ; (the explosion is over)
        sta     ship_st
        rts
@back:  lda     lives           ; (game over: the loop sees it)
        beq     @r
        ldx     #OB_FLY+NFLY-1  ; back when nothing is diving or shooting
@c:     lda     o_kind,x
        cmp     #K_EBUL
        beq     @r
        cmp     #K_ALIEN
        bne     @cn
        lda     o_mode,x
        cmp     #M_ATTACK
        beq     @r
@cn:    dex
        cpx     #OB_FLY
        bcs     @c
        lda     #0
        sta     ship_st
        lda     #80 + 32 - 4
        sta     ship_x
        lda     #50
        sta     dive_t
        lda     #<ready_txt
        ldy     #>ready_txt
        jsr     print
        lda     #1
        sta     msg_on
        lda     #40
        sta     msg_t
@r:     rts
@alive: lda     mv
        beq     @fire
        bmi     @left
        clc
        adc     ship_x
        cmp     #SHIP_XMAX+1
        bcc     @set
        lda     #SHIP_XMAX
        bne     @set
@left:  clc
        adc     ship_x
        cmp     #SHIP_XMIN
        bcs     @set
        lda     #SHIP_XMIN
@set:   sta     ship_x
@fire:  lda     fire
        beq     @r
        ldx     #OB_SHOT        ; a free shot?
        lda     o_kind,x
        beq     @shot
        inx
        lda     o_kind,x
        bne     @r
@shot:  lda     #K_SHOT
        sta     o_kind,x
        lda     ship_x
        clc
        adc     #3
        sta     o_x_hi,x
        lda     #SHIP_Y - 3
        sta     o_y_hi,x
        lda     #SND_FIRE
        jmp     sfx_snd

; the shots go up; each hits an alien in flight or in the formation
shots_update:
        ldx     #OB_SHOT
@s:     stx     si
        lda     o_kind,x
        cmp     #K_SHOT
        bne     @n
        lda     o_y_hi,x
        sec
        sbc     #SHOT_STEP
        cmp     #SHOT_TOP
        bcc     @off
        sta     o_y_hi,x
        jsr     shot_fly        ; an alien in flight?
        bcs     @off
        ldx     si
        jsr     shot_fm         ; ... or in the formation?
        bcc     @n
@off:   ldx     si
        lda     #0
        sta     o_kind,x
@n:     ldx     si
        inx
        cpx     #OB_SHOT+2
        bne     @s
        rts

; shot X against the aliens in flight.  Carry set: it hit one.
shot_fly:
        lda     o_x_hi,x
        sta     tpx
        lda     o_y_hi,x
        sta     tpy
        ldx     #OB_FLY
@a:     lda     o_kind,x
        cmp     #K_ALIEN
        bne     @n
        lda     tpx             ; x - its left: 0-7
        sec
        sbc     o_x_hi,x
        cmp     #8
        bcs     @n
        lda     tpy             ; y - its top + 3: 0-10 (the shot is 4 tall)
        clc
        adc     #3
        sec
        sbc     o_y_hi,x
        cmp     #11
        bcs     @n
        jsr     hit_flyer
        sec
        rts
@n:     inx
        cpx     #OB_FLY+NFLY
        bne     @a
        clc
        rts

; alien X (in flight) is hit
hit_flyer:
        lda     o_type,x        ; a boss the first time: hurt
        cmp     #T_BOSS
        bne     @kill
        lda     chal
        bne     @kill
        ldy     o_home,x
        lda     fhurt,y
        bne     @kill
        lda     #1
        sta     fhurt,y
        lda     #SND_BOSSHIT
        jmp     sfx_snd
@kill:  stx     tmp3
        lda     o_x_hi,x
        sta     tpx
        lda     o_y_hi,x
        sta     tpy
        jsr     boom_at
        ldx     tmp3
        lda     #0
        sta     o_kind,x
        ldy     o_home,x
        cpy     #NONE
        beq     @nh
        sta     fm,y            ; (no longer in the formation either)
@nh:    dec     left
        lda     chal
        beq     @pts
        inc     hits            ; a challenging stage: 100 each
        lda     #SND_HIT
        jsr     sfx_snd
        lda     #0
        ldy     #1
        jmp     add_score
@pts:   ldy     o_type,x        ; in flight: double (a boss 400)
        lda     hit_snd,y
        jsr     sfx_snd
        lda     pts_lo_d,y
        pha
        lda     pts_hi_d,y
        tay
        pla
        jmp     add_score

; shot X against the formation.  Carry set: it hit one.
shot_fm:
        lda     chal
        bne     @no
        lda     o_y_hi,x        ; its row: (y - FM_Y) / 8
        sec
        sbc     #FM_Y
        bcc     @no
        cmp     #FM_BOT - FM_Y
        bcs     @no
        lsr
        lsr
        lsr
        sta     tmp             ; gy
        asl                     ; its first place: gy * 10
        asl
        adc     tmp
        asl
        sta     tmp3
        ldy     #0              ; which place: x - its x = 0..7
@d:     sty     tmp2
        tya
        clc
        adc     tmp3
        tay
        jsr     grid_xy         ; (preserves X)
        lda     o_x_hi,x
        sec
        sbc     tpx
        cmp     #8
        bcc     @dd
        ldy     tmp2
        iny
        cpy     #10
        bcc     @d
        bcs     @no
@dd:    ldy     tmp2
        lda     tmp             ; the grid index: gy * 10 + gx
        asl
        sta     tmp4
        asl
        asl
        adc     tmp4
        adc     tmp2
        tay
        lda     fm,y
        cmp     #1
        bne     @no
        jsr     hit_fm
        sec
        rts
@no:    clc
        rts

; the alien in the formation at grid Y is hit
hit_fm:
        sty     tmp3
        lda     row_kind,y      ; a boss the first time: hurt
        cmp     #T_BOSS
        bne     @kill
        lda     fhurt,y
        bne     @kill
        lda     #1
        sta     fhurt,y
        jsr     fm_draw_one
        lda     #SND_BOSSHIT
        jmp     sfx_snd
@kill:  lda     #0
        sta     fm,y
        jsr     fm_draw_one     ; (blank now)
        ldy     tmp3
        jsr     grid_xy
        jsr     boom_at
        dec     left
        ldy     tmp3
        lda     row_kind,y
        tay
        lda     hit_snd,y
        jsr     sfx_snd
        lda     pts_lo_f,y
        pha
        lda     pts_hi_f,y
        tay
        pla
        jmp     add_score

; an explosion at tpx, tpy
boom_at:
        ldx     boom_i
        inx
        cpx     #NBOOM
        bcc     @b
        ldx     #0
@b:     stx     boom_i
        lda     #K_BOOM
        sta     o_kind,x
        lda     #0
        sta     o_t,x
        lda     tpx
        sta     o_x_hi,x
        lda     tpy
        sta     o_y_hi,x
        rts

booms_update:
        ldx     #NBOOM-1
@b:     lda     o_kind,x
        cmp     #K_BOOM
        bne     @n
        inc     o_t,x
        lda     o_t,x
        cmp     #16
        bcc     @n
        lda     #0
        sta     o_kind,x
@n:     dex
        bpl     @b
        rts

; the ship against the bullets and the aliens in flight
ship_hits:
        lda     ship_st
        bne     @r
        ldx     #OB_FLY
@o:     stx     si
        lda     o_kind,x
        cmp     #K_EBUL
        beq     @bul
        cmp     #K_ALIEN
        bne     @n
        lda     o_x_hi,x        ; an alien: their boxes overlap by enough
        sec
        sbc     ship_x
        clc
        adc     #6              ; (-6 .. 5)
        cmp     #12
        bcs     @n
        lda     o_y_hi,x
        sec
        sbc     #SHIP_Y
        clc
        adc     #6
        cmp     #12
        bcs     @n
        jsr     hit_flyer       ; (it goes too)
        ldx     si
        lda     o_kind,x        ; (a boss hit once is still there: it goes)
        beq     @die
        lda     #0
        sta     o_kind,x
        dec     left
        ldy     o_home,x
        cpy     #NONE
        beq     @die
        sta     fm,y
        jmp     @die
@bul:   lda     o_x_hi,x        ; a bullet: its pixel in the ship's middle
        sec
        sbc     ship_x
        sec
        sbc     #1
        cmp     #5
        bcs     @n
        lda     o_y_hi,x
        clc
        adc     #2
        sec
        sbc     #SHIP_Y+1
        cmp     #8
        bcs     @n
        lda     #0
        sta     o_kind,x
        jmp     @die
@n:     ldx     si
        inx
        cpx     #OB_FLY+NFLY
        bne     @o
@r:     rts
@die:   lda     #1              ; the ship blows up
        sta     ship_st
        lda     #36
        sta     dead_t
        dec     lives
        jsr     draw_lives
        lda     #SND_BOOM
        jsr     sfx_snd
        ldx     #OB_FLY         ; the divers go back to their places
@h:     lda     o_kind,x
        cmp     #K_ALIEN
        bne     @hn
        lda     o_mode,x
        cmp     #M_ATTACK
        bne     @hn
        lda     #M_HOME
        sta     o_mode,x
        lda     #0
        sta     o_t,x
@hn:    inx
        cpx     #OB_FLY+NFLY
        bne     @h
        rts

; ============================================================================
; the formation
; ============================================================================
; the formation sways a pixel at a time (the hardware scroll); its wings
; beat every 8 frames
sway:   lda     chal
        bne     @r
        lda     frame           ; the wings
        lsr
        lsr
        lsr
        and     #1
        cmp     flap
        beq     @s
        sta     flap
        jsr     fm_draw
@s:     dec     sway_t
        bne     @r
        lda     #SWAY_N
        sta     sway_t
        lda     fxs
        clc
        adc     fdir
        sta     fxs
        cmp     #FXS_MIN
        beq     @turn
        cmp     #FXS_MAX
        bne     @f
@turn:  lda     #0
        sec
        sbc     fdir
        sta     fdir
@f:     jmp     set_sway
@r:     rts

; ============================================================================
; aliens in flight
; ============================================================================
; a free object for an alien or a bullet: X (carry set), or carry clear
free_fly:
        ldx     #OB_FLY+NFLY-1
@f:     lda     o_kind,x
        beq     @y
        dex
        cpx     #OB_FLY
        bcs     @f
        clc
        rts
@y:     sec
        rts

; how many aliens are in flight in modes below A (M_ATTACK: coming in or
; going home; M_EXIT + 1: all): A
count_fly:
        sta     tmp
        lda     #0
        sta     tmp2
        ldx     #OB_FLY
@c:     lda     o_kind,x
        cmp     #K_ALIEN
        bne     @n
        lda     o_mode,x
        cmp     tmp
        bcs     @n
        inc     tmp2
@n:     inx
        cpx     #OB_FLY+NFLY
        bne     @c
        lda     tmp2
        rts

; start alien X on path A, at its start (mirrored if mir), kind tmp3, home Y
launch: sta     o_path,x
        tya
        sta     o_home,x
        lda     tmp3
        sta     o_type,x
        lda     #K_ALIEN
        sta     o_kind,x
        lda     #M_PATH
        sta     o_mode,x
        lda     #0
        sta     o_pp,x
        sta     o_pt,x
        sta     o_t,x
        sta     o_x_lo,x
        sta     o_y_lo,x
        lda     mir
        sta     o_mir,x
        lda     fly_sp
        sta     o_sp,x
        ldy     o_path,x
        lda     path_sy,y
        sta     o_y_hi,x
        lda     path_sx,y
        ldy     mir
        beq     @x
        eor     #$FF            ; the mirror: 216 - x
        sec
        adc     #216
@x:     sta     o_x_hi,x
        ldy     o_path,x
        lda     path_sh,y
        ldy     mir
        beq     @h
        eor     #$FF            ; 64 - h
        sec
        adc     #64
        and     #63
@h:     sta     o_h,x
        rts

; start alien X off from the formation at grid Y on path A (a dive)
take_off:
        sta     tmp
        lda     #2
        sta     fm,y
        sty     tmp4
        stx     tmp2
        jsr     fm_draw_one     ; (its place blank)
        ldy     tmp4
        jsr     grid_xy
        ldx     tmp2
        ldy     tmp4
        lda     row_kind,y
        sta     tmp3
        lda     grid_gx,y       ; the right half turns the other way
        cmp     #5
        lda     #0
        rol
        ldy     esc_on          ; (an escort: as its boss)
        bne     @m
        sta     mir
@m:     ldy     tmp4
        lda     tmp
        jsr     launch
        lda     tpx
        sta     o_x_hi,x
        lda     tpy
        sta     o_y_hi,x
        lda     #0              ; facing up: it climbs and rolls over
        sta     o_h,x
        lda     div_shots
        sta     o_fire,x
        lda     #52
        sta     o_fy,x
        lda     #SND_DIVE
        jmp     sfx_snd

; ---- coming in at the start of a stage ------------------------------------------------
; the aliens come in in 5 groups of 8, two at a time (one and its mirror
; image); a group starts when nearly all of the last are home
entries:
        lda     ent_g
        cmp     #5
        bcs     @r
        lda     msg_on          ; (after the "STAGE n" message)
        bne     @r
        lda     ent_i
        bne     @next
        lda     chal            ; a new group: when the last is nearly in
        beq     @n1
        lda     #M_EXIT+1       ; (challenging: when the last has gone)
        jsr     count_fly
        beq     @next
        rts
@n1:    lda     #M_ATTACK
        jsr     count_fly
        cmp     #3
        bcc     @next
@r:     rts
@next:  dec     ent_t
        bne     @r
        lda     #8
        sta     ent_t
        ldx     #OB_FLY+NFLY-1  ; two free objects
        ldy     #0
@fr:    lda     o_kind,x
        bne     @fn
        cpy     #0
        bne     @f2
        stx     tmp4
        iny
        bne     @fn
@f2:    stx     ent_x2
        jmp     @got
@fn:    dex
        cpx     #OB_FLY
        bcs     @fr
        lda     #1              ; (not yet: try the next frame)
        sta     ent_t
        rts
@got:
        ldx     ent_g           ; this group's path and kind
        lda     chal
        beq     @norm
        lda     stage           ; challenging: paths by the stage
        lsr
        lsr
        adc     ent_g
        and     #3
        tay
        lda     chal_path,y
        sta     ent_p
        lda     chal_kind,x
        sta     tmp3
        lda     #NONE
        sta     ent_h1
        sta     ent_h2
        jmp     @go
@norm:  lda     grp_path,x
        sta     ent_p
        txa                     ; its next two places: entry_order[8 g + i]
        asl
        asl
        asl
        adc     ent_i
        tay
        lda     entry_order,y
        sta     ent_h1
        lda     entry_order+1,y
        sta     ent_h2
        tay
        lda     #2
        sta     fm,y
        ldy     ent_h1
        sta     fm,y
        lda     row_kind,y
        sta     tmp3
@go:    lda     #0
        sta     mir
        ldx     tmp4
        ldy     ent_h1
        lda     ent_p
        jsr     launch
        lda     #1
        sta     mir
        ldx     ent_x2
        ldy     ent_h2
        lda     ent_p
        jsr     launch
        lda     ent_i
        clc
        adc     #2
        sta     ent_i
        cmp     #8
        bcc     @r2
        lda     #0
        sta     ent_i
        inc     ent_g
        lda     #20
        sta     ent_t
@r2:    rts

; ---- dives -----------------------------------------------------------------------------------
; now and then an alien in the formation dives at the ship (a boss takes
; the butterflies beside it along)
dives:  lda     chal
        bne     @r
        lda     ship_st
        bne     @r
        lda     ent_g           ; (once they are all in)
        cmp     #5
        bcc     @r
        dec     dive_t
        bne     @r
        lda     dive_gap        ; the next one: sooner when few are left
        ldx     left
        cpx     #10
        bcs     @g
        lsr
@g:     sta     dive_t
        jsr     rand            ; up to 4 more frames
        and     #3
        adc     dive_t
        sta     dive_t
        lda     #M_EXIT+1       ; not too many at once
        jsr     count_fly
        cmp     max_div
        bcs     @r
        jsr     rand            ; who: from a random place, the next one there
        and     #63
        cmp     #NGRID
        bcc     @p
        sbc     #NGRID
@p:     tay
        ldx     #NGRID
@f:     lda     fm,y
        cmp     #1
        beq     @who
        iny
        cpy     #NGRID
        bcc     @f1
        ldy     #0
@f1:    dex
        bne     @f
@r:     rts
@who:   sty     dv_g
        jsr     free_fly
        bcc     @r
        jsr     rand            ; the path
        and     #1
        clc
        adc     #PATH_DIVE
        sta     dv_p
        lda     #0
        sta     esc_on
        ldy     dv_g
        lda     dv_p
        jsr     take_off
        ldy     dv_g            ; a boss: up to 2 butterflies below it come
        lda     row_kind,y      ; too (the 3 places 9, 10, 11 on)
        cmp     #T_BOSS
        bne     @r2
        lda     #1
        sta     esc_on
        lda     #2
        sta     dv_n
        lda     #3
        sta     dv_k
        tya
        clc
        adc     #9
        sta     dv_g
@es:    ldy     dv_g
        lda     fm,y
        cmp     #1
        bne     @en
        jsr     free_fly
        bcc     @r2
        lda     dv_p
        ldy     dv_g
        jsr     take_off
        dec     dv_n
        beq     @r2
@en:    inc     dv_g
        dec     dv_k
        bne     @es
@r2:    lda     #0
        sta     esc_on
        rts

; ---- every alien in flight, every bullet --------------------------------------------
fly_update:
        ldx     #OB_FLY
@o:     stx     fi
        lda     o_kind,x
        cmp     #K_ALIEN
        bne     @nb
        jsr     alien_step
        jmp     @n
@nb:    cmp     #K_EBUL
        bne     @n
        jsr     bullet_step
@n:     ldx     fi
        inx
        cpx     #OB_FLY+NFLY
        bne     @o
        rts

bullet_step:
        lda     o_x_lo,x
        clc
        adc     o_vx_lo,x
        sta     o_x_lo,x
        lda     o_x_hi,x
        adc     o_vx_hi,x
        sta     o_x_hi,x
        lda     o_y_lo,x
        clc
        adc     #<EBUL_VY
        sta     o_y_lo,x
        lda     o_y_hi,x
        adc     #>EBUL_VY
        sta     o_y_hi,x
        cmp     #124            ; off the bottom (or the sides)
        bcs     @off
        lda     o_x_hi,x
        cmp     #32
        bcc     @off
        cmp     #192
        bcs     @off
        rts
@off:   lda     #0
        sta     o_kind,x
        rts

alien_step:
        lda     o_mode,x
        cmp     #M_PATH
        beq     a_path
        cmp     #M_HOME
        bne     *+5
        jmp     a_home
        cmp     #M_LAND
        bne     *+5
        jmp     a_land
        cmp     #M_ATTACK
        bne     *+5
        jmp     a_attack
        jmp     a_exit

; along its path: a piece is (frames, turn a frame); then what to do
a_path: lda     o_pt,x
        bne     @turn
        ldy     o_path,x        ; the next piece
        lda     path_lo,y
        sta     @ld+1
        lda     path_hi,y
        sta     @ld+2
        ldy     o_pp,x
        jsr     @ld
        cmp     #P_EXIT
        bcs     @end
        sta     o_pt,x
        iny
        jsr     @ld
        ldy     o_mir,x         ; (mirrored: the other way)
        beq     @t
        eor     #$FF
        clc
        adc     #1
@t:     sta     o_turn,x
        lda     o_pp,x
        clc
        adc     #2
        sta     o_pp,x
@turn:  dec     o_pt,x
        lda     o_h,x
        clc
        adc     o_turn,x
        and     #63
        sta     o_h,x
        jmp     move_fly
@ld:    lda     $FFFF,y
        rts
@end:   cmp     #P_HOME
        beq     @home
        cmp     #P_ATTACK
        beq     @att
        lda     #M_EXIT
        bne     @m
@att:   lda     ship_st         ; (no ship: home instead)
        bne     @home
        lda     #M_ATTACK
        bne     @m
@home:  lda     #0
        sta     o_t,x
        lda     #M_HOME
@m:     sta     o_mode,x
        jmp     move_fly

; away (a challenging stage): straight on until off the screen
a_exit: jsr     move_fly
        ldx     fi
        lda     o_x_hi,x
        cmp     #12
        bcc     @gone
        cmp     #212
        bcs     @gone
        lda     o_y_hi,x
        cmp     #8
        bcc     @gone
        cmp     #136
        bcs     @gone
        rts
@gone:  lda     #0
        sta     o_kind,x
        dec     left
        rts

; diving at the ship: turn towards it (always downwards), shoot; off the
; bottom it comes in again from the top and goes home
a_attack:
        lda     ship_x          ; aim at the ship's x, well below
        sta     tpx
        lda     #170
        sta     tpy
        jsr     aim
        jsr     atan2
        cmp     #20             ; (keep it going down: 20 .. 44)
        bcs     @a1
        lda     #20
@a1:    cmp     #45
        bcc     @a2
        lda     #44
@a2:    ldy     #2
        jsr     steer
        lda     o_fire,x        ; shoot as it passes the lines
        beq     @mv
        lda     o_y_hi,x
        cmp     o_fy,x
        bcc     @mv
        cmp     #104            ; (not when it's nearly on the ship)
        bcs     @mv
        lda     o_fy,x
        clc
        adc     #10
        sta     o_fy,x
        dec     o_fire,x
        jsr     shoot
        ldx     fi
@mv:    jsr     move_fly
        ldx     fi
        lda     o_y_hi,x        ; off the bottom: from the top again, home
        cmp     #132
        bcc     @r
        lda     #16
        sta     o_y_hi,x
        lda     #32
        sta     o_h,x
        lda     #M_HOME
        sta     o_mode,x
        lda     #0
        sta     o_t,x
@r:     rts

; a bullet from alien X, towards the ship
shoot:  stx     tmp2
        jsr     free_fly
        bcc     @r
        ldy     tmp2
        lda     #K_EBUL
        sta     o_kind,x
        lda     o_x_hi,y
        clc
        adc     #4
        sta     o_x_hi,x
        lda     o_y_hi,y
        clc
        adc     #8
        sta     o_y_hi,x
        lda     #0
        sta     o_x_lo,x
        sta     o_y_lo,x
        lda     ship_x          ; dx * 16, up to 1 pixel a frame
        clc
        adc     #3
        sec
        sbc     o_x_hi,x
        bvs     @r0             ; (too far: straight down)
        sta     tmp
        lda     #0
        sta     o_vx_hi,x
        lda     tmp
        bpl     @p
        dec     o_vx_hi,x
@p:     ldy     #4
@sh:    asl
        rol     o_vx_hi,x
        dey
        bne     @sh
        sta     o_vx_lo,x
        lda     o_vx_hi,x       ; clamp to -1 .. 1
        bmi     @neg
        beq     @ok
        lda     #0
        sta     o_vx_lo,x
        lda     #1
        sta     o_vx_hi,x
        bne     @ok
@neg:   cmp     #$FF
        beq     @ok
        lda     #0
        sta     o_vx_lo,x
        lda     #$FF
        sta     o_vx_hi,x
@ok:    lda     #SND_EFIRE
        jmp     sfx_snd
@r0:    lda     #0
        sta     o_vx_lo,x
        sta     o_vx_hi,x
@r:     rts

; home: fly to its place in the formation; near it, land
a_home: ldy     o_home,x
        jsr     grid_xy
        inc     o_t,x           ; (taking too long: land anyway)
        lda     o_t,x
        cmp     #150
        bcs     @land
        jsr     aim
        lda     a_far
        bne     @fly
        lda     a_dx            ; near: within 8 each way
        clc
        adc     #8
        cmp     #17
        bcs     @fly
        lda     a_dy
        clc
        adc     #8
        cmp     #17
        bcs     @fly
@land:  lda     #M_LAND
        sta     o_mode,x
        jmp     a_land
@fly:   jsr     atan2
        ldy     #5
        jsr     steer
        jmp     move_fly

; landing: straight to its place, up to 2 pixels a frame each way; there,
; it is in the formation again
a_land: ldy     o_home,x
        jsr     grid_xy
        lda     #32             ; (facing down, like the formation)
        sta     o_h,x
        lda     #0
        sta     o_x_lo,x
        sta     o_y_lo,x
        lda     tpx
        sec
        sbc     o_x_hi,x
        jsr     clamp2
        clc
        adc     o_x_hi,x
        sta     o_x_hi,x
        lda     tpy
        sec
        sbc     o_y_hi,x
        jsr     clamp2
        clc
        adc     o_y_hi,x
        sta     o_y_hi,x
        cmp     tpy
        bne     @r
        lda     o_x_hi,x
        cmp     tpx
        bne     @r
        lda     #0              ; home
        sta     o_kind,x
        ldy     o_home,x
        lda     #1
        sta     fm,y
        jmp     fm_draw_one
@r:     rts

; A (signed) limited to -2 .. 2
clamp2: bmi     @n
        cmp     #3
        bcc     @r
        lda     #2
@r:     rts
@n:     cmp     #$FE
        bcs     @r
        lda     #$FE
        rts

; a_dx, a_dy = tpx, tpy - alien X's place, halved if they don't fit in a
; signed byte (a_far = 1 then)
aim:    lda     #0
        sta     a_far
        lda     tpx
        sec
        sbc     o_x_hi,x
        sta     a_dx
        lda     #0
        sbc     #0
        sta     a_dxh           ; (the 9th bit: 0 or $FF)
        lda     tpy
        sec
        sbc     o_y_hi,x
        sta     a_dy
        lda     #0
        sbc     #0
        sta     a_dyh
        lda     a_dx            ; fits if bit 7 = the 9th bit
        eor     a_dxh
        bmi     @half
        lda     a_dy
        eor     a_dyh
        bmi     @half
        jmp     @y
@half:  inc     a_far
        lda     a_dxh
        lsr
        ror     a_dx
        lda     a_dyh
        lsr
        ror     a_dy
        lda     a_dx            ; (-128 would be its own negative)
        cmp     #$80
        bne     @y
        inc     a_dx
@y:     lda     a_dy
        cmp     #$80
        bne     @r
        inc     a_dy
@r:     rts

; A = the heading of (a_dx, a_dy): 0 up, 16 right, 32 down, 48 left
atan2:  lda     #0              ; w = -dy (up is positive)
        sec
        sbc     a_dy
        sta     at_w
        lda     a_dx
        bmi     @ul
        ldy     at_w            ; right half
        bmi     @dr
        sta     at_a            ; up right: q(u, w)
        lda     at_w
        sta     at_b
        jmp     at_q
@dr:    sta     at_a            ; down right: 32 - q(u, -w)
        lda     #0
        sec
        sbc     at_w
        sta     at_b
        jsr     at_q
        eor     #$FF
        sec
        adc     #32
        rts
@ul:    eor     #$FF            ; -u
        clc
        adc     #1
        sta     at_a
        lda     at_w
        bmi     @dl
        sta     at_b            ; up left: 64 - q(-u, w)
        jsr     at_q
        eor     #$FF
        sec
        adc     #64
        and     #63
        rts
@dl:    lda     #0              ; down left: 32 + q(-u, -w)
        sec
        sbc     at_w
        sta     at_b
        jsr     at_q
        clc
        adc     #32
        rts

; the angle (0-16) of (at_a across, at_b up), both 0..128
at_q:   lda     at_a
        cmp     at_b
        beq     @diag
        bcs     @wide
        ldy     at_b            ; steep: atan(a / b)
        jsr     frac16
        tay
        lda     atan_tab,y
        rts
@wide:  lda     at_b            ; flat: 16 - atan(b / a)
        ldy     at_a
        jsr     frac16
        tay
        lda     #16
        sec
        sbc     atan_tab,y
        rts
@diag:  ora     at_b
        beq     @z
        lda     #8
        rts
@z:     lda     #0
        rts

; A = A * 16 / Y (A < Y <= 128): 0..15
frac16: sty     fr_d
        ldy     #4
        ldx     #0
        stx     fr_q
@l:     asl                     ; (9 bits: carry)
        bcs     @sub
        cmp     fr_d
        bcc     @no
@sub:   sbc     fr_d
        sec
        rol     fr_q
        dey
        bne     @l
        beq     @e
@no:    clc
        rol     fr_q
        dey
        bne     @l
@e:     lda     fr_q
        ldx     fi
        rts

; turn alien X's heading towards A by at most Y a frame
steer:  sty     tmp
        sec
        sbc     o_h,x
        and     #63
        cmp     #32
        bcc     @p
        ora     #$C0            ; (-32 .. -1)
        sta     tmp2
        lda     #0              ; -most
        sec
        sbc     tmp
        cmp     tmp2            ; (-most >= the turn: -most)
        bcs     @add
        lda     tmp2
        jmp     @add
@p:     cmp     tmp
        bcc     @add
        lda     tmp
@add:   clc
        adc     o_h,x
        and     #63
        sta     o_h,x
        rts

; move alien X along its heading at its speed
move_fly:
        ldy     o_h,x
        lda     sin_tab,y       ; x += sin h * speed
        jsr     vel
        lda     o_x_lo,x
        clc
        adc     v_lo
        sta     o_x_lo,x
        lda     o_x_hi,x
        adc     v_hi
        sta     o_x_hi,x
        ldy     o_h,x           ; y -= cos h * speed
        lda     sin_tab+16,y
        jsr     vel
        lda     o_y_lo,x
        sec
        sbc     v_lo
        sta     o_y_lo,x
        lda     o_y_hi,x
        sbc     v_hi
        sta     o_y_hi,x
        rts

; v = A (sin, s.7) * the speed (32nds of a pixel) as 8.8: |A| * speed / 16
vel:    sta     v_s
        bpl     @p
        eor     #$FF
        clc
        adc     #1
@p:     sta     m_a             ; m_a * o_sp -> v_hi:v_lo
        lda     o_sp,x
        sta     m_b
        lda     #0
        sta     v_lo
        ldy     #8
@m:     lsr     m_b
        bcc     @s
        clc
        adc     m_a
@s:     ror
        ror     v_lo
        dey
        bne     @m
        ldy     #4              ; / 16
@d:     lsr
        ror     v_lo
        dey
        bne     @d
        sta     v_hi
        lda     v_s             ; the sign
        bpl     @r
        lda     #0
        sec
        sbc     v_lo
        sta     v_lo
        lda     #0
        sbc     v_hi
        sta     v_hi
@r:     rts

; ============================================================================
; the stars: pixels drifting down, not where the formation or a message is
; ============================================================================
stars:  ldx     #NSTAR-1
@s:     stx     sti
        txa                     ; the first half every frame, the rest
        and     #1              ; every other frame
        beq     @go
        lda     frame
        and     #1
        bne     @n
@go:    lda     st_on,x         ; off where it was
        beq     @mv
        lda     #0
        sta     st_on,x
        jsr     star_free
        bcc     @mv
        lda     #0
        jsr     star_put
@mv:    ldx     sti
        inc     st_y,x
        lda     st_y,x
        cmp     #STAR_BOT
        bcc     @on
        lda     #STAR_TOP       ; (round to the top, somewhere else)
        sta     st_y,x
@rx:    jsr     rand
        cmp     #160
        bcs     @rx
        sta     st_x,x
@on:    jsr     star_free       ; on where it is now
        bcc     @n
        lda     #1
        sta     st_on,x
        jsr     star_put
@n:     ldx     sti
        dex
        bpl     @s
        rts

; ============================================================================
; the display (PICO9918: Graphics I, two tile layers, ECM2 tiles and sprites)
; ============================================================================
; Layer 1 is the formation only, drawn at name column FM_COL + 2 gx; it sways
; with the hardware scroll (R27 = 8 FM_COL - fxs).  Layer 2 (on top, but
; under the sprites) has the status line, the messages, the stars and the
; ships in reserve.  Every sprite (one per object, 16 x 16) has its own
; pattern (names 4 k), loaded from the pictures when its picture changes.

; set up the VDP: registers, the tiles' two planes and attributes, the
; palette entries 16-63, the F18A's features
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (VRAM cleared)
        lda     #<V_TP0         ; the tiles: plane 0, plane 1
        ldy     #>V_TP0
        jsr     vdp_waddr
        lda     #<tile_p0
        ldx     #>tile_p0
        ldy     #8
        jsr     copy_pages
        lda     #<V_TP1
        ldy     #>V_TP1
        jsr     vdp_waddr
        lda     #<tile_p1
        ldx     #>tile_p1
        ldy     #8
        jsr     copy_pages
        lda     #<V_ATT1        ; the attributes (by pattern), both layers
        ldy     #>V_ATT1
        jsr     vdp_waddr
        lda     #<tile_attr
        ldx     #>tile_attr
        ldy     #1
        jsr     copy_pages
        lda     #<V_ATT2
        ldy     #>V_ATT2
        jsr     vdp_waddr
        lda     #<tile_attr
        ldx     #>tile_attr
        ldy     #1
        jsr     copy_pages
        lda     #$C0 | 16       ; the palette from entry 16 on (R47: the data
        ldx     #47             ; port writes the palette, counting up)
        jsr     vdp_reg
        ldx     #0
@pl:    lda     pal_game,x
        sta     VDP_DATA
        inx
        cpx     #96
        bne     @pl
        lda     #0              ; (the data port: VRAM again)
        ldx     #47
        jsr     vdp_reg
        ldx     #0              ; the F18A registers
@fr:    stx     tmp
        lda     f18a_regs+1,x   ; (value)
        pha
        lda     f18a_regs,x     ; (register)
        tax
        pla
        jsr     vdp_reg
        ldx     tmp
        inx
        inx
        cpx     #F18A_N * 2
        bne     @fr
        jsr     cls
        lda     #$C2            ; R1: display on, 16K, 16 x 16 sprites,
        ldx     #1              ; and bit 5 (the VDP interrupt) off
        jmp     vdp_reg

; copy Y pages from A (lo) / X (hi) to VRAM (the address set)
copy_pages:
        sta     vdp_src
        stx     vdp_src+1
        lda     #0
        sta     vdp_n
        sty     vdp_n+1
        jmp     vdp_copy

; both layers blank, no sprites, no sway
cls:    lda     #<V_NAME1
        ldy     #>V_NAME1
        jsr     @clr
        lda     #<V_NAME2
        ldy     #>V_NAME2
        jsr     @clr
        lda     #0
        ldx     #27
        jsr     vdp_reg
        lda     #0
        sta     rv
        jmp     no_sprites
@clr:   jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #3
        sta     vdp_n+1
        lda     #0
        jmp     vdp_fill

; every sprite off (and their patterns forgotten)
no_sprites:
        ldx     #NOBJ-1
        lda     #$FF
@f:     sta     spr_ver,x
        dex
        bpl     @f
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        rts

; ---- pacing: speed video frames a frame (the ROM's 60 Hz counter) -----------
pace:   jsr     sfx_poll
        jsr     SBC_TICKS
        sec
        sbc     last_tick
        cmp     speed
        bcc     pace
        jsr     SBC_TICKS
        sta     last_tick
        rts

; ---- text: layer 2 names (the font's patterns = ASCII; + RED_FONT: red) -----
; the cursor to column X, row Y.  Preserves X and Y.
gotoxy: stx     cur_x
        sty     cur_y
        tya
        and     #7
        asl
        asl
        asl
        asl
        asl
        ora     cur_x
        pha
        tya
        lsr
        lsr
        lsr
        clc
        adc     #>V_NAME2
        tay
        pla
        jsr     vdp_waddr
        ldx     cur_x
        ldy     cur_y
        rts

txt_mode:
gfx_mode:
        rts

; a character at the cursor (red after RV_ON).  Preserves A, X, Y.
putc:   pha
        sta     pc_t
        lda     rv
        beq     @w
        lda     pc_t
        clc
        adc     #RED_FONT
        sta     pc_t
@w:     lda     pc_t
        sta     VDP_DATA
        inc     cur_x
        pla
        rts

; print the string at A (lo) / Y (hi), ended by TERM: characters, TC_ROW r,
; TC_COL c, RV_ON / RV_OFF (red)
print:  sta     @ld+1
        sty     @ld+2
@nx:    jsr     @ld
        cmp     #TERM
        beq     @done
        cmp     #TC_ROW
        bne     @2
        jsr     @ld
        sta     cur_y
        jmp     @nx
@2:     cmp     #TC_COL
        bne     @3
        jsr     @ld
        tax
        ldy     cur_y
        jsr     gotoxy
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
@done:  lda     #0
        sta     rv
        rts
@ld:    lda     $FFFF
        inc     @ld+1
        bne     :+
        inc     @ld+2
:       rts

; ---- the formation (layer 1) ---------------------------------------------------
; grid Y's place: tpx, tpy (wire).  Its sprite's screen x is fxs + 16 gx, y
; 24 + 16 gy: wire x = 32 + (fxs + 16 gx - 6) * 2 / 3, y = FM_Y + 8 gy
grid_xy:
        stx     gx_save
        lda     grid_gx,y
        asl
        asl
        asl
        asl
        clc
        adc     fxs
        sec
        sbc     #6
        tax
        lda     two3,x
        clc
        adc     #32
        sta     tpx
        lda     grid_gy,y
        asl
        asl
        asl
        adc     #FM_Y
        sta     tpy
        ldx     gx_save
        rts

; the tile code for grid Y as it is now: 0 nobody, else 1 + kind * 2 + wings
fm_tile:
        lda     fm,y
        cmp     #1
        bne     @blank
        lda     row_kind,y
        ldx     fhurt,y
        beq     @k
        lda     #T_HURT
@k:     asl
        ora     flap
        clc
        adc     #1
        rts
@blank: lda     #0
        rts

; draw grid Y's 2 x 2 cells (column FM_COL + 2 gx, row FM_ROW + 2 gy)
fm_draw_one:
        sty     tmp4
        stx     fd_x
        jsr     fm_tile
        jsr     fm_pats
        ldy     tmp4
        lda     grid_gy,y
        asl
        adc     #FM_ROW
        sta     fd_r
        lda     grid_gx,y
        asl
        adc     #FM_COL
        sta     fd_c
        jsr     fm_put
        ldy     tmp4
        ldx     fd_x
        rts

; tile code A -> its 4 patterns: fd_p (TL; TR = +1, BL +2, BR +3), or 0s
fm_pats:
        tax
        beq     @z
        dex
        txa
        asl
        asl
        clc
        adc     #FM_PAT0
@z:     sta     fd_p
        rts

; the 4 names at column fd_c, row fd_r (layer 1)
fm_put: ldy     fd_r            ; the top row: fd_p, fd_p + 1
        lda     fd_p
        jsr     @two
        ldy     fd_r            ; the bottom: fd_p + 2, + 3
        iny
        lda     fd_p
        beq     @two
        clc
        adc     #2
@two:   sta     fd_t
        tya                     ; V_NAME1 + row * 32 + column
        and     #7
        asl
        asl
        asl
        asl
        asl
        ora     fd_c
        pha
        tya
        lsr
        lsr
        lsr
        clc
        adc     #>V_NAME1
        tay
        pla
        jsr     vdp_waddr
        lda     fd_t
        sta     VDP_DATA
        beq     @w
        clc
        adc     #1
@w:     sta     VDP_DATA
        rts

; the whole formation again
fm_draw:
        ldy     #NGRID-1
@g:     jsr     fm_draw_one
        dey
        bpl     @g
        rts

; the sway: the hardware scroll
set_sway:
        lda     #8 * FM_COL
        sec
        sbc     fxs
        ldx     #27
        jmp     vdp_reg

; ---- the stars (layer 2) -------------------------------------------------------
; star X's cell: st_c, st_r and its pattern st_p (screen x = 8 + 1.5 x,
; y = 2 y)
star_cell:
        lda     st_x,x
        lsr
        sta     tmp
        lda     st_x,x
        clc
        adc     tmp             ; 1.5 x
        adc     #8
        sta     tmp2            ; screen x
        lsr
        lsr
        lsr
        sta     st_c
        lda     st_y,x
        asl
        sta     tmp3            ; screen y
        lsr
        lsr
        lsr
        sta     st_r
        lda     tmp3
        and     #6
        asl
        asl                     ; (y & 7) / 2 * 8
        sta     st_p
        lda     tmp2
        and     #7
        ora     st_p
        clc
        adc     #STAR_PAT0
        sta     st_p
        txa                     ; the slow ones (odd) dim
        and     #1
        beq     @r
        lda     st_p
        clc
        adc     #$20
        sta     st_p
@r:     rts

; star X on (A = 1) or off (A = 0)
star_put:
        pha
        jsr     star_cell
        stx     sti2
        ldx     st_c
        ldy     st_r
        jsr     gotoxy
        pla
        beq     @off
        lda     st_p
@off:   sta     VDP_DATA
        ldx     sti2
        rts

; carry set if star X's place is free (not near the formation, a message,
; or the status line)
star_free:
        jsr     star_cell
        lda     st_r
        beq     @no
        lda     msg_on
        beq     @nm
        lda     st_r
        cmp     #MSG_ROW-1
        bcc     @nm
        cmp     #MSG_ROW+2
        bcc     @no
@nm:    lda     chal
        bne     @yes
        lda     st_r
        cmp     #FM_ROW
        bcc     @yes
        cmp     #FM_ROW+10
        bcs     @yes
        lda     tmp2            ; its screen x against the formation's
        clc
        adc     #4
        bcs     @yes
        cmp     fxs
        bcc     @yes
        sec
        sbc     #168
        bcc     @no
        cmp     fxs
        bcc     @no
@yes:   sec
        rts
@no:    clc
        rts

; ---- the ships in reserve: rows 22-23 -------------------------------------------
draw_lives:
        lda     #0
        sta     tmp3
@l:     lda     #0              ; blank, or a ship
        sta     fd_t
        lda     tmp3
        clc
        adc     #1
        cmp     lives
        bcs     @t
        lda     #LIFE_PAT0
        sta     fd_t
@t:     lda     tmp3            ; column 2 n
        asl
        tax
        ldy     #22
        jsr     gotoxy
        lda     fd_t
        jsr     @two
        ldy     #23
        jsr     gotoxy
        lda     fd_t
        beq     :+
        clc
        adc     #2
:       jsr     @two
        inc     tmp3
        lda     tmp3
        cmp     #5
        bne     @l
        rts
@two:   sta     VDP_DATA
        beq     :+
        clc
        adc     #1
:       sta     VDP_DATA
        rts

; ---- the sprites --------------------------------------------------------------
; Sprite k shows object k (the ship: SL_SHIP), with picture spr_pic (its
; pattern loaded when it changes), at the screen place of the object's wire
; place: x = 1.5 (x - 32) + 8 - 2, y = 2 (y - 32), with half pixels.
put_sprites:
        ldx     #NOBJ-1
@o:     stx     si2
        cpx     #SL_SHIP
        bne     @obj
        jsr     ship_pic
        jmp     @have
@obj:   lda     o_kind,x
        bne     @k
@hide:  lda     #HIDE_Y
        sta     sat_y,x
        jmp     @n
@k:     cmp     #K_ALIEN
        beq     @al
        cmp     #K_EBUL
        bne     @nb
        lda     #PIC_EBUL
        bne     @pic
@nb:    cmp     #K_SHOT
        bne     @bm
        lda     #PIC_SHOT
        bne     @pic
@bm:    lda     o_t,x           ; an explosion: 4 frames of 4
        lsr
        lsr
        clc
        adc     #PIC_BOOM0
@pic:   sta     sp_pic
        lda     #0
        sta     sp_flip
        lda     o_x_hi,x
        sta     sp_xh
        lda     o_x_lo,x
        sta     sp_xl
        lda     o_y_hi,x
        sta     sp_yh
        lda     o_y_lo,x
        sta     sp_yl
        jmp     @have
@al:    ldy     o_home,x        ; an alien: its kind, wings, heading
        lda     o_type,x
        cpy     #NONE
        beq     @kk
        lda     fhurt,y
        beq     @k0
        lda     #T_HURT
        bne     @kk
@k0:    lda     o_type,x
@kk:    sta     tmp             ; kind * 18
        asl
        asl
        asl
        adc     tmp
        asl
        sta     tmp
        lda     frame           ; + wings * 9
        and     #8
        beq     @w
        lda     #9
@w:     clc
        adc     tmp
        sta     tmp
        lda     o_h,x           ; the nearest of 16 headings: 0-8 on the
        clc                     ; right, 9-15 the left (mirrored)
        adc     #2
        lsr
        lsr
        and     #15
        ldy     #0
        cmp     #9
        bcc     @r
        eor     #$FF            ; 16 - it
        sec
        adc     #16
        ldy     #SA_FLIPX
@r:     sty     sp_flip
        clc
        adc     tmp
        jmp     @pic
@have:  ldx     si2
        lda     sp_pic
        cmp     #$FF
        bne     :+
        jmp     @off
:       cmp     spr_ver,x       ; a new picture: its pattern
        beq     @pos
        sta     spr_ver,x
        jsr     load_pic
        ldx     si2
@pos:   ; x: 1.5 (x - 32) + 6: h = 2 x + half (9 bits), x = 3 h / 4 - 42
        lda     sp_xl
        asl                     ; (the half pixel)
        lda     sp_xh
        rol
        sta     tmp
        lda     #0
        rol
        sta     tmp2            ; h: tmp2:tmp
        lda     tmp             ; 3 h
        asl
        sta     tmp3
        lda     tmp2
        rol
        sta     tmp4
        lda     tmp3
        clc
        adc     tmp
        sta     tmp3
        lda     tmp4
        adc     tmp2
        lsr                     ; / 4
        ror     tmp3
        lsr
        ror     tmp3
        sta     tmp4            ; (0 or 1)
        lda     tmp3
        sec
        sbc     #42
        sta     tmp3
        lda     tmp4
        sbc     #0              ; tmp4:tmp3 = the screen x (signed 16)
        bmi     @neg
        bne     @off            ; 256 or more: off the screen
        lda     tmp3
        sta     sat_x,x
        lda     #0
        beq     @ec
@neg:   lda     tmp3            ; -32 .. -1: the early clock (32 left)
        cmp     #$E0
        bcc     @off
        adc     #32-1           ; (carry set)
        sta     sat_x,x
        lda     #SA_EC
@ec:    ora     sp_flip
        ldy     sp_pic
        ora     pic_ps,y
        sta     sat_c,x
        ; y: 2 (y - 32) + half - 1
        lda     sp_yl
        asl
        lda     sp_yh
        rol
        sta     tmp
        lda     #0
        rol
        sta     tmp2
        lda     tmp
        sec
        sbc     #65             ; (2 * 32 + 1)
        sta     tmp
        lda     tmp2
        sbc     #0
        bmi     @ny
        bne     @off            ; below the screen
        lda     tmp
        cmp     #191
        bcs     @off
        bcc     @y
@ny:    lda     tmp             ; above: -16 .. -1 still shows a part
        cmp     #$F0
        bcc     @off
@y:     sta     sat_y,x
        jmp     @n
@off:   lda     #HIDE_Y
        sta     sat_y,x
@n:     ldx     si2
        dex
        bmi     :+
        jmp     @o
:       ; the attribute table
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     #0
@s:     lda     sat_y,x
        sta     VDP_DATA
        lda     sat_x,x
        sta     VDP_DATA
        txa
        asl
        asl
        sta     VDP_DATA
        lda     sat_c,x
        sta     VDP_DATA
        inx
        cpx     #NOBJ
        bne     @s
        lda     #$D0
        sta     VDP_DATA
        rts

; the ship's picture (sp_pic: $FF none) and place
ship_pic:
        lda     #$FF
        sta     sp_pic
        lda     ship_st
        cmp     #2
        beq     @r              ; (gone)
        lda     #PIC_SHIP
        ldy     ship_st
        beq     @p
        lda     #36             ; blowing up: 3 pictures of 12 frames
        sec
        sbc     dead_t
        ldy     #0
@d:     cmp     #12
        bcc     @dd
        sbc     #12
        iny
        bne     @d
@dd:    tya
        clc
        adc     #PIC_PBOOM0
@p:     sta     sp_pic
        lda     #0
        sta     sp_flip
        sta     sp_xl
        sta     sp_yl
        lda     ship_x
        sta     sp_xh
        lda     #SHIP_Y
        sta     sp_yh
@r:     rts

; picture A into sprite X's pattern (both planes: 32 bytes each)
load_pic:
        tay
        lda     pic_lo,y
        sta     @a+1
        sta     @b+1
        lda     pic_hi,y
        sta     @a+2
        sta     @b+2
        txa                     ; V_SP0 / V_SP1 + 32 x
        lsr
        lsr
        lsr
        sta     tmp2
        txa
        asl
        asl
        asl
        asl
        asl
        sta     tmp
        lda     tmp2
        clc
        adc     #>V_SP0
        tay
        lda     tmp
        jsr     vdp_waddr
        ldx     #0
@a:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @a
        lda     tmp2
        clc
        adc     #>V_SP1
        tay
        lda     tmp
        jsr     vdp_waddr
@b:     lda     $FFFF,x         ; (x 32-63: plane 1's bytes)
        sta     VDP_DATA
        inx
        cpx     #64
        bne     @b
        rts

; a sprite for the title: picture A as sprite X at screen x tmp3, y tmp4
title_spr:
        sta     sp_pic
        sta     spr_ver,x
        stx     si2
        jsr     load_pic
        ldx     si2
        lda     tmp3
        sta     sat_x,x
        lda     tmp4
        sta     sat_y,x
        ldy     sp_pic
        lda     pic_ps,y
        sta     sat_c,x
        rts

; the title's sprites, from sat_*: X of them
title_sat:
        stx     tmp
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     #0
@s:     lda     sat_y,x
        sta     VDP_DATA
        lda     sat_x,x
        sta     VDP_DATA
        txa
        asl
        asl
        sta     VDP_DATA
        lda     sat_c,x
        sta     VDP_DATA
        inx
        cpx     tmp
        bne     @s
        lda     #$D0
        sta     VDP_DATA
        rts

; ---- VDP registers ---------------------------------------------------------------
; R0-R7: Graphics I, display off (gfx_init turns it on), 16 x 16 sprites;
; tile patterns $0000 (plane 1 $0800), layer 1 names $2000, its attributes
; $2400, sprite attributes $2600, sprite patterns $1000 (plane 1 $1800);
; backdrop black
vdp_regs:
        .byte   $00, $82, V_NAME1 / $400, V_ATT1 / $40, V_TP0 / $800, V_SATTR / $80, V_SP0 / $800, $01
; the F18A's: register, value
f18a_regs:
        .byte   10, V_NAME2 / $400      ; layer 2 names
        .byte   11, V_ATT2 / $40        ; layer 2 attributes
        .byte   24, 0                   ; palette selects (ECM: unused)
        .byte   29, 0                   ; 2K plane offsets, 1 page
        .byte   25, 0                   ; layer 2: no scroll
        .byte   26, 0
        .byte   27, 0                   ; layer 1: the sway
        .byte   28, 0
        .byte   30, 31                  ; 31 sprites a line
        .byte   50, $01                 ; layer 2 under the sprites (by priority)
        .byte   49, $A2                 ; layer 2 on, ECM2 tiles, ECM2 sprites
F18A_N          = (* - f18a_regs) / 2

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
grid_gx:
        .repeat NGRID, K
        .byte   K .mod 10
        .endrepeat
grid_gy:
        .repeat NGRID, K
        .byte   K / 10
        .endrepeat
row_kind:                       ; each place's kind
        .repeat 10
        .byte   T_BOSS
        .endrepeat
        .repeat 20
        .byte   T_BFLY
        .endrepeat
        .repeat 20
        .byte   T_BEE
        .endrepeat
row_first:.byte 3, 11, 21, 30, 40       ; each row's places: the first, how many
row_n:  .byte   4, 8, 8, 10, 10
row_c0: .byte   18, 6, 6, 0, 0          ; ... their columns from fx: from, to
row_c1: .byte   42, 54, 54, 60, 60
; points (BCD): in the formation, in flight
pts_lo_f:.byte  $50, $80, $50
pts_hi_f:.byte  $00, $00, $01
pts_lo_d:.byte  $00, $60, $00
pts_hi_d:.byte  $01, $01, $04
hit_snd:.byte   SND_HIT, SND_HIT, SND_BOSSDIE
; the 8 headings: picture (up, up-right, right, down-right, down) and mirror
dir_pic:.byte   0, 1, 2, 3, 4, 3, 2, 1
dir_flip:.byte  0, 0, 0, 0, 0, 1, 1, 1
; coming in: each group's path, and the places in order (pairs: the left
; one, then its mirror image on the right)
grp_path:.byte  PATH_TOP, PATH_SIDE, PATH_SIDE, PATH_TOP, PATH_SIDE
entry_order:
        .byte   14, 15, 34, 35, 24, 25, 44, 45
        .byte   3, 6, 13, 16, 4, 5, 23, 26
        .byte   11, 18, 12, 17, 21, 28, 22, 27
        .byte   33, 36, 43, 46, 32, 37, 42, 47
        .byte   30, 39, 31, 38, 40, 49, 41, 48
chal_path:.byte PATH_B_LOOP, PATH_B_WAVE, PATH_B_DIP, PATH_B_ARC
chal_kind:.byte T_BEE, T_BFLY, T_BOSS, T_BFLY, T_BEE
title_pic:.byte PIC_ALIEN + 8, PIC_ALIEN + 18 + 8, PIC_ALIEN + 36 + 8    ; facing down
title_y:.byte   9 * 8 - 5, 12 * 8 - 5, 15 * 8 - 5

need_txt:
        .byte   13, 10, "SWARM NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
title_txt:
        .byte   TC_ROW, 2, TC_COL, 11, RV_ON, "S W A R M", RV_OFF
        .byte   TC_ROW, 4, TC_COL, 1, "THE SWARM FLIES IN, TAKES ITS"
        .byte   TC_ROW, 5, TC_COL, 1, "PLACES AND DIVES. SHOOT THEM"
        .byte   TC_ROW, 6, TC_COL, 1, "ALL. BOSSES TAKE TWO HITS."
        .byte   TC_ROW, 9, TC_COL, 10, " 50  IN FLIGHT 100"
        .byte   TC_ROW, 12, TC_COL, 10, " 80  IN FLIGHT 160"
        .byte   TC_ROW, 15, TC_COL, 10, "150  IN FLIGHT 400"
        .byte   TC_ROW, 22, TC_COL, 0, "EVERY THIRD STAGE: A CHALLENGE"
        .byte   TC_ROW, 23, TC_COL, 0, RV_ON, "SPACE OR START: PLAY   Q: QUIT", RV_OFF, TERM
hi_txt: .byte   "HIGH SCORE ", TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, RV_ON, "1UP", TC_COL, 11, "HIGH", TC_COL, 23, "STAGE", RV_OFF, TERM
stage_txt:
        .byte   TC_ROW, MSG_ROW, TC_COL, 12, "STAGE ", TERM
chal_txt:
        .byte   TC_COL, 7, RV_ON, "CHALLENGING STAGE", RV_OFF, TERM
ready_txt:
        .byte   TC_ROW, MSG_ROW, TC_COL, 13, "READY", TERM
unmsg_txt:
        .byte   TC_ROW, MSG_ROW, TC_COL, 2, "                            ", TERM
hits_txt:
        .byte   TC_ROW, MSG_ROW - 1, TC_COL, 7, "NUMBER OF HITS  ", TERM
bonus_txt:
        .byte   TC_ROW, MSG_ROW + 1, TC_COL, 7, "BONUS           ", TERM
perfect_txt:
        .byte   TC_ROW, MSG_ROW + 1, TC_COL, 7, RV_ON, "PERFECT!   10000", RV_OFF, TERM
paused_txt:
        .byte   RV_ON, "PAUSED", RV_OFF, TERM
unpaused_txt:
        .byte   "      ", TERM
over_txt:
        .byte   TC_ROW, 13, TC_COL, 11, RV_ON, "GAME  OVER", RV_OFF
        .byte   TC_ROW, 16, TC_COL, 9, "SPACE/A: AGAIN"
        .byte   TC_ROW, 17, TC_COL, 9, "Q: TITLE", TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD (G: KEYBOARD)", TERM

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
esc_st:     .res 1
quit:       .res 1
frame:      .res 1
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3              ; (right after score: prscore)
lives:      .res 1
stage:      .res 1
n_norm:     .res 1              ; normal stages played
chal:       .res 1              ; this is a challenging stage
hits:       .res 1              ; ... and its aliens hit
left:       .res 1              ; aliens of this stage still to go
extra1:     .res 1
extra2:     .res 1
hud_dirty:  .res 1
msg_on:     .res 1
msg_t:      .res 1
fire:       .res 1              ; this frame's controls
mv:         .res 1
mv_dir:     .res 1
mv_hold:    .res 1
ship_x:     .res 1
ship_st:    .res 1              ; 0 playing, 1 blowing up, 2 gone
dead_t:     .res 1
fly_sp:     .res 1              ; this stage: the aliens' speed
max_div:    .res 1              ;   how many may be in flight at once
dive_gap:   .res 1              ;   frames between dives
div_shots:  .res 1              ;   shots each diver fires
dive_t:     .res 1
dv_g:       .res 1
dv_p:       .res 1
dv_n:       .res 1
dv_k:       .res 1
esc_on:     .res 1              ; take_off: an escort (keeps mir)
ent_g:      .res 1              ; coming in: the group (5: all in)
ent_i:      .res 1              ;   the next of its 8
ent_t:      .res 1
ent_p:      .res 1
ent_h1:     .res 1
ent_h2:     .res 1
ent_x2:     .res 1
mir:        .res 1
fxs:        .res 1              ; the formation: its screen x (column 0)
fdir:       .res 1              ;   which way it sways (1, -1)
sway_t:     .res 1
flap:       .res 1              ;   its wings (0, 1)
fm:         .res NGRID          ; each place: 0 nobody, 1 there, 2 in flight
fhurt:      .res NGRID          ; a boss there was hit once
dr_r:       .res 1
dr_i:       .res 1
dr_cnt:     .res 1
dr_n:       .res 1
dr_t:       .res 1
boom_i:     .res 1
st_x:       .res NSTAR          ; the stars (pixels)
st_y:       .res NSTAR
st_on:      .res NSTAR          ;   drawn
sti:        .res 1
o_kind:     .res NOBJ           ; the objects (each its sprite slot)
o_x_lo:     .res NOBJ
o_x_hi:     .res NOBJ
o_y_lo:     .res NOBJ
o_y_hi:     .res NOBJ
o_vx_lo:    .res NOBJ           ; (bullets)
o_vx_hi:    .res NOBJ
o_h:        .res NOBJ           ; (aliens) heading
o_sp:       .res NOBJ           ;   speed
o_type:     .res NOBJ           ;   kind
o_home:     .res NOBJ           ;   its place in the formation (NONE)
o_mode:     .res NOBJ
o_path:     .res NOBJ
o_pp:       .res NOBJ           ;   where in its path
o_pt:       .res NOBJ           ;   frames left of this piece
o_turn:     .res NOBJ
o_mir:      .res NOBJ
o_fire:     .res NOBJ           ;   shots left
o_fy:       .res NOBJ           ;   ... the next at this y
o_t:        .res NOBJ           ; (explosions: frames; aliens: frames going home)
hs_i:       .res 1
si:         .res 1
fi:         .res 1
tpx:        .res 1
tpy:        .res 1
a_dx:       .res 1
a_dxh:      .res 1
a_dy:       .res 1
a_dyh:      .res 1
a_far:      .res 1
at_w:       .res 1
at_a:       .res 1
at_b:       .res 1
fr_d:       .res 1
fr_q:       .res 1
v_s:        .res 1
v_lo:       .res 1
v_hi:       .res 1
m_a:        .res 1
m_b:        .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
; the display
last_tick:  .res 1
cur_x:      .res 1              ; text
cur_y:      .res 1
rv:         .res 1
pc_t:       .res 1
gx_save:    .res 1
fd_x:       .res 1              ; the formation's names
fd_r:       .res 1
fd_c:       .res 1
fd_p:       .res 1
fd_t:       .res 1
st_c:       .res 1              ; a star's cell
st_r:       .res 1
st_p:       .res 1
sti2:       .res 1
si2:        .res 1              ; the sprites
sp_pic:     .res 1
sp_flip:    .res 1
sp_xh:      .res 1
sp_xl:      .res 1
sp_yh:      .res 1
sp_yl:      .res 1
spr_ver:    .res NOBJ           ; each sprite's picture now
sat_y:      .res NOBJ
sat_x:      .res NOBJ
sat_c:      .res NOBJ
bss_end:
