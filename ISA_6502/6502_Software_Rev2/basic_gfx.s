; ============================================================================
; basic_gfx.s - EhBASIC statements for the PICO9918 and ESP32_VGA displays
;
; NEW BASIC KEYWORDS (tokens after AYREG in basic.s, so programs SAVEd before
; keep their meaning):
;
;   CLS                       clear the text screen
;   CLS 1                     graphics: text over a bitmap, sprites on
;   CLS 0                     back to text only
;   COLOR fg [, bg]           text colours from now on
;   LOCATE col, row           move the cursor
;   PLOT x, y, c              a point (c = 0 clears it on the PICO9918)
;   PLOT x, y, c, r [, f]     a circle, radius r; f = 1 filled
;   PLOT x, y TO x2, y2, c [, f]
;                             a line; f = 1 a box, f = 2 a filled box
;   SPRITE n, p, x, y [, c]   show sprite n with pattern p at x, y
;   SPRITE DEF p, addr        define pattern p from the bytes at addr
;                             (POKE them there first)
;
; What the numbers mean depends on the card (each is used its own way):
;                 ESP32_VGA                  PICO9918
;   bitmap        320 x 240                  256 x 192 (after CLS 1)
;   text          80 x 30                    80 x 30 / 40 x 24; 32 x 24 after CLS 1
;   colours       0-63 = %00RRGGBB,          0-15 (TMS9918A); in text mode
;                 64 = transparent           one pair for the whole screen
;   sprites       0-15, patterns 0-31,       0-31, patterns 0-63, 16 x 16,
;                 16 x 16, 256 bytes each    32 bytes each; c = colour
;                 (a byte a pixel); c =      (default 15); y >= 192 hides it.
;                 flags: 1 show, 2 h-flip,   Only after CLS 1.
;                 4 v-flip (default 1)
;   After CLS 1 the ESP32 text background is transparent (64), so the bitmap
;   shows through; COLOR fg, 64 keeps it that way.
;
; With the KB_MONITOR_TERM display CLS sends a form feed ($0C); the others
; give ?FC ERROR.  A BASIC program can tell the cards apart with
;   D = PEEK(65279)   ($FEFF: 0 none, 1 terminal, 2 PICO9918, 3 ESP32_VGA)
; ============================================================================

.if CON_DISPLAY = DISP_PICO
SPR_DEFAULT     = 15                    ; white
.else
SPR_DEFAULT     = 1                     ; ESP32: visible
.endif

.segment "BIOS"

; ---- argument helpers ----------------------------------------------------------
; a number 0-65535 -> Itempl / Itemph
gx_getw:
        jsr     LAB_EVNM
        jmp     LAB_F2FX

; ", number" -> Itempl / Itemph
gx_cw:  jsr     LAB_1C01
        jmp     gx_getw

; ", byte" -> X
gx_cb:  jsr     LAB_1C01
        jmp     LAB_GTBY

; "[, byte]" -> X, C=1 if it was there (else X unchanged, C=0)
gx_opt: jsr     LAB_GBYT
        cmp     #','
        bne     @no
        jsr     gx_cb
        sec
        rts
@no:    clc
        rts

gx_fc:  jmp     LAB_FCER                ; ?FC ERROR

; ----------------------------------------------------------------------------
; CLS [mode]
; ----------------------------------------------------------------------------
BI_CLS:
        jsr     LAB_GBYT
        beq     @plain                  ; no mode
        jsr     LAB_GTBY
        cpx     #2
        bcs     gx_fc
        txa
        jmp     @do
@plain: lda     #$FF
@do:
.if GFX_OK
        jmp     gfx_cls
.else
        cmp     #1
        beq     gx_fc                   ; no graphics on this display
        lda     #$0C                    ; form feed
        jmp     CHROUT
.endif

; ----------------------------------------------------------------------------
; COLOR fg [, bg]
; ----------------------------------------------------------------------------
BI_COLOR:
        jsr     LAB_GTBY
        stx     gfx_fg
        jsr     gx_opt
        bcc     :+
        stx     gfx_bg
:
.if GFX_OK
        jmp     gfx_color
.else
        jmp     gx_fc
.endif

; ----------------------------------------------------------------------------
; LOCATE col, row
; ----------------------------------------------------------------------------
BI_LOCATE:
        jsr     LAB_GTBY
        stx     gfx_x
        jsr     gx_cb
        stx     gfx_y
.if GFX_OK
        jmp     gfx_locate
.else
        jmp     gx_fc
.endif

; ----------------------------------------------------------------------------
; PLOT x, y, c [, r [, f]]   /   PLOT x, y TO x2, y2, c [, f]
; ----------------------------------------------------------------------------
BI_PLOT:
.if GFX_OK
        jsr     gx_getw                 ; x
        lda     Itempl
        sta     gfx_x
        lda     Itemph
        sta     gfx_x+1
        jsr     gx_cb                   ; y
        stx     gfx_y
        lda     #0
        sta     gfx_y+1
        sta     gfx_f
        jsr     LAB_GBYT
        cmp     #TK_TO
        beq     @to
        jsr     gx_cb                   ; c
        stx     gfx_c
        jsr     gx_opt                  ; r?
        bcc     @point
        stx     gfx_r
        jsr     gx_opt                  ; f?
        bcc     :+
        stx     gfx_f
:       jmp     gfx_circle
@point: jmp     gfx_plot
@to:    jsr     LAB_IGBY                ; past TO
        jsr     gx_getw                 ; x2
        lda     Itempl
        sta     gfx_x1
        lda     Itemph
        sta     gfx_x1+1
        jsr     gx_cb                   ; y2
        stx     gfx_y1
        lda     #0
        sta     gfx_y1+1
        jsr     gx_cb                   ; c
        stx     gfx_c
        jsr     gx_opt                  ; f?
        bcc     @line
        cpx     #3
        bcc     :+
        jmp     gx_fc
:       stx     gfx_f
        txa
        beq     @line
        jmp     gfx_box
@line:  jmp     gfx_line
.else
        jmp     gx_fc
.endif

; ----------------------------------------------------------------------------
; SPRITE n, p, x, y [, c]   /   SPRITE DEF p, addr
; ----------------------------------------------------------------------------
BI_SPRITE:
.if GFX_OK
        jsr     LAB_GBYT
        cmp     #TK_DEF
        beq     @def
        jsr     LAB_GTBY                ; n
        stx     gfx_n
        jsr     gx_cb                   ; p
        stx     gfx_p
        jsr     gx_cw                   ; x
        lda     Itempl
        sta     gfx_x
        lda     Itemph
        sta     gfx_x+1
        jsr     gx_cw                   ; y
        lda     Itempl
        sta     gfx_y
        lda     Itemph
        sta     gfx_y+1
        jsr     gx_opt                  ; c?
        bcs     :+
        ldx     #SPR_DEFAULT
:       stx     gfx_c
        jmp     gfx_sprite
@def:   jsr     LAB_IGBY                ; past DEF
        jsr     LAB_GTBY                ; p
        stx     gfx_p
        jsr     gx_cw                   ; addr
        lda     Itempl
        sta     con_ptr
        lda     Itemph
        sta     con_ptr+1
        jmp     gfx_sprdef
.else
        jmp     gx_fc
.endif
