; ============================================================================
; breaker.s - BYTE BREAKER for the 6502 SBC, CPU Rev2, on the PICO9918 card
;
;   build:  make.bat (make.bat 4 for a 4 MHz clock)
;   run:    L BREAKER 0800   then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  video frames (1/60 s) a game frame takes: 2 (30 a second)
;   $0804  controls at start: 0 keyboard, 1 gamepad
;   $0805  sound at start: 0 on, 1 off (M switches)
;
; The game is the PIC32 terminal version's, unchanged: it still plays in
; the terminal's 160 x 96 pixels.  What is new is the drawing: the PICO9918
; in Graphics II used as tiles (each third its own patterns and colours).
; A game pixel is 1.5 x 2 screen pixels (x = 8 + 1.5 x, y = 2 y), so a text
; row is a tile row: the bricks are tiles (gen_pico.py), the paddle, balls,
; capsules and shots are sprites, rebuilt every frame.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 2             ; video frames (1/60 s) a game frame

; ---- text (print) ----------------------------------------------------------------
TC_COL          = $0E           ; print: the next byte is the column
TC_ROW          = $0F           ;   ... the row
TERM            = $FF
.define RV_ON   $11             ;   highlighted text from here (white on blue)
.define RV_OFF  $12
P_HI            = $A0           ; highlighted characters: + $A0 (patterns $C0-$FF)
P_BALL_ICON     = $06

; ---- VRAM (Graphics II as tiles: each third its own patterns and colours) --
V_PAT           = $0000
V_COL           = $2000
V_SPAT          = $1800         ; sprite patterns
V_NAME          = $3800
V_SATTR         = $3B00
VDP_NAME        = V_NAME

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
        .include "breaker_gfx.inc"      ; the PICO9918 graphics (gen_pico.py)

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

; called by vdp_frame while it waits
frame_idle:
        jsr     sfx_poll
        jmp     rand

; a character (a name) at the cursor; highlighted after RV_ON.  Keeps A, X, Y.
putc:   pha
        clc
        adc     rv
        sta     VDP_DATA
        pla
        rts

; the cursor to column X, row Y.  Keeps X and Y.
gotoxy: stx     cur_col
        sty     cur_row
        jmp     vdp_at

txt_mode:
gfx_mode:
        rts

; print the string at A (lo) / Y (hi), ended by TERM: characters, and
; TC_ROW r, TC_COL c (the cursor), RV_ON / RV_OFF
print:  sta     @ld+1
        sty     @ld+2
@nx:    jsr     @ld
        cmp     #TERM
        beq     @done
        cmp     #TC_ROW
        bne     @c
        jsr     @ld
        sta     cur_row
        jmp     @at
@c:     cmp     #TC_COL
        bne     @rv
        jsr     @ld
        sta     cur_col
@at:    stx     pr_x
        sty     pr_y
        ldx     cur_col
        ldy     cur_row
        jsr     vdp_at
        ldx     pr_x
        ldy     pr_y
        jmp     @nx
@rv:    cmp     #RV_ON
        bne     @off
        lda     #P_HI
        sta     rv
        bne     @nx
@off:   cmp     #RV_OFF
        bne     @ch
        lda     #0
        sta     rv
        beq     @nx
@ch:    jsr     putc
        jmp     @nx
@done:  lda     #0
        sta     rv
        rts
@ld:    lda     $FFFF           ; the next byte
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
CTRL_COL        = 1
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
        lda     #0
        sta     rp_on
        jsr     new_screen
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     txt_mode        ; the high score
        ldx     #7
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
        jsr     title_sprites   ; the capsules beside their words
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
        jsr     SBC_CONRESET    ; the console's text screen back
        jmp     SBC_MENU

; clear the screen (which hides the sprites) and forget what it showed
new_screen:
        lda     #<V_NAME        ; every name blank
        ldy     #>V_NAME
        jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #3
        sta     vdp_n+1
        lda     #0
        sta     rv
        jsr     vdp_fill
        ; fall through

