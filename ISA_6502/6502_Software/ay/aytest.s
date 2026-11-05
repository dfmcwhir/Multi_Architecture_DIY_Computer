; ============================================================================
; aytest.s - AYTEST: a test program for the AY-3-8910 sound card
;
;   build:  make.bat  (or make)        run:  L AYTEST 0500   then   R
;
; A menu of tests, each of which says what you should hear:
;   1  each channel on its own (A, B, C at 440 Hz): checks the three outputs
;   2  a scale on channel A (tone periods)
;   3  a chord on A, B and C together, then arpeggios
;   4  noise on all channels, low to high (noise period, mixer)
;   5  the 8 envelope shapes (envelope period and shape registers)
;   6  volume 0 to 15 and back (volume registers)
;   7  sound effects: laser, explosion, siren, bell
;   8  a sweep over every tone period, 4095 down to 1 (all 12 period bits)
;   9  all of them, one after another
;   Q  quit (to the boot menu)
; Any key stops a test and goes back to the menu.  The card is write only,
; so the program can't check itself: listen.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

        .segment "CODE"
        jmp     start

        .include "common.s"
        .include "ay.s"

; ---- the menu ----------------------------------------------------------------------
start:  cld
        ldx     #$FF
        txs
        jsr     ay_silence
menu:   jsr     ay_silence
        PRINT   menu_txt
@k:     jsr     waitkey
        cmp     #'Q'
        bne     @n
        jsr     ay_silence
        PRINT   bye_txt
        jmp     SBC_MENU
@n:     cmp     #'1'
        bcc     @k
        cmp     #'9' + 1
        bcs     @k
        sec
        sbc     #'1'
        cmp     #8
        beq     @all
        jsr     run_test
        jmp     menu
@all:   lda     #0              ; 9: each in turn, until a key
@a:     pha
        jsr     run_test
        pla
        bit     stopped
        bmi     @done
        clc
        adc     #1
        cmp     #8
        bne     @a
@done:  jmp     menu

; run test A (0-7)
run_test:
        asl
        tax
        lda     tests,x
        sta     @j+1
        lda     tests+1,x
        sta     @j+2
        lda     #0
        sta     stopped
        jsr     crlf
        jsr     ay_silence
@j:     jsr     $FFFF
        jsr     ay_silence
        rts
tests:  .word   t_channels, t_scale, t_chord, t_noise, t_envelope, t_volume, t_effects, t_sweep

; wait A x 10 ms; a key stops the test: then the carry is set (and stays set
; for the rest of it: stopped has bit 7 set)
wait10: sta     wcount
@l:     bit     stopped
        bmi     @stop
        jsr     getkey
        bcs     @key
        lda     #10
        jsr     delay_ms
        dec     wcount
        bne     @l
        clc
        rts
@key:   lda     #$80
        sta     stopped
        PRINT   stop_txt
@stop:  sec
        rts

; ---- 1: each channel on its own -----------------------------------------------------
t_channels:
        PRINT   t1_txt
        ldx     #0
@ch:    stx     chan
        txa                     ; "CHANNEL A"
        clc
        adc     #'A'
        sta     t1_ch
        PRINT   t1_line
        ldx     chan            ; the mixer: only this channel's tone
        lda     chan_tone_only,x
        jsr     ay_mixer
        ldx     chan
        lda     #45             ; A4, 440 Hz
        jsr     ay_note
        ldx     chan
        lda     #15
        jsr     ay_volume
        lda     #100            ; a second
        jsr     wait10
        bcs     @r
        ldx     chan
        lda     #0
        jsr     ay_volume
        lda     #30
        jsr     wait10
        bcs     @r
        ldx     chan
        inx
        cpx     #3
        bne     @ch
@r:     rts

; ---- 2: a scale ----------------------------------------------------------------------
t_scale:
        PRINT   t2_txt
        lda     #%00111110      ; tone A only
        jsr     ay_mixer
        ldx     #0
        lda     #13
        jsr     ay_volume
        ldy     #0
@up:    sty     idx
        lda     scale,y
        ldx     #0
        jsr     ay_note
        lda     #30
        jsr     wait10
        bcs     @r
        ldy     idx
        iny
        cpy     #15
        bne     @up
@r:     rts
scale:  .byte   36, 38, 40, 41, 43, 45, 47, 48, 47, 45, 43, 41, 40, 38, 36   ; C4 .. C5 .. C4

; ---- 3: a chord, then arpeggios --------------------------------------------------------
t_chord:
        PRINT   t3_txt
        lda     #%00111000      ; tones A, B, C
        jsr     ay_mixer
        ldx     #0
@c:     stx     chan
        lda     chord,x
        jsr     ay_note
        ldx     chan
        lda     #11
        jsr     ay_volume
        ldx     chan
        inx
        cpx     #3
        bne     @c
        lda     #200
        jsr     wait10
        bcs     @r
        lda     #0              ; arpeggios on A: C, F, G major, 3 octaves
        sta     idx
@a:     ldx     idx
        lda     arp,x
        bmi     @r
        ldx     #0
        jsr     ay_note
        ldx     #1
        lda     #0
        jsr     ay_volume
        ldx     #2
        lda     #0
        jsr     ay_volume
        lda     #8
        jsr     wait10
        bcs     @r
        inc     idx
        bne     @a
@r:     rts
chord:  .byte   36, 40, 43      ; C4 E4 G4
arp:    .byte   24, 28, 31, 36, 40, 43, 48, 52, 55, 60, 55, 52, 48, 43, 40, 36, 31, 28
        .byte   29, 33, 36, 41, 45, 48, 53, 57, 60, 65, 60, 57, 53, 48, 45, 41, 36, 33
        .byte   31, 35, 38, 43, 47, 50, 55, 59, 62, 67, 62, 59, 55, 50, 47, 43, 38, 35, 36, $FF

; ---- 4: noise ------------------------------------------------------------------------
t_noise:
        PRINT   t4_txt
        lda     #%00000111      ; noise on A, B, C; tones off
        jsr     ay_mixer
        ldx     #0
        lda     #10
        jsr     ay_volume
        inx
        jsr     ay_volume
        inx
        jsr     ay_volume
        lda     #31             ; period 31 (low) down to 0 (high)
        sta     idx
@n:     lda     idx
        ldx     #AY_NOISE
        jsr     ay_write
        lda     #15
        jsr     wait10
        bcs     @r
        dec     idx
        bpl     @n
@r:     rts

; ---- 5: the envelope shapes -------------------------------------------------------------
t_envelope:
        PRINT   t5_txt
        lda     #%00111110      ; tone A
        jsr     ay_mixer
        ldx     #0
        lda     #24             ; C3
        jsr     ay_note
        ldx     #0
        lda     #16             ; volume from the envelope
        jsr     ay_volume
        lda     #<ENV_HALF      ; one sweep in about half a second
        ldx     #AY_ENV_LO
        jsr     ay_write
        lda     #>ENV_HALF
        ldx     #AY_ENV_HI
        jsr     ay_write
        lda     #0
        sta     idx
@s:     ldx     idx
        lda     shapes,x
        bmi     @r
        sta     shape
        PRINT   t5_line
        lda     idx             ; its name
        asl
        tax
        lda     shape_names,x
        ldy     shape_names+1,x
        jsr     print
        lda     shape
        ldx     #AY_ENV_SHAPE   ; (writing it starts the envelope)
        jsr     ay_write
        lda     #200
        jsr     wait10
        bcs     @r
        inc     idx
        bne     @s
@r:     rts
ENV_HALF = 3906                 ; one ramp: 256 x 3906 / 2 MHz = 0.5 s
shapes: .byte   ENV_DECAY, ENV_ATTACK_ZERO, ENV_SAW_DOWN, ENV_DECAY_HOLD, ENV_TRIANGLE2, ENV_SAW_UP, ENV_ATTACK, ENV_TRIANGLE, $FF
shape_names:
        .word   sh0, sh1, sh2, sh3, sh4, sh5, sh6, sh7

; ---- 6: volume ----------------------------------------------------------------------------
t_volume:
        PRINT   t6_txt
        lda     #%00111110
        jsr     ay_mixer
        ldx     #0
        lda     #45
        jsr     ay_note
        lda     #0
        sta     idx
@up:    lda     idx
        ldx     #0
        jsr     ay_volume
        lda     idx
        jsr     prdec2
        lda     #' '
        jsr     SBC_CHROUT
        lda     #25
        jsr     wait10
        bcs     @r
        inc     idx
        lda     idx
        cmp     #16
        bne     @up
@dn:    dec     idx
        bmi     @r
        lda     idx
        ldx     #0
        jsr     ay_volume
        lda     #10
        jsr     wait10
        bcs     @r
        jmp     @dn
@r:     jmp     crlf

; ---- 7: sound effects -----------------------------------------------------------------------
t_effects:
        PRINT   fx1_txt         ; laser: a falling tone, 3 times
        lda     #%00111110
        jsr     ay_mixer
        ldx     #0
        lda     #14
        jsr     ay_volume
        lda     #3
        sta     idx
@l1:    lda     #40             ; period 40 .. 400
        sta     per
        lda     #0
        sta     per+1
@l2:    lda     per
        ldy     per+1
        ldx     #0
        jsr     ay_tone
        lda     #1
        jsr     wait10
        bcs     @r
        lda     per
        clc
        adc     #12
        sta     per
        bcc     @l3
        inc     per+1
@l3:    lda     per+1
        cmp     #>400
        bcc     @l2
        lda     per
        cmp     #<400
        bcc     @l2
        dec     idx
        bne     @l1
        lda     #30
        jsr     wait10
        bcs     @r
        PRINT   fx2_txt         ; explosion: low noise fading out
        lda     #%00110111      ; noise on A
        jsr     ay_mixer
        lda     #28
        ldx     #AY_NOISE
        jsr     ay_write
        ldx     #0
        lda     #16
        jsr     ay_volume
        lda     #<6000          ; about 0.75 s
        ldx     #AY_ENV_LO
        jsr     ay_write
        lda     #>6000
        ldx     #AY_ENV_HI
        jsr     ay_write
        lda     #ENV_DECAY
        ldx     #AY_ENV_SHAPE
        jsr     ay_write
        lda     #120
        jsr     wait10
        bcs     @r
        jmp     fx_siren
@r:     rts

fx_siren:
        PRINT   fx3_txt         ; siren: up and down, twice
        lda     #%00111110
        jsr     ay_mixer
        ldx     #0
        lda     #13
        jsr     ay_volume
        lda     #4
        sta     idx
@s:     ldy     #0
@s1:    sty     idx2
        tya
        clc
        adc     #36             ; C4 .. C5
        cpy     #13
        bcc     @s2
        lda     #36 + 24        ; (and back)
        sbc     idx2
@s2:    ldx     #0
        jsr     ay_note
        lda     #4
        jsr     wait10
        bcs     @r
        ldy     idx2
        iny
        cpy     #25
        bne     @s1
        dec     idx
        bne     @s
        lda     #30
        jsr     wait10
        bcs     @r
        PRINT   fx4_txt         ; bell: a tone with a slow decay, a tune
        lda     #%00111110
        jsr     ay_mixer
        ldx     #0
        lda     #16
        jsr     ay_volume
        lda     #<2500
        ldx     #AY_ENV_LO
        jsr     ay_write
        lda     #>2500
        ldx     #AY_ENV_HI
        jsr     ay_write
        lda     #0
        sta     idx
@b:     ldx     idx
        lda     bells,x
        bmi     @r
        ldx     #0
        jsr     ay_note
        lda     #ENV_DECAY      ; (restarts the envelope: a new strike)
        ldx     #AY_ENV_SHAPE
        jsr     ay_write
        lda     #40
        jsr     wait10
        bcs     @r
        inc     idx
        bne     @b
@r:     rts
bells:  .byte   52, 48, 50, 43, 43, 50, 52, 48, $FF

; ---- 8: every tone period ----------------------------------------------------------------------
t_sweep:
        PRINT   t8_txt
        lda     #%00111110
        jsr     ay_mixer
        ldx     #0
        lda     #12
        jsr     ay_volume
        lda     #<4095
        sta     per
        lda     #>4095
        sta     per+1
@p:     lda     per
        ldy     per+1
        ldx     #0
        jsr     ay_tone
        lda     #1              ; 10 ms each step; the step shrinks with the period
        jsr     wait10
        bcs     @r
        lda     per+1           ; step = period / 64 + 1
        sta     tmp
        lda     per
        ldx     #6
@d:     lsr     tmp
        ror
        dex
        bne     @d
        clc
        adc     #1
        sta     tmp
        lda     per
        sec
        sbc     tmp
        sta     per
        lda     per+1
        sbc     #0
        sta     per+1
        bcc     @r              ; (below 0: done)
        ora     per
        bne     @p
@r:     rts

; ---- data -----------------------------------------------------------------------------------
chan_tone_only: .byte %00111110, %00111101, %00111011

menu_txt:
        .byte   12, "AY-3-8910 SOUND CARD TEST   (registers at $7F22, data at $7F23)", 13, 10, 13, 10
        .byte   "  1  EACH CHANNEL ON ITS OWN (A, B, C AT 440 HZ)", 13, 10
        .byte   "  2  A SCALE ON CHANNEL A", 13, 10
        .byte   "  3  A CHORD ON A, B AND C, THEN ARPEGGIOS", 13, 10
        .byte   "  4  NOISE, LOW TO HIGH", 13, 10
        .byte   "  5  THE 8 ENVELOPE SHAPES", 13, 10
        .byte   "  6  VOLUME 0 TO 15 AND BACK", 13, 10
        .byte   "  7  SOUND EFFECTS: LASER, EXPLOSION, SIREN, BELL", 13, 10
        .byte   "  8  A SWEEP OVER EVERY TONE PERIOD", 13, 10
        .byte   "  9  ALL OF THEM", 13, 10
        .byte   "  Q  QUIT", 13, 10, 13, 10
        .byte   "ANY KEY STOPS A TEST.  CHOOSE: ", 0
bye_txt:.byte   13, 10, "BYE", 13, 10, 0
stop_txt:.byte  " (STOPPED)", 13, 10, 0
t1_txt: .byte   "1: EACH CHANNEL ALONE, 1 SECOND EACH. YOU SHOULD HEAR THE SAME NOTE 3 TIMES.", 13, 10, 0
t1_line:.byte   "   CHANNEL "
t1_ch:  .byte   "A", 13, 10, 0
t2_txt: .byte   "2: C MAJOR SCALE UP AND DOWN ON CHANNEL A.", 13, 10, 0
t3_txt: .byte   "3: C MAJOR CHORD (C E G) ON A B C FOR 2 SECONDS, THEN ARPEGGIOS ON A.", 13, 10, 0
t4_txt: .byte   "4: NOISE ON ALL CHANNELS, FROM A LOW RUMBLE TO A HIGH HISS.", 13, 10, 0
t5_txt: .byte   "5: ENVELOPE SHAPES ON A LOW C, 2 SECONDS EACH:", 13, 10, 0
t5_line:.byte   "   ", 0
sh0:    .byte   "\___  FADE OUT ONCE", 13, 10, 0
sh1:    .byte   "/___  FADE IN, THEN SILENT", 13, 10, 0
sh2:    .byte   "\\\\  FADE OUT, OVER AND OVER", 13, 10, 0
sh3:    .byte   "\~~~  FADE OUT, THEN LOUD", 13, 10, 0
sh4:    .byte   "\/\/  DOWN AND UP", 13, 10, 0
sh5:    .byte   "////  FADE IN, OVER AND OVER", 13, 10, 0
sh6:    .byte   "/~~~  FADE IN, THEN STAY LOUD", 13, 10, 0
sh7:    .byte   "/\/\  UP AND DOWN", 13, 10, 0
t6_txt: .byte   "6: 440 HZ, VOLUME 0 TO 15 AND BACK DOWN:", 13, 10, "   ", 0
fx1_txt:.byte   "7: LASER", 13, 10, 0
fx2_txt:.byte   "   EXPLOSION", 13, 10, 0
fx3_txt:.byte   "   SIREN", 13, 10, 0
fx4_txt:.byte   "   BELLS", 13, 10, 0
t8_txt: .byte   "8: TONE FROM VERY LOW (PERIOD 4095, 30 HZ) TO VERY HIGH, SMOOTHLY.", 13, 10
        .byte   "   JUMPS OR SILENT PATCHES MEAN A TONE PERIOD BIT ISN'T GETTING THROUGH.", 13, 10, 0

        .segment "BSS"
stopped:    .res 1
wcount:     .res 1
chan:       .res 1
idx:        .res 1
idx2:       .res 1
shape:      .res 1
per:        .res 2
tmp:        .res 1
