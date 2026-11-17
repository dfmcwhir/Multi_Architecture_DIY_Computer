; ============================================================================
; cpu_rev2.s - CPU card Rev2 registers: RAM bank register and bank count
;
;   $7FFE write: bank register, D3-D0 -> bus A16-A19 (cleared by /RESET)
;   $7FFE read : bank register on D3-D0 (D7-D4 not driven: AND #$0F)
;   $7FFF read : interrupt register (irq.s)
;
; Banked window: $1000-$7EFF.  Physical address = bank x 32K + CPU address.
; AS6C1008: banks 0-3, AS6C4008: banks 0-15, on-board RAM ("Block A"): 1.
;
; IMPORTANT for programs that switch banks: the code doing the switching (and
; its stack and variables) must be in ROM or in $0000-$0FFF.  Everything the
; BIOS and its interrupt handlers use is in $0000-$0FFF, so interrupts are safe
; whatever bank is selected.
; ============================================================================

BANKREG         = $7FFE
BANK_PROBE      = $1000                 ; first byte of the banked window

.segment "DRVVARS"
bank_cur:       .res 1                  ; bank selected now
bank_count:     .res 1                  ; banks found at boot (1-16)
bank_save:      .res 16                 ; BANK_INIT scratch

.segment "BIOS"

; ----------------------------------------------------------------------------
; BANK_INIT - select bank 0 and count the banks.  Called from RESET with
; interrupts off.  The byte at $1000 of each bank is put back afterwards, so a
; warm start keeps everything.  Clobbers A, X.
; ----------------------------------------------------------------------------
BANK_INIT:
        lda     #0
        sta     BANKREG
        sta     bank_cur
        lda     #1
        sta     bank_count
.if HAS_BANKS
        ldx     #15                     ; 1. keep the probe byte of every bank
@save:  stx     BANKREG
        lda     BANK_PROBE
        sta     bank_save,x
        dex
        bpl     @save
        ldx     #15                     ; 2. write each bank's number into it,
@mark:  stx     BANKREG                 ;    high to low: banks that alias onto
        txa                             ;    a lower one end up holding the
        sta     BANK_PROBE              ;    lower number
        dex
        bpl     @mark
        ldx     #1                      ; 3. the first bank that doesn't read
@count: stx     BANKREG                 ;    back its own number is the count
        cpx     BANK_PROBE
        bne     @found
        inx
        cpx     #16
        bne     @count
@found: stx     bank_count
        ldx     #15                     ; 4. put the bytes back, high to low,
@rest:  stx     BANKREG                 ;    ending with bank 0 selected
        lda     bank_save,x
        sta     BANK_PROBE
        dex
        bpl     @rest
.endif
        rts

; ----------------------------------------------------------------------------
; BANK_SET - A = bank to select (0-15; only the low 4 bits are used).
; Preserves X and Y.  See the note at the top about where the caller can be.
; ----------------------------------------------------------------------------
BANK_SET:
        and     #$0F
        sta     bank_cur
        sta     BANKREG
        rts

; ----------------------------------------------------------------------------
; BANK_GET - A = bank selected now, X = number of banks found at boot.
; ----------------------------------------------------------------------------
BANK_GET:
        ldx     bank_count
        lda     bank_cur
        rts

; ----------------------------------------------------------------------------
; DELAY_MS - wait A milliseconds (1-255; 0 = 256), from CPU_KHZ.
; Clobbers A, X, Y.  (Approximate: interrupts make it a little longer.)
; ----------------------------------------------------------------------------
DLY_LOOPS       = CPU_KHZ / 5 - 3       ; 5-cycle loops per millisecond

.segment "DRVVARS"
dly_n:          .res 1

.segment "BIOS"
DELAY_MS:
        sta     dly_n
@ms:    ldx     #<DLY_LOOPS
        ldy     #((DLY_LOOPS >> 8) + 1)
@l:     dex                             ; 2
        bne     @l                      ; 3
        dey
        bne     @l
        dec     dly_n
        bne     @ms
        rts
