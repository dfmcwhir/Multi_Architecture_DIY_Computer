; ============================================================================
; drv_pico.s - PICO9918 card as the console (VDP at $7F1C / $7F1D)
;
; Text console (CON_DISPLAY = DISP_PICO):
;   * PICO9918 firmware 1.0+ (found at boot): 80 x 30 text (F18A T80 + 30 rows)
;   * otherwise (or PICO_COLS = 40):         40 x 24 text (TMS9918A text mode)
;   The cursor is the character under it shown inverse.  Characters $A0-$FF
;   print as inverse copies of $20-$7F.  Control codes: CR, LF, BS, TAB and FF
;   (clear screen); the others are ignored.
;
; Graphics (BASIC "CLS 1", or the gfx_ calls): Graphics II, 256 x 192, colours
;   0-15 (2 colours in each 8 x 1 block), 32 sprites of 16 x 16, and the
;   console carries on as 32 x 24 text drawn into the bitmap.  "CLS 0" goes
;   back to the text mode.
;
; VRAM, text mode:     name table $0000 (up to 2400), patterns $1000
; VRAM, Graphics II:   patterns $0000, colours $2000, sprite patterns $1800,
;                      names $3800, sprite attributes $3B00
;
; Every routine here works with interrupts off while it talks to the VDP: a
; status read in between the two writes of an address would spoil it.  Your
; own programs that use the VDP directly must do the same (SEI ... CLI) if
; PICO_IRQ is set.
; ============================================================================

.if PICO_IRQ
PICO_IE         = $20                   ; R1 interrupt enable
.else
PICO_IE         = $00
.endif

; VRAM layout
TXT_NAME        = $0000
TXT_PATT        = $1000
TXT_SATTR       = $1800                 ; (F18A only: sprites parked here)
G2_PATT         = $0000
G2_COLOR        = $2000
G2_SPAT         = $1800
G2_NAME         = $3800
G2_SATTR        = $3B00

; Wait between VDP accesses (PICO_SLOW nops; 0 for the PICO9918)
.macro VW
  .repeat PICO_SLOW
        nop
  .endrepeat
.endmacro

.segment "DRVVARS"
pico_ok:        .res 1                  ; $80 = the VDP answered
pico_f18a:      .res 1                  ; $80 = PICO9918 1.0+: 80 columns, 30 rows
pico_fw:        .res 1                  ; its firmware version ($12 = 1.2), 0 = unknown
pico_mode:      .res 1                  ; 0 text, 1 Graphics II
pico_cols:      .res 1
pico_rows:      .res 1
pico_col:       .res 1
pico_row:       .res 1
pico_cur:       .res 1                  ; $80 = cursor shown
pico_st:        .res 1                  ; status bits gathered by pico_irq
pico_ch:        .res 1
pico_t0:        .res 1
pico_t1:        .res 1
pico_t2:        .res 1
pico_n:         .res 1                  ; pv_copy byte count (0 = 256)
pico_addr:      .res 2
pico_src:       .res 2
pico_dst:       .res 2
pico_cnt:       .res 2
pico_buf:       .res 256
; line / circle working values
pl_dx:          .res 2
pl_dy:          .res 2
pl_err:         .res 2
pl_e2:          .res 2
pl_sx:          .res 1
pl_sy:          .res 1
pc_x:           .res 1
pc_y:           .res 1
pc_d:           .res 2
pc_t:           .res 2
pc_a:           .res 1
pc_b:           .res 1
pc_cx:          .res 2
pc_cy:          .res 2
pc_n:           .res 2
pb_x0:          .res 2
pb_y0:          .res 2
pb_x1:          .res 2
pb_y1:          .res 2

.segment "BIOS"

; ============================================================================
; Low level (interrupts must already be off)
; ============================================================================

; pv_waddr - VRAM write address A (low) / X (high)
pv_waddr:
        sta     PICO_CTRL
        VW
        txa
        and     #$3F
        ora     #$40
        sta     PICO_CTRL
        VW
        rts

; pv_raddr - VRAM read address A (low) / X (high), then about 2 us for the
; VDP to fetch the first byte before it is read
PV_RDLY         = CPU_KHZ * 2 / 5000 + 1        ; 5-cycle loops
pv_raddr:
        sta     PICO_CTRL
        VW
        txa
        and     #$3F
        sta     PICO_CTRL
        ldx     #PV_RDLY
@w:     dex
        bne     @w
        rts

; pv_reg - VDP register X = A
pv_reg:
        sta     PICO_CTRL
        VW
        txa
        ora     #$80
        sta     PICO_CTRL
        VW
        rts

; pv_fill - write A pico_cnt times (16 bit, at the address already set).
; Clobbers X, Y.
pv_fill:
        ldy     pico_cnt
        beq     @pages
@lo:    sta     PICO_DATA
        VW
        dey
        bne     @lo
@pages: ldx     pico_cnt+1
        beq     @x
@pg:    sta     PICO_DATA
        VW
        dey
        bne     @pg
        dex
        bne     @pg
@x:     rts

; pv_copy - copy pico_n bytes (0 = 256) of VRAM from pico_src to pico_dst
; through pico_buf.  Clobbers A, X, Y.
pv_copy:
        lda     pico_src
        ldx     pico_src+1
        jsr     pv_raddr
        ldy     #0
@r:     lda     PICO_DATA
        sta     pico_buf,y
        VW
        iny
        cpy     pico_n
        bne     @r
        lda     pico_dst
        ldx     pico_dst+1
        jsr     pv_waddr
        ldy     #0
@w:     lda     pico_buf,y
        sta     PICO_DATA
        VW
        iny
        cpy     pico_n
        bne     @w
        rts

; pv_unlock - the F18A unlock sequence (VR57 = $1C, twice)
pv_unlock:
        lda     #$1C
        ldx     #57
        jsr     pv_reg
        lda     #$1C
        ldx     #57
        jmp     pv_reg

; pv_color - A = the console colours as one byte: fg << 4 | bg
pv_color:
        lda     gfx_fg
        asl     a
        asl     a
        asl     a
        asl     a
        ora     gfx_bg
        rts

; ============================================================================
; Start-up
; ============================================================================

; ----------------------------------------------------------------------------
; pico_init - C=0 if the VDP answered.  Text mode, cleared.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
pico_init:
        php
        sei
        lda     #0
        sta     pico_ok
        sta     pico_f18a
        sta     pico_fw
        sta     pico_cur
        sta     pico_st
        lda     #PICO_FG
        sta     gfx_fg
        lda     #PICO_BG
        sta     gfx_bg
        ; The PICO9918 takes a while to boot after power-up (it shows its
        ; logo meanwhile) and ignores the bus until then: keep trying for
        ; PICO_BOOT_MS, and once it answers give it PICO_SETTLE_MS more.
        lda     #<(PICO_BOOT_MS / 10)
        sta     pico_cnt
        lda     #>(PICO_BOOT_MS / 10)
        sta     pico_cnt+1
@try:   jsr     pv_present
        bcc     @found
        lda     #10
        jsr     DELAY_MS
        lda     pico_cnt
        bne     :+
        dec     pico_cnt+1
:       dec     pico_cnt
        lda     pico_cnt
        ora     pico_cnt+1
        bne     @try
        jmp     @absent
@found: lda     #PICO_SETTLE_MS
        jsr     DELAY_MS
        jsr     pv_present              ; still there after settling?
        bcs     @absent
        jsr     pv_detect
        jsr     pv_text
        lda     #$80
        sta     pico_ok
        lda     #4
        ora     DEVSTAT
        sta     DEVSTAT                 ; device status bit 2
        jsr     pv_curon
        plp
        clc
        rts
@absent:
        plp
        sec
        rts

; pv_present - C=0 if the VDP answers: R1 = display off, then $A5 $5A written
; at VRAM $3FFE and read back (an empty bus reads $7F).  Clobbers A, X.
pv_present:
        lda     #$80                    ; R1: 16K, display off
        ldx     #1
        jsr     pv_reg
        lda     #$FE
        ldx     #$3F
        jsr     pv_waddr
        lda     #$A5
        sta     PICO_DATA
        VW
        lda     #$5A
        sta     PICO_DATA
        VW
        lda     #$FE
        ldx     #$3F
        jsr     pv_raddr
        lda     PICO_DATA
        cmp     #$A5
        bne     @no
        VW
        lda     PICO_DATA
        cmp     #$5A
        bne     @no
        clc
        rts
@no:    sec
        rts

; pv_detect - a PICO9918 with firmware 1.0+?  (F18A unlock, then its
; configuration registers: option 0 = Pico model 1/2, option 2 = firmware.)
; On a TMS9918A the writes land in R0-R7 (set again by pv_text) and the
; status reads don't match.
pv_detect:
.if PICO_COLS <> 40
        jsr     pv_unlock
        lda     #$80                    ; VR50: registers to power-up values
        ldx     #50                     ; (keeps the palette)
        jsr     pv_reg
        jsr     pv_unlock
        lda     #0                      ; option 0: Pico model
        ldx     #58
        jsr     pv_reg
        lda     #$0C                    ; status register 12 = the option
        ldx     #15
        jsr     pv_reg
        lda     PICO_CTRL
        sta     pico_t0
        VW
        lda     #2                      ; option 2: firmware version
        ldx     #58
        jsr     pv_reg
        lda     PICO_CTRL
        sta     pico_t1
        VW
        lda     #0                      ; status register 0 again
        ldx     #15
        jsr     pv_reg
        lda     pico_t0
        cmp     #1
        beq     @model
        cmp     #2
        bne     @no
@model: lda     pico_t1
        cmp     #$10                    ; 1.0 or later
        bcc     @no
        cmp     #$A0
        bcs     @no
        sta     pico_fw
        lda     #$80
        sta     pico_f18a
@no:
.endif
        rts

; ----------------------------------------------------------------------------
; pv_text - text mode: registers, font (normal at $20, inverse at $A0),
; cleared screen, cursor home.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
pv_text:
        lda     #0
        sta     pico_mode
        sta     pico_cur
        lda     #$80                    ; R1: display off while loading
        ldx     #1
        jsr     pv_reg
        bit     pico_f18a
        bpl     @t40
        lda     #80
        sta     pico_cols
        lda     #30
        sta     pico_rows
        lda     #$04                    ; R0: T80 (with M1 in R1)
        ldx     #0
        jsr     pv_reg
        lda     #$00                    ; R2: names at $0000.  Unlocked, the
        ldx     #2                      ; F18A uses all 4 bits: (R2 & $0F) << 10
        jsr     pv_reg                  ; ($03 would put them at $0C00)
        lda     #$40                    ; VR49: 30 rows
        ldx     #49
        jsr     pv_reg
        jmp     @common
