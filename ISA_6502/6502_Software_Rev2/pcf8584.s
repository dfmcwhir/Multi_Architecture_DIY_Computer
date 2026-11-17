; ============================================================================
; pcf8584.s - PCF8584 parallel-bus to I2C bridge driver (master mode, polled)
;
; Ported from pcf8584_lcd_test.s (vasm) to ca65.  Contains only the bus layer:
;   pcf_init       initialise the chip                    C=1 on failure
;   i2c_start      START + address byte (i2c_addr)        C=1 on NACK / timeout
;   i2c_send       send byte in A                         C=1 on NACK / timeout
;   i2c_read1      START + read ONE byte, then STOP       C=1 on failure, A=byte
;   i2c_stop       STOP
;   delay_ms       delay A milliseconds
;
; Transfers are polled.  The chip's INT output (your IRQ4) stays silent because
; the ENI bit is never set in the control register.  The BIOS routes IRQ4 to
; EhBASIC's "ON IRQ" flag, so nothing happens there unless you add interrupt
; driven transfers later.
;
; Included from main.s after basic.s.  Code is in segment BIOS, variables in
; BIOSVARS (both placed by sbc.cfg).
; ============================================================================

; ---------------- user configuration ----------------------------------------
; CPU_MHZ (CPU clock in whole MHz) is set once, at the top of main.s

PCF_S0      = $7F10         ; A0=0 : S0 data / S0' own addr / S2 clock (selected via S1)
PCF_S1      = $7F11         ; A0=1 : S1 control (write) / status (read)

PCF_OWN     = $55           ; PCF8584's own I2C address (must not clash with your devices)

; S2 clock register = (PCF CLK pin frequency) + (SCL frequency)
;   CLK pin freq: $00 = 3 MHz, $10 = 4.43 MHz, $14 = 6 MHz, $18 = 8 MHz, $1C = 12 MHz
;   SCL freq    : +0 = 90 kHz, +1 = 45 kHz, +2 = 11 kHz, +3 = 1.5 kHz
; NOTE: the original test file said "$00 = 8 MHz clock" but by the table above
; $00 means a 3 MHz clock on the CLK pin.  Set this for YOUR oscillator.
PCF_CLOCK   = $00

; ---------------- PCF8584 bits ------------------------------------------------
; Control register (write)
PCF_PIN     = $80
PCF_ESO     = $40
PCF_ES1     = $20
PCF_STA     = $04
PCF_STO     = $02
PCF_ACK     = $01
; Status register (read)
PCF_ST_LRB  = $08           ; last received bit: 0 = ACK, 1 = NACK
PCF_ST_BB   = $01           ; bus busy (inverted: 1 = bus FREE)

CTRL_IDLE   = PCF_PIN+PCF_ESO+PCF_ACK              ; $C1
CTRL_START  = PCF_PIN+PCF_ESO+PCF_STA+PCF_ACK      ; $C5
CTRL_STOP   = PCF_PIN+PCF_ESO+PCF_STO+PCF_ACK      ; $C3
CTRL_NOACK  = PCF_PIN+PCF_ESO                      ; $C0 (receive last byte)

; ---------------- variables ---------------------------------------------------
.segment "BIOSVARS"
i2c_dly:    .res 1          ; delay_ms counter
i2c_addr:   .res 1          ; slave address byte (incl. R/W bit) for i2c_start
pcf_stat:   .res 1          ; last PCF status (for debugging)
pcf_ready:  .res 1          ; non-zero once pcf_init has succeeded

.segment "BIOS"

; ============================================================================
; PCF8584 initialisation (datasheet sequence)
; Returns C=0 on success, C=1 on failure (raw status in pcf_stat)
; ============================================================================
pcf_init:
        lda     #PCF_PIN            ; $80: ESO=0 -> next A0=0 access is S0' (own address)
        sta     PCF_S1
        lda     #PCF_OWN
        sta     PCF_S0              ; write own address
        lda     #PCF_PIN+PCF_ES1    ; $A0: next A0=0 access is S2 (clock)
        sta     PCF_S1
        lda     #PCF_CLOCK
        sta     PCF_S0              ; write clock register
        lda     #1
        jsr     delay_ms            ; let the internal clock settle
        lda     #CTRL_IDLE          ; $C1: serial interface on, ACK enabled
        sta     PCF_S1
        lda     #1
        jsr     delay_ms
        lda     PCF_S1              ; expect PIN=1 and BB=1 (bus free) -> $81
        sta     pcf_stat
        and     #PCF_PIN+PCF_ST_BB
        cmp     #PCF_PIN+PCF_ST_BB
        bne     @fail
        clc
        rts
@fail:  sec
        rts

; ============================================================================
; Wait for PIN to go low (byte transfer finished)
; Returns C=0 and A=status, or C=1 on timeout.  Clobbers X, Y.
; ============================================================================
pcf_wait_pin:
        ldx     #16
        ldy     #0
@loop:  lda     PCF_S1
        bpl     @ok                 ; bit7 (PIN) = 0 -> done
        dey
        bne     @loop
        dex
        bne     @loop
        sec
        rts
@ok:    sta     pcf_stat
        clc
        rts

; ============================================================================
; I2C: START + address.  i2c_addr = 8-bit address byte (incl. R/W)
; Returns C=0 if slave ACKed, C=1 on timeout/NACK.  Clobbers A, X, Y.
; ============================================================================
i2c_start:
        ldx     #16                 ; wait for bus free (BB=1)
        ldy     #0
@bb:    lda     PCF_S1
        and     #PCF_ST_BB
        bne     @go
        dey
        bne     @bb
        dex
        bne     @bb
        sec
        rts
@go:    lda     i2c_addr
        sta     PCF_S0              ; address goes into S0 first
        lda     #CTRL_START
        sta     PCF_S1              ; then START
        jsr     pcf_wait_pin
        bcs     @rts                ; timeout (C already set)
        and     #PCF_ST_LRB         ; 0 = ACK
        cmp     #1                  ; A=0 -> C=0 ; A=8 -> C=1
@rts:   rts

; ============================================================================
; I2C: send byte in A.  Returns C=0 if ACKed, C=1 on timeout/NACK
; ============================================================================
i2c_send:
        sta     PCF_S0
        jsr     pcf_wait_pin
        bcs     @rts
        and     #PCF_ST_LRB
        cmp     #1
@rts:   rts

; ============================================================================
; I2C: STOP
; ============================================================================
i2c_stop:
        lda     #CTRL_STOP
        sta     PCF_S1
        rts

; ============================================================================
; I2C: read ONE byte.  i2c_addr must hold the address byte with R/W = 1.
; Sends START + address, receives a single byte with NACK, then STOP.
; Returns C=0 and A = byte, or C=1 on NACK / timeout (bus is released).
; Follows the sequence used by the Linux i2c-algo-pcf driver.
; ============================================================================
i2c_read1:
        jsr     i2c_start           ; START + address (R)
        bcs     @fail
        lda     #CTRL_NOACK         ; this is the last byte: do not ACK it
        sta     PCF_S1
        lda     PCF_S0              ; dummy read of S0 starts the byte clocking in
        jsr     pcf_wait_pin
        bcs     @fail
        lda     #CTRL_STOP          ; STOP, then fetch the received byte
        sta     PCF_S1
        lda     PCF_S0
        clc
        rts
@fail:  jsr     i2c_stop
        sec
        rts

; ============================================================================
; Delay A milliseconds (approximate, errs on the long side)
; ============================================================================
delay_ms:
        sta     i2c_dly
@ms:    ldx     #CPU_MHZ
@outer: ldy     #200                ; 200 * 5 cycles = 1000 cycles = 1 ms @ 1 MHz
@inner: dey
        bne     @inner
        dex
        bne     @outer
        dec     i2c_dly
        bne     @ms
        rts
