; ============================================================================
; drv_kbterm.s - KB_MONITOR_TERM display card (PIC32 terminal + keyboard)
;
; One 6551 at $7F18-$7F1B, 115200 baud from the card's 16x clock, IRQ5.
; Characters written go to the PIC32 terminal; keys come back on the same
; 6551 (one interrupt for both).  The terminal's own control codes (cursor,
; colours, graphics blocks, tiles ...) pass straight through CHROUT.
; ============================================================================

TERM_DATA       = $7F18
TERM_STATUS     = $7F19
TERM_CMD        = $7F1A
TERM_CTRL       = $7F1B

TERM_CTRL_VAL   = $10                   ; 8N1, external 16x clock: 115200
TERM_CMD_VAL    = $89                   ; no parity/echo, RX interrupt on, DTR on

TERM_CHAR_LOOPS = (CPU_KHZ * 11000 / 115200) / 5 + 1   ; W65C51N wait
TERM_TX_TO      = CPU_KHZ * 20 / 11                    ; ~20 ms timeout

.segment "DRVVARS"
term_ok:        .res 1                  ; $80 = answered at boot

.segment "BIOS"

; ----------------------------------------------------------------------------
; term_init - C=0 if the card answered.  Clobbers A.
; ----------------------------------------------------------------------------
term_init:
        lda     #0
        sta     term_ok
        sta     TERM_STATUS             ; programmed reset
        lda     #TERM_CTRL_VAL
        sta     TERM_CTRL
        eor     TERM_CTRL               ; the control register reads back
        bne     @absent
        lda     #TERM_CMD_VAL
        sta     TERM_CMD
        lda     TERM_DATA               ; drop anything stale
        lda     #$80
        sta     term_ok
        lda     #4
        ora     DEVSTAT
        sta     DEVSTAT                 ; device status bit 2
        ldx     #(TERM_BOOT_MS / 100)   ; the PIC32 may still be starting up:
@b:     txa                             ; give it TERM_BOOT_MS before the
        pha                             ; first character
        lda     #100
        jsr     DELAY_MS
        pla
        tax
        dex
        bne     @b
        clc
        rts
@absent:
        sec
        rts

; ----------------------------------------------------------------------------
; term_irq - from irq.s (and CHRIN's polling).  C=1 = a key was received and
; put in the console buffer; C=0 = not ours.  Clobbers A, X.
; ----------------------------------------------------------------------------
term_irq:
        lda     TERM_STATUS             ; (reading it clears the IRQ flag)
        and     #$08                    ; receive register full?
        beq     @no
        lda     TERM_DATA
        jsr     CON_PUTKEY
        sec
        rts
@no:    clc
        rts

; ----------------------------------------------------------------------------
; term_putc - print A.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
term_putc:
        bit     term_ok
        bpl     @x
.if TERM_WDC
        sta     TERM_DATA
        ldx     #<TERM_CHAR_LOOPS
        ldy     #((TERM_CHAR_LOOPS >> 8) + 1)
@d:     dex
        bne     @d
        dey
        bne     @d
.else
        pha
        ldx     #<TERM_TX_TO
        ldy     #((TERM_TX_TO >> 8) + 1)
@w:     lda     TERM_STATUS
        and     #$10                    ; transmit register empty?
        bne     @go
        dex
        bne     @w
        dey
        bne     @w
        pla                             ; timed out: drop it
        rts
@go:    pla
        sta     TERM_DATA
.endif
@x:     rts