@t40:   lda     #40
        sta     pico_cols
        lda     #24
        sta     pico_rows
        lda     #$00                    ; R0: text
        ldx     #0
        jsr     pv_reg
        lda     #$00                    ; R2: names at $0000
        ldx     #2
        jsr     pv_reg
@common:
        lda     #$02                    ; R4: patterns at $1000
        ldx     #4
        jsr     pv_reg
        bit     pico_f18a               ; unlocked, the F18A shows sprites in
        bpl     @nospr                  ; text mode too, and with 30 rows the
        lda     #0                      ; $D0 end marker doesn't work: process
        ldx     #51                     ; no sprites (VR51 = 0) ...
        jsr     pv_reg
        lda     #(TXT_SATTR / $80)      ; ... and keep all 32 below the screen
        ldx     #5
        jsr     pv_reg
        lda     #<TXT_SATTR
        ldx     #>TXT_SATTR
        jsr     pv_waddr
        ldy     #32
@spr:   lda     #$F0                    ; y = 240: off the bottom
        sta     PICO_DATA
        VW
        lda     #0
        sta     PICO_DATA
        VW
        sta     PICO_DATA
        VW
        sta     PICO_DATA
        VW
        dey
        bne     @spr
@nospr:
        jsr     pv_color                ; R7: text colours
        ldx     #7
        jsr     pv_reg
        lda     #<(TXT_PATT + $20 * 8)  ; the font
        ldx     #>(TXT_PATT + $20 * 8)
        jsr     pv_waddr
        lda     #$00
        jsr     pv_font
        lda     #<(TXT_PATT + $A0 * 8)  ; and inverse
        ldx     #>(TXT_PATT + $A0 * 8)
        jsr     pv_waddr
        lda     #$FF
        jsr     pv_font
        jsr     pv_clear
        lda     #($D0 | PICO_IE)        ; R1: 16K, display on, text
        ldx     #1
        jmp     pv_reg

; pv_font - send the 768 byte font, each byte EOR A
pv_font:
        sta     pico_t0
        lda     #<pico_font
        sta     con_ptr
        lda     #>pico_font
        sta     con_ptr+1
        ldx     #3
        ldy     #0
@l:     lda     (con_ptr),y
        eor     pico_t0
        sta     PICO_DATA
        VW
        iny
        bne     @l
        inc     con_ptr+1
        dex
        bne     @l
        rts

; pv_clear - clear the screen (and the bitmap, in Graphics II), cursor home.
; The cursor must be off.  Clobbers A, X, Y.
pv_clear:
        lda     #0
        sta     pico_col
        sta     pico_row
        lda     pico_mode
        bne     @g2
        lda     #<TXT_NAME
        ldx     #>TXT_NAME
        jsr     pv_waddr
        lda     #<2400
        sta     pico_cnt
        lda     #>2400
        sta     pico_cnt+1
        lda     #' '
        jmp     pv_fill
@g2:    lda     #<G2_PATT
        ldx     #>G2_PATT
        jsr     pv_waddr
        lda     #<6144
        sta     pico_cnt
        lda     #>6144
        sta     pico_cnt+1
        lda     #0
        jsr     pv_fill
        lda     #<G2_COLOR
        ldx     #>G2_COLOR
        jsr     pv_waddr
        jsr     pv_color
        jmp     pv_fill                 ; (pico_cnt is still 6144)

; ----------------------------------------------------------------------------
; pv_g2 - Graphics II: registers, names 0-255 x 3, everything cleared, all
; sprites below the screen.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
pv_g2:
        lda     #1
        sta     pico_mode
        lda     #0
        sta     pico_cur
        lda     #32
        sta     pico_cols
        lda     #24
        sta     pico_rows
        lda     #$82                    ; R1: display off, 16x16 sprites
        ldx     #1
        jsr     pv_reg
        bit     pico_f18a
        bpl     :+
        lda     #$00                    ; VR49: 24 rows (and the $D0 sprite end)
        ldx     #49
        jsr     pv_reg
        lda     #32                     ; VR51: all 32 sprites again
        ldx     #51
        jsr     pv_reg
:       lda     #$02                    ; R0: Graphics II
        ldx     #0
        jsr     pv_reg
        lda     #$0E                    ; R2: names at $3800
        ldx     #2
        jsr     pv_reg
        lda     #$FF                    ; R3: colours at $2000
        ldx     #3
        jsr     pv_reg
        lda     #$03                    ; R4: patterns at $0000
        ldx     #4
        jsr     pv_reg
        lda     #$76                    ; R5: sprite attributes at $3B00
        ldx     #5
        jsr     pv_reg
        lda     #$03                    ; R6: sprite patterns at $1800
        ldx     #6
        jsr     pv_reg
        lda     gfx_bg                  ; R7: border = the background
        ldx     #7
        jsr     pv_reg
        lda     #<G2_NAME               ; names 0-255, three times
        ldx     #>G2_NAME
        jsr     pv_waddr
        ldx     #3
        ldy     #0
