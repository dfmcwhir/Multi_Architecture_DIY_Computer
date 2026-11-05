; LOADTEST - check the ROM's SBC_LOAD entry ($FE15) before playing DOOM
;   L LOADTEST 0500   then   R
; Loads E1M1.LVL to $5000 and prints the result, then tries a file that
; isn't there (that must fail with the carry set), then goes back to the
; monitor.
        .include "sbc_api.inc"
        .segment "CODE"
start:  cld
        ldx     #$FF
        txs
        lda     #<hello_txt
        ldy     #>hello_txt
        jsr     print
        lda     SBC_LOAD        ; is there a JMP at $FE15?
        cmp     #$4C
        beq     @have
        lda     #<none_txt
        ldy     #>none_txt
        jsr     print
        jmp     SBC_MONITOR
@have:  lda     #<good_txt      ; 1: a file that is there
        ldy     #>good_txt
        jsr     print
        jsr     fill
        lda     #<blk1
        ldy     #>blk1
        jsr     SBC_LOAD
        jsr     report
        bcs     @t2
        lda     #<first_txt     ; the first bytes: 44 36 01 = "D6", version 1
        ldy     #>first_txt
        jsr     print
        ldx     #0
@b:     lda     $5000,x
        jsr     pr_hex
        lda     #' '
        jsr     SBC_CHROUT
        inx
        cpx     #8
        bne     @b
        jsr     crlf
@t2:    lda     #<bad_txt       ; 2: a file that isn't there
        ldy     #>bad_txt
        jsr     print
        lda     #<blk2
        ldy     #>blk2
        jsr     SBC_LOAD
        jsr     report
        lda     #<limit_txt     ; 3: the length limit (load only 16 bytes)
        ldy     #>limit_txt
        jsr     print
        jsr     fill
        lda     #<blk3
        ldy     #>blk3
        jsr     SBC_LOAD
        jsr     report
        lda     $5010           ; the 17th byte must still be $EE
        cmp     #$EE
        beq     @lok
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
@lok:   lda     #<end_txt
        ldy     #>end_txt
        jsr     print
        jmp     SBC_MONITOR

; fill the buffer with $EE first, to see what gets written
fill:   lda     #$EE
        ldx     #0
@f:     sta     $5000,x
        sta     $5100,x
        sta     $5200,x
        sta     $5300,x
        sta     $5400,x
        sta     $5500,x
        inx
        bne     @f
        rts

; print what SBC_LOAD returned (keeps the carry)
report: php
        bcs     @err
        stx     len_lo
        sty     len_hi
        lda     #<ok_txt
        ldy     #>ok_txt
        jsr     print
        lda     len_hi
        jsr     pr_hex
        lda     len_lo
        jsr     pr_hex
        jsr     crlf
        plp
        rts
@err:   pha
        lda     #<err_txt
        ldy     #>err_txt
        jsr     print
        pla
        jsr     pr_hex
        jsr     crlf
        plp
        rts

print:  sta     @rd+1
        sty     @rd+2
@rd:    lda     $FFFF
        beq     @r
        jsr     SBC_CHROUT
        inc     @rd+1
        bne     @rd
        inc     @rd+2
        bne     @rd
@r:     rts

crlf:   lda     #13
        jsr     SBC_CHROUT
        lda     #10
        jmp     SBC_CHROUT

pr_hex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     @d
        pla
        and     #15
@d:     cmp     #10
        bcc     @n
        adc     #6
@n:     adc     #'0'
        jmp     SBC_CHROUT

        .segment "RODATA"
hello_txt:  .byte 13, 10, "SBC_LOAD TEST", 13, 10, 0
none_txt:   .byte "NO JMP AT $FE15: THIS ROM HAS NO SBC_LOAD", 13, 10, 0
good_txt:   .byte "1. LOAD E1M1.LVL TO $5000 (MAX $0600): ", 0
first_txt:  .byte "   FIRST BYTES (WANT 44 36 01 ...): ", 0
bad_txt:    .byte "2. LOAD NOFILE.XYZ (MUST FAIL): ", 0
limit_txt:  .byte "3. LOAD E1M1.LVL, MAX 16 BYTES (WANT LENGTH 0010): ", 0
over_txt:   .byte "   WRONG: MORE THAN 16 BYTES WERE WRITTEN", 13, 10, 0
ok_txt:     .byte "OK, LENGTH $", 0
err_txt:    .byte "FAILED, ERROR $", 0
end_txt:    .byte "DONE", 13, 10, 0
blk1:       .word $5000, $0600
            .byte "E1M1.LVL", 0
blk2:       .word $5000, $0600
            .byte "NOFILE.XYZ", 0
blk3:       .word $5000, $0010
            .byte "E1M1.LVL", 0

        .segment "BSS"
len_lo:     .res 1
len_hi:     .res 1
