; ============================================================================
; invaders.s - a Space Invaders style game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal using its
; control code mode (terminal setup item J must be ON).
;
;   build:  ca65 invaders.s -o invaders.o -l invaders.lst
;           ld65 -C invaders.cfg invaders.o -o INVADERS.BIN      (or: make)
;   needs sbc_api.inc (the ROM's fixed entry points at $FE00)
;
;   run:    L INVADERS 0500     then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  speed      delay per game tick, about 1 ms per unit (default 10)
;   $0504  controls   at start: 0 keyboard, 1 gamepad (G on the title
;                     screen switches; A or Start on the pad picks the pad)
;   $0505  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2).  Without the card the game is just silent.
;
; Keys:  A / D or , / . or the arrow keys  move
;        SPACE or W                        fire
;        P                                 pause
;        M                                 sound on / off
;        Q                                 quit (back to the boot menu)
; Gamepad: left / right move, A or B fire, Start pause
;
; Graphics: the invaders, the player and the saucer are block graphics
; characters (attribute $80, 2x4 blocks per character, each block is one
; graphics pixel).  The invader pictures are terminal tiles (terminal
; firmware v1.4: 19 SET TILE, 0B SEND TILE), and a row of the formation is
; sent as runs of one tile with the repeat count (attribute bits 3-6).  Bullets, bombs, the ground line, the title box and the
; damage to the shields use the set (05 x y) and reset (06 x y) pixel codes.
;
; Coordinates: text is 80 x 24, pixels are 160 x 96 (one character cell is
; 2 x 4 pixels), so a character at column c, row r covers pixels
; x = 2c..2c+1, y = 4r..4r+3.
;
; No zero page is used, so EhBASIC's and the BIOS's zero page are untouched.
; ============================================================================

        .setcpu "6502"

        .include "sbc_api.inc"   ; fixed ROM entry points ($FE00 table)

SPEED_DEFAULT   = 10

; ---- terminal control codes (control code mode) ----------------------------
TC_CURSOR       = $02           ; n   cursor character (0 = off)
TC_SETPIX       = $05           ; x y set a pixel
TC_CLRPIX       = $06           ; x y reset a pixel
TC_CLS          = $0C           ; clear screen
TC_COL          = $0E           ; n   set column
TC_ROW          = $0F           ; n   set row
TC_ATTR         = $18           ; n   attribute ($80 = block graphics)
TC_LIT          = $1A           ; n   draw n as a character
TC_TILE         = $0B           ; n   draw tile n            (terminal v1.4)
TC_DEFTILE      = $19           ; n c r data: define tile n  (terminal v1.4)
T_BLANK         = 6             ; tiles 0-5: the invader frames + a gap (4 x 1)
ATTR_TEXT       = $00
ATTR_GFX        = $80
ATTR_RV         = $04
; reverse video is an ANSI sequence (in terminal v1.4, attribute bit 2 is the
; double size font, not reverse)
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
TERM            = $FF           ; string terminator (0 is a valid argument)

; ---- screen layout ---------------------------------------------------------
UFO_ROW         = 2
PLAYER_ROW      = 21
PLAYER_Y        = PLAYER_ROW*4  ; 84
SHIELD_ROW      = 18
SHIELD_Y        = SHIELD_ROW*4  ; 72, shields are 8 x 6 pixels
GROUND_Y        = 90
NROWS           = 5
NCOLS           = 8
FORM_X          = 8             ; starting column of the formation
FORM_Y          = 4             ; starting row of the top invader row

; ============================================================================
        .segment "CODE"

        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

        .include "ay/sfx.s"     ; sound effects on the AY-3-8910 card

; ----------------------------------------------------------------------------
; I/O.  putc preserves A, X and Y (as the BIOS CHROUT does).  getc returns
; carry set and the key in A, or carry clear.  X and Y are preserved.
; ----------------------------------------------------------------------------
putc            = SBC_CHROUT    ; preserves A, X, Y
getc            = SBC_CHRIN     ; carry set = key in A

; output A as a block graphics pattern (codes 00-1F and 7F need a 1A first)
putblk: cmp     #$20
        bcc     @lit
        cmp     #$7F
        bne     @out
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@out:   jmp     putc

; blank block graphics cell
putblank:
        lda     #TC_LIT
        jsr     putc
        lda     #0
        jmp     putc

; move the cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
        lda     #TC_COL
        jsr     putc
        txa
        jmp     putc

; set / reset the pixel at X, Y.  Preserves X and Y.
setpix: lda     #TC_SETPIX
        bne     pix
clrpix: lda     #TC_CLRPIX
pix:    jsr     putc
        txa
        jsr     putc
        tya
        jmp     putc

; select block graphics / plain text (only sends the code when it changes)
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

; print the string at A (lo) / Y (hi), terminated by $FF.  It may contain
; control codes and their arguments.  Self-modifying, so no zero page needed.
print:  sta     @ld+1
        sty     @ld+2
        ldy     #0
