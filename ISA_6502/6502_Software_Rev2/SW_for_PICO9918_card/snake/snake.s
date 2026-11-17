; ============================================================================
; snake.s - the classic Snake game for the 6502 SBC, CPU Rev2, on the
;           PICO9918 card
;
;   build:  make.bat (make.bat 4 for a 4 MHz clock)
;   run:    L SNAKE 0800     then   R
;
; Header (patchable from the monitor, same layout as INVADERS):
;   $0800  JMP start
;   $0803  speed      starting delay per move, about 1 ms per unit (default 90)
;                     the snake gets faster as it eats, down to a third of this
;   $0804  controls   at start: 0 keyboard, 1 gamepad (default; G on the
;                     title screen switches; A or Start on the pad picks the pad)
;   $0805  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card, through ../ay/sfx.s.  Without it, silence.
;
; Keys:  W A S D or the arrow keys   steer
;        P                         pause
;        M                         sound on / off
;        Q                         quit (back to the boot menu)
; Gamepad: the d-pad steers, Start pauses
;
; The game is the PIC32 terminal version's, unchanged: a grid of 79 x 45
; cells, the snake growing 3 cells a food, faster as it eats.  What is new is
; the screen: the Graphics II bitmap, a cell 3 x 4 screen pixels; the snake
; dark green, its head (a sprite) light green, the food (a sprite) red, a
; grey border.  Each move draws the new head cell and clears the old tail's.
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

; ---- text (print) ------------------------------------------------------------
TC_COL          = $0E           ; print: the next byte is the column
TC_ROW          = $0F           ;   ... the row
.define RV_ON   $11             ;   highlighted (white on blue) from here
.define RV_OFF  $12
TERM            = $FF           ; string terminator

; ---- VRAM (Graphics II bitmap) and colours ---------------------------------
V_PAT           = $0000
V_COL           = $2000
V_SPAT          = $1800
V_NAME          = $3800
V_SATTR         = $3B00
VDP_NAME        = V_NAME
C_TEXT          = $F1           ; white on black
C_TEXT_HI       = $F4           ; white on blue
C_BORDER        = $E1           ; grey
C_GRID          = $C1           ; the snake: dark green
C_HEAD          = $03           ; sprites: the head light green,
C_FOOD          = $08           ;   the food red
HIDE_Y          = $C0           ; a sprite's Y off the screen

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
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound effects on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines

; ----------------------------------------------------------------------------
; I/O and helpers (as in INVADERS)
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

; a character into the bitmap at the cursor (8 pattern and 8 colour bytes:
; white on black, or white on blue after RV_ON), and the cursor on.  Off
; the right edge: nothing.  Preserves A, X, Y.
putc:   pha
        stx     pu_x
        sty     pu_y
        ldx     cur_col
        cpx     #32
        bcs     @out
        sec
        sbc     #$20
        cmp     #64
        bcc     @ok
        lda     #0              ; (anything else: a space)
@ok:    ldx     #0
        stx     pu_hi
        asl
        asl
        rol     pu_hi
        asl
        rol     pu_hi
        clc
        adc     #<font
        sta     @g+1
        lda     pu_hi
        adc     #>font
        sta     @g+2
        lda     cur_col
        sta     t_col
        lda     cur_row
        sta     t_row
        jsr     cell_addr
        lda     t_ca
        ldy     t_ca+1
        jsr     vdp_waddr
        ldx     #0
@g:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #8
        bne     @g
        lda     t_ca+1          ; the colour table: + $2000
        ora     #>V_COL
        tay
        lda     t_ca
        jsr     vdp_waddr
        lda     #C_TEXT
        ldx     rv
        beq     @c
        lda     #C_TEXT_HI
@c:     ldx     #8
@cw:    sta     VDP_DATA
        dex
        bne     @cw
@out:   inc     cur_col
        ldx     pu_x
        ldy     pu_y
        pla
        rts

; VRAM address of cell t_col, t_row (patterns) -> t_ca
cell_addr:
        lda     t_col
        asl
        asl
        asl
        sta     t_ca
        lda     t_row
        and     #7
        sta     t_ca+1
        lda     t_row
        lsr
        lsr
        lsr
        asl
        asl
        asl
        ora     t_ca+1
        sta     t_ca+1
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

