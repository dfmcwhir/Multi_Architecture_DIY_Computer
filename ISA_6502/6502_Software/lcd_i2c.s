; ============================================================================
; lcd_i2c.s - HD44780 LCD (4-bit) behind an MCP23008 I2C port expander
;
; Ported from pcf8584_lcd_test.s.  Uses the bus layer in pcf8584.s.
;
;   mcp_write      A = MCP register, Y = value
;   lcd_init       full HD44780 power-up sequence (also sets lcd_ready)
;   lcd_cmd        send command byte in A
;   lcd_data       send character in A
;   lcd_clear      clear display (includes the 1.6 ms wait)
;   lcd_putbuf     send lcd_len characters from (strptr)
;   lcd_puts       send zero terminated string at (strptr)  (kept from the test)
;
; ERRORS: any failed I2C access sets i2c_err non-zero and is "latched": while
; i2c_err is set, mcp_write returns immediately, so a missing LCD costs one
; timeout instead of dozens.  The caller clears i2c_err before a command and
; looks at it afterwards (basic_i2c.s does that and raises "I2C Error").
; ============================================================================

; ---------------- user configuration ----------------------------------------
MCP_ADDR_W  = $40           ; DEFAULT address: 0x20 << 1, R/W = 0 (write).  LCDINIT addr overrides it.

; ---------------- MCP23008 ------------------------------------------------------
MCP_IODIR   = $00
MCP_GPIO    = $09

LCD_RS      = $80           ; GPIO7
LCD_E       = $40           ; GPIO6
LCD_BL      = $02           ; GPIO1

; ---------------- PCF8574 backpack (LCDINIT addr, 1) ----------------------------
LCP_RS      = $01           ; P0
LCP_E       = $04           ; P2   (P1 = RW, kept low)
LCP_BL      = $08           ; P3   P4-P7 = D4-D7

; ---------------- variables ---------------------------------------------------
.zeropage
; strptr (zero page, 2 bytes) is declared in ch376_abs.s

.segment "BIOSVARS"
i2c_err:    .res 1          ; non-zero if any I2C error occurred (latched)
lcd_rs:     .res 1          ; current RS bit ($00 or LCD_RS)
lcd_val:    .res 1          ; GPIO value being sent
mcp_reg:    .res 1          ; MCP register for mcp_write
mcp_data:   .res 1          ; MCP data for mcp_write
lcd_ready:  .res 1          ; non-zero once lcd_init has run
lcd_addr:   .res 1          ; I2C address byte (7 bit address << 1, R/W = 0) of the LCD
lcd_type:   .res 1          ; 0 = MCP23008 backpack, 1 = PCF8574 backpack
lcd_len:    .res 1          ; characters left for lcd_putbuf

.segment "BIOS"

; ============================================================================
; MCP23008 register write.  A = register, Y = value
; Sets i2c_err on failure.  Does nothing while i2c_err is already set.
; Clobbers A, X, Y.
; ============================================================================
mcp_write:
        ldx     i2c_err
        bne     @rts                ; earlier error: don't touch the bus
        sta     mcp_reg
        sty     mcp_data
        lda     lcd_addr            ; default MCP_ADDR_W, changed by LCDINIT addr
        sta     i2c_addr
        jsr     i2c_start
        bcs     @fail
        lda     mcp_reg
        jsr     i2c_send
        bcs     @fail
        lda     mcp_data
        jsr     i2c_send
        bcs     @fail
        jsr     i2c_stop
@rts:   rts
@fail:  jsr     i2c_stop
        lda     #$FF
        sta     i2c_err
        rts

; ============================================================================
; LCD (HD44780, 4-bit, via MCP23008)
; ============================================================================
lcd_init:
        lda     lcd_type
        bne     @pcf
        lda     #MCP_IODIR          ; all GPIO = outputs
        ldy     #$00
        jsr     mcp_write
        lda     #MCP_GPIO           ; backlight on, E=0, RS=0
        ldy     #LCD_BL
        jsr     mcp_write
        jmp     @common
@pcf:   lda     #LCP_BL             ; PCF8574 has no registers: backlight on, E=0
        jsr     lcp_write
@common:
        lda     #0
        sta     lcd_rs

        lda     #50                 ; >40 ms after power up
        jsr     delay_ms
        lda     #$03
        jsr     lcd_nibble
        lda     #5                  ; >4.1 ms
        jsr     delay_ms
        lda     #$03
        jsr     lcd_nibble
        lda     #1                  ; >100 us
        jsr     delay_ms
        lda     #$03
        jsr     lcd_nibble
        lda     #1
        jsr     delay_ms
        lda     #$02                ; switch to 4-bit mode
        jsr     lcd_nibble
        lda     #1
        jsr     delay_ms

        lda     #$28                ; function set: 4-bit, 2 lines, 5x8
        jsr     lcd_cmd
        lda     #$08                ; display off
        jsr     lcd_cmd
        jsr     lcd_clear           ; clear display (+ wait)
        lda     #$06                ; entry mode: increment, no shift
        jsr     lcd_cmd
        lda     #$0C                ; display on, cursor off, blink off
        jsr     lcd_cmd
        lda     #1
        sta     lcd_ready
        rts

; Clear display and wait for it to finish (needs ~1.6 ms)
lcd_clear:
        lda     #$01
        jsr     lcd_cmd
        lda     #3
        jmp     delay_ms

; Send command in A
lcd_cmd:
        ldy     #$00
        sty     lcd_rs
        jmp     lcd_byte

; Send data (character) in A
lcd_data:
        ldy     #LCD_RS
        sty     lcd_rs
        ; fall through

; Send full byte in A (RS already in lcd_rs), high nibble first
lcd_byte:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr     lcd_nibble
        pla
        ; fall through, lcd_nibble masks to low nibble

; Send low nibble of A to LCD D4-D7 with an E pulse
lcd_nibble:
        ldx     lcd_type
        bne     lcd_nibble_pcf
        and     #$0F
        tax
        lda     nibble_tab,x
        ora     #LCD_BL
        ora     lcd_rs
        sta     lcd_val

        lda     #MCP_GPIO           ; data + RS valid, E low
        ldy     lcd_val
        jsr     mcp_write

        lda     lcd_val             ; E high
        ora     #LCD_E
        tay
        lda     #MCP_GPIO
        jsr     mcp_write

        lda     #MCP_GPIO           ; E low (latches data)
        ldy     lcd_val
        jmp     mcp_write

; PCF8574 variant of lcd_nibble.  Pins: P0=RS P1=RW(0) P2=E P3=BL P4-P7=D4-D7
lcd_nibble_pcf:
        asl
        asl
        asl
        asl                         ; nibble -> P7..P4
        ora     #LCP_BL
        ldx     lcd_rs
        beq     @nors
        ora     #LCP_RS
@nors:  sta     lcd_val
        jsr     lcp_write           ; data + RS valid, E low
        lda     lcd_val
        ora     #LCP_E
        jsr     lcp_write           ; E high
        lda     lcd_val
        jmp     lcp_write           ; E low (latches data)

; PCF8574 write: A = port value (a single byte, no register).
lcp_write:
        ldx     i2c_err
        bne     @rts
        sta     mcp_data
        lda     lcd_addr
        sta     i2c_addr
        jsr     i2c_start
        bcs     @fail
        lda     mcp_data
        jsr     i2c_send
        bcs     @fail
        jmp     i2c_stop
@rts:   rts
@fail:  jsr     i2c_stop
        lda     #$FF
        sta     i2c_err
        rts

; Send lcd_len characters from (strptr).  Stops early on an I2C error.
lcd_putbuf:
@next:  lda     lcd_len
        beq     @done
        lda     i2c_err
        bne     @done
        ldy     #0
        lda     (strptr),y
        jsr     lcd_data
        inc     strptr
        bne     @nc
        inc     strptr+1
@nc:    dec     lcd_len
        jmp     @next
@done:  rts

; Print zero-terminated string at (strptr)
lcd_puts:
        ldy     #0
        lda     (strptr),y
        beq     @done
        jsr     lcd_data
        inc     strptr
        bne     lcd_puts
        inc     strptr+1
        jmp     lcd_puts
@done:  rts

; ============================================================================
; Data
; ============================================================================
; LCD nibble (D7..D4 = bits 3..0) -> MCP GPIO bits.
; Wiring assumed literally as stated: GPIO5=D4, GPIO4=D5, GPIO3=D6, GPIO2=D7.
; If your wiring is actually GPIO2=D4 ... GPIO5=D7, replace this table with
; $00,$04,$08,$0C,$10,$14,$18,$1C,$20,$24,$28,$2C,$30,$34,$38,$3C
nibble_tab:
        .byte   $00,$20,$10,$30,$08,$28,$18,$38
        .byte   $04,$24,$14,$34,$0C,$2C,$1C,$3C
