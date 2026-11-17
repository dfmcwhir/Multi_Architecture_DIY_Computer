; ============================================================================
; drv_via.s - 65C22 VIA on the ISA6502_IO card ($7F00-$7F0F, IRQ2)
;
; Timer 1 is the 60 Hz system tick.  The timer counts only 16 bits, so on a
; fast clock it runs TICK_DIV times faster and every TICK_DIV-th timeout is a
; tick:  up to 3 MHz 60 Hz,  4-7 MHz 120 Hz (every 2nd),  8-11 MHz 180 Hz ...
; Each tick: the 60 Hz counter, the gamepad poll and BASIC's timed notes.
; Port A: gamepad (gamepad.s).  Port B: device status LEDs (DEVSTAT).
; ============================================================================

PORTB           = $7F00
PORTA           = $7F01
DDRB            = $7F02
DDRA            = $7F03
VIA_T1CL        = $7F04                 ; timer 1 counter low  (reading clears its flag)
VIA_T1CH        = $7F05                 ; timer 1 counter high (writing starts it)
VIA_T1LL        = $7F06                 ; timer 1 latch low
VIA_T1LH        = $7F07                 ; timer 1 latch high
VIA_ACR         = $7F0B                 ; auxiliary control register
IFR             = $7F0D
IER             = $7F0E

TICK_HZ         = 60
TICK_DIV        = ((CPU_KHZ * 1000) / TICK_HZ - 2) / 65536 + 1
TICK_T1         = (CPU_KHZ * 1000) / (TICK_HZ * TICK_DIV) - 2
.assert TICK_T1 > 0 .and TICK_T1 < 65536, error, "TICK_T1 doesn't fit the 16 bit VIA timer"

.segment "DRVVARS"
via_ok:         .res 1                  ; $80 = VIA answered at boot
tick_div:       .res 1                  ; timer 1 timeouts until the next tick
ticks:          .res 3                  ; 60 Hz counter, low byte first

.segment "BIOS"

; ----------------------------------------------------------------------------
; VIA_INIT - check the VIA is there, set up port B (LEDs) and start the tick.
; Clobbers A.
; ----------------------------------------------------------------------------
VIA_INIT:
        lda     #0
        sta     via_ok
        sta     ticks
        sta     ticks+1
        sta     ticks+2
        lda     #$7F                    ; disable all VIA interrupts
        sta     IER
        lda     IER                     ; IER reads back with bit 7 = 1:
        cmp     #$80                    ; $80 now if the VIA is there
        bne     @done                   ; (an empty bus reads $7F)
        lda     #$80
        sta     via_ok
        lda     #1
        ora     DEVSTAT
        sta     DEVSTAT                 ; device status bit 0
        lda     #$7F
        sta     IFR                     ; clear any old flags
        lda     #$FF
        sta     DDRB                    ; port B: status LEDs
        lda     #TICK_DIV
        sta     tick_div
        lda     VIA_ACR                 ; timer 1 free running, interrupt on timeout
        and     #$3F
        ora     #$40
        sta     VIA_ACR
        lda     #<TICK_T1
        sta     VIA_T1LL
        lda     #>TICK_T1
        sta     VIA_T1CH                ; loads the counter and starts it
        lda     #$C0                    ; enable the timer 1 interrupt
        sta     IER
@done:  rts

; ----------------------------------------------------------------------------
; via_irq - from irq.s.  C=1 = handled; C=0 = another VIA source wants
; attention (passed on to BASIC's ON IRQ).
; ----------------------------------------------------------------------------
via_irq:
        lda     IFR
        and     #$40                    ; timer 1 timeout?
        beq     @other
        lda     VIA_T1CL                ; reading the low counter clears the flag
.if HAS_SPO
        jsr     spo_tick                ; speech: every timeout (60-180 Hz)
.endif
        dec     tick_div
        bne     @other
        lda     #TICK_DIV
        sta     tick_div
        inc     ticks
        bne     :+
        inc     ticks+1
        bne     :+
        inc     ticks+2
:
.if HAS_GAMEPAD
        jsr     PAD_POLL
.endif
.if SND_DEV <> SND_NONE
        jsr     SND_TICK                ; timed notes (basic_ay.s)
.endif
@other: lda     IFR
        and     IER
        and     #$3F                    ; another enabled VIA source?
        beq     @mine
        clc
        rts
@mine:  sec
        rts

; ----------------------------------------------------------------------------
; TICKS_GET - A/X/Y = the 60 Hz counter, low/middle/high
; ----------------------------------------------------------------------------
TICKS_GET:
        php
        sei
        lda     ticks
        ldx     ticks+1
        ldy     ticks+2
        plp
        rts
