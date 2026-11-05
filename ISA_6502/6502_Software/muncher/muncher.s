; ============================================================================
; muncher.s - a maze chase game (in the style of Pac-Man) for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal using its
; control code mode (terminal setup item J must be ON).
;
;   build:  python3 gen.py > muncher_data.inc   (only after changing maze.py)
;           make                                (needs sbc_api.inc)
;   run:    L MUNCHER 0500     then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  speed      delay per game tick, about 1 ms per unit (default 25)
;   $0504  controls   at start: 0 keyboard, 1 gamepad (G on the title
;                     screen switches; A or Start on the pad picks the pad)
;   $0505  sound      at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2), the sounds in muncher_sound.inc (made by
; ../ay/tools/game_sounds.py).  Without the card the game is just silent.
;
; Keys:    W A S D or the arrow keys   steer      P pause   Q quit
;          M  sound on / off
; Gamepad: d-pad steers, Start pauses
;
; The maze is 39 x 21 tiles; a tile is 4 x 4 pixels = 2 block graphics
; characters, so tile (x, y) is at text column 2x, row y.  Walls are drawn as
; outlines: a wall tile gets a 1 pixel line on each side that faces an open
; tile.  The muncher and the 4 ghosts move a tile at a time; each has a speed
; that is added to an accumulator every tick and it moves when that carries.
;
; Ghosts: each picks, at every tile, the direction (never straight back) that
; brings it closest to its target.  In "scatter" phases the targets are the 4
; corners; in "chase" phases ghost 1 heads for you, ghost 2 for 4 tiles ahead
; of you, ghost 3 for a point that flanks you with ghost 1, and ghost 4 for
; you until it gets close, then its corner.  After a power pellet they run
; around at random and can be eaten; their eyes then go home.
;
; No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"   ; fixed ROM entry points ($FE00 table)

SPEED_DEFAULT   = 25

; ---- terminal control codes -----------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
TC_TILE         = $0B           ; n: draw tile n             (terminal v1.4)
TC_DEFTILE      = $19           ; n c r data: define tile n  (terminal v1.4)
NTILES          = 20            ; tiles 0-13: the sprites, 14-19: the maze tiles
T_TILE0         = 14            ; (2 x 1 characters each)
ATTR_TEXT       = $00
ATTR_RV         = $04
; reverse video is an ANSI sequence (in terminal v1.4, attribute bit 2 is the
; double size font, not reverse)
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
ATTR_GFX        = $80
TERM            = $FF

; ---- tiles -------------------------------------------------------------------------
T_EMPTY         = 0
T_DOT           = 1
T_PILL          = 2
T_WALL          = 3
T_DOOR          = 4
T_HOUSE         = 5

HUD_ROW         = 22
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
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; sound on the AY-3-8910 card

putc            = SBC_CHROUT    ; preserves A, X, Y
getc            = SBC_CHRIN     ; carry set = key in A

; ----------------------------------------------------------------------------
; output helpers
; ----------------------------------------------------------------------------
putblk: inc     cur_x           ; (the cursor moves on; repeat must be 1)
        cmp     #$20            ; block graphics pattern (00-1F, 7F need 1A)
        bcc     @lit
        cmp     #$7F
        bne     @out
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@out:   jmp     putc

; draw terminal tile A (2 x 1 characters) at the cursor, cur_rep times
send_tile:
        pha
        lda     #TC_TILE
        jsr     putc
        pla
        jsr     putc
        lda     cur_rep
        asl
        clc
        adc     cur_x
        sta     cur_x
        rts

; store the sprites and the maze tiles in the terminal (2 x 1 tiles; the
; table tile_gfx follows sprites)
def_tiles:
        ldx     #0
        ldy     #0
@t:     lda     #TC_DEFTILE
        jsr     putc
        txa
        jsr     putc
        lda     #2
        jsr     putc
        lda     #1
        jsr     putc
        lda     sprites,y
        jsr     putc
        lda     sprites+1,y
        jsr     putc
        iny
        iny
        inx
        cpx     #NTILES
        bne     @t
        rts

; cursor to column X, row Y, sending only what is needed (the cursor may be
; there already, or on the same row).  Preserves X and Y.
goto_cell:
        cpy     cur_y
        beq     @row
        jsr     gotoxy
        stx     cur_x
        sty     cur_y
        rts
@row:   cpx     cur_x
        beq     @r
        lda     #TC_COL
        jsr     putc
        txa
        stx     cur_x
        jmp     putc
@r:     rts

; cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #$FF            ; (text may follow: the cursor isn't tracked)
        sta     cur_y
        lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
        lda     #TC_COL
        jsr     putc
        txa
        jmp     putc

; the cursor's place is unknown now (text was printed)
lose_cursor:
        lda     #$FF
        sta     cur_y
        rts

; repeat each character (and tile) A times from now on (1-15), block graphics
set_rep:cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        jmp     setattr
@one:   lda     #ATTR_GFX
        jmp     setattr
@r:     rts

gfx_mode:
        lda     #ATTR_GFX
        bne     setattr
txt_mode:
        lda     #ATTR_TEXT
setattr:cmp     attr
        beq     @done
        sta     attr
        pha
        and     #$78            ; the repeat count that goes with it
        lsr
        lsr
        lsr
        bne     @rc
        lda     #1
@rc:    sta     cur_rep
        pla
        pha
        lda     #TC_ATTR
        jsr     putc
        pla
        jsr     putc
@done:  rts

; print the string at A (lo) / Y (hi), terminated by $FF (any length)
print:  sta     @ld+1
        sty     @ld+2
        jsr     lose_cursor
        jsr     txt_mode
        ldy     #0
@ld:    lda     $FFFF,y
        cmp     #TERM
        beq     @done
        jsr     putc
        iny
        bne     @ld
        inc     @ld+2
        jmp     @ld
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

; carry set if tile X, Y counts as open for drawing wall outlines (anything
; but a wall or the door; outside the maze is open too).  Preserves X, Y.
is_open:cpx     #MAZE_W
        bcs     @yes
        cpy     #MAZE_H
        bcs     @yes
        jsr     tile_get
        cmp     #T_WALL
        beq     @no
        cmp     #T_DOOR
        beq     @no
@yes:   sec
        rts
@no:    clc
        rts

; the two characters for tile dt_x, dt_y -> g0, g1
tile_gfx_at:
        ldx     dt_x
        ldy     dt_y
        jsr     tile_get
        sta     dt_t
        cmp     #T_WALL
        beq     @wall
        asl
        tax
        lda     tile_gfx,x
        sta     g0
        lda     tile_gfx+1,x
        sta     g1
        rts
@wall:  lda     #0              ; a line on every side that faces an open tile
        sta     g0
        sta     g1
        lda     #7
        sta     nbi
@nb:    ldy     nbi
        lda     dt_x
        clc
        adc     nb_dx,y
        tax
        lda     dt_y
        clc
        adc     nb_dy,y
        tay
        jsr     is_open
        bcc     @next
        ldy     nbi
        lda     g0
        ora     nb_ml,y
        sta     g0
        lda     g1
        ora     nb_mr,y
        sta     g1
@next:  dec     nbi
        bpl     @nb
        rts

; draw tile X, Y
draw_tile:
        stx     dt_x
        sty     dt_y
        jsr     gfx_mode
        lda     #1
        jsr     set_rep
        jsr     tile_gfx_at
        lda     dt_x
        asl
        tax
        ldy     dt_y
        jsr     goto_cell
        lda     dt_t
        cmp     #T_WALL
        beq     @wall
        clc
        adc     #T_TILE0
        jmp     send_tile
@wall:  lda     g0
        jsr     putblk
        lda     g1
        jmp     putblk