; ============================================================================
; the display (PICO9918, Graphics II bitmap)
; ============================================================================
; A grid cell is 3 x 4 screen pixels: cell (gx, gy) at x = 9 + 3 gx,
; y = 10 + 4 gy (the grid is x 9-245, y 10-189).  The border is a line at
; x = 6 and 248, y = 8 and 191, so it is in its own 8-pixel bytes and lines:
; every byte of the grid has one colour (the snake's, dark green) and the
; border another (grey).  The head and the food are sprites (light green,
; red).  shadow is a copy of the bitmap's patterns (32 bytes a line, 192
; lines), so pixels can be set and cleared without reading VRAM.
GX0             = 9
GY0             = 10

gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (VRAM cleared)
        lda     #<V_NAME        ; the names: the bitmap, 0-255 in each third
        ldy     #>V_NAME
        jsr     vdp_waddr
        ldy     #3
        ldx     #0
@n:     txa
        sta     VDP_DATA
        inx
        bne     @n
        dey
        bne     @n
        lda     #<V_SPAT        ; the sprites' pictures: the head, the food
        ldy     #>V_SPAT
        jsr     vdp_waddr
        ldx     #0
@sp:    lda     spr_pics,x
        sta     VDP_DATA
        inx
        cpx     #16
        bne     @sp
        jsr     cls
        lda     #$C0            ; R1: display on, 16K, 8 x 8 sprites, and
        ldx     #1              ; bit 5 (the VDP interrupt) off
        jmp     vdp_reg

; the screen blank (the shadow too), no sprites; the colours: row 0 white
; (text), the border grey, the grid dark green
cls:    lda     #<V_PAT
        ldy     #>V_PAT
        jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #>(256 * 8 * 3)
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        lda     #>shadow        ; the shadow
        sta     @sh+2
        ldx     #0
        ldy     #24
        lda     #0
@sh:    sta     shadow,x
        inx
        bne     @sh
        inc     @sh+2
        dey
        bne     @sh
        lda     #<V_COL
        ldy     #>V_COL
        jsr     vdp_waddr
        lda     #0              ; y: line, in order of the colour table
        sta     cl_r            ; (row, column, line in the cell)
@row:   lda     #0
        sta     cl_c
@col:   lda     #0
        sta     cl_k
@line:  lda     cl_r            ; this line's y
        asl
        asl
        asl
        ora     cl_k
        tay
        lda     #C_TEXT
        cpy     #8
        bcc     @put            ; row 0: the status line
        lda     #C_BORDER
        cpy     #8
        beq     @put            ; the top and bottom lines
        cpy     #191
        beq     @put
        ldx     cl_c            ; the side columns
        beq     @put
        cpx     #31
        beq     @put
        lda     #C_GRID
@put:   sta     VDP_DATA
        inc     cl_k
        lda     cl_k
        cmp     #8
        bne     @line
        inc     cl_c
        lda     cl_c
        cmp     #32
        bne     @col
        inc     cl_r
        lda     cl_r
        cmp     #24
        bne     @row
        lda     #0
        sta     rv
        sta     cur_col
        sta     cur_row
        ; (falls through)

; no sprites
no_sprites:
        lda     #HIDE_Y
        sta     spr_y
        sta     spr_y+1
        ; (falls through)

; the sprite table from spr_y / spr_x: 0 the head, 1 the food
put_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     #0
@s:     lda     spr_y,x
        sta     VDP_DATA
        lda     spr_x,x
        sta     VDP_DATA
        txa                     ; pattern 0 / 1
        sta     VDP_DATA
        lda     spr_col,x
        sta     VDP_DATA
        inx
        cpx     #2
        bne     @s
        lda     #$D0
        sta     VDP_DATA
        rts

; sprite X (0 the head, 1 the food) on cell spr_cx, spr_cy
place_spr:
        lda     spr_cx          ; x = GX0 + 3 gx
        asl
        adc     spr_cx
        adc     #GX0
        sta     spr_x,x
        lda     spr_cy          ; y = GY0 + 4 gy - 1 (a line lower)
        asl
        asl
        adc     #GY0-1
        sta     spr_y,x
        cpx     #1              ; the food is 5 x 6: 1 pixel out each way
        bne     :+
        dec     spr_x,x
        dec     spr_y,x
:       jmp     put_sprites

