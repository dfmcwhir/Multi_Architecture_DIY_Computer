; ============================================================================
; doom.s - "6502 DOOM": a small first person shooter for the 6502 SBC
;
; A raycasting engine (in the spirit of the 1993 game, nothing taken from
; it) that runs from the monitor at $0500 and draws on the PIC32 terminal in
; block graphics.  The engine loads one map at a time from the USB drive
; (E1M1.LVL, then the next one when you reach the exit) through the ROM's
; SBC_LOAD entry point.  On a ROM without SBC_LOAD it plays a built in copy
; of the first map.
;
;   build:  make     (runs gen_tables.py and mklevels.py when they change)
;   run:    L DOOM 0500   then   R           (needs terminal setup item J)
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  extra delay per frame in ms (default 0)
;   $0504  controls at start: 0 keyboard, 1 gamepad
;   $0505  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2, checked as the view is drawn): a bass line and effects,
; in doom_sound.inc (made by ../ay/tools/game_sounds.py).  Without the card
; the game is just silent.
;
; The view: 80 columns x 18 text rows of block graphics (160 x 72 pixels).
; A ray is cast for every other text column (each 2 pixels wide) and followed
; through the 32 x 32 tile map with a DDA; the columns between are averaged
; when their neighbours hit the same face of the same block, otherwise cast
; too.  The distance gives the wall height; the wall style, the side it hit
; and the distance give the shading pattern.
; Things (enemies, items) are scaled 8 x 8 bitmaps clipped against the wall
; distances.  The frame is built in RAM and only the characters that changed
; since the last frame are sent to the terminal.
;
; Angles are 0..1023 for a full turn (0 = east, 256 = south: y grows down).
;   memory: program and variables $0500-$4BFF, level $5000-$55FF, frame buffers $5600-$61FF
; Positions are 8.8 fixed point in tiles.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"
.ifndef SBC_LOAD
SBC_LOAD        = $FE15         ; load a file (see SBC_LOAD.md)
.endif

SPEED_DEFAULT   = 0

; ---- terminal --------------------------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
ATTR_TEXT       = $00
ATTR_RV         = $04
ATTR_GFX        = $80
TERM            = $FF

; ---- memory ----------------------------------------------------------------------
LEVEL_BUF       = $5000         ; the level file is loaded here
LEVEL_MAX       = $0600
MAP             = LEVEL_BUF + 64
THING_SRC       = LEVEL_BUF + 64 + 1024
FB              = $5600         ; the frame being built (18 x 80)
SB              = $5C00         ; what the terminal shows now

; ---- game --------------------------------------------------------------------------
MAXT            = 32            ; things per level
HUD_LINE        = 18
HUD_STATS       = 19
HUD_LEVEL       = 20
HUD_MSG         = 21
HUD_HELP        = 23
T_GRUNT         = 1
T_BRUTE         = 2
T_MEDKIT        = 3
T_AMMO          = 4
S_GONE          = 0             ; thing states
S_IDLE          = 1             ; (items use S_IDLE for "lying here")
S_CHASE         = 2
S_ATTACK        = 3
S_DEAD          = 4
TILE_DOOR       = 4
TILE_EXIT       = 5
RADIUS          = $40           ; the player's size, 1/4 tile

; ============================================================================
        .segment "RODATA"
        .include "tables.inc"     ; constants and lookup tables (gen_tables.py)
        .segment "CODE"

        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; music and effects on the AY-3-8910 card

putc:   jsr     sfx_poll        ; (the sound goes on while drawing)
        jmp     SBC_CHROUT      ; preserves A, X, Y
getc            = SBC_CHRIN     ; carry set = key in A

; ----------------------------------------------------------------------------
; output helpers
; ----------------------------------------------------------------------------
putblk: cmp     #$20            ; block graphics pattern (00-1F, 7F need 1A)
        bcc     @lit
        cmp     #$7F
        bne     @out
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@out:   jmp     putc

; cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
setcol: lda     #TC_COL         ; (column X only)
        jsr     putc
        txa
        jmp     putc

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

; print the string at A (lo) / Y (hi), terminated by $FF (any length)
print:  sta     @ld+1
        sty     @ld+2
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

; print a zero terminated string at A / Y (names in the level file)
print0: sta     @ld+1
        sty     @ld+2
        ldy     #0
@ld:    lda     $FFFF,y
        beq     @done
        jsr     putc
        iny
        bne     @ld
@done:  rts

; print A (0-255) in decimal, 3 characters, leading spaces.  pr_dec2: 2 digits
pr_dec3:ldx     #' '
        stx     lead
        ldx     #0
@h:     cmp     #100
        bcc     @hd
        sbc     #100
        inx
        bne     @h
@hd:    pha
        txa
        beq     @hs
        ora     #'0'
        sta     lead
        jsr     putc
        jmp     @t
@hs:    lda     #' '
        jsr     putc
@t:     pla
pr_dec2:ldx     #0
@l:     cmp     #10
        bcc     @d
        sbc     #10
        inx
        bne     @l
@d:     pha
        txa
        ora     #'0'
        jsr     putc
        pla
        ora     #'0'
        jmp     putc

; print A as 2 hex digits
pr_hex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     @dig
        pla
        and     #$0F
@dig:   cmp     #10
        bcc     @n
        adc     #6
@n:     adc     #'0'
        jmp     putc

; wait about A ms.  The inner loop is sized for the clock (CLOCK_MHZ in
; sbc_api.inc): 5 + 4 * (CLOCK_MHZ - 1) cycles a turn, DELAY_N turns a ms.
DELAY_N = (1000 * CLOCK_MHZ - 7) / (5 + 4 * (CLOCK_MHZ - 1))
delay_ms:
        tax
        beq     @done
@o:     jsr     sfx_poll        ; (and while waiting)
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
        jsr     rand
        jsr     sfx_poll
.endmacro
CTRL_COL        = 19
CTRL_ROW        = 17
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
; maths
; ============================================================================

; m_lo/m_hi = A * Y (unsigned 8 x 8), with quarter squares:
; a*b = f(a+b) - f(a-b), f(n) = n*n/4.  Changes X.
mul8:   sta     m_a
        sty     m_b
        clc
        adc     m_b
        tax
        bcs     @big
        lda     sq_lo,x
        sta     m_lo
        lda     sq_hi,x
        sta     m_hi
        jmp     @diff
@big:   lda     sq2_lo,x
        sta     m_lo
        lda     sq2_hi,x
        sta     m_hi
@diff:  lda     m_a
        sec
        sbc     m_b
        bcs     @pos
        eor     #$FF
        adc     #1              ; (carry is clear)
@pos:   tax
        lda     m_lo
        sec
        sbc     sq_lo,x
        sta     m_lo
        lda     m_hi
        sbc     sq_hi,x
        sta     m_hi
        rts

; r_lo/r_hi = (A * w) >> 8, w = w_lo/w_hi unsigned 16 bit.
; Two quarter-square products: a*b = sq(a+b) - sq(a-b), sq(n) = n*n/4
; (sq2 is the table for sums of 256 and more).
mul8x16:sta     mf
        sec                     ; low product: only its high byte is needed
        sbc     w_lo
        bcs     @d1
        eor     #$FF
        adc     #1
@d1:    tay                     ; |f - w_lo|
        lda     mf
        clc
        adc     w_lo
        tax                     ; f + w_lo
        bcs     @b1
        sec
        lda     sq_lo,x
        sbc     sq_lo,y
        lda     sq_hi,x
        sbc     sq_hi,y
        sta     r_lo
        jmp     @p2
@b1:    sec
        lda     sq2_lo,x
        sbc     sq_lo,y
        lda     sq2_hi,x
        sbc     sq_hi,y
        sta     r_lo
@p2:    lda     mf              ; high product, added in
        sec
        sbc     w_hi
        bcs     @d2
        eor     #$FF
        adc     #1
@d2:    tay
        lda     mf
        clc
        adc     w_hi
        tax
        bcs     @b2
        sec
        lda     sq_lo,x
        sbc     sq_lo,y
        sta     tmp
        lda     sq_hi,x
        sbc     sq_hi,y
        jmp     @add
@b2:    sec
        lda     sq2_lo,x
        sbc     sq_lo,y
        sta     tmp
        lda     sq2_hi,x
        sbc     sq_hi,y
@add:   sta     r_hi
        lda     tmp
        clc
        adc     r_lo
        sta     r_lo
        bcc     @r
        inc     r_hi
@r:     rts

; r = w * A / 128: A signed s.7 (a sine), w signed 8.8.  Changes w.
smul:   sta     sm_s
        eor     w_hi
        sta     sm_sign
        lda     sm_s
        bpl     @a
        eor     #$FF
        clc
        adc     #1
@a:     sta     sm_a
        lda     w_hi
        bpl     @w
        lda     #0
        sec
        sbc     w_lo
        sta     w_lo
        lda     #0
        sbc     w_hi
        sta     w_hi
@w:     lda     sm_a
        jsr     mul8x16
        asl     r_lo
        rol     r_hi
        lda     sm_sign
        bpl     @r
        lda     #0
        sec
        sbc     r_lo
        sta     r_lo
        lda     #0
        sbc     r_hi
        sta     r_hi
@r:     rts

; n0..n2 = n0..n2 / d0..d1 (unsigned 24 / 16 bit)
udiv24: lda     #0
        sta     rm0
        sta     rm1
        ldx     #24
@l:     asl     n0
        rol     n1
        rol     n2
        rol     rm0
        rol     rm1
        lda     rm0
        sec
        sbc     d0
        tay
        lda     rm1
        sbc     d1
        bcc     @s
        sta     rm1
        sty     rm0
        inc     n0
@s:     dex
        bne     @l
        rts

; A = sin(angle a_lo / a_hi), signed s.7.  get_cos: cos of the same angle
get_cos:lda     a_hi
        clc
        adc     #1
        and     #3
        jmp     sin_hi
get_sin:lda     a_hi
        and     #3
sin_hi: clc
        adc     #>sin_tab
        sta     @rd+2
        lda     #<sin_tab
        clc
        adc     a_lo
        sta     @rd+1
        bcc     @rd
        inc     @rd+2
@rd:    lda     $FFFF
        rts

; tile at X, Y (0..31) -> A.  Outside the map counts as wall.  Preserves X, Y.
tile_at:cpx     #32
        bcs     @wall
        cpy     #32
        bcs     @wall
        txa
        clc
        adc     maprow_lo,y
        sta     @rd+1
        lda     maprow_hi,y
        adc     #0
        sta     @rd+2
@rd:    lda     $FFFF
        rts
@wall:  lda     #1
        rts

; set the tile at X, Y to A
tile_set:
        inc     mapver          ; (the view must be drawn again)
        pha
        txa
        clc
        adc     maprow_lo,y
        sta     @wr+1
        lda     maprow_hi,y
        adc     #0
        sta     @wr+2
        pla
@wr:    sta     $FFFF
        rts

; ============================================================================
; the renderer
; ============================================================================

; cast one ray per column and draw the walls into FB
render_view:
        lda     #0
        sta     zmax
        ldy     py_hi           ; map address of the player's tile
        lda     maprow_lo,y
        clc
        adc     px_hi
        sta     pbase_lo
        lda     maprow_hi,y
        adc     #0
        sta     pbase_hi
        ldx     #0              ; cast the even columns
@e:     stx     col
        jsr     sfx_poll        ; (the sound goes on while it draws)
        jsr     cast_ray
        ldx     col
        inx
        inx
        cpx     #COLS
        bcc     @e
        ldx     #1              ; odd columns: between two rays that hit the
@o:     stx     col             ; same face of the same block, just average
        cpx     #COLS-1
        beq     @cast
        lda     c_mplo-1,x
        cmp     c_mplo+1,x
        bne     @cast
        lda     c_mphi-1,x
        cmp     c_mphi+1,x
        bne     @cast
        lda     c_pidx-1,x
        cmp     c_pidx+1,x
        bne     @cast
        sta     c_pidx,x
        lda     c_mplo-1,x
        sta     c_mplo,x
        lda     c_mphi-1,x
        sta     c_mphi,x
        lda     c_hgt-1,x
        clc
        adc     c_hgt+1,x
        ror
        sta     c_hgt,x
        lda     zb_lo-1,x
        clc
        adc     zb_lo+1,x
        sta     tmp
        lda     zb_hi-1,x
        adc     zb_hi+1,x
        ror
        sta     zb_hi,x
        lda     tmp
        ror
        sta     zb_lo,x
        jmp     @on
@cast:  jsr     cast_ray
@on:    ldx     col
        inx
        inx
        cpx     #COLS+1
        bcc     @o
        lda     #$FF            ; draw them all
        sta     lastc_lo
        sta     lastc_hi
        ldx     #0
@d:     stx     col
        lda     c_hgt,x
        sta     hgt
        ldy     c_pidx,x
        lda     wallpat,y
        sta     pat
        ; a different block or face from the column before: an edge line
        lda     c_mplo,x
        cmp     lastc_lo
        bne     @edge
        lda     c_mphi,x
        cmp     lastc_hi
        bne     @edge
        tya
        eor     lastside
        and     #4
        beq     @noedge
@edge:  lda     pat
        and     #$AA            ; just the right hand pixels
        sta     pat
@noedge:lda     c_mplo,x
        sta     lastc_lo
        lda     c_mphi,x
        sta     lastc_hi
        sty     lastside
        jsr     draw_column
        ldx     col
        inx
        cpx     #COLS
        bcc     @d
        rts

; cast the ray for column col: z-buffer, height, pattern and block hit
cast_ray:
        ldx     col
        lda     pa_lo           ; the ray's angle
        clc
        adc     coloff_lo,x
        sta     ra_lo
        lda     pa_hi
        adc     coloff_hi,x
        and     #3
        sta     ra_hi
        ldy     ra_lo           ; |1/cos| and |1/sin| from the quarter table
        lda     invc_lo,y
        sta     ta_lo
        lda     invc_hi,y
        sta     ta_hi
        tya
        beq     @r0
        eor     #$FF
        clc
        adc     #1              ; 256 - r
        tay
        lda     invc_lo,y
        sta     tb_lo
        lda     invc_hi,y
        sta     tb_hi
        jmp     @rr
@r0:    lda     #$FF            ; 1/cos(90) = "infinite"
        sta     tb_lo
        lda     #$7F
        sta     tb_hi
@rr:    lda     ra_hi
        and     #1
        bne     @odd
        lda     ta_lo           ; quarters 0 and 2
        sta     dx_lo
        lda     ta_hi
        sta     dx_hi
        lda     tb_lo
        sta     dy_lo
        lda     tb_hi
        sta     dy_hi
        jmp     @sx
@odd:   lda     tb_lo           ; quarters 1 and 3
        sta     dx_lo
        lda     tb_hi
        sta     dx_hi
        lda     ta_lo
        sta     dy_lo
        lda     ta_hi
        sta     dy_hi
@sx:    lda     ra_hi           ; x goes up in quarters 0 and 3
        beq     @xp
        cmp     #3
        beq     @xp
        lda     px_lo
        sta     ff
        lda     #$FF
        sta     spx_lo
        sta     spx_hi
        jmp     @xd
@xp:    lda     px_lo
        eor     #$FF
        sta     ff
        lda     #1
        sta     spx_lo
        lda     #0
        sta     spx_hi
@xd:    lda     dx_lo           ; first x side = fraction * |1/cos|
        sta     w_lo
        lda     dx_hi
        sta     w_hi
        lda     ff
        jsr     mul8x16
        lda     r_lo
        sta     sx_lo
        lda     r_hi
        sta     sx_hi
        lda     ra_hi           ; y goes up (south) in quarters 0 and 1
        cmp     #2
        bcc     @yp
        lda     py_lo
        sta     ff
        lda     #$E0            ; -32
        sta     spy_lo
        lda     #$FF
        sta     spy_hi
        jmp     @yd
@yp:    lda     py_lo
        eor     #$FF
        sta     ff
        lda     #32
        sta     spy_lo
        lda     #0
        sta     spy_hi
@yd:    lda     dy_lo
        sta     w_lo
        lda     dy_hi
        sta     w_hi
        lda     ff
        jsr     mul8x16
        lda     r_lo
        sta     sy_lo
        lda     r_hi
        sta     sy_hi
        lda     pbase_lo
        sta     @rd+1
        lda     pbase_hi
        sta     @rd+2
@dda:   lda     sx_hi           ; step along whichever side is nearer
        cmp     sy_hi
        bcc     @xs
        bne     @ys
        lda     sx_lo
        cmp     sy_lo
        bcs     @ys
@xs:    lda     @rd+1           ; next block in x
        clc
        adc     spx_lo
        sta     @rd+1
        lda     @rd+2
        adc     spx_hi
        sta     @rd+2
        ldx     #0
        beq     @rd
@ys:    lda     @rd+1           ; next block in y
        clc
        adc     spy_lo
        sta     @rd+1
        lda     @rd+2
        adc     spy_hi
        sta     @rd+2
        ldx     #1
@rd:    lda     $FFFF           ; (address = the map cell being tested)
        bne     @hit            ; (the map always has walls round the edge)
        txa
        bne     @ay
        lda     sx_lo           ; the next x side
        clc
        adc     dx_lo
        sta     sx_lo
        lda     sx_hi
        adc     dx_hi
        sta     sx_hi
        bcc     @dda
        lda     #$FF
        sta     sx_lo
        sta     sx_hi
        bne     @dda
@ay:    lda     sy_lo           ; the next y side
        clc
        adc     dy_lo
        sta     sy_lo
        lda     sy_hi
        adc     dy_hi
        sta     sy_hi
        bcc     @dda
        lda     #$FF
        sta     sy_lo
        sta     sy_hi
        beq     *+5
        jmp     @dda
@hit:   stx     side
        and     #7
        sta     tile
        lda     sx_lo           ; distance to the side that was hit
        ldy     sx_hi
        cpx     #0
        beq     @dh
        lda     sy_lo
        ldy     sy_hi
@dh:    sta     dist_lo
        sty     dist_hi
        lda     @rd+1           ; the cell that was hit
        sta     mp_lo
        lda     @rd+2
        sta     mp_hi
        ; perpendicular distance = distance * cos(column offset)
        lda     dist_lo
        sta     w_lo
        lda     dist_hi
        sta     w_hi
        ldx     col
        lda     cosfix,x
        jsr     mul8x16
        ldx     col
        lda     r_lo
        sta     zb_lo,x
        lda     r_hi
        sta     zb_hi,x
        cmp     zmax            ; the farthest wall seen this frame
        bcc     @zm
        sta     zmax
@zm:    jsr     dist_index      ; -> idx, hgt
        ; shading band by distance
        lda     idx_hi
        bne     @b3
        lda     idx_lo
        cmp     #48
        bcc     @b0
        cmp     #112
        bcc     @b1
        cmp     #224
        bcc     @b2
@b3:    lda     #3
        bne     @bs
@b2:    lda     #2
        bne     @bs
@b1:    lda     #1
        bne     @bs
@b0:    lda     #0
@bs:    sta     band
        lda     tile            ; pattern = style * 8 + side * 4 + band
        asl
        asl
        asl
        ora     band
        ldx     side
        beq     @s0
        ora     #4
@s0:    ldx     col
        sta     c_pidx,x
        lda     hgt
        sta     c_hgt,x
        lda     mp_lo
        sta     c_mplo,x
        lda     mp_hi
        sta     c_mphi,x
        rts

; r_lo/r_hi = a distance (8.8 tiles) -> idx (distance in 1/32 tile, max 1023)
; and hgt = the height in pixels of a wall that far away
dist_index:
        lda     r_hi
        cmp     #32
        bcc     @ok
        lda     #$FF
        sta     idx_lo
        lda     #3
        sta     idx_hi
        jmp     @h
@ok:    lsr
        lsr
        lsr
        sta     idx_hi
        lda     r_hi
        asl
        asl
        asl
        asl
        asl
        sta     tmp
        lda     r_lo
        lsr
        lsr
        lsr
        ora     tmp
        sta     idx_lo
@h:     lda     #<htab
        clc
        adc     idx_lo
        sta     @rd+1
        lda     #>htab
        adc     idx_hi
        sta     @rd+2
@rd:    lda     $FFFF
        sta     hgt
        rts

; draw column col: ceiling (blank), wall (pat) from y0 to y1, floor below.
; Character rows r0 .. r1 hold the wall; the first and last may be partly
; wall and partly background: (pat & mask) | (floor & ~mask).
; The background goes in first (bg_chain), then the whole wall characters
; (a run of wall_chain, stopped by a temporary RTS), then the two ends.
draw_column:
        jsr     sfx_poll        ; (once a column)
        ldx     hgt             ; where the wall starts and ends (tables)
        lda     dc_r0,x
        sta     r0
        lda     dc_t0,x
        sta     t0
        lda     dc_r1,x
        sta     r1
        lda     dc_t1,x
        sta     t1
        ldy     col
        jsr     bg_chain        ; (keeps Y)
        ldx     r0              ; first whole wall character
        lda     t0
        beq     @f0
        inx
@f0:    cpx     r1
        bcs     @ends
        lda     wc_lo,x         ; run wall_chain from row X to row r1
        sta     @jp+1
        lda     wc_hi,x
        sta     @jp+2
        ldx     r1
        lda     wc_lo,x
        sta     @rt+1
        sta     @un+1
        lda     wc_hi,x
        sta     @rt+2
        sta     @un+2
        lda     #$60            ; RTS
@rt:    sta     $FFFF
        lda     pat
        jsr     @jp
        lda     #$99            ; STA abs,Y back again
@un:    sta     $FFFF
@ends:  ldx     r0              ; the top character, if it is partly wall
        cpx     r1
        beq     @last
        lda     t0
        beq     @last
        tay
        lda     mstart,y
        jsr     part
@last:  ldx     r1              ; the bottom one
        cpx     #VROWS
        bcs     @done
        ldy     t1
        lda     mend,y
        cpx     r0              ; ...that may also be the top one
        bne     @l1
        ldy     t0
        and     mstart,y
@l1:    jmp     part
@done:  rts
@jp:    jmp     $FFFF

; character row X of column col = (pat & A) | (background & ~A)
part:   sta     msk
        lda     fbrow_lo,x
        clc
        adc     col
        sta     @w+1
        lda     fbrow_hi,x
        adc     #0
        sta     @w+2
        lda     pat
        eor     floorpat,x
        and     msk
        eor     floorpat,x
@w:     sta     $FFFF
        rts

; the background of column Y
bg_chain:
.repeat VROWS, R
        lda     floorpat+R
        sta     FB + R * COLS,y
.endrepeat
        rts

; A into rows of column Y: enter at wall_chain + 3 * first row
wall_chain:
.repeat VROWS, R
        sta     FB + R * COLS,y
.endrepeat
        rts
; for a wall H pixels high: rows y0 = HORIZON - H/2 .. y1 = y0 + H (not included)
; r0 / t0 = character row and pixel row of y0, r1 / t1 the same for y1
dc_r0:
.repeat VH + 1, H
        .byte   (HORIZON - H / 2) / 4
.endrepeat
dc_t0:
.repeat VH + 1, H
        .byte   (HORIZON - H / 2) .mod 4
.endrepeat
dc_r1:
.repeat VH + 1, H
        .byte   (HORIZON - H / 2 + H) / 4
.endrepeat
dc_t1:
.repeat VH + 1, H
        .byte   (HORIZON - H / 2 + H) .mod 4
.endrepeat
wc_lo:
.repeat VROWS + 1, R
        .byte   <(wall_chain + 3 * R)
.endrepeat
wc_hi:
.repeat VROWS + 1, R
        .byte   >(wall_chain + 3 * R)
.endrepeat

; ---- things ------------------------------------------------------------------------
; project every thing that is in front of the player; nearest drawn last
render_things:
        lda     #0
        sta     nvis
        lda     pa_lo
        sta     a_lo
        lda     pa_hi
        sta     a_hi
        jsr     get_sin
        sta     psin
        jsr     get_cos
        sta     pcos
        ldx     #0
@t:     jsr     sfx_poll        ; (the sound goes on: once a thing)
        stx     ti
        lda     t_state,x
        bne     @go
        jmp     @next
@go:    lda     t_x_lo,x        ; dx, dy from the player
        sec
        sbc     px_lo
        sta     tdx_lo
        lda     t_x_hi,x
        sbc     px_hi
        sta     tdx_hi
        clc
        adc     #20
        cmp     #40
        bcc     *+5           ; too far
        jmp     @skip
        lda     t_y_lo,x
        sec
        sbc     py_lo
        sta     tdy_lo
        lda     t_y_hi,x
        sbc     py_hi
        sta     tdy_hi
        clc
        adc     #20
        cmp     #40
        bcc     *+5
        jmp     @skip
        ; depth = dx cos + dy sin
        jsr     wdx
        lda     pcos
        jsr     smul
        jsr     r2acc
        jsr     wdy
        lda     psin
        jsr     smul
        jsr     acc_add_r
        lda     acc_hi
        bpl     *+5           ; behind
        jmp     @skip
        bne     @front
        lda     acc_lo
        cmp     #$40
        bcs     *+5           ; too close
        jmp     @skip
@front: lda     acc_hi          ; beyond every wall in view?
        cmp     zmax
        beq     @fr
        bcc     @fr
        jmp     @skip
@fr:    lda     acc_lo
        sta     dep_lo
        lda     acc_hi
        sta     dep_hi
        ; lateral = dy cos - dx sin
        jsr     wdy
        lda     pcos
        jsr     smul
        jsr     r2acc
        jsr     wdx
        lda     psin
        jsr     smul
        jsr     acc_sub_r
        ; |lateral| < 2 * depth, or it is well off the screen
        lda     acc_hi
        sta     lat_sign
        bpl     @lp
        lda     #0
        sec
        sbc     acc_lo
        sta     acc_lo
        lda     #0
        sbc     acc_hi
        sta     acc_hi
@lp:    lda     dep_lo
        asl
        sta     tmp
        lda     dep_hi
        rol
        cmp     acc_hi
        bcs     *+5
        jmp     @skip
        bne     @in
        lda     tmp
        cmp     acc_lo
        bcs     *+5
        jmp     @skip
@in:    ; column offset = |lateral| * FOCAL / depth
        lda     acc_lo
        sta     w_lo
        lda     acc_hi
        sta     w_hi
        lda     #FOCAL
        jsr     mul8x16_full    ; n0..n2 = FOCAL * |lateral|
        lda     dep_lo
        sta     d0
        lda     dep_hi
        sta     d1
        jsr     udiv24
        lda     n1
        bne     @skip
        lda     n0
        cmp     #120
        bcs     @skip
        ldx     nvis            ; record it
        ldy     ti
        tya
        sta     v_t,x
        lda     lat_sign
        bmi     @left
        lda     #40
        clc
        adc     n0
        sta     v_sx_lo,x
        lda     #0
        adc     #0
        sta     v_sx_hi,x
        jmp     @dep
@left:  lda     #40
        sec
        sbc     n0
        sta     v_sx_lo,x
        lda     #0
        sbc     #0
        sta     v_sx_hi,x
@dep:   lda     dep_lo
        sta     v_d_lo,x
        sta     r_lo
        lda     dep_hi
        sta     v_d_hi,x
        sta     r_hi
        jsr     dist_index
        ldx     nvis
        lda     hgt
        sta     v_h,x
        inc     nvis
        jmp     @next
@skip:
@next:  ldx     ti
        inx
        cpx     #MAXT
        beq     @sort
        jmp     @t
@sort:  ; sort far to near (insertion sort on depth)
        ldx     #1
@s1:    cpx     nvis
        bcs     @draw
        stx     sj
@s2:    lda     v_d_hi-1,x      ; the one before nearer than this one? swap
        cmp     v_d_hi,x
        bcc     @swap
        bne     @s3
        lda     v_d_lo-1,x
        cmp     v_d_lo,x
        bcs     @s3
@swap:  jsr     swap_vis        ; (keeps X)
        dex
        bne     @s2
@s3:    ldx     sj
        inx
        jmp     @s1
@draw:  ldx     #0
@d:     cpx     nvis
        bcs     @done
        stx     vi
        jsr     draw_thing
        ldx     vi
        inx
        jmp     @d
@done:  rts

; swap visible entries X-1 and X
swap_vis:
        .repeat 6, K
        lda     v_t + K*MAXT - 1,x
        pha
        lda     v_t + K*MAXT,x
        sta     v_t + K*MAXT - 1,x
        pla
        sta     v_t + K*MAXT,x
        .endrepeat
        rts

wdx:    lda     tdx_lo
        sta     w_lo
        lda     tdx_hi
        sta     w_hi
        rts
wdy:    lda     tdy_lo
        sta     w_lo
        lda     tdy_hi
        sta     w_hi
        rts
r2acc:  lda     r_lo
        sta     acc_lo
        lda     r_hi
        sta     acc_hi
        rts
acc_add_r:
        lda     acc_lo
        clc
        adc     r_lo
        sta     acc_lo
        lda     acc_hi
        adc     r_hi
        sta     acc_hi
        rts
acc_sub_r:
        lda     acc_lo
        sec
        sbc     r_lo
        sta     acc_lo
        lda     acc_hi
        sbc     r_hi
        sta     acc_hi
        rts

; n0..n2 = A * w (unsigned 8 x 16, full 24 bit result)
mul8x16_full:
        sta     mf
        ldy     w_lo
        jsr     mul8
        lda     m_lo
        sta     n0
        lda     m_hi
        sta     n1
        lda     mf
        ldy     w_hi
        jsr     mul8
        lda     m_lo
        clc
        adc     n1
        sta     n1
        lda     m_hi
        adc     #0
        sta     n2
        rts

; the sprite for thing X -> A
thing_sprite:
        lda     t_state,x
        cmp     #S_DEAD
        bne     @1
        lda     #SPR_DEAD
        rts
@1:     lda     t_type,x
        cmp     #T_MEDKIT
        bne     @2
        lda     #SPR_MEDKIT
        rts
@2:     cmp     #T_AMMO
        bne     @3
        lda     #SPR_AMMO
        rts
@3:     ldy     #SPR_GRUNT1
        cmp     #T_GRUNT
        beq     @4
        ldy     #SPR_BRUTE1
@4:     sty     tmp
        lda     t_state,x
        cmp     #S_ATTACK
        bne     @5
        lda     tmp
        clc
        adc     #2              ; firing frame
        rts
@5:     lda     t_anim,x
        and     #1
        clc
        adc     tmp
        rts

; draw visible thing vi into FB
draw_thing:
        jsr     sfx_poll
        ldx     vi
        lda     v_h,x
        cmp     #2
        bcs     @big
        rts
@big:   sta     sh
        lda     v_d_lo,x
        sta     sdep_lo
        lda     v_d_hi,x
        sta     sdep_hi
        ldy     v_t,x
        sty     ti
        tya
        tax
        jsr     thing_sprite    ; texture address -> self-modifying reads
        asl
        asl
        asl
        asl                     ; * 16
        clc
        adc     #<spr_data
        sta     spr_mk+1
        lda     #>spr_data
        adc     #0
        sta     spr_mk+2
        lda     spr_mk+1
        clc
        adc     #8
        sta     spr_fl+1
        lda     spr_mk+2
        adc     #0
        sta     spr_fl+2
        ldx     ti              ; items are half size, lying on the floor
        lda     t_type,x
        cmp     #T_MEDKIT
        bcc     @ns
        lda     sh
        lsr
        cmp     #2
        bcs     @half
        rts
@half:  sta     sh
        lda     #1
        sta     item
        bne     @st
@ns:    lda     #0
        sta     item
@st:    ldy     sh              ; texels per pixel (8.8)
        lda     rec_lo,y
        sta     st_lo
        lda     rec_hi,y
        sta     st_hi
        lda     item            ; an item: from the horizon down
        beq     @y0
        lda     #HORIZON
        sta     y0
        bne     @y0d
@y0:    lda     sh              ; rows y0 .. y1-1
        lsr
        sta     tmp
        lda     #HORIZON
        sec
        sbc     tmp
        sta     y0
@y0d:
        clc
        adc     sh
        cmp     #VH+1
        bcc     @y1
        lda     #VH
@y1:    sta     y1
        ldx     #0              ; texel row of every pixel row
        lda     #0
        sta     acc_lo
        sta     acc_hi
@vr:    cpx     y0
        bcc     @vno
        cpx     y1
        bcs     @vno
        lda     acc_hi
        cmp     #8
        bcc     @vok
        lda     #7
@vok:   sta     vtab,x
        lda     acc_lo
        clc
        adc     st_lo
        sta     acc_lo
        lda     acc_hi
        adc     st_hi
        sta     acc_hi
        jmp     @vn
@vno:   lda     #$FF
        sta     vtab,x
@vn:    inx
        cpx     #VH
        bne     @vr
        ; pixel columns x0 = 2*sx - sh/2 .. x0 + sh - 1 (16 bit, signed)
        ldx     vi
        lda     v_sx_lo,x
        asl
        sta     x0_lo
        lda     v_sx_hi,x
        rol
        sta     x0_hi
        lda     sh
        lsr
        sta     tmp
        lda     x0_lo
        sec
        sbc     tmp
        sta     x0_lo
        lda     x0_hi
        sbc     #0
        sta     x0_hi
        ; for each text column c that the sprite covers: from x0 / 2
        lda     #0
        ldx     x0_hi
        bmi     @c0             ; starts off the left edge
        beq     *+5           ; (can't happen: x0 < 256 when sx < 120)
        jmp     @past
        lda     x0_lo
        lsr
        cmp     #COLS
        bcc     *+5
        jmp     @past
@c0:    sta     cc
@cl:    ldx     cc              ; behind a wall in this column?
        lda     sdep_hi
        cmp     zb_hi,x
        bcc     @vis
        bne     @ncol
        lda     sdep_lo
        cmp     zb_lo,x
        bcs     @ncol
@vis:   ; left pixel p = 2c: u = (p - x0) if 0 <= p - x0 < sh
        lda     cc
        asl
        sec
        sbc     x0_lo
        sta     tmp
        lda     #0
        sbc     x0_hi
        bne     @lout           ; negative
        lda     tmp
        cmp     sh
        bcs     @past           ; to the right of the sprite: done
        jsr     tex_u
        sta     bu0
        jmp     @r1
@lout:  lda     #0
        sta     bu0
@r1:    lda     cc              ; right pixel 2c+1
        asl
        sec
        adc     #0              ; +1 (carry set)
        sec
        sbc     x0_lo
        sta     tmp
        lda     #0
        sbc     x0_hi
        bne     @rout
        lda     tmp
        cmp     sh
        bcs     @rout
        jsr     tex_u
        sta     bu1
        jmp     @both
@rout:  lda     #0
        sta     bu1
@both:  lda     bu0
        ora     bu1
        beq     @ncol
        jsr     sprite_column
@ncol:  inc     cc
        lda     cc
        cmp     #COLS
        bcc     @cl
@past:  rts

; A = pixel offset into the sprite (0..sh-1) -> bit mask of its texel column
tex_u:  sta     w_lo            ; u = offset * step >> 8
        lda     #0
        sta     w_hi
        lda     st_hi           ; step < 256 for sh > 8; handle both bytes
        beq     @small
        lda     w_lo            ; offset * st_hi + (offset * st_lo) >> 8
        ldy     st_hi
        jsr     mul8
        lda     m_lo
        sta     tmp2
        lda     w_lo
        ldy     st_lo
        jsr     mul8
        lda     m_hi
        clc
        adc     tmp2
        jmp     @u
@small: lda     w_lo
        ldy     st_lo
        jsr     mul8
        lda     m_hi
@u:     cmp     #8
        bcc     @ok
        lda     #7
@ok:    tay
        lda     bitmask,y
        rts

; draw the sprite's cells in column cc (bu0, bu1 = texel bits for its pixels)
sprite_column:
        jsr     sfx_poll
        lda     y0
        lsr
        lsr
        sta     rr
sc_row:   lda     rr
        asl
        asl
        sta     lo4
        lda     #0
        sta     cm
        sta     cf
        ldy     #0              ; 4 pixel rows
sc_k:     sty     kk
        tya
        clc
        adc     lo4
        tax
        lda     vtab,x
        bmi     sc_kn
        tax                     ; texel row
spr_mk = *
        lda     $FFFF,x         ; shape
        sta     tm
spr_fl = *
        lda     $FFFF,x         ; fill
        sta     tf
        ldy     kk
        lda     tm
        and     bu0
        beq     sc_l0
        lda     cm
        ora     rowbit_l,y
        sta     cm
        lda     tf
        and     bu0
        beq     sc_l0
        lda     cf
        ora     rowbit_l,y
        sta     cf
sc_l0:    lda     tm
        and     bu1
        beq     sc_kn2
        lda     cm
        ora     rowbit_r,y
        sta     cm
        lda     tf
        and     bu1
        beq     sc_kn2
        lda     cf
        ora     rowbit_r,y
        sta     cf
sc_kn2:   ldy     kk
sc_kn:    iny
        cpy     #4
        bne     sc_k
        lda     cm              ; anything to draw in this character?
        beq     sc_rn
        ldx     rr
        lda     fbrow_lo,x
        clc
        adc     cc
        sta     sc_rd+1
        sta     sc_wr+1
        lda     fbrow_hi,x
        adc     #0
        sta     sc_rd+2
        sta     sc_wr+2
        lda     cm
        eor     #$FF
sc_rd:    and     $FFFF
        sta     tmp
        lda     cf
        and     cm
        ora     tmp
sc_wr:    sta     $FFFF
sc_rn:    inc     rr
        lda     rr
        asl
        asl
        cmp     y1
        bcs     sc_done
        lda     rr
        cmp     #VROWS
        bcs     *+5
        jmp     sc_row
sc_done:  rts

; the gun at the bottom of the view
draw_gun:
        jsr     sfx_poll
        lda     gun_t
        beq     @g0
        dec     gun_t
        lda     #<gun1_mask
        sta     @m+1
        lda     #>gun1_mask
        sta     @m+2
        lda     #<gun1_fill
        sta     @f+1
        lda     #>gun1_fill
        sta     @f+2
        jmp     @go
@g0:    lda     #<gun0_mask
        sta     @m+1
        lda     #>gun0_mask
        sta     @m+2
        lda     #<gun0_fill
        sta     @f+1
        lda     #>gun0_fill
        sta     @f+2
@go:    ldx     #0
@l:     txa                     ; FB + (14 + i/8) * 80 + 36 + i%8
        lsr
        lsr
        lsr
        tay
        lda     gunrow_lo,y
        sta     @rd+1
        sta     @wr+1
        lda     gunrow_hi,y
        sta     @rd+2
        sta     @wr+2
        txa
        and     #7
        tay
@m:     lda     $FFFF,x
        eor     #$FF
@rd:    and     $FFFF,y
        sta     tmp
@f:     lda     $FFFF,x
        ora     tmp
@wr:    sta     $FFFF,y
        inx
        cpx     #32
        bne     @l
        rts

; ---- sending the frame -------------------------------------------------------------
; compare FB with SB and send only what changed
present:
        lda     attr            ; block graphics on; the repeat count it has
        cmp     #$FF
        beq     @gm
        tax
        bmi     @g
@gm:    jsr     gfx_mode
@g:     lda     attr
        and     #$78
        lsr
        lsr
        lsr
        bne     @rp
        lda     #1
@rp:    sta     cur_rep
        lda     #$FF
        sta     cur_r
        lda     #0
        sta     prow
@row:   jsr     sfx_poll        ; (once a row)
        ldx     prow
        lda     fbrow_lo,x
        sta     @fb+1
        sta     @f2+1
        lda     fbrow_hi,x
        sta     @fb+2
        sta     @f2+2
        lda     sbrow_lo,x
        sta     @sb+1
        sta     @s2+1
        sta     @sw+1
        sta     @rs+1
        lda     sbrow_hi,x
        sta     @sb+2
        sta     @s2+2
        sta     @sw+2
        sta     @rs+2
        ldx     #0
@c:
@fb:    lda     $FFFF,x         ; the same as the terminal shows?
@sb:    cmp     $FFFF,x
        bne     @diff
        inx
        cpx     #COLS
        bne     @c
        jmp     @nrow
@diff:  sta     val
        stx     pcol
        ; the run of cells with this value from here (at most 15), and how
        ; far into it the last changed one is
        lda     #1
        sta     need
        txa
        tay
        iny
@rl:    cpy     #COLS
        bcs     @rend
        tya
        sec
        sbc     pcol
        cmp     #15
        bcs     @rend
        sta     tmp
@f2:    lda     $FFFF,y
        cmp     val
        bne     @rend
@s2:    cmp     $FFFF,y         ; (A = val) unchanged there?
        beq     @rs1
        ldx     tmp
        inx
        stx     need
@rs1:   iny
        bne     @rl
@rend:  tya
        sec
        sbc     pcol
        sta     runl
        ; how many to draw: the repeat count already set if it covers the
        ; changes and stays in the run; otherwise single cells for short
        ; changes, or the whole run
        lda     cur_rep
        cmp     need
        bcc     @nofit
        cmp     runl
        beq     @setk
        bcc     @setk
@nofit: lda     need
        cmp     #1
        beq     @setk
        cmp     #4
        bcs     @whole
        lda     cur_rep
        cmp     #1
        beq     @setk
@whole: lda     runl
@setk:  sta     kcnt
        ; put the cursor there
        lda     cur_r
        cmp     prow
        bne     @goto
        lda     pcol
        sec
        sbc     cur_c
        beq     @put            ; right here
        bcc     @col            ; behind us: set the column
        cmp     #3
        bcs     @col
        ldx     cur_rep         ; a cell or two on: resend them (repeat off)
        cpx     #1
        bne     @col
        ldy     cur_c
@rs:    lda     $FFFF,y
        jsr     putblk
        iny
        cpy     pcol
        bne     @rs
        jmp     @put
@col:   ldx     pcol
        jsr     setcol
        jmp     @put
@goto:  ldx     pcol
        ldy     prow
        jsr     gotoxy
        lda     prow
        sta     cur_r
@put:   lda     kcnt
        jsr     set_rep
        lda     val
        jsr     putblk
        ldx     pcol            ; the terminal now shows them
        ldy     kcnt
        lda     val
@sw:    sta     $FFFF,x
        inx
        dey
        bne     @sw
        stx     cur_c
        cpx     #COLS
        bcs     @end
        jmp     @c
@end:   lda     #$FF            ; the cursor wrapped: position unknown
        sta     cur_r
@nrow:  inc     prow
        lda     prow
        cmp     #VROWS
        beq     @done
        jmp     @row
@done:  rts

; repeat each character A times from now on (1..15; block graphics on)
set_rep:cmp     cur_rep
        beq     @r
        sta     cur_rep
        cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        jmp     setattr
@one:   lda     #ATTR_GFX
        jmp     setattr
@r:     rts

; forget what the terminal shows (after clearing the screen)
; a frame that drew nothing: wait about as long as drawing would have taken,
; so the enemies keep their pace, but stop early (after 60 ms) for a key or a
; change on the gamepad.  A key read here is kept for read_input.
idle_wait:
        lda     #150
        sta     iw_n
@l:     lda     iw_n
        cmp     #150 - 60
        bcs     @wait           ; the first 60 ms: just wait
        lda     kbuf_n
        bne     @r
        jsr     getc
        bcs     @key
        lda     ctrl
        beq     @wait
        jsr     SBC_PADSTATE
        cmp     #$FF            ; (no pad)
        beq     @wait
        cmp     pad
        bne     @r              ; pressed or let go of something
@wait:  lda     #1
        jsr     delay_ms
        dec     iw_n
        bne     @l
@r:     rts
@key:   sta     kbuf
        lda     #1
        sta     kbuf_n
        rts

; carry set if anything the view is drawn from changed since the last call:
; where the player is and faces, the things, the gun, the doors
view_changed:
        lda     force
        sta     vchg
        lda     #0
        sta     force
.macro VCHK var, slot
        lda     var
        cmp     vstate + slot
        beq     :+
        sta     vstate + slot
        inc     vchg
:
.endmacro
        VCHK    px_lo, 0
        VCHK    px_hi, 1
        VCHK    py_lo, 2
        VCHK    py_hi, 3
        VCHK    pa_lo, 4
        VCHK    pa_hi, 5
        VCHK    gun_t, 6
        VCHK    mapver, 7
        ldx     #MAXT-1
@t:
.macro VCHKT arr, base
        lda     arr,x
        cmp     base,x
        beq     :+
        sta     base,x
        inc     vchg
:
.endmacro
        VCHKT   t_state, vt_state
        VCHKT   t_x_lo, vt_x_lo
        VCHKT   t_x_hi, vt_x_hi
        VCHKT   t_y_lo, vt_y_lo
        VCHKT   t_y_hi, vt_y_hi
        VCHKT   t_anim, vt_anim
        dex
        bpl     @t
        lda     vchg
        cmp     #1              ; carry set if anything changed
        rts

clear_sb:
        lda     #1              ; (the next frame must be drawn)
        sta     force
        lda     #0
        ldx     #0
@l:     .repeat 6, K
        sta     SB + K * 256,x
        .endrepeat
        inx
        bne     @l
        rts

; ============================================================================
; level loading
; ============================================================================
; load the file named in lp_name to LEVEL_BUF.  Carry set on failure (message
; shown, key waited for).
load_level:
        lda     #$FF
        sta     attr
        lda     #<loading_txt
        ldy     #>loading_txt
        jsr     print
        lda     #<lp_name
        ldy     #>lp_name
        jsr     print0
        lda     has_load
        beq     @builtin
        lda     #<lp_block
        ldy     #>lp_block
        jsr     SBC_LOAD
        bcc     @check
        sta     load_err
        lda     #<loaderr_txt
        ldy     #>loaderr_txt
        jsr     print
        lda     load_err
        jsr     pr_hex
        jmp     @fail
@builtin:
        ldx     #0              ; only the first map is built in
@cmp:   lda     lp_name,x
        cmp     first_name,x
        bne     @noload
        inx
        cpx     #9
        bne     @cmp
        lda     #<builtin_level ; copy it (5 pages)
        sta     @rd+1
        lda     #>builtin_level
        sta     @rd+2
        lda     #>LEVEL_BUF
        sta     @wr+2
        ldx     #5
        ldy     #0
@rd:    lda     $FFFF,y
@wr:    sta     LEVEL_BUF,y
        iny
        bne     @rd
        inc     @rd+2
        inc     @wr+2
        dex
        bne     @rd
@check: lda     LEVEL_BUF       ; is it a level?
        cmp     #'D'
        bne     @bad
        lda     LEVEL_BUF+1
        cmp     #'6'
        bne     @bad
        clc
        rts
@bad:   lda     #<badlvl_txt
        ldy     #>badlvl_txt
        jsr     print
        jmp     @fail
@noload:lda     #<noload_txt
        ldy     #>noload_txt
        jsr     print
@fail:  lda     #<anykey_txt
        ldy     #>anykey_txt
        jsr     print
        jsr     flush_in
        jsr     menu_key
        sec
        rts

; set up the loaded level: player, things, counters
init_level:
        lda     LEVEL_BUF+3
        sta     px_hi
        lda     LEVEL_BUF+4
        sta     py_hi
        lda     #$80
        sta     px_lo
        sta     py_lo
        lda     LEVEL_BUF+5     ; 0..255 -> 0..1023
        asl
        sta     pa_lo
        lda     #0
        rol
        sta     pa_hi
        asl     pa_lo
        rol     pa_hi
        lda     #0
        sta     kills
        sta     kills_max
        sta     items
        sta     items_max
        sta     gun_t
        sta     cool
        sta     msg_t
        sta     done
        ldx     #MAXT-1
@clr:   sta     t_state,x
        dex
        bpl     @clr
        lda     LEVEL_BUF+34
        cmp     #MAXT+1
        bcc     @n
        lda     #MAXT
@n:     sta     tcount
        lda     #<THING_SRC
        sta     @rd+1
        lda     #>THING_SRC
        sta     @rd+2
        ldx     #0
@t:     cpx     tcount
        bcs     @done
        jsr     @get
        sta     t_type,x
        jsr     @get
        sta     t_x_hi,x
        jsr     @get
        sta     t_y_hi,x
        jsr     @get
        lda     #$80
        sta     t_x_lo,x
        sta     t_y_lo,x
        lda     #S_IDLE
        sta     t_state,x
        lda     #0
        sta     t_timer,x
        sta     t_anim,x
        lda     t_type,x
        cmp     #T_GRUNT
        bne     @b
        lda     #30
        sta     t_hp,x
        inc     kills_max
        jmp     @nx
@b:     cmp     #T_BRUTE
        bne     @it
        lda     #90
        sta     t_hp,x
        inc     kills_max
        jmp     @nx
@it:    inc     items_max
@nx:    inx
        jmp     @t
@done:  ldx     #31             ; make sure the map has walls round its edge
@tb:    lda     MAP,x           ; (the ray caster relies on it)
        bne     @tb1
        lda     #1
        sta     MAP,x
@tb1:   lda     MAP+31*32,x
        bne     @tb2
        lda     #1
        sta     MAP+31*32,x
@tb2:   dex
        bpl     @tb
        lda     #<MAP
        sta     @lr+1
        sta     @lw+1
        lda     #>MAP
        sta     @lr+2
        sta     @lw+2
        ldx     #32
@lr0:   ldy     #0
        jsr     @fix
        ldy     #31
        jsr     @fix
        lda     @lr+1
        clc
        adc     #32
        sta     @lr+1
        sta     @lw+1
        bcc     @lr1
        inc     @lr+2
        inc     @lw+2
@lr1:   dex
        bne     @lr0
        rts
@fix:
@lr:    lda     $FFFF,y
        bne     @fx
        lda     #1
@lw:    sta     $FFFF,y
@fx:    rts
@get:
@rd:    lda     $FFFF
        inc     @rd+1
        bne     @g
        inc     @rd+2
@g:     rts

; ============================================================================
; start, title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear every variable (RAM is random at power-up)
        tax
        ldy     #>(bss_end - bss_start + $FF)   ; whole pages (past the end is free RAM)
@c1:    sta     bss_start,x
        inx
        bne     @c1
        inc     @c1+2
        dey
        bne     @c1
        lda     ctrl_def
        sta     ctrl
        lda     #$A7
        sta     rng
        lda     #$FF
        sta     attr
        lda     SBC_LOAD        ; is there a JMP at $FE15?
        cmp     #$4C
        bne     @nol
        lda     #1
        sta     has_load
@nol:   jsr     read_pad
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute

title:  jsr     sfx_off
        lda     #$FF
        sta     attr
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     gfx_mode        ; the big letters
        ldy     #0
@br:    sty     tmp2
        ldx     #26
        tya
        clc
        adc     #4
        tay
        jsr     gotoxy
        ldy     tmp2
        lda     banner_lo,y
        sta     @bd+1
        lda     banner_hi,y
        sta     @bd+2
        ldx     #0
@bd:    lda     $FFFF,x
        jsr     putblk
        inx
        cpx     #BANNER_W
        bne     @bd
        ldy     tmp2
        iny
        cpy     #BANNER_H
        bne     @br
        lda     has_load
        bne     @hl
        lda     #<noload_note
        ldy     #>noload_note
        jsr     print
@hl:    jsr     show_ctrl
        jsr     read_pad
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @nq
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
        jmp     SBC_MENU
@nq:    cmp     #'M'            ; sound on / off
        bne     @nm
        jsr     sfx_toggle
        jmp     @wait
@nm:    cmp     #'G'
        bne     @ng
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@ng:    cmp     #PAD_GO
        bne     @np
        lda     #1
        sta     ctrl
        bne     new_game
@np:    cmp     #' '
        bne     @wait

new_game:
        lda     #100
        sta     health
        lda     #50
        sta     ammo
        ldx     #12             ; the first map
@n:     lda     first_name,x
        sta     lp_name,x
        dex
        bpl     @n
play_level:
        lda     ammo            ; what to go back to after dying
        sta     ammo0
        jsr     load_level
        bcc     @ok
        jmp     title
@ok:    jsr     init_level
        jsr     screen_setup
        jsr     sfx_off         ; the music
        lda     #MUS_DREAD
        jsr     sfx_snd
        lda     #MUS_DREAD+1
        jsr     sfx_snd

; ============================================================================
; the game loop
; ============================================================================
game_loop:
        jsr     sfx_poll
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     move_player
        lda     use
        beq     @2
        jsr     do_use
@2:     jsr     pickups
        jsr     update_things
        jsr     view_changed    ; nothing in view changed: skip the drawing
        bcs     @draw
        jsr     do_fire
        jsr     view_changed    ; (the gun went off?)
        bcs     @rd
        jsr     idle_wait       ; keep the game's pace (and react to keys)
        jmp     @hud
@rd:
        jsr     render_view
        jsr     render_things
        jmp     @gun
@draw:  jsr     render_view
        jsr     render_things
        jsr     do_fire
@gun:   jsr     draw_gun
        jsr     present
@hud:   jsr     hud_update
        inc     frame
        lda     health
        bne     @alive
        jmp     died
@alive: lda     done
        beq     @3
        jmp     level_done
@3:     lda     speed
        jsr     delay_ms
        jmp     game_loop

; clear the screen, the status lines
screen_setup:
        lda     #$FF
        sta     attr
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        jsr     clear_sb
        lda     #<hud_txt
        ldy     #>hud_txt
        jsr     print
        ldx     #1
        ldy     #HUD_LEVEL
        jsr     gotoxy
        lda     #<lp_name       ; "E1M1.LVL  THE AIRLOCK"
        ldy     #>lp_name
        jsr     print0
        lda     #' '
        jsr     putc
        jsr     putc
        ldx     #0
@nm:    lda     LEVEL_BUF+6,x
        jsr     putc
        inx
        cpx     #16
        bne     @nm
        ldx     #1
        ldy     #HUD_HELP
        jsr     gotoxy
        lda     ctrl
        bne     @pad
        lda     #<help_kb
        ldy     #>help_kb
        jmp     @h
@pad:   lda     #<help_pad
        ldy     #>help_pad
@h:     jsr     print
        lda     #$FF
        sta     sh_health
        sta     sh_ammo
        sta     sh_kills
        sta     sh_items
        rts

; ---- status line -----------------------------------------------------------------------
hud_update:
        lda     health
        cmp     sh_health
        beq     @1
        sta     sh_health
        jsr     txt_mode
        ldx     #8
        ldy     #HUD_STATS
        jsr     gotoxy
        lda     health
        jsr     pr_dec3
@1:     lda     ammo
        cmp     sh_ammo
        beq     @2
        sta     sh_ammo
        jsr     txt_mode
        ldx     #22
        ldy     #HUD_STATS
        jsr     gotoxy
        lda     ammo
        jsr     pr_dec3
@2:     lda     kills
        cmp     sh_kills
        beq     @3
        sta     sh_kills
        jsr     txt_mode
        ldx     #36
        ldy     #HUD_STATS
        jsr     gotoxy
        lda     kills
        jsr     pr_dec2
        lda     #'/'
        jsr     putc
        lda     kills_max
        jsr     pr_dec2
@3:     lda     items
        cmp     sh_items
        beq     @4
        sta     sh_items
        jsr     txt_mode
        ldx     #52
        ldy     #HUD_STATS
        jsr     gotoxy
        lda     items
        jsr     pr_dec2
        lda     #'/'
        jsr     putc
        lda     items_max
        jsr     pr_dec2
@4:     lda     msg_t           ; the message line times out
        beq     @r
        dec     msg_t
        bne     @r
        jsr     txt_mode
        ldx     #1
        ldy     #HUD_MSG
        jsr     gotoxy
        ldx     #60
        lda     #' '
@cl:    jsr     putc
        dex
        bne     @cl
@r:     rts

; show the message at A / Y on the message line
message:sta     tmp
        sty     tmp2
        jsr     txt_mode
        ldx     #1
        ldy     #HUD_MSG
        jsr     gotoxy
        ldx     #60
        lda     #' '
@cl:    jsr     putc
        dex
        bne     @cl
        ldx     #1
        ldy     #HUD_MSG
        jsr     gotoxy
        lda     tmp
        ldy     tmp2
        jsr     print
        lda     #20
        sta     msg_t
        rts

; ============================================================================
; input and moving
; ============================================================================
read_input:
        lda     #0
        sta     mv_fwd
        sta     mv_turn
        sta     mv_strafe
        sta     fire
        sta     use
        sta     quit
        lda     ctrl
        beq     @keys
        jsr     read_pad        ; gamepad: buttons held
        lda     pad
        and     #PAD_UP
        beq     @u
        lda     #40
        sta     mv_fwd
@u:     lda     pad
        and     #PAD_DOWN
        beq     @d
        lda     #<-40
        sta     mv_fwd
@d:     lda     pad
        and     #PAD_SELECT     ; Select + left / right: strafe
        beq     @turn
        lda     pad
        and     #PAD_LEFT
        beq     @sr
        lda     #<-40
        sta     mv_strafe
@sr:    lda     pad
        and     #PAD_RIGHT
        beq     @ab
        lda     #40
        sta     mv_strafe
        jmp     @ab
@turn:  lda     pad
        and     #PAD_LEFT
        beq     @tr
        lda     #<-20
        sta     mv_turn
@tr:    lda     pad
        and     #PAD_RIGHT
        beq     @ab
        lda     #20
        sta     mv_turn
@ab:    lda     pad
        and     #PAD_A
        beq     @b
        lda     #1
        sta     fire
@b:     lda     padnew
        and     #PAD_B
        beq     @st
        lda     #1
        sta     use
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  lda     kbuf_n          ; a key that came during idle_wait
        beq     @k2
        lda     #0
        sta     kbuf_n
        lda     kbuf
        jsr     handle_key
@k2:    jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @k2
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
        cmp     #'A'
        beq     @fwd
        cmp     #'B'
        beq     @back
        cmp     #'C'
        beq     @right
        cmp     #'D'
        beq     @left
        rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    ldx     ctrl
        beq     @kb
        jsr     pad_typed       ; gamepad mode: ignore what the pad types
        bcc     @kb
        rts
@kb:    cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'W'
        beq     @fwd
        cmp     #'S'
        beq     @back
        cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #','
        beq     @sl
        cmp     #'.'
        beq     @sr
        cmp     #' '
        beq     @fire
        cmp     #'F'
        beq     @fire
        cmp     #'E'
        beq     @use
        cmp     #'Q'
        beq     @quit
        cmp     #'P'
        beq     @pause
        cmp     #'M'
        bne     @rr
        jmp     sfx_toggle
@rr:    rts
@fwd:   lda     #64
        sta     mv_fwd
        rts
@back:  lda     #<-64
        sta     mv_fwd
        rts
@left:  lda     mv_turn         ; key repeat faster than the frames:
        cmp     #<-32           ; turn up to twice as far
        beq     @l2
        lda     #<-32
        .byte   $2C             ; (BIT abs: skips the next LDA)
@l2:    lda     #<-64
        sta     mv_turn
        rts
@right: lda     mv_turn
        cmp     #32
        beq     @r2
        lda     #32
        .byte   $2C
@r2:    lda     #64
        sta     mv_turn
        rts
@sl:    lda     #<-64
        sta     mv_strafe
        rts
@sr:    lda     #64
        sta     mv_strafe
        rts
@fire:  lda     #1
        sta     fire
        rts
@use:   lda     #1
        sta     use
        rts
@quit:  lda     #1
        sta     quit
        rts
@pause: jmp     pause

pause:  jsr     sfx_hush        ; (quiet while paused)
        lda     #<paused_txt
        ldy     #>paused_txt
        jsr     message
        jsr     flush_in
@w:     jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @go
        jsr     getc
        bcc     @w
@go:    jsr     flush_in
        lda     #1
        sta     msg_t
        rts

; turn, then move forward / sideways with wall sliding
move_player:
        lda     mv_turn         ; angle += turn (signed)
        beq     @mv
        clc
        adc     pa_lo
        sta     pa_lo
        lda     mv_turn
        bmi     @neg
        lda     pa_hi
        adc     #0
        jmp     @set
@neg:   lda     pa_hi
        adc     #$FF
@set:   and     #3
        sta     pa_hi
@mv:    lda     #0
        sta     mx_lo
        sta     mx_hi
        sta     my_lo
        sta     my_hi
        lda     pa_lo
        sta     a_lo
        lda     pa_hi
        sta     a_hi
        lda     mv_fwd
        beq     @st
        jsr     sext_w          ; forward: (cos, sin) * step
        jsr     get_cos
        jsr     smul
        jsr     add_mx
        lda     mv_fwd
        jsr     sext_w
        jsr     get_sin
        jsr     smul
        jsr     add_my
@st:    lda     mv_strafe
        beq     @go
        jsr     sext_w          ; sideways (right): (-sin, cos) * step
        jsr     get_cos
        jsr     smul
        jsr     add_my
        lda     mv_strafe
        jsr     sext_w
        jsr     get_sin
        jsr     smul
        jsr     sub_mx
@go:    jmp     try_move

; w = A sign extended (a step in 1/256 tile)
sext_w: sta     w_lo
        lda     #0
        ldx     w_lo
        bpl     @p
        lda     #$FF
@p:     sta     w_hi
        rts
add_mx: lda     mx_lo
        clc
        adc     r_lo
        sta     mx_lo
        lda     mx_hi
        adc     r_hi
        sta     mx_hi
        rts
sub_mx: lda     mx_lo
        sec
        sbc     r_lo
        sta     mx_lo
        lda     mx_hi
        sbc     r_hi
        sta     mx_hi
        rts
add_my: lda     my_lo
        clc
        adc     r_lo
        sta     my_lo
        lda     my_hi
        adc     r_hi
        sta     my_hi
        rts

; move by mx, my: x and y separately, so walls can be slid along
try_move:
        lda     mx_lo
        ora     mx_hi
        beq     @y
        lda     px_lo           ; new x
        clc
        adc     mx_lo
        sta     nx_lo
        lda     px_hi
        adc     mx_hi
        sta     nx_hi
        lda     nx_lo           ; the edge of the player in that direction
        ldx     mx_hi
        bmi     @xl
        clc
        adc     #RADIUS
        lda     nx_hi
        adc     #0
        jmp     @xc
@xl:    sec
        sbc     #RADIUS
        lda     nx_hi
        sbc     #0
@xc:    tax
        stx     edge
        jsr     clear_rows      ; free at py +- radius?
        bcc     @xok
        ldx     edge            ; no, but the middle of the player would
        ldy     py_hi           ; fit: slide towards the middle of the row
        jsr     tile_at         ; (getting through doorways is easier)
        bne     @y
        lda     py_lo
        jsr     to_middle
        sta     py_lo
        jmp     @y
@xok:   lda     nx_lo
        sta     px_lo
        lda     nx_hi
        sta     px_hi
@y:     lda     my_lo
        ora     my_hi
        beq     @done
        lda     py_lo
        clc
        adc     my_lo
        sta     ny_lo
        lda     py_hi
        adc     my_hi
        sta     ny_hi
        lda     ny_lo
        ldx     my_hi
        bmi     @yu
        clc
        adc     #RADIUS
        lda     ny_hi
        adc     #0
        jmp     @yc
@yu:    sec
        sbc     #RADIUS
        lda     ny_hi
        sbc     #0
@yc:    tay
        sty     edge
        jsr     clear_cols      ; free at px +- radius?
        bcc     @yok
        ldx     px_hi           ; the same sliding as for x
        ldy     edge
        jsr     tile_at
        bne     @done
        lda     px_lo
        jsr     to_middle
        sta     px_lo
        rts
@yok:   lda     ny_lo
        sta     py_lo
        lda     ny_hi
        sta     py_hi
@done:  rts

; A = a position within a tile -> moved up to 1/8 tile towards the middle
to_middle:
        cmp     #$80
        bcs     @hi
        adc     #32
        cmp     #$80
        bcc     @r
        lda     #$80
@r:     rts
@hi:    sbc     #32
        cmp     #$80
        bcs     @r
        lda     #$80
        rts

; carry clear if column X is floor at the rows of py - radius and py + radius
clear_rows:
        lda     py_lo
        sec
        sbc     #RADIUS
        lda     py_hi
        sbc     #0
        tay
        jsr     tile_at
        bne     @no
        lda     py_lo
        clc
        adc     #RADIUS
        lda     py_hi
        adc     #0
        tay
        jsr     tile_at
        bne     @no
        clc
        rts
@no:    sec
        rts

; carry clear if row Y is floor at the columns of px - radius and px + radius
clear_cols:
        lda     px_lo
        sec
        sbc     #RADIUS
        lda     px_hi
        sbc     #0
        tax
        jsr     tile_at
        bne     @no
        lda     px_lo
        clc
        adc     #RADIUS
        lda     px_hi
        adc     #0
        tax
        jsr     tile_at
        bne     @no
        clc
        rts
@no:    sec
        rts

; ---- use: open a door or press the exit switch in front of the player --------------
do_use: lda     pa_lo
        sta     a_lo
        lda     pa_hi
        sta     a_hi
        lda     #$C0            ; probe 3/4 of a tile ahead
        jsr     sext_w
        lda     #0
        sta     w_hi
        jsr     get_cos
        jsr     smul
        lda     px_lo
        clc
        adc     r_lo
        lda     px_hi
        adc     r_hi
        sta     ux
        lda     #$C0
        sta     w_lo
        lda     #0
        sta     w_hi
        jsr     get_sin
        jsr     smul
        lda     py_lo
        clc
        adc     r_lo
        lda     py_hi
        adc     r_hi
        sta     uy
        ldx     ux
        ldy     uy
        jsr     tile_at
        cmp     #TILE_DOOR
        bne     @ex
        lda     #SND_DOOR
        jsr     sfx_snd
        lda     #0
        ldx     ux
        ldy     uy
        jsr     tile_set
        lda     #<door_txt
        ldy     #>door_txt
        jmp     message
@ex:    cmp     #TILE_EXIT
        bne     @no
        lda     #1
        sta     done
@no:    rts

; ---- picking things up ------------------------------------------------------------------
pickups:ldx     #MAXT-1
@l:     lda     t_state,x
        cmp     #S_IDLE
        bne     @n
        lda     t_type,x
        cmp     #T_MEDKIT
        bcc     @n              ; an enemy
        lda     t_x_hi,x        ; on the same tile as the player?
        cmp     px_hi
        bne     @n
        lda     t_y_hi,x
        cmp     py_hi
        bne     @n
        lda     t_type,x
        cmp     #T_MEDKIT
        bne     @am
        lda     health
        cmp     #100
        bcs     @n              ; not needed: leave it
        adc     #25
        cmp     #101
        bcc     @h
        lda     #100
@h:     sta     health
        lda     #SND_PICKUP
        jsr     sfx_snd
        lda     #S_GONE
        sta     t_state,x
        inc     items
        stx     ti
        lda     #<medkit_txt
        ldy     #>medkit_txt
        jsr     message
        ldx     ti
        jmp     @n
@am:    lda     ammo
        clc
        adc     #10
        cmp     #200
        bcc     @a
        lda     #199
@a:     sta     ammo
        lda     #SND_PICKUP
        jsr     sfx_snd
        lda     #S_GONE
        sta     t_state,x
        inc     items
        stx     ti
        lda     #<ammo_txt
        ldy     #>ammo_txt
        jsr     message
        ldx     ti
@n:     dex
        bpl     @l
        rts

; ============================================================================
; enemies
; ============================================================================
update_things:
        ldx     #0
@l:     stx     ti
        lda     t_state,x
        cmp     #S_IDLE
        bcc     @n
        cmp     #S_DEAD
        bcs     @n
        lda     t_type,x
        cmp     #T_MEDKIT
        bcs     @n              ; items don't think
        jsr     think
@n:     ldx     ti
        inx
        cpx     #MAXT
        bne     @l
        lda     cool
        beq     @r
        dec     cool
@r:     rts

; enemy ti: wake, chase, shoot
think:  ldx     ti
        lda     px_lo           ; vector to the player
        sec
        sbc     t_x_lo,x
        sta     tdx_lo
        lda     px_hi
        sbc     t_x_hi,x
        sta     tdx_hi
        lda     py_lo
        sec
        sbc     t_y_lo,x
        sta     tdy_lo
        lda     py_hi
        sbc     t_y_hi,x
        sta     tdy_hi
        jsr     approx_dist     ; -> edist (whole tiles, capped 255)
        ldx     ti
        lda     t_state,x
        cmp     #S_ATTACK
        bne     @na
        dec     t_timer,x
        bne     @r
        jsr     resolve_attack
        ldx     ti
        lda     #S_CHASE
        sta     t_state,x
@r:     rts
@na:    cmp     #S_IDLE
        bne     @chase
        lda     edist           ; asleep: wakes if it can see the player close by
        cmp     #8
        bcs     @r
        jsr     line_of_sight
        bcs     @r
        lda     #SND_WAKE
        jsr     sfx_snd
        ldx     ti
        lda     #S_CHASE
        sta     t_state,x
        rts
@chase: lda     edist           ; shoot?
        cmp     #12
        bcs     @move
        jsr     rand
        ldx     ti
        ldy     t_type,x
        cmp     shoot_chance-1,y
        bcs     @move
        jsr     line_of_sight
        bcs     @move
        lda     #SND_ESHOOT
        jsr     sfx_snd
        ldx     ti
        lda     #S_ATTACK
        sta     t_state,x
        lda     #3
        sta     t_timer,x
        rts
@move:  ldx     ti              ; close in, but not right on top
        lda     edist
        bne     *+5
        jmp     @r2
        inc     t_anim,x
        ldy     t_type,x
        lda     walk_speed-1,y
        sta     estep
        ; x
        lda     tdx_hi
        ora     tdx_lo
        beq     @my
        lda     t_x_lo,x
        ldy     tdx_hi
        bmi     @xm
        clc
        adc     estep
        sta     nx_lo
        lda     t_x_hi,x
        adc     #0
        jmp     @xs
@xm:    sec
        sbc     estep
        sta     nx_lo
        lda     t_x_hi,x
        sbc     #0
@xs:    sta     nx_hi
        tax                     ; free there? (its own row)
        ldy     ti
        lda     t_y_hi,y
        tay
        jsr     tile_at
        bne     @my
        ldx     ti
        lda     nx_lo
        sta     t_x_lo,x
        lda     nx_hi
        sta     t_x_hi,x
@my:    ldx     ti
        lda     tdy_hi
        ora     tdy_lo
        beq     @r2
        lda     t_y_lo,x
        ldy     tdy_hi
        bmi     @ym
        clc
        adc     estep
        sta     ny_lo
        lda     t_y_hi,x
        adc     #0
        jmp     @ys
@ym:    sec
        sbc     estep
        sta     ny_lo
        lda     t_y_hi,x
        sbc     #0
@ys:    sta     ny_hi
        tay
        lda     t_x_hi,x
        tax
        jsr     tile_at
        bne     @r2
        ldx     ti
        lda     ny_lo
        sta     t_y_lo,x
        lda     ny_hi
        sta     t_y_hi,x
@r2:    rts

; an enemy's shot or blow lands (or not)
resolve_attack:
        ldx     ti
        lda     t_type,x
        cmp     #T_BRUTE
        beq     @brute
        jsr     rand            ; grunt: 60 % to hit for 3-10
        cmp     #150
        bcs     @miss
        jsr     rand
        and     #7
        clc
        adc     #3
        jmp     hurt
@brute: lda     edist           ; brute: close up it hits hard
        cmp     #2
        bcs     @far
        jsr     rand
        and     #15
        clc
        adc     #10
        jmp     hurt
@far:   jsr     rand
        cmp     #110
        bcs     @miss
        jsr     rand
        and     #7
        clc
        adc     #6
        jmp     hurt
@miss:  rts

; the player loses A health
hurt:   sta     tmp3
        lda     #SND_OUCH
        jsr     sfx_snd
        lda     health
        sec
        sbc     tmp3
        bcs     @ok
        lda     #0
@ok:    sta     health
        lda     #<ouch_txt
        ldy     #>ouch_txt
        jmp     message

; edist = roughly the distance in tiles from tdx, tdy (max + min / 2)
approx_dist:
        lda     tdx_hi
        bpl     @x
        lda     tdx_lo          ; |dx| in whole tiles (rounded)
        eor     #$FF
        clc
        adc     #1
        lda     tdx_hi
        eor     #$FF
        adc     #0
@x:     sta     tmp
        lda     tdy_hi
        bpl     @y
        lda     tdy_lo
        eor     #$FF
        clc
        adc     #1
        lda     tdy_hi
        eor     #$FF
        adc     #0
@y:     sta     tmp2
        cmp     tmp
        bcc     @s
        lda     tmp             ; tmp = max, tmp2 = min
        ldy     tmp2
        sta     tmp2
        sty     tmp
@s:     lda     tmp2
        lsr
        clc
        adc     tmp
        bcc     @d
        lda     #255
@d:     sta     edist
        rts

; carry clear if enemy ti can see the player: 16 samples along the line
line_of_sight:
        ldx     ti
        lda     t_x_lo,x
        sta     lx_lo
        lda     t_x_hi,x
        sta     lx_hi
        lda     t_y_lo,x
        sta     ly_lo
        lda     t_y_hi,x
        sta     ly_hi
        lda     tdx_lo          ; step = d / 16 (arithmetic shift)
        sta     sx_lo
        lda     tdx_hi
        sta     sx_hi
        lda     tdy_lo
        sta     sy_lo
        lda     tdy_hi
        sta     sy_hi
        ldx     #4
@sh:    lda     sx_hi
        cmp     #$80
        ror     sx_hi
        ror     sx_lo
        lda     sy_hi
        cmp     #$80
        ror     sy_hi
        ror     sy_lo
        dex
        bne     @sh
        lda     #15
        sta     guard
@l:     lda     lx_lo
        clc
        adc     sx_lo
        sta     lx_lo
        lda     lx_hi
        adc     sx_hi
        sta     lx_hi
        lda     ly_lo
        clc
        adc     sy_lo
        sta     ly_lo
        lda     ly_hi
        adc     sy_hi
        sta     ly_hi
        ldx     lx_hi
        ldy     ly_hi
        jsr     tile_at
        bne     @no
        dec     guard
        bne     @l
        clc
        rts
@no:    sec
        rts

; ---- the player's gun -------------------------------------------------------------------
do_fire:lda     fire
        beq     @r
        lda     cool
        bne     @r
        lda     ammo
        bne     @shoot
        lda     #SND_CLICK
        jsr     sfx_snd
        lda     #<noammo_txt
        ldy     #>noammo_txt
        jsr     message
        lda     #8
        sta     cool
@r:     rts
@shoot: dec     ammo
        lda     #SND_PISTOL
        jsr     sfx_snd
        lda     #2
        sta     gun_t
        lda     #3
        sta     cool
        ; the noise wakes enemies nearby
        ldx     #MAXT-1
@wk:    lda     t_state,x
        cmp     #S_IDLE
        bne     @wn
        lda     t_type,x
        cmp     #T_MEDKIT
        bcs     @wn
        lda     t_x_hi,x        ; within 8 tiles?
        sec
        sbc     px_hi
        clc
        adc     #8
        cmp     #17
        bcs     @wn
        lda     t_y_hi,x
        sec
        sbc     py_hi
        clc
        adc     #8
        cmp     #17
        bcs     @wn
        lda     #S_CHASE
        sta     t_state,x
@wn:    dex
        bpl     @wk
        ; hit the nearest enemy on screen across the middle column
        lda     #$FF
        sta     hit
        ldx     nvis
@h:     dex
        bmi     @hd
        ldy     v_t,x
        lda     t_type,y
        cmp     #T_MEDKIT
        bcs     @h
        lda     t_state,y
        cmp     #S_CHASE
        bcc     @h
        cmp     #S_DEAD
        bcs     @h
        lda     v_h,x           ; half width in columns = h / 4 + 1
        lsr
        lsr
        clc
        adc     #1
        sta     tmp
        lda     v_sx_lo,x       ; |sx - 40| <= half width ?
        sec
        sbc     #40
        sta     tmp2
        lda     v_sx_hi,x
        sbc     #0
        bpl     @hp
        lda     #0
        sec
        sbc     tmp2
        sta     tmp2
        lda     #0              ; (beyond -255 can't happen)
@hp:    bne     @h
        lda     tmp2
        cmp     tmp
        bcs     @h
        lda     v_d_hi,x        ; in front of the wall in the middle?
        cmp     zb_hi+40
        bcc     @hv
        bne     @h
        lda     v_d_lo,x
        cmp     zb_lo+40
        bcs     @h
@hv:    stx     hit             ; drawn far to near: the last one is nearest
        jmp     @hd
@hd:    ldx     hit
        bmi     @r2
        ldy     v_t,x
        sty     ti
        jsr     rand
        and     #15
        clc
        adc     #12
        sta     tmp
        ldx     ti
        lda     t_hp,x
        sec
        sbc     tmp
        bcc     @kill
        beq     @kill
        sta     t_hp,x
        lda     #SND_PAIN
        jmp     sfx_snd
@kill:  lda     #SND_KILL
        jsr     sfx_snd
        lda     #S_DEAD
        sta     t_state,x
        inc     kills
        lda     #<kill_txt
        ldy     #>kill_txt
        jmp     message
@r2:    rts

; ============================================================================
; dying, finishing a level
; ============================================================================
died:   jsr     sfx_off
        lda     #SND_DIED
        jsr     sfx_snd
        lda     #<died_txt
        ldy     #>died_txt
        jsr     message
        lda     #20
        jsr     delay_long
        jsr     flush_in
        jsr     menu_key
        cmp     #'Q'
        bne     @again
        jmp     title
@again: lda     #100            ; back to the start of the level
        sta     health
        lda     ammo0
        cmp     #20
        bcs     @a
        lda     #20
@a:     sta     ammo
        jmp     play_level

level_done:
        jsr     sfx_off
        lda     #SND_DONE
        jsr     sfx_snd
        lda     #$FF
        sta     attr
        lda     #<done_txt
        ldy     #>done_txt
        jsr     print
        lda     #<lp_name
        ldy     #>lp_name
        jsr     print0
        lda     #<done2_txt
        ldy     #>done2_txt
        jsr     print
        lda     kills
        jsr     pr_dec2
        lda     #'/'
        jsr     putc
        lda     kills_max
        jsr     pr_dec2
        lda     #<done3_txt
        ldy     #>done3_txt
        jsr     print
        lda     items
        jsr     pr_dec2
        lda     #'/'
        jsr     putc
        lda     items_max
        jsr     pr_dec2
        lda     LEVEL_BUF+22    ; the next map, or the end
        bne     @next
        lda     #<win_txt
        ldy     #>win_txt
        jsr     print
        jsr     flush_in
        jsr     menu_key
        jmp     title
@next:  lda     #<next_txt
        ldy     #>next_txt
        jsr     print
        ldx     #11
@n:     lda     LEVEL_BUF+22,x
        sta     lp_name,x
        dex
        bpl     @n
        lda     #0
        sta     lp_name+12
        lda     #20
        jsr     delay_long
        jsr     flush_in
        jsr     menu_key
        cmp     #'Q'
        bne     @go
        jmp     title
@go:    jmp     play_level

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
        .include "builtin.inc"
        .include "doom_sound.inc"       ; the music and effects (game_sounds.py)

maprow_lo:
.repeat 32, I
        .byte   <(MAP + I * 32)
.endrepeat
maprow_hi:
.repeat 32, I
        .byte   >(MAP + I * 32)
.endrepeat
fbrow_lo:
.repeat VROWS, I
        .byte   <(FB + I * COLS)
.endrepeat
fbrow_hi:
.repeat VROWS, I
        .byte   >(FB + I * COLS)
.endrepeat
sbrow_lo:
.repeat VROWS, I
        .byte   <(SB + I * COLS)
.endrepeat
sbrow_hi:
.repeat VROWS, I
        .byte   >(SB + I * COLS)
.endrepeat
gunrow_lo:
.repeat 4, I
        .byte   <(FB + (14 + I) * COLS + 36)
.endrepeat
gunrow_hi:
.repeat 4, I
        .byte   >(FB + (14 + I) * COLS + 36)
.endrepeat
banner_lo:
.repeat BANNER_H, I
        .byte   <(banner + I * BANNER_W)
.endrepeat
banner_hi:
.repeat BANNER_H, I
        .byte   >(banner + I * BANNER_W)
.endrepeat

mstart: .byte   $FF, $FC, $F0, $C0, $00 ; rows from k down
mend:   .byte   $00, $03, $0F, $3F, $FF ; rows above k
bitmask:.byte   $01, $02, $04, $08, $10, $20, $40, $80
rowbit_l:.byte  $01, $04, $10, $40      ; left pixel of character row k
rowbit_r:.byte  $02, $08, $20, $80      ; right pixel
shoot_chance:   .byte 18, 26            ; per frame, out of 256 (grunt, brute)
walk_speed:     .byte 22, 16            ; 1/256 tile per frame

first_name:     .byte "E1M1.LVL", 0, 0, 0, 0, 0

; ---- text ----------------------------------------------------------------------------
cls_txt:.byte   TC_CLS, TC_CURSOR, 0, TERM
title_txt:
        .byte   TC_CLS, TC_CURSOR, 0
        .byte   TC_ROW, 2, TC_COL, 37, "6502"
        .byte   TC_ROW, 9, TC_COL, 24, "A FIRST PERSON SHOOTER, MORE OR LESS"
        .byte   TC_ROW, 11, TC_COL, 12, "KEYS: W/S OR UP/DOWN MOVE   A/D OR LEFT/RIGHT TURN   , . STRAFE"
        .byte   TC_ROW, 12, TC_COL, 12, "      SPACE FIRE   E USE (DOORS, EXIT)   P PAUSE   M SOUND   Q QUIT"
        .byte   TC_ROW, 13, TC_COL, 12, "PAD:  D-PAD MOVE/TURN   SELECT+LEFT/RIGHT STRAFE   A FIRE   B USE"
        .byte   TC_ROW, 20, TC_COL, 25, "SPACE OR START: NEW GAME    Q: QUIT", TERM
noload_note:
        .byte   TC_ROW, 15, TC_COL, 12, "THIS ROM HAS NO SBC_LOAD: ONLY THE BUILT-IN FIRST MAP CAN BE PLAYED", TERM
bye_txt:.byte   TC_CLS, TC_CURSOR, '_', TERM
loading_txt:
        .byte   TC_CLS, TC_CURSOR, 0, TC_ROW, 10, TC_COL, 30, "LOADING ", TERM
loaderr_txt:
        .byte   TC_ROW, 12, TC_COL, 30, "COULD NOT LOAD IT: ERROR $", TERM
badlvl_txt:
        .byte   TC_ROW, 12, TC_COL, 30, "THAT IS NOT A LEVEL FILE", TERM
noload_txt:
        .byte   TC_ROW, 12, TC_COL, 18, "THIS ROM HAS NO SBC_LOAD TO LOAD MORE MAPS", TERM
anykey_txt:
        .byte   TC_ROW, 14, TC_COL, 30, "PRESS A KEY", TERM
hud_txt:.byte   TC_ROW, HUD_LINE, TC_COL, 0
        .byte   "--------------------------------------------------------------------------------"
        .byte   TC_ROW, HUD_STATS, TC_COL, 1, "HEALTH"
        .byte   TC_COL, 16, "AMMO"
        .byte   TC_COL, 30, "KILLS"
        .byte   TC_COL, 46, "ITEMS", TERM
help_kb:.byte   "W/S MOVE  A/D TURN  , . STRAFE  SPACE FIRE  E USE  P PAUSE  M SOUND  Q QUIT", TERM
help_pad:
        .byte   "D-PAD MOVE/TURN  SELECT+L/R STRAFE  A FIRE  B USE  START PAUSE", TERM
paused_txt:     .byte "PAUSED", TERM
door_txt:       .byte "THE DOOR OPENS", TERM
medkit_txt:     .byte "PICKED UP A MEDKIT", TERM
ammo_txt:       .byte "PICKED UP SOME AMMO", TERM
noammo_txt:     .byte "OUT OF AMMO!", TERM
ouch_txt:       .byte "OUCH! YOU ARE HIT", TERM
kill_txt:       .byte "GOT ONE!", TERM
died_txt:       .byte "YOU DIED.  SPACE / START: TRY AGAIN   Q: TITLE", TERM
done_txt:
        .byte   TC_CLS, TC_CURSOR, 0, TC_ROW, 8, TC_COL, 30, "FINISHED ", TERM
done2_txt:
        .byte   TC_ROW, 10, TC_COL, 30, "KILLS ", TERM
done3_txt:
        .byte   TC_ROW, 11, TC_COL, 30, "ITEMS ", TERM
next_txt:
        .byte   TC_ROW, 14, TC_COL, 26, "SPACE / START: ON TO THE NEXT MAP", TERM
win_txt:
        .byte   TC_ROW, 14, TC_COL, 22, "THAT WAS THE LAST MAP.  YOU WIN!  (A KEY: TITLE)", TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM

; ---- the SBC_LOAD parameter block ------------------------------------------------------
        .segment "DATA"
lp_block:
        .word   LEVEL_BUF       ; load address
        .word   LEVEL_MAX       ; most bytes to load
lp_name:.res    13              ; "NAME.EXT", 0

; ============================================================================
; variables (not in the file)
; ============================================================================
        .segment "BSS"
bss_start:
attr:       .res 1
ctrl:       .res 1
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
has_load:   .res 1
load_err:   .res 1
lead:       .res 1
; maths
m_a:        .res 1
m_b:        .res 1
m_lo:       .res 1
m_hi:       .res 1
mf:         .res 1
w_lo:       .res 1
w_hi:       .res 1
r_lo:       .res 1
r_hi:       .res 1
sm_s:       .res 1
sm_a:       .res 1
sm_sign:    .res 1
n0:         .res 1
n1:         .res 1
n2:         .res 1
d0:         .res 1
d1:         .res 1
rm0:        .res 1
rm1:        .res 1
a_lo:       .res 1
a_hi:       .res 1
; the player
px_lo:      .res 1
px_hi:      .res 1
py_lo:      .res 1
py_hi:      .res 1
pa_lo:      .res 1
pa_hi:      .res 1
health:     .res 1
ammo:       .res 1

ammo0:      .res 1
kills:      .res 1
kills_max:  .res 1
items:      .res 1
items_max:  .res 1
sh_health:  .res 1
sh_ammo:    .res 1
sh_kills:   .res 1
sh_items:   .res 1
msg_t:      .res 1
gun_t:      .res 1
cool:       .res 1
done:       .res 1
frame:      .res 1
; input
mv_fwd:     .res 1
mv_turn:    .res 1
mv_strafe:  .res 1
fire:       .res 1
use:        .res 1
quit:       .res 1
esc_st:     .res 1
mx_lo:      .res 1
mx_hi:      .res 1
my_lo:      .res 1
my_hi:      .res 1
nx_lo:      .res 1
nx_hi:      .res 1
ny_lo:      .res 1
ny_hi:      .res 1
ux:         .res 1
uy:         .res 1
; ray casting
col:        .res 1
ra_lo:      .res 1
ra_hi:      .res 1
ta_lo:      .res 1
ta_hi:      .res 1
tb_lo:      .res 1
tb_hi:      .res 1
dx_lo:      .res 1
dx_hi:      .res 1
dy_lo:      .res 1
dy_hi:      .res 1
ff:         .res 1
spx_lo:     .res 1
spx_hi:     .res 1
spy_lo:     .res 1
spy_hi:     .res 1
sx_lo:      .res 1
sx_hi:      .res 1
sy_lo:      .res 1
sy_hi:      .res 1
mp_lo:      .res 1
mp_hi:      .res 1
pbase_lo:   .res 1
pbase_hi:   .res 1
item:       .res 1              ; drawing an item (half size)
edge:       .res 1              ; the tile at the edge of a move
zmax:       .res 1              ; farthest wall this frame (whole tiles)
guard:      .res 1
side:       .res 1
tile:       .res 1
dist_lo:    .res 1
dist_hi:    .res 1
idx_lo:     .res 1
idx_hi:     .res 1
hgt:        .res 1
band:       .res 1
pat:        .res 1
lastc_lo:   .res 1
lastc_hi:   .res 1
lastside:   .res 1
y0:         .res 1
y1:         .res 1
r0:         .res 1
r1:         .res 1
t0:         .res 1
t1:         .res 1
lo4:        .res 1
hi4:        .res 1
msk:        .res 1
zb_lo:      .res COLS
zb_hi:      .res COLS
colbuf:     .res VROWS
c_hgt:      .res COLS          ; per column: wall height
c_pidx:     .res COLS          ;   pattern index (style*8 + side*4 + band)
c_mplo:     .res COLS          ;   map address of the block hit
c_mphi:     .res COLS
; sending the frame
prow:       .res 1
pcol:       .res 1
cur_r:      .res 1
cur_c:      .res 1
val:        .res 1
force:      .res 1              ; draw the next frame whatever
kbuf:       .res 1              ; a key kept by idle_wait
kbuf_n:     .res 1
iw_n:       .res 1

vchg:       .res 1
mapver:     .res 1              ; counts changes to the map (doors)
vstate:     .res 8              ; what the last frame was drawn from
vt_state:   .res MAXT
vt_x_lo:    .res MAXT
vt_x_hi:    .res MAXT
vt_y_lo:    .res MAXT
vt_y_hi:    .res MAXT
vt_anim:    .res MAXT
cur_rep:    .res 1              ; the repeat count the terminal has now
need:       .res 1
runl:       .res 1
kcnt:       .res 1
; things
tcount:     .res 1
t_type:     .res MAXT
t_x_lo:     .res MAXT
t_x_hi:     .res MAXT
t_y_lo:     .res MAXT
t_y_hi:     .res MAXT
t_state:    .res MAXT
t_hp:       .res MAXT
t_timer:    .res MAXT
t_anim:     .res MAXT
; things on screen this frame (6 arrays in this order, see swap_vis)
v_t:        .res MAXT
v_sx_lo:    .res MAXT
v_sx_hi:    .res MAXT
v_d_lo:     .res MAXT
v_d_hi:     .res MAXT
v_h:        .res MAXT
nvis:       .res 1
vi:         .res 1
si:         .res 1
sj:         .res 1
ti:         .res 1
psin:       .res 1
pcos:       .res 1
tdx_lo:     .res 1
tdx_hi:     .res 1
tdy_lo:     .res 1
tdy_hi:     .res 1
acc_lo:     .res 1
acc_hi:     .res 1
dep_lo:     .res 1
dep_hi:     .res 1
lat_sign:   .res 1
sh:         .res 1
sdep_lo:    .res 1
sdep_hi:    .res 1
st_lo:      .res 1
st_hi:      .res 1
x0_lo:      .res 1
x0_hi:      .res 1
cc:         .res 1
bu0:        .res 1
bu1:        .res 1
rr:         .res 1
kk:         .res 1
cm:         .res 1
cf:         .res 1
tm:         .res 1
tf:         .res 1
vtab:       .res VH
edist:      .res 1
estep:      .res 1
lx_lo:      .res 1
lx_hi:      .res 1
ly_lo:      .res 1
ly_hi:      .res 1
hit:        .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
bss_end:
