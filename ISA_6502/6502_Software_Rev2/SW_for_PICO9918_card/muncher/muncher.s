; ============================================================================
; muncher.s - MUNCHER, a maze chase game (in the style of Pac-Man) for the
;             6502 SBC, CPU Rev2, on the PICO9918 card
;
;   build:  make.bat (make.bat 4 for a 4 MHz clock)
;   run:    L MUNCHER 0800   then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  speed      video frames (1/60 s) a game tick (default 2: 30 ticks
;                     a second)
;   $0804  controls   at start: 0 keyboard, 1 gamepad (default; G on the
;                     title switches; A or Start on the pad picks the pad)
;   $0805  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card, through ../ay/sfx.s.  Without it, silence.
;
; Keys:    W A S D or the arrow keys   steer      P pause   Q quit
;          M  sound on / off
; Gamepad: d-pad steers, Start pauses
;
; The game is the PIC32 terminal version's, unchanged: the maze (39 x 21
; tiles), the muncher, the ghosts' rules, the scoring, the sound.  What is
; new is the picture (Graphics I and the F18A's second tile layer):
;   - layer 1: the walls in blue (patterns made by gen_pico.py; a tile is
;     6 x 8 screen pixels, 4 tiles = 3 cells) and the status lines.
;   - layer 2, on top: the dots, the pellets (they flash) and the door, so
;     they keep their own colours next to the walls; READY!, PAUSED, GAME
;     OVER.  A tile's change redraws its group of 4 tiles (3 names).
;   - sprites (8 x 8): the muncher, and each ghost as a body and its eyes.
;     An actor glides from tile to tile as its accumulator fills (it is drawn
;     a tile behind the game's position).
; No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"   ; fixed ROM entry points ($FE00 table)

SPEED_DEFAULT   = 2             ; video frames (1/60 s) a game tick

; ---- text (print) ------------------------------------------------------------
TC_L1           = $01           ; print: layer 1 from here (the start)
TC_L2           = $02           ;   layer 2 from here
TC_CLS          = $0C           ;   clear the screen
TC_COL          = $0E           ;   the next byte is the column
TC_ROW          = $0F           ;   ... the row
TERM            = $FF

; ---- VRAM (Graphics I, two tile layers) -------------------------------------
V_PAT           = $0000         ; patterns (both layers)
V_NAME1         = $0800         ; layer 1 names: the walls, the status lines
V_COL1          = $0C00         ; layer 1 colours
V_COL2          = $0C40         ; layer 2 colours
V_SATTR         = $0D00         ; sprite attributes
V_NAME2         = $1000         ; layer 2 names: dots, pellets, door, texts
                                ; (R10's bit 0 is a page bit: $800 steps)
V_SPAT          = $1800         ; sprite patterns
VDP_NAME        = V_NAME1
WALL_COL0       = $40           ; the walls: blue (white when a maze is cleared)
WALL_COL1       = $F0
HIDE_Y          = $C0           ; a sprite's Y off the screen
SPAT_EYES       = 14            ; the eyes' sprite patterns (up, left, down, right)
HUD_ROW         = 22

; ---- tiles -------------------------------------------------------------------------
T_EMPTY         = 0
T_DOT           = 1
T_PILL          = 2
T_WALL          = 3
T_DOOR          = 4
T_HOUSE         = 5

NACT            = 5             ; actor 0 is the muncher, 1-4 the ghosts
UP              = 0             ; directions, in the ghosts' tie-break order
LEFT            = 1
DOWN            = 2
RIGHT           = 3
G_HOUSE         = 0             ; ghost states
G_LEAVE         = 1
G_ACTIVE        = 2
G_EYES          = 3
START_X         = 19            ; the muncher's start
START_Y         = 15
DOOR_X          = 19            ; the tile above the ghost house door
DOOR_Y          = 7
HOME_Y          = 9             ; inside the house
TUNNEL_Y        = 9

; ============================================================================
        .segment "CODE"

        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines

getc            = SBC_CHRIN     ; carry set = key in A

; ============================================================================
; the display (PICO9918, Graphics I + the F18A's second tile layer)
; ============================================================================

; set up the VDP: registers, patterns, colours, sprite patterns, layer 2
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (clears VRAM: pattern 0 is blank)
        lda     #<(V_PAT + $20 * 8)
        ldy     #>(V_PAT + $20 * 8)
        jsr     vdp_waddr
        lda     #<pat_font
        ldx     #>pat_font
        ldy     #>(64 * 8)
        jsr     copy_n
        lda     #<(V_PAT + WALL_PAT0 * 8)
        ldy     #>(V_PAT + WALL_PAT0 * 8)
        jsr     vdp_waddr
        lda     #<pat_wall
        ldx     #>pat_wall
        ldy     #<(NWALL * 8)
        sty     vdp_n
        ldy     #>(NWALL * 8)
        jsr     copy_n2
        lda     #<(V_PAT + DOT_PAT0 * 8)
        ldy     #>(V_PAT + DOT_PAT0 * 8)
        jsr     vdp_waddr
        lda     #<pat_dots
        ldx     #>pat_dots
        ldy     #<(NDOTPAT * 8)
        sty     vdp_n
        ldy     #>(NDOTPAT * 8)
        jsr     copy_n2
        lda     #<V_COL1        ; the colour tables
        ldy     #>V_COL1
        jsr     vdp_waddr
        lda     #<col_l1
        ldx     #>col_l1
        ldy     #32
        sty     vdp_n
        ldy     #0
        jsr     copy_n2
        lda     #<V_COL2
        ldy     #>V_COL2
        jsr     vdp_waddr
        lda     #<col_l2
        ldx     #>col_l2
        ldy     #32
        sty     vdp_n
        ldy     #0
        jsr     copy_n2
        lda     #<V_SPAT
        ldy     #>V_SPAT
        jsr     vdp_waddr
        lda     #<spr_pat
        ldx     #>spr_pat
        ldy     #18 * 8
        sty     vdp_n
        ldy     #0
        jsr     copy_n2
        lda     #V_NAME2/$400   ; R10: layer 2 names
        ldx     #10
        jsr     vdp_reg
        lda     #V_COL2/$40     ; R11: layer 2 colours
        ldx     #11
        jsr     vdp_reg
        lda     #$80            ; R49: layer 2 on
        ldx     #49
        jsr     vdp_reg
        lda     #0              ; R50: layer 2 on top
        ldx     #50
        jsr     vdp_reg
        lda     #31             ; R30: 31 sprites a line
        ldx     #30
        jsr     vdp_reg
        jsr     cls
        lda     #$C0            ; R1: 16K, display on, 8 x 8 sprites, no
        ldx     #1              ; interrupt (bit 5 stays 0)
        jmp     vdp_reg

; copy from A (lo) / X (hi): Y pages (copy_n), or vdp_n lo with Y = high
; byte (copy_n2)
copy_n: sty     vdp_n+1
        ldy     #0
        sty     vdp_n
        beq     copy_go
copy_n2:sty     vdp_n+1
copy_go:sta     vdp_src
        stx     vdp_src+1
        jmp     vdp_copy

; both layers' names to blank, no sprites, the walls blue
cls:    lda     #<V_NAME1
        ldy     #>V_NAME1
        jsr     @clr
        lda     #<V_NAME2
        ldy     #>V_NAME2
        jsr     @clr
        jsr     no_sprites
        lda     #0
        sta     flash_on
        lda     #PILL_COL
        jsr     pill_colour
        lda     #WALL_COL0
        jmp     wall_colour

@clr:   jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #3
        sta     vdp_n+1
        lda     #0
        jmp     vdp_fill

no_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        rts

; the walls' colour = A (their groups in layer 1's colour table)
wall_colour:
        pha
        lda     #<(V_COL1 + WALL_PAT0 / 8)
        ldy     #>(V_COL1 + WALL_PAT0 / 8)
        jsr     vdp_waddr
        pla
        ldx     #(NWALL + 7) / 8
@l:     sta     VDP_DATA
        dex
        bne     @l
        rts

; the power pellets' colour = A (layer 2's colour table)
pill_colour:
        pha
        lda     #<(V_COL2 + PILL_G0)
        ldy     #>(V_COL2 + PILL_G0)
        jsr     vdp_waddr
        pla
        ldx     #NPILL_G
@l:     sta     VDP_DATA
        dex
        bne     @l
        rts

; the pellets flash while flash_on (8 ticks on, 8 off)
flash:  lda     flash_on
        beq     @r
        jsr     SBC_TICKS
        and     #8
        cmp     flash_st
        beq     @r
        sta     flash_st
        cmp     #0
        beq     @on
        lda     #0
        jmp     pill_colour
@on:    lda     #PILL_COL
        jmp     pill_colour
@r:     rts

; flashing off, the pellets showing
no_flash:
        lda     #0
        sta     flash_on
        lda     #PILL_COL
        jmp     pill_colour

; wait until speed video frames have passed since the last time
pace:   jsr     sfx_poll
        jsr     flash
        jsr     SBC_TICKS
        sec
        sbc     last_tick
        cmp     speed
        bcc     pace
        jsr     SBC_TICKS
        sta     last_tick
        rts

; ---- text: the name tables, ASCII = the font's patterns -------------------------
; write address = column X, row Y of the layer in lay ($08 layer 1, $10
; layer 2).  Keeps X and Y.
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
        adc     lay
        tay
        pla
        jsr     vdp_waddr
        ldy     cur_y
        rts

l1:     lda     #>V_NAME1
        sta     lay
        rts
l2:     lda     #>V_NAME2
        sta     lay
        rts

; a character (or any name) at the address set.  Keeps A, X, Y.
putc:   sta     VDP_DATA
        rts

; print A as two BCD digits
prbcd:  pha
        lsr
        lsr
        lsr
        lsr
        ora     #'0'
        sta     VDP_DATA
        pla
        and     #$0F
        ora     #'0'
        sta     VDP_DATA
        rts

; print the text at A (lo) / Y (hi): TC_CLS, TC_L1 / TC_L2 (the layer, 1
; to start with), TC_ROW r, TC_COL c (sets the place), characters; TERM ends
print:  sta     @ld+1
        sty     @ld+2
        jsr     l1
@n:     jsr     @get
        cmp     #TERM
        beq     @r
        cmp     #TC_ROW
        bne     @1
        jsr     @get
        sta     pr_row
        jmp     @n
@1:     cmp     #TC_COL
        bne     @2
        jsr     @get
        tax
        ldy     pr_row
        jsr     gotoxy
        jmp     @n
@2:     cmp     #TC_L1
        bne     @3
        jsr     l1
        jmp     @n
@3:     cmp     #TC_L2
        bne     @4
        jsr     l2
        jmp     @n
@4:     cmp     #TC_CLS
        bne     @5
        jsr     cls
        jmp     @n
@5:     sta     VDP_DATA
        jmp     @n
@r:     rts
@get:
@ld:    lda     $FFFF
        inc     @ld+1
        bne     :+
        inc     @ld+2
:       rts

; ---- the maze ---------------------------------------------------------------------
; layer 1: the walls (rows 0-20); layer 2: the dots, pellets and the door
draw_maze:
        lda     #<V_NAME1
        ldy     #>V_NAME1
        jsr     vdp_waddr
        lda     #<wall_names
        ldx     #>wall_names
        ldy     #<(MAZE_H * 32)
        sty     vdp_n
        ldy     #>(MAZE_H * 32)
        jsr     copy_n2
        lda     #0
        sta     dr_r
@r:     ldy     dr_r
        jsr     dot_row
        inc     dr_r
        lda     dr_r
        cmp     #MAZE_H
        bne     @r
        rts

; layer 2, maze row Y: all 10 groups of 4 tiles (cells 1-30)
dot_row:
        sty     dr_y
        jsr     l2
        ldx     #1
        jsr     gotoxy
        lda     #0
        sta     dr_x
@g:     jsr     dot_grp
        lda     dr_x
        clc
        adc     #4
        sta     dr_x
        cmp     #40
        bcc     @g
        rts

; redraw tile X, Y: its group of 4 on layer 2.  (Walls never change.)
draw_tile:
        sty     dr_y
        txa
        and     #$FC
        sta     dr_x
        lsr
        lsr
        sta     tmp4
        asl
        adc     tmp4
        adc     #1              ; column 1 + 3 x group
        tax
        jsr     l2
        jsr     gotoxy
        ; (falls through)

; the 3 cells of the group at dr_x (its first tile), row dr_y, at the
; address set: named from the 4 tiles' codes
dot_grp:
        lda     #0
        sta     dr_k
        lda     dr_x
        clc
        adc     #3
        sta     dr_t
@t:     ldx     dr_t
        ldy     dr_y
        jsr     tile_get        ; (column 39 is outside: 0)
        tax
        lda     dr_k
        asl
        asl
        ora     dot_code,x
        sta     dr_k
        lda     dr_t
        cmp     dr_x
        beq     @w
        dec     dr_t
        jmp     @t
@w:     ldx     dr_k
        lda     dot_n0,x
        sta     VDP_DATA
        lda     dot_n1,x
        sta     VDP_DATA
        lda     dot_n2,x
        sta     VDP_DATA
        rts

; ---- the sprites ------------------------------------------------------------------
; Sprite 0 the muncher, 1-4 the ghosts' eyes, 5-8 their bodies.  An actor
; glides from the tile it was on (afx, afy) to the one it is on now (atx,
; aty) as its accumulator fills, so it is drawn a tile behind: the game
; moves it a whole tile when the accumulator carries.
put_sprites:
        ldx     #0
@a:     lda     snap            ; just placed: no glide
        bne     @set
        lda     ax,x
        cmp     atx,x
        bne     @mv
        lda     ay,x
        cmp     aty,x
        bne     @mv
        lda     aacc,x          ; a carry without a move: standing still
        cmp     lacc,x
        bcs     @frac
        bcc     @stand
@mv:    lda     atx,x
        sta     afx,x
        lda     aty,x
        sta     afy,x
        lda     ax,x
        sta     atx,x
        lda     ay,x
        sta     aty,x
        lda     atx,x           ; not to a neighbour (the tunnel): no glide
        sec
        sbc     afx,x
        clc
        adc     #1
        cmp     #3
        bcs     @stand
        lda     aty,x
        sec
        sbc     afy,x
        clc
        adc     #1
        cmp     #3
        bcs     @stand
        bcc     @frac
@set:   lda     ax,x
        sta     atx,x
        lda     ay,x
        sta     aty,x
@stand: lda     atx,x
        sta     afx,x
        lda     aty,x
        sta     afy,x
@frac:  lda     aacc,x
        sta     lacc,x
        lsr
        lsr
        lsr
        lsr
        lsr
        tay                     ; eighths of the way
        lda     afx,x           ; x = 8 + 6 fx - 1 (8 wide on a 6 wide tile)
        asl
        adc     afx,x
        asl
        adc     #7
        sta     spx,x
        lda     atx,x
        cmp     afx,x
        beq     @nx
        bcc     @xl
        lda     spx,x
        clc
        adc     xo_tab,y
        sta     spx,x
        jmp     @nx
@xl:    lda     spx,x
        sec
        sbc     xo_tab,y
        sta     spx,x
@nx:    lda     afy,x           ; y = 8 fy - 1 (the VDP draws a line lower)
        asl
        asl
        asl
        sec
        sbc     #1
        sta     spy,x
        lda     aty,x
        cmp     afy,x
        beq     @ny
        bcc     @yu
        tya
        clc
        adc     spy,x
        sta     spy,x
        jmp     @ny
@yu:    sty     tmp4
        lda     spy,x
        sec
        sbc     tmp4
        sta     spy,x
@ny:    inx
        cpx     #NACT
        beq     :+
        jmp     @a
:       lda     #0
        sta     snap
        ; the attribute table, built in satt
        ldx     #0              ; the muncher
        jsr     sprite_of
        lsr
        ldy     die_pic
        beq     @m
        tya
@m:     sta     satt+2
        lda     spy
        sta     satt
        lda     spx
        sta     satt+1
        lda     #MUNCH_COL
        sta     satt+3
        ldx     #1
@g:     stx     ri
        txa                     ; eyes at 4 x, body at 4 (x + 4)
        asl
        asl
        tay
        lda     #HIDE_Y
        sta     satt,y          ; both hidden to start with
        sta     satt+16,y
        lda     ghosts_off
        bne     @gn
        lda     spy,x
        sta     sg_y
        lda     spx,x
        sta     satt+1,y
        sta     satt+17,y
        lda     #EYES_COL
        sta     satt+3,y
        lda     adir,x
        clc
        adc     #SPAT_EYES
        sta     satt+2,y
        jsr     sprite_of
        ldx     ri
        cmp     #SP_EYES
        beq     @eyes
        cmp     #SP_SCARED1
        bcs     @scared
        ldy     gfr,x           ; the flashing end of a fright: white
        bne     @flash
        lsr
        pha
        lda     ri
        asl
        asl
        tay
        pla
        sta     satt+18,y
        lda     ghost_col-1,x
        sta     satt+19,y
        lda     sg_y
        sta     satt+16,y
@eyes:  lda     ri
        asl
        asl
        tay
        lda     sg_y
        sta     satt,y
        jmp     @gn
@flash: clc
        adc     #SP_SCARED1-SP_GHOST1
        ldy     #FLASH_COL
        bne     @sc
@scared:ldy     #SCARED_COL
@sc:    sty     tmp4
        lsr
        pha
        lda     ri
        asl
        asl
        tay
        pla
        sta     satt+18,y
        lda     tmp4
        sta     satt+19,y
        lda     sg_y
        sta     satt+16,y
@gn:    ldx     ri
        inx
        cpx     #NACT
        beq     :+
        jmp     @g
:
        lda     #$D0
        sta     satt+36
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #<satt
        ldx     #>satt
        ldy     #37
        sty     vdp_n
        ldy     #0
        jmp     copy_n2

; across a 6 pixel tile in eighths
xo_tab: .byte   0, 1, 2, 2, 3, 4, 4, 5

; R0-R7: Graphics I, display off (gfx_init turns it on); names $0800,
; colours $0C00, patterns $0000, sprite attributes $0D00, sprite patterns
; $1800; backdrop black
vdp_regs:
        .byte   $00, $80, V_NAME1/$400, V_COL1/$40, V_PAT/$800, V_SATTR/$80, V_SPAT/$800, $01

; while the VDP waits for a frame (vdp_frame isn't used, but lib/vdp.s needs it)
frame_idle:
        jmp     sfx_poll

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

; 16 bit Galois LFSR.  Returns a random byte in A.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

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
        jsr     l1
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
; the maze in RAM
; ============================================================================

; point mz_rd / mz_wr at tile X, Y.  Preserves X and Y.
mz_at:  txa
        clc
        adc     mrow_lo,y
        sta     mz_rd+1
        sta     mz_wr+1
        lda     mrow_hi,y
        adc     #0
        sta     mz_rd+2
        sta     mz_wr+2
        rts
mz_rd:  lda     $FFFF
        rts
mz_wr:  sta     $FFFF
        rts

; A = tile at X, Y.  Preserves X and Y.
tile_get:
        jsr     mz_at
        jmp     mz_rd

; copy the maze from ROM (4 pages; the maze is 21 x 40 = 840 bytes)
copy_maze:
        lda     #<maze_src
        sta     @rd+1
        lda     #>maze_src
        sta     @rd+2
        lda     #>maze
        sta     @wr+2
        ldx     #4
        ldy     #0
@rd:    lda     $FFFF,y
@wr:    sta     maze,y
        iny
        bne     @rd
        inc     @rd+2
        inc     @wr+2
        dex
        bne     @rd
        lda     #<DOTS_TOTAL
        sta     dots
        lda     #>DOTS_TOTAL
        sta     dots+1
        rts

; ============================================================================
; start / title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear every variable: RAM is random at power-up
        ldx     #bss_end - bss_start
@clr:   sta     bss_start-1,x
        dex
        bne     @clr
        lda     ctrl_def
        sta     ctrl
        lda     #0
        sta     hiscore
        sta     hiscore+1
        sta     hiscore+2
        lda     #$C3
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
@pico:  jsr     read_pad
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
        jsr     gfx_init

title:  jsr     sfx_off
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     title_cast
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

; ---- a new game ------------------------------------------------------------------
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     level
        lda     #3
        sta     lives
        lda     #1              ; (the tune before the first READY)
        sta     fresh
new_level:
        jsr     copy_maze
        jsr     level_speeds
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        jsr     draw_maze
        lda     #<hud_txt
        ldy     #>hud_txt
        jsr     print
        jsr     show_score
        jsr     show_lives
        jsr     show_level
new_life:
        jsr     reset_actors
        jsr     put_sprites
        jsr     ready           ; "READY!" for a moment
        jsr     SBC_TICKS
        sta     last_tick
        lda     #1              ; the pellets flash while playing
        sta     flash_on

; ---- the game loop -----------------------------------------------------------------
game_loop:
        jsr     sfx_poll
        jsr     read_input
        lda     quit
        beq     @play
        jmp     title
@play:  inc     tick
        jsr     move_player
        jsr     check_hits
        jsr     timers
        ldx     #1
@g:     stx     gi
        jsr     move_ghost
        ldx     gi
        inx
        cpx     #NACT
        bne     @g
        jsr     put_sprites
        lda     score_dirty
        beq     @sd
        jsr     show_score
@sd:    lda     dead
        bne     died
        lda     dots
        ora     dots+1
        beq     cleared
        jsr     pace
        jmp     game_loop

; ---- all the dots eaten -------------------------------------------------------------
cleared:
        jsr     sfx_off
        jsr     no_flash
        lda     #SND_CLEAR
        jsr     sfx_snd
        lda     #10
        jsr     delay_long
        lda     #1              ; the ghosts go; the walls flash
        sta     ghosts_off
        jsr     put_sprites
        lda     #8
        sta     tmp3
@fl:    lda     tmp3
        and     #1
        beq     @w0
        lda     #WALL_COL0
        bne     @w1
@w0:    lda     #WALL_COL1
@w1:    jsr     wall_colour
        lda     #3
        jsr     delay_long
        dec     tmp3
        bne     @fl
        lda     level
        cmp     #98
        bcs     @same
        inc     level
@same:  jmp     new_level

; ---- caught by a ghost --------------------------------------------------------------
died:   jsr     sfx_off         ; the siren stops
        jsr     no_flash
        lda     #10
        jsr     delay_long
        lda     #SND_DIE
        jsr     sfx_snd
        lda     #1              ; the ghosts vanish
        sta     ghosts_off
        lda     #SP_DIE1/2      ; the muncher shrinks away
        sta     die_pic
@anim:  jsr     put_sprites
        lda     #150
        jsr     delay_ms
        inc     die_pic
        lda     die_pic
        cmp     #SP_DIE4/2+1
        bcc     @anim
        lda     #150
        jsr     delay_ms
        jsr     no_sprites
        dec     lives
        jsr     show_lives
        lda     lives
        beq     game_over
        jmp     new_life

game_over:
        lda     score+2         ; new high score?
        cmp     hiscore+2
        bcc     @nohi
        bne     @hi
        lda     score+1
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
        lda     score+2
        sta     hiscore+2
        jsr     show_score
@nohi:  jsr     no_sprites
        lda     #SND_OVER
        jsr     sfx_snd
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        lda     #20
        jsr     delay_long
        jsr     flush_in
@w:     jsr     menu_key
        cmp     #'Q'
        beq     @t
        cmp     #'M'
        bne     @nm
        jsr     sfx_toggle
        jmp     @w
@nm:
        cmp     #' '
        beq     @t
        cmp     #PAD_GO
        bne     @w
@t:     jmp     title

exit_game:
        jsr     sfx_off
        lda     #$C0            ; the PICO9918 back to its defaults (VR50
        ldx     #50             ; soft reset), then the text console
        jsr     vdp_reg
        jsr     SBC_CONRESET
        jmp     SBC_MENU        ; back to the boot menu

; "READY!" in the middle, then put the maze back under it
ready:  jsr     sfx_off
        lda     #<ready_txt
        ldy     #>ready_txt
        jsr     print
        lda     fresh           ; a new game: its tune (a little longer)
        beq     @w
        lda     #0
        sta     fresh
        lda     #SND_INTROA
        jsr     sfx_snd
        lda     #SND_INTROB
        jsr     sfx_snd
        lda     #10
        jsr     delay_long
@w:     lda     #30
        jsr     delay_long
        jsr     flush_in
        ldy     #READY_ROW      ; the dots back under it
        jsr     dot_row
        lda     #SND_SIREN      ; the siren while they hunt
        jmp     sfx_snd

; ---- level settings -------------------------------------------------------------------
level_speeds:
        lda     level           ; speeds go up 6 per level, to a limit
        cmp     #8
        bcc     @l
        lda     #8
@l:     sta     tmp
        asl
        adc     tmp
        asl                     ; * 6
        sta     tmp
        clc
        adc     #100
        sta     pspeed          ; muncher 100 .. 148
        lda     tmp
        clc
        adc     #92
        sta     gspeed          ; ghosts 92 .. 140
        lda     level           ; fright time 180 ticks, 20 less per level
        cmp     #7
        bcc     @f
        lda     #7
@f:     sta     tmp
        asl
        asl
        adc     tmp
        asl
        asl                     ; * 20
        sta     tmp
        lda     #180
        sec
        sbc     tmp
        sta     fr_len          ; 180 .. 40
        rts

; ---- status line ------------------------------------------------------------------------
show_score:
        lda     #0
        sta     score_dirty
        jsr     l1
        ldx     #6
        ldy     #HUD_ROW
        jsr     gotoxy
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        ldx     #22
        ldy     #HUD_ROW
        jsr     gotoxy
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jmp     prbcd

show_lives:
        jsr     l1
        ldx     #6
        ldy     #HUD_ROW+1
        jsr     gotoxy
        lda     lives
        ora     #'0'
        jmp     putc

show_level:
        jsr     l1
        ldx     #16
        ldy     #HUD_ROW+1
        jsr     gotoxy
        lda     level           ; level + 1, in decimal
        clc
        adc     #1
        ldx     #0
@t:     cmp     #10
        bcc     @d
        sbc     #10
        inx
        bne     @t
@d:     pha
        txa
        ora     #'0'
        jsr     putc
        pla
        ora     #'0'
        jmp     putc

; the title's cast: the muncher, the 4 ghosts, a frightened one; a dot and
; a pellet (layer 2)
title_cast:
        ldx     #0
@c:     lda     cast_tab,x
        sta     satt,x
        inx
        cpx     #4 * NCAST
        bne     @c
        lda     #$D0
        sta     satt,x
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #<satt
        ldx     #>satt
        ldy     #4 * NCAST + 1
        sty     vdp_n
        ldy     #0
        jsr     copy_n2
        jsr     l2
        ldx     #CAST_COL
        ldy     #14
        jsr     gotoxy
        lda     dot_n0+1        ; (a dot in a group's first tile)
        jsr     putc
        ldx     #CAST_COL-1
        ldy     #15
        jsr     gotoxy
        lda     dot_n0+8        ; (a pellet: the maze has them in a
        jsr     putc            ; group's second tile, across 2 cells)
        lda     dot_n1+8
        jmp     putc
; add the BCD value Y (hi) : A (lo) to the score
add_score:
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
        lda     #1
        sta     score_dirty
        rts

; ============================================================================
; actors
; ============================================================================
reset_actors:
        lda     #1
        sta     snap
        lda     #0
        sta     ghosts_off
        sta     die_pic
        ldx     #NACT-1
@set:   lda     start_x,x
        sta     ax,x
        lda     start_y,x
        sta     ay,x
        lda     start_dir,x
        sta     adir,x
        lda     start_st,x
        sta     gst,x
        lda     start_rel,x
        sta     grel,x
        lda     #0
        sta     aacc,x
        sta     gfr,x
        sta     grev,x
        dex
        bpl     @set
        lda     #LEFT
        sta     want
        lda     #0
        sta     dead
        sta     fr_t
        sta     mode
        sta     mode_div
        sta     quit
        sta     esc_st
        lda     mode_len
        sta     mode_t
        rts

; next position from X, Y in direction A -> nx, ny (wrapping in the tunnel).
; Preserves X and Y.
step_pos:
        stx     nx
        sty     ny
        tay
        lda     nx
        clc
        adc     dir_dx,y
        bpl     @1
        lda     #MAZE_W-1       ; off the left: the right end
@1:     cmp     #MAZE_W
        bcc     @2
        lda     #0              ; off the right: the left end
@2:     sta     nx
        lda     ny
        clc
        adc     dir_dy,y
        sta     ny
        ldx     ax_tmp          ; (callers pass X, Y = ax_tmp, ay_tmp)
        ldy     ay_tmp
        rts

; ---- the muncher -----------------------------------------------------------------------
; carry set if the muncher can go in direction A from where it is
p_can:  sta     tmp
        ldx     ax
        stx     ax_tmp
        ldy     ay
        sty     ay_tmp
        jsr     step_pos
        ldx     nx
        ldy     ny
        jsr     tile_get
        cmp     #T_WALL         ; only empty, dot and pill tiles
        rts                     ; (carry clear if < T_WALL: so invert)

move_player:
        lda     aacc
        clc
        adc     pspeed
        sta     aacc
        bcc     @r
        lda     want            ; turn if the wanted way is open
        jsr     p_can
        bcs     @keep
        lda     want
        sta     adir
@keep:  lda     adir
        jsr     p_can
        bcs     @r              ; blocked: stand still
        lda     ax
        sta     apx
        lda     ay
        sta     apy
        lda     nx
        sta     ax
        lda     ny
        sta     ay
        lda     pmouth
        eor     #1
        sta     pmouth
        sta     waka
        ; eat what is here
        ldx     ax
        ldy     ay
        jsr     tile_get
        cmp     #T_DOT
        beq     @dot
        cmp     #T_PILL
        beq     @pill
@r:     rts
@dot:   lda     #T_EMPTY
        jsr     mz_wr
        jsr     draw_tile       ; (X, Y: the muncher's tile)
        lda     waka            ; (two sounds in turn)
        clc
        adc     #SND_WAKA1
        jsr     sfx_snd
        jsr     dot_gone
        lda     #$10
        ldy     #0
        jmp     add_score
@pill:  lda     #T_EMPTY
        jsr     mz_wr
        jsr     draw_tile
        lda     #SND_PILL
        jsr     sfx_snd
        lda     #SND_FRIGHT     ; the ghosts' siren changes
        jsr     sfx_snd
        jsr     dot_gone
        lda     #$50
        ldy     #0
        jsr     add_score
        jmp     frighten

dot_gone:
        lda     dots
        bne     @1
        dec     dots+1
@1:     dec     dots
        rts

; a power pellet: the ghosts turn and run
frighten:
        lda     fr_len
        sta     fr_t
        lda     #0
        sta     eat_n
        ldx     #NACT-1
@l:     lda     gst,x
        cmp     #G_EYES
        beq     @n
        lda     #1
        sta     gfr,x
        lda     gst,x
        cmp     #G_ACTIVE
        bne     @n
        lda     #1
        sta     grev,x
@n:     dex
        bne     @l
        rts

; ---- timers: scatter / chase phases, fright, ghosts leaving the house --------------
timers: lda     fr_t
        beq     @nofr
        dec     fr_t
        bne     @house
        ldx     #NACT-1         ; fright over
        lda     #0
@uf:    sta     gfr,x
        dex
        bne     @uf
        lda     #SND_SIREN
        jsr     sfx_snd
        beq     @house
@nofr:  inc     mode_div        ; the phase clock runs in steps of 8 ticks,
        lda     mode_div        ; and stops while the ghosts are frightened
        and     #7
        bne     @house
        lda     mode_t
        beq     @house          ; 0 = the last phase, for good
        dec     mode_t
        bne     @house
        lda     mode            ; next phase; the ghosts turn round
        cmp     #5
        bcs     @house
        inc     mode
        ldx     mode
        lda     mode_len,x
        sta     mode_t
        ldx     #NACT-1
@rv:    lda     gst,x
        cmp     #G_ACTIVE
        bne     @rn
        lda     #1
        sta     grev,x
@rn:    dex
        bne     @rv
@house: ldx     #NACT-1         ; ghosts waiting to come out
@hl:    lda     gst,x
        bne     @hn
        lda     grel,x
        beq     @out
        dec     grel,x
        jmp     @hn
@out:   lda     #G_LEAVE
        sta     gst,x
@hn:    dex
        bne     @hl
        rts

; ---- the ghosts --------------------------------------------------------------------------
; carry set if ghost gi may enter tile nx, ny
g_can:  ldx     nx
        ldy     ny
        cpy     #MAZE_H
        bcs     @no
        jsr     tile_get
        cmp     #T_WALL
        beq     @no
        cmp     #T_DOOR
        bcc     @yes            ; empty, dot, pill
        ldx     gi              ; door / house: only leaving or going home
        lda     gst,x
        cmp     #G_LEAVE
        beq     @yes
        cmp     #G_EYES
        beq     @yes
@no:    clc
        rts
@yes:   sec
        rts

move_ghost:
        ldx     gi
        lda     gst,x
        bne     @go
        rts                     ; still in the house
@go:    jsr     ghost_speed
        clc
        adc     aacc,x
        sta     aacc,x
        bcs     @step
        rts
@step:  lda     ax,x
        sta     ax_tmp
        lda     ay,x
        sta     ay_tmp
        lda     grev,x          ; a phase change: turn right round
        beq     @choose
        lda     #0
        sta     grev,x
        lda     adir,x
        eor     #2
        sta     adir,x
        jsr     g_try
        bcs     @move
        ldx     gi
@choose:jsr     ghost_target
        jsr     choose_dir
        bcc     @r              ; nowhere to go
@move:  ldx     gi
        lda     ax,x
        sta     gpx
        lda     ay,x
        sta     gpy
        lda     nx
        sta     ax,x
        lda     ny
        sta     ay,x
        lda     gst,x           ; arrived?
        cmp     #G_LEAVE
        bne     @eyes
        lda     nx
        cmp     #DOOR_X
        bne     @hit
        lda     ny
        cmp     #DOOR_Y
        bne     @hit
        lda     #G_ACTIVE       ; out of the house
        sta     gst,x
        lda     #LEFT
        sta     adir,x
        jmp     @hit
@eyes:  cmp     #G_EYES
        bne     @hit
        lda     nx
        cmp     #DOOR_X
        bne     @r
        lda     ny
        cmp     #HOME_Y
        bne     @r
        lda     #G_LEAVE        ; home: come straight out again
        sta     gst,x
        lda     #0
        sta     gfr,x
        rts
@hit:   jmp     ghost_hit       ; did it run into the muncher?
@r:     rts

; the speed of ghost X (preserves X)
ghost_speed:
        lda     gst,x
        cmp     #G_EYES
        bne     @1
        lda     #220
        rts
@1:     cmp     #G_LEAVE
        bne     @2
        lda     #64
        rts
@2:     lda     gfr,x
        beq     @3
        lda     #56
        rts
@3:     lda     ay,x            ; slow in the tunnel
        cmp     #TUNNEL_Y
        bne     @4
        lda     ax,x
        cmp     #5
        bcc     @slow
        cmp     #MAZE_W-5
        bcc     @4
@slow:  lda     #60
        rts
@4:     lda     gspeed
        rts

; try direction adir of ghost gi from ax_tmp, ay_tmp: carry set if open
; (nx, ny set)
g_try:  ldx     gi
        lda     adir,x
        ldx     ax_tmp
        ldy     ay_tmp
        jsr     step_pos
        jmp     g_can

; pick a direction for ghost gi: the open one (not straight back) closest to
; tx, ty; at random when frightened.  Carry set if found (adir, nx, ny set).
choose_dir:
        ldx     gi
        lda     adir,x
        eor     #2
        sta     back
        lda     #$FF
        sta     best_d
        sta     best
        lda     gst,x           ; frightened and roaming: random start,
        cmp     #G_ACTIVE       ; first open way wins
        bne     @scan
        lda     gfr,x
        beq     @scan
        jsr     rand
        and     #3
        sta     dtry
        lda     #4
        sta     dcnt
@rl:    lda     dtry
        cmp     back
        beq     @rnext
        ldx     ax_tmp
        ldy     ay_tmp
        jsr     step_pos
        jsr     g_can
        bcc     @rnext
        lda     dtry
        sta     best
        jmp     @done
@rnext: inc     dtry
        lda     dtry
        and     #3
        sta     dtry
        dec     dcnt
        bne     @rl
        jmp     @back
@scan:  lda     #0
        sta     dtry
@l:     lda     dtry
        cmp     back
        beq     @next
        ldx     ax_tmp
        ldy     ay_tmp
        jsr     step_pos
        jsr     g_can
        bcc     @next
        lda     nx              ; distance |nx-tx| + |ny-ty|
        sec
        sbc     tx
        bpl     @a1
        eor     #$FF
        clc
        adc     #1
@a1:    sta     tmp
        lda     ny
        sec
        sbc     ty
        bpl     @a2
        eor     #$FF
        clc
        adc     #1
@a2:    clc
        adc     tmp
        cmp     best_d
        bcs     @next           ; ties keep the earlier direction
        sta     best_d
        lda     dtry
        sta     best
@next:  inc     dtry
        lda     dtry
        cmp     #4
        bne     @l
@done:  lda     best
        bmi     @back
        ldx     gi
        sta     adir,x
        ldx     ax_tmp
        ldy     ay_tmp
        jsr     step_pos        ; nx, ny for the chosen way
        sec
        rts
@back:  ldx     gi              ; a dead end: back the way it came
        lda     back
        sta     adir,x
        jsr     g_try
        rts

; the target of ghost gi -> tx, ty (signed)
ghost_target:
        ldx     gi
        lda     gst,x
        cmp     #G_LEAVE
        bne     @1
        lda     #DOOR_X
        sta     tx
        lda     #DOOR_Y
        sta     ty
        rts
@1:     cmp     #G_EYES
        bne     @2
        lda     #DOOR_X
        sta     tx
        lda     #HOME_Y
        sta     ty
        rts
@2:     lda     mode            ; even phases scatter, odd ones chase
        and     #1
        bne     @chase
@corner:lda     corner_x,x
        sta     tx
        lda     corner_y,x
        sta     ty
        rts
@chase: cpx     #1
        bne     @g2
        lda     ax              ; 1: straight for the muncher
        sta     tx
        lda     ay
        sta     ty
        rts
@g2:    cpx     #2
        bne     @g3
        lda     #4              ; 2: 4 tiles ahead of it
        jsr     ahead
        rts
@g3:    cpx     #3
        bne     @g4
        lda     #2              ; 3: twice the way from ghost 1 to 2 ahead
        jsr     ahead
        lda     tx
        asl
        sec
        sbc     ax+1
        sta     tx
        lda     ty
        asl
        sec
        sbc     ay+1
        sta     ty
        rts
@g4:    lda     ax,x            ; 4: the muncher, or its corner when close
        sec
        sbc     ax
        bpl     @d1
        eor     #$FF
        clc
        adc     #1
@d1:    sta     tmp
        lda     ay,x
        sec
        sbc     ay
        bpl     @d2
        eor     #$FF
        clc
        adc     #1
@d2:    clc
        adc     tmp
        cmp     #9
        bcc     @corner
        lda     ax
        sta     tx
        lda     ay
        sta     ty
        rts

; tx, ty = A tiles ahead of the muncher
ahead:  sta     tmp
        lda     ax
        sta     tx
        lda     ay
        sta     ty
        ldy     adir
@l:     lda     tx
        clc
        adc     dir_dx,y
        sta     tx
        lda     ty
        clc
        adc     dir_dy,y
        sta     ty
        dec     tmp
        bne     @l
        ldx     gi
        rts

; ---- collisions ---------------------------------------------------------------------------
; after the muncher moved: is it on a ghost?
check_hits:
        ldx     #1
@l:     stx     gi
        lda     gst,x
        cmp     #G_ACTIVE
        bne     @n
        lda     ax,x
        cmp     ax
        bne     @n
        lda     ay,x
        cmp     ay
        bne     @n
        jsr     meet
@n:     ldx     gi
        inx
        cpx     #NACT
        bne     @l
        rts

; after ghost gi moved from gpx, gpy: on the muncher, or did they swap?
ghost_hit:
        ldx     gi
        lda     gst,x
        cmp     #G_ACTIVE
        bne     @r
        lda     ax,x
        cmp     ax
        bne     @swap
        lda     ay,x
        cmp     ay
        beq     meet
@swap:  lda     gpx             ; swapped places this tick
        cmp     ax
        bne     @r
        lda     gpy
        cmp     ay
        bne     @r
        lda     ax,x
        cmp     apx
        bne     @r
        lda     ay,x
        cmp     apy
        beq     meet
@r:     rts

; the muncher meets ghost gi: eat it, or be caught
meet:   ldx     gi
        lda     gfr,x
        bne     @eat
        lda     #1
        sta     dead
        rts
@eat:   lda     #SND_GHOST
        jsr     sfx_snd
        lda     #G_EYES
        sta     gst,x
        lda     #0
        sta     gfr,x
        ldy     eat_n           ; 200, 400, 800, 1600
        lda     #0
        ldx     ghost_pts,y
        txa
        tay
        lda     #0
        jsr     add_score
        lda     eat_n
        cmp     #3
        bcs     @p
        inc     eat_n
@p:     jsr     put_sprites     ; a short pause to see it
        lda     #200
        jmp     delay_ms

; ---- drawing the actors ---------------------------------------------------------------------
; the sprite for actor X -> A
sprite_of:
        txa
        bne     @ghost
        lda     pmouth          ; the muncher: mouth open or shut
        beq     @shut
        lda     adir
        asl
        clc
        adc     #SP_UP
        rts
@shut:  lda     #SP_SHUT
        rts
@ghost: lda     gst,x
        cmp     #G_EYES
        bne     @1
        lda     #SP_EYES
        rts
@1:     lda     tick            ; skirt waves every 8 ticks
        lsr
        lsr
        lsr
        and     #1
        asl
        sta     tmp
        lda     gfr,x
        beq     @normal
        lda     fr_t            ; near the end of the fright: flash
        cmp     #50
        bcs     @scared
        lda     tick
        and     #8
        beq     @normal
@scared:lda     #SP_SCARED1
        clc
        adc     tmp
        rts
@normal:lda     #SP_GHOST1
        clc
        adc     tmp
        rts

; ============================================================================
; input
; ============================================================================
read_input:
        lda     ctrl
        beq     @keys
        jsr     read_pad        ; gamepad: the d-pad held steers
        lda     pad             ; (bits 4-7: up, down, left, right)
        lsr
        lsr
        lsr
        lsr
        sta     tmp
        beq     @start
        lda     padnew          ; prefer a newly pressed direction
        lsr
        lsr
        lsr
        lsr
        and     tmp
        bne     @pick
        lda     tmp
@pick:  ldy     #0
@bit:   lsr
        bcs     @got
        iny
        cpy     #4
        bne     @bit
        beq     @start
@got:   lda     pad_dir,y
        sta     want
@start: lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pad_pause
@keys:  jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @keys
@done:  rts

handle_key:
        ldx     esc_st          ; ESC [ A..D are the arrow keys
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
        sec
        sbc     #'A'
        cmp     #4
        bcs     @x
        tax
        lda     arrow_dir,x
        sta     want
@x:     rts
@plain: cmp     #$1B
        bne     @ar
        inc     esc_st
        rts
@ar:    ldx     #3              ; the ROM's arrow key codes
@ak:    cmp     key_dir,x
        beq     @dir
        dex
        bpl     @ak
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
@uc:    ldx     #3
@k:     cmp     wasd,x
        beq     @dir
        dex
        bpl     @k
        cmp     #'Q'
        beq     @quit
        cmp     #'P'
        beq     @pause
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@dir:   stx     want            ; wasd (and key_dir) in direction order
        rts
@quit:  lda     #1
        sta     quit
        rts
@pause: jsr     paused_on
@pw:    jsr     sfx_poll
        jsr     getc
        bcc     @pw
        jmp     paused_off

; pause until Start is pressed again (or a key)
pad_pause:
        jsr     paused_on
@l:     jsr     sfx_poll
        jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @done
        jsr     getc
        bcc     @l
@done:  jsr     flush_in
        jmp     paused_off

; PAUSED over the maze (the sound quiet, the pellets still)
paused_on:
        jsr     sfx_hush
        jsr     no_flash
        lda     #<paused_txt
        ldy     #>paused_txt
        jmp     print
paused_off:
        ldy     #READY_ROW
        jsr     dot_row
        lda     #1
        sta     flash_on
        jsr     SBC_TICKS       ; (the next tick doesn't hurry)
        sta     last_tick
        rts

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"

        .include "muncher_data.inc"
        .include "muncher_sound.inc"    ; the sounds (game_sounds.py)
        .include "muncher_gfx.inc"      ; the PICO9918 graphics (gen_pico.py)

mrow_lo:
.repeat MAZE_H, I
        .byte   <(maze + I * 40)
.endrepeat
mrow_hi:
.repeat MAZE_H, I
        .byte   >(maze + I * 40)
.endrepeat

dir_dx: .byte   0, $FF, 0, 1    ; up, left, down, right
dir_dy: .byte   $FF, 0, 1, 0
wasd:   .byte   "WASD"          ; in direction order
arrow_dir:
        .byte   UP, DOWN, RIGHT, LEFT   ; ESC [ A, B, C, D
pad_dir:.byte   UP, DOWN, LEFT, RIGHT   ; pad bits 4, 5, 6, 7
key_dir:.byte   KEY_UP, KEY_LEFT, KEY_DOWN, KEY_RIGHT   ; in direction order

; actors: muncher, ghosts 1-4
start_x:  .byte START_X, 19, 19, 17, 21
start_y:  .byte START_Y, DOOR_Y, HOME_Y, HOME_Y, HOME_Y
start_dir:.byte LEFT, LEFT, UP, RIGHT, LEFT
start_st: .byte 0, G_ACTIVE, G_HOUSE, G_HOUSE, G_HOUSE
start_rel:.byte 0, 0, 1, 90, 180        ; ticks before leaving the house
corner_x: .byte 0, 37, 1, 37, 1         ; scatter corners
corner_y: .byte 0, $FE, $FE, 22, 22
ghost_pts:.byte $02, $04, $08, $16      ; hundreds (BCD)
; scatter / chase phases in units of 8 ticks; 0 = for ever
mode_len: .byte 26, 75, 26, 75, 19, 0

; ---- text ------------------------------------------------------------------------------
READY_ROW       = 11            ; READY!, PAUSED: over maze row 11
CAST_COL        = 7
CAST_X          = CAST_COL * 8 - 1
need_txt:
        .byte   13, 10, "MUNCHER NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
cls_txt:.byte   TC_CLS, TERM
title_txt:
        .byte   TC_CLS, TC_L2
        .byte   TC_ROW, 2, TC_COL, 9, "M U N C H E R"
        .byte   TC_L1
        .byte   TC_ROW, 4, TC_COL, 1, "EAT EVERY DOT, KEEP AWAY FROM"
        .byte   TC_ROW, 5, TC_COL, 1, "THE GHOSTS."
        .byte   TC_ROW, 8, TC_COL, 9, "YOU"
        .byte   TC_ROW, 10, TC_COL, 12, "THE GHOSTS"
        .byte   TC_ROW, 12, TC_COL, 9, "EATEN: 200 TO 1600"
        .byte   TC_ROW, 14, TC_COL, 9, "DOT            10"
        .byte   TC_ROW, 15, TC_COL, 9, "POWER PELLET   50"
        .byte   TC_ROW, 20, TC_COL, 0, "WASD/ARROWS  P PAUSE  M SOUND"
        .byte   TC_ROW, 21, TC_COL, 0, "Q QUIT"
        .byte   TC_ROW, 23, TC_COL, 6, "SPACE OR START: PLAY", TERM
; the title's sprites: y, x, pattern, colour
cast_tab:
        .byte   8 * 8 - 1, CAST_X, SP_RIGHT / 2, MUNCH_COL
        .byte   10 * 8 - 1, CAST_X - 8, SPAT_EYES + 3, EYES_COL
        .byte   10 * 8 - 1, CAST_X + 4, SPAT_EYES + 3, EYES_COL
        .byte   10 * 8 - 1, CAST_X + 16, SPAT_EYES + 3, EYES_COL
        .byte   10 * 8 - 1, CAST_X + 28, SPAT_EYES + 3, EYES_COL
        .byte   10 * 8 - 1, CAST_X - 8, SP_GHOST1 / 2, 8
        .byte   10 * 8 - 1, CAST_X + 4, SP_GHOST2 / 2, 3
        .byte   10 * 8 - 1, CAST_X + 16, SP_GHOST1 / 2, 7
        .byte   10 * 8 - 1, CAST_X + 28, SP_GHOST2 / 2, $A
        .byte   12 * 8 - 1, CAST_X, SP_SCARED1 / 2, SCARED_COL
NCAST           = 10
hud_txt:.byte   TC_ROW, HUD_ROW, TC_COL, 0, "SCORE"
        .byte   TC_COL, 17, "HIGH"
        .byte   TC_ROW, HUD_ROW+1, TC_COL, 0, "LIVES"
        .byte   TC_COL, 10, "LEVEL"
        .byte   TC_COL, 21, "P PAUSE", TERM
ready_txt:
        .byte   TC_L2, TC_ROW, READY_ROW, TC_COL, 13, "READY!", TERM
paused_txt:
        .byte   TC_L2, TC_ROW, READY_ROW, TC_COL, 13, "PAUSED", TERM
over_txt:
        .byte   TC_L2
        .byte   TC_ROW, 10, TC_COL, 7, "                  "
        .byte   TC_ROW, 11, TC_COL, 7, "    GAME  OVER    "
        .byte   TC_ROW, 12, TC_COL, 7, "  SPACE/A: TITLE  "
        .byte   TC_ROW, 13, TC_COL, 7, "                  ", TERM

ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: PAD)    ", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD (G: KEYBOARD)", TERM


; ============================================================================
; variables (not in the file)
; ============================================================================
        .segment "BSS"
bss_start:
ctrl:       .res 1              ; 0 keyboard, 1 gamepad
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
score_dirty:.res 1
lives:      .res 1
level:      .res 1
dots:       .res 2
pspeed:     .res 1
gspeed:     .res 1
fr_len:     .res 1
fr_t:       .res 1
eat_n:      .res 1
mode:       .res 1
mode_t:     .res 1
mode_div:   .res 1
tick:       .res 1
dead:       .res 1
quit:       .res 1
esc_st:     .res 1
want:       .res 1
pmouth:     .res 1
waka:       .res 1              ; which dot sound is next
fresh:      .res 1              ; a new game: play its tune at READY
; actors (0 = the muncher)
ax:         .res NACT
ay:         .res NACT
adir:       .res NACT
aacc:       .res NACT
gst:        .res NACT           ; ghost state
gfr:        .res NACT           ; frightened
grev:       .res NACT           ; turn round at the next step
grel:       .res NACT           ; ticks before leaving the house
apx:        .res 1              ; where the muncher was before its move
apy:        .res 1
gpx:        .res 1              ; where the ghost was before its move
gpy:        .res 1
gi:         .res 1
ri:         .res 1
nx:         .res 1
ny:         .res 1
ax_tmp:     .res 1
ay_tmp:     .res 1
tx:         .res 1
ty:         .res 1
back:       .res 1
best:       .res 1
best_d:     .res 1
dtry:       .res 1
dcnt:       .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
; the display
last_tick:  .res 1
lay:        .res 1              ; the layer print / gotoxy write to ($08, $10)
cur_x:      .res 1
cur_y:      .res 1
pr_row:     .res 1
dr_x:       .res 1              ; the dot layer: a group's first tile
dr_y:       .res 1
dr_t:       .res 1
dr_k:       .res 1
dr_r:       .res 1
flash_on:   .res 1              ; the pellets flash
flash_st:   .res 1
snap:       .res 1              ; the actors were just placed: no gliding
ghosts_off: .res 1
die_pic:    .res 1              ; the muncher's picture while it dies (0: none)
sg_y:       .res 1
afx:        .res NACT           ; the tile an actor glides from
afy:        .res NACT
atx:        .res NACT           ; ... and to
aty:        .res NACT
lacc:       .res NACT           ; its accumulator last time
spx:        .res NACT           ; its sprite's place
spy:        .res NACT
satt:       .res 44             ; the sprite attributes being built
bss_end:

        .segment "MAZE"
maze:       .res 4 * 256        ; 21 rows x 40 tiles (copied 4 pages at a time)