@ld:    lda     $FFFF,y
        cmp     #TERM
        beq     @done
        jsr     putc
        iny
        bne     @ld
@done:  rts

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

; 16 bit Galois LFSR.  Returns a random byte in A.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait about speed ms (one game tick)
tick_delay:
        lda     speed
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

; horizontal line of pixels: X = x0, Y = y, A = length
hline:  sta     tmp
@l:     jsr     setpix
        inx
        dec     tmp
        bne     @l
        rts

; vertical line of pixels: X = x, Y = y0, A = length
vline:  sta     tmp
@l:     jsr     setpix
        iny
        dec     tmp
        bne     @l
        rts

.macro MENU_IDLE
        jsr     rand            ; stir the random numbers while waiting
        jsr     sfx_poll
.endmacro
CTRL_COL        = 19
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
; start
; ============================================================================
start:  cld
        ldx     #$FF
        txs


        lda     #0              ; clear all variables
        tax
@clr:   sta     vars_start,x
        inx
        cpx     #vars_end-vars_start
        bne     @clr
        lda     #$A5            ; any non-zero seed (the title screen stirs it)
        sta     rng
        lda     ctrl_def
        sta     ctrl
        lda     #$FF
        sta     attr            ; unknown, so the first mode change is sent
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute

; ---- title screen ----------------------------------------------------------
title:  jsr     screen_init
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        ; draw the invaders next to their point values
        jsr     gfx_mode
        ldx     #30
        ldy     #10
        jsr     gotoxy
        ldx     #0              ; squid
        jsr     put_sprite3
        ldx     #30
        ldy     #12
        jsr     gotoxy
        ldx     #6              ; crab
        jsr     put_sprite3
        ldx     #30
        ldy     #14
        jsr     gotoxy
        ldx     #12             ; octopus
        jsr     put_sprite3
        ldx     #29
        ldy     #8
        jsr     gotoxy
        jsr     put_ufo_sprite
        ; a box around the title, drawn with pixels
        ldx     #44
        ldy     #4
        lda     #72
        jsr     hline           ; top    (44..115, 4)
        ldx     #44
        ldy     #15
        lda     #72
        jsr     hline           ; bottom
        ldx     #44
        ldy     #5
        lda     #10
        jsr     vline           ; left
        ldx     #115
        ldy     #5
        lda     #10
        jsr     vline           ; right

        jsr     show_ctrl
        jsr     read_pad
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @notq
        jmp     exit_game
@notq:  cmp     #'M'            ; sound on / off
        bne     @notm
        jsr     toggle_sound
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
        jsr     sfx_poll
        jsr     read_keys
        lda     quit
        beq     @noquit
        jmp     exit_game
@noquit:
        jsr     move_player
        jsr     move_bullet
        jsr     fire
        jsr     move_bombs
        lda     dead
        beq     @alive
        jsr     player_died
        lda     lives
        beq     game_over
@alive: jsr     spawn_bomb
        jsr     ufo_tick
        jsr     inv_tick
        jsr     expl_tick
        lda     invaded
        bne     game_over
        lda     alive_count
        bne     @more
        inc     wave
        jsr     sfx_off
        lda     #SND_WAVE
        ldx     #3
        jsr     sfx_play
        lda     #20
        jsr     delay_long      ; 1 s pause between waves
        jmp     new_wave
@more:  jsr     tick_delay
        jmp     game_loop

; ---- game over ----------------------------------------------------------------
game_over:
        lda     score+1         ; new high score?
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
        jsr     txt_mode
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        lda     #20
        jsr     delay_long      ; ignore keys for a second
        jsr     flush_in
@wait:  jsr     menu_key
        cmp     #'Q'
        beq     exit_game
        cmp     #'M'
        bne     @nm
        jsr     toggle_sound
        jmp     @wait
@nm:    cmp     #' '            ; space or the pad's A / Start: play again
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game

; ---- quit ------------------------------------------------------------------
exit_game:
        jsr     sfx_off
        jsr     txt_mode
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
exit_menu:
        jmp     SBC_MENU        ; back to the boot menu

; ============================================================================
; screen setup
; ============================================================================

; clear the screen, cursor off, text mode
screen_init:
        lda     #$FF
        sta     attr
        jsr     txt_mode
        lda     #<init_txt
        ldy     #>init_txt
        jsr     print
; store the invader pictures in the terminal as tiles: tile k = the 3
; characters of sprite 3k and a blank gap (4 x 1); tile 6 = 4 blanks
def_tiles:
        ldx     #0
@t:     lda     #TC_DEFTILE
        jsr     putc
        txa
        jsr     putc            ; slot
        lda     #4
        jsr     putc
        lda     #1
        jsr     putc
        txa                     ; the sprite's bytes: 3 * slot
        sta     tmp
        asl
        adc     tmp
        tay
        cpx     #T_BLANK
        beq     @blank
        lda     sprites,y
        jsr     putc
        lda     sprites+1,y
        jsr     putc
        lda     sprites+2,y
        jsr     putc
        lda     #0
        jsr     putc
        jmp     @n