; ---- pixels -------------------------------------------------------------------
; set (pix_op $0D, ORA) or clear (pix_op $2D AND with the mask inverted)
; the bits A of byte column X, line Y in the shadow and the bitmap.
; Preserves X, Y.
set_bits:
        sta     pb_m
        lda     #$0D            ; ora abs
        bne     bits
clr_bits:
        eor     #$FF
        sta     pb_m
        lda     #$2D            ; and abs
bits:   sta     @op
        stx     pb_x
        sty     pb_y
        tya                     ; the shadow: shadow + y * 32 + x
        and     #7
        asl
        asl
        asl
        asl
        asl                     ; (y & 7) << 5
        sta     pb_lo
        tya
        lsr
        lsr
        lsr
        clc
        adc     #>shadow
        sta     pb_hi
        txa
        ora     pb_lo
        sta     @ld+1
        sta     @st+1
        lda     pb_hi
        sta     @ld+2
        sta     @st+2
@ld:    lda     $FFFF
@op:    ora     pb_m            ; (or and)
@st:    sta     $FFFF
        pha
        tya                     ; VRAM: (y >> 3) * 256 + x * 8 + (y & 7)
        and     #7
        sta     pb_lo
        txa
        asl
        asl
        asl
        ora     pb_lo
        sta     VDP_CTRL
        tya
        lsr
        lsr
        lsr
        ora     #$40            ; (write)
        sta     VDP_CTRL
        pla
        sta     VDP_DATA
        ldx     pb_x
        ldy     pb_y
        rts

; cell X, Y on (draw_cell) or off (erase_cell): 3 x 4 pixels.  Preserves
; nothing.
draw_cell:
        lda     #0
        beq     cell_op
erase_cell:
        lda     #1
cell_op:sta     pc_clr
        txa                     ; x = GX0 + 3 gx
        asl
        stx     pc_t
        adc     pc_t
        adc     #GX0
        sta     pc_x
        tya                     ; y = GY0 + 4 gy
        asl
        asl
        adc     #GY0
        sta     pc_y
        lda     pc_x
        and     #7
        tax
        lda     cm1,x
        sta     pc_m1
        lda     cm2,x
        sta     pc_m2
        lda     pc_x
        lsr
        lsr
        lsr
        tax                     ; the byte column
        ldy     pc_y
        lda     #4
        sta     pc_n
@l:     lda     pc_m1
        jsr     @one
        lda     pc_m2
        beq     @nx
        inx
        jsr     @one
        dex
@nx:    iny
        dec     pc_n
        bne     @l
        rts
@one:   pha
        lda     pc_clr
        bne     :+
        pla
        jmp     set_bits
:       pla
        jmp     clr_bits

; the border: lines at y = 8 and 191 (x 6-248), x = 6 and 248 (y 8-191)
draw_border:
        ldy     #8
        jsr     @h
        ldy     #191
        jsr     @h
        ldy     #8
@v:     ldx     #0
        lda     #$02            ; x = 6
        jsr     set_bits
        ldx     #31
        lda     #$80            ; x = 248
        jsr     set_bits
        iny
        cpy     #192
        bne     @v
        rts
@h:     ldx     #0
        lda     #$03            ; x 6-7
        jsr     set_bits
@hl:    inx
        lda     #$FF
        cpx     #31
        bne     :+
        lda     #$80            ; x 248
:       jsr     set_bits
        cpx     #31
        bne     @hl
        rts

; the head's sprite on the head (head_x, head_y)
show_head:
        lda     head_x
        sta     spr_cx
        lda     head_y
        sta     spr_cy
        ldx     #0
        jmp     place_spr

; the food: its sprite on food_x, food_y
draw_food:
        lda     food_x
        sta     spr_cx
        lda     food_y
        sta     spr_cy
        ldx     #1
        jmp     place_spr

; the 3 pixels of a cell from x & 7: in the byte, and in the next
cm1:    .byte   $E0, $70, $38, $1C, $0E, $07, $03, $01
cm2:    .byte   $00, $00, $00, $00, $00, $00, $80, $C0
; sprites: the head (3 x 4), the food (5 x 6)
spr_pics:
        .byte   $E0, $E0, $E0, $E0, 0, 0, 0, 0
        .byte   $20, $70, $F8, $F8, $F8, $70, 0, 0
spr_col:.byte   C_HEAD, C_FOOD

; the display: R0-R7 (Graphics II: patterns $0000, colours $2000, names
; $3800, sprite attributes $3B00, sprite patterns $1800; display off; black)
vdp_regs:
        .byte   $02, $80, V_NAME / $400, $FF, $03, V_SATTR / $80, $03, $01

.macro MENU_IDLE
        jsr     rand            ; stir the random numbers while waiting
        jsr     sfx_poll
.endmacro
CTRL_COL        = 0
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

; ---- title screen ----------------------------------------------------------
title:  jsr     screen_init
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        ; a little snake under it
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
        lda     demo_x+DEMO_LEN-1       ; its head
        sta     head_x
        lda     demo_y+DEMO_LEN-1
        sta     head_y
        jsr     show_head

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
        jsr     show_head       ; (the head's sprite)
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
        lda     #HIDE_Y
        sta     spr_y
        jsr     put_sprites
        jmp     @w
@on:    jsr     draw_cell
        jsr     show_head
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
        jsr     SBC_CONRESET    ; the console's text screen back
exit_menu:
        jmp     SBC_MENU        ; back to the boot menu

; ============================================================================
; setup
; ============================================================================
screen_init:
        jmp     cls

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
        jsr     draw_border
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
        jsr     show_head
        jmp     draw_food

show_score:
        ldx     #6
        ldy     #0
        jsr     gotoxy
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        ldx     #18
        ldy     #0
        jsr     gotoxy
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jmp     prbcd

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
        bne     @ar
        inc     esc_st
        rts
@ar:    cmp     #KEY_UP         ; the ROM's arrow key codes
        beq     @up
        cmp     #KEY_DOWN
        beq     @down
        cmp     #KEY_LEFT
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
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

        .include "snake_gfx.inc"        ; the font (gen_pico.py)

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

need_txt:
        .byte   13, 10, "SNAKE NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
status_txt:
        .byte   TC_ROW, 0, TC_COL, 0, "SCORE", TC_COL, 13, "HIGH", TC_COL, 25, "P PAUSE", TERM
title_txt:
        .byte   TC_ROW, 2, TC_COL, 12, RV_ON, " SNAKE ", RV_OFF
        .byte   TC_ROW, 5, TC_COL, 3, "EAT THE FOOD, DON'T HIT"
        .byte   TC_ROW, 6, TC_COL, 3, "THE WALLS OR YOURSELF."
        .byte   TC_ROW, 14, TC_COL, 1, "STEER: W A S D, ARROWS, D-PAD"
        .byte   TC_ROW, 15, TC_COL, 1, "P OR START: PAUSE   M: SOUND"
        .byte   TC_ROW, 16, TC_COL, 1, "Q: QUIT"
        .byte   TC_ROW, 21, TC_COL, 2, "PRESS SPACE OR START TO PLAY", TERM
over_txt:
        .byte   TC_ROW, 10, TC_COL, 7, RV_ON, "    GAME OVER    "
        .byte   TC_ROW, 11, TC_COL, 7, "                 "
        .byte   TC_ROW, 12, TC_COL, 7, "  SPACE/A: PLAY  "
        .byte   TC_ROW, 13, TC_COL, 7, "  Q: QUIT        ", RV_OFF, TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD (G: KEYBOARD)", TERM
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
; the display
cur_row:    .res 1              ; text
cur_rep:    .res 1
cur_col:    .res 1
rv:         .res 1
pu_x:       .res 1
pu_y:       .res 1
pu_hi:      .res 1
t_col:      .res 1
t_row:      .res 1
t_ca:       .res 2
cl_r:       .res 1              ; cls
cl_c:       .res 1
cl_k:       .res 1
pb_m:       .res 1              ; set_bits / clr_bits
pb_x:       .res 1
pb_y:       .res 1
pb_lo:      .res 1
pb_hi:      .res 1
pc_clr:     .res 1              ; draw_cell / erase_cell
pc_t:       .res 1
pc_x:       .res 1
pc_y:       .res 1
pc_m1:      .res 1
pc_m2:      .res 1
pc_n:       .res 1
spr_cx:     .res 1              ; place_spr
spr_cy:     .res 1
spr_x:      .res 2              ; the sprites: 0 the head, 1 the food
spr_y:      .res 2
vars_end:

        .segment "GRID"
GRID_PAGES  = (GW * GH + 255) / 256
grid:       .res GRID_PAGES * 256

        .segment "SHADOW"
shadow:     .res 32 * 192       ; a copy of the bitmap's patterns, by line