@n:     tya
        sta     PICO_DATA
        VW
        iny
        bne     @n
        dex
        bne     @n
        lda     #<G2_SATTR              ; 32 sprites: y = 192 (below the screen)
        ldx     #>G2_SATTR
        jsr     pv_waddr
        ldx     #32
@s:     lda     #192
        sta     PICO_DATA
        VW
        lda     #0
        sta     PICO_DATA
        VW
        sta     PICO_DATA
        VW
        sta     PICO_DATA
        VW
        dex
        bne     @s
        jsr     pv_clear
        lda     #($C2 | PICO_IE)        ; R1: 16K, display on, 16x16 sprites
        ldx     #1
        jmp     pv_reg

; ============================================================================
; Console output
; ============================================================================

; ----------------------------------------------------------------------------
; pico_putc - print A.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
pico_putc:
        bit     pico_ok
        bmi     :+
        rts
:       php
        sei
        sta     pico_ch
        jsr     pv_curoff
        lda     pico_ch
        cmp     #$20
        bcc     @ctl
        cmp     #$80                    ; $80-$9F have no glyph: a space
        bcc     @draw
        cmp     #$A0
        bcs     @draw
        lda     #' '
        sta     pico_ch
@draw:  jsr     pv_glyph                ; draw it at the cursor
        inc     pico_col
        lda     pico_col
        cmp     pico_cols
        bcc     @done
        lda     #0                      ; end of the line: wrap
        sta     pico_col
        jsr     pv_lf
        jmp     @done
@ctl:   cmp     #$0D
        bne     @c1
        lda     #0
        sta     pico_col
        beq     @done
@c1:    cmp     #$0A
        bne     @c2
        jsr     pv_lf
        jmp     @done
@c2:    cmp     #$08
        bne     @c3
        lda     pico_col
        beq     @done
        dec     pico_col
        jmp     @done
@c3:    cmp     #$09
        bne     @c4
        lda     pico_col                ; next multiple of 8
        clc
        adc     #8
        and     #$F8
        cmp     pico_cols
        bcc     :+
        ldx     pico_cols
        dex
        txa
:       sta     pico_col
        jmp     @done
@c4:    cmp     #$0C
        bne     @done
        jsr     pv_clear
@done:  jsr     pv_curon
        plp
        rts

; pv_lf - down a line, scrolling at the bottom
pv_lf:
        inc     pico_row
        lda     pico_row
        cmp     pico_rows
        bcc     @x
        dec     pico_row
        jmp     pv_scroll
@x:     rts

; pv_scroll - everything up a line, bottom line cleared.  Clobbers A, X, Y.
pv_scroll:
        lda     pico_mode
        bne     @g2
        lda     pico_cols               ; text: row by row through pico_buf
        sta     pico_n
        lda     #<TXT_NAME
        sta     pico_dst
        lda     #>TXT_NAME
        sta     pico_dst+1
        lda     pico_cols
        sta     pico_src
        lda     #0
        sta     pico_src+1
        ldx     pico_rows
        dex
@tl:    stx     pico_t2
        jsr     pv_copy
        lda     pico_src                ; dst = src, src += cols
        sta     pico_dst
        lda     pico_src+1
        sta     pico_dst+1
        clc
        lda     pico_src
        adc     pico_cols
        sta     pico_src
        bcc     :+
        inc     pico_src+1
:       ldx     pico_t2
        dex
        bne     @tl
        lda     pico_dst                ; the last row: spaces
        ldx     pico_dst+1
        jsr     pv_waddr
        lda     pico_cols
        sta     pico_cnt
        lda     #0
        sta     pico_cnt+1
        lda     #' '
        jmp     pv_fill

@g2:    lda     #>G2_PATT               ; Graphics II: patterns, then colours
        jsr     pv_g2up
        lda     #0
        jsr     pv_fill
        lda     #>G2_COLOR
        jsr     pv_g2up
        jsr     pv_color
        jmp     pv_fill

; pv_g2up - A = table page: 23 character rows (256 bytes each) up one, then
; the address set to the last row and pico_cnt = 256, ready for pv_fill
pv_g2up:
        sta     pico_dst+1
        sta     pico_t1
        clc
        adc     #1
        sta     pico_src+1
        lda     #0
        sta     pico_src
        sta     pico_dst
        sta     pico_n                  ; 256 bytes a row
        ldx     #23
@l:     stx     pico_t2
        jsr     pv_copy
        inc     pico_src+1
        inc     pico_dst+1
        ldx     pico_t2
        dex
        bne     @l
        lda     #0
        ldx     pico_dst+1
        jsr     pv_waddr
        lda     #0
        sta     pico_cnt
        lda     #1
        sta     pico_cnt+1
        rts

; pv_txtaddr - pico_addr = text name table address of the cursor
pv_txtaddr:
        lda     pico_row
        sta     pico_t0
        lda     #0
        sta     pico_addr
        sta     pico_addr+1
        ldx     #8                      ; pico_addr = row * cols
@m:     asl     pico_addr
        rol     pico_addr+1
        asl     pico_t0
        bcc     @n
        clc
        lda     pico_addr
        adc     pico_cols
        sta     pico_addr
        bcc     @n
        inc     pico_addr+1
