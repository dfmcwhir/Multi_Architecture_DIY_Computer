; ============================================================================
; drv_spo.s - SPO256A-AL2 speech chip on the AY-3-8910 sound card ($7F26)
;
;   $7F26 write: allophone (0-63)
;   $7F26 read : D0 = STBY (1 = idle), D1 = /LRQ (0 = ready for the next one)
;
; Allophones go into a 64 byte queue.  With the VIA fitted the queue is fed
; from its timer interrupt (every timeout: 60-180 times a second), so a
; program hands over a whole phrase and carries on while it is spoken.  The
; chip asks for its next allophone while it is still saying the last one, so
; there are no gaps.  Without the VIA, SPO_PUT feeds the chip itself.
;
; Keep the card's SPO256 IRQ jumper (IRQ7) OFF: /LRQ stays low whenever the
; chip is waiting, and nothing in software can turn it off, so it would
; interrupt the CPU continuously.
; ============================================================================

SPO_PORT        = $7F26
SPO_QLEN        = 64                    ; (a power of 2)
SPO_PAUSE       = 3                     ; PA4: a short pause after each SAY

.segment "DRVVARS"
spo_ok:         .res 1                  ; $80 = the chip answered
spo_in:         .res 1
spo_out:        .res 1
spo_q:          .res SPO_QLEN

.segment "BIOS"

; ----------------------------------------------------------------------------
; spo_init - an idle SPO256 reads STBY = 1 and /LRQ = 0 (an empty bus reads
; $7F: both 1).  Clobbers A.
; ----------------------------------------------------------------------------
spo_init:
        lda     #0
        sta     spo_ok
        sta     spo_in
        sta     spo_out
        lda     SPO_PORT
        and     #$03
        cmp     #$01
        bne     @x
        lda     #$80
        sta     spo_ok
@x:     rts

; ----------------------------------------------------------------------------
; spo_tick - from the VIA interrupt (and SPO_PUT without a VIA): if the chip
; wants an allophone and one is waiting, give it.  Clobbers A, X.
; ----------------------------------------------------------------------------
spo_tick:
        bit     spo_ok
        bpl     @x
        ldx     spo_out
        cpx     spo_in
        beq     @x                      ; nothing waiting
        lda     SPO_PORT
        and     #$02                    ; /LRQ high: still busy
        bne     @x
        lda     spo_q,x
        sta     SPO_PORT
        inx
        txa
        and     #(SPO_QLEN - 1)
        sta     spo_out
@x:     rts

; ----------------------------------------------------------------------------
; SPO_PUT - queue allophone A (0-63).  Waits while the queue is full.
; Preserves X and Y.  Nothing happens if there is no chip.
; ----------------------------------------------------------------------------
SPO_PUT:
        bit     spo_ok
        bpl     @r
        and     #$3F
        pha
        txa
        pha
@full:  lda     spo_in                  ; full: (in + 1) = out
        clc
        adc     #1
        and     #(SPO_QLEN - 1)
        cmp     spo_out
        bne     @room
.if .not HAS_VIA
        php
        sei
        jsr     spo_tick                ; no timer: feed it from here
        plp
.endif
        jmp     @full
@room:  tsx
        lda     $0102,x                 ; the allophone
        ldx     spo_in
        sta     spo_q,x
        inx
        txa
        and     #(SPO_QLEN - 1)
        sta     spo_in
        pla
        tax
        pla
.if .not HAS_VIA
        php
        sei
        jsr     spo_tick
        plp
.endif
@r:     rts

; ----------------------------------------------------------------------------
; SPO_DRAIN - without the VIA: feed the chip until the queue is empty.
; ----------------------------------------------------------------------------
SPO_DRAIN:
.if .not HAS_VIA
        bit     spo_ok
        bpl     @r
@l:     lda     spo_in
        cmp     spo_out
        beq     @r
        php
        sei
        jsr     spo_tick
        plp
        jmp     @l
.endif
@r:     rts

; ----------------------------------------------------------------------------
; SPO_BUSY - C=1 while allophones are waiting or the chip is still speaking
; ----------------------------------------------------------------------------
SPO_BUSY:
        bit     spo_ok
        bpl     @no
        lda     spo_in
        cmp     spo_out
        bne     @yes
        lda     SPO_PORT
        and     #$01                    ; STBY = 0: still speaking
        bne     @no
@yes:   sec
        rts
@no:    clc
        rts

; ----------------------------------------------------------------------------
; SPO_SAY - queue the allophones at A (low) / Y (high), ended by $FF, then a
; short pause.  Returns at once (with the VIA).  Uses con_ptr.
; ----------------------------------------------------------------------------
SPO_SAY:
        sta     con_ptr
        sty     con_ptr+1
        ldy     #0
@l:     lda     (con_ptr),y
        cmp     #$FF
        beq     @end
        jsr     SPO_PUT
        iny
        bne     @l
@end:   lda     #SPO_PAUSE
        jsr     SPO_PUT
        jmp     SPO_DRAIN
