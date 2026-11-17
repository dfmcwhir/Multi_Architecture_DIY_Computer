; ============================================================================
; drv_acia.s - 6551 ACIA on the serial card ($7F14-$7F17, IRQ3)
;
; ACIA_TO_CON = 1 (config.inc: ACIA_CONSOLE, or CON_SERIAL = SER_ACIA):
;     receive interrupts on; what arrives is typed into the console.
; ACIA_TO_CON = 0:
;     receive interrupts off; the port is free for your own programs
;     (SBC_ACIAIN / SBC_ACIAOUT in the jump table, e.g. a modem).
;
; ACIA_WDC = 1: the W65C51N's "transmit register empty" flag doesn't work,
; so after each byte the driver waits one character time instead.
; ============================================================================

ACIA_DATA       = $7F14
ACIA_STATUS     = $7F15
ACIA_CMD        = $7F16
ACIA_CTRL       = $7F17

; control register: 1 stop bit, 8 data bits, internal baud rate generator
.if ACIA_BAUD = 1200
ACIA_CTRL_VAL   = $18
.elseif ACIA_BAUD = 2400
ACIA_CTRL_VAL   = $1A
.elseif ACIA_BAUD = 4800
ACIA_CTRL_VAL   = $1C
.elseif ACIA_BAUD = 9600
ACIA_CTRL_VAL   = $1E
.elseif ACIA_BAUD = 19200
ACIA_CTRL_VAL   = $1F
.else
  .error "config.inc: ACIA_BAUD must be 1200, 2400, 4800, 9600 or 19200"
.endif

; command register: no parity, no echo, RTS low + TX interrupt off, DTR on;
; receive interrupt on only when the port feeds the console
.if ACIA_TO_CON
ACIA_CMD_VAL    = $89
.else
ACIA_CMD_VAL    = $8B
.endif

; W65C51N: one character (11 bit times, a little margin) in 5-cycle loops
ACIA_CHAR_LOOPS = (CPU_KHZ * 11000 / ACIA_BAUD) / 5 + 1

; ~0.15 s timeout for "transmit register empty" in 11-cycle loops
ACIA_TX_TIMEOUT = CPU_KHZ * 150 / 11
.if ACIA_TX_TIMEOUT > $FE00
  ACIA_TX_TO    = $FE00
.else
  ACIA_TX_TO    = ACIA_TX_TIMEOUT
.endif

.segment "DRVVARS"
acia_ok:        .res 1                  ; $80 = answered at boot

.segment "BIOS"

; ----------------------------------------------------------------------------
; acia_init - C=0 if the 6551 answered.  Clobbers A.
; ----------------------------------------------------------------------------
acia_init:
        lda     #0
        sta     acia_ok
        sta     ACIA_STATUS             ; programmed reset
        lda     #ACIA_CTRL_VAL
        sta     ACIA_CTRL
        eor     ACIA_CTRL               ; the control register reads back
        bne     @absent
        lda     #ACIA_CMD_VAL
        sta     ACIA_CMD
        lda     ACIA_DATA               ; drop anything stale
        lda     #$80
        sta     acia_ok
        lda     #2
        ora     DEVSTAT
        sta     DEVSTAT                 ; device status bit 1
        clc
        rts
@absent:
        sec
        rts

; ----------------------------------------------------------------------------
; acia_irq - from irq.s (and CHRIN's polling).  C=1 = a byte was received and
; put in the console buffer; C=0 = not ours.  Clobbers A, X.
; ----------------------------------------------------------------------------
acia_irq:
        lda     ACIA_STATUS             ; (reading it clears the IRQ flag)
        and     #$08                    ; receive register full?
        beq     @no
        lda     ACIA_DATA
.if ACIA_TO_CON
        jsr     CON_PUTKEY
.endif
        sec
        rts
@no:    clc
        rts

; ----------------------------------------------------------------------------
; acia_putc - send A.  Gives up after ~0.15 s if the 6551 never gets ready.
; Preserves A; clobbers X, Y.
; ----------------------------------------------------------------------------
acia_putc:
        bit     acia_ok
        bpl     @x
.if ACIA_WDC
        sta     ACIA_DATA
        ldx     #<ACIA_CHAR_LOOPS
        ldy     #((ACIA_CHAR_LOOPS >> 8) + 1)
@d:     dex                             ; 5 cycles a loop
        bne     @d
        dey
        bne     @d
.else
        pha
        ldx     #<ACIA_TX_TO
        ldy     #((ACIA_TX_TO >> 8) + 1)
@w:     lda     ACIA_STATUS             ; 4
        and     #$10                    ; 2  transmit register empty?
        bne     @go                     ; 2
        dex                             ; 2
        bne     @w                      ; 3  (11 cycles a loop)
        dey
        bne     @w
        pla                             ; timed out: drop the byte
        rts
@go:    pla
        sta     ACIA_DATA
.endif
@x:     rts

; ----------------------------------------------------------------------------
; acia_getc - for programs using the port themselves (ACIA_TO_CON = 0):
; C=1 and A = the byte, or C=0 if nothing has arrived.  Preserves X and Y.
; ----------------------------------------------------------------------------
acia_getc:
        bit     acia_ok
        bpl     @no
        lda     ACIA_STATUS
        and     #$08
        beq     @no
        lda     ACIA_DATA
        sec
        rts
@no:    lda     #0
        clc
        rts
