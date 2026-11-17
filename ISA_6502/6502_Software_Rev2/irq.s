; ============================================================================
; irq.s - interrupt dispatch for the CPU card Rev2
;
; The 74LS148 + '574 interrupt register at $7FFF reads (7 - n) * 2 for the
; highest priority line that is active (IRQ0 highest).  IRQTABLE turns that
; into the handler for line n.
;
; Each line's handler is built from config.inc: it calls the _irq routine of
; every driver jumpered to that line, in a fixed order (keyboard first).  A
; driver's _irq routine checks its own card and returns
;       carry set   = it was this card, and it has been serviced
;       carry clear = not this card
; If no driver claims the interrupt it goes to IRQ_BASIC, which feeds
; EhBASIC's ON IRQ (a plain RTI when BASIC hasn't enabled ON IRQ).
; A source that is still active after the RTI simply interrupts again.
;
; Lines (see the design notes):
;   0, 1  header (spare)       2  VIA (tick, gamepad)      3  serial card 6551
;   4     PCF8584 (unused)     5  KB_MONITOR_TERM, or a 5/6 jumper card
;   6     a 5/6 jumper card    7  65SPI / SPO256 (jumpers)
; ============================================================================

IRQPORT         = $7FFF

.zeropage
TEMP_IRQ_ADDR:  .res 2

.segment "BIOS"

IRQ_ENTRY:
        pha
        txa
        pha
        tya
        pha
        cld
        lda     IRQPORT
        and     #$0E
        tax
        lda     IRQTABLE,x
        sta     TEMP_IRQ_ADDR
        lda     IRQTABLE+1,x
        sta     TEMP_IRQ_ADDR+1
        jmp     (TEMP_IRQ_ADDR)

IRQTABLE:                               ; register value 0 = IRQ7 ... 14 = IRQ0
        .word   IRQ7, IRQ6, IRQ5, IRQ4, IRQ3, IRQ2, IRQ1, IRQ0

; Not claimed by a driver: EhBASIC's ON IRQ.  If BASIC has enabled IRQ
; handling, the flag is set and the BASIC handler runs after the current
; statement (it must clear the source itself).  Otherwise IrqBase is 0 and
; this does nothing.
IRQ_BASIC:
        lda     IrqBase
        lsr     a
        ora     IrqBase
        sta     IrqBase
IRQ_EXIT:
        pla
        tay
        pla
        tax
        pla
        rti

; ----------------------------------------------------------------------------
; IRQ_CALL handler - call one driver; if it claimed the interrupt, we're done
; ----------------------------------------------------------------------------
.macro IRQ_CALL handler
        jsr     handler
        bcc     :+
        jmp     IRQ_EXIT
:
.endmacro

; ----------------------------------------------------------------------------
; IRQ_LINE n - the handler for line n, from the settings in config.inc
; ----------------------------------------------------------------------------
.macro IRQ_LINE n
.ident(.sprintf("IRQ%d", n)):
  .if HAS_AVRKBD                        ; keyboard first: typing stays responsive
    .if AVRKBD_IRQ = n
        IRQ_CALL avrkbd_irq
    .endif
  .endif
  .if ESP_KEYS
    .if ESP32_IRQ <> 0 .and ESP32_IRQ = n
        IRQ_CALL esp_irq
    .endif
  .endif
  .if CON_DISPLAY = DISP_PICO
    .if PICO_IRQ <> 0 .and PICO_IRQ = n
        IRQ_CALL pico_irq
    .endif
  .endif
  .if CON_DISPLAY = DISP_TERM
    .if n = 5
        IRQ_CALL term_irq
    .endif
  .endif
  .if HAS_ACIA
    .if n = 3
        IRQ_CALL acia_irq
    .endif
  .endif
  .if HAS_VIA
    .if n = 2
        IRQ_CALL via_irq
    .endif
  .endif
        jmp     IRQ_BASIC
.endmacro

        IRQ_LINE 0
        IRQ_LINE 1
        IRQ_LINE 2
        IRQ_LINE 3
        IRQ_LINE 4
        IRQ_LINE 5
        IRQ_LINE 6
        IRQ_LINE 7
