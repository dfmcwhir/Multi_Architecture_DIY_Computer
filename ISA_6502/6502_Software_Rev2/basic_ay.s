; ============================================================================
; basic_ay.s - EhBASIC sound statements: the AY-3-8910 sound card ($7F22
;              register number, $7F23 data; 2 MHz chip clock), or the ESP32_VGA
;              card's 4-voice synthesizer (SND_DEV in config.inc), plus SAY
;              for the SPO256 speech chip and a sound API for programs.
;
; BASIC KEYWORDS (their tokens follow I2CREAD( in basic.s, after all of
; EhBASIC's own, so programs SAVEd before keep their meaning):
;
;   SOUND ch, freq, vol [, time]   a tone: channel 0-2 (ESP32: 0-3), frequency
;                                  in Hz (31 - 65535), volume 0-15 (16: AY: follow
;                                  the envelope, see ENVELOPE; ESP32: 15)
;   NOTE ch, n, vol [, time]       the same with a note number: 0 = C1 ...
;                                  36 = C4 (middle C), 45 = A4 (440 Hz) ... 95 = B8
;   NOISE ch, period, vol [, time] noise on the channel instead of a tone;
;                                  period 0-31 (0 = the highest hiss)
;   ENVELOPE shape, period         AY only: the chip's envelope (one for all
;                                  channels, used by volume 16): shape 0-15 (8 saw
;                                  down, 12 saw up, 10 or 14 triangle, 0 one fade
;                                  out, 13 fade in and hold), period 0-65535 (one
;                                  ramp lasts period x 128 us)
;   VOICE ch, wave [, a, d, s, r]  ESP32 only: the voice's waveform for SOUND and
;                                  NOTE (0 square, 1 triangle, 2 saw, 3 sine,
;                                  4 noise) and its envelope: attack, decay,
;                                  sustain level, release, each 0-15
;   QUIET                          all channels off
;   AYREG reg, value               AY only: write any register (0-15) as it is.
;                                  Register 7 bits 6 / 7 make I/O port A / B an
;                                  output; SOUND, NOISE and QUIET now keep them.
;   x = AYREAD(reg)                AY only: read a register back: 14 and 15 are
;                                  the I/O ports A and B
;   SAY a [, b ...]  /  SAY s$     the SPO256: allophones 0-63, as numbers or as
;                                  the characters of a string (their codes AND
;                                  63); a short pause is added at the end.  The
;                                  program carries on while it speaks.
;
; time: in 1/60 s (the VIA's timer interrupt counts it down); 0 or left out =
; until changed.  With a time, the note stops by itself while BASIC goes on -
; and a timed SOUND / NOTE / NOISE first waits for the last timed one on its
; channel to finish, so a tune is just one statement per note:
;
;   10 FOR I = 1 TO 8 : READ N : NOTE 0, N, 12, 15 : NEXT
;   20 DATA 36,38,40,41,43,45,47,48
;
; plays a scale, a quarter of a second a note, one channel.  The other
; channels can play at the same time (their own queue of one).  CTRL-C stops
; a wait.  Without the timer interrupt (no VIA) a time is ignored.
;
; The interrupt writes the sound chip too (to stop a note), so every write
; here is done with interrupts off.  ESP32: the interrupt then sends an I/O
; command to the card - machine code that drives the card's I/O channel
; itself should not run while a timed BASIC note is still playing.
;
; SOUND API for programs (jump table, see sbc_api.inc):
;   SBC_SNDNOTE   A/Y -> 5 bytes: voice, note (0-95), volume (0-16), time
;                 (16 bit, 1/60 s, 0 = hold).  Doesn't wait.  C=1 = bad values.
;   SBC_SNDQUIET  everything off
;   SBC_SNDBUSY   A = voice: C=1 while its timed note is still playing
;   SBC_AYREAD    X = register -> A          (AY only)
;   SBC_AYWRITE   X = register, A = value    (AY only; register 7 is tracked)
; ============================================================================

AY_ADDR     = $7F22
AY_DATA     = $7F23
AY_FULL     = 125000                ; 2 MHz / 16: the tone period is this / Hz

.if SND_DEV = SND_ESP
SND_VOICES  = 4
.else
SND_VOICES  = 3
.endif

.segment "BIOSVARS"
snd_tl:     .res 4                  ; each channel: the time left (1/60 s)
snd_th:     .res 4
snd_mix:    .res 1                  ; AY: the mixer (register 7) as last written
snd_ch:     .res 1                  ; the statement's arguments
snd_vol:    .res 1
snd_pl:     .res 1                  ;  the period (AY), Hz or note (ESP32)
snd_ph:     .res 1
snd_dl:     .res 1                  ;  the time
snd_dh:     .res 1
snd_q:      .res 3                  ; (the division)
snd_r:      .res 2

.segment "DRVVARS"
snd_wave:   .res 4                  ; ESP32: each voice's waveform (VOICE)
snd_kind:   .res 1                  ; ESP32: 0 a tone in Hz, 1 a note, 2 noise

.segment "BIOS"

; ----------------------------------------------------------------------------
; SND_BOOT - called from RESET: all quiet
; ----------------------------------------------------------------------------
SND_BOOT:
AY_BOOT:
.if SND_DEV = SND_ESP
        ldx     #3
        lda     #WAVE_SQUARE
@w:     sta     snd_wave,x
        dex
        bpl     @w
.endif
        lda     #0
        sta     snd_mix             ; (AY: the I/O ports inputs)
        ; (on into BI_QUIET)

; ----------------------------------------------------------------------------
; QUIET  (also SBC_SNDQUIET)
; ----------------------------------------------------------------------------
BI_QUIET:
        php
        sei
        lda     #0
        ldx     #3
@c:     sta     snd_tl,x            ; no notes timed
        sta     snd_th,x
        dex
        bpl     @c
.if SND_DEV = SND_AY
        ldx     #8                  ; volumes 0
@v:     jsr     ay_w0
        inx
        cpx     #11
        bne     @v
        lda     snd_mix             ; mixer: all off, the I/O port bits kept
        ora     #$3F
        sta     snd_mix
        ldx     #7
        jsr     ay_w0
.elseif SND_DEV = SND_ESP
        bit     esp_ok
        bpl     @x
        lda     #IO_SNDSTOP
        sta     VGA_IOCMD
@x:
.endif
        plp
        rts

.if SND_DEV = SND_AY
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
.endif

; ----------------------------------------------------------------------------
; SND_TICK - from the timer interrupt (60 a second): a timed note that runs
; out is made silent (AY: its volume 0; ESP32: its gate off)
; ----------------------------------------------------------------------------
SND_TICK:
        ldx     #(SND_VOICES - 1)
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
.if SND_DEV = SND_AY
        txa                         ; run out: its volume 0
        clc
        adc     #8
        sta     AY_ADDR
        lda     #0
        sta     AY_DATA
.elseif SND_DEV = SND_ESP
        bit     esp_ok              ; run out: its gate off (release)
        bpl     @n
        lda     #IO_SNDGATE
        sta     VGA_IOCMD
        stx     VGA_IODATA
        lda     #0
        sta     VGA_IODATA
.endif
@n:     dex
        bpl     @l
        rts

; ----------------------------------------------------------------------------
; the arguments
; ----------------------------------------------------------------------------
snd_fc: jmp     LAB_FCER            ; "Function call Error"

; the channel (0 - SND_VOICES-1) into snd_ch
snd_getch:
.if SND_DEV = SND_NONE
        jmp     snd_fc              ; no sound device in this ROM
.else
        jsr     LAB_GTBY
        cpx     #SND_VOICES
        bcs     snd_fc
        stx     snd_ch
        rts
.endif

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
.if SND_DEV = SND_ESP
        lda     Itempl              ; the card takes Hz
        sta     snd_pl
        lda     Itemph
        sta     snd_ph
        lda     #0
        sta     snd_kind
        jsr     snd_getvt
        jmp     snd_play
.else
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
.endif

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
.if SND_DEV = SND_ESP
        stx     snd_pl
        lda     #1
        sta     snd_kind
        jsr     snd_getvt
        jmp     snd_play
.else
        lda     snd_nlo,x
        sta     snd_pl
        lda     snd_nhi,x
        sta     snd_ph
        jsr     snd_getvt
        jmp     snd_tone
.endif

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
.if SND_DEV = SND_ESP
        txa                         ; the AY's noise rate: 125000 / period Hz
        bne     :+                  ; (period 0: as 1)
        lda     #1
:       sta     Itempl
        lda     #0
        sta     Itemph
        lda     #<AY_FULL
        sta     snd_q
        lda     #>AY_FULL
        sta     snd_q+1
        lda     #^AY_FULL
        sta     snd_q+2
        jsr     snd_div
        lda     snd_q+2             ; above 31250 Hz (the card's sample rate):
        bne     @max                ; 31250
        lda     snd_q+1
        cmp     #>31250
        bcc     @ok
        bne     @max
        lda     snd_q
        cmp     #<31250
        bcc     @ok
@max:   lda     #<31250
        sta     snd_q
        lda     #>31250
        sta     snd_q+1
@ok:    lda     snd_q
        sta     snd_pl
        lda     snd_q+1
        sta     snd_ph
        lda     #2
        sta     snd_kind
        jsr     snd_getvt
        jmp     snd_play
.else
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
        jmp     snd_go
.endif

; ----------------------------------------------------------------------------
; snd_ctime - no timer interrupt: no times at all
; ----------------------------------------------------------------------------
snd_ctime:
        lda     $7F0E               ; the VIA's timer 1 interrupt on?
        and     #$40
        bne     @r
        sta     snd_dl
        sta     snd_dh
@r:     rts

; a timed note: wait for the last timed one on the channel to run out (only
; when the timer interrupt is on; CTRL-C stops the wait)
snd_wait:
        jsr     snd_ctime
        lda     snd_dl
        ora     snd_dh
        beq     @r                  ; (this one isn't timed)
@w:     ldx     snd_ch
        lda     snd_tl,x
        ora     snd_th,x
        beq     @r
        jsr     LAB_1629            ; (CTRL-C)
        jmp     @w
@r:     rts

.if SND_DEV = SND_AY
; ----------------------------------------------------------------------------
; AY: the tone (snd_pl/ph) on channel snd_ch at snd_vol for snd_dl/dh
; ----------------------------------------------------------------------------
snd_tone:
        jsr     snd_wait
snd_tone_nw:
        jsr     snd_ctime
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
        ; (on into snd_go)

; mixer = A (the I/O port bits 6-7 as they were), then the volume and the
; time (interrupts off; ends with plp)
snd_go: sta     snd_mix
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

tone_on:    .byte   $FE, $FD, $FB   ; (and: its bit 0)
tone_off:   .byte   $01, $02, $04   ; (or: its bit 1)
noise_on:   .byte   $F7, $EF, $DF
noise_off:  .byte   $08, $10, $20
.endif

.if SND_DEV = SND_ESP
; ----------------------------------------------------------------------------
; ESP32: play snd_kind (0 tone snd_pl/ph Hz, 1 note snd_pl, 2 noise snd_pl/ph
; Hz) on voice snd_ch at snd_vol for snd_dl/dh
; ----------------------------------------------------------------------------
snd_play:
        jsr     snd_wait
snd_play_nw:
        jsr     snd_ctime
        bit     esp_ok
        bmi     :+
        rts
:       php
        sei
        ldx     snd_ch
        lda     #IO_SNDWAVE         ; the waveform
        sta     VGA_IOCMD
        stx     VGA_IODATA
        lda     #WAVE_NOISE
        ldy     snd_kind
        cpy     #2
        beq     :+
        lda     snd_wave,x
:       sta     VGA_IODATA
        lda     #0                  ; (duty: the default, 50 %)
        sta     VGA_IODATA
        lda     #IO_SNDVOL          ; the volume 0-15 -> 0-255
        sta     VGA_IOCMD
        stx     VGA_IODATA
        lda     snd_vol
        cmp     #16
        bcc     :+
        lda     #15
:       sta     snd_q
        asl     a
        asl     a
        asl     a
        asl     a
        ora     snd_q
        sta     VGA_IODATA
        lda     snd_kind
        cmp     #1
        bne     @tone
        lda     #IO_SNDNOTE         ; a note: MIDI = n + 24 (36 = C4 = 60),
        sta     VGA_IOCMD           ; held (the tick ends a timed one)
        stx     VGA_IODATA
        lda     snd_pl
        clc
        adc     #24
        sta     VGA_IODATA
        lda     #0
        sta     VGA_IODATA
        jmp     @time
@tone:  lda     #IO_SNDFREQ         ; a frequency, then the gate on
        sta     VGA_IOCMD
        stx     VGA_IODATA
        lda     snd_pl
        sta     VGA_IODATA
        lda     snd_ph
        sta     VGA_IODATA
        lda     #IO_SNDGATE
        sta     VGA_IOCMD
        stx     VGA_IODATA
        lda     #1
        sta     VGA_IODATA
@time:  lda     snd_dl
        sta     snd_tl,x
        lda     snd_dh
        sta     snd_th,x
        plp
        rts
.endif

; ----------------------------------------------------------------------------
; ENVELOPE shape, period   (AY)
; ----------------------------------------------------------------------------
BI_ENVELOPE:
.if SND_DEV = SND_AY
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
@fc:
.endif
        jmp     LAB_FCER

; ----------------------------------------------------------------------------
; VOICE ch, wave [, a, d, s, r]   (ESP32)
; ----------------------------------------------------------------------------
BI_VOICE:
.if SND_DEV = SND_ESP
        jsr     snd_getch
        jsr     LAB_1C01
        jsr     LAB_GTBY            ; the waveform
        cpx     #5
        bcs     @fc
        txa
        ldx     snd_ch
        sta     snd_wave,x
        jsr     LAB_GBYT            ; an envelope?
        cmp     #','
        bne     @x
        ldx     #0
@e:     stx     snd_vol             ; (the index)
        jsr     LAB_1C01
        jsr     LAB_GTBY            ; a, d, s, r: 0-15
        cpx     #16
        bcs     @fc
        txa
        ldx     snd_vol
        sta     snd_q,x             ; (snd_q, snd_q+1, snd_q+2, snd_r)
        inx
        cpx     #4
        bne     @e
        bit     esp_ok
        bpl     @x
        php
        sei
        lda     #IO_SNDENV
        sta     VGA_IOCMD
        lda     snd_ch
        sta     VGA_IODATA
        ldx     #0
@s:     lda     snd_q,x
        sta     VGA_IODATA
        inx
        cpx     #4
        bne     @s
        plp
@x:     rts
@fc:
.endif
        jmp     LAB_FCER

; ----------------------------------------------------------------------------
; AYREG reg, value   (AY)
; ----------------------------------------------------------------------------
BI_AYREG:
.if SND_DEV = SND_AY
        jsr     LAB_GTBY            ; the register
        cpx     #16
        bcs     @fc
        stx     snd_ch
        jsr     LAB_1C01
        jsr     LAB_GTBY            ; the value
        txa
        ldx     snd_ch
        jmp     SND_AYWRITE
@fc:
.endif
        jmp     LAB_FCER

; ----------------------------------------------------------------------------
; AYREAD(reg) - function: FAC1 = the register number; the value in FAC1  (AY)
; ----------------------------------------------------------------------------
BI_AYRD:
.if SND_DEV = SND_AY
        jsr     LAB_F2FX
        lda     Itemph
        bne     @fc
        ldx     Itempl
        cpx     #16
        bcs     @fc
        jsr     SND_AYREAD
        tay
        jmp     LAB_1FD0            ; Y as a number in FAC1
@fc:
.endif
        jmp     LAB_FCER

; ----------------------------------------------------------------------------
; SAY a [, b ...]  /  SAY s$
; ----------------------------------------------------------------------------
BI_SAY:
.if HAS_SPO
@next:  jsr     LAB_EVEX
        bit     Dtypef
        bmi     @str
        jsr     LAB_EVBY            ; X = the allophone
        cpx     #64
        bcs     @fc
        txa
        jsr     SPO_PUT
        jmp     @more
@str:   jsr     LAB_EVST            ; A = length, (ut1_pl) = the characters
        tax
        beq     @more
        ldy     #0
@c:     lda     (ut1_pl),y
        jsr     SPO_PUT             ; (keeps X and Y; uses the low 6 bits)
        iny
        dex
        bne     @c
@more:  jsr     LAB_GBYT
        cmp     #','
        bne     @end
        jsr     LAB_IGBY
        jmp     @next
@end:   lda     #SPO_PAUSE
        jsr     SPO_PUT
        jmp     SPO_DRAIN           ; (no VIA: speak it all now)
@fc:
.endif
        jmp     LAB_FCER

; ============================================================================
; The sound API (jump table)
; ============================================================================

; SND_API_NOTE - A/Y -> voice, note, volume, time lo, time hi.  C=1 = bad.
SND_API_NOTE:
.if SND_DEV <> SND_NONE
        sta     con_ptr
        sty     con_ptr+1
        ldy     #0
        lda     (con_ptr),y         ; voice
        cmp     #SND_VOICES
        bcs     @bad
        sta     snd_ch
        iny
        lda     (con_ptr),y         ; note
        cmp     #96
        bcs     @bad
        tax
        iny
        lda     (con_ptr),y         ; volume
        cmp     #17
        bcs     @bad
        sta     snd_vol
        iny
        lda     (con_ptr),y         ; time
        sta     snd_dl
        iny
        lda     (con_ptr),y
        sta     snd_dh
  .if SND_DEV = SND_AY
        lda     snd_nlo,x
        sta     snd_pl
        lda     snd_nhi,x
        sta     snd_ph
        jsr     snd_tone_nw
  .else
        stx     snd_pl
        lda     #1
        sta     snd_kind
        jsr     snd_play_nw
  .endif
        clc
        rts
.endif
@bad:   sec
        rts

; SND_API_BUSY - A = voice: C=1 while its timed note is still playing
SND_API_BUSY:
        cmp     #SND_VOICES
        bcs     @no
        tax
        lda     snd_tl,x
        ora     snd_th,x
        beq     @no
        sec
        rts
@no:    clc
        rts

; SND_AYREAD - X = register -> A   (0 without the AY)
SND_AYREAD:
.if SND_DEV = SND_AY
        php
        sei
        stx     AY_ADDR
        lda     AY_DATA
        plp
        rts
.else
        lda     #0
        rts
.endif

; SND_AYWRITE - register X = A (register 7 is remembered, so SOUND / NOISE /
; QUIET keep the I/O port directions)
SND_AYWRITE:
.if SND_DEV = SND_AY
        cpx     #7
        bne     :+
        sta     snd_mix
:       jmp     ay_w
.else
        rts
.endif

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