@n:     dex
        bne     @m
        clc                             ; + col
        lda     pico_addr
        adc     pico_col
        sta     pico_addr
        bcc     :+
        inc     pico_addr+1
:       rts

; pv_g2addr - pico_addr = Graphics II pattern address of the cursor cell
pv_g2addr:
        lda     pico_col
        asl     a
        asl     a
        asl     a
        sta     pico_addr
        lda     pico_row
        sta     pico_addr+1
        rts

; pv_glyph - draw pico_ch at the cursor
pv_glyph:
        lda     pico_mode
        bne     @g2
        jsr     pv_txtaddr
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_waddr
        lda     pico_ch
        sta     PICO_DATA
        VW
        rts
@g2:    lda     pico_ch                 ; $A0-$FF: inverse
        ldx     #0
        cmp     #$A0
        bcc     :+
        ldx     #$FF
        sec
        sbc     #$80
:       stx     pico_t1
        cmp     #$80
        bcc     :+
        lda     #' '                    ; $80-$9F: a space
:       sec
        sbc     #$20                    ; con_ptr = pico_font + (ch - $20) * 8
        sta     con_ptr
        lda     #0
        asl     con_ptr
        rol     a
        asl     con_ptr
        rol     a
        asl     con_ptr
        rol     a
        sta     con_ptr+1
        clc
        lda     con_ptr
        adc     #<pico_font
        sta     con_ptr
        lda     con_ptr+1
        adc     #>pico_font
        sta     con_ptr+1
        jsr     pv_g2addr
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_waddr
        ldy     #0
@p:     lda     (con_ptr),y
        eor     pico_t1
        sta     PICO_DATA
        VW
        iny
        cpy     #8
        bne     @p
        lda     pico_addr               ; and its colours
        pha
        lda     pico_addr+1
        clc
        adc     #>G2_COLOR
        tax
        pla
        jsr     pv_waddr
        jsr     pv_color
        ldy     #8
@c:     sta     PICO_DATA
        VW
        dey
        bne     @c
        rts

; pv_curon / pv_curoff - show / hide the cursor (the cell inverted)
pv_curon:
        bit     pico_cur
        bmi     @x
        jsr     pv_curflip
        lda     #$80
        sta     pico_cur
@x:     rts

pv_curoff:
        bit     pico_cur
        bpl     @x
        jsr     pv_curflip
        lda     #0
        sta     pico_cur
@x:     rts

pv_curflip:
        lda     pico_mode
        bne     @g2
        jsr     pv_txtaddr              ; text: flip bit 7 of the character
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_raddr
        lda     PICO_DATA
        eor     #$80
        pha
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_waddr
        pla
        sta     PICO_DATA
        VW
        rts
@g2:    jsr     pv_g2addr               ; Graphics II: invert the 8 bytes
        ldy     #8
@b:     lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_raddr
        lda     PICO_DATA
        eor     #$FF
        pha
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_waddr
        pla
        sta     PICO_DATA
        VW
        inc     pico_addr
        dey
        bne     @b
        rts

; ============================================================================
; gfx_ calls (see console.s for the shared values gfx_x ... gfx_f)
; ============================================================================

; pico_gcls - A = $FF: clear the screen;  0: text mode;  1: Graphics II
pico_gcls:
        bit     pico_ok
        bpl     @x
        php
        sei
        pha
        jsr     pv_curoff
        pla
        cmp     #0
        beq     @text
        cmp     #1
        beq     @g2
        jsr     pv_clear
        jmp     @done
@text:  jsr     pv_text
        jmp     @done
@g2:    jsr     pv_g2
@done:  jsr     pv_curon
        plp
@x:     rts

; pico_reset - back to the text console (jump table SBC_CONRESET)
pico_reset:
        lda     #0
        jmp     pico_gcls

; pico_gcolor - gfx_fg / gfx_bg (0-15) for the text from now on.  In text
; mode the whole screen has one colour pair.
pico_gcolor:
        bit     pico_ok
        bpl     @x
        lda     gfx_fg
        and     #$0F
        sta     gfx_fg
        lda     gfx_bg
        and     #$0F
        sta     gfx_bg
        lda     pico_mode
        bne     @x
        php
        sei
        jsr     pv_color
        ldx     #7
        jsr     pv_reg
        plp
@x:     rts

; pico_glocate - cursor to column gfx_x, row gfx_y (held inside the screen)
pico_glocate:
        bit     pico_ok
        bpl     @x
        php
        sei
        jsr     pv_curoff
        lda     gfx_x
        cmp     pico_cols
        bcc     :+
        ldx     pico_cols
        dex
        txa
:       sta     pico_col
        lda     gfx_y
        cmp     pico_rows
        bcc     :+
        ldx     pico_rows
        dex
        txa
:       sta     pico_row
        jsr     pv_curon
        plp
@x:     rts

; pico_gplot - point gfx_x, gfx_y (16 bit, signed y) in colour gfx_c
; (0 = clear the pixel).  Graphics II only; off-screen points are skipped.
pico_gplot:
        php
        sei
        jsr     pv_pset
        plp
        rts

; pv_pset - the point, interrupts already off.  Clobbers A, X.
pv_pset:
        lda     pico_mode
        beq     @out
        lda     gfx_x+1
        bne     @out
        lda     gfx_y+1
        bne     @out
        lda     gfx_y
        cmp     #192
        bcc     @in
