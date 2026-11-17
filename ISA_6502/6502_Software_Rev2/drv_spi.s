; ============================================================================
; drv_spi.s - Daryl Rictor's 65SPI on the ISA6502_Advanced_IO card ($7F28-$7F2B)
;
;   $7F28  read: data in              write: data out (starts a shift)
;   $7F29  read: status               write: control
;          status  b7 TC  b6 BSY  b5 IER  b4 FRX  b3 TMO  b2 ECE  b1 CPOL  b0 CPHA
;          control b7 SR (software reset), b5-b0 as above
;   $7F2A  slave select register (SS0-SS7 outputs, active low; $FF = none)
;
; SCLK = PHI2 / 2 (the CPU clock), MSB first.  The driver uses the polled TC
; flag: a byte takes 16 CPU cycles, far less than an interrupt would cost, so
; the card's IRQ7 jumper can stay off.
; ============================================================================

SPI_DATA        = $7F28
SPI_STAT        = $7F29
SPI_CTRL        = $7F29
SPI_SS          = $7F2A

SPI_MODE0       = $00                   ; CPOL 0, CPHA 0, PHI2 clock, no IRQ

.segment "DRVVARS"
spi_ok:         .res 1                  ; $80 = the 65SPI answered

.segment "BIOS"

; ----------------------------------------------------------------------------
; spi_init - reset the 65SPI, mode 0, nothing selected.  C=0 if it answered:
; the mode bits written to the control register read back in the status.
; Clobbers A.
; ----------------------------------------------------------------------------
spi_init:
        lda     #0
        sta     spi_ok
        lda     #$80                    ; software reset
        sta     SPI_CTRL
        lda     #$FF                    ; no slave selected
        sta     SPI_SS
        lda     #$03                    ; mode 3: CPOL / CPHA should read back
        sta     SPI_CTRL
        lda     SPI_STAT
        and     #$3F
        cmp     #$03
        bne     @no
        lda     #SPI_MODE0
        sta     SPI_CTRL
        lda     SPI_STAT
        and     #$3F
        cmp     #SPI_MODE0
        bne     @no
        lda     SPI_DATA                ; clear TC
        lda     #$80
        sta     spi_ok
        clc
        rts
@no:    sec
        rts

; ----------------------------------------------------------------------------
; spi_xfer - send A, return the byte received in A.  Preserves X and Y.
; ----------------------------------------------------------------------------
spi_xfer:
        sta     SPI_DATA                ; starts the shift
@w:     bit     SPI_STAT                ; TC (bit 7) -> N
        bpl     @w
        lda     SPI_DATA                ; the byte in (also clears TC)
        rts

; ----------------------------------------------------------------------------
; spi_select - A = slave select register value (e.g. $FE = SS0), $FF = none
; ----------------------------------------------------------------------------
spi_select:
        sta     SPI_SS
        rts
