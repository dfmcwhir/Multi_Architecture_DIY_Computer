; ============================================================================
; bios.s - hardware layer for the custom 6502 SBC, EhBASIC build
;
; Based on the msbasic bios.s.  What changed:
;   * CHRIN no longer echoes.  EhBASIC echoes what it reads, and wozmon.s
;     echoes for itself, so echoing here would double every character.
;   * RESET now does all hardware init, copies EhBASIC's I/O vectors into
;     RAM, and shows a boot menu: [C]old start, [W]arm start, [M]onitor.
;   * Variables are real linker segments (no more .org tricks).
;   * Unused IRQ lines can flag EhBASIC's "ON IRQ" (see IRQ_BASIC below).
;   * NMI goes through EhBASIC's RAM NMI handler (NMI_vec) so "ON NMI" works.
;
; This file must be included AFTER basic.s (it uses basic.s's zero page
; symbols IrqBase/NmiBase and RAM symbols VEC_IN/NMI_vec).
; ============================================================================

; ----------------------------------------------------------------------------
; Zero page (placed by sbc.cfg in the free area $E2-$EE of EhBASIC's zero page)
; ----------------------------------------------------------------------------
.zeropage
READ_PTR:       .res 1
WRITE_PTR:      .res 1
TEMP_IRQ_ADDR:  .res 2

; ----------------------------------------------------------------------------
; RAM variables (sbc.cfg: BIOSVARS at $0380)
; ----------------------------------------------------------------------------
.segment "BIOSVARS"
LAST_CHAR:      .res 1
DEVSTAT:        .res 1
UI_DATA_OFF:    .res 1
UI_STATUS_OFF:  .res 1
UI_CMD_OFF:     .res 1
UI_CTRL_OFF:    .res 1

; ----------------------------------------------------------------------------
; Serial / keyboard receive buffer, 256 bytes (sbc.cfg: INPUT_BUFFER at $0400)
; ----------------------------------------------------------------------------
.segment "INPUT_BUFFER"
INPUT_BUFFER:   .res $100


.segment "BIOS"

;IO address offsets from IO_BASE
IO_BASE         = $7f00
ACIA_DATA_OFF:      .byte $14
ACIA_STATUS_OFF:    .byte $15
ACIA_CMD_OFF:       .byte $16
ACIA_CTRL_OFF:      .byte $17
KEYBDISP_DATA_OFF:  .byte $18
KEYBDISP_STATUS_OFF:    .byte $19
KEYBDISP_CMD_OFF:   .byte $1a
KEYBDISP_CTRL_OFF:  .byte $1b
PORTB_OFF:          .byte $00
PORTA_OFF:          .byte $01
DDRB_OFF:           .byte $02
DDRA_OFF:           .byte $03
IFR_OFF:            .byte $0d
IER_OFF:            .byte $0e
IRQPORT_OFF:        .byte $ff

;ACIA_DATA       = $7f14
;ACIA_STATUS     = $7f15
;ACIA_CMD        = $7f16
;ACIA_CTRL       = $7f17
;KEYBDISP_DATA   = $7f18
;KEYBDISP_STATUS = $7f19
;KEYBDISP_CMD    = $7f1a
;KEYBDISP_CTRL   = $7f1b
PORTB           = $7f00
PORTA           = $7f01
DDRB            = $7f02
DDRA            = $7f03
IFR             = $7f0d
IER             = $7f0e
IRQPORT         = $7fff


; ============================================================================
; RESET - entry point from the reset vector
; ============================================================================
RESET:
        cld
        sei
        ldx     #$ff
        txs                     ; empty the stack
        lda     #0
        sta     DEVSTAT         ; clear device status flags
        jsr     CH_BOOT         ; CH376 is initialised lazily on first LOAD/SAVE
		jsr     I2C_BOOT        ; PCF8584 and LCD are initialised on first use
        jsr     AY_BOOT         ; the sound card quiet (basic_ay.s)
        jsr     INIT_BUFFER
        jsr     INIT_IO
        jsr     PAD_INIT        ; gamepad on VIA port A (gamepad.s)
        jsr     INIT_SERIAL
        jsr     INIT_DISPLAY
        jsr     SET_UI_DEVICE   ; if init display initialised a device, output goes
                                ; there, otherwise to the serial port
        jsr     COPY_VECTORS    ; EhBASIC I/O vectors + NMI code into RAM
                                ; (falls into MENU)

; ----------------------------------------------------------------------------
; MENU - boot menu.  Also reachable with CTRL-C from the monitor.
; ----------------------------------------------------------------------------
MENU:
        cld
        ldx     #$ff
        txs
        cli
        ldy     #0
@print: lda     MENU_MSG,y
        beq     @wait
        jsr     CHROUT
        iny
        bne     @print
@wait:  jsr     CHRIN
        bcc     @wait
        and     #$DF            ; force upper case
        cmp     #'C'
        beq     @cold
        cmp     #'W'
        beq     @warm
        cmp     #'M'
        beq     @mon
        bne     @wait           ; anything else: keep waiting
@cold:  jmp     LAB_COLD        ; EhBASIC cold start
@warm:  jmp     LAB_WARM        ; EhBASIC warm start (program in RAM is kept)
@mon:   jmp     WOZ_ENTRY       ; wozmon

MENU_MSG:
        .byte   $0D,$0A,"6502 SBC - EhBASIC 2.22",$0D,$0A
        .byte   "[C]old start, [W]arm start, [M]onitor? ",$00


; ----------------------------------------------------------------------------
; COPY_VECTORS - copy VEC_BLOCK to RAM, starting at VEC_IN:
;   VEC_IN, VEC_OUT, VEC_LD, VEC_SV   EhBASIC's I/O vectors
;   IRQ_vec: 10 bytes                 EhBASIC's RAM IRQ code (not used here: the
;                                     real IRQ vector points at "irq" below)
;   NMI_vec: 10 bytes                 EhBASIC's RAM NMI code (NMI vector -> here)
; modifies A, Y, flags
; ----------------------------------------------------------------------------
COPY_VECTORS:
        ldy     #VEC_BLOCK_END-VEC_BLOCK
@loop:  lda     VEC_BLOCK-1,y
        sta     VEC_IN-1,y
        dey
        bne     @loop
        rts

VEC_BLOCK:
        .word   CHRIN           ; VEC_IN  - byte in from keyboard/serial
        .word   CHROUT          ; VEC_OUT - byte out to screen/serial
        .word   CH_LOAD         ; VEC_LD  - LOAD (ch376_loadsave.s)
        .word   CH_SAVE         ; VEC_SV  - SAVE (ch376_loadsave.s)
IRQ_CODE:                       ; EhBASIC IRQ support (10 bytes, copied to IRQ_vec)
        pha
        lda     IrqBase         ; get the IRQ flag byte
        lsr                     ; shift the set b7 to b6, and on down ...
        ora     IrqBase         ; OR the original back in
        sta     IrqBase         ; save the new IRQ flag byte
        pla
        rti
NMI_CODE:                       ; EhBASIC NMI support (10 bytes, copied to NMI_vec)
        pha
        lda     NmiBase         ; get the NMI flag byte
        lsr                     ; shift the set b7 to b6, and on down ...
        ora     NmiBase         ; OR the original back in
        sta     NmiBase         ; save the new NMI flag byte
        pla
        rti
VEC_BLOCK_END:


; Initialize the IO port
; modifies A, Y, flags
INIT_IO:
        ldy     IER_OFF
        lda     #$7f
        sta     IO_BASE,Y
        eor     IO_BASE,Y       ;check if IER was set to value as a check to see if device is present
        bne     IO_INIT_DONE    ;device not present
        lda     #1
        ora     DEVSTAT
        sta     DEVSTAT         ; set bit 0 of device status indicator
        ldy     IFR_OFF
        lda     #$80
        sta     IO_BASE,Y
        ldy     DDRB_OFF
        lda     #$ff
        sta     IO_BASE,Y
        lda     #$1
        ldy     PORTB_OFF
        sta     IO_BASE,y
IO_INIT_DONE:
        rts


;Initializes the serial port
; modifies A, Y, flags
INIT_SERIAL:
        ldy     ACIA_STATUS_OFF
        lda     #$00
        sta     IO_BASE,Y
        ldy     ACIA_CTRL_OFF
        lda     #$1a            ; N-8-1 2400 BAUD
        sta     IO_BASE,Y
        eor     IO_BASE,Y       ;check if serial control register was set to value as a check to see if device is present
        bne     SERIAL_INIT_DONE ;device not present
        lda     #2
        ora     DEVSTAT
        sta     DEVSTAT         ; set bit 1 of device status indicator
        ldy     ACIA_CMD_OFF
        lda     #$89            ; no parity, no echo, interrupts
        sta     IO_BASE,Y

SERIAL_INIT_DONE:
        lda     DEVSTAT
        ldy     PORTB_OFF
        sta     IO_BASE,y
        rts

;Initializes the KB_MONITOR_TERMINAL Card
; modifies A, Y, flags
INIT_DISPLAY:
        ldy     KEYBDISP_STATUS_OFF
        lda     #$00
        sta     IO_BASE,Y
        ldy     KEYBDISP_CTRL_OFF
        lda     #$10            ; N-8-1 115.2K BAUD
        sta     IO_BASE,Y
        eor     IO_BASE,Y       ;check if kb display control register was set to value as a check to see if device is present
        bne     KEYBDISP_INIT_DONE ;device not present
        lda     #4
        ora     DEVSTAT
        sta     DEVSTAT         ; set bit 2 of device status indicator
        ldy     KEYBDISP_CMD_OFF
        lda     #$89            ; no parity, no echo, interrupts
        sta     IO_BASE,Y

KEYBDISP_INIT_DONE:
        lda     DEVSTAT
        ldy     PORTB_OFF
        sta     IO_BASE,y
        rts

; modifies A,X,Y flags
SET_UI_DEVICE:

        lda     #4
        and     DEVSTAT
        beq     SET_SERIAL_UI
        lda     KEYBDISP_CMD_OFF
        sta     UI_CMD_OFF
        lda     KEYBDISP_CTRL_OFF
        sta     UI_CTRL_OFF
        lda     KEYBDISP_DATA_OFF
        sta     UI_DATA_OFF
        lda     KEYBDISP_STATUS_OFF
        sta     UI_STATUS_OFF
        rts
SET_SERIAL_UI:
        lda     ACIA_CMD_OFF
        sta     UI_CMD_OFF
        lda     ACIA_CTRL_OFF
        sta     UI_CTRL_OFF
        lda     ACIA_DATA_OFF
        sta     UI_DATA_OFF
        lda     ACIA_STATUS_OFF
        sta     UI_STATUS_OFF
        rts


; ============================================================================
; CHRIN - input a character (non-blocking, NO echo).
;   Used as EhBASIC's input vector (VEC_IN) and by the monitor.
;   On return the carry flag indicates whether a key was available.
;   If carry is set the key is in A (and Z reflects it, which EhBASIC relies on).
;   If carry is clear A = 0.
;   Preserves X and Y.
;
; Modifies: flags, A
; ============================================================================
MONRDKEY:
CHRIN:
        txa                     ; save X
        pha

        jsr     BUFFER_SIZE
        beq     @no_keypressed

        jsr     READ_BUFFER     ; returns character in A (and LAST_CHAR)

        pla                     ; restore X
        tax

        lda     LAST_CHAR       ; the character (sets Z/N for the caller)
        sec                     ; success
        rts

@no_keypressed:
        pla
        tax
        lda     #0
        clc                     ; no character
        rts


; ============================================================================
; CHROUT - output a character (from the A register) to the UI interface.
;   Used as EhBASIC's output vector (VEC_OUT) and by the monitor.
;   Preserves A, X and Y.
;
; Modifies: flags
; ============================================================================
MONCOUT:
CHROUT:
        sta     LAST_CHAR
        pha
        tya
        pha
        ldy     UI_DATA_OFF
        lda     LAST_CHAR
        sta     IO_BASE,Y
tx_wait:
        ldy     UI_STATUS_OFF
        lda     IO_BASE,Y
        and     #$10
        beq     tx_wait
        pla
        tay
        pla
        rts

; Initialize the circular input buffer
; Modifies: flags, A
INIT_BUFFER:
        lda     #0
        sta     READ_PTR
        sta     WRITE_PTR
        rts

; Write a character (from the A register) to the circular input buffer
; Modifies: flags, X
WRITE_BUFFER:
        ldx     WRITE_PTR
        sta     INPUT_BUFFER,x
        inc     WRITE_PTR
        rts

; Read a character from the circular input buffer and put it in the A register
; Modifies: flags, A, X
READ_BUFFER:
        ldx     READ_PTR
        lda     INPUT_BUFFER,x
        sta     LAST_CHAR
        inc     READ_PTR
        rts

; Return (in A) the number of unread bytes in the circular input buffer
; Modifies: flags, A
BUFFER_SIZE:
        lda     WRITE_PTR
        sec
        sbc     READ_PTR
        rts


; ============================================================================
; Interrupts
; ============================================================================
irq: ; reads the IRQ priority register and jmps to the appropriate interrupt routine
        sei
        PHA
        TXA
        PHA
        TYA
        PHA
        LDX     IRQPORT
        LDA     IRQTABLE,X
        STA     TEMP_IRQ_ADDR
        INX
        LDA     IRQTABLE,X
        STA     TEMP_IRQ_ADDR+1
        JMP     (TEMP_IRQ_ADDR)



IRQTABLE:   ; Order of the IRQ subroutines is reversed in the IRQ table due to a schematic error (?). The physical IRQ0 line reads 14
            ;on the IRQ port which is 2x7 and correct. It may not be an actual wiring defect, but a feature becuase it makes it so
            ; IRQ0 has the highest priority and IRQ7 has the lowest. either way, this IRQ table should work.
        .word IRQ7
        .word IRQ6
        .word IRQ5
        .word IRQ4
        .word IRQ3
        .word IRQ2
        .word IRQ1
        .word IRQ0

; Lines the BIOS does not use itself:
;   IRQ0, IRQ1 not used   IRQ2 IO Card VIA   IRQ4 IO Card I2C   IRQ6, IRQ7 spare
; They all share this code, which feeds EhBASIC's "ON IRQ" feature: if the BASIC
; program has enabled IRQ handling, the "interrupt happened" flag gets set and
; the BASIC handler routine runs at the end of the current statement.  (That
; handler must clear the interrupt source itself.)  If BASIC has not enabled
; IRQ handling, IrqBase is 0 and this does nothing, exactly like a plain RTI.
IRQ0:
IRQ1:
IRQ4:
IRQ6:
IRQ7:
IRQ_BASIC:
        lda     IrqBase
        lsr
        ora     IrqBase
        sta     IrqBase
IRQ_EXIT:
        PLA
        TAY
        PLA
        TAX
        PLA
        cli
        rti

IRQ2:      ; IO card VIA: timer 1 = gamepad poll (gamepad.s); anything else is
           ; passed on to BASIC's ON IRQ like the unused lines
        lda     IFR
        and     #$40                ; timer 1 timeout?
        beq     @other
        lda     VIA_T1CL            ; reading the low counter clears the flag
        jsr     PAD_POLL
        jsr     SND_TICK            ; timed notes (basic_ay.s)
@other: lda     IFR
        and     IER
        and     #$3F                ; another enabled VIA source?
        beq     @done
        jmp     IRQ_BASIC
@done:  jmp     IRQ_EXIT

IRQ3:      ;SERIAL in interrupt
        ldy     ACIA_STATUS_OFF
        lda     IO_BASE,Y
        ldy     ACIA_DATA_OFF
        lda     IO_BASE,Y
        jsr     WRITE_BUFFER
        jmp     IRQ_EXIT

IRQ5:   ; Keyboard/Display Card
        ldy     KEYBDISP_STATUS_OFF
        lda     IO_BASE,Y
        ldy     KEYBDISP_DATA_OFF
        lda     IO_BASE,Y
        jsr     WRITE_BUFFER
        jmp     IRQ_EXIT


; ============================================================================
; Vectors  (segment RESETVEC is placed at $FFFA by sbc.cfg)
; ============================================================================
.segment "RESETVEC"
        .word   NMI_vec         ; NMI vector   -> EhBASIC's RAM NMI handler
        .word   RESET_CWD       ; RESET vector (jumptable.s: clears mon_cwd, then RESET)
        .word   irq             ; IRQ vector
