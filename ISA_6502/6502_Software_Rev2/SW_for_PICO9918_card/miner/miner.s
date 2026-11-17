; ============================================================================
; miner.s - MINER MOS, a platform game for the 6502 SBC, CPU Rev2, on the
;           PICO9918 card
;
;   build:  make.bat (make.bat 4 for a 4 MHz clock)
;   run:    L MINER 0800   then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  video frames (1/60 s) for two game frames (default 5: 24 frames
;          a second, the original's 40 ms)
;   $0804  controls at start: 0 keyboard, 1 gamepad (default; any pad
;          button switches to it)
;   $0805  sound at start: 0 on, 1 off (M switches)
;
; The game is the PIC32 terminal version's, unchanged: the rooms, the
; movement, the guardians, the air, the sound.  What is new is the picture:
; the room (40 x 20 tiles of 4 x 4 game pixels) is drawn into the Graphics
; II bitmap, a game pixel 1.5 x 2 screen pixels, straight from the tile map
; (4 tiles = 8 block graphics characters = 3 bitmap cells, each cell
; coloured by the tiles in it).  MOS, the guardians and the portal are
; 16 x 16 sprites; each picture comes in 4 versions (facing either way, at
; an even or odd x), loaded into a sprite's pattern when it changes.  Text
; is drawn into the bitmap with the font.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 5             ; video frames for 2 game frames

; ---- text (print) ------------------------------------------------------------
TC_CLS          = $0C           ; print: clear the screen
TC_COL          = $0E           ;   the next byte is the column
TC_ROW          = $0F           ;   ... the row
.define RV_ON   $11             ;   highlighted text (white on blue) from here
.define RV_OFF  $12
TERM            = $FF

; ---- VRAM (Graphics II bitmap) ----------------------------------------------
V_PAT           = $0000
V_COL           = $2000
V_SPAT          = $1800
V_NAME          = $3800
V_SATTR         = $3B00
VDP_NAME        = V_NAME

; ---- the room ----------------------------------------------------------------------
COLS            = 40            ; tiles
ROWS            = 20
NTILE           = COLS * ROWS
EMPTY           = 0             ; tiles
FLOOR           = 1
WALL            = 2
CONV_L          = 3
CONV_R          = 4
CR0             = 5             ; crumbling floor, 3 stages
CR2             = 7
HAZARD          = 8
KEY             = 9
NAME_ROW        = 20
AIR_ROW         = 21
AIR_COL0        = 4             ; the bar's first cell
AIR_RATE        = 12            ; frames a unit of air lasts

; ---- Willy -------------------------------------------------------------------------
W_W             = 6             ; his box
W_H             = 8
FALL_MAX        = 24            ; a fall longer than this kills
CRUMBLE_T       = 6             ; frames on a crumbling floor per stage
ST_STAND        = 0
ST_JUMP         = 1
ST_FALL         = 2

; ---- sprite slots (higher on top) -----------------------------------------------------
NSLOT           = 16
SL_WILLY        = 15
SL_GUARD        = 8             ; 8-14
MAXG            = 7
SL_PORTAL       = 0

; ============================================================================
        .segment "RODATA"
        .include "miner_data.inc"
        .include "miner_sound.inc"      ; the music and effects (game_sounds.py)
        .include "miner_gfx.inc"        ; the PICO9918 graphics (gen_pico.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; music and effects on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines

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
        cmp     #TC_CLS
        bne     @1
        jsr     new_screen
        jmp     @nx
@1:     cmp     #TC_ROW
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
        jsr     txt_mode        ; the high score
        ldx     #7
        ldy     #17
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
        ldx     #NTSPR-1        ; Willy and the guardians, for show
@ts:    lda     #1
        sta     des_on+1,x
        lda     tspr_n,x
        sta     des_n+1,x
        lda     tspr_x,x
        sta     des_x+1,x
        lda     #32 + 52
        sta     des_y+1,x
        lda     #0
        sta     des_f+1,x
        dex
        bpl     @ts
        jsr     put_sprites
        jsr     show_ctrl
        lda     #<start_txt
        ldy     #>start_txt
        jsr     print
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
        jsr     cls
        ldx     #NSLOT-1
        lda     #0
@f:     sta     des_on,x
        dex
        bpl     @f
        rts

; ============================================================================
; the display: the PICO9918 in Graphics II (a bitmap)
; ============================================================================
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
        jsr     cls
        lda     #$C2            ; R1: display on, 16K, 16 x 16 sprites, and
        ldx     #1              ; bit 5 (the VDP interrupt) off
        jmp     vdp_reg

; the screen blank (white on black), no sprites
cls:    lda     #<V_PAT
        ldy     #>V_PAT
        jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #>(256 * 8 * 3)
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        lda     #<V_COL
        ldy     #>V_COL
        jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #>(256 * 8 * 3)
        sta     vdp_n+1
        lda     #C_TEXT
        jsr     vdp_fill
        lda     #0
        sta     rv
        sta     cur_col
        sta     cur_row
        ; fall through

; no sprites (and none of their pictures known to be loaded)
hide_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        ldx     #15
        lda     #$FF
@l:     sta     spr_ver,x
        dex
        bpl     @l
        rts

; ---- the room -------------------------------------------------------------------
; the whole room: every group of 4 tiles
draw_room:
        lda     #0
        sta     tr
@r:     lda     #0
        sta     pgrp
@g:     jsr     draw_tgroup
        inc     pgrp
        lda     pgrp
        cmp     #COLS / 4
        bne     @g
        inc     tr
        lda     tr
        cmp     #ROWS
        bne     @r
        rts

; draw tile tc, tr as the map has it: its group of 4
draw_tile:
        lda     tc
        lsr
        lsr
        sta     pgrp
        ; fall through

; tiles 4 pgrp .. 4 pgrp + 3 of row tr -> 3 bitmap cells (columns 1 + 3
; pgrp, row tr): their 8 characters spread, and each cell's colour from the
; tiles in it (cell 0: tile 0, else 1; cell 1: 1, else 2; cell 2: 3, else 2)
draw_tgroup:
        jsr     sfx_poll
        ldx     tr
        lda     pgrp
        asl
        asl
        clc
        adc     rowoff_lo,x
        sta     @m+1
        lda     rowoff_hi,x
        adc     #0
        sta     @m+2
        lda     @m+1
        clc
        adc     #<map
        sta     @m+1
        lda     @m+2
        adc     #>map
        sta     @m+2
        ldx     #0
@t:
@m:     lda     $FFFF,x
        tay
        lda     tcol,y
        sta     tg_c,x
        lda     tile_l,y
        sta     tmp4
        lda     tile_r,y
        pha
        txa
        asl
        tay
        lda     tmp4
        sta     grp,y
        pla
        sta     grp+1,y
        inx
        cpx     #4
        bne     @t
        lda     tg_c            ; the cells' inks
        bne     @i0
        lda     tg_c+1
@i0:    sta     dg_c0
        lda     tg_c+1
        bne     @i1
        lda     tg_c+2
@i1:    sta     dg_c1
        lda     tg_c+3
        bne     @i2
        lda     tg_c+2
@i2:    sta     dg_c2
        lda     tr
        sta     prow
        ; fall through

; grp[0..7] -> cells 1 + 3 pgrp .. + 2 of row prow, inks dg_c0..2 on black.
; Each character (2 x 4 pixels, bit 2k = row k's left pixel, 2k+1 its
; right) becomes 3 screen pixels across (left, left, right at an even
; column; left, right, right at an odd one) by 8 lines.
draw_group:
        ldx     #0              ; k
@k:     stx     dg_k
        lda     grp
        and     #3
        tay
        lda     ev_75,y
        sta     dg_t
        lda     grp+1
        and     #3
        tay
        lda     od_42,y
        ora     dg_t
        sta     dg_t
        lda     grp+2
        and     #3
        tay
        lda     ev_10,y
        ora     dg_t
        ldx     dg_k
        sta     dg_b0,x
        lda     grp+2
        and     #3
        tay
        lda     ev_7,y
        sta     dg_t
        lda     grp+3
        and     #3
        tay
        lda     od_64,y
        ora     dg_t
        sta     dg_t
        lda     grp+4
        and     #3
        tay
        lda     ev_31,y
        ora     dg_t
        sta     dg_t
        lda     grp+5
        and     #3
        tay
        lda     od_0,y
        ora     dg_t
        sta     dg_b1,x
        lda     grp+5
        and     #3
        tay
        lda     od_76,y
        sta     dg_t
        lda     grp+6
        and     #3
        tay
        lda     ev_53,y
        ora     dg_t
        sta     dg_t
        lda     grp+7
        and     #3
        tay
        lda     od_20,y
        ora     dg_t
        sta     dg_b2,x
        ldx     #7
@sh:    lsr     grp,x
        lsr     grp,x
        dex
        bpl     @sh
        ldx     dg_k
        inx
        cpx     #4
        beq     @put
        jmp     @k
@put:   lda     pgrp
        asl
        adc     pgrp
        adc     #1
        sta     t_col
        lda     prow
        sta     t_row
        jsr     cell_addr
        lda     t_ca
        sta     VDP_CTRL
        lda     t_ca+1
        ora     #$40
        sta     VDP_CTRL
        ldx     #0
@c0:    lda     dg_b0,x
        sta     VDP_DATA
        sta     VDP_DATA
        inx
        cpx     #4
        bne     @c0
        ldx     #0
@c1:    lda     dg_b1,x
        sta     VDP_DATA
        sta     VDP_DATA
        inx
        cpx     #4
        bne     @c1
        ldx     #0
@c2:    lda     dg_b2,x
        sta     VDP_DATA
        sta     VDP_DATA
        inx
        cpx     #4
        bne     @c2
        lda     t_ca            ; the colours
        sta     VDP_CTRL
        lda     t_ca+1
        ora     #$40 | >V_COL
        sta     VDP_CTRL
        ldx     #0
@cc:    lda     dg_c0,x
        asl
        asl
        asl
        asl
        ora     #1
        ldy     #8
@c8:    sta     VDP_DATA
        dey
        bne     @c8
        inx
        cpx     #3
        bne     @cc
        rts

; the tiles' colours for this room
room_cols:
        ldx     room
        lda     room_floor,x
        sta     tcol+FLOOR
        sta     tcol+CR0
        sta     tcol+CR0+1
        sta     tcol+CR2
        lda     room_wall,x
        sta     tcol+WALL
        lda     #CONV_COL
        sta     tcol+CONV_L
        sta     tcol+CONV_R
        lda     #HAZARD_COL
        sta     tcol+HAZARD
        lda     #KEY_COL
        sta     tcol+KEY
        lda     #0
        sta     tcol+EMPTY
        rts

; ---- the air: a bar of one pixel a unit from column 4 of AIR_ROW ---------------
draw_air:
        lda     #AIR_COL0
@c:     pha
        jsr     air_cell
        pla
        clc
        adc     #1
        cmp     #32
        bne     @c
        rts

; the bar's cell at column A: pixels for the units in it
air_cell:
        sta     t_col
        lda     #AIR_ROW
        sta     t_row
        jsr     cell_addr
        lda     t_ca
        ldy     t_ca+1
        jsr     vdp_waddr
        lda     t_col           ; units in this cell: air - 8 (col - 4), 0..8
        sec
        sbc     #AIR_COL0
        asl
        asl
        asl
        sta     tmp4
        lda     air
        sec
        sbc     tmp4
        bcs     @p
        lda     #0
@p:     cmp     #8
        bcc     @n
        lda     #8
@n:     tax
        lda     air_bits,x
        ldx     #0
        stx     VDP_DATA
        ldx     #6
@w:     sta     VDP_DATA
        dex
        bne     @w
        lda     #0
        sta     VDP_DATA
        lda     t_ca+1          ; its colour
        ora     #>V_COL
        tay
        lda     t_ca
        jsr     vdp_waddr
        lda     #AIR_COL
        ldx     #8
@cw:    sta     VDP_DATA
        dex
        bne     @cw
        rts
air_bits:
        .byte   $00, $80, $C0, $E0, $F0, $F8, $FC, $FE, $FF

; ---- the sprites: the slots as set_sprites wants them (des_*), highest slot
; first (on top); each hardware sprite k has its own pattern (k * 4), loaded
; only when its picture changes ------------------------------------------------------
put_sprites:
        lda     #0
        sta     sp_k
        ldx     #NSLOT-1
@l:     stx     hs_i
        lda     des_on,x
        bne     @on
        jmp     @n
@on:    lda     des_n,x         ; the version: picture * 4 + face * 2 + odd x
        asl
        asl
        sta     tmp4
        lda     des_f,x
        asl
        ora     tmp4
        sta     tmp4
        lda     des_x,x
        and     #1
        ora     tmp4
        ldy     sp_k
        cmp     spr_ver,y
        beq     @same
        sta     spr_ver,y       ; its picture into pattern k * 4: 32 bytes
        ldx     #0
        stx     sp_src+1
        asl
        rol     sp_src+1
        asl
        rol     sp_src+1
        asl
        rol     sp_src+1
        asl
        rol     sp_src+1
        asl
        rol     sp_src+1
        clc
        adc     #<spr_vers
        sta     @v+1
        lda     sp_src+1
        adc     #>spr_vers
        sta     @v+2
        lda     sp_k
        asl
        asl
        asl
        asl
        asl
        php
        clc
        adc     #<V_SPAT
        tax
        lda     #>V_SPAT
        plp
        adc     #0
        tay
        txa
        jsr     vdp_waddr
        ldx     #0
@v:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @v
@same:  lda     sp_k            ; its place in the attribute table
        asl
        asl
        clc
        adc     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     hs_i
        lda     des_y,x         ; Y = 2 (y - 32) - 1
        sec
        sbc     #32
        asl
        sec
        sbc     #1
        sta     VDP_DATA
        lda     des_x,x         ; X = 8 + 1.5 (x - 32)
        sec
        sbc     #32
        sta     tmp4
        lsr
        clc
        adc     tmp4
        adc     #8
        sta     VDP_DATA
        lda     sp_k
        asl
        asl
        sta     VDP_DATA
        ldy     des_n,x
        lda     pic_col,y
        sta     VDP_DATA
        inc     sp_k
@n:     ldx     hs_i
        dex
        bmi     @end
        jmp     @l
@end:   lda     sp_k            ; the end of the list
        asl
        asl
        clc
        adc     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        rts

; the frame's pace: speed video frames for two game frames, split 2 + 3 for
; 5 (the ROM's 60 Hz counter); the sound goes on meanwhile
pace:   lda     speed
        lsr
        sta     tmp4
        lda     frame
        and     #1
        beq     @w
        lda     speed
        sec
        sbc     tmp4
        sta     tmp4
@w:     jsr     sfx_poll
        jsr     SBC_TICKS
        sec
        sbc     last_tick
        cmp     tmp4
        bcc     @w
        jsr     SBC_TICKS
        sta     last_tick
        rts

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     room
        sta     quit
        lda     #3
        sta     lives
start_room:
        jsr     load_room
        jsr     new_screen
        jsr     room_cols
        jsr     draw_room
        jsr     draw_names
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        lda     #0
        sta     frame
        sta     air_t
        sta     jhold
        sta     mv_hold
        jsr     sfx_off         ; the tune, from its start
        lda     #MUS_HALL
        jsr     sfx_snd
        lda     #MUS_HALL+1
        jsr     sfx_snd

; ---- the frame loop --------------------------------------------------------------
        jsr     SBC_TICKS
        sta     last_tick
game_loop:
        jsr     sfx_poll
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     guards_move
        lda     in_d
        ldx     in_j
        jsr     willy_step
        jsr     willy_touch     ; hazards, keys
        jsr     guards_hit
        jsr     air_tick
        jsr     set_sprites
        jsr     put_sprites
        jsr     hud_update
        jsr     pace
        inc     frame
        lda     w_dead
        beq     @2
        jmp     life_lost
@2:     lda     keys_left       ; all the keys, and in the portal?
        bne     game_loop
        jsr     in_portal
        bcc     game_loop
        jmp     room_done

; Willy is gone: he blinks, a life goes, and the room starts again
life_lost:
        jsr     sfx_off         ; the tune stops
        lda     #SND_DIEA
        jsr     sfx_snd
        lda     #SND_DIEC
        jsr     sfx_snd
        ldx     #8
@b:     stx     tmp3
        txa
        and     #1
        beq     @hd
        jsr     set_sprites     ; (shown)
        jmp     @sd
@hd:    lda     #0              ; (hidden)
        sta     des_on+SL_WILLY
@sd:    jsr     put_sprites
        lda     #80
        jsr     delay_ms
        ldx     tmp3
        dex
        bne     @b
        dec     lives
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        lda     lives
        bne     @more
        jmp     game_over
@more:  jmp     start_room

; through the portal: the air left goes to the score, then the next room
room_done:
        jsr     hide_sprites
        jsr     sfx_off
        lda     #SND_ROOM
        jsr     sfx_snd
        lda     #10
        jsr     delay_long
@a:     lda     air             ; 10 points a unit of air
        beq     @next
        and     #3              ; (a tick every 4)
        bne     @nt
        lda     #SND_AIRTICK
        jsr     sfx_snd
@nt:    jsr     air_down
        lda     #$10
        ldy     #0
        jsr     add_score
        jsr     hud_update
        lda     #8
        jsr     delay_ms
        jmp     @a
@next:  lda     #10
        jsr     delay_long
        inc     room
        lda     room
        cmp     #NROOM
        bcc     @r
        lda     #0              ; all of them: round again
        sta     room
        lda     #SND_ALLA
        jsr     sfx_snd
        lda     #SND_ALLB
        jsr     sfx_snd
        lda     #<allclear_txt
        ldy     #>allclear_txt
        jsr     print
        lda     #40
        jsr     delay_long
@r:     jmp     start_room

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
        jsr     hide_sprites
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
; the room
; ============================================================================
; the room's data (room_lo / hi, room) into its variables and map
load_room:
        ldx     room
        lda     room_lo,x
        sta     src
        lda     room_hi,x
        sta     src+1
        lda     #32             ; (the name is drawn from there)
        jsr     src_add
        jsr     src_get         ; air
        sta     air
        jsr     src_get         ; Willy
        sta     w_x
        jsr     src_get
        sta     w_y
        jsr     src_get         ; the portal
        sta     p_x
        jsr     src_get
        sta     p_y
        jsr     src_get         ; the guardians
        sta     ng
        ldx     #0
@g:     cpx     ng
        beq     @gd
        jsr     src_get
        sta     g_kind,x
        jsr     src_get
        sta     g_axis,x
        jsr     src_get
        sta     g_x,x
        jsr     src_get
        sta     g_y,x
        jsr     src_get
        sta     g_lo,x
        jsr     src_get
        sta     g_hi,x
        jsr     src_get
        sta     g_slow,x
        lda     #1
        sta     g_dir,x
        lda     #0
        sta     g_t,x
        inx
        bne     @g
@gd:    lda     #0              ; the tiles, two to a byte
        sta     keys_left
        sta     tmp2            ; (map index, 16 bits: tmp2 / tmp3)
        sta     tmp3
@t:     jsr     src_get
        pha
        and     #$0F
        jsr     @put
        pla
        lsr
        lsr
        lsr
        lsr
        jsr     @put
        lda     tmp3
        cmp     #>(NTILE)
        bne     @t
        lda     tmp2
        cmp     #<(NTILE)
        bne     @t
        lda     #0              ; Willy: standing, facing right
        sta     w_mode
        sta     w_jt
        sta     w_jdx
        sta     w_anim
        sta     w_crt
        sta     w_dead
        sta     w_face
        lda     w_y
        sta     w_ytop
        rts
@put:   cmp     #KEY
        bne     @p1
        inc     keys_left
@p1:    pha
        lda     #<map
        clc
        adc     tmp2
        sta     @w+1
        lda     #>map
        adc     tmp3
        sta     @w+2
        pla
@w:     sta     $FFFF
        inc     tmp2
        bne     @p2
        inc     tmp3
@p2:    rts

; the next byte of the room data (src), and src + A
src_get:
        lda     src
        sta     @l+1
        lda     src+1
        sta     @l+2
@l:     lda     $FFFF
        inc     src
        bne     @r
        inc     src+1
@r:     rts
src_add:clc
        adc     src
        sta     src
        bcc     @r
        inc     src+1
@r:     rts

; the room's name (row 20, highlighted) and the air
draw_names:
        lda     #<name_txt
        ldy     #>name_txt
        jsr     print
        ldx     room
        lda     room_lo,x
        sta     @n+1
        lda     room_hi,x
        sta     @n+2
        ldx     #0
@n:     lda     $FFFF,x
        jsr     putc
        inx
        cpx     #32
        bne     @n
        lda     #<rvoff_txt
        ldy     #>rvoff_txt
        jsr     print
        lda     #<air_txt
        ldy     #>air_txt
        jsr     print
        jmp     draw_air

; A = the tile at tc, tr (empty outside the room); tile_adr = its address
tile_get:
        lda     tr
        cmp     #ROWS
        bcs     @out
        lda     tc
        cmp     #COLS
        bcs     @out
        ldx     tr
        lda     rowoff_lo,x
        clc
        adc     tc
        sta     tile_adr
        lda     rowoff_hi,x
        adc     #0
        sta     tile_adr+1
        lda     tile_adr
        clc
        adc     #<map
        sta     tile_adr
        sta     @l+1
        lda     tile_adr+1
        adc     #>map
        sta     tile_adr+1
        sta     @l+2
@l:     lda     $FFFF
        rts
@out:   lda     #EMPTY
        rts

; set the tile at tile_adr (from tile_get) to A
tile_set:
        pha
        lda     tile_adr
        sta     @s+1
        lda     tile_adr+1
        sta     @s+2
        pla
@s:     sta     $FFFF
        rts

; ============================================================================
; Willy (see phys.py: the same rules, step by step)
; ============================================================================
; his columns: c0 = x / 4 .. c1 = (x + 5) / 4
w_cols: lda     w_x
        lsr
        lsr
        sta     c0
        lda     w_x
        clc
        adc     #W_W - 1
        lsr
        lsr
        sta     c1
        rts

; carry set if something holds him up (a floor tile under his feet)
support:
        lda     w_y
        clc
        adc     #W_H
        lsr
        lsr
        cmp     #ROWS
        bcs     @no
        sta     tr
        jsr     w_cols
        lda     c0
        sta     tc
@l:     jsr     tile_get
        cmp     #FLOOR
        bcc     @n
        cmp     #CR2 + 1
        bcc     @yes
@n:     inc     tc
        lda     tc
        cmp     c1
        beq     @l
        bcc     @l
@no:    clc
        rts
@yes:   sec
        rts

; A = the conveyor under his feet: 1 right, $FF left, 0 none
conveyor:
        lda     w_y
        clc
        adc     #W_H
        lsr
        lsr
        sta     tr
        jsr     w_cols
        lda     c0
        sta     tc
@l:     jsr     tile_get
        cmp     #CONV_L
        beq     @left
        cmp     #CONV_R
        beq     @right
        inc     tc
        lda     tc
        cmp     c1
        beq     @l
        bcc     @l
        lda     #0
        rts
@left:  lda     #$FF
        rts
@right: lda     #1
        rts

; carry set if column tc has a wall in his rows (y / 4 .. (y + 7) / 4)
wall_rows:
        lda     w_y
        lsr
        lsr
        sta     tr
        lda     w_y
        clc
        adc     #W_H - 1
        lsr
        lsr
        sta     tmp4
@l:     jsr     tile_get
        cmp     #WALL
        beq     @yes
        inc     tr
        lda     tr
        cmp     tmp4
        beq     @l
        bcc     @l
        clc
        rts
@yes:   sec
        rts

; move him A (1 or $FF) across unless a wall or the edge stops him; carry
; set if he moved
move_x: sta     tmp
        cmp     #1
        bne     @left
        lda     w_x             ; right: x + 1 + 5 <= 159
        cmp     #COLS * 4 - W_W
        bcs     @no
        clc
        adc     #W_W            ; (x + 1 + 5) / 4
        lsr
        lsr
        bpl     @chk
@left:  lda     w_x
        beq     @no
        sec
        sbc     #1
        lsr
        lsr
@chk:   sta     tc
        jsr     wall_rows
        bcs     @no
        lda     w_x
        clc
        adc     tmp
        sta     w_x
        sec
        rts
@no:    clc
        rts

; carry set if a wall is just above his head (or the top)
head_blocked:
        lda     w_y
        beq     @yes
        sec
        sbc     #1
        lsr
        lsr
        sta     tr
        jsr     w_cols
        lda     c0
        sta     tc
@l:     jsr     tile_get
        cmp     #WALL
        beq     @yes
        inc     tc
        lda     tc
        cmp     c1
        beq     @l
        bcc     @l
        clc
        rts
@yes:   sec
        rts

; on the ground again: a fall from too high kills
land:   lda     #SND_LAND
        jsr     sfx_snd
        lda     #ST_STAND
        sta     w_mode
        lda     w_y
        sec
        sbc     w_ytop
        cmp     #FALL_MAX + 1
        bcc     @r
        lda     #1
        sta     w_dead
@r:     rts

; carry set if his feet are on a tile's top and something holds him up
on_ground:
        lda     w_y
        clc
        adc     #W_H
        and     #3
        bne     @no
        jmp     support
@no:    clc
        rts

; one frame of Willy: A = -1 / 0 / 1 (left, none, right), X = jump pressed
willy_step:
        sta     w_d
        stx     w_j
        lda     w_mode
        beq     @stand
        cmp     #ST_JUMP
        bne     @fall0
        jmp     @jump
@fall0: jmp     @fall
@stand: jsr     support
        bcs     @held
        lda     #ST_FALL        ; nothing under him: down he goes
        sta     w_mode
        lda     w_y
        sta     w_ytop
        rts
@held:  jsr     conveyor        ; a conveyor takes him its way
        beq     @nc
        sta     w_d
@nc:    lda     w_j
        beq     @walk
        lda     #SND_JUMP
        jsr     sfx_snd
        lda     #ST_JUMP        ; a jump, the way he is going
        sta     w_mode
        lda     #0
        sta     w_jt
        lda     w_d
        sta     w_jdx
        beq     @j0
        jsr     set_face
@j0:    lda     w_y
        sta     w_ytop
        jmp     @jump
@walk:  lda     w_d
        beq     @crum
        jsr     set_face
        lda     w_d
        jsr     move_x
        bcc     @crum
        lda     w_anim
        clc
        adc     #1
        and     #7
        sta     w_anim
@crum:  lda     w_y             ; a crumbling floor under his feet
        clc
        adc     #W_H
        lsr
        lsr
        sta     tr
        jsr     w_cols
        lda     #0
        sta     tmp3            ; (any?)
        lda     c0
        sta     tc
@cl:    jsr     tile_get
        cmp     #CR0
        bcc     @cn
        cmp     #CR2 + 1
        bcs     @cn
        inc     tmp3
@cn:    inc     tc
        lda     tc
        cmp     c1
        beq     @cl
        bcc     @cl
        lda     tmp3
        beq     @r
        inc     w_crt
        lda     w_crt
        cmp     #CRUMBLE_T
        bcc     @r
        lda     #0
        sta     w_crt
        lda     c0              ; each one a stage on
        sta     tc
@cs:    jsr     tile_get
        cmp     #CR0
        bcc     @cs2
        cmp     #CR2 + 1
        bcs     @cs2
        cmp     #CR2
        bne     @cs1
        lda     #<(EMPTY - 1)   ; (gone)
@cs1:   clc
        adc     #1
        jsr     tile_set
        jsr     draw_tile
@cs2:   inc     tc
        lda     tc
        cmp     c1
        beq     @cs
        bcc     @cs
@r:     rts

@jump:  ldx     w_jt            ; this frame's rise or fall
        lda     jtab,x
        sta     w_dy
        inc     w_jt
        lda     w_jdx
        beq     @jy
        jsr     move_x
        bcs     @jy
        lda     #0              ; (a wall: straight on)
        sta     w_jdx
@jy:    lda     w_dy
        beq     @jend
        bpl     @down
@up:    jsr     head_blocked    ; up, a pixel at a time
        bcc     @up1
        lda     #ST_FALL
        sta     w_mode
        rts
@up1:   dec     w_y
        lda     w_y
        sta     w_ytop
        inc     w_dy
        bne     @up
        beq     @jend
@down:  jsr     on_ground       ; down, a pixel at a time, landing on a floor
        bcc     @dn1
        jmp     land
@dn1:   inc     w_y
        dec     w_dy
        bne     @down
@jend:  lda     w_jt
        cmp     #JTAB_LEN
        bne     @jr
        lda     #ST_FALL
        sta     w_mode
@jr:    rts

@fall:  lda     #2              ; 2 pixels a frame, straight down
        sta     w_dy
@fl:    jsr     on_ground
        bcc     @fl1
        jmp     land
@fl1:   inc     w_y
        dec     w_dy
        bne     @fl
        lda     w_y             ; out of the bottom
        clc
        adc     #W_H
        cmp     #ROWS * 4 + 1
        bcc     @fr
        lda     #1
        sta     w_dead
@fr:    rts

set_face:
        lda     w_d
        bmi     @l
        lda     #0
        sta     w_face
        rts
@l:     lda     #1
        sta     w_face
        rts

; the tiles he is on: a hazard kills, a key is his
willy_touch:
        jsr     w_cols
        lda     w_y
        lsr
        lsr
        sta     tr
        lda     w_y
        clc
        adc     #W_H - 1
        lsr
        lsr
        sta     tmp3            ; the last row
@r:     lda     c0
        sta     tc
@c:     jsr     tile_get
        cmp     #HAZARD
        bne     @k
        lda     #1
        sta     w_dead
        bne     @n
@k:     cmp     #KEY
        bne     @n
        lda     #SND_KEY
        jsr     sfx_snd
        lda     #EMPTY
        jsr     tile_set
        jsr     draw_tile
        dec     keys_left
        lda     #$00            ; 100 points
        ldy     #$01
        jsr     add_score
@n:     inc     tc
        lda     tc
        cmp     c1
        beq     @c
        bcc     @c
        inc     tr
        lda     tr
        cmp     tmp3
        beq     @r
        bcc     @r
        rts

; carry set if he is in the portal (boxes overlap)
in_portal:
        lda     w_x             ; x + 5 >= px and x <= px + 7
        clc
        adc     #W_W - 1
        cmp     p_x
        bcc     @no
        lda     p_x
        clc
        adc     #7
        cmp     w_x
        bcc     @no
        lda     w_y             ; y + 7 >= py and y <= py + 7
        clc
        adc     #W_H - 1
        cmp     p_y
        bcc     @no
        lda     p_y
        clc
        adc     #7
        cmp     w_y
        bcc     @no
        sec
        rts
@no:    clc
        rts

; ============================================================================
; the guardians: to and fro between lo and hi, a pixel a frame (or every
; second frame if slow)
; ============================================================================
guards_move:
        ldx     ng
        dex
        bmi     @r
@g:     lda     g_t,x
        eor     #1
        sta     g_t,x
        beq     @go
        lda     g_slow,x
        bne     @n
@go:    lda     g_axis,x
        bne     @v
        lda     g_x,x
        jsr     @turn
        sta     g_x,x
        jmp     @n
@v:     lda     g_y,x
        jsr     @turn
        sta     g_y,x
@n:     dex
        bpl     @g
@r:     rts
@turn:  sta     tmp             ; A = its place: turn at the ends, then move
        lda     g_dir,x
        bmi     @tl
        lda     tmp
        cmp     g_hi,x
        bcc     @ok
        lda     #$FF
        sta     g_dir,x
        bne     @ok
@tl:    lda     tmp
        cmp     g_lo,x
        beq     @tr
        bcs     @ok
@tr:    lda     #1
        sta     g_dir,x
@ok:    lda     tmp
        clc
        adc     g_dir,x
        rts

; a guardian touching Willy kills him (its box 1 pixel in on each side)
guards_hit:
        ldx     ng
        dex
        bmi     @r
@g:     lda     g_x,x           ; x + 5 >= gx + 1 and x <= gx + 6
        clc
        adc     #1
        sta     tmp
        lda     w_x
        clc
        adc     #W_W - 1
        cmp     tmp
        bcc     @n
        lda     g_x,x
        clc
        adc     #6
        cmp     w_x
        bcc     @n
        lda     g_y,x           ; y + 7 >= gy + 1 and y <= gy + 6
        clc
        adc     #1
        sta     tmp
        lda     w_y
        clc
        adc     #W_H - 1
        cmp     tmp
        bcc     @n
        lda     g_y,x
        clc
        adc     #6
        cmp     w_y
        bcc     @n
        lda     #1
        sta     w_dead
@n:     dex
        bpl     @g
@r:     rts

; ============================================================================
; the air: a unit every AIR_RATE frames; none left kills
; ============================================================================
air_tick:
        inc     air_t
        lda     air_t
        cmp     #AIR_RATE
        bcc     @r
        lda     #0
        sta     air_t
        lda     air
        beq     @dead
        jsr     air_down
        lda     air
        bne     @r
@dead:  lda     #1
        sta     w_dead
@r:     rts

; one unit less, and its half character of the bar
air_down:
        dec     air
        lda     air             ; its cell of the bar
        lsr
        lsr
        lsr
        clc
        adc     #AIR_COL0
        cmp     #32
        bcs     @r
        jmp     air_cell
@r:     rts

; ============================================================================
; the sprites: where each slot should be (des_*), and what changed is sent
; ============================================================================
set_sprites:
        ldx     #NSLOT-1
        lda     #0
@c:     sta     des_on,x
        dex
        bpl     @c
        lda     #1              ; Willy
        sta     des_on+SL_WILLY
        lda     w_anim
        lsr
        and     #3
        clc
        adc     #PIC_WILLY
        sta     des_n+SL_WILLY
        lda     w_x
        clc
        adc     #32
        sta     des_x+SL_WILLY
        lda     w_y
        clc
        adc     #32
        sta     des_y+SL_WILLY
        lda     w_face
        sta     des_f+SL_WILLY
        lda     #1              ; the portal: shut, or flashing when open
        sta     des_on+SL_PORTAL
        lda     #PIC_PORTAL
        ldx     keys_left
        bne     @ps
        lda     frame
        lsr
        lsr
        and     #1
        clc
        adc     #PIC_PORTAL + 1
@ps:    sta     des_n+SL_PORTAL
        lda     p_x
        clc
        adc     #32
        sta     des_x+SL_PORTAL
        lda     p_y
        clc
        adc     #32
        sta     des_y+SL_PORTAL
        lda     #0
        sta     des_f+SL_PORTAL
        ldx     ng              ; the guardians
        dex
        bmi     @r
@g:     lda     #1
        sta     des_on+SL_GUARD,x
        ldy     g_kind,x
        lda     g_axis,x        ; its frame from where it is
        bne     @gv
        lda     g_x,x
        jmp     @gf
@gv:    lda     g_y,x
@gf:    lsr
        lsr
        and     #1
        clc
        adc     guard_pic,y
        sta     des_n+SL_GUARD,x
        lda     g_x,x
        clc
        adc     #32
        sta     des_x+SL_GUARD,x
        lda     g_y,x
        clc
        adc     #32
        sta     des_y+SL_GUARD,x
        lda     #0              ; facing the way it goes (across)
        ldy     g_axis,x
        bne     @gs
        ldy     g_dir,x
        bpl     @gs
        lda     #1
@gs:    sta     des_f+SL_GUARD,x
        dex
        bpl     @g
@r:     rts

; ============================================================================
; the status line, the score
; ============================================================================
hud_update:
        lda     hud_dirty
        bne     @go
        rts
@go:    lda     #0
        sta     hud_dirty
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        lda     #<hi2_txt
        ldy     #>hi2_txt
        jsr     print
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jsr     prbcd
        lda     #<lives_txt
        ldy     #>lives_txt
        jsr     print
        lda     lives
        ora     #'0'
        jsr     putc
        lda     #<room_txt
        ldy     #>room_txt
        jsr     print
        lda     room
        clc
        adc     #1
        jmp     prdec2

; add A (BCD, low) / Y (BCD, high) to the score.  Every 10000: a life.
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
        lda     score+2         ; the 10000s changed: a life
        cmp     tmp
        beq     @n
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
        sta     in_d
        sta     in_j
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
        lda     #$FF
        sta     in_d
@r:     lda     pad
        and     #PAD_RIGHT
        beq     @a
        lda     #1
        sta     in_d
@a:     lda     pad             ; jump: A, B or up, held
        and     #PAD_A | PAD_B | PAD_UP
        beq     @st
        lda     #1
        sta     in_j
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
        beq     @jh
        dec     mv_hold
        lda     mv_dir
        sta     in_d
@jh:    lda     jhold
        beq     @done
        dec     jhold
        lda     #1
        sta     in_j
@done:  rts
HOLD_MOVE       = 4
HOLD_JUMP       = 2

handle_key:
        ldx     esc_st          ; arrow keys: ESC [ A / C / D
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
        beq     @jump
        cmp     #'C'
        beq     @right
        cmp     #'D'
        beq     @left
        rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    cmp     #KEY_LEFT       ; the AVR keyboard's arrows
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
        cmp     #KEY_UP
        beq     @jump
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
        beq     @jump
        cmp     #'W'
        beq     @jump
        cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@left:  lda     #$FF
        bne     @mv
@right: lda     #1
@mv:    sta     mv_dir
        sta     in_d
        lda     #HOLD_MOVE
        sta     mv_hold
        rts
@jump:  lda     #1
        sta     in_j
        lda     #HOLD_JUMP
        sta     jhold
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
; data
; ============================================================================
        .segment "RODATA"
rowoff_lo:
        .repeat ROWS, K
        .byte   <(K * COLS)
        .endrepeat
rowoff_hi:
        .repeat ROWS, K
        .byte   >(K * COLS)
        .endrepeat
NTSPR           = 7             ; the title's sprites
tspr_n: .byte   PIC_WILLY, PIC_ROBOT, PIC_BIRD, PIC_BLOB, PIC_SPIN, PIC_SKULL, PIC_JELLY
tspr_x: .byte   32 + 40, 32 + 54, 32 + 66, 32 + 78, 32 + 90, 32 + 102, 32 + 114

need_txt:
        .byte   13, 10, "MINER MOS NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
cls_txt:.byte   TC_CLS, TERM
title_txt:
        .byte   TC_ROW, 1, TC_COL, 9, RV_ON, "  MINER  MOS  ", RV_OFF
        .byte   TC_ROW, 3, TC_COL, 1, "MOS THE MINER IS DEEP IN THE"
        .byte   TC_ROW, 4, TC_COL, 1, "6502, AND HIS AIR IS RUNNING"
        .byte   TC_ROW, 5, TC_COL, 1, "OUT. TAKE EVERY KEY IN A ROOM,"
        .byte   TC_ROW, 6, TC_COL, 1, "THEN GET TO THE PORTAL. KEEP"
        .byte   TC_ROW, 7, TC_COL, 1, "CLEAR OF THE GUARDIANS AND THE"
        .byte   TC_ROW, 8, TC_COL, 1, "SPIKES, AND DON'T FALL TOO FAR."
        .byte   TC_ROW, 9, TC_COL, 1, "CRUMBLING FLOORS GIVE WAY, AND"
        .byte   TC_ROW, 10, TC_COL, 1, "CONVEYORS TAKE YOU THEIR WAY.", TERM
hi_txt: .byte   "HIGH SCORE ", TERM
name_txt:
        .byte   TC_ROW, NAME_ROW, TC_COL, 0, RV_ON, TERM
rvoff_txt:
        .byte   RV_OFF, TERM
air_txt:.byte   TC_ROW, AIR_ROW, TC_COL, 0, "AIR ", TERM
status_txt:
        .byte   TC_ROW, 23, TC_COL, 0, "SCORE ", TERM
hi2_txt:.byte   " HI ", TERM
lives_txt:
        .byte   " L", TERM
room_txt:
        .byte   " RM", TERM
allclear_txt:
        .byte   TC_CLS
        .byte   TC_ROW, 10, TC_COL, 6, "EVERY ROOM CLEARED."
        .byte   TC_ROW, 12, TC_COL, 9, "ROUND AGAIN!", TERM
paused_txt:
        .byte   TC_ROW, 22, TC_COL, 12, RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   TC_ROW, 22, TC_COL, 12, "        ", TERM
over_txt:
        .byte   TC_ROW, 7, TC_COL, 7, RV_ON, "                  "
        .byte   TC_ROW, 8, TC_COL, 7, "    GAME  OVER    "
        .byte   TC_ROW, 9, TC_COL, 7, "                  "
        .byte   TC_ROW, 10, TC_COL, 7, " SPACE/A: AGAIN   "
        .byte   TC_ROW, 11, TC_COL, 7, " Q: TITLE         "
        .byte   TC_ROW, 12, TC_COL, 7, "                  ", RV_OFF, TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD (G: KEYBOARD)", TERM
start_txt:
        .byte   TC_ROW, 22, TC_COL, 0, "SPACE OR START: PLAY  M: SOUND"
        .byte   TC_ROW, 23, TC_COL, 0, "Q: QUIT", TERM

; the display: R0-R7 (Graphics II: patterns $0000, colours $2000, names
; $3800, sprite attributes $3B00, sprite patterns $1800; display off; black)
vdp_regs:
        .byte   $02, $82, V_NAME / $400, $FF, $03, V_SATTR / $80, V_SPAT / $800, $01

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
room:       .res 1
hud_dirty:  .res 1
in_d:       .res 1              ; this frame's controls: -1 / 0 / 1
in_j:       .res 1              ;   jump
mv_dir:     .res 1
mv_hold:    .res 1
jhold:      .res 1
rp_on:      .res 1              ; IDENTIFY sent: S P 1 are its answer
rp_got:     .res 1              ; ... and it came
rp_t:       .res 1
air:        .res 1              ; units of air left
air_t:      .res 1
keys_left:  .res 1
p_x:        .res 1              ; the portal
p_y:        .res 1
w_x:        .res 1              ; Willy: his top left
w_y:        .res 1
w_mode:     .res 1              ;   ST_*
w_jt:       .res 1              ;   frames into a jump
w_jdx:      .res 1              ;   a jump's way across
w_ytop:     .res 1              ;   the highest he has been since he stood
w_face:     .res 1              ;   1: left
w_anim:     .res 1
w_crt:      .res 1              ;   frames on a crumbling floor
w_dead:     .res 1
w_d:        .res 1
w_j:        .res 1
w_dy:       .res 1
ng:         .res 1              ; the guardians
g_kind:     .res MAXG
g_axis:     .res MAXG
g_x:        .res MAXG
g_y:        .res MAXG
g_lo:       .res MAXG
g_hi:       .res MAXG
g_slow:     .res MAXG
g_dir:      .res MAXG
g_t:        .res MAXG
des_on:     .res NSLOT          ; the slots as they should be ...
des_n:      .res NSLOT
des_x:      .res NSLOT
des_y:      .res NSLOT
des_f:      .res NSLOT
sl_on:      .res NSLOT          ; ... and as the terminal shows them
sl_n:       .res NSLOT
sl_x:       .res NSLOT
sl_y:       .res NSLOT
sl_f:       .res NSLOT
hs_i:       .res 1
; the display
rv:         .res 1
cur_col:    .res 1
cur_row:    .res 1
pu_x:       .res 1
pu_y:       .res 1
pu_hi:      .res 1
t_col:      .res 1
t_row:      .res 1
t_ca:       .res 2
prow:       .res 1
pgrp:       .res 1
grp:        .res 8
dg_k:       .res 1
dg_t:       .res 1
dg_b0:      .res 4
dg_b1:      .res 4
dg_b2:      .res 4
dg_c0:      .res 3              ; the three cells' inks
dg_c1       = dg_c0 + 1
dg_c2       = dg_c0 + 2
tg_c:       .res 4
tcol:       .res 10             ; each kind of tile's colour (this room)
spr_ver:    .res 16             ; the picture version in each sprite's pattern
sp_k:       .res 1
sp_src:     .res 2
last_tick:  .res 1
src:        .res 2
tc:         .res 1              ; a tile: column, row, its address
tr:         .res 1
tile_adr:   .res 2
c0:         .res 1              ; Willy's first and last columns
c1:         .res 1
dr_r:       .res 1
rowbuf:     .res COLS * 2
map:        .res NTILE          ; the room's tiles
tmp:        .res 2
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
bss_end:
