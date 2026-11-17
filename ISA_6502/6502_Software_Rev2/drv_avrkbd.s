; ============================================================================
; drv_avrkbd.s - AVR keyboard / mouse / serial console interface
;               (Serial Rev3 card or PICO9918 card; only one is fitted)
;
;   $7F1E read : next byte from the AVR's queue (reading it acknowledges it)
;   $7F1E write: byte to send out of the AVR's serial port, or a command
;   $7F1F read : status  D7 = KBAVAIL (1 = byte waiting)    -> BIT sets N
;                        D6 = DBUSY   (1 = TX byte not taken) -> BIT sets V
;   KBAVAIL drives the card's IRQ line (jumper 5 or 6: AVRKBD_IRQ).
;
; Byte stream from the AVR:
;   $00-$FE        a key (PS/2 keyboard, or a byte from the serial port)
;   $FF $FF        a literal $FF from the serial port
;   $FF $01 b x y  mouse report: b buttons (bit0 L, bit1 R, bit2 M),
;                  x/y signed movement (right / down positive)
; Commands to the AVR:  $FF $01 mouse on   $FF $00 mouse off   $FF $FF = $FF
;
; The AVR loads its next byte only after the previous one has been read, so
; a mouse report arrives one byte per interrupt; avr_state keeps track of
; where we are between interrupts.  Exactly one byte is read per call, and
; only when KBAVAIL says one is there.
; ============================================================================

AVR_DATA        = $7F1E
AVR_STAT        = $7F1F
AVR_ESC         = $FF

; Boot: wait up to ~0.2 s for DBUSY = 0 (the AVR clears it when it starts).
; The loop is 11 cycles, 256 per page; at most 255 pages.
AVR_BOOT_PAGES0 = CPU_KHZ * 200 / 2816 + 1
.if AVR_BOOT_PAGES0 > 255
AVR_BOOT_PAGES  = 255
.else
AVR_BOOT_PAGES  = AVR_BOOT_PAGES0
.endif
; Sending: give up after ~20 ms (11-cycle loops).  The AVR takes a byte in
; well under 1 ms unless its 256 byte TX buffer is full (then ~87 us a byte).
AVR_TX_TO       = CPU_KHZ * 20 / 11

.segment "DRVVARS"
avr_ok:         .res 1                  ; $80 = the AVR answered
avr_state:      .res 1                  ; 0 normal, 1 after $FF, 2-4 mouse b/x/y
ms_dx:          .res 1                  ; mouse movement since the last read,
ms_dy:          .res 1                  ;   signed, held at -128 / +127
ms_btn:         .res 1                  ; mouse buttons now
ms_new:         .res 1                  ; $80 = a report arrived since the last read

.segment "BIOS"

; ----------------------------------------------------------------------------
; avrkbd_init - C=0 if the AVR answered.  Turns mouse reports off (a 6502
; reset doesn't reset the AVR).  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
avrkbd_init:
        lda     #0
        sta     avr_ok
        sta     avr_state
        sta     ms_dx
        sta     ms_dy
        sta     ms_btn
        sta     ms_new
        ldx     #0
        ldy     #AVR_BOOT_PAGES
@w:     bit     AVR_STAT                ; 4
        bvc     @ok                     ; 2  DBUSY clear: the AVR is running
        dex                             ; 2
        bne     @w                      ; 3
        dey
        bne     @w
        sec                             ; DBUSY never cleared (an empty bus
        rts                             ; reads $7F: DBUSY looks stuck at 1)
@ok:    lda     #$80
        sta     avr_ok
        lda     #8
        ora     DEVSTAT
        sta     DEVSTAT                 ; device status bit 3
        lda     #0
        jsr     MOUSE_ON                ; mouse reports off
        clc
        rts

; ----------------------------------------------------------------------------
; avrkbd_irq - from irq.s (and CHRIN's polling).  Reads at most one byte.
; C=1 = a byte was taken; C=0 = nothing waiting.  Clobbers A, X.
; ----------------------------------------------------------------------------
avrkbd_irq:
        bit     AVR_STAT
        bmi     @have
        clc
        rts
@have:  lda     AVR_DATA                ; reading it acknowledges it
        ldx     avr_state
        bne     @esc
        cmp     #AVR_ESC
        beq     @setesc
@key:   jsr     CON_PUTKEY              ; a key
@yes:   sec
        rts
@setesc:
        inc     avr_state               ; 0 -> 1
        sec
        rts

@esc:   cpx     #1
        bne     @mouse
        ldx     #0                      ; the byte after $FF:
        stx     avr_state
        cmp     #AVR_ESC
        beq     @key                    ;   $FF $FF = a literal $FF
        cmp     #$01
        bne     @yes                    ;   unknown: dropped
        lda     #2                      ;   $FF $01: a mouse report follows
        sta     avr_state
        sec
        rts

@mouse: cpx     #2
        bne     @xy
        sta     ms_btn                  ; state 2: buttons
        inc     avr_state
        sec
        rts
@xy:    cpx     #3                      ; (X is still avr_state)
        beq     @addx                   ; state 3: x -> ms_dx
        ldx     #1                      ; state 4: y -> ms_dy, report done
        jsr     ms_add
        lda     #$80
        sta     ms_new
        lda     #0
        sta     avr_state
        sec
        rts
@addx:  ldx     #0
        jsr     ms_add
        inc     avr_state
        sec
        rts

; ms_add - ms_dx,x = ms_dx,x + A, signed, held at -128 / +127
ms_add: clc
        adc     ms_dx,x
        bvc     @st                     ; no signed overflow
        bmi     @pos                    ; overflowed upward (wrapped negative)
        lda     #$80                    ; overflowed downward
        bne     @st
@pos:   lda     #$7F
@st:    sta     ms_dx,x
        rts

; ----------------------------------------------------------------------------
; avrkbd_putc - send A out of the AVR's serial port ($FF is sent as $FF $FF).
; Preserves A; clobbers X, Y.
; ----------------------------------------------------------------------------
avrkbd_putc:
        bit     avr_ok
        bpl     avr_x
        cmp     #AVR_ESC
        bne     avr_send
        jsr     avr_send                ; first $FF of the pair
        ; (falls into avr_send for the second)

; avr_send - write A to $7F1E once DBUSY is clear.  If the AVR doesn't take a
; byte within ~20 ms it is marked dead (avr_ok = 0) so output can't hang.
; Preserves A; clobbers X, Y.
avr_send:
        ldx     #<AVR_TX_TO
        ldy     #((AVR_TX_TO >> 8) + 1)
@w:     bit     AVR_STAT                ; 4
        bvc     @go                     ; 2
        dex                             ; 2
        bne     @w                      ; 3
        dey
        bne     @w
        ldx     #0
        stx     avr_ok
        rts
@go:    sta     AVR_DATA
avr_x:  rts

; ----------------------------------------------------------------------------
; MOUSE_ON - A = 1: mouse reports on, A = 0: off.  Clears the movement so far.
; C=1 if there is no mouse interface.  Clobbers A, X, Y.
; ----------------------------------------------------------------------------
MOUSE_ON:
        bit     avr_ok
        bpl     @none
        pha
        lda     #AVR_ESC
        jsr     avr_send
        pla
        and     #$01                    ; $FF $01 = on, $FF $00 = off
        jsr     avr_send
        php
        sei
        lda     #0
        sta     ms_dx
        sta     ms_dy
        sta     ms_new
        plp
        clc
        rts
@none:  sec
        rts

; ----------------------------------------------------------------------------
; MOUSE_READ - A = buttons, X = x movement, Y = y movement (signed, since the
; last MOUSE_READ; right/down positive).  C=1 if a report arrived since the
; last call, C=0 if not (X = Y = 0 then).
; ----------------------------------------------------------------------------
MOUSE_READ:
        php
        sei
        ldx     ms_dx
        ldy     ms_dy
        lda     #0
        sta     ms_dx
        sta     ms_dy
        lda     ms_new
        asl     a                       ; bit 7 -> carry
        lda     #0
        sta     ms_new
        lda     ms_btn
        bcs     @new
        plp
        clc
        rts
@new:   plp
        sec
        rts
