; ============================================================================
; bios.s - reset, boot menu and vectors for the 6502 CPU Rev2 ROM
;
; The hardware is now handled by one driver file per card (drv_*.s), the
; console by console.s and interrupts by irq.s; config.inc says which cards
; the ROM is built for.  This file only starts everything up.
;
; Must be included AFTER basic.s (it uses LAB_COLD, LAB_WARM, VEC_IN,
; NMI_vec, IrqBase and NmiBase).
; ============================================================================

.segment "BIOSVARS"
DEVSTAT:        .res 1                  ; device status, shown on VIA port B:
                                        ; bit 0 VIA  1 serial 6551  2 display
                                        ; bit 3 AVR keyboard interface

API_VERSION     = 2                     ; SBC_SYSINFO returns it in Y

.segment "BIOS"

; ============================================================================
; RESET - from the reset vector (through RESET_CWD)
; ============================================================================
RESET:
        sei
        cld
        ldx     #$FF
        txs
        ; Clear all BIOS / driver RAM, so nothing depends on what the RAM
        ; happened to hold at power-up (a short power cycle keeps the old
        ; contents, a long one doesn't).  Not cleared: EhBASIC's zero page and
        ; page 3 (for the warm start) and the program area.  Addresses as in
        ; sbc.cfg: ZP $E2-$EE, $0200-$02FF (wozmon buffer, CHVARS),
        ; $0380-$03FF (BIOSVARS), $0400-$07FF (console buffer, DRVVARS).
        lda     #0
        ldx     #$0C
@z:     sta     $E2,x
        dex
        bpl     @z
        tax                             ; X = 0
@p:     sta     $0200,x
        sta     $0400,x
        sta     $0500,x
        sta     $0600,x
        sta     $0700,x
        inx
        bne     @p
        ldx     #$7F
@b:     sta     $0380,x
        dex
        bpl     @b
        jsr     BANK_INIT               ; bank 0 selected, banks counted
        lda     #0
        sta     DEVSTAT
        jsr     INIT_BUFFER
        jsr     CH_BOOT                 ; CH376: set up lazily on first use
        jsr     I2C_BOOT                ; PCF8584 and LCD: set up on first use
        jsr     SND_BOOT                ; sound quiet
.if HAS_SPO
        jsr     spo_init                ; speech chip
.endif
.if HAS_VIA
        jsr     VIA_INIT                ; port B LEDs, 60 Hz tick
.endif
.if HAS_GAMEPAD
        jsr     PAD_INIT                ; gamepad on VIA port A
.endif
.if HAS_SPI
        jsr     spi_init                ; 65SPI (the CF card is mounted on first use)
.endif
.if HAS_ACIA
        jsr     acia_init               ; serial card 6551
.endif
.if HAS_AVRKBD
        jsr     avrkbd_init             ; keyboard / mouse / serial console
.endif
        jsr     CON_INIT                ; display, and where output goes
.if HAS_VIA
        bit     via_ok
        bpl     :+
        lda     DEVSTAT
        sta     PORTB                   ; show what answered on the LEDs
:
.endif
        jsr     COPY_VECTORS            ; EhBASIC I/O vectors + NMI code into RAM
                                        ; (falls into MENU)

; ----------------------------------------------------------------------------
; MENU - boot menu.  Also reachable with CTRL-C from the monitor.
; ----------------------------------------------------------------------------
MENU:
        cld
        ldx     #$FF
        txs
        cli
        lda     #<MENU_MSG
        ldy     #>MENU_MSG
        jsr     bios_puts
        lda     bank_count              ; "nn" banks (1-16)
        cmp     #10
        bcc     @one
        pha
        lda     #'1'
        jsr     CHROUT
        pla
        sec
        sbc     #10
@one:   ora     #'0'
        jsr     CHROUT
        lda     #<MENU_MSG2
        ldy     #>MENU_MSG2
        jsr     bios_puts
        jsr     sh_find                 ; a shell in a RAM bank? (shell.s)
        bcs     @ns
        lda     #<MENU_MSG3
        ldy     #>MENU_MSG3
        jsr     bios_puts
@ns:    lda     #'?'
        jsr     CHROUT
        lda     #' '
        jsr     CHROUT
@wait:  jsr     CHRIN
        bcc     @wait
        and     #$DF                    ; force upper case
        cmp     #'G'
        bne     @ng
        jsr     sh_find
        bcs     @wait
        sta     sh_bank
        jmp     sh_enter                ; back to the file manager
@ng:    cmp     #'C'
        beq     @cold
        cmp     #'W'
        beq     @warm
        cmp     #'M'
        beq     @mon
        bne     @wait                   ; anything else: keep waiting
@cold:  jmp     LAB_COLD                ; EhBASIC cold start
@warm:  jmp     LAB_WARM                ; EhBASIC warm start (program in RAM is kept)
@mon:   jmp     WOZ_ENTRY               ; wozmon

MENU_MSG:
        .byte   $0D,$0A,"6502 SBC CPU Rev2 - EhBASIC 2.22",$0D,$0A
        .byte   "RAM banks: ",$00
MENU_MSG2:
        .byte   $0D,$0A,"[C]old start, [W]arm start, [M]onitor",$00
MENU_MSG3:
        .byte   ", [G]o to the file manager",$00

; bios_puts - print the 0-ended string at A (low) / Y (high): mon_puts
bios_puts       = mon_puts

; ----------------------------------------------------------------------------
; COPY_VECTORS - copy VEC_BLOCK to RAM, starting at VEC_IN:
;   VEC_IN, VEC_OUT, VEC_LD, VEC_SV   EhBASIC's I/O vectors
;   IRQ_vec: 10 bytes                 EhBASIC's RAM IRQ code (not used: the
;                                     real IRQ vector goes to irq.s)
;   NMI_vec: 10 bytes                 EhBASIC's RAM NMI code (NMI vector -> here)
; Modifies A, Y, flags.
; ----------------------------------------------------------------------------
COPY_VECTORS:
        ldy     #VEC_BLOCK_END-VEC_BLOCK
@loop:  lda     VEC_BLOCK-1,y
        sta     VEC_IN-1,y
        dey
        bne     @loop
        rts

VEC_BLOCK:
        .word   CHRIN                   ; VEC_IN  - byte in from keyboard/serial
        .word   CHROUT                  ; VEC_OUT - byte out to screen/serial
        .word   CH_LOAD                 ; VEC_LD  - LOAD (ch376_loadsave.s)
        .word   CH_SAVE                 ; VEC_SV  - SAVE (ch376_loadsave.s)
IRQ_CODE:                               ; EhBASIC IRQ support (10 bytes)
        pha
        lda     IrqBase
        lsr     a
        ora     IrqBase
        sta     IrqBase
        pla
        rti
NMI_CODE:                               ; EhBASIC NMI support (10 bytes)
        pha
        lda     NmiBase
        lsr     a
        ora     NmiBase
        sta     NmiBase
        pla
        rti
VEC_BLOCK_END:

; ----------------------------------------------------------------------------
; RESET_CWD - the reset vector comes here: start in the top folder ("" in
; mon_cwd, which is random at power-up), then RESET.
; ----------------------------------------------------------------------------
RESET_CWD:
        lda     #0
        sta     mon_cwd
        jmp     RESET

; sbc_cwd - A/Y = the monitor's current folder (jump table SBC_CWD)
sbc_cwd:
        lda     #<mon_cwd
        ldy     #>mon_cwd
        rts

; ----------------------------------------------------------------------------
; SYSINFO - A = display type (config.inc DISP_...), X = DEVSTAT,
;           Y = API version (jump table SBC_SYSINFO)
; ----------------------------------------------------------------------------
SYSINFO:
        lda     #CON_DISPLAY
        ldx     DEVSTAT
        ldy     #API_VERSION
        rts

; ============================================================================
; Vectors  (segment RESETVEC is placed at $FFFA by sbc.cfg)
; ============================================================================
.segment "RESETVEC"
        .word   NMI_vec                 ; NMI   -> EhBASIC's RAM NMI handler
        .word   RESET_CWD               ; RESET
        .word   IRQ_ENTRY               ; IRQ   (irq.s)
