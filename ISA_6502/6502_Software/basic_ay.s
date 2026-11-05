; ============================================================================
; basic_ay.s - EhBASIC statements and a function for the AY-3-8910 sound card
;              ($7F22 register number, $7F23 data; 2 MHz chip clock)
;
; NEW BASIC KEYWORDS (their tokens follow I2CREAD( in basic.s, after all of
; EhBASIC's own, so programs SAVEd before keep their meaning):
;
;   SOUND ch, freq, vol [, time]   a tone: channel 0-2 (A B C), frequency in Hz
;                                  (31 - 65535), volume 0-15 (16: follow the
;                                  envelope, see ENVELOPE)
;   NOTE ch, n, vol [, time]       the same with a note number: 0 = C1 ...
;                                  36 = C4 (middle C), 45 = A4 (440 Hz) ... 95 = B8
;   NOISE ch, period, vol [, time] noise on the channel instead of a tone;
;                                  period 0-31 (0 = the highest hiss)
;   ENVELOPE shape, period         the chip's envelope (one for all channels,
;                                  used by volume 16): shape 0-15 (8 saw down,
;                                  12 saw up, 10 or 14 triangle, 0 one fade out,
;                                  13 fade in and hold), period 0-65535 (one
;                                  ramp lasts period x 128 us)
;   QUIET                          all channels off
;   AYREG reg, value               write any register (0-15) as it is
;   x = AYREAD(reg)                read a register back: 14 and 15 are the I/O
;                                  ports A and B.  Needs a card that can be read
;                                  (AY38910_DEC rev 2); the first card gives 255.
;
; time: in 1/60 s (the gamepad's timer interrupt counts it down); 0 or left
; out = until changed.  With a time, the note stops by itself while BASIC goes
; on - and a timed SOUND / NOTE / NOISE first waits for the last timed one on
; its channel to finish, so a tune is just one statement per note:
;
;   10 FOR I = 1 TO 8 : READ N : NOTE 0, N, 12, 15 : NEXT
;   20 DATA 36,38,40,41,43,45,47,48
;
; plays a scale, a quarter of a second a note, one channel.  The other
; channels can play at the same time (their own queue of one).  CTRL-C stops
; a wait.  Without the timer interrupt (no VIA) a time is ignored.
;
; The interrupt writes the card too (to stop a note), so every write here is
; done with interrupts off between the register number and the data.
; ============================================================================

AY_ADDR     = $7F22
AY_DATA     = $7F23
AY_FULL     = 125000                ; 2 MHz / 16: the tone period is this / Hz

.segment "BIOSVARS"
snd_tl:     .res 3                  ; each channel: the time left (1/60 s)
snd_th:     .res 3
snd_mix:    .res 1                  ; the mixer (register 7) as last written
snd_ch:     .res 1                  ; the statement's arguments
snd_vol:    .res 1
snd_pl:     .res 1                  ;  the period (tone 12 bits, or noise)
snd_ph:     .res 1
snd_dl:     .res 1                  ;  the time
snd_dh:     .res 1
snd_q:      .res 3                  ; (the division)
snd_r:      .res 2

.segment "BIOS"

; ----------------------------------------------------------------------------
; AY_BOOT - called from RESET: all quiet
; ----------------------------------------------------------------------------
AY_BOOT:
        lda     #0
        ldx     #2
@t:     sta     snd_tl,x
        sta     snd_th,x
        dex
        bpl     @t
        ; (on into BI_QUIET)

; ----------------------------------------------------------------------------
; QUIET
; ----------------------------------------------------------------------------
BI_QUIET:
        php
        sei
        lda     #0
        ldx     #2
@c:     sta     snd_tl,x            ; no notes timed
        sta     snd_th,x
        dex
        bpl     @c
        ldx     #8                  ; volumes 0
@v:     jsr     ay_w0
        inx
        cpx     #11
        bne     @v
        lda     #$3F                ; mixer: all off (the I/O ports inputs)
        sta     snd_mix
        ldx     #7
        jsr     ay_w0
        plp
        rts

; register X = A (interrupts already off; keeps A, X)
ay_w0:  stx     AY_ADDR
        sta     AY_DATA
        rts

; register X = A with interrupts off (keeps A, X)
ay_w:   php
        sei
        stx     AY_ADDR
        sta     AY_DATA
        plp
        rts

; ----------------------------------------------------------------------------
; SND_TICK - from the timer interrupt (IRQ2, 60 a second): a timed note that
; runs out is made silent (its volume 0)
; ----------------------------------------------------------------------------
SND_TICK:
        ldx     #2
@l:     lda     snd_tl,x
        ora     snd_th,x
        beq     @n                  ; (not timed)
        lda     snd_tl,x
        bne     :+
        dec     snd_th,x
:       dec     snd_tl,x
        lda     snd_tl,x
        ora     snd_th,x
        bne     @n
        txa                         ; run out: its volume 0
        clc
        adc     #8
        sta     AY_ADDR
        lda     #0
        sta     AY_DATA
@n:     dex
        bpl     @l
        rts

; ----------------------------------------------------------------------------
; the arguments
; ----------------------------------------------------------------------------
snd_fc: jmp     LAB_FCER            ; "Function call Error"

; channel (0-2) into snd_ch
snd_getch:
        jsr     LAB_GTBY
        cpx     #3
        bcs     snd_fc
        stx     snd_ch
        rts

; ", n" (0-65535) into Itempl / Itemph
snd_getw:
        jsr     LAB_1C01            ; ","
        jsr     LAB_EVNM            ; a number
        jmp     LAB_F2FX            ; as an integer 0-65535

; ", vol [, time]": the volume (0-16) and the time (0: none)
snd_getvt:
        jsr     LAB_1C01
        jsr     LAB_GTBY
        cpx     #17
        bcs     snd_fc
        stx     snd_vol
        lda     #0
        sta     snd_dl
        sta     snd_dh
        jsr     LAB_GBYT            ; ", time"?
        cmp     #','
        bne     @r
        jsr     snd_getw
        lda     Itempl
        sta     snd_dl
        lda     Itemph
        sta     snd_dh
@r:     rts

; ----------------------------------------------------------------------------
; SOUND ch, freq, vol [, time]
; ----------------------------------------------------------------------------
BI_SOUND:
        jsr     snd_getch
        jsr     snd_getw            ; the frequency
        lda     Itempl
        ora     Itemph
        beq     snd_fc              ; (0 Hz)
        lda     #<AY_FULL           ; period = 125000 / Hz
        sta     snd_q
        lda     #>AY_FULL
        sta     snd_q+1
        lda     #^AY_FULL
        sta     snd_q+2
        jsr     snd_div
        lda     snd_q+2             ; more than 4095 (under 31 Hz): 4095
        bne     @max
        lda     snd_q+1
        cmp     #$10
        bcs     @max
        sta     snd_ph
        lda     snd_q
        sta     snd_pl
        ora     snd_ph
        bne     @ok
        inc     snd_pl              ; (0: 1)
        bne     @ok
@max:   lda     #$FF
        sta     snd_pl
        lda     #$0F
        sta     snd_ph
@ok:    jsr     snd_getvt
        jmp     snd_tone

; snd_q (24 bits) = snd_q / Itempl,h (16 bits)
snd_div:
        lda     #0
        sta     snd_r
        sta     snd_r+1
        ldx     #24
@l:     asl     snd_q
        rol     snd_q+1
        rol     snd_q+2
        rol     snd_r
        rol     snd_r+1
        bcs     @s                  ; (17 bits: more than the divisor)
        lda     snd_r
        sec
        sbc     Itempl
        tay
        lda     snd_r+1
        sbc     Itemph
        bcc     @n
        bcs     @k
@s:     lda     snd_r
        sbc     Itempl              ; (carry set)
        tay
        lda     snd_r+1
        sbc     Itemph
@k:     sta     snd_r+1
        sty     snd_r
        inc     snd_q
@n:     dex
        bne     @l
        rts

; ----------------------------------------------------------------------------
; NOTE ch, n, vol [, time]
; ----------------------------------------------------------------------------
BI_NOTE:
        jsr     snd_getch
        jsr     LAB_1C01
        jsr     LAB_GTBY            ; the note
        cpx     #96
        bcc     :+
        jmp     LAB_FCER
:
        lda     snd_nlo,x
        sta     snd_pl
        lda     snd_nhi,x
        sta     snd_ph
        jsr     snd_getvt
        ; (on into snd_tone)

; the tone (snd_pl/ph) on channel snd_ch at snd_vol for snd_dl/dh
snd_tone:
        jsr     snd_wait
        php
        sei
        lda     snd_ch              ; the period
        asl
        tax
        lda     snd_pl
        jsr     ay_w0
        inx
        lda     snd_ph
        jsr     ay_w0
        ldx     snd_ch              ; mixer: its tone on, its noise off
        lda     snd_mix
        and     tone_on,x
        ora     noise_off,x
        jmp     snd_go

; ----------------------------------------------------------------------------
; NOISE ch, period, vol [, time]
; ----------------------------------------------------------------------------
BI_NOISE:
        jsr     snd_getch
        jsr     LAB_1C01
        jsr     LAB_GTBY            ; the noise period
        cpx     #32
        bcc     :+
        jmp     LAB_FCER
:
        stx     snd_pl
        jsr     snd_getvt
        jsr     snd_wait
        php
        sei
        lda     snd_pl
        ldx     #6
        jsr     ay_w0
        ldx     snd_ch              ; mixer: its noise on, its tone off
        lda     snd_mix
        and     noise_on,x
        ora     tone_off,x
        ; (on into snd_go)

; mixer = A, then the volume and the time (interrupts off; ends with plp)
snd_go: and     #$3F                ; (the I/O ports kept inputs)
        sta     snd_mix
        ldx     #7
        jsr     ay_w0
        ldx     snd_ch
        lda     snd_dl              ; the time, then the volume
        sta     snd_tl,x
        lda     snd_dh
        sta     snd_th,x
        txa
        clc
        adc     #8
        tax
        lda     snd_vol
        jsr     ay_w0
        plp
        rts

; a timed note: wait for the last timed one on the channel to run out (only
; when the timer interrupt is on; CTRL-C stops the wait)
snd_wait:
        lda     snd_dl
        ora     snd_dh
        beq     @r                  ; (this one isn't timed)
        lda     $7F0E               ; the VIA's timer 1 interrupt on?
        and     #$40
        bne     @w
        sta     snd_dl              ; no: no times at all
        sta     snd_dh
        rts
@w:     ldx     snd_ch
        lda     snd_tl,x
        ora     snd_th,x
        beq     @r
        jsr     LAB_1629            ; (CTRL-C)
        jmp     @w
@r:     rts

tone_on:    .byte   $FE, $FD, $FB   ; (and: its bit 0)
tone_off:   .byte   $01, $02, $04   ; (or: its bit 1)
noise_on:   .byte   $F7, $EF, $DF
noise_off:  .byte   $08, $10, $20

; ----------------------------------------------------------------------------
; ENVELOPE shape, period
; ----------------------------------------------------------------------------
BI_ENVELOPE:
        jsr     LAB_GTBY            ; the shape
        cpx     #16
        bcs     @fc
        stx     snd_vol
        jsr     snd_getw            ; the period
        lda     Itempl
        ldx     #11
        jsr     ay_w
        lda     Itemph
        inx
        jsr     ay_w
        lda     snd_vol             ; the shape last: it starts the envelope
        inx
        jmp     ay_w
@fc:    jmp     LAB_FCER

; ----------------------------------------------------------------------------
; AYREG reg, value
; ----------------------------------------------------------------------------
BI_AYREG:
        jsr     LAB_GTBY            ; the register
        cpx     #16
        bcs     @fc
        stx     snd_ch
        jsr     LAB_1C01
        jsr     LAB_GTBY            ; the value
        txa
        ldx     snd_ch
        cpx     #7
        bne     :+
        sta     snd_mix             ; (the mixer: kept, for SOUND and NOISE)
:       jmp     ay_w
@fc:    jmp     LAB_FCER

; ----------------------------------------------------------------------------
; AYREAD(reg) - function: FAC1 = the register number; the value in FAC1
; ----------------------------------------------------------------------------
BI_AYRD:
        jsr     LAB_F2FX
        lda     Itemph
        bne     @fc
        ldx     Itempl
        cpx     #16
        bcs     @fc
        php
        sei
        stx     AY_ADDR
        ldy     AY_DATA
        plp
        jmp     LAB_1FD0            ; Y as a number in FAC1
@fc:    jmp     LAB_FCER

; ----------------------------------------------------------------------------
; the tone periods of the notes (2 MHz clock): C1 = 0 ... B8 = 95
; ----------------------------------------------------------------------------
snd_nlo:
        .byte   $EE, $18, $4D, $8E, $DA, $2F, $8F, $F7, $68, $E1, $61, $E9   ; octave 1
        .byte   $77, $0C, $A7, $47, $ED, $98, $47, $FC, $B4, $70, $31, $F4   ; octave 2
        .byte   $BC, $86, $53, $24, $F6, $CC, $A4, $7E, $5A, $38, $18, $FA   ; octave 3
        .byte   $DE, $C3, $AA, $92, $7B, $66, $52, $3F, $2D, $1C, $0C, $FD   ; octave 4
        .byte   $EF, $E1, $D5, $C9, $BE, $B3, $A9, $9F, $96, $8E, $86, $7F   ; octave 5
        .byte   $77, $71, $6A, $64, $5F, $59, $54, $50, $4B, $47, $43, $3F   ; octave 6
        .byte   $3C, $38, $35, $32, $2F, $2D, $2A, $28, $26, $24, $22, $20   ; octave 7
        .byte   $1E, $1C, $1B, $19, $18, $16, $15, $14, $13, $12, $11, $10   ; octave 8
snd_nhi:
        .byte   $0E, $0E, $0D, $0C, $0B, $0B, $0A, $09, $09, $08, $08, $07
        .byte   $07, $07, $06, $06, $05, $05, $05, $04, $04, $04, $04, $03
        .byte   $03, $03, $03, $03, $02, $02, $02, $02, $02, $02, $02, $01
        .byte   $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $01, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
        .byte   $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
