; ============================================================================
; vdp.s - PICO9918 / TMS9918A routines shared by the SBC games (CPU Rev2)
;
; Include it after setting VDP_NAME (the name table's VRAM address):
;           VDP_NAME = $1800
;           .include "lib/vdp.s"
; No zero page is used: the copy routines patch their own addresses.
;
;   vdp_setup   A/Y -> 8 bytes: R0-R7.  Puts a PICO9918 (F18A mode) back to
;               plain TMS9918A behaviour first (24 rows, all 32 sprites, no
;               scrolling, no second tile layer; the unlock leaves VR30 at
;               31 sprites a line),
;               clears the 16K of VRAM, then loads R0-R7.  Interrupts from
;               the VDP should be off in R1 (bit 5): the games poll.
;   vdp_reg     register X = A
;   vdp_waddr   VRAM write address = A (low) / Y (high)
;   vdp_fill    write A to VRAM vdp_n (16 bit) times, from the address set
;   vdp_copy    copy vdp_n bytes from RAM vdp_src to VRAM (from the address set)
;   vdp_at      write address = the name table cell at column X, row Y
;   vdp_puts    write the 0-ended string at A/Y from there (names = ASCII)
;   vdp_bcd     write A as two digits
;   vdp_frame   wait for the next frame (60 a second), calling frame_idle
;               (the game's: sound, random numbers) while it waits
;
; The VDP's ports: data $7F1C, control/status $7F1D.  Reading the status
; clears the frame flag, so nothing else should read it while a game runs
; (the ROM doesn't, with PICO_IRQ = 0 in its config.inc, the default).
; ============================================================================

VDP_DATA        = $7F1C
VDP_CTRL        = $7F1D

; register X = A.  Keeps A, X, Y.
vdp_reg:
        sta     VDP_CTRL
        pha
        txa
        ora     #$80
        sta     VDP_CTRL
        pla
        rts

; VRAM write address = A (low) / Y (high).  Keeps A, X, Y.
vdp_waddr:
        sta     VDP_CTRL
        pha
        tya
        and     #$3F
        ora     #$40
        sta     VDP_CTRL
        pla
        rts

; write A, vdp_n times.  Keeps A.
vdp_fill:
        ldx     vdp_n           ; the odd bytes first
        beq     @pg
@lo:    sta     VDP_DATA
        dex
        bne     @lo
@pg:    ldy     vdp_n+1         ; then whole pages
        beq     @done
@p:     ldx     #0
@pp:    sta     VDP_DATA
        dex
        bne     @pp
        dey
        bne     @p
@done:  rts

; copy vdp_n bytes from vdp_src to VRAM
vdp_copy:
        lda     vdp_src
        sta     @rd+1
        lda     vdp_src+1
        sta     @rd+2
        lda     vdp_n
        sta     vdp_t
        lda     vdp_n+1
        sta     vdp_t+1
@l:     lda     vdp_t
        ora     vdp_t+1
        beq     @done
@rd:    lda     $FFFF
        sta     VDP_DATA
        inc     @rd+1
        bne     :+
        inc     @rd+2
:       lda     vdp_t
        bne     :+
        dec     vdp_t+1
:       dec     vdp_t
        jmp     @l
@done:  rts

; A/Y -> 8 register values.  Clears VRAM.
vdp_setup:
        sta     @rr+1
        sty     @rr+2
        lda     VDP_CTRL        ; (resets the register write latch)
        lda     #$80            ; R1 = $80: display off while we work
        ldx     #1
        jsr     vdp_reg
        lda     #$1C            ; F18A unlock (a PICO9918): $1C twice to VR57
        ldx     #57
        jsr     vdp_reg
        jsr     vdp_reg
        lda     #0              ; VR49: 24 rows, no 80 columns, no layer 2
        ldx     #49
        jsr     vdp_reg
        ldx     #50             ; VR50: plain TMS9918A behaviour
        jsr     vdp_reg
        ldx     #19             ; VR19: no line interrupt
        jsr     vdp_reg
        ldx     #25             ; VR25-VR29: no scrolling, one page
@sc:    jsr     vdp_reg
        inx
        cpx     #30
        bne     @sc
        lda     #32             ; VR51: all 32 sprites
        ldx     #51
        jsr     vdp_reg
        ; (on a real TMS9918A those writes land in R0-R7: all set below)
        lda     #$80            ; R1 again: display off
        ldx     #1
        jsr     vdp_reg
        lda     #0              ; clear the 16K
        tay
        jsr     vdp_waddr
        lda     #$00
        sta     vdp_n
        lda     #$40
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        ldx     #0
@rr:    lda     $FFFF,x
        jsr     vdp_reg
        inx
        cpx     #8
        bne     @rr
        rts

; write address = name table cell X (column), Y (row).  Keeps X and Y.
vdp_at:
        stx     vdp_t
        tya
        lsr                     ; row * 32: high byte = row / 8
        lsr
        lsr
        sta     vdp_t+1
        tya
        asl
        asl
        asl
        asl
        asl                     ; low byte = (row & 7) * 32
        clc
        adc     vdp_t
        clc
        adc     #<VDP_NAME
        sta     VDP_CTRL
        lda     vdp_t+1
        adc     #>VDP_NAME
        and     #$3F
        ora     #$40
        sta     VDP_CTRL
        rts

; write the 0-ended string at A/Y.  Keeps X.
vdp_puts:
        sta     @rd+1
        sty     @rd+2
        ldy     #0
@rd:    lda     $FFFF,y
        beq     @done
        sta     VDP_DATA
        iny
        bne     @rd
@done:  rts

; A as two BCD digits.  Keeps X, Y.
vdp_bcd:
        pha
        lsr
        lsr
        lsr
        lsr
        ora     #'0'
        sta     VDP_DATA
        pla
        pha
        and     #$0F
        ora     #'0'
        sta     VDP_DATA
        pla
        rts

; wait for the next frame
vdp_frame:
@w:     jsr     frame_idle
        lda     VDP_CTRL
        bpl     @w
        rts

        .segment "BSS"
vdp_n:          .res 2
vdp_src:        .res 2
vdp_t:          .res 2
        .segment "CODE"
