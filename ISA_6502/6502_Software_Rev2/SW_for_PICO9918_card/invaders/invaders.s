; ============================================================================
; invaders.s - a Space Invaders style game for the 6502 SBC, CPU Rev2,
;              on the PICO9918 card (TMS9918A Graphics I mode and sprites)
;
;   build:  make.bat  (ca65 -I .. invaders.s, ld65 -C invaders.cfg)
;   run:    L INVADERS 0800    then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  speed      frames per game tick: 1 = full speed (60 a second),
;                     2 = half speed ...
;   $0804  controls   at start: 0 keyboard, 1 gamepad (G on the title
;                     screen switches; A or Start on the pad picks the pad)
;   $0805  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card, through ../ay/sfx.s (timed by the VIA's timer 2).
;
; Keys:  A / D, , / . or the arrow keys  move (S or down: stop)
;        SPACE or W                     fire
;        P pause, M sound on / off, Q quit (back to the boot menu)
; Gamepad: left / right move, A or B fire, Start pause
;
; The screen (256 x 192, 32 x 24 cells of 8 x 8):
;   row 0      the status line (text)
;   y 12       the saucer (a sprite)
;   rows 3-    the invaders: name table cells.  Each invader has a 24 pixel
;              cell (3 patterns); the patterns come in 4 positions, 0, 2,
;              4 and 6 pixels to the right, so a row moves 2 pixels at a
;              time and is redrawn with one line of names.
;   rows 18-19 the shields: 4 x 6 patterns of their own, worn away pixel by
;              pixel (the game keeps a copy of each in RAM)
;   y 168      the cannon (a sprite);  y 180  the ground
; Sprites: 0 cannon, 1 shot, 2-4 bombs, 5 saucer, 6 explosion.
;
; Timing: one game tick per frame (the VDP's frame flag, polled).
; No zero page is used, so EhBASIC's and the BIOS's zero page are untouched.
; ============================================================================

        .setcpu "6502"

        .include "sbc_api.inc"  ; fixed ROM entry points ($FE00 table)

; ---- VRAM layout (Graphics I) -----------------------------------------------
V_PAT           = $0000         ; patterns
V_NAME          = $1800         ; names (32 x 24)
V_SATTR         = $1B00         ; sprite attributes
V_COLOUR        = $2000         ; colours (32 groups of 8 patterns)
V_SPAT          = $3800         ; sprite patterns
VDP_NAME        = V_NAME

; patterns
P_BLANK         = $00
P_SHIELD        = $60           ; 4 x 6
P_GROUND        = $78
P_LIFE          = $79           ; 2 side by side
P_INV           = $80           ; kind * 24 + frame * 12 + position * 3
; sprite patterns (16 x 16: 4 each)
SP_CANNON       = 0
SP_SHOT         = 4
SP_BOMB         = 8             ; and 12
SP_SAUCER       = 16
SP_EXPL         = 20
SP_PEXPL        = 24            ; and 28
; sprite slots
S_CANNON        = 0
S_SHOT          = 1
S_BOMB          = 2             ; 2-4
S_SAUCER        = 5
S_EXPL          = 6
NSPR            = 7
HIDE_Y          = $C0           ; a sprite's Y that puts it below the screen
; colours
C_CANNON        = 3             ; light green
C_SHOT          = 15            ; white
C_BOMB          = 15
C_SAUCER        = 8             ; red
C_EXPL          = 15

; ---- the layout ----------------------------------------------------------
NROWS           = 5
NCOLS           = 8
CELL            = 24            ; pixels from one invader to the next
FORM_C          = 3             ; starting cell column of the formation
FORM_TOP        = 3             ; starting cell row of the top invader row
SHIELD_ROW      = 18
SHIELD_Y        = SHIELD_ROW*8
PLAYER_Y        = 168
PLAYER_ROW      = PLAYER_Y/8    ; 21
GROUND_ROW      = 22
GROUND_Y        = GROUND_ROW*8+4
UFO_Y           = 12
PX_MIN          = 4             ; the cannon sprite's x range
PX_MAX          = 238
PX_START        = 120
EDGE_L          = 4             ; the formation turns at these pixels
EDGE_R          = 251
KEY_HOLD        = 7             ; frames a direction key keeps moving (the
                                ; keyboard's auto-repeat comes every ~5)

; ============================================================================
        .segment "CODE"

        jmp     start
speed:  .byte   1
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

        .include "ay/sfx.s"     ; sound effects on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines

getc            = SBC_CHRIN     ; carry set = key in A

; called by vdp_frame while it waits
frame_idle:
        jsr     sfx_poll
        jmp     rand

; 16 bit Galois LFSR.  Returns a random byte in A.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait A frames (keys pressed meanwhile are dropped)
wait_frames:
        sta     wf_n
@l:     jsr     vdp_frame
        jsr     put_sprites
        jsr     flush_in
        dec     wf_n
        bne     @l
        rts

; ============================================================================
; gamepad and menu input (as in the other SBC games)
; ============================================================================
PAD_A           = $01
PAD_B           = $02
PAD_SELECT      = $04
PAD_START       = $08
PAD_UP          = $10
PAD_DOWN        = $20
PAD_LEFT        = $40
PAD_RIGHT       = $80
PAD_GO          = $80           ; menu_key's answer for gamepad A or Start

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

flush_in:
        jsr     getc
        bcs     flush_in
        rts

; carry set if A is a character the gamepad driver types (W A S D space)
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

; wait for a menu choice: a key (letters in upper case) or PAD_GO
menu_key:
@l:     jsr     vdp_frame
        jsr     put_sprites
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
@pad:   jsr     flush_in
        lda     #PAD_GO
        rts

; ============================================================================
; start
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear all variables
        tax
@clr:   sta     vars_start,x
        sta     vars_start+$100,x
        inx
        bne     @clr
        lda     #$A5
        sta     rng
        lda     ctrl_def
        sta     ctrl
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
        lda     #0
        sta     hiscore
        sta     hiscore+1

; ---- title screen ----------------------------------------------------------
title:  jsr     sfx_off
        jsr     clear_names
        jsr     hide_sprites
        ldx     #0              ; the texts
        stx     tmp
@t:     ldx     tmp
        lda     title_txt,x
        beq     @tdone
        pha
        ldy     title_txt+1,x
        pla
        tax
        jsr     vdp_at
        ldx     tmp
        lda     title_txt+2,x
        ldy     title_txt+3,x
        jsr     vdp_puts
        lda     tmp
        clc
        adc     #4
        sta     tmp
        bne     @t
@tdone: ldx     #0              ; the invaders next to their points
@k:     stx     tmp
        txa
        asl
        clc
        adc     #8
        tay                     ; rows 8, 10, 12
        ldx     #9
        jsr     vdp_at
        ldx     tmp
        lda     kind_pat,x
        sta     VDP_DATA
        clc
        adc     #1
        sta     VDP_DATA
        adc     #1
        sta     VDP_DATA
        ldx     tmp
        inx
        cpx     #3
        bne     @k
        lda     #48             ; and the saucer (row 6)
        sta     spr_tab+S_SAUCER*4
        lda     #72
        sta     spr_tab+S_SAUCER*4+1
        lda     #SP_SAUCER
        sta     spr_tab+S_SAUCER*4+2
        lda     #C_SAUCER
        sta     spr_tab+S_SAUCER*4+3
        jsr     show_ctrl
        jsr     show_hiscore
        jsr     read_pad
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @notq
        jmp     exit_game
@notq:  cmp     #'M'
        bne     @notm
        jsr     toggle_sound
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
        bne     new_game
@notp:  cmp     #' '
        bne     @wait

; ---- new game ----------------------------------------------------------------
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     wave
        lda     #3
        sta     lives

new_wave:
        jsr     sfx_off
        jsr     init_wave
        jsr     draw_all

; ---- main loop ---------------------------------------------------------------
game_loop:
        lda     speed
        sta     wf_n
@f:     jsr     vdp_frame
        dec     wf_n
        bne     @f
        jsr     put_sprites
        jsr     sfx_poll
        jsr     read_keys
        lda     quit
        beq     @noquit
        jmp     exit_game
@noquit:
        jsr     move_player
        jsr     fire
        jsr     move_shot
        jsr     move_bombs
        lda     dead
        beq     @alive
        jsr     player_died
        lda     lives
        beq     game_over
        jmp     game_loop
@alive: jsr     spawn_bomb
        jsr     ufo_tick
        jsr     inv_tick
        jsr     expl_tick
        lda     invaded
        bne     game_over
        lda     alive_count
        bne     game_loop
        inc     wave
        jsr     sfx_off
        lda     #SND_WAVE
        ldx     #3
        jsr     sfx_play
        jsr     hide_moving
        lda     #60
        jsr     wait_frames     ; a second between waves
        jmp     new_wave

; ---- game over ----------------------------------------------------------------
game_over:
        lda     score+1         ; a new high score?
        cmp     hiscore+1
        bcc     @nohi
        bne     @hi
        lda     score
        cmp     hiscore
        bcc     @nohi
@hi:    lda     score
        sta     hiscore
        lda     score+1
        sta     hiscore+1
        jsr     show_score
@nohi:  jsr     sfx_off
        lda     #SND_OVER
        ldx     #3
        jsr     sfx_play
        jsr     hide_moving
        ldx     #0
@o:     stx     tmp
        lda     over_txt,x
        beq     @odone
        pha
        ldy     over_txt+1,x
        pla
        tax
        jsr     vdp_at
        ldx     tmp
        lda     over_txt+2,x
        ldy     over_txt+3,x
        jsr     vdp_puts
        lda     tmp
        clc
        adc     #4
        tax
        bne     @o
@odone: lda     #60
        jsr     wait_frames     ; ignore keys for a second
@wait:  jsr     menu_key
        cmp     #'Q'
        beq     @title
        cmp     #'M'
        bne     @nm
        jsr     toggle_sound
        jmp     @wait
@nm:    cmp     #' '
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game
@title: jmp     title

; ---- quit ------------------------------------------------------------------
exit_game:
        jsr     sfx_off
        jsr     SBC_CONRESET    ; the console's text screen back
        jmp     SBC_MENU

; ============================================================================
; screen
; ============================================================================

; set up the VDP and load the patterns, colours and sprites
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup
        lda     #<(V_PAT + $20*8)       ; the font
        ldy     #>(V_PAT + $20*8)
        jsr     vdp_waddr
        ldx     #<gfx_font
        ldy     #>gfx_font
        jsr     copy_xy
        .word   64*8
        lda     #<(V_PAT + P_GROUND*8)  ; the ground and the cannon
        ldy     #>(V_PAT + P_GROUND*8)
        jsr     vdp_waddr
        ldx     #<gfx_ground
        ldy     #>gfx_ground
        jsr     copy_xy
        .word   3*8
        lda     #<(V_PAT + P_INV*8)     ; the invaders
        ldy     #>(V_PAT + P_INV*8)
        jsr     vdp_waddr
        ldx     #<gfx_inv
        ldy     #>gfx_inv
        jsr     copy_xy
        .word   72*8
        lda     #<V_COLOUR
        ldy     #>V_COLOUR
        jsr     vdp_waddr
        ldx     #<gfx_colours
        ldy     #>gfx_colours
        jsr     copy_xy
        .word   32
        lda     #<V_SPAT
        ldy     #>V_SPAT
        jsr     vdp_waddr
        ldx     #<gfx_sprites
        ldy     #>gfx_sprites
        jsr     copy_xy
        .word   8*32
        lda     #<(V_SATTR + NSPR*4)    ; the end of the sprite list
        ldy     #>(V_SATTR + NSPR*4)
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        jsr     hide_sprites
        jsr     put_sprites
        lda     #$C2            ; R1: display on, 16 x 16 sprites
        ldx     #1
        jmp     vdp_reg

; copy from X/Y (low/high) to VRAM; the length is the .word after the JSR
copy_xy:
        stx     vdp_src
        sty     vdp_src+1
        pla                     ; the return address points at the .word - 1
        sta     cx_ret
        pla
        sta     cx_ret+1
        ldy     #1
        jsr     cx_byte
        sta     vdp_n
        ldy     #2
        jsr     cx_byte
        sta     vdp_n+1
        lda     cx_ret          ; return past the .word
        clc
        adc     #2
        tax
        lda     cx_ret+1
        adc     #0
        pha
        txa
        pha
        jmp     vdp_copy
cx_byte:                        ; A = the byte at cx_ret + Y
        lda     cx_ret
        sta     @rd+1
        lda     cx_ret+1
        sta     @rd+2
@rd:    lda     $FFFF,y
        rts

; the whole name table blank
clear_names:
        lda     #<V_NAME
        ldy     #>V_NAME
        jsr     vdp_waddr
        lda     #<768
        sta     vdp_n
        lda     #>768
        sta     vdp_n+1
        lda     #P_BLANK
        jmp     vdp_fill

; all sprites below the screen
hide_sprites:
        ldx     #NSPR*4-4
@l:     lda     #HIDE_Y
        sta     spr_tab,x
        lda     #0
        sta     spr_tab+3,x
        dex
        dex
        dex
        dex
        bpl     @l
        rts

; all but the cannon
hide_moving:
        lda     #HIDE_Y
        ldx     #S_SHOT*4
@l:     sta     spr_tab,x
        inx
        inx
        inx
        inx
        cpx     #NSPR*4
        bne     @l
        rts

; the sprite table to VRAM (once a frame)
put_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     #0
@l:     lda     spr_tab,x
        sta     VDP_DATA
        inx
        cpx     #NSPR*4
        bne     @l
        rts

; the controls line on the title screen
show_ctrl:
        ldx     #2
        ldy     #20
        jsr     vdp_at
        lda     ctrl
        beq     @kb
        lda     #<ctrl_pad_txt
        ldy     #>ctrl_pad_txt
        jmp     vdp_puts
@kb:    lda     #<ctrl_kb_txt
        ldy     #>ctrl_kb_txt
        jmp     vdp_puts

; draw the whole playfield for a new wave
draw_all:
        jsr     clear_names
        ldx     #0
        ldy     #0
        jsr     vdp_at
        lda     #<status_txt
        ldy     #>status_txt
        jsr     vdp_puts
        jsr     show_score
        jsr     show_hiscore
        jsr     show_lives
        ldx     #0              ; the ground
        ldy     #GROUND_ROW
        jsr     vdp_at
        lda     #32
        sta     vdp_n
        lda     #0
        sta     vdp_n+1
        lda     #P_GROUND
        jsr     vdp_fill
        jsr     draw_shields
        ldx     #NROWS-1
@inv:   jsr     draw_row        ; (keeps X)
        dex
        bpl     @inv
        jsr     hide_sprites
        jmp     draw_player

show_score:
        ldx     #6
        ldy     #0
        jsr     vdp_at
        lda     score+1
        jsr     vdp_bcd
        lda     score
        jmp     vdp_bcd

show_hiscore:
        ldx     #21
        ldy     #0
        jsr     vdp_at
        lda     hiscore+1
        jsr     vdp_bcd
        lda     hiscore
        jmp     vdp_bcd

show_lives:
        ldx     #31
        ldy     #0
        jsr     vdp_at
        lda     lives
        ora     #'0'
        sta     VDP_DATA
        rts

; BCD score += Y:A
add_score:
        sed
        clc
        adc     score
        sta     score
        tya
        adc     score+1
        sta     score+1
        cld
        jmp     show_score

; ============================================================================
; a new wave
; ============================================================================
init_wave:
        ldx     #NROWS-1
@row:   lda     #$FF
        sta     alive,x
        lda     #FORM_C
        sta     rowc,x
        lda     #0
        sta     rowph,x
        sta     rowfrm,x
        txa                     ; rowy = FORM_TOP + 2*row + min(wave, 4)
        asl
        clc
        adc     #FORM_TOP
        sta     rowy,x
        lda     wave
        cmp     #4
        bcc     @w
        lda     #4
@w:     clc
        adc     rowy,x
        sta     rowy,x
        dex
        bpl     @row
        lda     #NROWS*NCOLS
        sta     alive_count
        lda     #1
        sta     dir
        sta     inv_t
        lda     #NROWS-1
        sta     cur_row
        lda     #0
        sta     dropping
        sta     invaded
        sta     dead
        sta     shot_on
        sta     bomb_on
        sta     bomb_on+1
        sta     bomb_on+2
        sta     ufo_on
        sta     expl_t
        sta     shield_gone
        sta     key_dir
        sta     key_hold
        lda     wave            ; bombs get more frequent each wave
        cmp     #6
        bcc     @r
        lda     #6
@r:     asl
        asl
        clc
        adc     #6              ; 6 .. 30 out of 256 a frame
        sta     bomb_rate
        lda     #PX_START
        sta     px
        jsr     ufo_reset
        ldx     #4*48-1         ; fresh shields
@sh:    txa
        pha
@m:     cmp     #48             ; (X mod 48)
        bcc     @g
        sbc     #48
        bcs     @m
@g:     tay
        lda     gfx_shield,y
        sta     shields,x
        pla
        tax
        dex
        cpx     #$FF
        bne     @sh
        rts

; the 4 shields: their patterns from the RAM copy, and their names
draw_shields:
        lda     #<(V_PAT + P_SHIELD*8)
        ldy     #>(V_PAT + P_SHIELD*8)
        jsr     vdp_waddr
        ldx     #0              ; X = shield * 48 + line * 3 + column
        stx     sd_s
@s:     ldy     #0              ; pattern row 0/1, pattern 0-2, its 8 lines
        sty     sd_tr
@tr:    lda     #0
        sta     sd_tc
@tc:    lda     sd_s            ; first byte of this pattern:
        sta     tmp             ; shield*48 + tr*24 + tc
        asl
        clc
        adc     tmp
        asl
        asl
        asl
        asl                     ; shield * 48
        sta     tmp
        lda     sd_tr
        beq     @t0
        lda     #24
@t0:    clc
        adc     tmp
        adc     sd_tc
        tax
        ldy     #8
@l:     lda     shields,x
        sta     VDP_DATA
        inx
        inx
        inx
        dey
        bne     @l
        inc     sd_tc
        lda     sd_tc
        cmp     #3
        bne     @tc
        inc     sd_tr
        lda     sd_tr
        cmp     #2
        bne     @tr
        inc     sd_s
        lda     sd_s
        cmp     #4
        bne     @s
        ; the names: P_SHIELD + shield*6 + tr*3 + tc
        lda     #0
        sta     sd_s
@n:     ldx     sd_s
        lda     shield_col,x
        tax
        ldy     #SHIELD_ROW
        jsr     vdp_at
        lda     sd_s
        asl
        sta     tmp
        asl
        clc
        adc     tmp             ; * 6
        adc     #P_SHIELD
        sta     VDP_DATA
        adc     #1
        sta     VDP_DATA
        adc     #1
        sta     VDP_DATA
        sta     tmp
        ldy     #SHIELD_ROW+1
        jsr     vdp_at
        lda     tmp
        adc     #1
        sta     VDP_DATA
        adc     #1
        sta     VDP_DATA
        adc     #1
        sta     VDP_DATA
        inc     sd_s
        lda     sd_s
        cmp     #4
        bne     @n
        rts

; the invaders have come down to the shields: remove them
wipe_shields:
        lda     shield_gone
        bne     @done
        inc     shield_gone
        ldx     #4*48-1
        lda     #0
@z:     sta     shields,x
        dex
        cpx     #$FF
        bne     @z
        ldx     #0
        ldy     #SHIELD_ROW
        jsr     vdp_at
        lda     #64
        sta     vdp_n
        lda     #0
        sta     vdp_n+1
        lda     #P_BLANK
        jsr     vdp_fill
        ldx     #NROWS-1        ; (any invaders on those lines again)
@r:     lda     alive,x
        beq     @n
        jsr     draw_row
@n:     dex
        bpl     @r
@done:  rts

; ============================================================================
; shields: 4 bitmaps of 24 x 16 pixels (3 bytes a line, bit 7 = left)
; ============================================================================

; is pixel X, Y part of a shield?  Carry set if so; then sh_i = its byte in
; shields, sh_m = its bit, and sh_va = the VRAM address of its pattern byte.
; Preserves X and Y.
shield_px:
        stx     sh_x
        sty     sh_y
        tya
        sec
        sbc     #SHIELD_Y
        cmp     #16
        bcs     @no
        sta     sh_line
        ldy     #3
@k:     txa
        sec
        sbc     shield_x,y
        cmp     #24
        bcc     @found
        dey
        bpl     @k
@no:    ldx     sh_x
        ldy     sh_y
        clc
        rts
@found: sta     sh_col          ; 0-23
        sty     sh_s
        and     #7
        tax
        lda     bitmask_hi,x
        sta     sh_m
        lda     sh_col          ; byte = shield*48 + line*3 + col/8
        lsr
        lsr
        lsr
        sta     sh_tc
        lda     sh_line
        asl
        adc     sh_line
        adc     sh_tc
        sta     sh_i
        lda     sh_s            ; + shield*48
        asl
        adc     sh_s
        asl
        asl
        asl
        asl
        clc
        adc     sh_i
        sta     sh_i
        tax
        lda     shields,x
        and     sh_m
        beq     @no
        ; the VRAM byte: (P_SHIELD + s*6 + (line/8)*3 + col/8) * 8 + line & 7
        lda     sh_s
        asl
        adc     sh_s
        asl                     ; s * 6
        sta     tmp3
        lda     sh_line
        cmp     #8
        lda     tmp3
        bcc     @t
        adc     #3-1            ; (carry is set)
@t:     clc
        adc     sh_tc
        adc     #P_SHIELD       ; the pattern number (< $80)
        sta     sh_va+1         ; * 8, into 16 bits
        lda     #0
        asl     sh_va+1
        rol
        asl     sh_va+1
        rol
        asl     sh_va+1
        rol
        sta     tmp3            ; high byte
        lda     sh_line
        and     #7
        ora     sh_va+1
        sta     sh_va
        lda     tmp3
        sta     sh_va+1
        ldx     sh_x
        ldy     sh_y
        sec
        rts

; clear the pixel shield_px found.  Preserves X and Y.
shield_clr:
        stx     sh_x2
        ldx     sh_i
        lda     sh_m
        eor     #$FF
        and     shields,x
        sta     shields,x
        pha
        lda     sh_va
        sta     VDP_CTRL
        lda     sh_va+1
        ora     #$40 + >V_PAT
        sta     VDP_CTRL
        pla
        sta     VDP_DATA
        ldx     sh_x2
        rts

; blast a hole round X, Y: the shield pixels in a 3 x 3 square (and a few
; more at random).  Preserves X and Y.
shield_blast:
        stx     bl_x
        sty     bl_y
        lda     #12
        sta     bl_n
@l:     ldx     bl_n
        lda     bl_y
        clc
        adc     blast_dy,x
        tay
        lda     bl_x
        clc
        adc     blast_dx,x
        tax
        jsr     shield_px
        bcc     @next
        lda     bl_n
        cmp     #9
        bcc     @clr            ; the square: always
        jsr     rand
        bmi     @next           ; the rest: half of them
@clr:   jsr     shield_clr
@next:  dec     bl_n
        bpl     @l
        ldx     bl_x
        ldy     bl_y
        rts

; ============================================================================
; keyboard / gamepad
; ============================================================================
read_keys:
        lda     #0
        sta     key_fire
        lda     key_hold        ; a direction key moves for KEY_HOLD frames
        beq     @nh             ; (its auto-repeat keeps it going)
        dec     key_hold
        bne     @nh
        lda     #0
        sta     key_dir
@nh:    lda     padold          ; the pad, in either mode: held = moving
        sta     pad_prev
        jsr     read_pad
        lda     pad
        and     #PAD_LEFT | PAD_RIGHT
        beq     @nopad
        ldx     #1
        and     #PAD_LEFT
        beq     @pr
        ldx     #$FF
@pr:    stx     key_dir
        lda     #0
        sta     key_hold
        lda     #1
        sta     pad_mv
        bne     @pf
@nopad: lda     pad_mv          ; let go: stop at once
        beq     @pf
        lda     #0
        sta     pad_mv
        sta     key_dir
@pf:    lda     pad
        and     #PAD_A | PAD_B
        beq     @nf
        lda     #1
        sta     key_fire
@nf:    lda     padnew
        and     #PAD_START
        beq     @l
        jsr     pad_pause
@l:     jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @l
@done:  rts

handle_key:
        ldx     esc_st          ; ESC [ C / ESC [ D: arrows from a terminal
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
        cmp     #KEY_DOWN
        beq     @stop
        jsr     pad_typed       ; W A S D space: typed by the pad?
        bcc     @kb
        ldx     ctrl            ; gamepad mode: always ignored
        bne     @ign
        ldx     pad             ; or while a pad button is (was) held
        bne     @ign
        ldx     pad_prev
        beq     @kb
@ign:   rts
@kb:    cmp     #' '
        beq     @fire
        cmp     #','
        beq     @left
        cmp     #'.'
        beq     @right
        and     #$DF            ; letters to upper case
        cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #'S'
        beq     @stop
        cmp     #'W'
        beq     @fire
        cmp     #'Q'
        beq     @quit
        cmp     #'P'
        beq     @pause
        cmp     #'M'
        beq     toggle_sound
        rts
@left:  lda     #$FF
        bne     @dir
@right: lda     #1
@dir:   sta     key_dir
        lda     #KEY_HOLD
        sta     key_hold
        rts
@stop:  lda     #0
        sta     key_dir
        sta     key_hold
        rts
@fire:  lda     #1
        sta     key_fire
        rts
@quit:  lda     #1
        sta     quit
        rts
@pause: jsr     sfx_hush
@pw:    jsr     frame_idle_q
        jsr     getc
        bcc     @pw
        lda     #0
        sta     key_dir
        sta     key_hold
        rts

; keeps the random numbers going in a pause (the sound stays quiet)
frame_idle_q:
        jmp     rand

toggle_sound:
        lda     sfx_mute
        eor     #1
        sta     sfx_mute
        jmp     sfx_hush

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

; ============================================================================
; the cannon and its shot
; ============================================================================
move_player:
        lda     key_dir
        beq     @done
        lda     frame_odd       ; 1.5 pixels a frame: 1, then 2
        eor     #1
        sta     frame_odd
        clc
        adc     #1
        sta     tmp
        lda     key_dir
        bmi     @left
        lda     px
        clc
        adc     tmp
        cmp     #PX_MAX+1
        bcc     @set
        lda     #PX_MAX
        bne     @set
@left:  lda     px
        sec
        sbc     tmp
        bcc     @min
        cmp     #PX_MIN
        bcs     @set
@min:   lda     #PX_MIN
@set:   sta     px
@done:  ; (on into draw_player)

draw_player:
        lda     #PLAYER_Y-1
        sta     spr_tab+S_CANNON*4
        lda     px
        sta     spr_tab+S_CANNON*4+1
        lda     #SP_CANNON
        sta     spr_tab+S_CANNON*4+2
        lda     #C_CANNON
        sta     spr_tab+S_CANNON*4+3
        rts

fire:   lda     key_fire
        beq     @done
        lda     shot_on
        bne     @done
        lda     px              ; the gun is at the sprite's 8th pixel
        sta     shot_x
        lda     #PLAYER_Y-4
        sta     shot_y
        lda     #1
        sta     shot_on
        jsr     draw_shot
        lda     #SND_SHOT
        ldx     #4
        jmp     sfx_play
@done:  rts

draw_shot:
        lda     shot_y
        sec
        sbc     #1
        sta     spr_tab+S_SHOT*4
        lda     shot_x
        sta     spr_tab+S_SHOT*4+1
        lda     #SP_SHOT
        sta     spr_tab+S_SHOT*4+2
        lda     #C_SHOT
        sta     spr_tab+S_SHOT*4+3
        rts

; the shot goes up 4 pixels a frame, checked a pixel at a time
move_shot:
        lda     shot_on
        beq     @done
        lda     #4
        sta     shot_n
@step:  dec     shot_y
        lda     shot_y
        cmp     #9              ; the status line
        bcc     @off
        jsr     shot_hits
        bcs     @off
        dec     shot_n
        bne     @step
        jmp     draw_shot
@off:   lda     #0
        sta     shot_on
        lda     #HIDE_Y
        sta     spr_tab+S_SHOT*4
@done:  rts

; has the shot's tip (shot_x + 7, shot_y) hit something?  Carry set if so.
shot_hits:
        lda     shot_x
        clc
        adc     #7
        sta     hit_x
        lda     ufo_on          ; the saucer?
        beq     @inv
        lda     shot_y
        cmp     #UFO_Y
        bcc     @inv
        cmp     #UFO_Y+7
        bcs     @inv
        lda     hit_x
        sec
        sbc     ufo_x
        cmp     #16
        bcs     @inv
        jsr     ufo_hit
        sec
        rts
@inv:   lda     shot_y          ; an invader?
        lsr
        lsr
        lsr
        sta     hit_row
        ldx     #NROWS-1
@rl:    lda     alive,x
        beq     @next
        lda     rowy,x
        cmp     hit_row
        bne     @next
        lda     hit_x
        jsr     slot_at
        bcc     @next
        jsr     kill_inv
        sec
        rts
@next:  dex
        bpl     @rl
        ldx     hit_x           ; a shield?
        ldy     shot_y
        jsr     shield_px
        bcc     @r
        jsr     shield_blast
        sec
@r:     rts

; ============================================================================
; the invaders
; ============================================================================

; row X's left pixel (of slot 0), signed 16 bit -> rx (lo), rx+1 (hi):
; rowc * 8 + rowph * 2.  Preserves X.
row_left:
        lda     #0
        sta     rx+1
        lda     rowc,x
        bpl     @p
        dec     rx+1            ; (negative)
@p:     asl
        rol     rx+1
        asl
        rol     rx+1
        asl
        rol     rx+1
        sta     rx
        lda     rowph,x
        asl
        clc
        adc     rx
        sta     rx
        bcc     @r
        inc     rx+1
@r:     rts

; is pixel column A on a live invader of row X?  Carry set if so, with its
; slot in Y.  Preserves X.
slot_at:
        sta     sa_x
        jsr     row_left
        lda     sa_x            ; rel = x - left (16 bit), must be 0-191
        sec
        sbc     rx
        sta     sa_rel
        lda     #0
        sbc     rx+1
        bne     @no
        lda     sa_rel
        cmp     #NCOLS*CELL
        bcs     @no
        ldy     #0              ; slot = rel / 24, rel = rel mod 24
@d:     cmp     #CELL
        bcc     @got
        sbc     #CELL
        iny
        bne     @d
@got:   sta     sa_rel
        lda     alive,x
        and     bitmask,y
        beq     @no
        stx     sa_row
        lda     rowkind,x       ; inside the picture?
        tax
        lda     sa_rel
        sec
        sbc     inv_ox,x
        cmp     inv_w,x
        ldx     sa_row
        bcs     @no
        sec
        rts
@no:    clc
        rts

; draw row X: blank, 8 cells of 3 patterns, blank, starting a cell to the
; left of slot 0 (only the part on the screen).  Preserves X.
draw_row:
        stx     dr_r
        ldy     #0              ; build the 26 names in rowbuf
        sty     rowbuf
        iny
        lda     rowkind,x       ; the first pattern: kind*24 + frame*12 + pos*3
        sta     tmp
        asl
        clc
        adc     tmp
        asl
        asl
        asl                     ; kind * 24
        sta     tmp
        lda     rowfrm,x
        beq     @f0
        lda     #12
@f0:    clc
        adc     tmp
        sta     tmp
        lda     rowph,x
        asl
        adc     rowph,x
        adc     tmp
        adc     #P_INV
        sta     dr_base
        lda     alive,x
        sta     dr_mask
        ldx     #NCOLS
@s:     lsr     dr_mask
        bcc     @dead
        lda     dr_base
        sta     rowbuf,y
        iny
        adc     #0              ; (carry set: +1)
        sta     rowbuf,y
        iny
        clc
        adc     #1
        sta     rowbuf,y
        iny
        bne     @n
@dead:  lda     #P_BLANK
        sta     rowbuf,y
        iny
        sta     rowbuf,y
        iny
        sta     rowbuf,y
        iny
@n:     dex
        bne     @s
        lda     #P_BLANK
        sta     rowbuf,y        ; [25]
        ; the part on the screen: columns rowc-1 .. rowc+24
        ldx     dr_r
        lda     rowc,x
        sec
        sbc     #1
        sta     dr_c            ; first column (signed)
        ldy     #0              ; first index into rowbuf
        lda     dr_c
        bpl     @on
        eor     #$FF            ; off the left: skip -c names
        clc
        adc     #1
        tay
        lda     #0
        sta     dr_c
@on:    sty     dr_i
        cpy     #26
        bcs     @out
        lda     dr_c
        cmp     #32
        bcs     @out
        ldx     dr_c
        ldy     dr_r
        lda     rowy,y
        tay
        jsr     vdp_at
        ldy     dr_i
        ldx     dr_c
@w:     lda     rowbuf,y
        sta     VDP_DATA
        iny
        cpy     #26
        bcs     @out
        inx
        cpx     #32
        bcc     @w
@out:   ldx     dr_r
        rts

; blank cell row Y (all of it).  Preserves X.
blank_line:
        stx     tmp2
        ldx     #0
        jsr     vdp_at
        lda     #32
        sta     vdp_n
        lda     #0
        sta     vdp_n+1
        lda     #P_BLANK
        jsr     vdp_fill
        ldx     tmp2
        rts

; move one row a step: the rows take turns, from the bottom up, as in the
; arcade game.  The step rate goes up as invaders are shot.
inv_tick:
        dec     inv_t
        beq     @go
        rts
@go:    lda     alive_count     ; frames a step = alive / 8 + 1
        lsr
        lsr
        lsr
        clc
        adc     #1
        sta     inv_t
@find:  ldx     cur_row
        bmi     @sweep_end
        lda     alive,x
        bne     @do
        dec     cur_row
        jmp     @find
@do:    lda     rowfrm,x        ; the next picture
        eor     #1
        sta     rowfrm,x
        lda     dropping
        beq     @horiz
        ldy     rowy,x          ; down a cell row
        jsr     blank_line
        inc     rowy,x
        jmp     @draw
@horiz: lda     dir
        bmi     @l
        inc     rowph,x         ; 2 pixels right
        lda     rowph,x
        cmp     #4
        bne     @draw
        lda     #0
        sta     rowph,x
        inc     rowc,x
        jmp     @draw
@l:     dec     rowph,x         ; 2 pixels left
        bpl     @draw
        lda     #3
        sta     rowph,x
        dec     rowc,x
@draw:  jsr     draw_row
        dec     cur_row
        rts

@sweep_end:                     ; every row has moved: the next sweep
        lda     march           ; the march: one of 4 notes a step
        clc
        adc     #1
        and     #3
        sta     march
        ldx     #0
        jsr     sfx_play        ; (SND_MARCH0 .. 3 are 0 .. 3)
        lda     #NROWS-1
        sta     cur_row
        lda     #1
        sta     inv_t
        lda     dropping
        beq     @edges
        lda     #0
        sta     dropping
        jmp     after_drop
@edges: jsr     form_extent
        lda     dir
        bmi     @left
        lda     ext_max+1       ; right edge + 2 past EDGE_R?
        bne     @drop
        lda     ext_max
        cmp     #EDGE_R-2
        bcs     @drop
        rts
@left:  lda     ext_min+1       ; left edge - 2 below EDGE_L?
        bmi     @drop
        bne     @ok
        lda     ext_min
        cmp     #EDGE_L+2
        bcc     @drop
@ok:    rts
@drop:  lda     #1
        sta     dropping
        lda     dir
        eor     #$FF
        clc
        adc     #1
        sta     dir
        rts

; the left and right pixels of the live invaders -> ext_min, ext_max (16 bit)
form_extent:
        lda     #$FF
        sta     ext_min
        lda     #$7F
        sta     ext_min+1
        lda     #0
        sta     ext_max
        lda     #$FF
        sta     ext_max+1
        ldx     #NROWS-1
@l:     lda     alive,x
        beq     @next
        jsr     row_left
        lda     alive,x         ; first live slot -> Y
        ldy     #$FF
@f:     iny
        lsr
        bcc     @f
        jsr     slot_px         ; left of its picture
        lda     ex_t+1          ; < ext_min? (signed)
        cmp     ext_min+1
        bmi     @lo
        bne     @hi
        lda     ex_t
        cmp     ext_min
        bcs     @hi
@lo:    lda     ex_t
        sta     ext_min
        lda     ex_t+1
        sta     ext_min+1
@hi:    lda     alive,x         ; last live slot -> Y
        ldy     #NCOLS
@h:     dey
        asl
        bcc     @h
        jsr     slot_px
        ldy     rowkind,x       ; its right pixel
        lda     ex_t
        clc
        adc     inv_w,y
        sta     ex_t
        bcc     :+
        inc     ex_t+1
:       lda     ex_t+1          ; > ext_max? (signed)
        cmp     ext_max+1
        bmi     @next
        bne     @max
        lda     ex_t
        cmp     ext_max
        bcc     @next
@max:   lda     ex_t
        sta     ext_max
        lda     ex_t+1
        sta     ext_max+1
@next:  dex
        bpl     @l
        rts

; ex_t = rx + slot Y * 24 + the picture's offset for row X's kind (16 bit).
; Preserves X and Y.
slot_px:
        sty     ex_y
        lda     rx
        sta     ex_t
        lda     rx+1
        sta     ex_t+1
        tya
        beq     @k
@m:     lda     ex_t
        clc
        adc     #CELL
        sta     ex_t
        bcc     :+
        inc     ex_t+1
:       dey
        bne     @m
@k:     ldy     rowkind,x
        lda     ex_t
        clc
        adc     inv_ox,y
        sta     ex_t
        bcc     :+
        inc     ex_t+1
:       ldy     ex_y
        rts

; after the formation has come down a row: shields gone?  landed?
after_drop:
        ldx     #NROWS-1
@l:     lda     alive,x         ; the lowest live row
        bne     @found
        dex
        bpl     @l
        rts
@found: lda     rowy,x
        cmp     #PLAYER_ROW
        bcc     @1
        lda     #1
        sta     invaded
        rts
@1:     cmp     #SHIELD_ROW-1   ; touching the shields?
        bcc     @2
        jmp     wipe_shields
@2:     rts

; shoot the invader in row X, slot Y
kill_inv:
        lda     bitmask,y
        eor     #$FF
        and     alive,x
        sta     alive,x
        dec     alive_count
        stx     kv_r
        sty     kv_s
        jsr     row_left        ; the explosion where it was
        jsr     slot_px
        lda     ex_t
        sec
        sbc     #1
        sta     spr_tab+S_EXPL*4+1
        lda     rowy,x
        asl
        asl
        asl
        sec
        sbc     #1
        sta     spr_tab+S_EXPL*4
        lda     #SP_EXPL
        sta     spr_tab+S_EXPL*4+2
        lda     #C_EXPL
        sta     spr_tab+S_EXPL*4+3
        lda     #16
        sta     expl_t
        ldx     kv_r
        jsr     draw_row        ; (the row without it)
        lda     #SND_KILL
        ldx     #5
        jsr     sfx_play
        ldx     kv_r
        lda     points,x
        ldy     #0
        jmp     add_score

expl_tick:
        lda     expl_t
        beq     @done
        dec     expl_t
        bne     @done
        lda     #HIDE_Y
        sta     spr_tab+S_EXPL*4
@done:  rts

; ============================================================================
; bombs: 3 of them, falling a pixel a frame (2 from wave 4)
; ============================================================================
spawn_bomb:
        jsr     rand
        cmp     bomb_rate
        bcs     @done
        ldx     #2
@free:  lda     bomb_on,x
        beq     @got
        dex
        bpl     @free
@done:  rts
@got:   stx     bm_i
        jsr     rand
        and     #NCOLS-1
        tay                     ; a random column ...
        ldx     #NROWS-1
@r:     lda     alive,x         ; ... and its lowest invader drops it
        and     bitmask,y
        bne     @found
        dex
        bpl     @r
        rts
@found: jsr     row_left
        jsr     slot_px         ; the middle of the picture - 1
        ldy     rowkind,x
        lda     inv_w,y
        lsr
        sec
        sbc     #1
        clc
        adc     ex_t
        sta     tmp
        lda     ex_t+1
        adc     #0
        bne     @done           ; (off the screen)
        lda     rowy,x
        asl
        asl
        asl
        adc     #8
        ldx     bm_i
        sta     bomb_y,x
        lda     tmp
        sta     bomb_x,x
        lda     #1
        sta     bomb_on,x
        rts

move_bombs:
        lda     #2
        sta     bm_i
@l:     ldx     bm_i
        lda     bomb_on,x
        bne     @on
        lda     #HIDE_Y
        sta     tmp
        jmp     @spr
@on:    lda     wave            ; speed: 1, or 2 from wave 4
        cmp     #3
        lda     #1
        adc     #0
        sta     bm_n
@step:  ldx     bm_i
        inc     bomb_y,x
        lda     bomb_y,x        ; its tip: x + 1, y + 6
        clc
        adc     #6
        tay
        cpy     #GROUND_Y
        bcs     @gone
        lda     bomb_x,x
        clc
        adc     #1
        tax
        cpy     #PLAYER_Y+1     ; the cannon?
        bcc     @noplayer
        txa
        sec
        sbc     px
        sec
        sbc     #1
        cmp     #13
        bcs     @noplayer
        lda     #1
        sta     dead
        bne     @gone
@noplayer:
        jsr     shield_px
        bcc     @next
        iny                     ; the hole is a little lower
        jsr     shield_blast
        jmp     @gone
@next:  dec     bm_n
        bne     @step
        ldx     bm_i
        lda     bomb_y,x
        sec
        sbc     #1
        sta     tmp
        jmp     @spr
@gone:  ldx     bm_i
        lda     #0
        sta     bomb_on,x
        lda     #HIDE_Y
        sta     tmp
@spr:   lda     bm_i            ; its sprite
        clc
        adc     #S_BOMB
        asl
        asl
        tay
        ldx     bm_i
        lda     tmp
        sta     spr_tab,y
        lda     bomb_x,x
        sta     spr_tab+1,y
        lda     bomb_y,x        ; the zigzag turns every 4 pixels
        and     #4
        clc
        adc     #SP_BOMB
        sta     spr_tab+2,y
        lda     #C_BOMB
        sta     spr_tab+3,y
        dec     bm_i
        bmi     @done
        jmp     @l
@done:  rts

; the cannon was hit
player_died:
        lda     #0
        sta     dead
        ldx     #1              ; (the saucer's hum stops)
        jsr     sfx_stop
        lda     #SND_DEATH
        ldx     #5
        jsr     sfx_play
        lda     #SND_DEATH2
        ldx     #3
        jsr     sfx_play
        lda     #0              ; the shot and the bombs go
        sta     shot_on
        sta     bomb_on
        sta     bomb_on+1
        sta     bomb_on+2
        lda     #HIDE_Y
        sta     spr_tab+S_SHOT*4
        sta     spr_tab+S_BOMB*4
        sta     spr_tab+S_BOMB*4+4
        sta     spr_tab+S_BOMB*4+8
        lda     #12             ; the wreck flickers for a second
        sta     tmp3
@flash: lda     tmp3
        and     #1
        asl
        asl
        clc
        adc     #SP_PEXPL
        sta     spr_tab+S_CANNON*4+2
        lda     #5
        jsr     wait_frames
        jsr     ufo_tick        ; (the saucer flies on)
        dec     tmp3
        bne     @flash
        lda     #HIDE_Y
        sta     spr_tab+S_CANNON*4
        dec     lives
        jsr     show_lives
        lda     lives
        beq     @done
        lda     #30
        jsr     wait_frames
        lda     #PX_START
        sta     px
        lda     #0
        sta     key_dir
        sta     key_hold
        jsr     draw_player
        lda     ufo_on          ; the saucer's hum again
        beq     @done
        lda     #SND_UFO
        ldx     #1
        jsr     sfx_play
@done:  rts

; ============================================================================
; the saucer
; ============================================================================

; the next one comes in 10-18 seconds
ufo_reset:
        jsr     rand
        and     #$7F
        clc
        adc     #<600
        sta     ufo_t
        lda     #>600
        adc     #0
        sta     ufo_t+1
        jsr     rand
        and     #1
        clc
        adc     ufo_t+1
        sta     ufo_t+1
        rts

ufo_tick:
        lda     ufo_on
        bne     @move
        lda     ufo_t           ; count down
        bne     @d
        lda     ufo_t+1
        beq     @start
        dec     ufo_t+1
@d:     dec     ufo_t
        rts
@start: lda     alive_count     ; not for the last few
        cmp     #8
        bcc     @done
        jsr     rand
        and     #1
        beq     @fromleft
        lda     #240
        sta     ufo_x
        lda     #$FF
        bne     @go
@fromleft:
        lda     #0
        sta     ufo_x
        lda     #1
@go:    sta     ufo_dir
        lda     #1
        sta     ufo_on
        lda     #SND_UFO        ; its hum, in the background
        ldx     #1
        jsr     sfx_play
        jmp     draw_ufo
@move:  lda     ufo_x
        clc
        adc     ufo_dir
        sta     ufo_x
        cmp     #241            ; gone off either side?
        bcs     @off
@draw:  jmp     draw_ufo
@off:   jsr     ufo_gone
@done:  rts

ufo_gone:
        lda     #0
        sta     ufo_on
        lda     #HIDE_Y
        sta     spr_tab+S_SAUCER*4
        ldx     #1
        jsr     sfx_stop
        jmp     ufo_reset

draw_ufo:
        lda     #UFO_Y-1
        sta     spr_tab+S_SAUCER*4
        lda     ufo_x
        sta     spr_tab+S_SAUCER*4+1
        lda     #SP_SAUCER
        sta     spr_tab+S_SAUCER*4+2
        lda     #C_SAUCER
        sta     spr_tab+S_SAUCER*4+3
        rts

ufo_hit:
        lda     ufo_x           ; an explosion where it was
        sta     spr_tab+S_EXPL*4+1
        lda     #UFO_Y-1
        sta     spr_tab+S_EXPL*4
        lda     #SP_EXPL
        sta     spr_tab+S_EXPL*4+2
        lda     #C_SAUCER
        sta     spr_tab+S_EXPL*4+3
        lda     #24
        sta     expl_t
        jsr     ufo_gone
        lda     #SND_UFO_HIT
        ldx     #5
        jsr     sfx_play
        jsr     rand            ; 50, 100, 150 or 300 points
        and     #3
        tax
        lda     ufo_pts_lo,x
        ldy     ufo_pts_hi,x
        jmp     add_score

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"

; R0-R7: Graphics I, display off for now, 16 x 16 sprites, no VDP interrupt;
; names $1800, colours $2000, patterns $0000, sprites $1B00 / $3800; black
vdp_regs:
        .byte   $00, $82, V_NAME/$400, V_COLOUR/$40, V_PAT/$800, V_SATTR/$80, V_SPAT/$800, $01

rowkind:.byte   0, 1, 1, 2, 2   ; squids, crabs, octopuses
kind_pat:.byte  P_INV, P_INV+24, P_INV+48
points: .byte   $30, $20, $20, $10, $10
ufo_pts_lo: .byte $50, $00, $50, $00
ufo_pts_hi: .byte $00, $01, $01, $03
bitmask:.byte   $01, $02, $04, $08, $10, $20, $40, $80
bitmask_hi:
        .byte   $80, $40, $20, $10, $08, $04, $02, $01
shield_x:   .byte 32, 88, 144, 200          ; left pixel of each shield
shield_col: .byte 4, 11, 18, 25             ; = shield_x / 8
; the hole a hit makes: a 3 x 3 square (0-8), then 4 more at random (9-12)
blast_dx:   .byte 0, $FF, 1, 0, $FF, 1, 0, $FF, 1, $FE, 2, 0, 0
blast_dy:   .byte 0, 0, 0, $FF, $FF, $FF, 1, 1, 1, 0, 0, $FE, 2

        .include "invaders_gfx.inc"

; texts: column, row, address (0 = the end)
title_txt:
        .byte   12, 0
        .word   t_hi
        .byte   9, 2
        .word   t_title
        .byte   13, 6
        .word   t_mystery
        .byte   13, 8
        .word   t_30
        .byte   13, 10
        .word   t_20
        .byte   13, 12
        .word   t_10
        .byte   1, 15
        .word   t_keys1
        .byte   1, 16
        .word   t_keys2
        .byte   1, 17
        .word   t_keys3
        .byte   6, 22
        .word   t_press
        .byte   0
t_hi:     .byte "HI-SCORE", 0
t_title:  .byte "SPACE  INVADERS", 0
t_mystery:.byte "= ? MYSTERY", 0
t_30:     .byte "= 30 POINTS", 0
t_20:     .byte "= 20 POINTS", 0
t_10:     .byte "= 10 POINTS", 0
t_keys1:  .byte "KEYS: A/D OR ARROWS, SPACE FIRE", 0
t_keys2:  .byte "PAD:  LEFT/RIGHT, A OR B FIRE", 0
t_keys3:  .byte "P/START PAUSE  M SOUND  Q QUIT", 0
t_press:  .byte "SPACE OR START: PLAY", 0
ctrl_kb_txt:
          .byte "CONTROLS: KEYBOARD  (G: PAD)  ", 0
ctrl_pad_txt:
          .byte "CONTROLS: GAMEPAD   (G: KEYS) ", 0
status_txt:
          .byte "SCORE       HI-SCORE      LIVES", 0
over_txt:
        .byte   10, 10
        .word   t_over1
        .byte   10, 11
        .word   t_over2
        .byte   10, 12
        .word   t_over3
        .byte   10, 13
        .word   t_over4
        .byte   0
t_over1:  .byte "            ", 0
t_over2:  .byte "  GAME OVER ", 0
t_over3:  .byte " SPACE: PLAY", 0
t_over4:  .byte " Q: TITLE   ", 0
need_txt: .byte 13, 10, "INVADERS NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0

; ---- sounds (scripts for ay/sfx.s: voices 0-2 background, 3-5 foreground
; on channels A-C) ---------------------------------------------------------------
SND_MARCH0      = 0             ; 0-3: the march, background A
SND_SHOT        = 4             ; foreground B
SND_KILL        = 5             ; foreground C
SND_UFO         = 6             ; background B, until stopped
SND_UFO_HIT     = 7             ; foreground C
SND_DEATH       = 8             ; foreground C (noise) ...
SND_DEATH2      = 9             ; ... and A (a falling tone)
SND_WAVE        = 10            ; foreground A: a wave cleared
SND_OVER        = 11            ; foreground A: game over
sfx_scripts:
        .word   s_march0, s_march1, s_march2, s_march3, s_shot, s_kill, s_ufo
        .word   s_ufo_hit, s_death, s_death2, s_wave, s_over
sfx_prio:
        .byte   1, 1, 1, 1, 3, 5, 2, 8, 10, 10, 6, 6

s_march0: .byte SX_VOL, 14, SX_DECAY, 1, SX_NOTE(19), SX_WAIT(10), SX_END    ; G2
s_march1: .byte SX_VOL, 14, SX_DECAY, 1, SX_NOTE(17), SX_WAIT(10), SX_END    ; F2
s_march2: .byte SX_VOL, 14, SX_DECAY, 1, SX_NOTE(15), SX_WAIT(10), SX_END    ; D#2
s_march3: .byte SX_VOL, 14, SX_DECAY, 1, SX_NOTE(14), SX_WAIT(10), SX_END    ; D2
s_shot:   .byte SX_VOL, 12, SX_DECAY, 2, SX_PER, 60, 0, SX_SWEEP, 9, 0, SX_WAIT(18), SX_END
s_kill:   .byte SX_MIX, 2, SX_NOISE, 12, SX_VOL, 15, SX_DECAY, 1, SX_WAIT(15), SX_END
s_ufo:    .byte SX_VOL, 9, SX_LOOP, 0
          .byte SX_PER, 80, 0, SX_SWEEP, 6, 0, SX_WAIT(8), SX_SWEEP, $FA, $FF, SX_WAIT(8)
          .byte SX_NEXT
s_ufo_hit:.byte SX_VOL, 13, SX_DECAY, 5, SX_LOOP, 4
          .byte SX_NOTE(67), SX_WAIT(3), SX_NOTE(64), SX_WAIT(3), SX_NOTE(60), SX_WAIT(3), SX_NOTE(55), SX_WAIT(3)
          .byte SX_NEXT, SX_END
s_death:  .byte SX_MIX, 2, SX_NOISE, 24, SX_VOL, 15, SX_DECAY, 4, SX_WAIT(64), SX_END
s_death2: .byte SX_VOL, 12, SX_DECAY, 5, SX_PER, $90, $01, SX_SWEEP, 14, 0, SX_WAIT(60), SX_END
s_wave:   .byte SX_VOL, 12, SX_DECAY, 3
          .byte SX_NOTE(36), SX_WAIT(5), SX_NOTE(40), SX_WAIT(5), SX_NOTE(43), SX_WAIT(5), SX_NOTE(48), SX_WAIT(20), SX_END
s_over:   .byte SX_VOL, 12, SX_DECAY, 4
          .byte SX_NOTE(31), SX_WAIT(12), SX_NOTE(30), SX_WAIT(12), SX_NOTE(29), SX_WAIT(12), SX_NOTE(28), SX_WAIT(40), SX_END

; ============================================================================
; variables (not in the file; cleared at start)
; ============================================================================
        .segment "BSS"
vars_start:
ctrl:       .res 1              ; 0 keyboard, 1 gamepad
pad:        .res 1
pad_prev:   .res 1              ; pad last frame
pad_mv:     .res 1              ; moving because of the pad
padold:     .res 1
padnew:     .res 1
hiscore:    .res 2
rng:        .res 2
score:      .res 2
lives:      .res 1
wave:       .res 1
px:         .res 1              ; the cannon sprite's x
frame_odd:  .res 1
key_dir:    .res 1
key_hold:   .res 1
key_fire:   .res 1
quit:       .res 1
esc_st:     .res 1
shot_on:    .res 1
shot_x:     .res 1              ; the shot sprite's x (its line is at x + 7)
shot_y:     .res 1              ; its top pixel
shot_n:     .res 1
hit_x:      .res 1
hit_row:    .res 1
bomb_on:    .res 3
bomb_x:     .res 3              ; sprite x (the bomb is 3 pixels wide)
bomb_y:     .res 3              ; top pixel (7 tall)
bm_i:       .res 1
bm_n:       .res 1
bomb_rate:  .res 1
ufo_on:     .res 1
ufo_x:      .res 1
ufo_dir:    .res 1
ufo_t:      .res 2              ; frames until the next saucer
alive:      .res NROWS          ; bit n = invader in slot n is alive
rowc:       .res NROWS          ; cell column of slot 0 (signed)
rowph:      .res NROWS          ; + 0-3 x 2 pixels
rowy:       .res NROWS          ; cell row
rowfrm:     .res NROWS          ; picture 0 or 1
alive_count:.res 1
dir:        .res 1              ; +1 or -1
dropping:   .res 1
cur_row:    .res 1
inv_t:      .res 1
march:      .res 1
expl_t:     .res 1
invaded:    .res 1
dead:       .res 1
shield_gone:.res 1
rx:         .res 2
ex_t:       .res 2
ex_y:       .res 1
ext_min:    .res 2
ext_max:    .res 2
sa_x:       .res 1
sa_rel:     .res 1
sa_row:     .res 1
dr_r:       .res 1
dr_base:    .res 1
dr_mask:    .res 1
dr_c:       .res 1
dr_i:       .res 1
kv_r:       .res 1
kv_s:       .res 1
sh_x:       .res 1
sh_y:       .res 1
sh_x2:      .res 1
sh_line:    .res 1
sh_col:     .res 1
sh_tc:      .res 1
sh_s:       .res 1
sh_i:       .res 1
sh_m:       .res 1
sh_va:      .res 2
bl_x:       .res 1
bl_y:       .res 1
bl_n:       .res 1
sd_s:       .res 1
sd_tr:      .res 1
sd_tc:      .res 1
cx_ret:     .res 2
wf_n:       .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
rowbuf:     .res 26
spr_tab:    .res NSPR*4
shields:    .res 4*48
vars_end:
