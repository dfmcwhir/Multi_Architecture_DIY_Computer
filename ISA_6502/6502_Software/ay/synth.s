; ============================================================================
; synth.s - the sounds of PIANO and SEQ: 8 sounds and a drum kit on the three
; channels, each note with its own shape (attack, decay to a sustain level, a
; time held, release), vibrato, octave and chord arpeggios, falling pitch,
; noise, and the envelope as a saw wave (BUZZ).
;
;   syn_init    all off
;   syn_start   start a note: sound k_ins, note k_note, on channel X
;   step_all    every 1/50 s: every channel a frame on, the registers written
;   all_off     all the notes off now
;   chan_out    channel X's registers from its state
;   hold,x      frames a note stays in its sustain (beyond its own time)
;   gate_mode   1: a note sustains only while hold,x lasts (SEQ's steps)
;
; Needs ay.s (ay_write, ay_tone, ay_volume, ay_mixer, the note table).
; ============================================================================

; the sounds: 16 bytes each
I_ATK           = 0             ; attack: added to the volume a frame (240 = at once)
I_DEC           = 1             ; decay: taken off a frame, down to
I_SUS           = 2             ;  the sustain level (volume x 16, 0-240)
I_SUST          = 3             ; frames it sustains at least (more while held)
I_REL           = 4             ; release: taken off a frame
I_FLAGS         = 5
I_VIB           = 6             ; vibrato: the period / 2^n either way
I_VDEL          = 7             ;  after this many frames
I_SWEEP         = 8             ; the pitch falls: period += period / 2^n a frame
I_NOISE         = 9             ; the noise period to set (0: not)
I_NOTE          = 10            ; a fixed note ($FF: the key's)
I_NFR           = 11            ; noise only for this many frames (0: all along)
I_REP           = 12            ; a key again within this many frames: a repeat

F_NOISE         = 1
F_NOTONE        = 2
F_BUZZ          = 4             ; the envelope as a saw wave at the note
F_OCT           = 8             ; the octave above every other frame
F_CHORD         = 16            ; a major chord, a note a frame
F_SWEEP         = 32
F_DRUMS         = 64            ; the key picks a drum
F_VIB           = 128

N_SOUNDS        = 8             ; the ones to choose from
DRUM_KIT        = 8             ; the drums after them
HOLD            = 8             ; frames a key repeat holds a note for

ST_OFF          = 0
ST_ATK          = 1
ST_DEC          = 2
ST_SUS          = 3
ST_REL          = 4

; all off: the channels silent, tones on, noise off
syn_init:
        lda     #$38
        sta     mixer
        jsr     ay_mixer
        ldx     #2
@c:     lda     #ST_OFF
        sta     st,x
        sta     vol,x
        sta     hold,x
        dex
        bpl     @c
        lda     #0
        sta     frame
        sta     arp3
        sta     gate_mode
        rts

; start a note: sound k_ins, note k_note (or the sound's own) on channel X;
; its registers are written at once
syn_start:
        lda     k_ins
        sta     ins,x
        jsr     ins_ptr
        ldy     #I_NOTE
        lda     cur_ins,y
        cmp     #$FF
        bne     @fix
        lda     k_note
@fix:   sta     note,x
        tay
        lda     note_lo,y       ; the period, for the sweeps
        sta     per_lo,x
        lda     note_hi,y
        sta     per_hi,x
        lda     #0
        sta     t,x
        sta     age,x
        sta     last,x
        sta     hold,x
        lda     #ST_ATK
        sta     st,x
        ldy     #I_ATK          ; at once: straight to the decay
        lda     cur_ins,y
        cmp     #240
        bcc     @noise
        lda     #240
        sta     vol,x
        lda     #ST_DEC
        sta     st,x
@noise: ldy     #I_NOISE
        lda     cur_ins,y
        beq     @buzz
        stx     s_t1
        ldx     #AY_NOISE
        jsr     ay_write
        ldx     s_t1
@buzz:  ldy     #I_FLAGS
        lda     cur_ins,y
        and     #F_BUZZ
        beq     @out
        stx     s_t1             ; the envelope period: the tone period / 16
        lda     per_lo,x
        clc
        adc     #8
        sta     s_t2
        lda     per_hi,x
        adc     #0
        lsr
        ror     s_t2
        lsr
        ror     s_t2
        lsr
        ror     s_t2
        lsr
        ror     s_t2
        ldx     #AY_ENV_HI
        jsr     ay_write
        lda     s_t2
        ldx     #AY_ENV_LO
        jsr     ay_write
        lda     #ENV_SAW_DOWN   ; (starts it)
        ldx     #AY_ENV_SHAPE
        jsr     ay_write
        ldx     s_t1
@out:   jmp     chan_out        ; on the chip now

; cur_ins = the sound A's 16 bytes (keeps X)
ins_ptr:
        asl
        asl
        asl
        asl
        tay
        stx     @x
        ldx     #0
@c:     lda     ins_tab,y
        sta     cur_ins,x
        iny
        inx
        cpx     #16
        bne     @c
        ldx     @x
        rts
@x:     .byte   0

; A = A mod 12
mod12:  cmp     #12
        bcc     @r
        sbc     #12
        bcs     mod12
@r:     rts

; all the notes off at once
all_off:
        ldx     #2
@c:     lda     #ST_OFF
        sta     st,x
        sta     vol,x
        jsr     chan_out
        dex
        bpl     @c
        rts


; ---- the sounds, a frame on ------------------------------------------------------------
step_all:
        inc     frame
        inc     arp3            ; (0 1 2: the chord's notes)
        lda     arp3
        cmp     #3
        bcc     @a
        lda     #0
        sta     arp3
@a:     ldx     #2
@c:     jsr     chan_step
        jsr     chan_out
        dex
        bpl     @c
        rts

; channel X: its volume a frame on (attack, decay, sustain, release)
chan_step:
        lda     age,x           ; (the counts, kept at 255)
        cmp     #255
        beq     :+
        inc     age,x
:       lda     last,x
        cmp     #255
        beq     :+
        inc     last,x
:       lda     hold,x
        beq     :+
        dec     hold,x
:       lda     st,x
        bne     :+
        rts
:       lda     ins,x
        jsr     ins_ptr
        lda     st,x
        cmp     #ST_ATK
        bne     @dec
        ldy     #I_ATK
        lda     vol,x
        clc
        adc     cur_ins,y
        bcs     @top
        cmp     #240
        bcc     @sv
@top:   lda     #240
        sta     vol,x
        lda     #ST_DEC
        sta     st,x
        rts
@sv:    sta     vol,x
        rts
@dec:   cmp     #ST_DEC
        bne     @sus
        ldy     #I_DEC
        lda     cur_ins,y
        beq     @tosus          ; (no decay: straight to the sustain level)
        sta     s_t1
        lda     vol,x
        sec
        sbc     s_t1
        bcc     @tosus
        ldy     #I_SUS
        cmp     cur_ins,y
        bcc     @tosus
        beq     @tosus
        sta     vol,x
        rts
@tosus: ldy     #I_SUS
        lda     cur_ins,y
        sta     vol,x
        beq     @off            ; (sustain 0: the note is over)
        lda     #ST_SUS
        sta     st,x
        lda     #0
        sta     t,x
        rts
@sus:   cmp     #ST_SUS
        bne     @rel
        lda     t,x
        cmp     #255
        beq     :+
        inc     t,x
:       lda     hold,x          ; held: stay
        bne     @r
        lda     gate_mode       ; (SEQ: only as long as held)
        bne     @torel
        ldy     #I_SUST
        lda     t,x
        cmp     cur_ins,y
        bcc     @r
@torel: lda     #ST_REL
        sta     st,x
@r:     rts
@rel:   ldy     #I_REL
        lda     vol,x
        sec
        sbc     cur_ins,y
        bcc     @off
        beq     @off
        sta     vol,x
        rts
@off:   lda     #ST_OFF
        sta     st,x
        lda     #0
        sta     vol,x
        rts

; channel X's registers from how it is now: tone period, volume, the mixer
chan_out:
        stx     cx
        lda     st,x
        bne     @on
        lda     #0              ; off: volume 0
        jsr     ay_volume
        jmp     @mix
@on:    lda     ins,x
        jsr     ins_ptr
        ldy     #I_FLAGS
        lda     cur_ins,y
        sta     fl
        and     #F_SWEEP        ; the pitch falling: per += per >> n
        beq     @pitch
        ldy     #I_SWEEP
        lda     cur_ins,y
        tay
        lda     per_lo,x
        sta     s_t1
        lda     per_hi,x
        sta     s_t2
@sh:    lsr     s_t2
        ror     s_t1
        dey
        bne     @sh
        lda     per_lo,x
        clc
        adc     s_t1
        sta     per_lo,x
        sta     p_lo
        lda     per_hi,x
        adc     s_t2
        cmp     #$10            ; (12 bits at most)
        bcc     @sw
        lda     #$FF
        sta     per_lo,x
        sta     p_lo
        lda     #$0F
@sw:    sta     per_hi,x
        sta     p_hi
        jmp     @tone
@pitch: lda     note,x          ; the note, or a note of the chord
        ldy     fl
        cpy     #F_CHORD
        bne     @n
        ldy     arp3
        clc
        adc     chord,y
        cmp     #AY_NOTES
        bcc     @n
        lda     #AY_NOTES - 1
@n:     tay
        lda     note_lo,y
        sta     p_lo
        lda     note_hi,y
        sta     p_hi
        lda     fl              ; the octave above, every other frame
        and     #F_OCT
        beq     @vib
        lda     frame
        lsr
        bcc     @vib
        lsr     p_hi
        ror     p_lo
@vib:   lda     fl              ; vibrato: + d, 0, - d, 0 ...
        bpl     @tone
        ldy     #I_VDEL
        lda     age,x
        cmp     cur_ins,y
        bcc     @tone
        ldy     #I_VIB
        lda     cur_ins,y
        tay
        lda     p_lo
        sta     s_t1
        lda     p_hi
        sta     s_t2
@vs:    lsr     s_t2
        ror     s_t1
        dey
        bne     @vs
        lda     frame
        and     #6
        cmp     #2
        beq     @vup
        cmp     #6
        bne     @tone
        lda     p_lo            ; down: - d
        sec
        sbc     s_t1
        sta     p_lo
        lda     p_hi
        sbc     s_t2
        sta     p_hi
        jmp     @tone
@vup:   lda     p_lo
        clc
        adc     s_t1
        sta     p_lo
        lda     p_hi
        adc     s_t2
        sta     p_hi
@tone:  lda     p_lo
        ldy     p_hi
        ldx     cx
        jsr     ay_tone
        lda     fl              ; the volume (BUZZ: the envelope)
        and     #F_BUZZ
        beq     @v
        lda     #16
        bne     @vw
@v:     lda     vol,x
        lsr
        lsr
        lsr
        lsr
@vw:    jsr     ay_volume
@mix:   ldx     cx              ; the mixer: this channel's bits
        lda     mixer
        ora     tone_bit,x      ; (off to start with)
        ora     noise_bit,x
        sta     mixer
        lda     st,x
        beq     @mw             ; (off: both off)
        lda     fl
        and     #F_NOTONE
        bne     @nz
        lda     mixer
        and     tone_off,x
        sta     mixer
@nz:    lda     fl
        and     #F_NOISE
        beq     @mw
        ldy     #I_NFR
        lda     cur_ins,y
        beq     @non
        cmp     age,x
        bcc     @mw
        beq     @mw
@non:   lda     mixer
        and     noise_off,x
        sta     mixer
@mw:    lda     mixer
        jsr     ay_mixer
        ldx     cx
        rts

tone_bit:   .byte   1, 2, 4
noise_bit:  .byte   8, 16, 32
tone_off:   .byte   $FE, $FD, $FB
noise_off:  .byte   $F7, $EF, $DF
chord:      .byte   0, 4, 7

; the sounds' names (8 characters each) and the sounds
names:      .byte   "PIANO   HARP    ORGAN   STRINGS CHIP    CHORD   BUZZ    DRUMS   "

; the sounds: attack, decay, sustain, sustain frames, release, flags,
; vibrato shift and delay, sweep shift, noise period, fixed note, noise frames,
; repeat window, (3 spare)
ins_tab:
        .byte   240,  6,  96,  0,   2, 0,                  0,  0, 0, 0, $FF, 0,  6, 0,0,0  ; PIANO
        .byte   240, 12,  40,  0,   3, 0,                  0,  0, 0, 0, $FF, 0,  6, 0,0,0  ; HARP
        .byte    60,  0, 208, 30,   8, 0,                  0,  0, 0, 0, $FF, 0, 40, 0,0,0  ; ORGAN
        .byte    12,  0, 192, 40,   4, F_VIB,              7, 15, 0, 0, $FF, 0, 40, 0,0,0  ; STRINGS
        .byte   240,  4, 160, 20,   4, F_OCT,              0,  0, 0, 0, $FF, 0,  6, 0,0,0  ; CHIP
        .byte   240,  4, 160, 20,   4, F_CHORD,            0,  0, 0, 0, $FF, 0,  6, 0,0,0  ; CHORD
        .byte   240,  0, 240, 25, 240, F_BUZZ|F_NOTONE,    0,  0, 0, 0, $FF, 0, 40, 0,0,0  ; BUZZ
        .byte   240, 40,   0,  0,   0, F_DRUMS,            0,  0, 0, 0, $FF, 0,  6, 0,0,0  ; DRUMS (the kit:)
        .byte   240, 24,   0,  0,   0, F_SWEEP,            0,  0, 2, 0,  31, 0,  6, 0,0,0  ; kick
        .byte   240, 14,   0,  0,   0, F_NOISE|F_SWEEP,    0,  0, 4, 6,  43, 0,  6, 0,0,0  ; snare
        .byte   240, 40,   0,  0,   0, F_NOISE|F_NOTONE,   0,  0, 0, 1, $FF, 0,  6, 0,0,0  ; closed hi-hat
        .byte   240, 10,   0,  0,   0, F_NOISE|F_NOTONE,   0,  0, 0, 1, $FF, 0,  6, 0,0,0  ; open hi-hat
        .byte   240, 12,   0,  0,   0, F_SWEEP,            0,  0, 4, 0, $FF, 0,  6, 0,0,0  ; tom
        .byte   240,  5,   0,  0,   0, F_NOISE|F_NOTONE,   0,  0, 0, 3, $FF, 0,  6, 0,0,0  ; crash


        .segment "BSS"
frame:      .res 1
arp3:       .res 1
mixer:      .res 1
cx:         .res 1
fl:         .res 1
p_lo:       .res 1
p_hi:       .res 1
k_note:     .res 1
k_ins:      .res 1
cur_ins:    .res 16             ; the sound in use (ins_ptr)
st:         .res 3              ; each channel: the stage,
note:       .res 3              ;  the note,
ins:        .res 3              ;  the sound
vol:        .res 3              ;  the volume x 16
t:          .res 3              ;  frames in the sustain
age:        .res 3              ;  frames since it started
last:       .res 3              ;  frames since its key was last pressed
hold:       .res 3              ;  frames still held by key repeats
per_lo:     .res 3              ;  the period (the sweeps)
per_hi:     .res 3
s_t1:       .res 1
gate_mode:  .res 1
s_t2:       .res 1
        .segment "CODE"