@out:   rts
@in:    lsr     a                       ; address = (y / 8) * 256
        lsr     a                       ;         + (x & $F8) + (y & 7)
        lsr     a
        sta     pico_addr+1
        lda     gfx_x
        and     #$F8
        sta     pico_addr
        lda     gfx_y
        and     #7
        ora     pico_addr
        sta     pico_addr
        lda     gfx_x
        and     #7
        tax
        lda     pv_bits,x
        sta     pico_t0
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_raddr
        lda     PICO_DATA
        sta     pico_t1
        lda     gfx_c
        beq     @clr
        lda     pico_t1
        ora     pico_t0
        jmp     @wp
@clr:   lda     pico_t0
        eor     #$FF
        and     pico_t1
@wp:    pha
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_waddr
        pla
        sta     PICO_DATA
        VW
        lda     gfx_c                   ; set: the block's colour = gfx_c
        beq     @x
        lda     pico_addr+1
        clc
        adc     #>G2_COLOR
        sta     pico_addr+1
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_raddr
        lda     PICO_DATA
        and     #$0F
        sta     pico_t1
        lda     gfx_c
        asl     a
        asl     a
        asl     a
        asl     a
        ora     pico_t1
        pha
        lda     pico_addr
        ldx     pico_addr+1
        jsr     pv_waddr
        pla
        sta     PICO_DATA
        VW
@x:     rts

pv_bits:
        .byte   $80, $40, $20, $10, $08, $04, $02, $01

; ----------------------------------------------------------------------------
; pico_gline - line from gfx_x, gfx_y to gfx_x1, gfx_y1 in gfx_c (Bresenham).
; gfx_x / gfx_y end up at the far end.
; ----------------------------------------------------------------------------
pico_gline:
        php
        sei
        jsr     pv_line
        plp
        rts

pv_line:
        sec                             ; dx = |x1 - x0|, sx = direction
        lda     gfx_x1
        sbc     gfx_x
        sta     pl_dx
        lda     gfx_x1+1
        sbc     gfx_x+1
        sta     pl_dx+1
        ldx     #0
        lda     pl_dx+1
        bpl     @dxok
        ldx     #$FF
        sec
        lda     #0
        sbc     pl_dx
        sta     pl_dx
        lda     #0
        sbc     pl_dx+1
        sta     pl_dx+1
@dxok:  stx     pl_sx
        sec                             ; dy = -|y1 - y0|, sy = direction
        lda     gfx_y1
        sbc     gfx_y
        sta     pl_dy
        lda     gfx_y1+1
        sbc     gfx_y+1
        sta     pl_dy+1
        ldx     #$FF
        lda     pl_dy+1
        bmi     @dyok                   ; y1 < y0: already negative
        ldx     #0
        sec
        lda     #0
        sbc     pl_dy
        sta     pl_dy
        lda     #0
        sbc     pl_dy+1
        sta     pl_dy+1
@dyok:  stx     pl_sy
        clc                             ; err = dx + dy
        lda     pl_dx
        adc     pl_dy
        sta     pl_err
        lda     pl_dx+1
        adc     pl_dy+1
        sta     pl_err+1
@loop:  jsr     pv_pset
        lda     gfx_x                   ; at the end?
        cmp     gfx_x1
        bne     @go
        lda     gfx_x+1
        cmp     gfx_x1+1
        bne     @go
        lda     gfx_y
        cmp     gfx_y1
        bne     @go
        lda     gfx_y+1
        cmp     gfx_y1+1
        bne     @go
        rts
@go:    lda     pl_err                  ; e2 = 2 * err
        asl     a
        sta     pl_e2
        lda     pl_err+1
        rol     a
        sta     pl_e2+1
        sec                             ; e2 >= dy ?
        lda     pl_e2
        sbc     pl_dy
        lda     pl_e2+1
        sbc     pl_dy+1
        bvc     :+
        eor     #$80
:       bmi     @noX
        clc                             ; err += dy, x += sx
        lda     pl_err
        adc     pl_dy
        sta     pl_err
        lda     pl_err+1
        adc     pl_dy+1
        sta     pl_err+1
        lda     pl_sx
        bne     @xm
        inc     gfx_x
        bne     @noX
        inc     gfx_x+1
        jmp     @noX
@xm:    lda     gfx_x
        bne     :+
        dec     gfx_x+1
:       dec     gfx_x
@noX:   sec                             ; e2 <= dx ?
        lda     pl_dx
        sbc     pl_e2
        lda     pl_dx+1
        sbc     pl_e2+1
        bvc     :+
        eor     #$80
:       bmi     @noY
        clc                             ; err += dx, y += sy
        lda     pl_err
        adc     pl_dx
        sta     pl_err
        lda     pl_err+1
        adc     pl_dx+1
        sta     pl_err+1
        lda     pl_sy
        bne     @ym
        inc     gfx_y
        bne     @noY
        inc     gfx_y+1
        jmp     @noY
@ym:    lda     gfx_y
        bne     :+
        dec     gfx_y+1
:       dec     gfx_y
@noY:   jmp     @loop

