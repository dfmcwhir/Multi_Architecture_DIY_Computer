; ============================================================================
; view.s - DOOM2's view: walls, textures and things at the screen's own
; resolution (included by doom2.s)
;
; The view is 120 columns of 2 pixels by 144 lines (cell columns 1-30, rows
; 0-17 of the Graphics II screen).  The name table is laid out so that each
; cell column's lines are together in VRAM: rows 0-7 and 8-15 use names
; col * 8 + (row & 7) (64 bytes of patterns a cell column in each third),
; rows 16-17 names col * 2 + (row - 16) (16 bytes in the last third).
; Each cell column (4 columns) is built in pb (patterns), cb (colours) and
; sent to the screen whole.
; ============================================================================

; ---- the rays: 120 columns ---------------------------------------------------------
; every third column is cast (and the last); the two between are worked out
; from those two if they hit the same face of the same block, else cast too
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
        ldx     #0
@c:     stx     col
        jsr     sfx_poll
        jsr     cast_ray
        lda     col
        clc
        adc     #3
        tax
        cpx     #COLS-1
        bcc     @c
        ldx     #COLS-1
        stx     col
        jsr     cast_ray
        ldx     #0              ; the columns between
@g:     stx     ga
        txa
        clc
        adc     #3
        cmp     #COLS
        bcc     :+
        lda     #COLS-1
:       sta     gb
        tay
        lda     c_mplo,x        ; the same face?
        cmp     c_mplo,y
        bne     @cast
        lda     c_mphi,x
        cmp     c_mphi,y
        bne     @cast
        lda     c_pidx,x
        eor     c_pidx,y
        and     #$FC
        bne     @cast
        lda     gb
        sec
        sbc     ga
        cmp     #3
        beq     @two
        jsr     interp_mid      ; (one column between)
        jmp     @next
@two:   jsr     interp_two
        jmp     @next
@cast:  ldx     ga
        inx
        stx     col
        jsr     cast_ray
        ldx     ga
        inx
        inx
        cpx     gb
        bcs     @next
        stx     col
        jsr     cast_ray
@next:  ldx     ga
        inx
        inx
        inx
        cpx     #COLS-1
        bcc     @g
        rts

; column ga + 1 = halfway between ga and gb (= ga + 2)
interp_mid:
        ldx     ga
        ldy     gb
        lda     c_hgt,x
        clc
        adc     c_hgt,y
        ror
        sta     c_hgt+1,x
        lda     c_u,x
        clc
        adc     c_u,y
        ror
        sta     c_u+1,x
        lda     zb_lo,x
        clc
        adc     zb_lo,y
        sta     tmp
        lda     zb_hi,x
        adc     zb_hi,y
        ror
        sta     zb_hi+1,x
        lda     tmp
        ror
        sta     zb_lo+1,x
        jmp     copy_face

; columns ga + 1, ga + 2: a third and two thirds of the way to gb
interp_two:
        ldx     ga
        ldy     gb
        lda     c_hgt,x         ; h: (2a + b) / 3, (a + 2b) / 3
        sta     ia
        lda     c_hgt,y
        sta     ib
        jsr     thirds
        sta     c_hgt+1,x
        tya
        sta     c_hgt+2,x
        ldy     gb
        lda     c_u,x           ; the texture place
        sta     ia
        lda     c_u,y
        sta     ib
        jsr     thirds
        sta     c_u+1,x
        tya
        sta     c_u+2,x
        ldy     gb
        ; z: (3a + b) / 4 and (a + 3b) / 4
        lda     zb_lo,x
        clc
        adc     zb_lo,y
        sta     tmp
        lda     zb_hi,x
        adc     zb_hi,y
        sta     tmp2            ; a + b
        lda     zb_lo,x
        asl
        sta     tmp3
        lda     zb_hi,x
        rol
        sta     tmp4            ; 2a
        lda     tmp
        clc
        adc     tmp3
        sta     tmp3
        lda     tmp2
        adc     tmp4
        lsr
        ror     tmp3
        lsr
        ror     tmp3
        sta     zb_hi+1,x
        lda     tmp3
        sta     zb_lo+1,x
        lda     zb_lo,y
        asl
        sta     tmp3
        lda     zb_hi,y
        rol
        sta     tmp4            ; 2b
        lda     tmp
        clc
        adc     tmp3
        sta     tmp3
        lda     tmp2
        adc     tmp4
        lsr
        ror     tmp3
        lsr
        ror     tmp3
        sta     zb_hi+2,x
        lda     tmp3
        sta     zb_lo+2,x
        jsr     copy_face
        inx
        ; fall through
; column X + 1 shows the same face as column X
copy_face:
        lda     c_pidx,x
        sta     c_pidx+1,x
        lda     c_mplo,x
        sta     c_mplo+1,x
        lda     c_mphi,x
        sta     c_mphi+1,x
        rts

; ia, ib -> A = (2 ia + ib) / 3 = ia + d / 3, Y = (ia + 2 ib) / 3 = ib - d / 3
; (d = ib - ia; keeps X)
thirds: lda     ib
        sec
        sbc     ia
        bcc     @neg
        tay
        lda     d3_0,y
        sta     tmp2
        lda     ia
        clc
        adc     tmp2
        pha
        lda     ib
        sec
        sbc     tmp2
        tay
        pla
        rts
@neg:   eor     #$FF
        adc     #1
        tay
        lda     d3_0,y
        sta     tmp2
        lda     ia
        sec
        sbc     tmp2
        pha
        lda     ib
        clc
        adc     tmp2
        tay
        pla
        rts
; A / 3 (A = 0..255)
div3:   tay
        lda     d3_0,y
        rts

; ---- the view, cell column by cell column --------------------------------------
draw_view:
        jsr     things_prep
        ldx     #0              ; pb, cb: the ceiling and floor
@bg:    lda     bg_pat,x
        sta     pb,x
        lda     bg_col,x
        sta     cb,x
        inx
        cpx     #VH
        bne     @bg
        lda     #VH             ; (nothing to put back)
        sta     dmin
        lda     #0
        sta     dmax
        sta     vx
@l:     jsr     sfx_poll
        jsr     build_cell
        jsr     add_textures
        lda     nvis
        beq     :+
        jsr     add_things
:       jsr     upload_cell
        inc     vx
        lda     vx
        cmp     #30
        bne     @l
        rts

; pb, cb for cell column vx: the last one's lines dmin..dmax back to the
; ceiling and floor, then the walls: between the 8 places where a column's
; wall starts or ends, the same columns show wall: a run of one byte
build_cell:
        lda     vx
        asl
        asl
        sta     c0
        tax
        lda     #0
        sta     hbest
        ldy     #0
@j:     lda     c_hgt,x         ; tops and bottoms
        cmp     hbest           ; (the nearest gives the colour)
        bcc     :+
        sta     hbest
        stx     cbest
:       lsr
        sta     tmp
        lda     #HORIZON
        sec
        sbc     tmp
        sta     cy0,y
        sta     bp,y
        lda     c_hgt,x
        clc
        adc     cy0,y
        sta     cy1,y
        sta     bp+4,y
        inx
        iny
        cpy     #4
        bne     @j
        ldx     cbest
        ldy     c_pidx,x
        lda     wallcol,y
        ora     #C_BLACK
        sta     fgc
        ldx     #1              ; sort the 8 places (insertion)
@s1:    lda     bp,x
        sta     tmp3
        stx     tmp
@s2:    dex
        bmi     @s3
        lda     bp,x
        cmp     tmp3
        bcc     @s3
        beq     @s3
        sta     bp+1,x
        jmp     @s2
@s3:    lda     tmp3
        sta     bp+1,x
        ldx     tmp
        inx
        cpx     #8
        bne     @s1
        ldx     dmin            ; the last cell's lines back to the ceiling and
        lda     dmax            ; floor, outside this cell's walls
        cmp     bp
        bcc     :+
        lda     bp
:       sta     l1
        jsr     restore
        ldx     bp+7
        cpx     dmin
        bcs     :+
        ldx     dmin
:       lda     dmax
        sta     l1
        jsr     restore
        lda     bp              ; the lines changed: bp(0) .. bp(7)
        sta     dmin
        lda     bp+7
        sta     dmax
        ldx     #0              ; each run bp(k) .. bp(k+1)
@run:   stx     tk
        lda     bp,x
        cmp     bp+1,x
        bcs     @rn             ; (empty)
        sta     l0
        lda     bp+1,x
        sta     l1
        ldx     l0              ; the columns showing wall there
        lda     #0
        cpx     cy0
        bcc     :+
        cpx     cy1
        bcs     :+
        ora     #$C0
:       cpx     cy0+1
        bcc     :+
        cpx     cy1+1
        bcs     :+
        ora     #$30
:       cpx     cy0+2
        bcc     :+
        cpx     cy1+2
        bcs     :+
        ora     #$0C
:       cpx     cy0+3
        bcc     :+
        cpx     cy1+3
        bcs     :+
        ora     #$03
:       cmp     #0
        beq     @rn             ; (none: the background, already there)
        ldx     l0
        ldy     l1
        jsr     pfill
        lda     fgc
        ldx     l0
        ldy     l1
        jsr     cfill
@rn:    ldx     tk
        inx
        cpx     #7
        bne     @run
        rts

; pb, cb lines X .. l1 - 1 back to the ceiling and floor
restore:cpx     l1
        bcs     @r
@l:     lda     bg_pat,x
        sta     pb,x
        lda     bg_col,x
        sta     cb,x
        inx
        cpx     l1
        bcc     @l
@r:     rts

; pb (pfill) or cb (cfill) lines X .. Y - 1 = A: into the chain of stores
pfill:  sta     pf_v
        lda     #<fill_pb
        sta     pf_b
        lda     #>fill_pb
        jmp     fill
cfill:  sta     pf_v
        lda     #<fill_cb
        sta     pf_b
        lda     #>fill_cb
fill:   sta     pf_b+1
        stx     pf_x
        tya                     ; the end: chain + 3 Y gets an RTS
        jsr     @a3
        sta     @rt+1
        sta     @un+1
        lda     tmp+1
        sta     @rt+2
        sta     @un+2
        lda     pf_x            ; the start: chain + 3 X
        jsr     @a3
        sta     @go+1
        lda     tmp+1
        sta     @go+2
        lda     #$60            ; RTS
@rt:    sta     $FFFF
        lda     pf_v
        jsr     @go
        lda     #$8D            ; STA abs again
@un:    sta     $FFFF
        rts
@go:    jmp     $FFFF
@a3:    sta     tmp             ; chain + 3 A -> A (lo), tmp+1 (hi)
        lda     #0
        sta     tmp+1
        lda     tmp
        asl
        rol     tmp+1
        clc
        adc     tmp
        bcc     :+
        inc     tmp+1
:       clc
        adc     pf_b
        pha
        lda     tmp+1
        adc     pf_b+1
        sta     tmp+1
        pla
        rts

fill_pb:
.repeat VH, L
        sta     pb + L
.endrepeat
        rts
fill_cb:
.repeat VH, L
        sta     cb + L
.endrepeat
        rts

; the textures' dark texels: for each column, its texture column's dark runs
; (v0, v1 in texels of 32) become lines y0 + v * h / 32.  Columns next to
; each other with the same texture column and height are done together.
add_textures:
        lda     #0
        sta     tj
@j:     lda     c0
        clc
        adc     tj
        tax
        lda     c_hgt,x
        cmp     #16             ; (too far for detail)
        bcs     :+
        jmp     @nj
:       sta     th
        jsr     tex_idx
        sta     tk
        tay
        lda     tx_lo,y
        sta     @r0+1
        sta     @r1+1
        lda     tx_hi,y
        sta     @r0+2
        sta     @r1+2
        ldy     tj
        lda     cy0,y
        sta     ty0
        lda     colmask,y
        sta     tmask
@mg:    lda     tj              ; the next column the same?
        cmp     #3
        bcs     @go
        lda     c0
        clc
        adc     tj
        tax
        lda     c_hgt+1,x
        cmp     th
        bne     @go
        inx
        jsr     tex_idx
        cmp     tk
        bne     @go
        inc     tj
        ldy     tj
        lda     tmask
        ora     colmask,y
        sta     tmask
        jmp     @mg
@go:    lda     tmask
        eor     #$FF
        sta     @and+1
        ldx     #0
@run:
@r0:    lda     $FFFF,x         ; v0 -> the line
        bpl     :+
        jmp     @nj
:
        sta     tmp
        clc
        adc     th
        tay
        lda     sq5,y
        sta     tmp2
        lda     th
        sec
        sbc     tmp
        tay                     ; (th >= 16 > v or not: |th - v|)
        bcs     :+
        eor     #$FF
        adc     #1
        tay
:       lda     tmp2
        sec
        sbc     sq5,y
        clc
        adc     ty0
        sta     l0
        inx
@r1:    lda     $FFFF,x         ; v1 -> the line
        sta     tmp
        clc
        adc     th
        tay
        lda     sq5,y
        sta     tmp2
        lda     th
        sec
        sbc     tmp
        tay
        bcs     :+
        eor     #$FF
        adc     #1
        tay
:       lda     tmp2
        sec
        sbc     sq5,y
        clc
        adc     ty0
        cmp     #VH
        bcc     :+
        lda     #VH
:       sta     l1
        inx
        stx     tmp3
        ldx     l0
        cpx     l1
        bcs     @rn
@cl:    lda     pb,x
@and:   and     #$FF
        sta     pb,x
        inx
        cpx     l1
        bcc     @cl
@rn:    ldx     tmp3
        jmp     @run
@nj:    inc     tj
        lda     tj
        cmp     #4
        bcs     :+
        jmp     @j
:       rts

; column X's texture column: style * 16 + u / 16 -> A
tex_idx:lda     c_pidx,x
        and     #$F8
        asl
        sta     tmp
        lda     c_u,x
        lsr
        lsr
        lsr
        lsr
        ora     tmp
        rts

colmask:.byte   $C0, $30, $0C, $03

; ---- things ---------------------------------------------------------------------------
; for each visible thing (far to near): its place and size on the screen
things_prep:
        ldx     #0
@t:     cpx     nvis
        bcc     :+
        rts
:       stx     vi
        ldy     v_t,x
        sty     ti
        lda     v_h,x
        sta     sh
        lda     t_type,y
        cmp     #T_MEDKIT       ; items: half size, from the horizon down
        bcc     @mon
        lsr     sh
        lda     #HORIZON
        jmp     @y
@mon:   lda     sh
        lsr
        sta     tmp
        lda     #HORIZON
        sec
        sbc     tmp
@y:     sta     th_y0,x
        clc
        adc     sh
        cmp     #VH+1
        bcc     :+
        lda     #VH
:       sta     th_y1,x
        lda     sh              ; too small to draw: none
        cmp     #3
        bcs     :+
        lda     #0
        sta     th_w,x
        jmp     @n
:       ldy     sh
        lda     rec_lo,y        ; texel rows per line
        sta     th_vs_lo,x
        lda     rec_hi,y
        sta     th_vs_hi,x
        lda     rcw_lo,y        ; texel columns per column
        sta     th_us_lo,x
        lda     rcw_hi,y
        sta     th_us_hi,x
        lda     sh              ; width: h / 3 columns
        jsr     div3
        bne     :+
        lda     #1
:       sta     th_w,x
        lsr
        sta     tmp
        lda     v_sx_lo,x       ; x0 = sx - w / 2
        sec
        sbc     tmp
        sta     th_x0_lo,x
        lda     v_sx_hi,x
        sbc     #0
        sta     th_x0_hi,x
        ldx     ti              ; its picture and colour
        jsr     thing_sprite
        tay
        ldx     vi
        lda     art_lo,y
        sta     th_art_lo,x
        lda     art_hi,y
        sta     th_art_hi,x
        ldy     ti
        lda     t_state,y
        cmp     #S_DEAD
        beq     @dead
        lda     t_type,y
        tay
        lda     thing_col,y
        jmp     @c
@dead:  lda     #C_BRICKD << 4
@c:     sta     th_col,x
@n:     ldx     vi
        inx
        jmp     @t

; the things in cell column vx, far to near, behind walls left out
add_things:
        lda     #0
        sta     vi
@t:     ldx     vi
        cpx     nvis
        bcc     :+
        rts
:       lda     th_w,x
        beq     @nt
        ; does it reach columns c0 .. c0 + 3?  x0 <= c0 + 3 and x0 + w > c0
        lda     th_x0_hi,x
        bmi     @lft            ; (starts off the left: reaches if x0 + w > c0)
        bne     @nt             ; (far right)
        lda     c0
        clc
        adc     #3
        cmp     th_x0_lo,x
        bcc     @nt
@lft:   lda     th_x0_lo,x
        clc
        adc     th_w,x
        sta     tmp
        lda     th_x0_hi,x
        adc     #0
        bmi     @nt
        bne     @in
        lda     c0
        cmp     tmp
        bcs     @nt
@in:    jsr     thing_cell
@nt:    inc     vi
        jmp     @t

; thing vi in cell column vx: which of the 4 columns show it (in front of
; the wall there), their texel columns; then its lines
thing_cell:
        lda     th_art_lo,x     ; the cover and body planes
        sta     ta_c
        lda     th_art_hi,x
        sta     ta_c+1
        lda     ta_c
        clc
        adc     #ART_H * 4
        sta     ta_b
        lda     ta_c+1
        adc     #0
        sta     ta_b+1
        lda     #0
        sta     any
        lda     #0
        sta     en+0
        lda     c0
        clc
        adc     #0
        sta     tmp             ; the column
        tay
        ldx     vi
        lda     v_d_hi,x        ; behind the wall there?
        cmp     zb_hi,y
        bcc     tv_vis0
        beq     :+
        jmp     tv_no0
:       lda     v_d_lo,x
        cmp     zb_lo,y
        bcc     tv_vis0
        jmp     tv_no0
tv_vis0:   lda     tmp             ; offset = column - x0 (0 .. w - 1)
        sec
        sbc     th_x0_lo,x
        sta     tmp2
        lda     #0
        sbc     th_x0_hi,x
        beq     :+
        jmp     tv_no0
:
        lda     tmp2
        cmp     th_w,x
        bcc     :+
        jmp     tv_no0
:
        lda     th_us_lo,x      ; u = offset * step >> 8
        sta     w_lo
        lda     th_us_hi,x
        sta     w_hi
        lda     tmp2
        jsr     mul8x16
        lda     r_hi
        beq     :+
        jmp     tv_no0
:
        lda     r_lo
        cmp     #ART_W
        bcc     :+
        lda     #ART_W - 1
:       pha
        lsr
        lsr
        lsr
        sta     tmp             ; its byte in a row
        pla
        and     #7
        tay
        lda     bit_hi,y
        sta     mk+0
        lda     ta_c
        clc
        adc     tmp
        sta     tcov0 + 1
        lda     ta_c+1
        adc     #0
        sta     tcov0 + 2
        lda     ta_b
        clc
        adc     tmp
        sta     tbod0 + 1
        lda     ta_b+1
        adc     #0
        sta     tbod0 + 2
        lda     mk+0
        sta     tcov0 + 4
        sta     tbod0 + 4
        lda     #1
        sta     en+0
        sta     any
tv_no0:
        lda     #0
        sta     en+1
        lda     c0
        clc
        adc     #1
        sta     tmp             ; the column
        tay
        ldx     vi
        lda     v_d_hi,x        ; behind the wall there?
        cmp     zb_hi,y
        bcc     tv_vis1
        beq     :+
        jmp     tv_no1
:       lda     v_d_lo,x
        cmp     zb_lo,y
        bcc     tv_vis1
        jmp     tv_no1
tv_vis1:   lda     tmp             ; offset = column - x0 (0 .. w - 1)
        sec
        sbc     th_x0_lo,x
        sta     tmp2
        lda     #0
        sbc     th_x0_hi,x
        beq     :+
        jmp     tv_no1
:
        lda     tmp2
        cmp     th_w,x
        bcc     :+
        jmp     tv_no1
:
        lda     th_us_lo,x      ; u = offset * step >> 8
        sta     w_lo
        lda     th_us_hi,x
        sta     w_hi
        lda     tmp2
        jsr     mul8x16
        lda     r_hi
        beq     :+
        jmp     tv_no1
:
        lda     r_lo
        cmp     #ART_W
        bcc     :+
        lda     #ART_W - 1
:       pha
        lsr
        lsr
        lsr
        sta     tmp             ; its byte in a row
        pla
        and     #7
        tay
        lda     bit_hi,y
        sta     mk+1
        lda     ta_c
        clc
        adc     tmp
        sta     tcov1 + 1
        lda     ta_c+1
        adc     #0
        sta     tcov1 + 2
        lda     ta_b
        clc
        adc     tmp
        sta     tbod1 + 1
        lda     ta_b+1
        adc     #0
        sta     tbod1 + 2
        lda     mk+1
        sta     tcov1 + 4
        sta     tbod1 + 4
        lda     #1
        sta     en+1
        sta     any
tv_no1:
        lda     #0
        sta     en+2
        lda     c0
        clc
        adc     #2
        sta     tmp             ; the column
        tay
        ldx     vi
        lda     v_d_hi,x        ; behind the wall there?
        cmp     zb_hi,y
        bcc     tv_vis2
        beq     :+
        jmp     tv_no2
:       lda     v_d_lo,x
        cmp     zb_lo,y
        bcc     tv_vis2
        jmp     tv_no2
tv_vis2:   lda     tmp             ; offset = column - x0 (0 .. w - 1)
        sec
        sbc     th_x0_lo,x
        sta     tmp2
        lda     #0
        sbc     th_x0_hi,x
        beq     :+
        jmp     tv_no2
:
        lda     tmp2
        cmp     th_w,x
        bcc     :+
        jmp     tv_no2
:
        lda     th_us_lo,x      ; u = offset * step >> 8
        sta     w_lo
        lda     th_us_hi,x
        sta     w_hi
        lda     tmp2
        jsr     mul8x16
        lda     r_hi
        beq     :+
        jmp     tv_no2
:
        lda     r_lo
        cmp     #ART_W
        bcc     :+
        lda     #ART_W - 1
:       pha
        lsr
        lsr
        lsr
        sta     tmp             ; its byte in a row
        pla
        and     #7
        tay
        lda     bit_hi,y
        sta     mk+2
        lda     ta_c
        clc
        adc     tmp
        sta     tcov2 + 1
        lda     ta_c+1
        adc     #0
        sta     tcov2 + 2
        lda     ta_b
        clc
        adc     tmp
        sta     tbod2 + 1
        lda     ta_b+1
        adc     #0
        sta     tbod2 + 2
        lda     mk+2
        sta     tcov2 + 4
        sta     tbod2 + 4
        lda     #1
        sta     en+2
        sta     any
tv_no2:
        lda     #0
        sta     en+3
        lda     c0
        clc
        adc     #3
        sta     tmp             ; the column
        tay
        ldx     vi
        lda     v_d_hi,x        ; behind the wall there?
        cmp     zb_hi,y
        bcc     tv_vis3
        beq     :+
        jmp     tv_no3
:       lda     v_d_lo,x
        cmp     zb_lo,y
        bcc     tv_vis3
        jmp     tv_no3
tv_vis3:   lda     tmp             ; offset = column - x0 (0 .. w - 1)
        sec
        sbc     th_x0_lo,x
        sta     tmp2
        lda     #0
        sbc     th_x0_hi,x
        beq     :+
        jmp     tv_no3
:
        lda     tmp2
        cmp     th_w,x
        bcc     :+
        jmp     tv_no3
:
        lda     th_us_lo,x      ; u = offset * step >> 8
        sta     w_lo
        lda     th_us_hi,x
        sta     w_hi
        lda     tmp2
        jsr     mul8x16
        lda     r_hi
        beq     :+
        jmp     tv_no3
:
        lda     r_lo
        cmp     #ART_W
        bcc     :+
        lda     #ART_W - 1
:       pha
        lsr
        lsr
        lsr
        sta     tmp             ; its byte in a row
        pla
        and     #7
        tay
        lda     bit_hi,y
        sta     mk+3
        lda     ta_c
        clc
        adc     tmp
        sta     tcov3 + 1
        lda     ta_c+1
        adc     #0
        sta     tcov3 + 2
        lda     ta_b
        clc
        adc     tmp
        sta     tbod3 + 1
        lda     ta_b+1
        adc     #0
        sta     tbod3 + 2
        lda     mk+3
        sta     tcov3 + 4
        sta     tbod3 + 4
        lda     #1
        sta     en+3
        sta     any
tv_no3:
        lda     any
        bne     :+
        rts
:       ldx     vi              ; its lines
        lda     th_col,x
        sta     tcol
        lda     th_vs_lo,x
        sta     tvs
        lda     th_vs_hi,x
        sta     tvs+1
        lda     #0
        sta     vacc
        sta     vacc+1
        lda     th_y0,x
        sta     tl
        cmp     dmin            ; (lines to put back after)
        bcs     :+
        sta     dmin
:       lda     th_y1,x
        sta     tl1
        cmp     dmax
        bcc     :+
        sta     dmax
:
tc_line:  lda     tl
        cmp     tl1
        bcc     :+
        rts
:       lda     vacc+1          ; the texel row: * 4 bytes
        cmp     #ART_H
        bcc     :+
        lda     #ART_H - 1
:       asl
        asl
        tay
        lda     #0
        sta     tmk
        sta     tbd
        lda     en+0
        beq     tl_s0
tcov0: lda     $FFFF,y
        and     #$FF
        beq     tl_s0
        lda     tmk
        ora     #$C0
        sta     tmk
tbod0: lda     $FFFF,y
        and     #$FF
        beq     tl_s0
        lda     tbd
        ora     #$C0
        sta     tbd
tl_s0:
        lda     en+1
        beq     tl_s1
tcov1: lda     $FFFF,y
        and     #$FF
        beq     tl_s1
        lda     tmk
        ora     #$30
        sta     tmk
tbod1: lda     $FFFF,y
        and     #$FF
        beq     tl_s1
        lda     tbd
        ora     #$30
        sta     tbd
tl_s1:
        lda     en+2
        beq     tl_s2
tcov2: lda     $FFFF,y
        and     #$FF
        beq     tl_s2
        lda     tmk
        ora     #$0C
        sta     tmk
tbod2: lda     $FFFF,y
        and     #$FF
        beq     tl_s2
        lda     tbd
        ora     #$0C
        sta     tbd
tl_s2:
        lda     en+3
        beq     tl_s3
tcov3: lda     $FFFF,y
        and     #$FF
        beq     tl_s3
        lda     tmk
        ora     #$03
        sta     tmk
tbod3: lda     $FFFF,y
        and     #$FF
        beq     tl_s3
        lda     tbd
        ora     #$03
        sta     tbd
tl_s3:
        lda     tmk
        beq     tc_nx
        ldx     tl              ; on the line: its body pixels in its colour;
        lda     tbd             ; the rest of the byte in the line's other
        sta     pb,x            ; colour: on a wall the wall's, else the dark
        cpx     bp
        bcc     tc_bg
        cpx     bp+7
        bcs     tc_bg
        lda     cb,x
        lsr
        lsr
        lsr
        lsr
        ora     tcol
        sta     cb,x
        jmp     tc_nx
tc_bg:  lda     cb,x
        and     #$0F
        ora     tcol
        sta     cb,x
tc_nx:    lda     vacc
        clc
        adc     tvs
        sta     vacc
        lda     vacc+1
        adc     tvs+1
        sta     vacc+1
        inc     tl
        jmp     tc_line


bit_hi: .byte   $80, $40, $20, $10, $08, $04, $02, $01

; ---- pb, cb to the screen: cell column vx + 1 ------------------------------------
upload_cell:
        lda     vx
        clc
        adc     #1
        sta     tmp             ; the cell column
        lsr                     ; * 64: lines 0-63 (third 0), 64-127 (third 1)
        lsr
        sta     tmp2
        lda     tmp
        asl
        asl
        asl
        asl
        asl
        asl
        sta     tmp3            ; (low byte)
        ldy     tmp2
        jsr     vdp_waddr
        ldx     #0
        jsr     @p64
        lda     tmp3
        ldy     tmp2
        iny                     ; (+ $800: 8 pages)
        tya
        clc
        adc     #7
        tay
        lda     tmp3
        jsr     vdp_waddr
        jsr     @p64
        lda     tmp             ; lines 128-143: $1000 + col * 16
        asl
        asl
        asl
        asl
        sta     tmp3
        lda     tmp
        lsr
        lsr
        lsr
        lsr
        clc
        adc     #$10
        tay
        lda     tmp3
        jsr     vdp_waddr
        jsr     @p16
        ; the colours: the same places + $2000
        lda     tmp
        asl
        asl
        asl
        asl
        asl
        asl
        sta     tmp3
        lda     tmp2
        clc
        adc     #$20
        tay
        lda     tmp3
        jsr     vdp_waddr
        ldx     #0
        jsr     @c64
        lda     tmp2
        clc
        adc     #$28
        tay
        lda     tmp3
        jsr     vdp_waddr
        jsr     @c64
        lda     tmp
        asl
        asl
        asl
        asl
        sta     tmp3
        lda     tmp
        lsr
        lsr
        lsr
        lsr
        clc
        adc     #$30
        tay
        lda     tmp3
        jsr     vdp_waddr
        jmp     @c16
@p64:   jsr     @p16
        jsr     @p16
        jsr     @p16
@p16:   .repeat 16
        lda     pb,x
        sta     VDP_DATA
        inx
        .endrepeat
        rts
@c64:   jsr     @c16
        jsr     @c16
        jsr     @c16
@c16:   .repeat 16
        lda     cb,x
        sta     VDP_DATA
        inx
        .endrepeat
        rts

; ---- the gun: sprites -------------------------------------------------------------------
; its picture's top left at x 96, y 80 (+ a bob while walking); the flash
; picture for gun_t frames after a shot
put_gun:
        lda     gun_t
        beq     @g0
        dec     gun_t
        lda     #<gun1_list
        ldy     #>gun1_list
        ldx     #GUN1_N
        bne     @go
@g0:    lda     #<gun0_list
        ldy     #>gun0_list
        ldx     #GUN0_N
@go:    sta     @rd+1
        sty     @rd+2
        stx     gn
        lda     mv_fwd          ; the bob: a step while walking
        ora     mv_strafe
        beq     @nb
        inc     bob
@nb:    lda     bob
        lsr
        and     #7
        tax
        lda     bob_x,x
        sta     gbx
        lda     bob_y,x
        sta     gby
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     #0
@s:     jsr     @rd             ; x, y, part, group
        sta     tmp
        jsr     @rd
        clc
        adc     #80 - 1
        adc     gby
        sta     VDP_DATA        ; y
        lda     tmp
        clc
        adc     #96
        adc     gbx
        sta     VDP_DATA        ; x
        jsr     @rd
        asl
        asl
        sta     VDP_DATA        ; the pattern: part * 4
        jsr     @rd
        sta     VDP_DATA        ; the colour group
        dec     gn
        bne     @s
        lda     #$D0
        sta     VDP_DATA
        rts
@rd:    lda     $FFFF,x
        inx
        rts
bob_x:  .byte   0, 1, 2, 1, 0, $FF, $FE, $FF
bob_y:  .byte   0, 1, 2, 1, 0, 1, 2, 1

; the gun's sprite patterns into VRAM (once): part k at V_SPR + 32 k (plane
; 0) and V_SPR + $400 + 32 k (plane 1)
load_gun:
        lda     #<V_SPR
        ldy     #>V_SPR
        jsr     vdp_waddr
        lda     #<gun_parts
        sta     @a+1
        lda     #>gun_parts
        sta     @a+2
        ldx     #NGUNPART
@p:     ldy     #0
@a:     lda     $FFFF,y
        sta     VDP_DATA
        iny
        cpy     #32
        bne     @a
        lda     @a+1
        clc
        adc     #64
        sta     @a+1
        bcc     :+
        inc     @a+2
:       dex
        bne     @p
        lda     #<(V_SPR + $400)
        ldy     #>(V_SPR + $400)
        jsr     vdp_waddr
        lda     #<(gun_parts + 32)
        sta     @b+1
        lda     #>(gun_parts + 32)
        sta     @b+2
        ldx     #NGUNPART
@q:     ldy     #0
@b:     lda     $FFFF,y
        sta     VDP_DATA
        iny
        cpy     #32
        bne     @b
        lda     @b+1
        clc
        adc     #64
        sta     @b+1
        bcc     :+
        inc     @b+2
:       dex
        bne     @q
        rts

hide_sprites:
        lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        rts
