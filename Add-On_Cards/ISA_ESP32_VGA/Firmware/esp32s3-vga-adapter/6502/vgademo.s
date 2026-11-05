; vgademo.s - demo for the ESP32-S3 VGA adapter. Load and run at $0500.
;
; Bitmap background, text overlay, a bouncing sprite synced to vblank with a
; sound on each bounce, keys play notes, the mouse paints. ESC quits.

        .setcpu "65C02"
        .include "vga.inc"
        .import vga_init, vga_puts, vga_wait_vbl, vga_hex

        .zeropage
ballx:  .res 2          ; 0..304
bally:  .res 1          ; 0..224
dx:     .res 1          ; signed
dy:     .res 1          ; signed
tmp:    .res 1
xacc:   .res 2
mouse:  .res 5          ; buttons, x lo, x hi, y lo, y hi

        .code
start:
        jsr vga_init
        bcc :+
        rts                     ; adapter not found
:
        ; ---------------------------------------------------- layers + text
        VCMD V_LAYERS
        VARG 7                  ; text + bitmap + sprites
        VCMD V_COLOR
        VARG YELLOW
        VARG TRANSPARENT        ; text floats over the graphics
        VCMD V_CLS
        VCMD V_CURSOR
        VARG 0

        ; ---------------------------------------------------- background
        VCMD V_GCLS
        VARG RGB(0,0,1)
        VCMD V_RECT
        VARG16 0
        VARG 0
        VARG16 320
        VARG 240
        VARG WHITE
        VCMD V_FILLCIRC
        VARG16 260
        VARG 70
        VARG 40
        VARG RGB(1,0,2)
        VCMD V_CIRCLE
        VARG16 260
        VARG 70
        VARG 46
        VARG MAGENTA

        ; 16 colour bars along the bottom: x = i*20, colour = i*4
        stz xacc
        stz xacc+1
        ldx #0
@bar:   VCMD V_FILLRECT
        lda xacc
        sta VGA_DATA
        lda xacc+1
        sta VGA_DATA
        VARG 216
        VARG16 20
        VARG 23
        txa
        asl a
        asl a
        sta VGA_DATA
        clc
        lda xacc
        adc #20
        sta xacc
        bcc :+
        inc xacc+1
:       inx
        cpx #16
        bne @bar

        ; ---------------------------------------------------- text
        VCMD V_LOCATE
        VARG 2
        VARG 1
        lda #<title
        ldx #>title
        jsr vga_puts
        VCMD V_COLOR
        VARG WHITE
        VARG TRANSPARENT
        VCMD V_LOCATE
        VARG 2
        VARG 3
        lda #<help
        ldx #>help
        jsr vga_puts

        ; ---------------------------------------------------- sprite pattern 0
        VCMD V_SPRDEF
        VARG 0
        ldx #0
@byte:  lda ball_mask,x
        sta tmp
        ldy #8
@bit:   asl tmp
        bcc @clear
        lda #YELLOW
        bra @put
@clear: lda #TRANSPARENT
@put:   sta VGA_DATA
        dey
        bne @bit
        inx
        cpx #32
        bne @byte

        lda #100
        sta ballx
        stz ballx+1
        lda #50
        sta bally
        lda #2
        sta dx
        lda #1
        sta dy
        VCMD V_SPRSET           ; sprite 0, pattern 0, visible
        VARG 0
        VARG 0
        VARG16 100
        VARG16 50
        VARG 1

        ; ---------------------------------------------------- sound + mouse
        IOCMD IO_SNDWAVE        ; voice 0: square blip for bounces
        IOARG 0
        IOARG 0
        IOARG 128
        IOCMD IO_SNDENV
        IOARG 0
        IOARG 0
        IOARG 2
        IOARG 0
        IOARG 3
        IOCMD IO_SNDWAVE        ; voice 1: triangle for the keyboard
        IOARG 1
        IOARG 1
        IOARG 0
        IOCMD IO_SNDENV
        IOARG 1
        IOARG 1
        IOARG 6
        IOARG 8
        IOARG 8
        VCMD V_MOUSEPTR
        VARG 1

        ; ---------------------------------------------------- main loop
loop:   jsr vga_wait_vbl
        jsr move_ball
        VCMD V_SPRMOVE
        VARG 0
        lda ballx
        sta VGA_DATA
        lda ballx+1
        sta VGA_DATA
        lda bally
        sta VGA_DATA
        stz VGA_DATA

        ; mouse: paint while the left button is held
        IOCMD IO_MOUSE
        ldx #0
:       lda IO_RESP
        sta mouse,x
        inx
        cpx #5
        bne :-
        lda mouse
        and #1
        beq @nomouse
        VCMD V_FILLRECT
        lda mouse+1
        sta VGA_DATA
        lda mouse+2
        sta VGA_DATA
        lda mouse+3
        sta VGA_DATA
        VARG16 2
        VARG 2
        VARG CYAN
@nomouse:
        ; keyboard: ESC quits, anything else plays a note and is shown
        lda VGA_KEY
        bne @key
        jmp loop
@key:   cmp #$1B
        beq quit
        pha
        IOCMD IO_SNDNOTE
        IOARG 1
        pla
        pha
        and #$1F
        clc
        adc #48
        sta IO_DATA             ; midi note 48..79
        IOARG 20                ; 1/3 second
        VCMD V_LOCATE
        VARG 2
        VARG 5
        lda #<keymsg
        ldx #>keymsg
        jsr vga_puts
        pla
        jsr vga_hex
        jmp loop

quit:   IOCMD IO_RESET
        VCMD V_RESET
        rts                     ; back to the monitor

; ------------------------------------------------------------- ball motion
move_ball:
        lda dx
        bmi @left
        clc
        adc ballx
        sta ballx
        lda ballx+1
        adc #0
        sta ballx+1
        beq @ydo                ; < 256: fine
        lda ballx
        cmp #<304
        bcc @ydo
        lda #<304
        sta ballx
        lda #$FE
        sta dx
        jsr blip
        bra @ydo
@left:  clc
        adc ballx
        sta ballx
        lda ballx+1
        adc #$FF
        sta ballx+1
        bpl @ydo
        stz ballx
        stz ballx+1
        lda #2
        sta dx
        jsr blip
@ydo:   lda bally
        clc
        adc dy
        sta bally
        lda dy
        bmi @up
        lda bally
        cmp #200                ; stop above the colour bars
        bcc @done
        lda #200
        sta bally
        lda #$FF
        sta dy
        jmp blip
@up:    lda bally
        cmp #225                ; wrapped below zero
        bcc @done
        stz bally
        lda #1
        sta dy
        jmp blip
@done:  rts

blip:   IOCMD IO_SNDNOTE
        IOARG 0
        IOARG 84
        IOARG 3
        rts

        .rodata
title:  .byte "ESP32-S3 VGA adapter demo", 0
help:   .byte "Type to play notes, hold the left mouse button to paint, ESC quits", 0
keymsg: .byte "Key code: $", 0

ball_mask:
        .byte %00000111, %11100000
        .byte %00011111, %11111000
        .byte %00111111, %11111100
        .byte %01111111, %11111110
        .byte %01111111, %11111110
        .byte %11111111, %11111111
        .byte %11111111, %11111111
        .byte %11111111, %11111111
        .byte %11111111, %11111111
        .byte %11111111, %11111111
        .byte %11111111, %11111111
        .byte %01111111, %11111110
        .byte %01111111, %11111110
        .byte %00111111, %11111100
        .byte %00011111, %11111000
        .byte %00000111, %11100000
