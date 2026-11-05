; ============================================================================
; basic_i2c.s - EhBASIC statements and function for the PCF8584 I2C bridge and
;               the I2C LCD.  Glue between basic.s and pcf8584.s / lcd_i2c.s.
;
; NEW BASIC KEYWORDS (tokens are defined in basic.s, tokenized by EhBASIC):
;
;   I2CINIT                     initialise the PCF8584 (optional: done on first use)
;   I2CWRITE addr, b1 [,b2...]  write bytes to the device at 7-bit address "addr"
;                               (0-127, i.e. the datasheet address, NOT shifted).
;                               Up to 32 data bytes; none is allowed (address probe).
;                               A device that doesn't ACK gives "I2C Error".
;   x = I2CREAD(addr)           read ONE byte from 7-bit address "addr" (0-255).
;                               Returns -1 if the device doesn't answer, so it can
;                               be used to scan the bus without raising an error.
;
;   LCDINIT [addr]              (re)initialise the LCD (optional: done on first use).
;                               With addr (0-127) the LCD at that 7-bit I2C address is
;                               used from now on; plain LCDINIT goes back to the default
;                               address (MCP_ADDR_W in lcd_i2c.s, 0x20).
;   LCDPRINT s$                 write a string at the cursor
;   LCDPOS col, row             move the cursor (col 0-39, row 0-3)
;   LCDCLS                      clear the display
;   LCDCMD n                    send raw HD44780 command byte n (e.g. LCDCMD 12 =
;                               display on, cursor off; LCDCMD 15 = blinking cursor)
;
; Both the PCF8584 and the LCD are initialised automatically the first time they
; are needed.  Arguments are fully evaluated BEFORE the bus is touched, so a
; syntax error in a line never leaves the bus in the middle of a transfer.
; ============================================================================

I2C_BUF_MAX = 32                    ; most data bytes in one I2CWRITE
EH_ERR_I2C  = $24                   ; error code: "I2C Error" (see LAB_BAER in basic.s)

.segment "BIOSVARS"
i2c_n:      .res 1                  ; data bytes collected for I2CWRITE
i2c_idx:    .res 1                  ; index while sending them
i2c_buf:    .res I2C_BUF_MAX        ; the data bytes
lcd_tmp:    .res 1                  ; argument scratch (LCDCMD / LCDPOS)
lcd_row:    .res 1

.segment "BIOS"

; ----------------------------------------------------------------------------
; I2C_BOOT - called from RESET: nothing is initialised yet
; ----------------------------------------------------------------------------
I2C_BOOT:
        lda     #0
        sta     pcf_ready
        sta     lcd_ready
        sta     i2c_err
        lda     #MCP_ADDR_W
        sta     lcd_addr            ; default LCD address
        lda     #0
        sta     lcd_type            ; MCP23008
        rts

; ----------------------------------------------------------------------------
; common helpers
; ----------------------------------------------------------------------------
BI_ERR:                             ; raise "I2C Error" (never returns)
        ldx     #EH_ERR_I2C
        jmp     LAB_XERR

BI_FC:                              ; raise "Function call Error" (never returns)
        jmp     LAB_FCER

BI_CHK:                             ; error if the last operation failed
        lda     i2c_err
        bne     BI_ERR
        rts

pcf_ensure:                         ; make sure the PCF8584 is initialised
        lda     pcf_ready
        bne     @ok
        jsr     pcf_init
        bcs     BI_ERR
        lda     #1
        sta     pcf_ready
@ok:    rts

lcd_ensure:                         ; make sure PCF8584 and LCD are initialised
        jsr     pcf_ensure
        lda     lcd_ready
        bne     @ok
        lda     #0
        sta     i2c_err
        jsr     lcd_init
        lda     i2c_err
        beq     @ok
        lda     #0
        sta     lcd_ready           ; failed: try the whole thing again next time
        beq     BI_ERR              ; (always)
@ok:    lda     #0
        sta     i2c_err             ; start the caller's operation with no error
        rts

; ----------------------------------------------------------------------------
; I2CINIT
; ----------------------------------------------------------------------------
BI_I2CINIT:
        lda     #0
        sta     pcf_ready
        jmp     pcf_ensure

; ----------------------------------------------------------------------------
; I2CWRITE addr, b1 [, b2 ...]
; ----------------------------------------------------------------------------
BI_I2CWRITE:
        jsr     LAB_GTBY            ; X = 7 bit address
        cpx     #$80
        bcs     BI_FC
        txa
        asl
        sta     i2c_addr            ; address byte, R/W = 0
        lda     #0
        sta     i2c_n
@more:  jsr     LAB_GBYT            ; next character
        cmp     #','
        bne     @send
        jsr     LAB_1C01            ; step over ","
        jsr     LAB_GTBY            ; X = data byte
        ldy     i2c_n
        cpy     #I2C_BUF_MAX
        bcs     BI_FC               ; too many bytes
        txa
        sta     i2c_buf,y
        inc     i2c_n
        jmp     @more
@send:  jsr     pcf_ensure
        jsr     i2c_start
        bcs     @fail
        lda     #0
        sta     i2c_idx
@loop:  lda     i2c_idx
        cmp     i2c_n
        beq     @done
        tax
        lda     i2c_buf,x
        jsr     i2c_send
        bcs     @fail
        inc     i2c_idx
        jmp     @loop
@done:  jsr     i2c_stop
        rts
@fail:  jsr     i2c_stop
        jmp     BI_ERR

; ----------------------------------------------------------------------------
; I2CREAD(addr) - function, FAC1 = address on entry (numeric pre-processing is
; done by the interpreter, see LAB_FTPL); result in FAC1
; ----------------------------------------------------------------------------
BI_I2CRD:
        jsr     LAB_F2FX            ; integer part of FAC1 -> Itempl/Itemph
        lda     Itemph
        bne     @fc
        lda     Itempl
        cmp     #$80
        bcs     @fc
        asl
        ora     #1                  ; address byte, R/W = 1
        sta     i2c_addr
        jsr     pcf_ensure
        jsr     i2c_read1
        bcs     @none
        tay                         ; byte -> Y
        jmp     LAB_1FD0            ; convert Y to a number in FAC1 and return
@none:  lda     #$FF
        jmp     LAB_27DB            ; save A as signed integer byte: -1
@fc:    jmp     LAB_FCER

; ----------------------------------------------------------------------------
; LCDINIT
; ----------------------------------------------------------------------------
BI_LCDINIT:
        lda     #0
        sta     lcd_type            ; default: MCP23008
        jsr     LAB_GBYT            ; anything after the keyword?
        beq     @default            ; no: use the default address
        jsr     LAB_GTBY            ; X = 7 bit I2C address
        cpx     #$80
        bcs     @fc
        txa
        asl
        pha                         ; keep the address byte
        jsr     LAB_GBYT            ; optional ", type"
        beq     @notype
        jsr     LAB_1C01            ; scan for ","
        jsr     LAB_GTBY            ; X = 0 (MCP23008) or 1 (PCF8574)
        cpx     #2
        bcs     @fc2
        stx     lcd_type
@notype:
        pla
        jmp     @set
@default:
        lda     #MCP_ADDR_W
@set:   sta     lcd_addr
        lda     #0
        sta     lcd_ready
        jmp     lcd_ensure
@fc2:   pla
@fc:    jmp     LAB_FCER

; ----------------------------------------------------------------------------
; LCDPRINT s$
; ----------------------------------------------------------------------------
BI_LCDPRINT:
        jsr     LAB_EVEX            ; evaluate expression at the BASIC pointer
        jsr     LAB_EVST            ; must be a string (else ?Type mismatch);
                                    ; A = length, (ut1_pl) -> characters
        sta     lcd_len
        lda     ut1_pl
        sta     strptr
        lda     ut1_ph
        sta     strptr+1
        jsr     lcd_ensure
        jsr     lcd_putbuf
        jmp     BI_CHK

; ----------------------------------------------------------------------------
; LCDPOS col, row
; ----------------------------------------------------------------------------
BI_LCDPOS:
        jsr     LAB_GTBY            ; X = column
        cpx     #40
        bcs     @fc
        stx     lcd_tmp
        jsr     LAB_1C01            ; scan for ","
        jsr     LAB_GTBY            ; X = row
        cpx     #4
        bcs     @fc
        lda     row_tab,x
        clc
        adc     lcd_tmp
        ora     #$80                ; "set DDRAM address" command
        sta     lcd_tmp
        jsr     lcd_ensure
        lda     lcd_tmp
        jsr     lcd_cmd
        jmp     BI_CHK
@fc:    jmp     LAB_FCER

row_tab:
        .byte   $00,$40,$14,$54     ; DDRAM start of rows 0-3 (16x2 uses the first two)

; ----------------------------------------------------------------------------
; LCDCLS
; ----------------------------------------------------------------------------
BI_LCDCLS:
        jsr     lcd_ensure
        jsr     lcd_clear
        jmp     BI_CHK

; ----------------------------------------------------------------------------
; LCDCMD n
; ----------------------------------------------------------------------------
BI_LCDCMD:
        jsr     LAB_GTBY            ; X = command byte
        stx     lcd_tmp
        jsr     lcd_ensure
        lda     lcd_tmp
        jsr     lcd_cmd
        lda     lcd_tmp
        cmp     #4                  ; clear / home need ~1.6 ms
        bcs     @nodly
        lda     #3
        jsr     delay_ms
@nodly: jmp     BI_CHK