@blank: lda     #0
        jsr     putc
        jsr     putc
        jsr     putc
        jsr     putc
@n:     inx
        cpx     #T_BLANK+1
        bne     @t
        rts

; repeat every character (and tile) A times from now on, block graphics
set_rep:cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        jmp     setattr
@one:   lda     #ATTR_GFX
        jmp     setattr

; set up a new wave
init_wave:
        ldx     #NROWS-1
@row:   lda     #$FF
        sta     alive,x
        lda     #FORM_X
        sta     rowx,x
        lda     #0
        sta     rowfrm,x
        txa                     ; rowy = FORM_Y + 2*row + min(wave, 4)
        asl
        clc
        adc     #FORM_Y
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
        sta     bul_on
        sta     bomb_on
        sta     bomb_on+1
        sta     bomb_on+2
        sta     ufo_on
        sta     expl_t
        sta     shield_gone
        lda     wave            ; bombs get more frequent each wave
        cmp     #6
        bcc     @r
        lda     #6
@r:     asl
        asl
        asl
        clc
        adc     #12             ; 12 .. 60 out of 256 per tick
        sta     bomb_rate
        lda     #38
        sta     px
        ldx     #4*6-1          ; fresh shields
@sh:    lda     shield_shape,x
        sta     shields,x
        dex
        bpl     @sh
        rts

; draw the whole playfield
draw_all:
        jsr     screen_init
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        jsr     show_score
        jsr     show_lives
        ; ground line
        ldx     #0
        ldy     #GROUND_Y
        lda     #160
        jsr     hline
        ; shields, as block graphics characters
        jsr     gfx_mode
        lda     #3
        sta     tmp2
@shield:ldx     tmp2
        lda     shield_col,x
        tax
        ldy     #SHIELD_ROW
        jsr     gotoxy
        ldx     #0
@s1:    lda     shield_chars,x
        jsr     putblk
        inx
        cpx     #4
        bne     @s1
        ldx     tmp2
        lda     shield_col,x
        tax
        ldy     #SHIELD_ROW+1
        jsr     gotoxy
        ldx     #4
@s2:    lda     shield_chars,x
        jsr     putblk
        inx
        cpx     #8
        bne     @s2
        dec     tmp2
        bpl     @shield
        ; invaders and player
        ldx     #NROWS-1
@inv:   jsr     draw_row
        dex
        bpl     @inv
        jmp     draw_player

show_score:
        jsr     txt_mode
        ldx     #6
        ldy     #0
        jsr     gotoxy
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        ldx     #38
        ldy     #0
        jsr     gotoxy
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jmp     prbcd

show_lives:
        jsr     txt_mode
        ldx     #78
        ldy     #0
        jsr     gotoxy
        lda     lives
        ora     #'0'
        jmp     putc

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

; output the 3 block characters of sprite X (offset into sprites).
; Preserves Y.
put_sprite3:
        lda     sprites,x
        jsr     putblk
        lda     sprites+1,x
        jsr     putblk
        lda     sprites+2,x
        jmp     putblk

put_ufo_sprite:
        ldx     #0
@l:     lda     ufo_spr,x
        jsr     putblk
        inx
        cpx     #4
        bne     @l
        rts

; ============================================================================
; keyboard
; ============================================================================
read_keys:
        lda     #0
        sta     key_dir
        sta     key_fire
        lda     ctrl
        beq     @l
        jsr     read_pad        ; gamepad: buttons held move and fire
        lda     pad
        and     #PAD_LEFT
        beq     @nl
        lda     #$FF
        sta     key_dir
@nl:    lda     pad
        and     #PAD_RIGHT
        beq     @nr
        lda     #1
        sta     key_dir
