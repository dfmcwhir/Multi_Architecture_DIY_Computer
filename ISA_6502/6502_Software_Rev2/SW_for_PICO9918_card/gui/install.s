; ============================================================================
; install.s - GUI.BIN's start: copies the file manager (assembled to run at
; $1000) into the top RAM bank and registers it with SBC_SHELL; then the
; ROM starts it (SBC_MENU goes to the shell from now on).
;
;   GUI.BIN:  $0800  this (and a page buffer), $0B00  the file manager
;
; The copy goes a page at a time through the buffer here ($0800-$0FFF is
; never banked): read from the bank GUI.BIN was loaded into, write to the
; top bank.
; ============================================================================

        .include "sbc_api.inc"

; the stage 6 entries (an older sbc_api.inc doesn't have them)
.ifndef SBC_SHELL
SBC_DIR         = $FE57
SBC_RUN         = $FE5A
SBC_SHELL       = $FE5D
.endif

IMG     = $0B00                 ; the file manager in GUI.BIN (as loaded)
IMG_DST = $1000                 ; where it runs, in its bank

        .segment "INSTALL"
        jmp     inst
inst:   cld
        lda     SBC_SHELL       ; ROM stage 6?
        cmp     #$4C
        bne     @old
        jsr     SBC_SYSINFO
        cmp     #DISP_PICO
        bne     @pico
        jsr     SBC_BANKGET     ; A = this bank, X = banks fitted
        sta     i_src
        dex
        stx     i_dst
        beq     @banks          ; (one bank)
        cpx     i_src
        beq     @banks          ; (loaded into the top bank itself)
        lda     IMG+8           ; pages = (the end - $1000 + 255) / 256
        clc
        adc     #$FF
        lda     IMG+9
        adc     #0
        sec
        sbc     #>IMG_DST
        sta     i_n
        lda     #>IMG
        sta     @rd+2
        lda     #>IMG_DST
        sta     @wr+2
@pg:    lda     i_src
        jsr     SBC_BANKSET
        ldx     #0
@rd:    lda     IMG,x
        sta     i_buf,x
        inx
        bne     @rd
        lda     i_dst
        jsr     SBC_BANKSET
        ldx     #0
@cp:    lda     i_buf,x
@wr:    sta     IMG_DST,x
        inx
        bne     @cp
        inc     @rd+2
        inc     @wr+2
        dec     i_n
        bne     @pg
        lda     i_src
        jsr     SBC_BANKSET
        lda     i_dst
        jsr     SBC_SHELL
        bcs     @bad
        jmp     SBC_MENU        ; (the ROM starts the shell)
@old:   lda     #<m_old
        ldy     #>m_old
        bne     @msg
@pico:  lda     #<m_pico
        ldy     #>m_pico
        bne     @msg
@banks: lda     #<m_banks
        ldy     #>m_banks
        bne     @msg
@bad:   lda     #<m_bad
        ldy     #>m_bad
@msg:   sta     @pr+1
        sty     @pr+2
        ldx     #0
@pr:    lda     $FFFF,x
        beq     @end
        jsr     SBC_CHROUT
        inx
        bne     @pr
@end:   jmp     SBC_MONITOR

m_old:  .byte   13, 10, "GUI needs ROM stage 6 (SBC_DIR, SBC_RUN, SBC_SHELL)", 13, 10, 0
m_pico: .byte   13, 10, "GUI needs the PICO9918 display", 13, 10, 0
m_banks:
        .byte   13, 10, "GUI needs a second RAM bank (load it into bank 0)", 13, 10, 0
m_bad:  .byte   13, 10, "GUI: the copy in the top bank failed its check", 13, 10, 0
i_src:  .res    1
i_dst:  .res    1
i_n:    .res    1
i_buf:  .res    256
