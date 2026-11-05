; ============================================================================
; snake.s - the classic Snake game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal using its
; control code mode (terminal setup item J must be ON).
;
;   build:  make                (needs sbc_api.inc, the ROM's entry points)
;   run:    L SNAKE 0500     then   R
;
; Header (patchable from the monitor, same layout as INVADERS):
;   $0500  JMP start
;   $0503  speed      starting delay per move, about 1 ms per unit (default 90)
;                     the snake gets faster as it eats, down to a third of this
;   $0504  controls   at start: 0 keyboard, 1 gamepad (G on the title
;                     screen switches; A or Start on the pad picks the pad)
;   $0505  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2).  Without the card the game is just silent.
;
; Keys:  W A S D or the arrow keys   steer
;        P                         pause
;        M                         sound on / off
;        Q                         quit (back to the boot menu)
; Gamepad: the d-pad steers, Start pauses
;
; Graphics: everything in the playfield is drawn with the set (05 x y) and
; reset (06 x y) pixel codes.  The screen is 160 x 96 pixels; the snake moves
; on a grid of 2 x 2 pixel cells (square on the screen), 79 x 45 cells inside
; a 1 pixel border.  Cell (gx, gy) is pixels x = 1+2gx .. 2+2gx,
; y = 5+2gy .. 6+2gy.  Row 0 of the text screen is the status line.
;
; The playfield is also kept in RAM, one byte per cell:
;   0      empty
;   1..4   snake; the direction (1 up, 2 right, 3 down, 4 left) of the next
;          segment towards the head, so the tail can follow the body
; The cells are reached with self-modifying code, so no zero page is used.
; ============================================================================

        .setcpu "6502"

        .include "sbc_api.inc"   ; fixed ROM entry points ($FE00 table)

SPEED_DEFAULT   = 90

; ---- terminal control codes (control code mode) ----------------------------
TC_CURSOR       = $02
TC_SETPIX       = $05
TC_CLRPIX       = $06
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
ATTR_TEXT       = $00
ATTR_RV         = $04
; reverse video is an ANSI sequence (in terminal v1.4, attribute bit 2 is the
; double size font, not reverse)
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
TERM            = $FF           ; string terminator

; ---- playfield -------------------------------------------------------------
GW              = 79            ; grid width in cells
GH              = 45            ; grid height in cells
PX0             = 1             ; pixel x of cell 0
PY0             = 5             ; pixel y of cell 0
UP              = 1
RIGHT           = 2
DOWN            = 3
LEFT            = 4
GROW_PER_FOOD   = 3

; ============================================================================
        .segment "CODE"

        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound effects on the AY-3-8910 card

; ----------------------------------------------------------------------------
; I/O and helpers (as in INVADERS)
; ----------------------------------------------------------------------------
putc            = SBC_CHROUT    ; preserves A, X, Y
getc            = SBC_CHRIN     ; carry set = key in A

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

; print the string at A (lo) / Y (hi), terminated by $FF
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

; ----------------------------------------------------------------------------
; grid access.  cell_at points grid_rd / grid_wr at cell X, Y.
; Preserves X and Y.
; ----------------------------------------------------------------------------
cell_at:
        txa
        clc
        adc     row_lo,y
        sta     grid_rd+1
        sta     grid_wr+1
        lda     row_hi,y
        adc     #0
        sta     grid_rd+2
        sta     grid_wr+2
        rts
grid_rd:lda     $FFFF           ; operand set by cell_at
        rts
grid_wr:sta     $FFFF
        rts

; draw / erase cell X, Y (2 x 2 pixels).  Preserves nothing.
cell_pixels:                    ; X, Y -> pixel X, Y of the cell's top left
        txa
        asl
        adc     #PX0            ; (carry is clear: gx*2 < 256)
        tax
        tya
        asl
        adc     #PY0
        tay
        rts

draw_cell:
        jsr     cell_pixels
        jsr     setpix
        inx
        jsr     setpix
        iny
        jsr     setpix
        dex
        jmp     setpix

erase_cell:
        jsr     cell_pixels
        jsr     clrpix
        inx
        jsr     clrpix
        iny
        jsr     clrpix
        dex
        jmp     clrpix

; food is the two pixels on one diagonal of its cell
draw_food:
        ldx     food_x
        ldy     food_y
        jsr     cell_pixels
        jsr     setpix
        inx
        iny
        jmp     setpix

.macro MENU_IDLE
        jsr     rand            ; stir the random numbers while waiting
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
; start
; ============================================================================
start:  cld
        ldx     #$FF
        txs
  lda     #0              ; clear the variables
        tax
@clr:   sta     vars_start,x
        inx
        cpx     #vars_end-vars_start
        bne     @clr
        lda     #$5A
        sta     rng
        lda     ctrl_def
        sta     ctrl
        lda     #$FF
        sta     attr
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute

; ---- title screen ----------------------------------------------------------
title:  jsr     screen_init
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        ; a box around the title and a little snake under it, with pixels
        ldx     #56
        ldy     #4
        lda     #48
        jsr     hline
        ldx     #56
        ldy     #15
        lda     #48
        jsr     hline
        ldx     #56
        ldy     #5
        lda     #10
        jsr     vline
        ldx     #103
        ldy     #5
        lda     #10
        jsr     vline
        ldx     #0
@demo:  stx     tmp2            ; demo snake: cells along a zigzag
        lda     demo_x,x
        ldy     demo_y,x
        tax
        jsr     draw_cell
        ldx     tmp2
        inx
        cpx     #DEMO_LEN
        bne     @demo
        ldx     #DEMO_FOOD_X
        stx     food_x
        ldy     #DEMO_FOOD_Y
        sty     food_y
        jsr     draw_food

        jsr     show_ctrl
        jsr     read_pad
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
        bne     new_game
@notp:  cmp     #' '
        bne     @wait

; ---- new game ----------------------------------------------------------------
new_game:
        jsr     init_game
        jsr     draw_all
        lda     #SND_START
        jsr     sfx_snd

; ---- main loop ---------------------------------------------------------------
game_loop:
        jsr     sfx_poll
        jsr     read_keys
        lda     quit
        beq     @noquit
        jmp     exit_game
@noquit:jsr     step
        lda     dead
        bne     game_over
        lda     move_delay
        jsr     delay_ms
        jmp     game_loop

; ---- game over ---------------------------------------------------------------
game_over:
        lda     #SND_CRASH
        jsr     sfx_snd
        lda     #SND_CRASH2
        jsr     sfx_snd
        lda     #6              ; flash the head
        sta     tmp3
@flash: ldx     head_x
        ldy     head_y
        lda     tmp3
        and     #1
        beq     @on
        jsr     erase_cell
        jmp     @w
@on:    jsr     draw_cell
@w:     lda     #120
        jsr     delay_ms
        dec     tmp3
        bne     @flash
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
        lda     #SND_HI         ; (a new high score: a fanfare)
        bne     @snd
@nohi:  lda     #SND_OVER
@snd:   jsr     sfx_snd
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        lda     #10
        jsr     delay_long      ; ignore keys for half a second
        jsr     flush_in
@wait:  jsr     menu_key
        cmp     #'Q'
        beq     exit_game
        cmp     #'M'
        bne     @nm
        jsr     sfx_toggle
        jmp     @wait
@nm:    cmp     #' '            ; space or the pad's A / Start: play again
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game

; ---- quit ------------------------------------------------------------------
exit_game:
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
exit_menu:
        jmp     SBC_MENU        ; back to the boot menu

; ============================================================================
; setup
; ============================================================================
screen_init:
        lda     #<init_txt
        ldy     #>init_txt
        jmp     print

init_game:
        lda     #0              ; empty grid (14 pages covers 79 x 45)
        ldy     #>grid
        sty     @st+2
        tax
@pg:    ldy     #0
@st:    sta     grid,x          ; high byte patched for each page
        inx
        bne     @st
        inc     @st+2
        lda     @st+2
        cmp     #>grid + GRID_PAGES
        lda     #0
        bcc     @pg
        sta     score
        sta     score+1
        sta     dead
        sta     quit
        sta     kq_n
        sta     esc_st
        lda     speed
        sta     move_delay
        lda     #RIGHT
        sta     dir
        ; a snake of 4 cells in the middle, heading right
        lda     #37
        sta     tail_x
        lda     #22
        sta     tail_y
        sta     head_y
        lda     #40
        sta     head_x
        lda     #37
        sta     tmp2
@body:  ldx     tmp2
        ldy     #22
        jsr     cell_at
        lda     #RIGHT
        jsr     grid_wr
        inc     tmp2
        lda     tmp2
        cmp     #41
        bne     @body
        lda     #0
        sta     grow
        jmp     place_food      ; (only sets food_x/y; drawn by draw_all)

draw_all:
        jsr     screen_init
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        jsr     show_score
        ; the border: block graphics characters (rows of them with the
        ; repeat count, the sides as two tiles); the bottom right corner
        ; with pixels, so the screen can't scroll
        lda     #<border_txt
        ldy     #>border_txt
        jsr     print
        ldx     #159
        ldy     #92
        lda     #4
        jsr     vline
        ldx     #158
        ldy     #95
        jsr     setpix
        ; the snake
        lda     #37
        sta     tmp2
@body:  ldx     tmp2
        ldy     #22
        jsr     draw_cell
        inc     tmp2
        lda     tmp2
        cmp     #41
        bne     @body
        jmp     draw_food

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

txt_mode:
        lda     attr
        beq     @done
        lda     #0
        sta     attr
        lda     #TC_ATTR
        jsr     putc
        lda     #0
        jmp     putc
@done:  rts

; put the food in a random empty cell
place_food:
@x:     jsr     rand
        and     #$7F
        cmp     #GW
        bcs     @x
        sta     food_x
@y:     jsr     rand
        and     #$3F
        cmp     #GH
        bcs     @y
        sta     food_y
        tay
        ldx     food_x
        jsr     cell_at
        jsr     grid_rd
        bne     @x              ; on the snake: try again
        rts

; ============================================================================
; keyboard.  Turns are queued (up to 2) so that two quick key presses within
; one move both count, e.g. a U-turn into the next lane.
; ============================================================================
read_keys:
        lda     ctrl
        beq     @l
        jsr     read_pad        ; gamepad: each new d-pad press is a turn
        lda     padnew
        and     #PAD_UP
        beq     @1
        lda     #UP
        jsr     turn
@1:     lda     padnew
        and     #PAD_DOWN
        beq     @2
        lda     #DOWN
        jsr     turn
@2:     lda     padnew
        and     #PAD_LEFT
        beq     @3
        lda     #LEFT
        jsr     turn
@3:     lda     padnew
        and     #PAD_RIGHT
        beq     @4
        lda     #RIGHT
        jsr     turn
@4:     lda     padnew
        and     #PAD_START
        beq     @l
        jsr     pad_pause
@l:     jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @l
@done:  rts

handle_key:
        ldx     esc_st          ; ESC [ A..D (or ESC O A..D) are the arrows
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
        beq     @up
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
@kb:    and     #$DF            ; letters to upper case
        cmp     #'W'
        beq     @up
        cmp     #'S'
        beq     @down
        cmp     #'D'
        beq     @right
        cmp     #'A'
        beq     @left
        cmp     #'Q'
        beq     @quit
        cmp     #'P'
        beq     @pause
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@up:    lda     #UP
        bne     turn
@down:  lda     #DOWN
        bne     turn
@right: lda     #RIGHT
        bne     turn
@left:  lda     #LEFT
        bne     turn
@quit:  lda     #1
        sta     quit
        rts
@pause: jsr     sfx_hush        ; (quiet while paused)
@pw:    jsr     getc            ; wait for any key
        bcc     @pw
        rts

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

; queue a turn to direction A, unless it is the way the snake (or the last
; queued turn) is already going, or straight back
turn:   sta     tmp
        ldx     kq_n
        cpx     #2
        bcs     @done           ; queue full
        lda     dir
        cpx     #0
        beq     @cmp
        lda     kq-1,x          ; last queued turn
@cmp:   cmp     tmp
        beq     @done           ; same way
        tay
        lda     opposite,y
        cmp     tmp
        beq     @done           ; reverse
        lda     tmp
        sta     kq,x
        inc     kq_n
@done:  rts

; ============================================================================
; one move
; ============================================================================
step:   lda     kq_n            ; take a queued turn
        beq     @go
        lda     kq
        sta     dir
        lda     kq+1
        sta     kq
        dec     kq_n
@go:    ldx     dir             ; the new head position
        lda     head_x
        clc
        adc     dx,x
        cmp     #GW             ; (-1 is $FF, also >= GW)
        bcs     @wall
        sta     new_x
        lda     head_y
        clc
        adc     dy,x
        cmp     #GH
        bcc     @iny
@wall:  jmp     @crash
@iny:   sta     new_y
        lda     new_x           ; food?
        cmp     food_x
        bne     @nofood
        lda     new_y
        cmp     food_y
        bne     @nofood
        jsr     eat
@nofood:lda     grow            ; growing: the tail stays where it is
        beq     @tail
        dec     grow
        jmp     @check
@tail:  ldx     tail_x          ; move the tail first, so the head may move
        ldy     tail_y          ; into the cell the tail just left
        jsr     cell_at
        jsr     grid_rd
        sta     tmp             ; its direction to the next segment
        lda     #0
        jsr     grid_wr
        jsr     erase_cell
        ldx     tmp
        lda     tail_x
        clc
        adc     dx,x
        sta     tail_x
        lda     tail_y
        clc
        adc     dy,x
        sta     tail_y
@check: ldx     new_x           ; ran into itself?
        ldy     new_y
        jsr     cell_at
        jsr     grid_rd
        bne     @crash
        lda     dir             ; mark the new head (its direction is
        jsr     grid_wr         ; rewritten on the next move) ...
        ldx     head_x          ; ... and link the old head to it
        ldy     head_y
        jsr     cell_at
        lda     dir
        jsr     grid_wr
        lda     new_x
        sta     head_x
        tax
        lda     new_y
        sta     head_y
        tay
        jmp     draw_cell
@crash: lda     #1
        sta     dead
        rts

; the head is about to move onto the food
eat:    lda     #SND_EAT
        jsr     sfx_snd
        lda     grow
        clc
        adc     #GROW_PER_FOOD
        sta     grow
        sed                     ; 10 points per food
        lda     score
        clc
        adc     #$10
        sta     score
        lda     score+1
        adc     #0
        sta     score+1
        cld
        jsr     show_score
        lda     speed           ; speed up: delay - 2, but not below speed/3
        lsr
        lsr
        sta     tmp
        lsr
        lsr
        adc     tmp             ; ~ speed * 5/16 ...
        sta     tmp
        lda     move_delay
        sec
        sbc     #2
        bcc     @min
        cmp     tmp
        bcs     @ok
@min:   lda     tmp
@ok:    sta     move_delay
        jsr     place_food      ; the new food (the head cell is still empty
        lda     food_x          ; in the grid, so make sure it's not there)
        cmp     new_x
        bne     @draw
        lda     food_y
        cmp     new_y
        beq     eat_again
@draw:  jmp     draw_food
eat_again:
        jsr     place_food
        lda     food_x
        cmp     new_x
        bne     @d
        lda     food_y
        cmp     new_y
        beq     eat_again
@d:     jmp     draw_food

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"

dx:     .byte   0, 0, 1, 0, $FF         ; by direction (index 0 unused)
dy:     .byte   0, $FF, 0, 1, 0
opposite:
        .byte   0, DOWN, LEFT, UP, RIGHT

; grid row addresses
row_lo:
.repeat GH, I
        .byte   <(grid + I * GW)
.endrepeat
row_hi:
.repeat GH, I
        .byte   >(grid + I * GW)
.endrepeat

; the snake on the title screen
demo_x: .byte   20,21,22,23,24,25,26,26,26,27,28,29,30,31,32,32,32,33,34,35,36,37,38,39
demo_y: .byte   18,18,18,18,18,18,18,19,20,20,20,20,20,20,20,19,18,18,18,18,18,18,18,18
DEMO_LEN = * - demo_y
DEMO_FOOD_X = 44
DEMO_FOOD_Y = 18

init_txt:
        .byte   TC_CLS, TC_CURSOR, 0, TERM
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "SCORE"
        .byte   TC_COL, 29, "HI-SCORE"
        .byte   TC_COL, 62, "P PAUSE  Q QUIT", TERM
title_txt:
        .byte   TC_ROW, 2, TC_COL, 36, RV_ON, " SNAKE ", RV_OFF, TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 13, TC_COL, 18, "STEER WITH W A S D OR THE ARROW KEYS"
        .byte   TC_ROW, 14, TC_COL, 18, "EAT THE FOOD, DON'T HIT THE WALLS OR YOURSELF"
        .byte   TC_ROW, 15, TC_COL, 18, "GAMEPAD: THE D-PAD STEERS, START PAUSES"
        .byte   TC_ROW, 16, TC_COL, 18, "P: PAUSE   M: SOUND ON/OFF   Q: QUIT"
        .byte   TC_ROW, 21, TC_COL, 26, "PRESS SPACE OR START TO PLAY", TERM
over_txt:
        .byte   TC_ROW, 10, TC_COL, 32, RV_ON, "    GAME OVER    "
        .byte   TC_ROW, 11, TC_COL, 32, "                 "
        .byte   TC_ROW, 12, TC_COL, 32, "  SPACE/A: PLAY  "
        .byte   TC_ROW, 13, TC_COL, 32, "  Q: QUIT        ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM
TC_TILE         = $0B           ; n: draw tile n            (terminal v1.4)
TC_DEFTILE      = $19           ; n c r data: define tile n (terminal v1.4)
TC_LIT          = $1A
ATTR_GFX        = $80
border_txt:     ; pixel row 4 and 95, pixel columns 0 and 159 (rows 5-94)
        .byte   TC_ATTR, ATTR_GFX, TC_ROW, 1, TC_COL, 0, $57         ; top left
        .byte   TC_ATTR, ATTR_GFX | 13 << 3                         ; 13 at a time
        .byte   TC_LIT, $03, TC_LIT, $03, TC_LIT, $03, TC_LIT, $03, TC_LIT, $03, TC_LIT, $03
        .byte   TC_ATTR, ATTR_GFX, $AB                               ; top right
        .byte   TC_DEFTILE, 0, 1, 21                                 ; the sides
        .res    21, $55
        .byte   TC_DEFTILE, 1, 1, 21
        .res    21, $AA
        .byte   TC_ROW, 2, TC_COL, 0, TC_TILE, 0, TC_COL, 79, TC_TILE, 1
        .byte   TC_ROW, 23, TC_COL, 0, $D5                           ; bottom left
        .byte   TC_ATTR, ATTR_GFX | 13 << 3, $C0, $C0, $C0, $C0, $C0, $C0
        .byte   TC_ATTR, ATTR_TEXT, TERM
; ---- sounds (scripts for ../ay/sfx.s); sfx_prio: the voice x 16 + the
; priority (voices 3-5: channels A-C)
SND_START       = 0
SND_EAT         = 1
SND_CRASH       = 2             ; noise ...
SND_CRASH2      = 3             ; ... and a falling tone
SND_OVER        = 4
SND_HI          = 5             ; GAME OVER with a new high score
sfx_scripts:
        .word   s_start, s_eat, s_crash, s_crash2, s_over, s_hi
sfx_prio:
        .byte   $36, $52, $58, $48, $37, $37
s_start:.byte   SX_VOL, 11, SX_DECAY, 2, SX_LEN, 5
        .byte   SX_NOTE(36), SX_NOTE(40), SX_NOTE(43), SX_NOTE(48), SX_END
s_eat:  .byte   SX_VOL, 12, SX_DECAY, 2, SX_PER, 200, 0, SX_SWEEP, <-22, >-22, SX_WAIT(6), SX_END
s_crash:.byte   SX_MIX, 2, SX_NOISE, 20, SX_VOL, 15, SX_DECAY, 3, SX_WAIT(45), SX_END
s_crash2:.byte  SX_VOL, 12, SX_DECAY, 4, SX_PER, $00, $01, SX_SWEEP, 10, 0, SX_WAIT(40), SX_END
s_over: .byte   SX_VOL, 11, SX_DECAY, 3, SX_LEN, 12
        .byte   SX_NOTE(43), SX_NOTE(40), SX_NOTE(36), SX_LEN, 30, SX_NOTE(31), SX_END
s_hi:   .byte   SX_VOL, 12, SX_DECAY, 2, SX_LEN, 6
        .byte   SX_NOTE(48), SX_NOTE(52), SX_NOTE(55), SX_NOTE(60), SX_NOTE(55), SX_LEN, 24, SX_NOTE(60), SX_END

bye_txt:
        .byte   TC_CLS, TC_CURSOR, '_', TERM

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
dir:        .res 1
kq:         .res 2              ; queued turns
kq_n:       .res 1
esc_st:     .res 1
quit:       .res 1
dead:       .res 1
grow:       .res 1
move_delay: .res 1
head_x:     .res 1
head_y:     .res 1
tail_x:     .res 1
tail_y:     .res 1
new_x:      .res 1
new_y:      .res 1
food_x:     .res 1
food_y:     .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
vars_end:

        .segment "GRID"
GRID_PAGES  = (GW * GH + 255) / 256
grid:       .res GRID_PAGES * 256
