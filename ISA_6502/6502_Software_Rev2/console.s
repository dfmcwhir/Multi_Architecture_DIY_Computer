; ============================================================================
; console.s - console layer: CHRIN / CHROUT and the input buffer
;
; Input:  every driver that produces keys (keyboard, serial, gamepad) puts
;         them in one 256 byte buffer from its interrupt handler with
;         CON_PUTKEY.  CHRIN takes them out.  With CON_POLL = 1, CHRIN also
;         polls the devices, so typing works even if an IRQ jumper is wrong.
; Output: CHROUT sends each character to the display driver and/or the serial
;         console, as chosen by CON_INIT at boot (con_out).
;
; The drivers chosen in config.inc are reached through these names:
;   disp_init  C=0 if the display card answered
;   disp_putc  print A (may change A, X, Y)
;   ser_putc   send A out of the serial console (may change A, X, Y)
; ============================================================================

CON_TO_DISP     = $01                   ; con_out bits
CON_TO_SER      = $02

; ---- pick the drivers -------------------------------------------------------
.if CON_DISPLAY = DISP_TERM
disp_init       = term_init
disp_putc       = term_putc
disp_reset      = term_init
.elseif CON_DISPLAY = DISP_ESP32
disp_init       = esp_init
disp_putc       = esp_putc
disp_reset      = esp_reset
.elseif CON_DISPLAY = DISP_PICO
disp_init       = pico_init
disp_putc       = pico_putc
disp_reset      = pico_reset
.endif

; ---- graphics: the gfx_ calls used by BASIC (basic_gfx.s) --------------------
; In:  gfx_x, gfx_y (16 bit; text column/row for gfx_locate), gfx_x1, gfx_y1,
;      gfx_c colour (sprites: colour on the PICO9918, flags on the ESP32),
;      gfx_r radius, gfx_f fill (circle 0/1, box 1/2), gfx_n sprite, gfx_p
;      pattern, gfx_fg / gfx_bg text colours, con_ptr sprite data.
; GFX_OK = 1 if the display has graphics.
.if CON_DISPLAY = DISP_ESP32
GFX_OK          = 1
gfx_cls         = esp_gcls              ; A = $FF clear, 0 text, 1 graphics
gfx_color       = esp_gcolor
gfx_locate      = esp_glocate
gfx_plot        = esp_gplot
gfx_line        = esp_gline
gfx_box         = esp_gbox
gfx_circle      = esp_gcircle
gfx_sprite      = esp_gsprite
gfx_sprdef      = esp_gsprdef
gfx_vsync       = esp_vsync
.elseif CON_DISPLAY = DISP_PICO
GFX_OK          = 1
gfx_cls         = pico_gcls
gfx_color       = pico_gcolor
gfx_locate      = pico_glocate
gfx_plot        = pico_gplot
gfx_line        = pico_gline
gfx_box         = pico_gbox
gfx_circle      = pico_gcircle
gfx_sprite      = pico_gsprite
gfx_sprdef      = pico_gsprdef
gfx_vsync       = pico_vsync
.else
GFX_OK          = 0
.endif

.if CON_SERIAL = SER_AVR
ser_putc        = avrkbd_putc
.elseif CON_SERIAL = SER_ACIA
ser_putc        = acia_putc
.endif

; ---- RAM ----------------------------------------------------------------------
.zeropage
READ_PTR:       .res 1
WRITE_PTR:      .res 1
con_ptr:        .res 2                  ; display drivers: font / sprite data

.segment "DRVVARS"
gfx_x:          .res 2                  ; (keep x, y, x1, y1 together and in
gfx_y:          .res 2                  ;  this order: drv_pico.s copies them)
gfx_x1:         .res 2
gfx_y1:         .res 2
gfx_c:          .res 1
gfx_r:          .res 1
gfx_f:          .res 1
gfx_n:          .res 1
gfx_p:          .res 1
gfx_fg:         .res 1
gfx_bg:         .res 1

.segment "BIOSVARS"
LAST_CHAR:      .res 1

.segment "DRVVARS"
con_out:        .res 1                  ; CON_TO_DISP / CON_TO_SER
con_ch:         .res 1                  ; CHROUT's character

.segment "INPUT_BUFFER"
INPUT_BUFFER:   .res $100

.segment "BIOS"

; ----------------------------------------------------------------------------
; CON_INIT - start the display driver and choose where output goes.
; Called from RESET after the serial/keyboard drivers.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
CON_INIT:
        lda     #0
        sta     con_out
.if CON_DISPLAY <> DISP_NONE
        jsr     disp_init
        bcs     @nodisp
        lda     #CON_TO_DISP
        sta     con_out
  .if CON_MIRROR .and (CON_SERIAL <> SER_NONE)
        jsr     ser_ok
        bcs     @done
        lda     #(CON_TO_DISP | CON_TO_SER)
        sta     con_out
  .endif
        rts
@nodisp:
.endif
.if CON_SERIAL <> SER_NONE
        jsr     ser_ok                  ; no display: the serial console
        bcs     @done
        lda     #CON_TO_SER
        sta     con_out
.endif
@done:  rts

; ser_ok - C=0 if the serial console's device answered at boot
.if CON_SERIAL <> SER_NONE
ser_ok:
  .if CON_SERIAL = SER_AVR
        lda     avr_ok
  .else
        lda     acia_ok
  .endif
        asl     a                       ; bit 7 -> carry: 1 = answered
        bcs     @yes
        sec
        rts
@yes:   clc
        rts
.endif

; ----------------------------------------------------------------------------
; CHROUT - print the character in A.  Preserves A, X and Y.
; Used as EhBASIC's output vector and by the monitor.
; ----------------------------------------------------------------------------
MONCOUT:
CHROUT:
        bit     ld_on                   ; quiet while LOAD types in a text file
        bpl     @go
        pha                             ; (keep Z/N = the character, as below)
        pla
        rts
@go:    sta     con_ch
        pha
        txa
        pha
        tya
        pha
.if CON_DISPLAY <> DISP_NONE
        lda     con_out
        and     #CON_TO_DISP
        beq     @ser
        lda     con_ch
        jsr     disp_putc
@ser:
.endif
.if CON_SERIAL <> SER_NONE
        lda     con_out
        and     #CON_TO_SER
        beq     @done
        lda     con_ch
        jsr     ser_putc
@done:
.endif
        pla
        tay
        pla
        tax
        pla
        rts

; ----------------------------------------------------------------------------
; SER_OUT - send A out of the serial console port, whether or not it is the
; console right now (for terminal programs).  Preserves A, X and Y.
; ----------------------------------------------------------------------------
SER_OUT:
.if CON_SERIAL <> SER_NONE
        sta     con_ch
        pha
        txa
        pha
        tya
        pha
        lda     con_ch
        jsr     ser_putc
        pla
        tay
        pla
        tax
        pla
.endif
        rts

; ----------------------------------------------------------------------------
; CHRIN - get a character without waiting, and without echo.
;   carry set   = A is the character (Z/N reflect it: EhBASIC relies on that)
;   carry clear = nothing waiting, A = 0
; Preserves X and Y.  Used as EhBASIC's input vector and by the monitor.
; ----------------------------------------------------------------------------
MONRDKEY:
CHRIN:
        bit     ld_on                   ; LOAD is typing in a text file?
        bpl     @kbd
        jmp     ld_getc                 ; (ch376_loadsave.s)
@kbd:   txa
        pha
        tya
        pha
.if CON_POLL
        jsr     CON_POLLDEV
.endif
        jsr     BUFFER_SIZE
        beq     @none
        jsr     READ_BUFFER             ; A = the character (and LAST_CHAR)
        pla
        tay
        pla
        tax
        lda     LAST_CHAR               ; sets Z/N for the caller
        sec
        rts
@none:  pla
        tay
        pla
        tax
        lda     #0
        clc
        rts

; ----------------------------------------------------------------------------
; CON_POLLDEV - check the input devices directly, with interrupts off (so an
; interrupt handler can't read the same device at the same moment).
; Each driver's _irq routine only reads its device when it has a byte.
; Clobbers A, X, Y.
; ----------------------------------------------------------------------------
.if CON_POLL
CON_POLLDEV:
        php
        sei
  .if HAS_AVRKBD
        jsr     avrkbd_irq
  .endif
  .if CON_DISPLAY = DISP_TERM
        jsr     term_irq
  .endif
  .if HAS_ACIA .and ACIA_TO_CON
        jsr     acia_irq
  .endif
  .if ESP_KEYS
        jsr     esp_irq
  .endif
        plp
        rts
.endif

; ----------------------------------------------------------------------------
; CON_PUTKEY - put A in the input buffer (from interrupt handlers, or with
; interrupts off).  A full buffer drops the byte.  Uses X; preserves A and Y.
; ----------------------------------------------------------------------------
CON_PUTKEY:
        ldx     WRITE_PTR
        inx
        cpx     READ_PTR
        beq     @full                   ; keep one slot free: full
        dex
        sta     INPUT_BUFFER,x
        inc     WRITE_PTR
@full:  rts

; ----------------------------------------------------------------------------
; The buffer routines (names kept from the Rev1 BIOS; gamepad.s uses them)
; ----------------------------------------------------------------------------
INIT_BUFFER:                            ; empty the buffer.  Modifies A
        lda     #0
        sta     READ_PTR
        sta     WRITE_PTR
        rts

WRITE_BUFFER    = CON_PUTKEY            ; A -> buffer.  Modifies X

READ_BUFFER:                            ; A (and LAST_CHAR) <- buffer.  Modifies X
        ldx     READ_PTR
        lda     INPUT_BUFFER,x
        sta     LAST_CHAR
        inc     READ_PTR
        rts

BUFFER_SIZE:                            ; A = bytes waiting.  Modifies A
        lda     WRITE_PTR
        sec
        sbc     READ_PTR
        rts