; no sprites
hide_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        rts

; ============================================================================
; the display
; ============================================================================
; set up the VDP: registers, then the load list (patterns, colours, sprites)
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (VRAM cleared)
        lda     #0
        sta     ll_i
@e:     ldx     ll_i            ; entry: VRAM address, length, source (a
        lda     load_list+1,x   ; source below $0100: fill with that byte)
        cmp     #$FF
        beq     @done
        tay
        lda     load_list,x
        jsr     vdp_waddr
        lda     load_list+2,x
        sta     vdp_n
        lda     load_list+3,x
        sta     vdp_n+1
        lda     load_list+5,x
        beq     @fill
        sta     vdp_src+1
        lda     load_list+4,x
        sta     vdp_src
        jsr     vdp_copy
        jmp     @nx
@fill:  lda     load_list+4,x
        jsr     vdp_fill
@nx:    lda     ll_i
        clc
        adc     #6
        sta     ll_i
        jmp     @e
@done:  lda     #$C2            ; R1: display on, 16K, 16 x 16 sprites, and
        ldx     #1              ; bit 5 (the VDP interrupt) off
        jmp     vdp_reg

; the sprite list: add one (sp_x, sp_y = the Y register, sp_p, sp_c)
spr_add:
        ldy     sp_n
        cpy     #32
        bcs     @r
        tya
        asl
        asl
        tay
        lda     sp_y
        sta     satt,y
        lda     sp_x
        sta     satt+1,y
        lda     sp_p
        sta     satt+2,y
        lda     sp_c
        sta     satt+3,y
        inc     sp_n
@r:     rts

; the sprite list onto the screen
put_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     sp_n
        asl
        asl
        tax
        beq     @end            ; (X bytes)
        ldy     #0
@l:     lda     satt,y
        sta     VDP_DATA
        iny
        dex
        bne     @l
@end:   lda     sp_n
        cmp     #32
        bcs     @r
        lda     #$D0            ; (the end of the list)
        sta     VDP_DATA
@r:     rts

; the title's capsules beside their words
title_sprites:
        lda     #0
        sta     sp_n
        ldx     #NCAPTYPE-1
@c:     stx     sp_i
        lda     title_cx,x
        sta     sp_x
        lda     title_cy,x
        sta     sp_y
        txa
        asl
        asl
        adc     #S_SIGN_W
        sta     sp_p
        lda     #C_SIGN
        sta     sp_c
        jsr     spr_add
        ldx     sp_i
        lda     #S_CAP
        sta     sp_p
        lda     cap_col,x
        sta     sp_c
        jsr     spr_add
        ldx     sp_i
        dex
        bpl     @c
        jmp     put_sprites

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
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     move_paddle
        jsr     launch
        jsr     balls_update
        jsr     caps_update
        jsr     shots_update
        jsr     set_sprites     ; the sprite list ...
        jsr     pace            ; ... onto the screen when the frame is up
        jsr     hud_update
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

; the game's pace: speed video frames a game frame (the sound goes on
; meanwhile), then the sprites
pace:   lda     speed
        sta     wf_n
@w:     jsr     vdp_frame
        dec     wf_n
        bne     @w
        jmp     put_sprites

life_lost:
        lda     #SND_LOST
        jsr     sfx_snd
        jsr     hide_sprites    ; (the sprites go)
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
        jsr     hide_sprites
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
        ldx     #0              ; the top: row 1
        ldy     #1
        jsr     gotoxy
        lda     #2
        sta     VDP_DATA
        ldx     #30
        lda     #1
@t:     sta     VDP_DATA
        dex
        bne     @t
        lda     #3
        sta     VDP_DATA
        ldy     #2              ; the sides: columns 0 and 31, rows 2-23
@s:     ldx     #0
        jsr     gotoxy
        lda     #2
        sta     VDP_DATA
        ldx     #31
        jsr     gotoxy
        lda     #3
        sta     VDP_DATA
        iny
        cpy     #24
        bne     @s
        rts

; every brick row, tile columns 1-30
draw_bricks:
        lda     #0
        sta     br_r
@r:     lda     br_r
        clc
        adc     #BRICK_Y / 4
        tay
        ldx     #1
        jsr     gotoxy
        lda     #1
        sta     br_t
@t:     jsr     tile_name
        sta     VDP_DATA
        inc     br_t
        lda     br_t
        cmp     #31
        bne     @t
        inc     br_r
        lda     br_r
        cmp     #BH
        bne     @r
        rts

; draw brick bidx as map says: its two tiles (brick c: tiles 1 + 3 (c / 2)
; + 2 (c & 1) and the next)
draw_brick:
        ldx     bidx
        lda     b_row,x
        sta     br_r
        lda     b_col,x
        pha
        lsr
        sta     tmp
        asl
        adc     tmp             ; 3 * (c / 2)
        sta     tmp
        pla
        and     #1
        asl
        sec                     ; + 1
        adc     tmp
        sta     br_t
        jsr     draw_tile
        inc     br_t
draw_tile:
        lda     br_r
        clc
        adc     #BRICK_Y / 4
        tay
        ldx     br_t
        jsr     gotoxy
        jsr     tile_name
        sta     VDP_DATA
        rts

; A = the name of tile column br_t in brick row br_r: from the kinds of the
; (up to two) bricks in it (gen_pico.py: tc_phase, tc_a, tc_b, brick_names)
tile_name:
        ldx     br_t
        lda     tc_phase,x
        sta     tn_i
        ldy     br_r
        lda     row_off,y
        sta     tn_o
        lda     tc_a,x
        bmi     @na
        clc
        adc     tn_o
        tay
        lda     map,y
        asl
        asl
        ora     tn_i
        sta     tn_i
@na:    lda     tc_b,x
        bmi     @nb
        clc
        adc     tn_o
        tay
        lda     map,y
        ora     tn_i
        sta     tn_i
@nb:    ldy     tn_i
        lda     brick_names,y
        cmp     #$FF
        beq     @blank
        ldy     br_r
        clc
        adc     row_base,y
        rts
@blank: lda     #0
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
        ldx     #16
        ldy     #0
        jsr     gotoxy
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jsr     prbcd
        ldx     #25
        ldy     #0
        jsr     gotoxy
        lda     lives
        ora     #'0'
        jsr     putc
        ldx     #30
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
        jsr     read_pad        ; (any gamepad button: gamepad mode)
        lda     pad
        beq     @nsw
        lda     #1
        sta     ctrl
@nsw:   lda     ctrl
        beq     @keys
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
@np:    cmp     #KEY_LEFT       ; the AVR keyboard's arrow keys
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
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
; the sprites: the list is made again every frame (balls on top, then the
; shots, the capsules, the paddle), and put_sprites sends it
; ============================================================================
; game x -> screen x (8 + x * 1.5)
scr_x:  sta     tmp2
        lsr
        clc
        adc     tmp2
        adc     #8
        rts
; game y -> the sprite's Y register (2y - 1); carry set: off the bottom
scr_y:  cmp     #96
        bcs     @r
        asl
        sec
        sbc     #1
        clc
@r:     rts

set_sprites:
        lda     #0
        sta     sp_n
        lda     #C_BALL         ; the balls
        sta     sp_c
        lda     #S_BALL
        sta     sp_p
        ldx     #NBALL-1
@b:     stx     sp_i
        lda     b_on,x
        beq     @bn
        lda     b_xh,x
        jsr     scr_x
        sta     sp_x
        lda     b_yh,x
        jsr     scr_y
        bcs     @bn
        sta     sp_y
        jsr     spr_add
@bn:    ldx     sp_i
        dex
        bpl     @b
        lda     #C_SHOT         ; the shots
        sta     sp_c
        lda     #S_SHOT
        sta     sp_p
        ldx     #NSHOT-1