; ----------------------------------------------------------------------------
; pico_gbox - rectangle with corners gfx_x, gfx_y and gfx_x1, gfx_y1 in gfx_c;
; gfx_f = 1 outline, 2 filled
; ----------------------------------------------------------------------------
pico_gbox:
        php
        sei
        ldx     #7                      ; keep the corners
@k:     lda     gfx_x,x
        sta     pb_x0,x
        dex
        bpl     @k
        lda     gfx_f
        cmp     #2
        beq     @fill
        jsr     @set00                  ; top: (x0,y0) - (x1,y0)
        jsr     @to10
        jsr     pv_line
        jsr     @to11                   ; right: on to (x1,y1)
        jsr     pv_line
        jsr     @to01                   ; bottom: on to (x0,y1)
        jsr     pv_line
        jsr     @to00                   ; left: back to (x0,y0)
        jsr     pv_line
        plp
        rts
@fill:  jsr     @set00                  ; one line per row, y0 to y1
@row:   jsr     @to10x                  ; (x0,y) - (x1,y)
        lda     gfx_y
        pha
        lda     gfx_y+1
        pha
        jsr     pv_line
        pla
        sta     gfx_y+1
        pla
        sta     gfx_y
        lda     gfx_y                   ; last row?
        cmp     pb_y1
        bne     @nx
        lda     gfx_y+1
        cmp     pb_y1+1
        beq     @end
@nx:    lda     pb_x0                   ; back to x0, next row towards y1
        sta     gfx_x
        lda     pb_x0+1
        sta     gfx_x+1
        jsr     @ystep
        jmp     @row
@end:   plp
        rts

@set00: lda     pb_x0
        sta     gfx_x
        lda     pb_x0+1
        sta     gfx_x+1
        lda     pb_y0
        sta     gfx_y
        lda     pb_y0+1
        sta     gfx_y+1
        rts
@to10:  lda     pb_y0                   ; target (x1, y0)
        sta     gfx_y1
        lda     pb_y0+1
        sta     gfx_y1+1
@to10x: lda     pb_x1                   ; target x1, current row
        sta     gfx_x1
        lda     pb_x1+1
        sta     gfx_x1+1
        lda     gfx_y
        sta     gfx_y1
        lda     gfx_y+1
        sta     gfx_y1+1
        rts
@to11:  lda     pb_x1
        sta     gfx_x1
        lda     pb_x1+1
        sta     gfx_x1+1
        lda     pb_y1
        sta     gfx_y1
        lda     pb_y1+1
        sta     gfx_y1+1
        rts
@to01:  lda     pb_x0
        sta     gfx_x1
        lda     pb_x0+1
        sta     gfx_x1+1
        lda     pb_y1
        sta     gfx_y1
        lda     pb_y1+1
        sta     gfx_y1+1
        rts
@to00:  lda     pb_x0
        sta     gfx_x1
        lda     pb_x0+1
        sta     gfx_x1+1
        lda     pb_y0
        sta     gfx_y1
        lda     pb_y0+1
        sta     gfx_y1+1
        rts
@ystep: lda     gfx_y                   ; y one step towards pb_y1
        cmp     pb_y1
        lda     gfx_y+1
        sbc     pb_y1+1
        bcs     @yd                     ; y >= y1: down
        inc     gfx_y
        bne     :+
        inc     gfx_y+1
:       rts
@yd:    lda     gfx_y
        bne     :+
        dec     gfx_y+1
:       dec     gfx_y
        rts

; ----------------------------------------------------------------------------
; pico_gcircle - circle centre gfx_x, gfx_y, radius gfx_r, colour gfx_c;
; gfx_f = 1 filled (midpoint circle)
; ----------------------------------------------------------------------------
pico_gcircle:
        php
        sei
        ldx     #3                      ; keep the centre
@k:     lda     gfx_x,x
        sta     pc_cx,x
        dex
        bpl     @k
        lda     #0
        sta     pc_x
        lda     gfx_r
        sta     pc_y
        sec                             ; d = 1 - r
        lda     #1
        sbc     gfx_r
        sta     pc_d
        lda     #0
        sbc     #0
        sta     pc_d+1
@loop:  lda     pc_y                    ; while x <= y
        cmp     pc_x
        bcs     :+
        jmp     @done
:
        lda     pc_x                    ; the eight points (or four spans)
        sta     pc_a
        lda     pc_y
        sta     pc_b
        jsr     pv_quad
        lda     pc_y
        sta     pc_a
        lda     pc_x
        sta     pc_b
        jsr     pv_quad
        lda     pc_d+1
        bpl     @dpos
        lda     pc_x                    ; d < 0: d += 2x + 3
        asl     a
        sta     pc_t
        lda     #0
        rol     a
        sta     pc_t+1
        clc
        lda     pc_t
        adc     #3
        sta     pc_t
        bcc     :+
        inc     pc_t+1
:       jmp     @addd
@dpos:  lda     pc_y                    ; d >= 0: d += 2(x - y) + 5, y -= 1
        beq     @done                   ; (y = 0: finished)
        sec
        lda     pc_x
        sbc     pc_y
        sta     pc_t
        lda     #0
        sbc     #0
        sta     pc_t+1
        asl     pc_t
        rol     pc_t+1
        clc
        lda     pc_t
        adc     #5
        sta     pc_t
        lda     pc_t+1
        adc     #0
        sta     pc_t+1
        dec     pc_y
