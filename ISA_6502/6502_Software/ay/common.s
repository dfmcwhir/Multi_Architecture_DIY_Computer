; ============================================================================
; common.s - small helpers shared by AYTEST and YMPLAY: printing, keys, delays
; ============================================================================

; PRINT label: print the 0-ended string at label; keeps X
.macro  PRINT   str
        lda     #<str
        ldy     #>str
        jsr     print
.endmacro

; print the 0-ended string at A (low) / Y (high).  Keeps X.
print:  sta     @ld+1
        sty     @ld+2
@ld:    lda     $FFFF
        beq     @r
        jsr     SBC_CHROUT
        inc     @ld+1
        bne     @ld
        inc     @ld+2
        bne     @ld
@r:     rts

crlf:   lda     #13
        jsr     SBC_CHROUT
        lda     #10
        jmp     SBC_CHROUT

; print A as 2 decimal digits (0-99)
prdec2: ldx     #'0'
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     pha
        txa
        jsr     SBC_CHROUT
        pla
        ora     #'0'
        jmp     SBC_CHROUT

; print A in hex
prhex:  pha
        lsr
        lsr
        lsr
        lsr
        jsr     @d
        pla
        and     #$0F
@d:     cmp     #10
        bcc     @n
        adc     #'A' - '0' - 10 - 1
@n:     adc     #'0'
        jmp     SBC_CHROUT

; a key: carry set and A = the key (letters in upper case), or carry clear
getkey: jsr     SBC_CHRIN
        bcc     @r
        cmp     #'a'
        bcc     @y
        cmp     #'z' + 1
        bcs     @y
        and     #$DF
@y:     sec
@r:     rts

; wait for a key; A = the key (upper case)
waitkey:jsr     getkey
        bcc     waitkey
        rts

; wait about A ms.  The inner loop is sized for the clock (CLOCK_MHZ in
; sbc_api.inc): 5 + 4 * (CLOCK_MHZ - 1) cycles a turn, DELAY_N turns a ms.
DELAY_N = (1000 * CLOCK_MHZ - 7) / (5 + 4 * (CLOCK_MHZ - 1))
delay_ms:
        tax
        beq     @done
@o:     ldy     #DELAY_N
@i:
.repeat CLOCK_MHZ - 1
        nop
        nop
.endrepeat
        dey
        bne     @i
        dex
        bne     @o
@done:  rts