@s:     stx     sp_i
        lda     s_on,x
        beq     @sn
        lda     s_x,x
        jsr     scr_x
        sta     sp_x
        lda     s_y,x
        jsr     scr_y
        bcs     @sn
        sta     sp_y
        jsr     spr_add
@sn:    ldx     sp_i
        dex
        bpl     @s
        ldx     #NCAP-1         ; the capsules: the sign, then the pill
@k:     stx     sp_i
        lda     c_on,x
        beq     @kn
        lda     c_x,x
        jsr     scr_x
        sta     sp_x
        lda     c_yh,x
        jsr     scr_y
        bcs     @kn
        sta     sp_y
        lda     c_kind,x
        asl
        asl
        adc     #S_SIGN_W
        sta     sp_p
        lda     #C_SIGN
        sta     sp_c
        jsr     spr_add
        ldx     sp_i
        lda     #S_CAP
        sta     sp_p
        ldy     c_kind,x
        lda     cap_col,y
        sta     sp_c
        jsr     spr_add
@kn:    ldx     sp_i
        dex
        bpl     @k
        ; the paddle: its ends (colour by power), then its body, in 16
        ; pixel parts
        ldx     pw
        lda     pad_parts,x
        sta     sp_i
        lda     pad_ends,x
        sta     sp_p
        lda     end_col,x
        sta     sp_c
        jsr     @pad
        ldx     pw
        lda     pad_body,x
        sta     sp_p
        lda     #C_PAD
        sta     sp_c
@pad:   lda     #PAD_Y
        jsr     scr_y
        sta     sp_y
        lda     pad_x
        jsr     scr_x
        sta     sp_x
        lda     sp_i
        sta     tmp3
@pp:    jsr     spr_add
        lda     sp_x
        clc
        adc     #16
        sta     sp_x
        lda     sp_p
        clc
        adc     #4
        sta     sp_p
        dec     tmp3
        bne     @pp
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
pad_parts:.byte 2, 3, 2, 2      ; the paddle by power: 16 pixel parts,
pad_ends:.byte  S_PADE0, S_WIDEE0, S_LASE0, S_PADE0     ; ends, body
pad_body:.byte  S_PAD0, S_WIDE0, S_LAS0, S_PAD0
title_cx:.byte  8, 136, 8, 136, 8, 136                  ; the title's capsules
title_cy:.byte  94, 94, 110, 110, 126, 126               ; (rows 12, 14, 16)

; the display: R0-R7 (Graphics II: patterns $0000, colours $2000, names
; $3800, sprite attributes $3B00, sprite patterns $1800; display off; black)
vdp_regs:
        .byte   $02, $82, V_NAME / $400, $FF, $03, V_SATTR / $80, V_SPAT / $800, $01

; the load list: VRAM address, length, source (or a fill byte below $0100)
.macro LOAD vram, len, src
        .word   vram, len, src
.endmacro
load_list:
.repeat 3, T
        LOAD    V_PAT + T * $800 + $20 * 8, 64 * 8, font
        LOAD    V_COL + T * $800 + $20 * 8, 64 * 8, $F1
        LOAD    V_PAT + T * $800 + 8, 24, wall_pats
        LOAD    V_COL + T * $800 + 8, 24, wall_cols
        LOAD    V_PAT + T * $800 + P_BALL_ICON * 8, 8, ball_icon
        LOAD    V_COL + T * $800 + P_BALL_ICON * 8, 8, $F1
.endrepeat
.repeat 2, K                    ; the highlighted font: thirds 0 and 2
        LOAD    V_PAT + K * $1000 + $C0 * 8, 64 * 8, font
        LOAD    V_COL + K * $1000 + $C0 * 8, 64 * 8, $F4