; draw the whole maze, skipping empty tiles.  A run of the same tile (dots
; mostly) is one tile sent with the repeat count.
draw_maze:
        jsr     gfx_mode
        jsr     lose_cursor
        lda     #0
        sta     dt_y
@row:   lda     #0
        sta     dt_x
@col:   jsr     tile_gfx_at
        lda     g0
        ora     g1
        beq     @next           ; empty
        lda     dt_x
        asl
        tax
        ldy     dt_y
        jsr     goto_cell
        lda     dt_t
        cmp     #T_WALL
        bne     @run
        lda     #1
        jsr     set_rep
        lda     g0
        jsr     putblk
        lda     g1
        jsr     putblk
        jmp     @next
@run:   sta     mz_t            ; how many of this tile in a row (up to 15)
        lda     #1
        sta     mz_n
@rl:    lda     dt_x
        clc
        adc     mz_n
        cmp     #MAZE_W
        bcs     @rend
        tax
        ldy     dt_y
        jsr     tile_get
        cmp     mz_t
        bne     @rend
        inc     mz_n
        lda     mz_n
        cmp     #15
        bcc     @rl
@rend:  lda     mz_n
        jsr     set_rep
        lda     mz_t
        clc
        adc     #T_TILE0
        jsr     send_tile
        lda     dt_x
        clc
        adc     mz_n
        sta     dt_x
        dec     dt_x            ; (the loop steps on one)
@next:  inc     dt_x
        lda     dt_x
        cmp     #MAZE_W
        bne     @col
        inc     dt_y
        lda     dt_y
        cmp     #MAZE_H
        beq     *+5
        jmp     @row
        lda     #1
        jmp     set_rep

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
        lda     #$FF
        sta     attr
        jsr     read_pad
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute

title:  jsr     sfx_off
        lda     #$FF
        sta     attr
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     def_tiles
        jsr     gfx_mode        ; the cast
        ldx     #28
        ldy     #8
        jsr     gotoxy
        ldx     #SP_RIGHT
        jsr     put_sprite
        ldx     #28
        ldy     #10
        jsr     gotoxy
        ldx     #SP_GHOST1
        jsr     put_sprite
        ldx     #28
        ldy     #12
        jsr     gotoxy
        ldx     #SP_SCARED1
        jsr     put_sprite
        ldx     #28
        ldy     #14
        jsr     gotoxy
        lda     #T_TILE0+T_DOT
        jsr     send_tile
        ldx     #28
        ldy     #15
        jsr     gotoxy
        lda     #T_TILE0+T_PILL
        jsr     send_tile
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
        lda     #$FF
        sta     attr
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
        jsr     redraw_actors
        jsr     ready           ; "READY!" for a moment

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
        jsr     redraw_actors
        lda     score_dirty
        beq     @sd
        jsr     show_score
@sd:    lda     dead
        bne     died
        lda     dots
        ora     dots+1
        beq     cleared
        lda     speed
        jsr     delay_ms
        jmp     game_loop

; ---- all the dots eaten -------------------------------------------------------------
cleared:
        jsr     sfx_off
        lda     #SND_CLEAR
        jsr     sfx_snd
        lda     #30
        jsr     delay_long      ; 1.5 s
        lda     level
        cmp     #98
        bcs     @same
        inc     level
@same:  jmp     new_level

; ---- caught by a ghost --------------------------------------------------------------
died:   jsr     sfx_off         ; the siren stops
        lda     #10
        jsr     delay_long
        lda     #SND_DIE
        jsr     sfx_snd
        ldx     #1              ; the ghosts vanish
@hide:  stx     gi
        lda     adrawn,x
        beq     @nh
        lda     #0
        sta     adrawn,x
        ldy     ady,x
        lda     adx,x
        tax
        jsr     draw_tile
@nh:    ldx     gi
        inx
        cpx     #NACT
        bne     @hide
        lda     #SP_DIE1        ; the muncher shrinks away
        sta     tmp3