@nr:    lda     pad
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
        ldx     esc_st          ; ESC [ C / ESC [ D are the arrow keys
        beq     @plain
        cpx     #1
        bne     @esc2
        cmp     #'['
        beq     @br
        cmp     #'O'
        beq     @br
        lda     #0              ; not an arrow key sequence
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
        sta     key_dir
        rts
@right: lda     #1
        sta     key_dir
        rts
@fire:  lda     #1
        sta     key_fire
        rts
@quit:  lda     #1
        sta     quit
        rts
@pause: jsr     sfx_hush        ; (quiet while paused)
@pw:    jsr     getc            ; wait for any key
        bcc     @pw
        rts

; M: sound on / off
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
; player
; ============================================================================
move_player:
        lda     key_dir
        beq     @done
        clc
        adc     px
        cmp     #1
        bcc     @done
        cmp     #77
        bcs     @done
        sta     px
        jmp     draw_player
@done:  rts

; blank, cannon, blank at columns px-1 .. px+3
draw_player:
        jsr     gfx_mode
        ldx     px
        dex
        ldy     #PLAYER_ROW
        jsr     gotoxy
        jsr     putblank
        ldx     #SPR_PLAYER
        jsr     put_sprite3
        jmp     putblank

fire:   lda     key_fire
        beq     @done
        lda     bul_on
        bne     @done
        lda     px              ; x = middle of the cannon
        asl
        clc
        adc     #2
        sta     bul_x
        tax
        lda     #PLAYER_Y-2
        sta     bul_y
        tay
        jsr     setpix
        iny
        jsr     setpix
        lda     #1
        sta     bul_on
        lda     #0
        sta     bul_keep
        lda     #SND_SHOT
        ldx     #4
        jmp     sfx_play
@done:  rts

; the player's bullet is 2 pixels tall and moves up 2 pixels per tick
move_bullet:
        lda     bul_on
        beq     @done
        ldx     bul_x
        ldy     bul_y
        lda     bul_keep
        jsr     erase_shot
        lda     #0
        sta     bul_keep
        lda     #2
        sta     bul_n
@step:  dec     bul_y
        lda     bul_y
        cmp     #4              ; reached the status line
        bcc     @off
        jsr     bul_collide
        bcs     @off
        dec     bul_n
        bne     @step
        ldx     bul_x
        ldy     bul_y
        jsr     setpix
        iny
        jsr     setpix
@done:  rts
@off:   lda     #0
        sta     bul_on
        rts

; has the bullet's tip at bul_x, bul_y hit something?  Carry set if so.
bul_collide:
        lda     ufo_on          ; the saucer?
        beq     @inv
        lda     bul_y
        cmp     #UFO_ROW*4
        bcc     @inv
        cmp     #UFO_ROW*4+4
        bcs     @inv
        lda     bul_x
        lsr
        sec
        sbc     ufo_x
        cmp     #4
        bcs     @inv
        jsr     ufo_hit
        sec
        rts
@inv:   lda     bul_y           ; an invader?
        lsr
        lsr
        sta     tmp_row
        lda     bul_x
        lsr
        sta     tmp_col
        ldx     #NROWS-1
@rl:    lda     alive,x
        beq     @next
        lda     rowy,x
        cmp     tmp_row
        bne     @next
        lda     tmp_col
        sec
        sbc     rowx,x          ; (rowx can be "negative" when the left
        cmp     #NCOLS*4        ;  slots are empty, so ignore the borrow)
        bcs     @next           ; not in this row
        tay
        and     #3
        cmp     #3
        beq     @next           ; the gap between two invaders
        tya
        lsr
        lsr
        tay                     ; slot
        lda     alive,x
        and     bitmask,y
        beq     @next
        jsr     kill_inv
        sec
        rts
@next:  dex
        bpl     @rl
        ldx     bul_x           ; a shield?
        ldy     bul_y
        jmp     shield_hit

; ============================================================================
; shields: 4 bitmaps of 8 x 6 pixels, bit 7 = left
; ============================================================================

; if the shield pixel at X, Y is set, reset it and return carry set
shield_hit:
        tya
        sec
        sbc     #SHIELD_Y
        cmp     #6
        bcs     @no
        sta     sh_line
        stx     sh_x
        sty     sh_y
        ldy     #3
@k:     txa
        sec
        sbc     shield_x,y
        cmp     #8
        bcc     @found
        dey
        bpl     @k
@no:    clc
        rts
@found: tax
        lda     bitmask_hi,x
        sta     sh_m
        tya                     ; shield * 6 + line
        asl
        sta     tmp
        asl
        clc
        adc     tmp
        adc     sh_line
        tax
        lda     shields,x
        and     sh_m
        beq     @no
        lda     sh_m
        eor     #$FF
        and     shields,x
        sta     shields,x
        ldx     sh_x
        ldy     sh_y
        jsr     clrpix
        sec
        rts

; the invaders have come down to the shields: remove them
wipe_shields:
        lda     shield_gone
        bne     @done
        inc     shield_gone
        jsr     txt_mode
        ldx     #4*6-1
        lda     #0
@z:     sta     shields,x
        dex
        bpl     @z
        lda     #3
        sta     tmp2
@sh:    ldx     tmp2
        lda     shield_col,x
        tax
        ldy     #SHIELD_ROW
        jsr     gotoxy
        jsr     spaces4
        iny
        jsr     gotoxy
        jsr     spaces4
        dec     tmp2
        bpl     @sh
@done:  rts

spaces4:lda     #' '
        jsr     putc
        jsr     putc
        jsr     putc
        jmp     putc

; ============================================================================
; invaders
; ============================================================================

; first and last live slot of row X -> ext_s0, ext_s1.  The row must have a
; live invader.  Preserves X.
row_extent:
        lda     alive,x
        ldy     #$FF
@l:     iny
        lsr
        bcc     @l
        sty     ext_s0
        lda     alive,x
        ldy     #NCOLS
@h:     dey
        asl
        bcc     @h
        sty     ext_s1
        rts

; draw row X from (first live slot) - 1 to (last live slot) + 3, so that the
; blanks at each end erase where the row was before a move.  Preserves X.
draw_row:
        lda     alive,x
        bne     @go
        rts
@go:    stx     dr_r
        jsr     row_extent
        jsr     gfx_mode
        ldx     dr_r
        lda     rowfrm,x        ; next animation frame
        eor     #3
        sta     rowfrm,x
        clc
        adc     rowtype,x
        sta     dr_spr
        lda     ext_s0          ; column = rowx + 4 * s0 - 1
        asl
        asl
        clc
        adc     rowx,x
        sec
        sbc     #1
        sta     dr_c0
        lda     rowy,x
        sta     dr_row
        lda     ext_s1          ; end column (exclusive) = start + 4*(s1-s0) + 5
        sec
        sbc     ext_s0
        asl
        asl
        sec
        adc     #4
        adc     dr_c0
        sta     dr_c1
        jsr     mark_over
        ldx     dr_c0
        ldy     dr_row
        jsr     gotoxy
        jsr     putblank
        ldx     dr_r
        lda     alive,x
        ldy     ext_s0
        beq     @sh_done
@sh:    lsr
        dey
        bne     @sh
@sh_done:
        sta     dr_mask
        lda     ext_s1
        sec
        sbc     ext_s0
        sta     dr_cnt
        lda     dr_spr          ; its tile: sprite number / 3
        ldx     #$FF
@div:   inx
        sec
        sbc     #3
        bcs     @div
        stx     dr_tile
@slot:  lda     dr_mask         ; a run of invaders (or of gaps) in a row:
        and     #1              ; one tile, repeated
        sta     dr_kind
        lda     #0
        sta     dr_n
@cnt:   inc     dr_n
        lsr     dr_mask
        dec     dr_cnt
        bmi     @emit
        lda     dr_mask
        and     #1
        cmp     dr_kind
        bne     @emit
        lda     dr_n
        cmp     #15
        bcc     @cnt
@emit:  lda     dr_n
        jsr     set_rep
        lda     #TC_TILE
        jsr     putc
        lda     #T_BLANK
        ldx     dr_kind
        beq     @t
        lda     dr_tile
@t:     jsr     putc
        lda     dr_cnt
        bpl     @slot
        jsr     gfx_mode        ; (repeat off again)
        ldx     dr_r
        rts

; draw_row is about to overwrite columns dr_c0 .. dr_c1-1 of row dr_row.
; Any bullet or bomb pixel there is replaced by the invader picture, so it
; must not be erased later (that would punch a hole in an invader).
mark_over:
        lda     bul_on
        beq     @bombs
        lda     bul_x
        ldy     bul_y
        jsr     over_bits
        ora     bul_keep
        sta     bul_keep
@bombs: ldx     #2
@b:     lda     bomb_on,x
        beq     @nb
        lda     bomb_x,x
        ldy     bomb_y,x
        jsr     over_bits
        beq     @nb
        cmp     #1
        beq     @top
        lda     #0              ; the row came down onto the bomb: the
        sta     bomb_on,x       ; invader swallows it
        ldy     bomb_y,x        ; (over_bits changed Y)
        lda     bomb_keep,x
        ora     #2
        stx     bm_i
        pha
        lda     bomb_x,x
        tax
        pla
        jsr     erase_shot      ; erase the top pixel if it's outside the row
        ldx     bm_i
        jmp     @nb
@top:   ora     bomb_keep,x
        sta     bomb_keep,x
@nb:    dex
        bpl     @b
        rts

; A = pixel x, Y = top pixel y of a 2 pixel tall shot.  Returns A: bit 0 set
; if pixel (x, y) is in the overwritten span, bit 1 if (x, y+1) is.
; Preserves X.
over_bits:
        lsr
        cmp     dr_c0
        bcc     @none
        cmp     dr_c1
        bcs     @none
        lda     #0
        sta     tmp
        tya
        lsr
        lsr
        cmp     dr_row
        bne     @1
        lda     #1
        sta     tmp
@1:     iny
        tya
        lsr
        lsr
        cmp     dr_row
        bne     @2
        lda     tmp
        ora     #2
        sta     tmp
@2:     lda     tmp
        rts
@none:  lda     #0
        rts

; erase a 2 pixel shot at X, Y unless keep (in A) says it was drawn over
erase_shot:
        sta     tmp
        lsr     tmp
        bcs     @1
        jsr     clrpix
@1:     iny
        lsr     tmp
        bcs     @2
        jsr     clrpix
@2:     dey
        rts

; blank row X where it is now (before it moves down a line).  Preserves X.
erase_row:
        stx     dr_r
        jsr     row_extent
        lda     ext_s0
        asl
        asl
        clc
        adc     rowx,x
        sec
        sbc     #1
        sta     tmp_col
        lda     ext_s1
        sec
        sbc     ext_s0
        asl
        asl
        clc
        adc     #5
        sta     tmp
        jsr     txt_mode
        ldy     rowy,x
        ldx     tmp_col
        jsr     gotoxy
@l:     lda     tmp             ; spaces, up to 15 at a time (repeat count)
        cmp     #15
        bcc     @c
        lda     #15
@c:     sta     dr_n
        asl
        asl
        asl
        jsr     setattr         ; text, repeat dr_n times
        lda     #' '
        jsr     putc
        lda     tmp
        sec
        sbc     dr_n
        sta     tmp
        bne     @l
        jsr     txt_mode        ; (repeat off again)
        ldx     dr_r
        rts

; move one row of the formation each step, bottom row first, like the
; arcade game.  The step rate goes up as invaders are shot.
inv_tick:
        dec     inv_t
        beq     @go
        rts
@go:    lda     alive_count     ; ticks per step = alive / 8 + 1
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
@do:    lda     expl_t          ; an explosion in this row is removed first
        beq     @noexp
        cpx     expl_r
        bne     @noexp
        jsr     expl_blank
        ldx     cur_row
@noexp: lda     dropping
        beq     @horiz
        jsr     erase_row
        inc     rowy,x
        jmp     @draw
@horiz: lda     rowx,x
        clc
        adc     dir
        sta     rowx,x
@draw:  jsr     draw_row
        dec     cur_row
        rts

@sweep_end:                     ; every row has moved: decide the next sweep
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
        lda     ext_max
        cmp     #77
        bcs     @drop
        rts
@left:  lda     ext_min
        cmp     #2
        bcs     @ok
@drop:  lda     #1
        sta     dropping
        lda     dir
        eor     #$FF
        clc
        adc     #1
        sta     dir
@ok:    rts

; leftmost and rightmost columns used by live invaders -> ext_min, ext_max
form_extent:
        lda     #$FF
        sta     ext_min
        lda     #0
        sta     ext_max
        ldx     #NROWS-1
@l:     lda     alive,x
        beq     @next
        jsr     row_extent
        lda     ext_s0
        asl
        asl
        clc
        adc     rowx,x
        cmp     ext_min
        bcs     @1
        sta     ext_min
@1:     lda     ext_s1
        asl
        asl
        clc
        adc     rowx,x
        adc     #2
        cmp     ext_max
        bcc     @next
        sta     ext_max
@next:  dex
        bpl     @l
        rts

; after the formation has come down a line: shields gone?  landed?
after_drop:
        ldx     #NROWS-1
@l:     lda     alive,x         ; lowest live row
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
@1:     cmp     #SHIELD_ROW-1
        bcc     @2
        jmp     wipe_shields
@2:     rts

; shoot invader in row X, slot Y
kill_inv:
        lda     bitmask,y
        eor     #$FF
        and     alive,x
        sta     alive,x
        dec     alive_count
        stx     kv_r
        sty     kv_s
        lda     expl_t          ; only one explosion at a time
        beq     @1
        jsr     expl_blank
@1:     ldx     kv_r
        lda     kv_s
        asl
        asl
        clc
        adc     rowx,x
        sta     expl_col
        lda     rowy,x
        sta     expl_row
        stx     expl_r
        lda     #6
        sta     expl_t
        jsr     gfx_mode
        ldx     expl_col
        ldy     expl_row
        jsr     gotoxy
        ldx     #SPR_EXPL
        jsr     put_sprite3
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
        beq     expl_blank
@done:  rts

; remove the explosion from the screen
expl_blank:
        lda     #0
        sta     expl_t
        jsr     gfx_mode
        ldx     expl_col
        ldy     expl_row
        jsr     gotoxy
        jsr     putblank
        jsr     putblank
        jmp     putblank

; ============================================================================
; bombs: 3 of them, 2 pixels tall, falling 1 pixel per tick
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
@found: tya
        asl
        asl
        clc
        adc     rowx,x
        asl
        adc     #2
        sta     tmp
        lda     rowy,x
        asl
        asl
        adc     #4
        ldx     bm_i
        sta     bomb_y,x
        lda     tmp
        sta     bomb_x,x
        lda     #1
        sta     bomb_on,x
        lda     #0
        sta     bomb_keep,x
        rts

move_bombs:
        lda     #2
        sta     bm_i
@l:     ldx     bm_i
        lda     bomb_on,x
        beq     @next
        lda     bomb_keep,x
        pha
        lda     #0
        sta     bomb_keep,x
        lda     bomb_y,x
        tay
        lda     bomb_x,x
        tax
        pla
        jsr     erase_shot
        iny
        iny                     ; Y = new bottom pixel
        cpy     #GROUND_Y
        bcs     @gone
        cpy     #PLAYER_Y       ; the player?
        bcc     @noplayer
        txa
        lsr
        sec
        sbc     px
        cmp     #3
        bcs     @noplayer
        lda     #1
        sta     dead
        bne     @gone
@noplayer:
        jsr     shield_hit
        bcc     @move
        iny                     ; take out the pixel below too
        jsr     shield_hit
        jmp     @gone
@move:  ldx     bm_i
        inc     bomb_y,x
        lda     bomb_y,x
        tay
        lda     bomb_x,x
        tax
        jsr     setpix
        iny
        jsr     setpix
        jmp     @next
@gone:  ldx     bm_i
        lda     #0
        sta     bomb_on,x
@next:  dec     bm_i
        bpl     @l
        rts

; the player was hit
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
        lda     #6              ; flash the explosion
        sta     tmp3
@flash: jsr     gfx_mode
        ldx     px
        ldy     #PLAYER_ROW
        jsr     gotoxy
        lda     tmp3
        and     #1
        beq     @e0
        ldx     #SPR_EXPL2
        bne     @e1
@e0:    ldx     #SPR_EXPL
@e1:    jsr     put_sprite3
        lda     #150
        jsr     delay_ms
        jsr     flush_in        ; (drop keys pressed meanwhile)
        dec     tmp3
        bne     @flash
        ldx     #2              ; remove the bombs and the bullet
@b:     lda     bomb_on,x
        beq     @nb
        lda     #0
        sta     bomb_on,x
        stx     bm_i
        lda     bomb_keep,x
        pha
        lda     bomb_y,x
        tay
        lda     bomb_x,x
        tax
        pla
        jsr     erase_shot
        ldx     bm_i
@nb:    dex
        bpl     @b
        lda     bul_on
        beq     @nbul
        lda     #0
        sta     bul_on
        ldx     bul_x
        ldy     bul_y
        lda     bul_keep
        jsr     erase_shot
@nbul:  jsr     gfx_mode        ; remove the wreck
        ldx     px
        ldy     #PLAYER_ROW
        jsr     gotoxy
        jsr     putblank
        jsr     putblank
        jsr     putblank
        dec     lives
        jsr     show_lives
        lda     lives
        beq     @done
        lda     #38
        sta     px
        jsr     draw_player
        lda     #10
        jsr     delay_long
        jsr     read_keys       ; forget keys typed meanwhile
        lda     ufo_on          ; the saucer's hum again
        beq     @done
        lda     #SND_UFO
        ldx     #1
        jsr     sfx_play
@done:  rts

; ============================================================================
; the saucer, 4 characters wide on row 2
; ============================================================================
ufo_tick:
        lda     ufo_on
        bne     @move
        jsr     rand            ; maybe start one
        cmp     #2
        bcs     @done
        lda     alive_count
        cmp     #8
        bcc     @done
        jsr     rand
        and     #1
        beq     @fromleft
        lda     #74
        sta     ufo_x
        lda     #$FF
        bne     @start
@fromleft:
        lda     #1
        sta     ufo_x
        lda     #1
@start: sta     ufo_dir
        lda     #1
        sta     ufo_on
        lda     #SND_UFO        ; its hum, in the background
        ldx     #1
        jsr     sfx_play
        jmp     draw_ufo
@move:  lda     ufo_t           ; moves every other tick
        eor     #1
        sta     ufo_t
        beq     @done
        lda     ufo_x
        ldx     ufo_dir
        bmi     @l
        cmp     #74
        bcs     @off
        bcc     @mv
@l:     cmp     #2
        bcc     @off
@mv:    clc
        adc     ufo_dir
        sta     ufo_x
        jmp     draw_ufo
@off:   lda     #0
        sta     ufo_on
        ldx     #1
        jsr     sfx_stop
        jmp     erase_ufo
@done:  rts

; blank, saucer, blank at columns ufo_x-1 .. ufo_x+4
draw_ufo:
        jsr     gfx_mode
        ldx     ufo_x
        dex
        ldy     #UFO_ROW
        jsr     gotoxy
        jsr     putblank
        jsr     put_ufo_sprite
        jmp     putblank

erase_ufo:
        jsr     gfx_mode
        ldx     ufo_x
        dex
        ldy     #UFO_ROW
        jsr     gotoxy
        ldx     #6
@l:     jsr     putblank
        dex
        bne     @l
        rts

ufo_hit:
        lda     #0
        sta     ufo_on
        ldx     #1
        jsr     sfx_stop
        lda     #SND_UFO_HIT
        ldx     #5
        jsr     sfx_play
        jsr     erase_ufo
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

; sprites: 3 block graphics characters each (6 x 4 pixels)
SPR_PLAYER      = 18
SPR_EXPL        = 21
SPR_EXPL2       = 24
sprites:
        .byte   $98, $3F, $64   ;  0 squid, frame 0
        .byte   $58, $3F, $A4   ;  3 squid, frame 1
        .byte   $9D, $3C, $6E   ;  6 crab
        .byte   $5E, $3C, $AD   ;  9
        .byte   $76, $3F, $B9   ; 12 octopus
        .byte   $B6, $3F, $79   ; 15
        .byte   $F8, $FF, $F4   ; 18 player
        .byte   $49, $5A, $92   ; 21 explosion
        .byte   $66, $4C, $59   ; 24 explosion 2
ufo_spr:.byte   $B8, $AF, $5F, $74

rowtype:.byte   0, 6, 6, 12, 12 ; sprite for each row
points: .byte   $30, $20, $20, $10, $10
ufo_pts_lo: .byte $50, $00, $50, $00
ufo_pts_hi: .byte $00, $01, $01, $03
bitmask:.byte   $01, $02, $04, $08, $10, $20, $40, $80
bitmask_hi:
        .byte   $80, $40, $20, $10, $08, $04, $02, $01

shield_x:   .byte 16, 56, 96, 136           ; left pixel of each shield
shield_col: .byte 8, 28, 48, 68             ; = shield_x / 2
shield_shape:                               ; 8 x 6, bit 7 = left
        .byte   $7E, $FF, $FF, $FF, $E7, $C3
        .byte   $7E, $FF, $FF, $FF, $E7, $C3
        .byte   $7E, $FF, $FF, $FF, $E7, $C3
        .byte   $7E, $FF, $FF, $FF, $E7, $C3
shield_chars:                               ; the same shape as block graphics
        .byte   $FE, $FF, $FF, $FD          ; top row of characters
        .byte   $0F, $01, $02, $0F          ; bottom row (2 pixel lines)

init_txt:
        .byte   TC_CLS, TC_CURSOR, 0, TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "SCORE"
        .byte   TC_COL, 29, "HI-SCORE"
        .byte   TC_COL, 72, "LIVES", TERM
title_txt:
        .byte   TC_ROW, 2, TC_COL, 33, RV_ON, " SPACE INVADERS ", RV_OFF, TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 8, TC_COL, 34, "= ? MYSTERY"
        .byte   TC_ROW, 10, TC_COL, 34, "= 30 POINTS"
        .byte   TC_ROW, 12, TC_COL, 34, "= 20 POINTS"
        .byte   TC_ROW, 14, TC_COL, 34, "= 10 POINTS"
        .byte   TC_ROW, 16, TC_COL, 13, "KEYBOARD: A/D OR ARROWS MOVE, SPACE FIRE, P PAUSE"
        .byte   TC_ROW, 17, TC_COL, 13, "GAMEPAD:  LEFT/RIGHT MOVE, A OR B FIRE, START PAUSE"
        .byte   TC_ROW, 18, TC_COL, 13, "M: SOUND ON/OFF   Q: QUIT"
        .byte   TC_ROW, 22, TC_COL, 25, "PRESS SPACE OR START TO PLAY", TERM
over_txt:
        .byte   TC_ROW, 10, TC_COL, 33, RV_ON, "   GAME OVER   "
        .byte   TC_ROW, 11, TC_COL, 33, "               "
        .byte   TC_ROW, 12, TC_COL, 33, " SPACE/A: PLAY "
        .byte   TC_ROW, 13, TC_COL, 33, " Q: QUIT       ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM
bye_txt:
        .byte   TC_CLS, TC_CURSOR, '_', TERM

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

ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM

; ============================================================================
; variables (not in the file; cleared at start)
; ============================================================================
        .segment "BSS"
vars_start:
ctrl:       .res 1              ; 0 keyboard, 1 gamepad
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
hiscore:    .res 2
rng:        .res 2
attr:       .res 1
score:      .res 2
lives:      .res 1
wave:       .res 1
px:         .res 1
key_dir:    .res 1
key_fire:   .res 1
quit:       .res 1
esc_st:     .res 1
bul_on:     .res 1
bul_x:      .res 1
bul_y:      .res 1
bul_n:      .res 1
bul_keep:   .res 1              ; bits 0/1: pixel drawn over, don't erase
bomb_on:    .res 3
bomb_x:     .res 3
bomb_y:     .res 3
bomb_keep:  .res 3
bm_i:       .res 1
bomb_rate:  .res 1
ufo_on:     .res 1
ufo_x:      .res 1
ufo_dir:    .res 1
ufo_t:      .res 1
alive:      .res NROWS          ; bit n = invader in slot n is alive
rowx:       .res NROWS          ; column of slot 0
rowy:       .res NROWS          ; text row
rowfrm:     .res NROWS          ; animation frame (0 or 3)
alive_count:.res 1
dir:        .res 1              ; +1 or -1
dropping:   .res 1
cur_row:    .res 1
inv_t:      .res 1
expl_t:     .res 1
expl_col:   .res 1
expl_row:   .res 1
expl_r:     .res 1
shields:    .res 4*6
shield_gone:.res 1
invaded:    .res 1
dead:       .res 1
dr_r:       .res 1
dr_spr:     .res 1
dr_mask:    .res 1
dr_cnt:     .res 1
dr_tile:    .res 1
dr_kind:    .res 1
dr_n:       .res 1
dr_c0:      .res 1
dr_c1:      .res 1
dr_row:     .res 1
ext_s0:     .res 1
ext_s1:     .res 1
ext_min:    .res 1
ext_max:    .res 1
kv_r:       .res 1
kv_s:       .res 1
sh_line:    .res 1
sh_x:       .res 1
sh_y:       .res 1
sh_m:       .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
tmp_row:    .res 1
tmp_col:    .res 1
march:      .res 1              ; the march's next note
vars_end:
