; ============================================================================
; picotest.s - checks the PICO9918's F18A features that SMB will use:
;   1. tile layer 1 smooth scrolling across two name table pages (R27 and the
;      page bit in R2, R29 bit 1 = two pages)
;   2. tile layer 2 for a fixed status line on top (R49 bit 7, names R10,
;      colours R11; colour 0 = see-through)
;   3. magnified 8 x 8 sprites, 12 on one line (R30: sprites per line)
;
;   run:  L PICOTEST 0800  then  R.    Keys: SPACE pause, Q quit.
; ============================================================================
        .setcpu "6502"
        .include "sbc_api.inc"

V_NAME1         = $0000         ; layer 1 names: two pages, $0000 and $0400
V_PAT           = $0800         ; patterns
V_NAME2         = $1000         ; layer 2 names
V_SATTR         = $1B00
V_COL1          = $2000         ; layer 1 colours
V_COL2          = $2040         ; layer 2 colours
V_SPAT          = $3800
VDP_NAME        = V_NAME1
NSPR            = 12

        .segment "CODE"
        jmp     start
        .byte   0, 0, 0, 0, 0
        .include "lib/vdp.s"

frame_idle:
        rts

start:  cld
        ldx     #$FF
        txs
        lda     SBC_SYSINFO             ; a Rev2 ROM and the PICO9918?
        cmp     #$4C
        bne     @no
        jsr     SBC_SYSINFO
        cmp     #DISP_PICO
        beq     @ok
@no:    jmp     SBC_MENU
@ok:    lda     #<regs
        ldy     #>regs
        jsr     vdp_setup
        ; patterns: the font at $20-$5F, a column number pattern set, ground
        lda     #<(V_PAT + $20*8)
        ldy     #>(V_PAT + $20*8)
        jsr     vdp_waddr
        lda     #<font
        sta     vdp_src
        lda     #>font
        sta     vdp_src+1
        lda     #0
        sta     vdp_n
        lda     #2
        sta     vdp_n+1
        jsr     vdp_copy
        lda     #<(V_PAT + $80*8)       ; $80 brick, $81 sky dot, $82 sprite ball
        ldy     #>(V_PAT + $80*8)
        jsr     vdp_waddr
        ldx     #0
@p:     lda     pats,x
        sta     VDP_DATA
        inx
        cpx     #3*8
        bne     @p
        ; layer 1 colours: text $20-$5F yellow on blue, $80 brick red on blue
        lda     #<V_COL1
        ldy     #>V_COL1
        jsr     vdp_waddr
        ldx     #0
@c1:    lda     col1,x
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @c1
        ; layer 2 colours: group 0 see-through, text white on black
        lda     #<V_COL2
        ldy     #>V_COL2
        jsr     vdp_waddr
        ldx     #0
@c2:    lda     col2,x
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @c2
        ; layer 1, both pages: the column number (0-63) at the top of each
        ; column, sky dots, bricks at the bottom
        lda     #0
        sta     row
@r1:    ldx     #0
@cl:    stx     col
        lda     col             ; address: page (col / 32) * $400 + row * 32 + col & 31
        and     #31
        sta     tmp
        lda     row
        asl
        asl
        asl
        asl
        asl
        ora     tmp
        sta     VDP_CTRL
        lda     row
        lsr
        lsr
        lsr
        sta     tmp
        lda     col
        and     #32
        lsr
        lsr
        lsr                     ; page 1: +4 to the high byte
        ora     tmp
        ora     #$40 + >V_NAME1
        sta     VDP_CTRL
        lda     row
        cmp     #2
        beq     @tens
        cmp     #3
        beq     @ones
        cmp     #20
        bcs     @brick
        lda     col             ; a diagonal of letters, so the scroll shows
        clc
        adc     row
        and     #7
        beq     @dot
        lda     #$81
        bne     @put
@dot:   lda     col
        and     #31
        clc
        adc     #'A'-1
        cmp     #'A'
        bcs     @put
        lda     #'@'
        bne     @put
@tens:  lda     col
        ldy     #'0'
@t:     cmp     #10
        bcc     @td
        sbc     #10
        iny
        bne     @t
@td:    tya
        bne     @put
@ones:  lda     col
@o:     cmp     #10
        bcc     @od
        sbc     #10
        bcs     @o
@od:    ora     #'0'
        bne     @put
@brick: lda     #$80
@put:   sta     VDP_DATA
        ldx     col
        inx
        cpx     #64
        beq     :+
        jmp     @cl
:       inc     row
        lda     row
        cmp     #24
        beq     @l2
        jmp     @r1
        ; layer 2: blank (see-through) but for the top row
@l2:    lda     #<V_NAME2
        ldy     #>V_NAME2
        jsr     vdp_waddr
        ldx     #0
@tx:    lda     top_txt,x
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @tx
        lda     #<(768-32)
        sta     vdp_n
        lda     #>(768-32)
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        ; the F18A registers
        lda     #V_NAME2/$400   ; R10: layer 2 names
        ldx     #10
        jsr     vdp_reg
        lda     #V_COL2/$40     ; R11: layer 2 colours
        ldx     #11
        jsr     vdp_reg
        lda     #$02            ; R29: layer 1 two pages across
        ldx     #29
        jsr     vdp_reg
        lda     #$80            ; R49: layer 2 on
        ldx     #49
        jsr     vdp_reg
        lda     #0              ; R50 bit 0 = 0: layer 2 always on top
        ldx     #50
        jsr     vdp_reg
        lda     #31             ; R30: 31 sprites a line
        ldx     #30
        jsr     vdp_reg
        ; the sprites: 12 balls in a row, magnified 8 x 8
        lda     #<V_SPAT
        ldy     #>V_SPAT
        jsr     vdp_waddr
        ldx     #0
@sp:    lda     pats+16,x
        sta     VDP_DATA
        inx
        cpx     #8
        bne     @sp
        lda     #$C1            ; R1: 16K, display on, no interrupt, 8 x 8 sprites magnified
        ldx     #1
        jsr     vdp_reg
        lda     #0
        sta     scroll
        sta     scroll+1
        sta     bounce

; ---- every frame -------------------------------------------------------------------
loop:   jsr     vdp_frame
        lda     scroll          ; R27 = scroll low byte, R2 page bit = bit 8
        ldx     #27
        jsr     vdp_reg
        lda     scroll+1
        and     #1
        ora     #V_NAME1/$400
        ldx     #2
        jsr     vdp_reg
        lda     #<V_SATTR       ; the sprites, bobbing together on one line
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     bounce
        lsr
        lsr
        and     #15
        clc
        adc     #120
        sta     tmp
        ldx     #0
@s:     lda     tmp
        sta     VDP_DATA
        txa
        asl
        asl
        asl
        asl
        clc
        adc     #20             ; x = 20 + 16 * n... over 12 sprites
        sta     VDP_DATA
        lda     #0
        sta     VDP_DATA
        txa
        and     #7
        clc
        adc     #8
        sta     VDP_DATA
        inx
        cpx     #NSPR
        bne     @s
        lda     #$D0
        sta     VDP_DATA
        lda     #<(V_NAME2+26)  ; the scroll position on the status line
        ldy     #>(V_NAME2+26)
        jsr     vdp_waddr
        lda     scroll+1
        and     #1
        ora     #'0'
        sta     VDP_DATA
        lda     scroll
        lsr
        lsr
        lsr
        lsr
        tax
        lda     hex,x
        sta     VDP_DATA
        lda     scroll
        and     #15
        tax
        lda     hex,x
        sta     VDP_DATA
        inc     bounce
        lda     paused
        bne     @keys
        inc     scroll          ; one pixel a frame, around the 512
        bne     @keys
        inc     scroll+1
@keys:  jsr     SBC_CHRIN
        bcs     :+
        jmp     loop
:
        and     #$DF
        cmp     #'Q'
        beq     quit
        lda     paused
        eor     #1
        sta     paused
        jmp     loop
quit:   jsr     SBC_CONRESET
        jmp     SBC_MENU

        .segment "RODATA"
regs:   .byte   $00, $80, V_NAME1/$400, V_COL1/$40, V_PAT/$800, V_SATTR/$80, V_SPAT/$800, $04
pats:   .byte   $FE, $FE, $FE, $00, $EF, $EF, $EF, $00       ; $80 bricks
        .byte   $00, $00, $00, $10, $00, $00, $00, $00       ; $81 a dot
        .byte   $3C, $7E, $FF, $FF, $FF, $FF, $7E, $3C       ; sprite 0: a ball
col1:   .byte   $00, $00, $00, $00, $B4, $B4, $B4, $B4, $B4, $B4, $B4, $B4
        .byte   $00, $00, $00, $00, $64, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00
col2:   .byte   $00, $00, $00, $00, $F1, $F1, $F1, $F1, $F1, $F1, $F1, $F1
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00
top_txt:.byte   "LAYER 2: FIXED.   SCROLL      "
        .byte   $20, $20
hex:    .byte   "0123456789ABCDEF"
font:   .include "font.inc"

        .segment "BSS"
row:    .res 1
col:    .res 1
tmp:    .res 1
scroll: .res 2
bounce: .res 1
paused: .res 1