.endrepeat
        LOAD    V_PAT + P_BRICK * 8, BRICKS0_LEN, bricks0_pat
        LOAD    V_COL + P_BRICK * 8, BRICKS0_LEN, bricks0_col
        LOAD    V_PAT + $800 + P_BRICK * 8, BRICKS1_LEN, bricks1_pat
        LOAD    V_COL + $800 + P_BRICK * 8, BRICKS1_LEN, bricks1_col
        LOAD    V_SPAT, SPR_PATS_LEN, spr_pats
        LOAD    V_SATTR, 1, $D0
        .word   $FF00

need_txt:
        .byte   13, 10, "BYTE BREAKER NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
title_txt:
        .byte   TC_ROW, 2, TC_COL, 8, RV_ON, " BYTE  BREAKER ", RV_OFF
        .byte   TC_ROW, 4, TC_COL, 1, "KNOCK OUT EVERY BRICK WITH THE"
        .byte   TC_ROW, 5, TC_COL, 1, "BALL, AND DON'T LET IT FALL."
        .byte   TC_ROW, 7, TC_COL, 1, "OUTLINED BRICKS TAKE TWO HITS,"
        .byte   TC_ROW, 8, TC_COL, 1, "CHECKED ONES NEVER BREAK."
        .byte   TC_ROW, 10, TC_COL, 1, "CATCH THE CAPSULES THAT FALL:"
        .byte   TC_ROW, 12, TC_COL, 3, "WIDE PADDLE"
        .byte   TC_COL, 19, "THREE BALLS"
        .byte   TC_ROW, 14, TC_COL, 3, "SLOWER BALL"
        .byte   TC_COL, 19, "LASER: FIRE"
        .byte   TC_ROW, 16, TC_COL, 3, "CATCH BALL"
        .byte   TC_COL, 19, "EXTRA BALL"
        .byte   TC_ROW, 22, TC_COL, 1, "SPACE/START: PLAY"
        .byte   TC_ROW, 23, TC_COL, 1, "M: SOUND ON/OFF   Q: QUIT", TERM
hi_txt: .byte   "HIGH SCORE ", TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "SCORE"
        .byte   TC_COL, 13, "HI"
        .byte   TC_COL, 24, P_BALL_ICON
        .byte   TC_COL, 27, "LV", TERM
ready_txt:
        .byte   TC_ROW, 16, TC_COL, 12, "LEVEL ", TERM
unready_txt:
        .byte   TC_ROW, 16, TC_COL, 12, "        ", TERM
clear_txt:
        .byte   TC_ROW, 16, TC_COL, 8, RV_ON, " LEVEL CLEARED ", RV_OFF, TERM
paused_txt:
        .byte   TC_ROW, 16, TC_COL, 12, RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   TC_ROW, 16, TC_COL, 12, "        ", TERM
over_txt:
        .byte   TC_ROW, 16, TC_COL, 7, RV_ON, "                  "
        .byte   TC_ROW, 17, TC_COL, 7, "    GAME  OVER    "
        .byte   TC_ROW, 18, TC_COL, 7, "                  "
        .byte   TC_ROW, 19, TC_COL, 7, " SPACE/A: AGAIN   "
        .byte   TC_ROW, 20, TC_COL, 7, " Q: TITLE         "
        .byte   TC_ROW, 21, TC_COL, 7, "                  ", RV_OFF, TERM
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
rv:         .res 1              ; print: 0, or P_HI (highlighted)
cur_col:    .res 1
cur_row:    .res 1
pr_x:       .res 1
pr_y:       .res 1
wf_n:       .res 1
ll_i:       .res 1
br_r:       .res 1              ; draw_tile: brick row, tile column
br_t:       .res 1
tn_i:       .res 1
tn_o:       .res 1
sp_n:       .res 1              ; the sprite list: how many, the next one's
sp_x:       .res 1              ;   place, pattern and colour
sp_y:       .res 1
sp_p:       .res 1
sp_c:       .res 1
sp_i:       .res 1
satt:       .res 128
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
bss_end:
