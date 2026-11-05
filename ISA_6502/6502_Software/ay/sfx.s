; ============================================================================
; sfx.s - sound effects and music for games, on the AY-3-8910 card
;         ($7F22 register number, $7F23 data; 2 MHz chip clock)
;
; Include it in a game (it finds its note table one folder up, like
; sbc_api.inc:  ca65 -I ..):
;           .include "ay/sfx.s"
; and then
;   sfx_init    once at the start (silence, the timer)
;   sfx_poll    often: at least every 20 ms (the game loop, and the delay
;               loops).  It runs the sound 50 times a second, timed by the
;               VIA's timer 2 (polled: its interrupt stays off; timer 1 and
;               the gamepad aren't touched).  Keeps A, X, Y and the flags.
;   sfx_play    play script A on voice X (see below); it doesn't if that
;               voice is busy with a script of higher priority
;   sfx_stop    stop voice X
;   sfx_off     stop everything (and silence)
;   sfx_mute    0 = sound on, 1 = muted (the scripts still run, unheard)
;   sfx_hush    call before waiting without sfx_poll (a pause): silences the
;               card until the next tick
; With SFX_SND defined before the include, also:
;   sfx_snd     play script A on its own voice (sfx_prio's high 4 bits)
;   sfx_toggle  sound on / off (for the M key)
;
; The voices: 0-2 are the background (music, a saucer's hum ...) on the
; chip's channels A-C; 3-5 are the foreground on the same channels.  While
; a foreground voice plays, it is heard instead of the background voice of
; its channel, which carries on unheard and comes back when it stops.
;
; A game lists its scripts in sfx_scripts (.word address) and their
; priorities in sfx_prio (.byte, higher wins), indexed by script number.
;
; A script is bytes, run 50 times a second until it waits:
;   $80-$FF         wait 1-128 ticks (1/50 s each): $80 + ticks - 1
;   $20-$7F         note 0-95 (C1 .. B8, A4 = 45): $20 + note; the
;                   volume goes back to the VOL level, the decay restarts;
;                   then it waits LEN ticks (if LEN isn't 0)
;   SX_END          (0) the end: the voice stops
;   SX_PER  lo, hi  tone period (12 bits): 2 MHz / (16 x period) Hz
;   SX_VOL  v       volume 0-15 (also the level each note starts at)
;   SX_NOISE n      noise period 0-31 (for the whole chip)
;   SX_MIX  m       bit 0 tone on, bit 1 noise on
;   SX_SWEEP lo, hi add this (signed) to the period every tick (0 = off)
;   SX_DECAY d      the volume drops by 1 every d ticks (0 = holds)
;   SX_LOOP c       the start of a part to play c times (0 = for ever)
;   SX_NEXT         the end of that part
;   SX_JUMP lo, hi  go on at another script (for music that repeats)
;   SX_REST         volume 0 until the next note (and wait LEN ticks)
;   SX_LEN t        notes and rests wait t ticks each from now on (music:
;                   a byte a note); 0 (the start) = they don't wait
; ============================================================================

; ---- variables (123 bytes): in the BSS, or at SFX_VARS if the game sets it
;      (SMB puts them at $0100, the bottom of the stack page) ----------------
.ifdef SFX_VARS
sfx_vars        = SFX_VARS
sfx_lo          = sfx_vars
sfx_hi          = sfx_lo + 6
sfx_wait        = sfx_hi + 6
sfx_perl        = sfx_wait + 6
sfx_perh        = sfx_perl + 6
sfx_swl         = sfx_perh + 6
sfx_swh         = sfx_swl + 6
sfx_vol         = sfx_swh + 6
sfx_base        = sfx_vol + 6
sfx_dec         = sfx_base + 6
sfx_decc        = sfx_dec + 6
sfx_mix         = sfx_decc + 6
sfx_noise       = sfx_mix + 6
sfx_lpl         = sfx_noise + 6
sfx_lph         = sfx_lpl + 6
sfx_lcnt        = sfx_lph + 6
sfx_vprio       = sfx_lcnt + 6
sfx_len         = sfx_vprio + 6
sfx_runs        = sfx_len + 6
sfx_mixer       = sfx_runs + 1
sfx_chan        = sfx_mixer + 1
sfx_guard       = sfx_chan + 1
sfx_mute        = sfx_guard + 2
sfx_sa          = sfx_mute + 1
sfx_sx          = sfx_sa + 1
sfx_sy          = sfx_sx + 1
sfx_vars_end    = sfx_sy + 1
.else
        .segment "BSS"
sfx_vars:
sfx_lo:     .res 6              ; script pointer (high byte 0: voice off)
sfx_hi:     .res 6
sfx_wait:   .res 6
sfx_perl:   .res 6              ; tone period
sfx_perh:   .res 6
sfx_swl:    .res 6              ; sweep
sfx_swh:    .res 6
sfx_vol:    .res 6
sfx_base:   .res 6              ; the volume notes start at
sfx_dec:    .res 6              ; decay: ticks a step
sfx_decc:   .res 6
sfx_mix:    .res 6
sfx_noise:  .res 6
sfx_lpl:    .res 6              ; loop start
sfx_lph:    .res 6
sfx_lcnt:   .res 6
sfx_vprio:  .res 6
sfx_len:    .res 6              ; LEN
sfx_runs:   .res 1
sfx_mixer:  .res 1
sfx_chan:   .res 1
sfx_guard:  .res 2
sfx_mute:   .res 1
sfx_sa:     .res 1              ; (sfx_snd)
sfx_sx:     .res 1
sfx_sy:     .res 1
sfx_vars_end:
        .segment "CODE"
.endif

SX_END          = 0
SX_PER          = 1
SX_VOL          = 2
SX_NOISE        = 3
SX_MIX          = 4
SX_SWEEP        = 5
SX_DECAY        = 6
SX_LOOP         = 7
SX_NEXT         = 8
SX_JUMP         = 9
SX_REST         = 10
SX_LEN          = 11
.define SX_WAIT(t)  ($80 + (t) - 1)
.define SX_NOTE(n)  ($20 + (n))

SFX_AY_ADDR     = $7F22
SFX_AY_DATA     = $7F23
SFX_T2CL        = $7F08
SFX_T2CH        = $7F09
SFX_ACR         = $7F0B
SFX_IFR         = $7F0D
SFX_IER         = $7F0E

; the timer counts a 50th of a second in SFX_RUNS runs of SFX_COUNT cycles
; (it holds 16 bits)
SFX_CYCLES      = CLOCK_MHZ * 20000
SFX_RUNS        = (SFX_CYCLES + 65535) / 65536
SFX_COUNT       = SFX_CYCLES / SFX_RUNS - 2

; ---- the routines ------------------------------------------------------------------------
sfx_init:
        lda     #0
        ldx     #sfx_vars_end - sfx_vars - 1
@c:     sta     sfx_vars,x
        dex
        bpl     @c
        lda     SFX_ACR         ; timer 2: one shot, its interrupt off
        and     #$DF
        sta     SFX_ACR
        lda     #$20
        sta     SFX_IER
        lda     #SFX_RUNS
        sta     sfx_runs
        lda     #<SFX_COUNT
        sta     SFX_T2CL
        lda     #>SFX_COUNT
        sta     SFX_T2CH
        ; (on into sfx_off)

; stop every voice, silence
sfx_off:
        pha
        txa
        pha
        ldx     #5
        lda     #0
@v:     sta     sfx_hi,x
        dex
        bpl     @v
        pla
        tax
        pla
        ; (on into sfx_hush)

; silence the card (until the next tick).  Keeps A, X, Y.
sfx_hush:
        pha
        txa
        pha
        lda     #7              ; mixer: all off
        sta     SFX_AY_ADDR
        lda     #$3F
        sta     SFX_AY_DATA
        ldx     #8              ; volumes 0
        lda     #0
@v:     stx     SFX_AY_ADDR
        sta     SFX_AY_DATA
        inx
        cpx     #11
        bne     @v
        pla
        tax
        pla
        rts

; stop voice X
sfx_stop:
        pha
        lda     #0
        sta     sfx_hi,x
        pla
        rts

; play script A on voice X (0-5); not if the voice is playing a script of
; higher priority.  Keeps X.
sfx_play:
        tay
        lda     sfx_hi,x
        beq     @go
        lda     sfx_prio,y
        cmp     sfx_vprio,x
        bcs     @go
        rts
@go:    lda     sfx_prio,y
        sta     sfx_vprio,x
        tya
        asl
        tay
        lda     sfx_scripts,y
        sta     sfx_lo,x
        lda     sfx_scripts+1,y
        sta     sfx_hi,x
        lda     #0
        sta     sfx_wait,x
        sta     sfx_swl,x
        sta     sfx_swh,x
        sta     sfx_dec,x
        sta     sfx_perl,x
        sta     sfx_perh,x
        sta     sfx_len,x
        lda     #15
        sta     sfx_base,x
        sta     sfx_vol,x
        lda     #1              ; tone on, noise off
        sta     sfx_mix,x
        rts

; run the sound if a tick has come.  Keeps A, X, Y and the flags (so it can
; go anywhere: in putc, in a loop ...)
sfx_poll:
        php
        pha
        lda     SFX_IFR
        and     #$20
        bne     @t
        pla
        plp
        rts
@t:     txa
        pha
        tya
        pha
        ; the timer has gone on counting down past 0 ($FFFF, $FFFE ...): how
        ; late this call is.  The next run is that much shorter, so the beat
        ; keeps time however long the game takes between calls.
@rd:    ldx     SFX_T2CH
        lda     SFX_T2CL
        cpx     SFX_T2CH        ; (the high byte changed in between: again)
        bne     @rd
        sec
        adc     #<(SFX_COUNT - SFX_FIX)
        tay
        txa
        adc     #>(SFX_COUNT - SFX_FIX)
        bcs     @set
        ldy     #100            ; (more than a whole run late: soon)
        lda     #0
@set:   sty     SFX_T2CL
        sta     SFX_T2CH
        dec     sfx_runs
        bne     @r
        lda     #SFX_RUNS
        sta     sfx_runs
        jsr     sfx_tick
@r:     pla
        tay
        pla
        tax
        pla
        plp
        rts
SFX_FIX = 28                    ; cycles from reading the timer to starting it

.ifdef SFX_SND
; ---- (with SFX_SND defined) ---------------------------------------------------
; play script A on its own voice: the high 4 bits of its sfx_prio byte (the
; low 4 are its priority).  Keeps A, X and Y.
sfx_snd:
        sta     sfx_sa
        stx     sfx_sx
        sty     sfx_sy
        tay
        lda     sfx_prio,y
        lsr
        lsr
        lsr
        lsr
        tax
        tya
        jsr     sfx_play
        lda     sfx_sa
        ldx     sfx_sx
        ldy     sfx_sy
        rts

; sound on / off (the M key).  Keeps X and Y.
sfx_toggle:
        lda     sfx_mute
        eor     #1
        sta     sfx_mute
        jmp     sfx_hush
.endif

; ---- a tick: every voice a step, then the card ---------------------------------------------
sfx_tick:
        ldx     #5
@v:     lda     sfx_hi,x
        beq     @n
        jsr     sfx_voice
@n:     dex
        bpl     @v
        ; the card: each channel hears its foreground voice if that plays,
        ; else its background voice
        lda     #$3F
        sta     sfx_mixer
        ldx     #2
@ch:    stx     sfx_chan
        txa
        clc
        adc     #3
        tay                     ; foreground voice
        lda     sfx_hi,y
        bne     @have
        ldy     sfx_chan        ; background voice
        lda     sfx_hi,y
        bne     @have
        lda     #0              ; neither: silent
        beq     @vol
@have:  txa                     ; the tone period
        asl
        sta     SFX_AY_ADDR
        lda     sfx_perl,y
        sta     SFX_AY_DATA
        txa
        asl
        ora     #1
        sta     SFX_AY_ADDR
        lda     sfx_perh,y
        and     #$0F
        sta     SFX_AY_DATA
        lda     sfx_mix,y       ; the mixer bits (0 = on)
        lsr
        bcc     @nt
        lda     sfx_tone_on,x
        and     sfx_mixer
        sta     sfx_mixer
@nt:    lda     sfx_mix,y
        and     #2
        beq     @nn
        lda     sfx_noise_on,x
        and     sfx_mixer
        sta     sfx_mixer
        lda     #6
        sta     SFX_AY_ADDR
        lda     sfx_noise,y
        sta     SFX_AY_DATA
@nn:    lda     sfx_vol,y
        ldy     sfx_mute
        beq     @vol
        lda     #0
@vol:   ldy     sfx_chan
        tax
        tya
        clc
        adc     #8
        sta     SFX_AY_ADDR
        stx     SFX_AY_DATA
        ldx     sfx_chan
        dex
        bpl     @ch
        lda     #7
        sta     SFX_AY_ADDR
        lda     sfx_mixer
        sta     SFX_AY_DATA
        rts
sfx_tone_on:    .byte   $3E, $3D, $3B
sfx_noise_on:   .byte   $37, $2F, $1F

; one voice (X): the sweep and the decay, then the script when its wait
; is over
sfx_voice:
        lda     sfx_swl,x       ; the sweep
        ora     sfx_swh,x
        beq     @ns
        lda     sfx_perl,x
        clc
        adc     sfx_swl,x
        sta     sfx_perl,x
        lda     sfx_perh,x
        adc     sfx_swh,x
        sta     sfx_perh,x
@ns:    lda     sfx_dec,x       ; the decay
        beq     @nd
        dec     sfx_decc,x
        bne     @nd
        sta     sfx_decc,x
        lda     sfx_vol,x
        beq     @nd
        dec     sfx_vol,x
@nd:    lda     sfx_wait,x
        beq     @run
        dec     sfx_wait,x
        beq     @run
        rts
@run:   lda     #40             ; (at most 40 commands a tick: a script that
        sta     sfx_guard       ;  never waits can't hang the game)
@cmd:   dec     sfx_guard
        beq     @stop
        jsr     sfx_byte
        cmp     #$80
        bcc     @nw
        and     #$7F            ; wait
        sta     sfx_wait,x
        inc     sfx_wait,x
        rts
@nw:    cmp     #$20
        bcc     @op
        sec                     ; a note
        sbc     #$20
        cmp     #96
        bcc     @nt
        lda     #95
@nt:    ldy     #0              ; octave Y, note A in it
@oc:    cmp     #12
        bcc     @ok
        sbc     #12
        iny
        bne     @oc
@ok:    sty     sfx_guard+1     ; (as a count)
        tay
        lda     sfx_c1_lo,y     ; the period in octave 1, halved for each
        sta     sfx_perl,x      ; octave up
        lda     sfx_c1_hi,y
        ldy     sfx_guard+1
        beq     @p
@sh:    lsr
        ror     sfx_perl,x
        dey
        bne     @sh
        sta     sfx_perh,x      ; (rounded: the last bit out was a half)
        bcc     @r0
        inc     sfx_perl,x
        bne     @r0
        inc     sfx_perh,x
        bne     @r0
@p:     sta     sfx_perh,x
@r0:
        lda     sfx_base,x
        sta     sfx_vol,x
        lda     sfx_dec,x
        sta     sfx_decc,x
@len:   lda     sfx_len,x       ; (LEN: wait that long)
        beq     @cmd
        sta     sfx_wait,x
        rts
@op:    cmp     #12
        bcs     @stop
        tay
        lda     @hi,y
        pha
        lda     @lo,y
        pha
        rts                     ; (to the command, which goes back to @cmd)
@stop:  lda     #0
        sta     sfx_hi,x
        sta     sfx_vol,x
        rts
@lo:    .lobytes  @stop-1, @per-1, @vl-1, @noi-1, @mix-1, @sw-1, @dc-1, @lp-1, @nx-1, @jp-1, @rest-1, @ln-1
@hi:    .hibytes  @stop-1, @per-1, @vl-1, @noi-1, @mix-1, @sw-1, @dc-1, @lp-1, @nx-1, @jp-1, @rest-1, @ln-1
@per:   jsr     sfx_byte
        sta     sfx_perl,x
        jsr     sfx_byte
        sta     sfx_perh,x
        jmp     @cmd
@vl:    jsr     sfx_byte
        sta     sfx_base,x
        sta     sfx_vol,x
        lda     sfx_dec,x
        sta     sfx_decc,x
        jmp     @cmd
@noi:   jsr     sfx_byte
        sta     sfx_noise,x
        jmp     @cmd
@mix:   jsr     sfx_byte
        sta     sfx_mix,x
        jmp     @cmd
@sw:    jsr     sfx_byte
        sta     sfx_swl,x
        jsr     sfx_byte
        sta     sfx_swh,x
        jmp     @cmd
@dc:    jsr     sfx_byte
        sta     sfx_dec,x
        sta     sfx_decc,x
        jmp     @cmd
@lp:    jsr     sfx_byte
        sta     sfx_lcnt,x
        lda     sfx_lo,x
        sta     sfx_lpl,x
        lda     sfx_hi,x
        sta     sfx_lph,x
        jmp     @cmd
@nx:    lda     sfx_lcnt,x
        beq     @back           ; (0: for ever)
        dec     sfx_lcnt,x
        beq     @go
@back:  lda     sfx_lpl,x
        sta     sfx_lo,x
        lda     sfx_lph,x
        sta     sfx_hi,x
@go:    jmp     @cmd
@jp:    jsr     sfx_byte
        pha
        jsr     sfx_byte
        sta     sfx_hi,x
        pla
        sta     sfx_lo,x
        jmp     @cmd
@rest:  lda     #0
        sta     sfx_vol,x
        jmp     @len
@ln:    jsr     sfx_byte
        sta     sfx_len,x
        jmp     @cmd

; the next byte of voice X's script
sfx_byte:
        lda     sfx_lo,x
        sta     @ld+1
        lda     sfx_hi,x
        sta     @ld+2
@ld:    lda     $FFFF
        inc     sfx_lo,x
        bne     @r
        inc     sfx_hi,x
@r:     rts

; the tone periods of C1 .. B1 for the 2 MHz chip clock: 2 MHz / (16 x
; frequency); each octave up is half (to within a third of a percent)
sfx_c1_lo:  .lobytes 3822, 3608, 3405, 3214, 3034, 2863, 2703, 2551, 2408, 2273, 2145, 2025
sfx_c1_hi:  .hibytes 3822, 3608, 3405, 3214, 3034, 2863, 2703, 2551, 2408, 2273, 2145, 2025