@addd:  clc
        lda     pc_d
        adc     pc_t
        sta     pc_d
        lda     pc_d+1
        adc     pc_t+1
        sta     pc_d+1
        inc     pc_x
        jmp     @loop
@done:  plp
        rts

; pv_quad - the 4 points (cx +- a, cy +- b), or with gfx_f the 2 spans
; cx - a ... cx + a on the rows cy +- b
pv_quad:
        lda     gfx_f
        bne     @fill
        ldy     #3
@p:     tya
        pha
        jsr     pv_cpt
        jsr     pv_pset
        pla
        tay
        dey
        bpl     @p
        rts
@fill:  ldy     #1
        jsr     pv_span
        ldy     #3
        ; (on into pv_span)
pv_span:
        jsr     pv_cpt                  ; gfx_x = cx - a, gfx_y = cy +- b
        lda     pc_a                    ; 2a + 1 points
        asl     a
        sta     pc_n
        lda     #0
        rol     a
        sta     pc_n+1
        inc     pc_n
        bne     @l
        inc     pc_n+1
@l:     jsr     pv_pset
        inc     gfx_x
        bne     :+
        inc     gfx_x+1
:       lda     pc_n
        bne     :+
        dec     pc_n+1
:       dec     pc_n
        lda     pc_n
        ora     pc_n+1
        bne     @l
        rts

; pv_cpt - gfx_x = cx +- pc_a (Y bit 0: minus), gfx_y = cy +- pc_b (bit 1)
pv_cpt:
        tya
        and     #1
        bne     @xm
        clc
        lda     pc_cx
        adc     pc_a
        sta     gfx_x
        lda     pc_cx+1
        adc     #0
        sta     gfx_x+1
        jmp     @y
@xm:    sec
        lda     pc_cx
        sbc     pc_a
        sta     gfx_x
        lda     pc_cx+1
        sbc     #0
        sta     gfx_x+1
@y:     tya
        and     #2
        bne     @ym
        clc
        lda     pc_cy
        adc     pc_b
        sta     gfx_y
        lda     pc_cy+1
        adc     #0
        sta     gfx_y+1
        rts
@ym:    sec
        lda     pc_cy
        sbc     pc_b
        sta     gfx_y
        lda     pc_cy+1
        sbc     #0
        sta     gfx_y+1
        rts

; ----------------------------------------------------------------------------
; pico_gsprite - sprite gfx_n (0-31): pattern gfx_p (0-63), at gfx_x, gfx_y,
; colour gfx_c (0-15).  y 192 or more hides it.  Graphics II only.
; ----------------------------------------------------------------------------
pico_gsprite:
        lda     pico_mode
        beq     @x
        php
        sei
        lda     gfx_n                   ; attribute address $3B00 + n * 4
        and     #$1F
        asl     a
        asl     a
        ldx     #>G2_SATTR
        jsr     pv_waddr
        lda     gfx_y+1                 ; y (the VDP shows y + 1)
        bne     @hide
        lda     gfx_y
        cmp     #192
        bcs     @hide
        sec
        sbc     #1
        jmp     @y
@hide:  lda     #192
@y:     sta     PICO_DATA
        VW
        lda     gfx_x
        sta     PICO_DATA
        VW
        lda     gfx_p                   ; 16x16: pattern * 4
        and     #$3F
        asl     a
        asl     a
        sta     PICO_DATA
        VW
        lda     gfx_c
        and     #$0F
        sta     PICO_DATA
        VW
        plp
@x:     rts

; pico_gsprdef - sprite pattern gfx_p (0-63) = the 32 bytes at con_ptr
; (16x16: left column top to bottom, then the right column, as the TMS9918A)
pico_gsprdef:
        bit     pico_ok
        bpl     @x
        php
        sei
        lda     gfx_p                   ; $1800 + p * 32
        and     #$3F
        sta     pico_t0
        lda     #0
        ldx     #5
@m:     asl     pico_t0
        rol     a
        dex
        bne     @m
        clc
        adc     #>G2_SPAT
        tax
        lda     pico_t0
        jsr     pv_waddr
        ldy     #0
@l:     lda     (con_ptr),y
        sta     PICO_DATA
        VW
        iny
        cpy     #32
        bne     @l
        plp
@x:     rts

; ----------------------------------------------------------------------------
; pico_vsync - C=1 if a frame has ended since the last call; A = the status
; bits (5th sprite / collision) seen since then.
; ----------------------------------------------------------------------------
pico_vsync:
.if PICO_IRQ
        php
        sei
        lda     pico_st
        ldx     #0
        stx     pico_st
        plp
.else
        php
        sei
        lda     PICO_CTRL               ; status: bit 7 = frame ended
        sta     pico_t0
        plp
        lda     pico_t0
.endif
        cmp     #$80                    ; C = bit 7
        rts

; pico_irq - from irq.s (PICO_IRQ): read the status (that clears the VDP's
; interrupt) and keep its bits for pico_vsync.  C=1 if it was a frame.
pico_irq:
        bit     pico_ok
        bpl     @no
        lda     PICO_CTRL
        bpl     @no
        ora     pico_st
        sta     pico_st
        sec
        rts
@no:    clc
        rts

.include "pico_font.inc"
