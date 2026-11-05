; ============================================================================
; ay.s - AY-3-8910 sound chip driver for the 6502 SBC (ca65)
;
; The card (write only):
;   AY_ADDR  $7F22  write the number of the register to use  (BDIR = BC1 = 1)
;   AY_DATA  $7F23  write a value to that register           (BDIR = 1, BC1 = 0)
;   BC2 and A8 tied high, A9 low; chip clock 2 MHz; the three channels mixed
;   together (mono).  The I/O ports aren't used: register 7 keeps them inputs.
;
; Only plain STA abs is used on the card's addresses: an indexed store
; (STA abs,X) can make an extra read cycle there first, and the card decodes
; the address without looking at R/W.
;
; Routines (A, X, Y may change unless it says):
;   ay_write    register X = A (A, X, Y kept)
;   ay_silence  all channels off, volumes 0, envelope stopped
;   ay_regs     registers 0-13 from the 14 bytes at (ay_ptr); register 13 is
;               only written when it isn't $FF (writing it restarts the
;               envelope)
;   ay_tone     channel X (0-2) to tone period A (low) / Y (high)
;   ay_note     channel X (0-2) to note A (0 = C1 .. 95 = B8, 45 = A4 440 Hz)
;   ay_volume   channel X (0-2) to volume A (0-15; 16 = the envelope)
;   ay_mixer    register 7 = A, the I/O port bits kept as inputs
;
; The registers:
;   0/1 2/3 4/5  tone period of A, B, C (12 bits: low, high 4 bits):
;                frequency = 2 MHz / (16 * period)
;   6            noise period (5 bits)
;   7            mixer: bits 0-2 tone A-C off, bits 3-5 noise A-C off
;                (0 = on), bits 6-7 I/O port directions (kept 0)
;   8 9 10       volume A, B, C (0-15), bit 4 = use the envelope
;   11/12        envelope period (16 bits): one ramp (16 steps) lasts
;                256 x period / 2 MHz
;   13           envelope shape (writing it restarts the envelope)
; ============================================================================

AY_ADDR         = $7F22
AY_DATA         = $7F23

AY_TONE_A       = 0
AY_NOISE        = 6
AY_MIXER        = 7
AY_VOL_A        = 8
AY_ENV_LO       = 11
AY_ENV_HI       = 12
AY_ENV_SHAPE    = 13

; envelope shapes (register 13)
ENV_DECAY       = $00           ; \______   fade out once
ENV_ATTACK      = $0D           ; /~~~~~~   fade in once, then stay up
ENV_SAW_DOWN    = $08           ; \\\\\\\   repeat
ENV_SAW_UP      = $0C           ; ///////   repeat
ENV_TRIANGLE    = $0E           ; /\/\/\/   repeat
ENV_TRIANGLE2   = $0A           ; \/\/\/\   repeat
ENV_DECAY_HOLD  = $0B           ; \~~~~~~   fade out, then jump up and stay
ENV_ATTACK_ZERO = $0F           ; /______   fade in, then drop to 0

; register X = A.  Keeps A, X and Y.
ay_write:
        stx     AY_ADDR
        sta     AY_DATA
        rts

; everything quiet: tones and noise off, volumes 0, the envelope stopped
ay_silence:
        pha
        txa
        pha
        lda     #$3F            ; mixer: all off (and the ports inputs)
        ldx     #AY_MIXER
        jsr     ay_write
        lda     #0
        ldx     #AY_VOL_A       ; volumes 0
        jsr     ay_write
        inx
        jsr     ay_write
        inx
        jsr     ay_write
        ldx     #0              ; tone and noise periods 0
@p:     jsr     ay_write
        inx
        cpx     #AY_MIXER
        bne     @p
        ldx     #AY_ENV_LO      ; envelope period 0, shape 0 (fades to 0)
        jsr     ay_write
        inx
        jsr     ay_write
        inx
        jsr     ay_write
        pla
        tax
        pla
        rts

; registers 0-13 from (ay_ptr); register 13 only if it isn't $FF
ay_regs:
        lda     ay_ptr
        sta     @ld+1
        lda     ay_ptr+1
        sta     @ld+2
        ldx     #0
@l:
@ld:    lda     $FFFF,x
        cpx     #AY_ENV_SHAPE
        bne     @w
        cmp     #$FF
        beq     @r
@w:     stx     AY_ADDR
        sta     AY_DATA
        inx
        cpx     #14
        bne     @l
@r:     rts

; channel X (0-2): tone period A (low) / Y (high)
ay_tone:
        pha
        txa
        asl
        tax
        pla
        jsr     ay_write        ; the low byte
        inx
        tya
        jsr     ay_write        ; the high 4 bits
        txa
        lsr
        tax
        rts

; channel X (0-2): note A (0 = C1 .. 95 = B8)
ay_note:
        cmp     #AY_NOTES
        bcc     @ok
        lda     #AY_NOTES - 1
@ok:    tay
        lda     note_hi,y
        pha
        lda     note_lo,y
        tay
        pla                     ; (A = high, Y = low: swapped for ay_tone)
        sta     ay_tmp
        tya
        ldy     ay_tmp
        jmp     ay_tone

; channel X (0-2): volume A (0-15, 16 = follow the envelope)
ay_volume:
        pha
        txa
        clc
        adc     #AY_VOL_A
        tax
        pla
        jsr     ay_write
        pha
        txa
        sec
        sbc     #AY_VOL_A
        tax
        pla
        rts

; mixer (register 7) = A: the port direction bits are always kept 0 (inputs)
ay_mixer:
        and     #$3F
        ldx     #AY_MIXER
        jmp     ay_write

        .include "ay_notes.inc"

        .segment "BSS"
ay_ptr:     .res 2              ; ay_regs: where the 14 register values are
ay_tmp:     .res 1
        .segment "CODE"
