; ============================================================================
; disp2.s - GOLD GRABBER's picture on the PICO9918 (included by grabber.s)
;
; Graphics I, the F18A's ECM2 (2 bits a pixel) for both tile layers and the
; sprites (16 x 16); the art is gen_pico.py's (grabber_gfx.inc).
;   layer 1: the field's background (sky, grass, dirt); text (white on black)
;   layer 2: the miner, the platform and the winch; the things in the pit,
;            drawn into patterns of their own (the pool, from POOL) by
;            compose; highlighted text (white on blue)
;   sprites: the claw, what it holds, the gophers, the bangs, the target,
;            the rope and the laser (their patterns drawn here)
; Layer 2 is under the sprites (R50 bit 0).  A game pixel is 1.5 x 2 screen
; pixels: x = 8 + x + x / 2, y = 8 + 2y.
; ============================================================================

V_TP0           = $0000         ; tile patterns, plane 0
V_TP1           = $0800         ;   plane 1
V_SP0           = $1000         ; sprite patterns, plane 0 (32 x 32 bytes)
V_SP1           = $1400         ;   plane 1
V_NAME1         = $1800         ; layer 1 names
V_ATT1          = $1C00         ; layer 1 attributes (a byte a pattern)
V_ATT2          = $1D00         ; layer 2 attributes
V_SATTR         = $1E00         ; sprite attributes
V_NAME2         = $2000         ; layer 2 names
VDP_NAME        = V_NAME1

NSLOT           = 30            ; sprite patterns for pictures (cached)
SL_ROPE         = 30            ; ... the rope's own
SL_LASER        = 31            ; ... the laser's
PIV_SX          = 8 + PIVX + PIVX / 2
PIV_SY          = 8 + 2 * PIVY

; ---- the display's set-up ----------------------------------------------------
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (VRAM cleared)
        ldx     #0              ; the F18A's registers
@r:     stx     tmp
        lda     f18a_regs+1,x
        pha
        lda     f18a_regs,x
        tax
        pla
        jsr     vdp_reg
        ldx     tmp
        inx
        inx
        cpx     #F18A_N * 2
        bne     @r
        ; the palette: VR47 = $C0 (auto increment from 0), 128 bytes
        lda     #$C0
        ldx     #47
        jsr     vdp_reg
        ldx     #0
@p:     lda     pal_data,x
        sta     VDP_DATA
        inx
        cpx     #128
        bne     @p
        lda     #0
        ldx     #47
        jsr     vdp_reg
        ; the font into both planes ($20-$5F)
        lda     #<(V_TP0 + $100)
        ldy     #>(V_TP0 + $100)
        jsr     font_up
        lda     #<(V_TP1 + $100)
        ldy     #>(V_TP1 + $100)
        jsr     font_up
        ; the field's patterns
        lda     #<(V_TP0 + T_BASE * 8)
        ldy     #>(V_TP0 + T_BASE * 8)
        jsr     vdp_waddr
        lda     #<t_pat0
        sta     vdp_src
        lda     #>t_pat0
        sta     vdp_src+1
        lda     #<(T_COUNT * 8)
        sta     vdp_n
        lda     #>(T_COUNT * 8)
        sta     vdp_n+1
        jsr     vdp_copy
        lda     #<(V_TP1 + T_BASE * 8)
        ldy     #>(V_TP1 + T_BASE * 8)
        jsr     vdp_waddr
        lda     #<t_pat1
        sta     vdp_src
        lda     #>t_pat1
        sta     vdp_src+1
        lda     #<(T_COUNT * 8)
        sta     vdp_n
        lda     #>(T_COUNT * 8)
        sta     vdp_n+1
        jsr     vdp_copy
        ; the attribute tables
        lda     #<V_ATT1
        ldy     #>V_ATT1
        jsr     vdp_waddr
        ldx     #0
@a1:    lda     attr1,x
        sta     VDP_DATA
        inx
        bne     @a1
        lda     #<V_ATT2
        ldy     #>V_ATT2
        jsr     vdp_waddr
@a2:    lda     attr2,x
        sta     VDP_DATA
        inx
        bne     @a2
        lda     #$FF            ; no sprite patterns loaded
        ldx     #NSLOT-1
@s:     sta     sl_part,x
        dex
        bpl     @s
        sta     rope_md
        sta     laser_md
        jsr     cls
        lda     #$C2            ; R1: display on, 16K, 16 x 16 sprites, and
        ldx     #1              ; bit 5 (the VDP interrupt) off
        jmp     vdp_reg

; the font's 512 bytes to VRAM at A/Y
font_up:jsr     vdp_waddr
        lda     #<font
        sta     vdp_src
        lda     #>font
        sta     vdp_src+1
        lda     #<512
        sta     vdp_n
        lda     #>512
        sta     vdp_n+1
        jmp     vdp_copy

; before going back to the console: the PICO9918 resets itself and its
; palette (VR50 = $C0)
pal_restore:
        lda     #$C0
        ldx     #50
        jmp     vdp_reg

; ---- a new page --------------------------------------------------------------
; both layers empty (black), no sprites, the things' patterns all free
new_screen:
cls:    lda     font_gone       ; (the things were drawn over letters)
        beq     @f
        lda     #<(V_TP0 + $100)
        ldy     #>(V_TP0 + $100)
        jsr     font_up
        lda     #<(V_TP1 + $100)
        ldy     #>(V_TP1 + $100)
        jsr     font_up
        lda     #<(V_ATT2 + $20)
        ldy     #>(V_ATT2 + $20)
        jsr     vdp_waddr
        ldx     #$20
@fa:    lda     attr2,x
        sta     VDP_DATA
        inx
        cpx     #$60
        bne     @fa
@f:     lda     #0
        sta     font_gone
        sta     rv
        sta     cur_col
        sta     cur_row
        sta     fieldcol
        sta     wshown
        lda     #<V_SATTR       ; no sprites
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        lda     #<V_NAME1       ; the names: layer 1, then layer 2
        ldy     #>V_NAME1
        jsr     vdp_waddr
        jsr     @fill
        lda     #<V_NAME2
        ldy     #>V_NAME2
        jsr     vdp_waddr
        jsr     @fill
        lda     #0              ; layer 2's copy, and the pool
        tax
@c:     sta     l2n,x
        sta     l2n+256,x
        sta     l2n+512,x
        inx
        bne     @c
        ldx     #NPOOL
@u:     sta     pool_used-1,x
        dex
        bne     @u
        rts
@fill:  lda     #0
        sta     vdp_n
        lda     #3
        sta     vdp_n+1
        lda     #0
        jmp     vdp_fill

; ---- text --------------------------------------------------------------------------
; a character at the cursor, and the cursor on (off the right edge:
; nothing).  Plain text: layer 1 (white on black), and layer 2 cleared
; there; highlighted (rv): layer 2 (white on blue), but a highlighted space
; in the sky row of the field: nothing (layer 2 cleared).  Preserves A, X, Y.
putc:   pha
        stx     pu_x
        sty     pu_y
        ldx     cur_col
        cpx     #32
        bcc     :+
        jmp     @out
:       cmp     #$20
        bcc     @sp
        cmp     #$60
        bcc     @ok
@sp:    lda     #$20            ; (anything else: a space)
@ok:    sta     pu_c
        lda     cur_row         ; the cell: row * 32 + column
        sta     pu_a+1
        lda     #0
        lsr     pu_a+1
        ror
        lsr     pu_a+1
        ror
        lsr     pu_a+1
        ror
        ora     cur_col
        sta     pu_a
        ldx     rv
        bne     @hi
        lda     pu_a            ; layer 1
        ldy     pu_a+1
        clc
        adc     #<V_NAME1
        pha
        tya
        adc     #>V_NAME1
        tay
        pla
        jsr     vdp_waddr
        lda     pu_c
        sta     VDP_DATA
        lda     #0              ; layer 2 cleared
        jmp     @l2
@hi:    lda     pu_c
        cmp     #$20
        bne     @l2
        ldx     fieldcol
        beq     @l2
        ldx     cur_row
        cpx     #1
        bne     @l2
        lda     #0
@l2:    sta     pu_c
        lda     pu_a            ; layer 2 (and its copy)
        clc
        adc     #<l2n
        sta     @w+1
        lda     pu_a+1
        adc     #>l2n
        sta     @w+2
        lda     pu_c
@w:     sta     $FFFF
        lda     pu_a
        ldy     pu_a+1
        clc
        adc     #<V_NAME2
        pha
        tya
        adc     #>V_NAME2
        tay
        pla
        jsr     vdp_waddr
        lda     pu_c
        sta     VDP_DATA
@out:   inc     cur_col
        ldx     pu_x
        ldy     pu_y
        pla
        rts

; ---- the field ----------------------------------------------------------------------
; the background (layer 1), the miner, platform and winch, and the things
; that lie still (layer 2)
draw_field:
        lda     #<(V_NAME1 + 32)        ; (not row 0: the status line)
        ldy     #>(V_NAME1 + 32)
        jsr     vdp_waddr
        lda     #<(field_l1 + 32)
        sta     vdp_src
        lda     #>(field_l1 + 32)
        sta     vdp_src+1
        lda     #<736
        sta     vdp_n
        lda     #>736
        sta     vdp_n+1
        jsr     vdp_copy
        ldx     #N_L2-1         ; layer 2's still pictures (into the copy)
@s:     lda     l2_lo,x
        clc
        adc     #<l2n
        sta     @w+1
        lda     l2_hi,x
        adc     #>l2n
        sta     @w+2
        lda     l2_nm,x
@w:     sta     $FFFF
        dex
        bpl     @s
        lda     #0
        sta     wshown
        ldx     #NITEM-1        ; the things
@i:     stx     fd_i
        lda     it_k,x
        beq     @n
        cmp     #K_GOPHER
        beq     @n
        jsr     comp_item
@n:     ldx     fd_i
        dex
        bpl     @i
        lda     #0              ; layer 2 to the screen (not row 0)
        sta     ur_x0
        lda     #1
        sta     ur_y0
        lda     #31
        sta     ur_x1
        lda     #23
        sta     ur_y1
        jmp     upload

; the winch's picture: turning (2 frames) while reeling in
draw_winch:
        lda     #0
        ldx     hst
        cpx     #H_BACK
        bne     @f
        lda     frame
        lsr
        and     #1
@f:     cmp     wshown
        beq     @r
        sta     wshown
        ldx     #N_WINCH-1
@l:     stx     tmp
        lda     w_lo,x
        clc
        adc     #<V_NAME2
        pha
        lda     w_hi,x
        adc     #>V_NAME2
        tay
        pla
        jsr     vdp_waddr
        ldx     tmp
        lda     w_nm0,x
        ldy     wshown
        beq     @0
        lda     w_nm1,x
@0:     sta     VDP_DATA
        dex
        bpl     @l
@r:     rts

; ---- the things in the pit: drawn into layer 2 ----------------------------------------
; item X's picture into the pool (ur_ the cells it covers)
comp_item:
        lda     it_k,x
        sec
        sbc     #1              ; (kinds 1-6 are CP_GEM .. CP_TNT)
        pha
        lda     it_y,x
        asl
        clc
        adc     #8
        tay
        lda     it_x,x
        jsr     scr_x
        tax
        pla
        ; fall through

; compose picture A at screen X, Y into layer 2's copy and the pool;
; ur_x0..ur_y1 = the cells it covers
compose:stx     cm_x
        sty     cm_y
        tax
        lda     cp_lo,x
        sta     @d+1
        lda     cp_hi,x
        sta     @d+2
        jsr     @get
        sta     cm_w
        jsr     @get
        sta     cm_h
        jsr     @get
        sta     cm_ps
        jsr     @get
        sta     cm_nb
        lda     cm_x            ; the cells it covers
        lsr
        lsr
        lsr
        sta     ur_x0
        lda     cm_x
        clc
        adc     cm_w
        sec
        sbc     #1
        bcs     :+
        lda     #255
:       lsr
        lsr
        lsr
        sta     ur_x1
        lda     cm_y
        lsr
        lsr
        lsr
        sta     ur_y0
        lda     cm_y
        clc
        adc     cm_h
        sec
        sbc     #1
        lsr
        lsr
        lsr
        sta     ur_y1
        lda     cm_y
        sta     cm_yy
@row:   ldx     #0              ; this row, both planes, shifted
@g0:    jsr     @get
        sta     cm_b0,x
        inx
        cpx     cm_nb
        bne     @g0
        lda     #0
        sta     cm_b0,x
        ldx     #0
@g1:    jsr     @get
        sta     cm_b1,x
        inx
        cpx     cm_nb
        bne     @g1
        lda     #0
        sta     cm_b1,x
        lda     cm_x
        and     #7
        beq     @sh
        tay
@shl:   lsr     cm_b0
        ror     cm_b0+1
        ror     cm_b0+2
        ror     cm_b0+3
        lsr     cm_b1
        ror     cm_b1+1
        ror     cm_b1+2
        ror     cm_b1+3
        dey
        bne     @shl
@sh:    lda     cm_yy           ; the row of cells: its first cell in the copy
        lsr
        lsr
        lsr
        sta     tmp2            ; (cy)
        lda     #0
        lsr     tmp2
        ror
        lsr     tmp2
        ror
        lsr     tmp2
        ror
        sta     cm_c            ; cy * 32
        lda     tmp2
        sta     cm_c+1
        lda     cm_x
        lsr
        lsr
        lsr
        sta     cm_cx
        ldx     #0
@byte:  lda     cm_b0,x
        ora     cm_b1,x
        beq     @nb
        lda     cm_cx
        cmp     #32
        bcs     @nb
        stx     cm_j
        jsr     cm_cell         ; A = the cell's pool number, or carry set
        bcs     @nb1
        tay                     ; its line: pool * 8 + y & 7
        lda     #0
        sta     cm_p+1
        tya
        asl
        rol     cm_p+1
        asl
        rol     cm_p+1
        asl
        rol     cm_p+1
        sta     cm_p
        lda     cm_yy
        and     #7
        ora     cm_p
        sta     cm_p
        clc
        adc     #<pool_p0
        sta     @o0+1
        sta     @w0+1
        lda     cm_p+1
        adc     #>pool_p0
        sta     @o0+2
        sta     @w0+2
        lda     cm_p
        clc
        adc     #<pool_p1
        sta     @o1+1
        sta     @w1+1
        lda     cm_p+1
        adc     #>pool_p1
        sta     @o1+2
        sta     @w1+2
        ldx     cm_j
        lda     cm_b0,x
@o0:    ora     $FFFF
@w0:    sta     $FFFF
        lda     cm_b1,x
@o1:    ora     $FFFF
@w1:    sta     $FFFF
@nb1:   ldx     cm_j
@nb:    inc     cm_cx
        inx
        cpx     cm_nb
        beq     :+              ; (one more byte than the picture's: the shift)
        bcs     :++
:       jmp     @byte
:       inc     cm_yy
        dec     cm_h
        beq     @done
        jmp     @row
@done:  rts
@get:
@d:     lda     $FFFF
        inc     @d+1
        bne     :+
        inc     @d+2
:       rts

; the pool pattern of cell cm_cx in the row at cm_c (a new one if it has
; none) -> A (0 .. NPOOL-1), carry clear; carry set: a cell of something
; else (text, the miner), or the pool is full
cm_cell:lda     cm_c
        ora     cm_cx
        clc
        adc     #<l2n
        sta     @r+1
        sta     @w+1
        lda     cm_c+1
        adc     #>l2n
        sta     @r+2
        sta     @w+2
@r:     lda     $FFFF
        beq     @new
        tax
        lda     pool_ix,x       ; (one of the pool's?)
        beq     @no
        sec
        sbc     #1
        clc
        rts
@new:   ldx     #0              ; a free one
@f:     lda     pool_used,x
        beq     @got
        inx
        cpx     #NPOOL
        bne     @f
@no:    sec
        rts
@got:   lda     #1
        sta     pool_used,x
        sta     font_gone
        lda     cm_ps
        ora     #$10            ; (see-through)
        sta     pool_at,x
        lda     pool_pat,x
@w:     sta     $FFFF
        txa                     ; its 16 bytes cleared
        pha
        lda     #0
        sta     cm_p+1
        txa
        asl
        rol     cm_p+1
        asl
        rol     cm_p+1
        asl
        rol     cm_p+1
        clc
        adc     #<pool_p0
        sta     @z0+1
        lda     cm_p+1
        adc     #>pool_p0
        sta     @z0+2
        lda     @z0+1
        clc
        adc     #<(pool_p1 - pool_p0)
        sta     @z1+1
        lda     @z0+2
        adc     #>(pool_p1 - pool_p0)
        sta     @z1+2
        ldy     #7
        lda     #0
@z0:    sta     $FFFF,y
@z1:    sta     $FFFF,y
        dey
        bpl     @z0
        pla
        clc
        rts

; layer 2's cells ur_x0..ur_x1, ur_y0..ur_y1 to the screen: names, and the
; patterns (and attributes) of the pool's
upload: lda     ur_y0
        sta     up_y
@row:   jsr     sfx_poll
        lda     #0              ; the row's first cell
        sta     up_c+1
        lda     up_y
        lsr
        ror     up_c+1
        lsr
        ror     up_c+1
        lsr
        ror     up_c+1
        sta     tmp
        lda     up_c+1
        ora     ur_x0
        sta     up_c
        lda     tmp
        sta     up_c+1
        lda     up_c            ; the names
        clc
        adc     #<V_NAME2
        pha
        lda     up_c+1
        adc     #>V_NAME2
        tay
        pla
        jsr     vdp_waddr
        lda     up_c
        clc
        adc     #<l2n
        sta     @n+1
        sta     @p+1
        lda     up_c+1
        adc     #>l2n
        sta     @n+2
        sta     @p+2
        ldx     #0
        ldy     ur_x0
@n:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        iny
        cpy     ur_x1
        beq     @n
        bcc     @n
        ldx     #0              ; the pool's patterns there
        ldy     ur_x0
@p:     lda     $FFFF,x
        stx     up_x
        tax
        lda     pool_ix,x
        beq     @np0
        txa
        ldx     up_x
        sty     up_xx
        jsr     up_pat
        ldy     up_xx
@np0:   ldx     up_x
@np:    inx
        iny
        cpy     ur_x1
        beq     @p
        bcc     @p
        lda     up_y
        cmp     ur_y1
        bcs     @done
        inc     up_y
        jmp     @row
@done:  rts

; pattern A (a pool one) to VRAM: its 2 x 8 bytes and its attribute
up_pat: sta     up_n
        tax
        lda     pool_ix,x
        tax
        dex
        lda     pool_at,x
        pha
        lda     #0
        sta     up_s+1
        txa
        asl
        rol     up_s+1
        asl
        rol     up_s+1
        asl
        rol     up_s+1
        sta     up_s
        clc
        adc     #<pool_p0
        sta     @r0+1
        lda     up_s+1
        adc     #>pool_p0
        sta     @r0+2
        lda     up_s
        clc
        adc     #<pool_p1
        sta     @r1+1
        lda     up_s+1
        adc     #>pool_p1
        sta     @r1+2
        lda     #0              ; VRAM: pattern * 8
        sta     up_s+1
        lda     up_n
        asl
        rol     up_s+1
        asl
        rol     up_s+1
        asl
        rol     up_s+1
        sta     up_s
        ldy     up_s+1          ; (V_TP0 = 0)
        jsr     vdp_waddr
        ldx     #0
@r0:    lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #8
        bne     @r0
        lda     up_s
        ldy     up_s+1
        tya
        clc
        adc     #>V_TP1
        tay
        lda     up_s
        jsr     vdp_waddr
        ldx     #0
@r1:    lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #8
        bne     @r1
        lda     up_n            ; the attribute
        ldy     #>V_ATT2
        jsr     vdp_waddr
        pla
        sta     VDP_DATA
        rts

; the cells item X (kind A, 1-6) covers -> ur_x0..ur_x1, ur_y0..ur_y1
item_rect:
        sec
        sbc     #1
        tay
        lda     it_x,x
        jsr     scr_x
        sta     tmp
        lsr
        lsr
        lsr
        sta     ur_x0
        lda     tmp
        clc
        adc     cp_w,y
        bcc     :+
        lda     #0              ; (past the edge: the last column)
:       sbc     #0              ; (carry clear: - 1)
        lsr
        lsr
        lsr
        sta     ur_x1
        lda     it_y,x
        asl
        clc
        adc     #8
        sta     tmp
        lsr
        lsr
        lsr
        sta     ur_y0
        lda     tmp
        clc
        adc     cp_h,y
        sec
        sbc     #1
        lsr
        lsr
        lsr
        sta     ur_y1
        rts

; item X (kind ei_k) is taken away (it_k X already 0): its cells cleared,
; and what shares those cells drawn again
erase_item:
        stx     ei_i
        lda     ei_k
        jsr     item_rect
        lda     ur_x0
        sta     er_x0
        lda     ur_x1
        sta     er_x1
        lda     ur_y0
        sta     er_y0
        lda     ur_y1
        sta     er_y1
        sta     tmp4
@row:   lda     #0              ; row tmp4's cells er_x0..er_x1
        sta     tmp+1
        lda     tmp4
        lsr
        ror     tmp+1
        lsr
        ror     tmp+1
        lsr
        ror     tmp+1
        tay
        lda     tmp+1
        clc
        adc     #<l2n
        sta     @r+1
        sta     @w+1
        tya
        adc     #>l2n
        sta     @r+2
        sta     @w+2
        ldx     er_x0
@c:
@r:     lda     $FFFF,x
        tay
        lda     pool_ix,y
        beq     @n
        tay
        lda     #0
        sta     pool_used-1,y
@w:     sta     $FFFF,x
@n:     inx
        cpx     er_x1
        beq     @c
        bcc     @c
        dec     tmp4
        lda     tmp4
        cmp     er_y0
        bcs     @row
        ldx     #NITEM-1        ; the others there: again
@o:     stx     er_j
        lda     it_k,x
        beq     @on
        cmp     #K_GOPHER
        beq     @on
        jsr     item_rect
        lda     ur_x1
        cmp     er_x0
        bcc     @on
        lda     er_x1
        cmp     ur_x0
        bcc     @on
        lda     ur_y1
        cmp     er_y0
        bcc     @on
        lda     er_y1
        cmp     ur_y0
        bcc     @on
        ldx     er_j
        jsr     comp_item
@on:    ldx     er_j
        dex
        bpl     @o
        lda     er_x0           ; to the screen
        sta     ur_x0
        lda     er_x1
        sta     ur_x1
        lda     er_y0
        sta     ur_y0
        lda     er_y1
        sta     ur_y1
        jsr     upload
        ldx     ei_i
        rts

; ---- sprites ----------------------------------------------------------------------
; the moving things, as sprites, and the winch; then the attribute table
frame_draw:
        jsr     draw_winch
        lda     #0
        sta     ns
        lda     hst             ; the laser pointer: where it would go
        bne     @nl
        jsr     laser_on
        beq     @nl
        jsr     draw_laser
        lda     ls_hit
        beq     @nl
        lda     tpx             ; the ring where it would grab
        sec
        sbc     #2
        jsr     scr_x
        sta     ap_x
        lda     #0
        sta     ap_x+1
        lda     tpy
        sec
        sbc     #2
        asl
        clc
        adc     #8
        sta     ap_y
        lda     #SP_TARGET
        jsr     add_pic
@nl:    lda     hx              ; the claw, at the rope's end
        jsr     scr_x
        sta     ap_x
        sta     rp_x1
        lda     #0
        sta     ap_x+1
        lda     hy
        asl
        clc
        adc     #8
        sta     ap_y
        sta     rp_y1
        ldy     ang+1
        lda     dir_claw,y
        ldx     carry
        beq     @cl
        clc
        adc     #NCLAW
@cl:    jsr     add_pic
        lda     carry           ; what it holds
        beq     @nc
        jsr     held_at
        lda     ox
        jsr     scr_xs
        lda     oy
        asl
        clc
        adc     #8
        sta     ap_y
        lda     cspr
        jsr     add_pic
@nc:    ldx     #NITEM-1        ; the gophers
@g:     lda     it_k,x
        cmp     #K_GOPHER
        bne     @gn
        stx     fd_i
        lda     it_x,x
        jsr     scr_x
        sta     ap_x
        lda     #0
        sta     ap_x+1
        lda     it_y,x
        asl
        clc
        adc     #8
        sta     ap_y
        jsr     gopher_pic
        jsr     add_pic
        ldx     fd_i
@gn:    dex
        bpl     @g
        ldx     #NEXP-1         ; the bangs
@e:     lda     ex_t,x
        beq     @en
        stx     fd_i
        and     #2
        lsr
        clc
        adc     #SP_BOOM1
        pha
        lda     ex_x,x
        jsr     scr_xs
        ldx     fd_i
        lda     ex_y,x
        asl
        clc
        adc     #8
        sta     ap_y
        pla
        jsr     add_pic
        ldx     fd_i
@en:    dex
        bpl     @e
        jsr     rope_spr        ; the rope
        lda     hst
        bne     @nl2
        jsr     laser_on
        beq     @nl2
        jsr     laser_spr
@nl2:   jmp     put_sat

; A (0..255, a game x) -> the screen x: 8 + x + x / 2 (to 247)
scr_x:  sta     tmp
        lsr
        clc
        adc     tmp
        adc     #8
        rts

; A, a game x that may be a little below 0 (>= $E0) -> ap_x (16 bits)
scr_xs: cmp     #$E0
        bcs     @neg
        jsr     scr_x
        sta     ap_x
        lda     #0
        rol                     ; (carry: past 255)
        sta     ap_x+1
        rts
@neg:   sta     tmp             ; 8 + x + x / 2, x < 0
        sec
        ror
        clc
        adc     tmp
        clc
        adc     #8
        sta     ap_x
        lda     #$FF
        adc     #0
        sta     ap_x+1
        rts

; picture A (an SP_ number) at ap_x (16 bits), ap_y: its parts as sprites
add_pic:tax
        lda     pk_lo,x
        sta     @d+1
        lda     pk_hi,x
        sta     @d+2
        jsr     @get
        sta     ap_n
        beq     @r
@l:     jsr     @get            ; dx (signed)
        sta     tmp
        ldy     #0
        cmp     #$80
        bcc     :+
        dey
:       clc
        adc     ap_x
        sta     as_x
        tya
        adc     ap_x+1
        sta     as_x+1
        jsr     @get            ; dy
        clc
        adc     ap_y
        sta     as_y
        jsr     @get            ; the part
        sta     as_p
        jsr     @get            ; the attribute
        sta     as_a
        jsr     add_spr
        dec     ap_n
        bne     @l
@r:     rts
@get:
@d:     lda     $FFFF
        inc     @d+1
        bne     :+
        inc     @d+2
:       rts

; a sprite: part as_p (its pattern loaded into a slot if not there yet),
; at as_x (16 bits), as_y, attribute as_a; or a slot of its own: as_p =
; $80 | slot
add_spr:lda     ns
        cmp     #32
        bcs     @r
        lda     as_x+1          ; on the screen?
        beq     @x
        cmp     #$FF
        bne     @r
        lda     as_x
        cmp     #$E0
        bcc     @r
        adc     #31             ; (carry set: + 32) early clock
        sta     as_x
        lda     as_a
        ora     #$80
        sta     as_a
@x:     lda     as_p
        bmi     @own
        jsr     slot_of
        bcs     @r
        jmp     @put
@own:   and     #$1F
@put:   asl                     ; the pattern name: slot * 4
        asl
        pha
        lda     ns
        asl
        asl
        tax
        lda     as_y
        sec
        sbc     #1
        cmp     #$D0            ; ($D0 would end the table)
        bne     :+
        lda     #$CF
:       sta     sat,x
        lda     as_x
        sta     sat+1,x
        pla
        sta     sat+2,x
        lda     as_a
        sta     sat+3,x
        inc     ns
@r:     rts

; part A -> the slot holding it (loaded now if none does) in A, carry clear;
; carry set: no slot free
slot_of:sta     so_p
        ldx     #NSLOT-1
@f:     lda     sl_part,x
        cmp     so_p
        beq     @hit
        dex
        bpl     @f
        ldx     #NSLOT-1        ; a slot not used this frame or the last
@e:     lda     sl_used,x
        cmp     frame
        beq     @en
        clc
        adc     #1
        cmp     frame
        bne     @take
@en:    dex
        bpl     @e
        sec
        rts
@take:  stx     so_s
        lda     so_p
        sta     sl_part,x
        jsr     load_part
        ldx     so_s
@hit:   lda     frame
        sta     sl_used,x
        txa
        clc
        rts

; part so_p into slot so_s: spr_parts + 64 part -> V_SP0 + 32 slot (32
; bytes), V_SP1 + 32 slot (32)
load_part:
        lda     so_p
        sta     tmp
        lda     #0
        sta     tmp+1
        ldy     #6
@m:     asl     tmp
        rol     tmp+1
        dey
        bne     @m
        lda     tmp
        clc
        adc     #<spr_parts
        sta     lp_src
        lda     tmp+1
        adc     #>spr_parts
        sta     lp_src+1
        lda     so_s
        ; fall through

; 64 bytes at lp_src into sprite slot A
slot_up:sta     tmp
        lda     lp_src
        sta     @a+1
        sta     @b+1
        lda     lp_src+1
        sta     @a+2
        sta     @b+2
        lda     #0
        sta     tmp+1
        lda     tmp
        ldy     #5
@m:     asl
        rol     tmp+1
        dey
        bne     @m
        sta     tmp
        lda     tmp+1
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
        lda     tmp+1
        clc
        adc     #>V_SP1
        tay
        lda     tmp
        jsr     vdp_waddr
@b:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #64
        bne     @b
        rts

; the sprite attribute table: the sprites made this frame, then the end
put_sat:lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     ns
        asl
        asl
        tay
        ldx     #0
        cpy     #0
        beq     @end
@l:     lda     sat,x
        sta     VDP_DATA
        inx
        dey
        bne     @l
@end:   lda     #$D0
        sta     VDP_DATA
        rts

; ---- the rope and the laser ----------------------------------------------------------
; the direction: rd_d = 0 .. 32 from straight down, rd_left = 1 to the left
rope_dir:
        lda     ang+1
        sec
        sbc     #(NDIR - 1) / 2
        ldx     #0
        bcs     @r
        eor     #$FF
        adc     #1
        inx
@r:     sta     rd_d
        stx     rd_left
        rts

; draw a line of 14 pixels (rope: A = 0) or two dots (laser: A = 1) for
; direction rd_d into lp_buf (64 bytes), from (1.5, 1.5)
make_pat:
        sta     mp_kind
        ldx     #63
        lda     #0
@c:     sta     lp_buf,x
        dex
        bpl     @c
        lda     #$80            ; x, y = 1.5 (8.8)
        sta     mp_x
        sta     mp_y
        lda     #1
        sta     mp_x+1
        sta     mp_y+1
        lda     #0
        sta     mp_t
@l:     lda     mp_kind
        bne     @dot
        lda     mp_x+1          ; the rope: a light pixel and a dark one
        ldy     mp_y+1          ; beside it
        ldx     #2
        jsr     setpix
        ldy     rd_d            ; (steep: to its right; else below)
        lda     mp_x+1
        ldx     mp_y+1
        cpy     #20
        bcs     @low
        clc
        adc     #1
        jmp     @s
@low:   inx
@s:     stx     tmp3
        ldy     tmp3
        ldx     #1
        jsr     setpix_or
        jmp     @nx
@dot:   lda     mp_t            ; the laser: 2 x 2 dots at 0 and 7
        beq     @d
        cmp     #7
        bne     @nx
@d:     lda     mp_x+1
        ldy     mp_y+1
        ldx     #3
        jsr     setpix
        lda     mp_x+1
        clc
        adc     #1
        ldy     mp_y+1
        ldx     #2
        jsr     setpix
        lda     mp_x+1
        ldy     mp_y+1
        iny
        ldx     #2
        jsr     setpix
        lda     mp_x+1
        clc
        adc     #1
        ldy     mp_y+1
        iny
        ldx     #1
        jsr     setpix
@nx:    ldy     rd_d
        clc
        lda     mp_x
        adc     rd_ux,y
        sta     mp_x
        lda     mp_x+1
        adc     rd_ux_hi,y
        sta     mp_x+1
        clc
        lda     mp_y
        adc     rd_uy,y
        sta     mp_y
        lda     mp_y+1
        adc     rd_uy_hi,y
        sta     mp_y+1
        inc     mp_t
        lda     mp_t
        cmp     #14
        beq     :+
        jmp     @l
:       rts

; pixel A, Y (0..15) of lp_buf = X (1-3); setpix_or: only where empty
setpix_or:
        stx     sp_v
        jsr     pix_at
        lda     lp_buf,x
        ora     lp_buf+32,x
        and     sp_m
        bne     @r
        jmp     pix_set
@r:     rts
setpix: stx     sp_v
        jsr     pix_at
pix_set:lda     sp_m            ; clear, then set the planes
        eor     #$FF
        and     lp_buf,x
        sta     lp_buf,x
        lda     sp_m
        eor     #$FF
        and     lp_buf+32,x
        sta     lp_buf+32,x
        lda     sp_v
        lsr
        bcc     :+
        lda     lp_buf,x
        ora     sp_m
        sta     lp_buf,x
:       lda     sp_v
        and     #2
        beq     :+
        lda     lp_buf+32,x
        ora     sp_m
        sta     lp_buf+32,x
:       rts
; -> X = the byte (TMS 16 x 16 order), sp_m its bit
pix_at: cmp     #16
        bcs     @off
        cpy     #16
        bcs     @off
        sty     tmp3
        tax
        and     #7
        tay
        lda     bitmask_l,y
        sta     sp_m
        txa
        and     #8
        asl
        ora     tmp3
        tax
        rts
@off:   pla                     ; (outside: nothing, and no return here)
        pla
        rts

; the rope: from the pulley to the claw, RSTEP pixels a sprite
rope_spr:
        jsr     rope_dir
        lda     rd_d
        cmp     rope_md
        beq     @have
        sta     rope_md
        lda     #0
        jsr     make_pat
        lda     #<lp_buf
        sta     lp_src
        lda     #>lp_buf
        sta     lp_src+1
        lda     #SL_ROPE
        jsr     slot_up
@have:  lda     #$80 | SL_ROPE
        sta     as_p
        lda     #PS_ROPE
        sta     sg_a
        lda     #PIV_SX
        sta     sg_x0
        lda     #PIV_SY
        sta     sg_y0
        lda     rp_x1
        sta     sg_x1
        lda     rp_y1
        sta     sg_y1
        lda     #1              ; (and the last one ends at the claw)
        sta     sg_end
        jmp     segments

; the laser's dots: from ls_x0, ls_y0 to ls_x1, ls_y1 (screen)
laser_spr:
        lda     ls_n            ; (no dots: nothing)
        beq     @r
        jsr     rope_dir
        lda     rd_d
        cmp     laser_md
        beq     @have
        sta     laser_md
        lda     #1
        jsr     make_pat
        lda     #<lp_buf
        sta     lp_src
        lda     #>lp_buf
        sta     lp_src+1
        lda     #SL_LASER
        jsr     slot_up
@have:  lda     #$80 | SL_LASER
        sta     as_p
        lda     #PS_BOOM
        sta     sg_a
        lda     ls_x0
        sta     sg_x0
        lda     ls_y0
        sta     sg_y0
        lda     ls_x1
        sta     sg_x1
        lda     ls_y1
        sta     sg_y1
        lda     #0
        sta     sg_end
        jmp     segments
@r:     rts

; sprites of pattern as_p along the line sg_x0, sg_y0 -> sg_x1, sg_y1 in
; direction rd_d / rd_left, a step of RSTEP pixels; sg_end = 1: one more,
; ending at the end
segments:
        lda     #$80            ; position (8.8): the start + 0.5
        sta     sg_x
        sta     sg_y
        lda     sg_x0
        sta     sg_x+1
        lda     sg_y0
        sta     sg_y+1
        lda     #16
        sta     sg_k
@l:     ldy     rd_d            ; the next step's end: still short of the end?
        lda     sg_y
        clc
        adc     rs_y,y
        lda     sg_y+1
        adc     rs_y_hi,y
        cmp     sg_y1
        bcc     :+
        jmp     @last           ; (down: past the end's y)
:
        lda     rd_d
        cmp     #24             ; (nearly across: x too)
        bcc     @ok
        lda     rd_left
        bne     @lx
        lda     sg_x
        clc
        adc     rs_x,y
        lda     sg_x+1
        adc     rs_x_hi,y
        cmp     sg_x1
        bcs     @last
        bcc     @ok
@lx:    lda     sg_x
        sec
        sbc     rs_x,y
        lda     sg_x+1
        sbc     rs_x_hi,y
        bcc     @last           ; (gone below 0)
        cmp     sg_x1
        bcc     @last
        beq     @last
@ok:    lda     sg_x+1
        ldx     sg_y+1
        jsr     @one
        ldy     rd_d            ; a step on
        lda     sg_y
        clc
        adc     rs_y,y
        sta     sg_y
        lda     sg_y+1
        adc     rs_y_hi,y
        sta     sg_y+1
        lda     rd_left
        bne     @sl
        lda     sg_x
        clc
        adc     rs_x,y
        sta     sg_x
        lda     sg_x+1
        adc     rs_x_hi,y
        sta     sg_x+1
        jmp     @nk
@sl:    lda     sg_x
        sec
        sbc     rs_x,y
        sta     sg_x
        lda     sg_x+1
        sbc     rs_x_hi,y
        sta     sg_x+1
@nk:    dec     sg_k
        beq     :+
        jmp     @l
:       rts
@last:  lda     sg_end          ; the last: a step back from the end
        beq     @r
        ldy     rd_d
        lda     sg_y1
        sec
        sbc     rs_y_hi,y
        tax
        cpx     sg_y0           ; (shorter than a step: from the start)
        bcs     :+
        ldx     sg_y0
        lda     sg_x0
        jmp     @one
:       lda     rd_left
        bne     @ll
        lda     sg_x1
        sec
        sbc     rs_x_hi,y
        jmp     @one
@ll:    lda     sg_x1
        clc
        adc     rs_x_hi,y
        ; fall through
; a sprite with its line's start at screen A, X
@one:   stx     as_y
        ldx     #0
        ldy     rd_left
        bne     @fl
        sec                     ; (the line starts at pixel 1)
        sbc     #1
        bcs     :+
        dex
:       sta     as_x
        stx     as_x+1
        lda     sg_a
        sta     as_a
        jmp     add_spr
@fl:    sec                     ; mirrored: at pixel 14
        sbc     #14
        bcs     :+
        dex
:       sta     as_x
        stx     as_x+1
        lda     sg_a
        ora     #$40
        sta     as_a
        jmp     add_spr
@r:     rts
