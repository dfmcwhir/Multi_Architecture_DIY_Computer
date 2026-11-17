; ============================================================================
; mousetest.s - MOUSETEST: what the ROM gets from the mouse (CPU Rev2)
;
;   build:  make.bat           run:  L MOUSETEST 0800   then   R
;
; Turns mouse reports on (SBC_MOUSEON) and prints every report SBC_MOUSE
; returns: the buttons and the movement, and the running totals.  Any key
; ends it (mouse reports off again, back to the boot menu).  It prints
; through the ROM's console, so it works on any display.
; ============================================================================
        .setcpu "65C02"
        .include "sbc_api.inc"

        .segment "CODE"
        jmp     start

start:  jsr     SBC_CONRESET
        lda     #<hello
        ldy     #>hello
        jsr     puts
        lda     SBC_MOUSEON     ; a ROM with the mouse calls?
        cmp     #$4C
        beq     @api
        lda     #<noapi
        ldy     #>noapi
        jsr     puts
        jmp     wait_end
@api:   lda     #1
        jsr     SBC_MOUSEON
        bcc     @on
        lda     #<nomouse
        ldy     #>nomouse
        jsr     puts
        jmp     wait_end
@on:    lda     #<onmsg
        ldy     #>onmsg
        jsr     puts
        lda     #0
        sta     count
        sta     count+1
        sta     tx
        sta     tx+1
        sta     ty
        sta     ty+1
@loop:  jsr     SBC_CHRIN       ; a key ends it
        bcc     :+
        jmp     @end
:       jsr     SBC_MOUSE
        bcc     @loop
        sta     btn
        stx     dx
        sty     dy
        inc     count
        bne     :+
        inc     count+1
:       lda     dx              ; totals (16 bit, signed)
        jsr     sx16
        clc
        adc     tx
        sta     tx
        txa
        adc     tx+1
        sta     tx+1
        lda     dy
        jsr     sx16
        clc
        adc     ty
        sta     ty
        txa
        adc     ty+1
        sta     ty+1
        lda     #<r1            ; "#nnnn B b X +nnn Y +nnn  TOTAL x y"
        ldy     #>r1
        jsr     puts
        lda     count+1
        jsr     hex2
        lda     count
        jsr     hex2
        lda     #<r2
        ldy     #>r2
        jsr     puts
        lda     btn
        jsr     hex2
        lda     #<r3
        ldy     #>r3
        jsr     puts
        lda     dx
        jsr     hex2
        lda     #<r4
        ldy     #>r4
        jsr     puts
        lda     dy
        jsr     hex2
        lda     #<r5
        ldy     #>r5
        jsr     puts
        lda     tx+1
        jsr     hex2
        lda     tx
        jsr     hex2
        lda     #' '
        jsr     SBC_CHROUT
        lda     ty+1
        jsr     hex2
        lda     ty
        jsr     hex2
        lda     #13
        jsr     SBC_CHROUT
        lda     #10
        jsr     SBC_CHROUT
        jmp     @loop
@end:   lda     #0
        jsr     SBC_MOUSEON     ; reports off
        jmp     SBC_MENU

wait_end:
        jsr     SBC_CHRIN
        bcc     wait_end
        jmp     SBC_MENU

; A -> X:A sign-extended
sx16:   ldx     #0
        cmp     #$80
        bcc     :+
        dex
:       rts

hex2:   pha
        lsr
        lsr
        lsr
        lsr
        jsr     @d
        pla
        and     #15
@d:     cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        jmp     SBC_CHROUT

puts:   sta     @l+1
        sty     @l+2
        ldx     #0
@l:     lda     $FFFF,x
        beq     @r
        jsr     SBC_CHROUT
        inx
        bne     @l
@r:     rts

        .segment "RODATA"
hello:  .byte   "MOUSE TEST - ANY KEY ENDS", 13, 10, 0
noapi:  .byte   "THIS ROM HAS NO MOUSE CALLS", 13, 10, 0
nomouse:.byte   "SBC_MOUSEON: NO MOUSE INTERFACE", 13, 10
        .byte   "(NO AVR, OR MOUSE_SRC = NONE)", 13, 10, 0
onmsg:  .byte   "MOUSE REPORTS ON. MOVE IT,", 13, 10
        .byte   "PRESS ITS BUTTONS...", 13, 10, 0
r1:     .byte   "#", 0
r2:     .byte   " B", 0
r3:     .byte   " X", 0
r4:     .byte   " Y", 0
r5:     .byte   " T", 0

        .segment "BSS"
count:  .res    2
tx:     .res    2
ty:     .res    2
btn:    .res    1
dx:     .res    1
dy:     .res    1