@anim:  jsr     gfx_mode
        lda     ax
        asl
        tax
        ldy     ay
        jsr     gotoxy
        ldx     tmp3
        jsr     put_sprite
        lda     #150
        jsr     delay_ms
        inc     tmp3
        inc     tmp3
        lda     tmp3
        cmp     #SP_DIE4+2
        bcc     @anim
        lda     #150
        jsr     delay_ms
        lda     #0
        sta     adrawn
        ldx     ax
        ldy     ay
        jsr     draw_tile
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
@nohi:  lda     #SND_OVER
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
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
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
        lda     #17
        sta     tmp2
@r:     ldx     tmp2
        ldy     #11
        jsr     draw_tile
        inc     tmp2
        lda     tmp2
        cmp     #22
        bne     @r
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
        jsr     txt_mode
        ldx     #6
        ldy     #HUD_ROW
        jsr     gotoxy
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        ldx     #25
        ldy     #HUD_ROW
        jsr     gotoxy
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jmp     prbcd

show_lives:
        jsr     txt_mode
        ldx     #42
        ldy     #HUD_ROW
        jsr     gotoxy
        lda     lives
        ora     #'0'
        jmp     putc

show_level:
        jsr     txt_mode
        ldx     #55
        ldy     #HUD_ROW
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
        ; take the actors off the screen where they were drawn
        ldx     #0
@er:    stx     gi
        lda     adrawn,x
        beq     @en
        lda     #0
        sta     adrawn,x
        ldy     ady,x
        lda     adx,x
        tax
        jsr     draw_tile
@en:    ldx     gi
        inx
        cpx     #NACT
        bne     @er
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
        sta     adrawn,x
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
@p:     jsr     redraw_actors   ; a short pause to see it
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

; put the 2 characters of sprite X at the cursor
put_sprite:
        lda     #1
        jsr     set_rep
        txa
        lsr
        jmp     send_tile

; erase the actors that moved or changed (putting the maze back), then draw
; every actor that isn't on the screen: ghosts first, the muncher on top
redraw_actors:
        ldx     #0
@chk:   stx     ri
        lda     adrawn,x
        beq     @cn
        jsr     sprite_of
        ldx     ri
        cmp     aspr,x
        bne     @erase
        lda     ax,x
        cmp     adx,x
        bne     @erase
        lda     ay,x
        cmp     ady,x
        beq     @cn
@erase: lda     #0
        sta     adrawn,x
        lda     adx,x
        sta     ex_
        lda     ady,x
        sta     ey_
        tay
        ldx     ex_
        jsr     draw_tile
        ldx     #NACT-1         ; anyone else drawn there has to be redrawn
@oth:   lda     adrawn,x
        beq     @on
        lda     adx,x
        cmp     ex_
        bne     @on
        lda     ady,x
        cmp     ey_
        bne     @on
        lda     #0
        sta     adrawn,x
@on:    dex
        bpl     @oth
@cn:    ldx     ri
        inx
        cpx     #NACT
        bne     @chk
        ; draw
        jsr     gfx_mode
        ldx     #1
@dr:    stx     ri
        lda     adrawn,x
        bne     @dn
        jsr     draw_actor
        lda     ax,x            ; a ghost drawn on the muncher's tile:
        cmp     ax              ; the muncher goes on top again
        bne     @dn
        lda     ay,x
        cmp     ay
        bne     @dn
        lda     #0
        sta     adrawn
@dn:    ldx     ri
        inx
        cpx     #NACT
        bne     @dr
        ldx     #0
        stx     ri
        lda     adrawn
        bne     @r
        jmp     draw_actor
@r:     rts

; draw actor ri; leaves X = ri
draw_actor:
        ldx     ri
        lda     ax,x
        sta     adx,x
        asl
        pha
        lda     ay,x
        sta     ady,x
        tay
        pla
        tax
        jsr     goto_cell
        ldx     ri
        jsr     sprite_of
        ldx     ri
        sta     aspr,x
        lda     #1
        sta     adrawn,x
        lda     aspr,x
        tax
        jsr     put_sprite
        ldx     ri
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
@dir:   stx     want            ; wasd is in direction order
        rts
@quit:  lda     #1
        sta     quit
        rts
@pause: jsr     sfx_hush        ; (quiet while paused)
@pw:    jsr     getc
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

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"

        .include "muncher_data.inc"
        .include "muncher_sound.inc"    ; the sounds (game_sounds.py)

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

; neighbours for wall outlines: U, D, L, R, UL, UR, DL, DR
nb_dx:  .byte   0, 0, $FF, 1, $FF, 1, $FF, 1
nb_dy:  .byte   $FF, 1, 0, 0, $FF, $FF, 1, 1
nb_ml:  .byte   $03, $C0, $55, $00, $01, $00, $40, $00  ; left character
nb_mr:  .byte   $03, $C0, $00, $AA, $00, $02, $00, $80  ; right character

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
cls_txt:.byte   TC_CLS, TC_CURSOR, 0, TERM
title_txt:
        .byte   TC_CLS, TC_CURSOR, 0
        .byte   TC_ROW, 3, TC_COL, 35, RV_ON, " MUNCHER ", RV_OFF, TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 5, TC_COL, 22, "EAT EVERY DOT, KEEP AWAY FROM THE GHOSTS"
        .byte   TC_ROW, 8, TC_COL, 32, "YOU"
        .byte   TC_ROW, 10, TC_COL, 32, "GHOST"
        .byte   TC_ROW, 12, TC_COL, 32, "AFTER A POWER PELLET: 200-1600"
        .byte   TC_ROW, 14, TC_COL, 32, "DOT            10"
        .byte   TC_ROW, 15, TC_COL, 32, "POWER PELLET   50"
        .byte   TC_ROW, 17, TC_COL, 13, "KEYS: W A S D OR ARROWS  P PAUSE  M SOUND  Q QUIT  PAD: D-PAD"
        .byte   TC_ROW, 21, TC_COL, 25, "PRESS SPACE OR START TO PLAY", TERM
hud_txt:.byte   TC_ROW, HUD_ROW, TC_COL, 0, "SCORE"
        .byte   TC_COL, 20, "HIGH"
        .byte   TC_COL, 36, "LIVES"
        .byte   TC_COL, 49, "LEVEL"
        .byte   TC_COL, 62, "P PAUSE  Q QUIT", TERM
ready_txt:
        .byte   TC_ROW, 11, TC_COL, 35, RV_ON, " READY! ", RV_OFF, TC_ATTR, ATTR_TEXT, TERM
over_txt:
        .byte   TC_ROW, 11, TC_COL, 32, RV_ON, "   GAME  OVER   "
        .byte   TC_ROW, 12, TC_COL, 32, " SPACE/A: TITLE "
        .byte   RV_OFF, TC_ATTR, ATTR_TEXT, TERM
bye_txt:.byte   TC_CLS, TC_CURSOR, '_', TERM

ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM


; ============================================================================
; variables (not in the file)
; ============================================================================
        .segment "BSS"
bss_start:
attr:       .res 1
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
adx:        .res NACT           ; where it is drawn
ady:        .res NACT
aspr:       .res NACT
adrawn:     .res NACT
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
dt_x:       .res 1
dt_t:       .res 1              ; the tile type tile_gfx_at found
mz_t:       .res 1
mz_n:       .res 1
cur_x:      .res 1              ; where the cursor is (cur_y $FF: unknown)
cur_y:      .res 1
cur_rep:    .res 1              ; the repeat count the terminal has
dt_y:       .res 1
g0:         .res 1
g1:         .res 1
nbi:        .res 1
gap:        .res 1
ex_:        .res 1
ey_:        .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
bss_end:

        .segment "MAZE"
maze:       .res 4 * 256        ; 21 rows x 40 tiles (copied 4 pages at a time)
