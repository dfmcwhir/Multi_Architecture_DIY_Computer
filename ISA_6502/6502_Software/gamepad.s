; ============================================================================
; gamepad.s - NES style gamepad on the 65C22 VIA, typed into the input buffer
;
; The pad is read 60 times a second from the VIA's timer 1 interrupt (IRQ2).
; Every new button press puts the character assigned to that button into the
; same input buffer the keyboard and serial port use, so BASIC (GET, INPUT)
; and the monitor see it as if it had been typed.  A held button repeats like
; a keyboard key.
;
; WIRING (VIA port A; change the three PAD_..._BIT masks below if you wire it
; differently).  The pad's +5V and GND go to the supply:
;       PA0  <-  DATA   (pad pin "Data", needs a pull-up resistor, 10k to +5V)
;       PA1  ->  LATCH
;       PA2  ->  CLOCK
; The other port A pins are left alone.
;
; BUTTON NUMBERS (the order the pad shifts them out):
;       0 = A        1 = B        2 = Select    3 = Start
;       4 = Up       5 = Down     6 = Left      7 = Right
;
; DEFAULT CHARACTERS:  Up W, Down S, Left A, Right D (upper case), A = space; B, Select and
; Start are not assigned (0).  Change them from BASIC with
;       PADKEY button, char        e.g.  PADKEY 1, 13    (B = Enter)
;                                        PADKEY 4, ASC("W")
;       PADKEY                     restore the defaults
; char 0 switches a button off.  Or edit pad_defaults below.
; ============================================================================

PAD_ENABLE       = 1                ; 0 = leave the VIA alone, no pad support
PAD_DATA_BIT     = $01              ; PA0
PAD_LATCH_BIT    = $02              ; PA1
PAD_CLOCK_BIT    = $04              ; PA2
PAD_HZ           = 60               ; polls per second
PAD_REPEAT_DELAY = 20               ; polls (1/60 s) before a held button repeats
PAD_REPEAT_RATE  = 6                ; polls between repeats (0 = no repeat)
PAD_T1           = (CPU_MHZ * 1000000) / PAD_HZ - 2
.assert PAD_T1 > 0 .and PAD_T1 < 65536, error, "CPU_MHZ too high for the 16 bit VIA timer at 60 Hz"

VIA_T1CL         = $7F04            ; timer 1 counter low  (reading clears its flag)
VIA_T1CH         = $7F05            ; timer 1 counter high (writing starts it)
VIA_T1LL         = $7F06            ; timer 1 latch low
VIA_ACR          = $7F0B            ; auxiliary control register

.segment "BIOSVARS"
pad_map:    .res 8                  ; character for each button (0 = none)
pad_prev:   .res 1                  ; buttons down at the previous poll
pad_now:    .res 1                  ; buttons down now (bit n = button n)
pad_last:   .res 1                  ; buttons that are auto-repeating
pad_cnt:    .res 1                  ; polls until the next repeat
pad_new:    .res 1
pad_tmp:    .res 1

.segment "BIOS"

; ----------------------------------------------------------------------------
; PAD_INIT - called from RESET after INIT_IO.  Clobbers A.
; ----------------------------------------------------------------------------
PAD_INIT:
        jsr     PAD_DEFAULTS
        lda     #0
        sta     pad_prev
        sta     pad_last
        sta     pad_cnt
        lda     #PAD_ENABLE         ; 0 = no gamepad support: leave the VIA alone
        beq     @off
        lda     PORTA               ; latch and clock idle low
        and     #($FF ^ (PAD_LATCH_BIT | PAD_CLOCK_BIT))
        sta     PORTA
        lda     DDRA                ; latch + clock are outputs, data an input
        ora     #(PAD_LATCH_BIT | PAD_CLOCK_BIT)
        and     #($FF ^ PAD_DATA_BIT)
        sta     DDRA
        lda     VIA_ACR             ; timer 1 free running, interrupt on timeout
        and     #$3F
        ora     #$40
        sta     VIA_ACR
        lda     #<PAD_T1
        sta     VIA_T1LL
        lda     #>PAD_T1
        sta     VIA_T1CH            ; loads the counter and starts it
        lda     #$C0                ; enable the timer 1 interrupt
        sta     IER
@off:   rts

