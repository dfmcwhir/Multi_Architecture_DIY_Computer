; vga.s - small driver for the ESP32-S3 VGA adapter (ca65, W65C02S)
;
;   vga_init      detect + reset the adapter. C=0 ok, C=1 not responding
;   vga_chrout    print A (EhBASIC-compatible output vector, preserves A/X/Y)
;   vga_chrin     C=1 and A=key if a key is waiting, else C=0 (EhBASIC input)
;   vga_waitkey   wait for a key, return it in A
;   vga_puts      print zero-terminated string at A=lo, X=hi
;   vga_wait_vbl  wait for the start of the next vertical blank
;   vga_hex       print A as two hex digits

        .setcpu "65C02"
        .include "vga.inc"

        .export vga_init, vga_chrout, vga_chrin, vga_waitkey
        .export vga_puts, vga_wait_vbl, vga_hex
        .exportzp vga_ptr

        .zeropage
vga_ptr:        .res 2

        .code

; The ESP32 needs about a second after power-up. Retry IO_PING for ~2-3 s
; (at 2 MHz) before giving up.
vga_init:
        ldy #0
        ldx #0
@retry: lda #IO_PING
        sta IO_CMD
        lda IO_RESP
        cmp #$A5
        bne @wait
        lda IO_RESP
        cmp #$5A
        beq @found
@wait:  lda #10
@dly:   dec a
        bne @dly
        dex
        bne @retry
        dey
        bne @retry
        sec
        rts
@found: lda #IO_RESET
        sta IO_CMD
        lda #V_RESET
        sta VGA_CMD
        clc
        rts

vga_chrout:
        sta VGA_DATA
        rts

vga_chrin:
        lda VGA_KEY
        beq @none
        sec
        rts
@none:  clc
        rts

vga_waitkey:
        lda VGA_KEY
        beq vga_waitkey
        rts

vga_puts:
        sta vga_ptr
        stx vga_ptr+1
        phy
        ldy #0
@loop:  lda (vga_ptr),y
        beq @done
        sta VGA_DATA
        iny
        bne @loop
        inc vga_ptr+1
        bra @loop
@done:  ply
        rts

; Reading STATUS clears the vblank flag, so read once to discard a stale
; flag, then wait for a fresh one.
vga_wait_vbl:
        pha
        lda VGA_STATUS
@wait:  lda VGA_STATUS
        and #ST_VBL
        beq @wait
        pla
        rts

vga_hex:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        jsr @digit
        pla
        pha
        and #$0F
        jsr @digit
        pla
        rts
@digit: cmp #10
        bcc @num
        adc #'A'-'0'-10-1       ; carry is set here
@num:   adc #'0'
        sta VGA_DATA
        rts
