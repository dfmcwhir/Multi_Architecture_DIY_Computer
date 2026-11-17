; ============================================================================
; drv_esp32.s - ESP32_VGA card as the console ($7F18-$7F1B)
;
; What the ROM does with the card:
;   * console output: one STA VGA_DATA per character.  The card handles CR,
;     LF, BS, TAB, FF (clear screen) and BEL itself; there is no other
;     control-code translation.  Programs use the card's own commands
;     (esp32vga.inc) for colour, cursor position, graphics, sprites, sound.
;   * keyboard (ESP32_KBD = 1): keys are read from VGA_KEY on the card's IRQ
;     line (jumper 5/6: ESP32_IRQ), and converted to the same codes as the
;     AVR keyboard (arrows ^E ^X ^P ^D, Esc ^C, F1-F12 129-140).
;   * mouse (MOUSE_SRC = MOUSE_ESP32): SBC_MOUSE reads IO_MDELTA.
;
; The ROM never reads STATUS (so the VBL flag is your program's), and its
; interrupt handler only reads VGA_KEY (so programs can send commands at any
; time without disabling interrupts).
; ============================================================================

.include "esp32vga.inc"

ESP_BOOT_TRIES  = 300                   ; x 10 ms: wait up to 3 s for the card to boot

.if ESP32_KBD
ESP_IRQ_MASK    = ST_KEY
.else
ESP_IRQ_MASK    = 0
.endif

.segment "DRVVARS"
esp_ok:         .res 1                  ; $80 = the card answered
esp_tries:      .res 2
esp_mbtn:       .res 1                  ; mouse buttons at the last read

.segment "BIOS"

; ----------------------------------------------------------------------------
; esp_init - wait for the card's PING reply, then reset it to a known state:
; text layer only, white on black, keys flushed, sound off.  C=0 if it
; answered.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
esp_init:
        lda     #0
        sta     esp_ok
        sta     esp_mbtn
        sta     gfx_bg                  ; V_RESET: white on black
        lda     #C_WHITE
        sta     gfx_fg
        lda     #<ESP_BOOT_TRIES
        sta     esp_tries
        lda     #>ESP_BOOT_TRIES
        sta     esp_tries+1
@try:   lda     #IO_PING                ; (while the ESP32 is still booting it
        sta     VGA_IOCMD               ;  doesn't stall the CPU: reads are junk)
        lda     VGA_IORESP
        cmp     #$A5
        bne     @wait
        lda     VGA_IORESP
        cmp     #$5A
        beq     @found
@wait:  lda     #10
        jsr     DELAY_MS
        lda     esp_tries
        bne     :+
        dec     esp_tries+1
:       dec     esp_tries
        lda     esp_tries
        ora     esp_tries+1
        bne     @try
        sec                             ; no card (or it never booted)
        rts
@found: lda     #IO_RESET               ; keys flushed, IRQs off, sound off
        sta     VGA_IOCMD
        lda     #V_RESET                ; text only, white on black, cleared
        sta     VGA_CMD
        lda     #IO_IRQEN               ; /IRQ while a key is waiting
        sta     VGA_IOCMD
        lda     #ESP_IRQ_MASK
        sta     VGA_IODATA
        lda     #$80
        sta     esp_ok
        lda     #4
        ora     DEVSTAT
        sta     DEVSTAT                 ; device status bit 2
        clc
        rts

; ----------------------------------------------------------------------------
; esp_putc - print A.  Preserves A, X, Y.
; ----------------------------------------------------------------------------
esp_putc:
        bit     esp_ok
        bpl     :+
        sta     VGA_DATA
:       rts

; ----------------------------------------------------------------------------
; esp_irq - from irq.s (and CHRIN's polling).  Takes one key from the card.
; C=1 = a key was taken; C=0 = none waiting.  Clobbers A, X.
; ----------------------------------------------------------------------------
esp_irq:
.if ESP32_KBD
        bit     esp_ok
        bpl     @no
        lda     VGA_KEY                 ; 0 = none (the card drops /IRQ when empty)
        beq     @no
        jsr     esp_keymap
        cmp     #0
        beq     @yes                    ; a key with no console code: dropped
        jsr     CON_PUTKEY
@yes:   sec
        rts
.endif
@no:    clc
        rts

; esp_keymap - the card's key code in A -> the console's (AVR) code, 0 = none
esp_keymap:
        cmp     #$1B                    ; Esc -> ^C, as on the AVR keyboard
        bne     @n1
        lda     #$03
        rts
@n1:    cmp     #$80
        bcc     @x                      ; ASCII: as it is
        cmp     #$84
        bcs     @n2
        tax                             ; arrows $80-$83 -> ^E ^X ^P ^D
        lda     esp_arrows-$80,x
        rts
@n2:    cmp     #$89
        bcs     @n3
        lda     #$01                    ; Home End PgUp PgDn Ins -> 1 (as the AVR)
        rts
@n3:    cmp     #$90
        bcc     @none
        cmp     #$9C
        bcs     @none
        sec                             ; F1-F12 $90-$9B -> 129-140
        sbc     #($90 - 129)
@x:     rts
@none:  lda     #0
        rts

esp_arrows:
        .byte   $05, $18, $10, $04      ; up, down, left, right

; ----------------------------------------------------------------------------
; esp_mouse_on - A = 1 on, 0 off.  The card always tracks the mouse, so this
; just throws away the movement so far.  C=1 if the card isn't there.
; ----------------------------------------------------------------------------
esp_mouse_on:
        bit     esp_ok
        bpl     @none
        lda     #IO_MDELTA
        sta     VGA_IOCMD
        lda     VGA_IORESP
        sta     esp_mbtn
        lda     VGA_IORESP
        lda     VGA_IORESP
        clc
        rts
@none:  sec
        rts

; ----------------------------------------------------------------------------
; esp_mouse_read - A = buttons, X/Y = movement since the last call (signed,
; right/down +).  C=1 if anything changed since the last call.
; ----------------------------------------------------------------------------
esp_mouse_read:
        bit     esp_ok
        bpl     @none
        lda     #IO_MDELTA
        sta     VGA_IOCMD
        lda     VGA_IORESP              ; buttons
        ldx     VGA_IORESP              ; dx
        ldy     VGA_IORESP              ; dy
        cmp     esp_mbtn
        sta     esp_mbtn                ; (STA leaves the flags alone)
        bne     @new
        cpx     #0
        bne     @new
        cpy     #0
        bne     @new
        clc
        rts
@new:   sec
        rts
@none:  lda     #0
        tax
        tay
        clc
        rts

; ============================================================================
; gfx_ calls (see console.s for the shared values gfx_x ... gfx_bg)
; Coordinates: bitmap and sprites 320 x 240, text 80 x 30; colours %00RRGGBB
; (0-63, 64 = transparent).
; ============================================================================

; esp_gcls - A = $FF: clear the text;  0: text only;  1: text over bitmap
; and sprites (bitmap cleared, sprites hidden, text background transparent)
esp_gcls:
        bit     esp_ok
        bpl     @x
        cmp     #0
        beq     @text
        cmp     #1
        beq     @gfx
        lda     #V_CLS
        sta     VGA_CMD
@x:     rts
@text:  lda     #LAYER_TEXT
        jsr     esp_layers
        lda     gfx_bg                  ; an opaque background again
        and     #$3F
        sta     gfx_bg
        jmp     @cls
@gfx:   lda     #(LAYER_TEXT | LAYER_BITMAP | LAYER_SPRITES)
        jsr     esp_layers
        lda     #V_GCLS
        sta     VGA_CMD
        lda     #C_BLACK
        sta     VGA_DATA
        lda     #C_TRANSPARENT          ; text over the bitmap
        sta     gfx_bg
@cls:   jsr     esp_gcolor
        lda     #V_CLS
        sta     VGA_CMD
        rts

; esp_layers - A = layer mask; all sprites hidden as well
esp_layers:
        ldx     #V_LAYERS
        stx     VGA_CMD
        sta     VGA_DATA
        lda     #V_SPRHIDE
        sta     VGA_CMD
        lda     #$FF
        sta     VGA_DATA
        rts

; esp_gcolor - text colours gfx_fg, gfx_bg from now on
esp_gcolor:
        bit     esp_ok
        bpl     @x
        lda     #V_COLOR
        sta     VGA_CMD
        lda     gfx_fg
        and     #$3F
        sta     VGA_DATA
        lda     gfx_bg
        and     #$7F
        sta     VGA_DATA
@x:     rts

; esp_glocate - cursor to column gfx_x, row gfx_y
esp_glocate:
        bit     esp_ok
        bpl     @x
        lda     #V_LOCATE
        sta     VGA_CMD
        lda     gfx_x
        sta     VGA_DATA
        lda     gfx_y
        sta     VGA_DATA
@x:     rts

; esp_xy - send gfx_x (16 bit) and gfx_y (8 bit)
esp_xy:
        lda     gfx_x
        sta     VGA_DATA
        lda     gfx_x+1
        sta     VGA_DATA
        lda     gfx_y
        sta     VGA_DATA
        rts

; esp_gplot - point gfx_x, gfx_y, colour gfx_c
esp_gplot:
        bit     esp_ok
        bpl     @x
        lda     #V_PLOT
        sta     VGA_CMD
        jsr     esp_xy
        lda     gfx_c
        sta     VGA_DATA
@x:     rts

; esp_gline - line gfx_x, gfx_y to gfx_x1, gfx_y1, colour gfx_c
esp_gline:
        bit     esp_ok
        bpl     @x
        lda     #V_LINE
        sta     VGA_CMD
        jsr     esp_xy
        lda     gfx_x1
        sta     VGA_DATA
        lda     gfx_x1+1
        sta     VGA_DATA
        lda     gfx_y1
        sta     VGA_DATA
        lda     gfx_c
        sta     VGA_DATA
@x:     rts

; esp_gbox - rectangle with corners gfx_x, gfx_y and gfx_x1, gfx_y1;
; gfx_f = 1 outline, 2 filled
esp_gbox:
        bit     esp_ok
        bmi     :+
        rts
:       lda     #V_RECT
        ldx     gfx_f
        cpx     #2
        bne     :+
        lda     #V_FILLRECT
:       sta     VGA_CMD
        sec                             ; x0 <= x1?  (swap if not)
        lda     gfx_x1
        sbc     gfx_x
        sta     esp_w
        lda     gfx_x1+1
        sbc     gfx_x+1
        sta     esp_w+1
        bcs     @xok
        lda     gfx_x1                  ; x1 is the left
        sta     VGA_DATA
        lda     gfx_x1+1
        sta     VGA_DATA
        sec                             ; width = -(x1 - x0)
        lda     #0
        sbc     esp_w
        sta     esp_w
        lda     #0
        sbc     esp_w+1
        sta     esp_w+1
        jmp     @y
@xok:   lda     gfx_x
        sta     VGA_DATA
        lda     gfx_x+1
        sta     VGA_DATA
@y:     sec                             ; the same for y (8 bit)
        lda     gfx_y1
        sbc     gfx_y
        bcs     @yok
        eor     #$FF                    ; height - 1 = y0 - y1
        adc     #1
        ldx     gfx_y1
        jmp     @y2
@yok:   ldx     gfx_y
@y2:    stx     VGA_DATA                ; top
        sta     esp_h
        inc     esp_w                  ; width = difference + 1
        bne     :+
        inc     esp_w+1
:       lda     esp_w
        sta     VGA_DATA
        lda     esp_w+1
        sta     VGA_DATA
        ldx     esp_h                   ; height = difference + 1
        inx
        stx     VGA_DATA
        lda     gfx_c
        sta     VGA_DATA
        rts

; esp_gcircle - centre gfx_x, gfx_y, radius gfx_r, colour gfx_c; gfx_f = 1 filled
esp_gcircle:
        bit     esp_ok
        bpl     @x
        lda     #V_CIRCLE
        ldx     gfx_f
        beq     :+
        lda     #V_FILLCIRC
:       sta     VGA_CMD
        jsr     esp_xy
        lda     gfx_r
        sta     VGA_DATA
        lda     gfx_c
        sta     VGA_DATA
@x:     rts

; esp_gsprite - sprite gfx_n (0-15): pattern gfx_p (0-31) at gfx_x, gfx_y
; (16 bit), flags gfx_c (SPR_VISIBLE | SPR_HFLIP | SPR_VFLIP)
esp_gsprite:
        bit     esp_ok
        bpl     @x
        lda     #V_SPRSET
        sta     VGA_CMD
        lda     gfx_n
        sta     VGA_DATA
        lda     gfx_p
        sta     VGA_DATA
        lda     gfx_x
        sta     VGA_DATA
        lda     gfx_x+1
        sta     VGA_DATA
        lda     gfx_y
        sta     VGA_DATA
        lda     gfx_y+1
        sta     VGA_DATA
        lda     gfx_c
        sta     VGA_DATA
@x:     rts

; esp_gsprdef - sprite pattern gfx_p (0-31) = the 256 bytes at con_ptr
; (16 x 16 pixels, a byte each, top row first; $40 bit = clear)
esp_gsprdef:
        bit     esp_ok
        bpl     @x
        lda     #V_SPRDEF
        sta     VGA_CMD
        lda     gfx_p
        sta     VGA_DATA
        ldy     #0
@l:     lda     (con_ptr),y
        sta     VGA_DATA
        iny
        bne     @l
@x:     rts

; esp_vsync - C=1 if a vblank started since the last call; A = STATUS
esp_vsync:
        lda     VGA_STATUS
        pha
        and     #ST_VBL
        cmp     #1
        pla
        rts

; esp_reset - the console back to text only (jump table SBC_CONRESET)
esp_reset       = esp_init

.segment "DRVVARS"
esp_w:         .res 2                  ; (box width)
esp_h:          .res 1