; PAD_STATE - for the fixed jump table: A = buttons held right now
PAD_STATE:
        lda     pad_now
        rts

; Restore the default button characters
PAD_DEFAULTS:
        ldx     #7
@l:     lda     pad_defaults,x
        sta     pad_map,x
        dex
        bpl     @l
        rts

pad_defaults:
        .byte   ' '                 ; 0 A
        .byte   0                   ; 1 B
        .byte   0                   ; 2 Select
        .byte   0                   ; 3 Start
        .byte   'W'                 ; 4 Up
        .byte   'S'                 ; 5 Down
        .byte   'A'                 ; 6 Left
        .byte   'D'                 ; 7 Right

; ----------------------------------------------------------------------------
; PAD_POLL - read the pad and queue characters.  Called from the IRQ handler
; (registers are already saved there).
; ----------------------------------------------------------------------------
PAD_POLL:
        lda     PORTA               ; latch pulse: the pad's shift register
        ora     #PAD_LATCH_BIT      ; loads the 8 button states
        sta     PORTA
        jsr     pad_wait
        lda     PORTA
        and     #($FF ^ PAD_LATCH_BIT)
        sta     PORTA
        ldx     #8
@bit:   lda     PORTA               ; data line is LOW while a button is down
        and     #PAD_DATA_BIT
        cmp     #1                  ; carry = 1 when the line is high (not pressed)
        ror     pad_now             ; first button ends up in bit 0
        lda     PORTA
        ora     #PAD_CLOCK_BIT      ; clock pulse: shift to the next button
        sta     PORTA
        jsr     pad_wait
        lda     PORTA
        and     #($FF ^ PAD_CLOCK_BIT)
        sta     PORTA
        jsr     pad_wait
        dex
        bne     @bit
        lda     pad_now
        eor     #$FF                ; now bit = 1 when the button is down
        cmp     #$FF
        bne     @ok
        lda     #0                  ; all 8 down = nothing plugged in
@ok:    sta     pad_now

        lda     pad_prev            ; buttons newly pressed
        eor     #$FF
        and     pad_now
        sta     pad_new
        beq     @held
        sta     pad_last            ; they are the ones that repeat
        lda     #PAD_REPEAT_DELAY
        sta     pad_cnt
        lda     pad_new
        jsr     pad_emit
        jmp     @done
@held:  lda     pad_last
        beq     @done               ; nothing to repeat
        and     pad_now
        sta     pad_last            ; drop released buttons
        beq     @done
        lda     #PAD_REPEAT_RATE    ; 0 = no auto repeat
        beq     @norep
        dec     pad_cnt
        bne     @done
        lda     #PAD_REPEAT_RATE
        sta     pad_cnt
        lda     pad_last
        jsr     pad_emit
        jmp     @done
@norep: lda     #0
        sta     pad_last
@done:  lda     pad_now
        sta     pad_prev
        rts

; short delay for the pad's slow shift register (about 5 us at any clock)
pad_wait:
        ldy     #CPU_MHZ
@l:     dey
        bne     @l
        rts

; pad_emit - A = mask of buttons: queue the character of each one
pad_emit:
        sta     pad_tmp
        ldy     #0
@l:     lsr     pad_tmp
        bcc     @next
        lda     pad_map,y
        beq     @next               ; button not assigned
        pha
        lda     WRITE_PTR           ; keep clear of a full buffer
        sec
        sbc     READ_PTR
        cmp     #$F0
        bcs     @drop
        pla
        jsr     WRITE_BUFFER        ; (uses X, not Y)
        jmp     @next
@drop:  pla
@next:  iny
        cpy     #8
        bne     @l
        rts

; ----------------------------------------------------------------------------
; PADKEY button, char   (BASIC statement)      PADKEY alone = defaults
; ----------------------------------------------------------------------------
BI_PADKEY:
        jsr     LAB_GBYT
        bne     @set
        jmp     PAD_DEFAULTS
@set:   jsr     LAB_GTBY            ; X = button 0-7
        cpx     #8
        bcs     @fc
        txa
        pha
        jsr     LAB_1C01            ; ","
        jsr     LAB_GTBY            ; X = character code 0-255
        pla
        tay
        txa
        sta     pad_map,y
        rts
@fc:    jmp     LAB_FCER
