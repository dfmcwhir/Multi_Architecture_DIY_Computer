; ============================================================================
; term.s - TERM: a terminal for BBSs through a Zimodem on the serial port
;
;   build:  make.bat  (or make)        run:  L TERM 0500   then   R
;
; The serial port (the 6551 at $7F14, where the Zimodem is) and the PIC32
; display card (the 6551 at $7F18: screen out, keyboard in) are joined up:
; what the BBS sends goes to the screen, what you type goes to the BBS.
;
; The display does most of ANSI itself (cursor moves, erasing, scroll regions,
; bold, underline, reverse, the CP437 box and block characters), so most bytes
; go straight through.  On the way TERM:
;   - turns ANSI colours into what a one colour screen can show: bright
;     colours as bold, and reverse video where the background is lighter than
;     the text (black text on cyan, blue on white ...), so nothing disappears
;     (Ctrl-A C: the colour codes passed on as they are)
;   - shows the control codes a BBS means as characters (the CP437 symbols:
;     smileys, arrows ...) as characters, not as the display's own control
;     codes (control code mode is on for the games)
;   - rings the bell (07) on the AY card, if there is one
;
; Local commands: Ctrl-A, then
;   D  dial a BBS: asks for host:port, sends ATDT"host:port" (T: Zimodem does
;      the telnet protocol)          X  hang up (+++, then ATH)
;   S  set-up: the serial port (baud rate 110 - 19200, or 115200 from an
;      external clock; data bits, parity, stop bits, DTR, RTS or RTS flow
;      control) and the settings below; saved as TERM.CFG on the USB drive
;   E  local echo     L  a line feed after each CR received   (also in S)
;   C  ANSI colours as mono, or passed on       K  Backspace sends DEL / BS
;   Z  clear the screen     A  send Ctrl-A     H  help     Q  quit
;
; How: the serial port's characters come in through the ROM's interrupt and
; buffer (SBC_CHRIN), as before.  The display card's receive interrupt is
; turned off while TERM runs (it shares that buffer), and the keyboard is read
; from it directly, between every byte sent to the screen, into TERM's own
; buffer.  The bytes to the screen and to the serial port are timed (one byte
; time each) rather than waited for with the transmit bit, so a W65C51N (whose
; transmit bit is stuck) works too.  The gamepad's interrupt is off meanwhile
; (it would type into the serial buffer).  Quitting puts all of that back.
;
; RTS flow control (set-up item 6: FLOW): RTS is let go when the ROM's
; serial buffer is three quarters full and asserted again under a quarter, so
; a Zimodem set for it (AT&K3) waits.  This looks at the ROM's buffer pointers
; (READ_PTR / WRITE_PTR, $E2 / $E3 in the current ROM).
;
; TERM.CFG: the settings, read at the start from the monitor's current folder
; (SBC_CWD, as YMPLAY and SEQ do) and written by set-up's S.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

MDM_DATA        = $7F14         ; the serial port (the Zimodem)
MDM_STAT        = $7F15
MDM_CMD         = $7F16
MDM_CTRL        = $7F17
DSP_DATA        = $7F18         ; the display card (screen and keyboard)
DSP_STAT        = $7F19
DSP_CMD         = $7F1A
DSP_CTRL        = $7F1B
VIA_T2CL        = $7F08
VIA_T2CH        = $7F09
VIA_ACR         = $7F0B
VIA_IFR         = $7F0D
VIA_IER         = $7F0E
AY_ADDR         = $7F22
AY_DATA         = $7F23

CMD_IRQ         = $89           ; 6551 command: DTR on, RTS on, receive IRQ on (the ROM's)
CMD_NOIRQ       = $8B           ;  the same, receive IRQ off
CTRL_ROM        = $1A           ; the ROM's serial setting: 2400 8N1
RDRF            = $08           ; status: a byte received

TICK            = CLOCK_MHZ * 10000 - 2     ; timer 2: 1/100 s
.assert TICK < 65536, error, "the clock is too fast for a 1/100 s tick"
KB_SIZE         = 64            ; the keyboard buffer
CSI_MAX         = 40            ; an ESC [ sequence kept for looking at
LINE_MAX        = 60            ; the dial line

; the wait loops: 13 cycles a turn (with the keyboard looked at)
DSP_N           = (90 * CLOCK_MHZ + 12) / 13                ; 90 us: a byte at 115200
.define TXN(baud) (11000000 / baud * CLOCK_MHZ / 13 + 2)    ; 11 bits at baud (the longest frame)
ROM_RP          = $E2           ; the ROM's serial buffer: read and write
ROM_WP          = $E3           ;  pointers (zero page; see above)
FLOW_OFF        = 192           ; RTS let go at this many bytes waiting,
FLOW_ON         = 64            ;  asserted again under this many
.ifndef SBC_CWD
SBC_CWD         = $FE18
.endif
CWD_MAX         = 31
CH_WRITE        = 1             ; (ch376r.s: writing too)

        .segment "CODE"
        jmp     start

        .include "ay/common.s"  ; (delay_ms, for the USB drive code)
        .include "ay/ch376r.s"  ; the USB drive: TERM.CFG

; ---- start ---------------------------------------------------------------------------
start:  cld
        ldx     #$FF
        txs
        lda     VIA_IER         ; the gamepad's timer interrupt off (kept to put back)
        and     #$40
        sta     ier_t1
        lda     #$40
        sta     VIA_IER
        lda     #$20            ; timer 2: one shot, its interrupt off
        sta     VIA_IER
        lda     VIA_ACR
        and     #$DF
        sta     VIA_ACR
        lda     #CMD_NOIRQ      ; the keyboard read here, not by the interrupt
        sta     DSP_CMD
        lda     #0
        sta     kb_r
        sta     kb_w
        sta     rx_state
        sta     cmd_mode
        sta     bell_t
        sta     port_to
        sta     cwd_buf         ; the monitor's current folder (SBC_CWD)
        lda     SBC_CWD
        cmp     #$4C
        bne     @nocwd
        jsr     SBC_CWD
        sta     @cw+1
        sty     @cw+2
        ldx     #0
@cw:    lda     $FFFF,x
        sta     cwd_buf,x
        beq     @nocwd
        inx
        cpx     #CWD_MAX
        bcc     @cw
        lda     #0
        sta     cwd_buf
@nocwd: jsr     cfg_default
        jsr     cfg_load        ; TERM.CFG, if there is one
        lda     #0
        rol
        sta     tmp2            ; (1: not read)
        jsr     apply_port
        jsr     sgr_reset
@fl:    jsr     SBC_CHRIN       ; (anything waiting from before: dropped)
        bcs     @fl
        lda     #$18            ; the display: normal text, no scroll region, clear
        jsr     dout
        lda     #0
        jsr     dout
        sta     out_last
        lda     #<init_txt
        ldy     #>init_txt
        jsr     dprint
        jsr     show_port
        lda     tmp2
        bne     :+
        lda     #<loaded_txt
        ldy     #>loaded_txt
        jsr     msg
        jsr     msg_end
:       lda     #<hello_txt
        ldy     #>hello_txt
        jsr     dprint
        jsr     t_start

; ---- the main loop -----------------------------------------------------------------------
main:   lda     DSP_STAT        ; the keyboard
        and     #RDRF
        beq     :+
        jsr     kb_store
:       jsr     kb_get
        bcc     :+
        jsr     do_key
:       jsr     SBC_CHRIN       ; the serial port
        bcc     :+
        jsr     rx_byte
:       lda     rts_i           ; RTS flow control
        cmp     #2
        bne     :+
        jsr     flow
:       lda     VIA_IFR         ; 1/100 s gone?
        and     #$20
        beq     main
        jsr     t_start
        jsr     tick_job
        jmp     main

t_start:lda     #<TICK
        sta     VIA_T2CL
        lda     #>TICK
        sta     VIA_T2CH
        rts

; every 1/100 s: the bell's time
tick_job:
        lda     bell_t
        beq     @r
        dec     bell_t
        bne     @r
        jmp     bell_off
@r:     rts

; wait A hundredths of a second (the keyboard still read)
wait_ticks:
        sta     wt
@l:     lda     DSP_STAT
        and     #RDRF
        beq     :+
        jsr     kb_store
:       lda     VIA_IFR
        and     #$20
        beq     @l
        jsr     t_start
        jsr     tick_job
        dec     wt
        bne     @l
        rts

; ---- the keyboard ------------------------------------------------------------------------
; the byte waiting in the display card into the buffer (keeps A, X, Y)
kb_store:
        pha
        txa
        pha
        lda     DSP_DATA
        ldx     kb_w
        sta     kbbuf,x
        inx
        txa
        and     #KB_SIZE - 1
        cmp     kb_r            ; (full: the byte is dropped)
        beq     :+
        sta     kb_w
:       pla
        tax
        pla
        rts

; carry set and A = the next key, or carry clear
kb_get: ldx     kb_r
        cpx     kb_w
        beq     @no
        lda     kbbuf,x
        pha
        inx
        txa
        and     #KB_SIZE - 1
        sta     kb_r
        pla
        sec
        rts
@no:    clc
        rts

; wait for a key: A (the serial port keeps filling the ROM's buffer)
kb_wait:
@l:     lda     DSP_STAT
        and     #RDRF
        beq     :+
        jsr     kb_store
:       lda     VIA_IFR
        and     #$20
        beq     :+
        jsr     t_start
        jsr     tick_job
:       jsr     kb_get
        bcc     @l
        rts

; a key typed
do_key: ldx     cmd_mode
        beq     @n
        ldx     #0
        stx     cmd_mode
        jmp     local_cmd
@n:     cmp     #1              ; Ctrl-A: a local command next
        bne     @k
        sta     cmd_mode
        rts
@k:     ldx     bs_swap         ; Backspace: DEL <-> BS
        beq     @s
        cmp     #8
        bne     :+
        lda     #127
        bne     @s
:       cmp     #127
        bne     @s
        lda     #8
@s:     jsr     mdm_out
        ldx     echo
        beq     @r
        jmp     rx_byte         ; (shown as if it had come back)
@r:     rts

; ---- out ---------------------------------------------------------------------------------
; A to the screen, then a byte's time, reading the keyboard meanwhile.
; Keeps A, X, Y.
dout:   sta     DSP_DATA
        pha
        tya
        pha
        ldy     #DSP_N
@l:     lda     DSP_STAT
        and     #RDRF
        beq     :+
        jsr     kb_store
:       dey
        bne     @l
        pla
        tay
        pla
        rts

; A to the serial port, then 11 bits' time at the baud rate.  Keeps A, X, Y.
mdm_out:
        sta     MDM_DATA
        pha
        txa
        pha
        tya
        pha
        ldx     txn_hi
        inx
        ldy     txn_lo
@l:     lda     DSP_STAT
        and     #RDRF
        beq     :+
        jsr     kb_store
:       dey
        bne     @l
        dex
        bne     @l
        pla
        tay
        pla
        tax
        pla
        rts

; the 0-ended string at A/Y to the screen
dprint: sta     @ld+1
        sty     @ld+2
@ld:    lda     $FFFF
        beq     @r
        jsr     dout
        inc     @ld+1
        bne     @ld
        inc     @ld+2
        bne     @ld
@r:     rts

; the 0-ended string at A/Y to the serial port
mprint: sta     @ld+1
        sty     @ld+2
@ld:    lda     $FFFF
        beq     @r
        jsr     mdm_out
        inc     @ld+1
        bne     @ld
        inc     @ld+2
        bne     @ld
@r:     rts

; ---- from the BBS -------------------------------------------------------------------------
; a byte from the serial port: to the screen, through the ANSI filter
rx_byte:
        ldx     rx_state
        beq     rx_norm
        dex
        beq     rx_esc
        dex
        bne     :+
        jmp     rx_csi
:       ; 3: a long ESC [ sequence: passed on to its end
        jsr     dout
        cmp     #$40
        bcc     :+
        lda     #0
        sta     rx_state
:       rts

rx_norm:
        cmp     #27
        bne     @c
        lda     #1              ; ESC: see what follows
        sta     rx_state
        rts
@c:     cmp     #$20
        bcs     @hi
        tax                     ; the control codes
        beq     @r              ; (NUL: padding)
        cpx     #7
        bne     :+
        jmp     bell
:       cpx     #13
        bne     @ctl
        jsr     dout            ; CR (and LF, if asked for)
        lda     addlf
        beq     @r
        lda     #10
        jmp     dout
@ctl:   lda     ctl_pass-1,x    ; BS, TAB, LF, FF: the display does them;
        beq     @sym            ;  the others are characters to show
        txa
        jmp     dout
@hi:    cmp     #$7F
        bne     @out
@sym:   pha                     ; (a character the display would take as a
        lda     #$1A            ;  control code: 1A n draws it)
        jsr     dout
        pla
        bne     @out
        txa
@out:   jmp     dout
@r:     rts

; 1 for the control codes the display is to act on (01 - 1F)
ctl_pass:   .byte   0,0,0,0,0,0,0, 1,1,1,0,1,0, 0,0,0,0,0,0,0,0,0,0,0,0,0, 0,0,0,0,0
            ;       01-07           08 09 0A 0B 0C 0D(CR, above)  0E-1F (1B is ESC)

rx_esc: cmp     #'['
        bne     @two
        lda     #2              ; ESC [: collect it
        sta     rx_state
        lda     #0
        sta     csi_len
        rts
@two:   pha                     ; any other ESC x: as it is (the display
        lda     #27             ;  does ESC 7, ESC 8, ESC M, ESC ( 0 ...)
        jsr     dout
        pla
        cmp     #27             ; (ESC ESC: the second still waits)
        beq     @r
        ldx     #0
        stx     rx_state
        jmp     dout
@r:     rts

rx_csi: cmp     #$20
        bcs     @in
        pha                     ; a control code inside: what there is goes
        jsr     csi_raw         ;  on, then the control code
        lda     #0
        sta     rx_state
        pla
        jmp     rx_norm
@in:    cmp     #$40
        bcs     @fin
        ldx     csi_len         ; a parameter (or an intermediate)
        cpx     #CSI_MAX
        bcs     @long
        sta     csi_buf,x
        inc     csi_len
        rts
@long:  pha                     ; too long to keep: passed on as it comes
        jsr     csi_raw
        pla
        jsr     dout
        lda     #3
        sta     rx_state
        rts
@fin:   ldx     #0              ; the end of it
        stx     rx_state
        cmp     #'m'
        bne     @raw
        ldx     cmap
        beq     @raw
        jmp     sgr
@raw:   pha
        jsr     csi_raw
        pla
        jmp     dout

; ESC [ and what has been collected, to the screen
csi_raw:
        lda     #27
        jsr     dout
        lda     #'['
        jsr     dout
        ldx     #0
@l:     cpx     csi_len
        beq     @r
        lda     csi_buf,x
        jsr     dout
        inx
        bne     @l
@r:     rts

; ---- colours to mono ---------------------------------------------------------------------
; ESC [ ... m: the colours and attributes followed; what the display can show
; of them sent as ESC [ 0 ; 1 ; 4 ; 7 m (when it changes)
sgr:    ldx     #0              ; only digits and ";": else passed on
@chk:   cpx     csi_len
        beq     @ok
        lda     csi_buf,x
        cmp     #';'
        beq     :+
        cmp     #'0'
        bcc     @raw
        cmp     #'9' + 1
        bcs     @raw
:       inx
        bne     @chk
@raw:   jsr     csi_raw
        lda     #'m'
        jmp     dout
@ok:    lda     #0
        sta     num
        sta     ext
        ldx     #0
@p:     cpx     csi_len
        beq     @last
        lda     csi_buf,x
        cmp     #';'
        bne     @dig
        jsr     sgr_one
        lda     #0
        sta     num
        inx
        bne     @p
@dig:   and     #$0F            ; num = num x 10 + the digit (kept under 256)
        sta     tmp
        lda     num
        cmp     #26
        bcs     @big
        asl
        sta     tmp2
        asl
        asl
        adc     tmp2
        adc     tmp
        bcc     :+
@big:   lda     #255
:       sta     num
        inx
        bne     @p
@last:  jsr     sgr_one
        ; (on into sgr_show)

; what the display shows for the colours now: bold, underline, reverse
sgr_show:
        lda     #0
        sta     tmp
        lda     s_bold          ; bold: bold, or a bright colour
        ora     s_fgb
        beq     :+
        lda     #1
        sta     tmp
:       lda     s_ul
        beq     :+
        lda     tmp
        ora     #2
        sta     tmp
:       lda     s_bold          ; the text's lightness, and the background's
        ora     s_fgb
        beq     :+
        lda     #8
:       ora     s_fg
        tax
        lda     lum,x
        sta     tmp2
        lda     s_bgb           ; (blink: a bright background, as the iCE
        ora     s_blink         ;  colour files mean it)
        beq     :+
        lda     #8
:       ora     s_bg
        tax
        lda     lum,x
        cmp     tmp2            ; a lighter background: reverse
        beq     :+
        bcc     :+
        lda     #4
        bne     @rv
:       lda     #0
@rv:    eor     s_rev           ; (s_rev is 0 or 4)
        ora     tmp
        cmp     out_last
        beq     @r
        sta     out_last
        sta     tmp
        lda     #27
        jsr     dout
        lda     #'['
        jsr     dout
        lda     #'0'
        jsr     dout
        lsr     tmp
        bcc     :+
        lda     #<b1_txt
        ldy     #>b1_txt
        jsr     dprint
:       lsr     tmp
        bcc     :+
        lda     #<b4_txt
        ldy     #>b4_txt
        jsr     dprint
:       lsr     tmp
        bcc     :+
        lda     #<b7_txt
        ldy     #>b7_txt
        jsr     dprint
:       lda     #'m'
        jmp     dout
@r:     rts

; one parameter (num) of ESC [ ... m (keeps X)
sgr_one:
        lda     ext             ; after 38 / 48: 5;n or 2;r;g;b to skip
        beq     @n
        cmp     #1
        bne     @skip
        lda     #0
        sta     ext
        lda     num
        cmp     #5
        bne     :+
        lda     #2              ; (one more to skip)
        sta     ext
        rts
:       cmp     #2
        bne     @x
        lda     #4              ; (three more)
        sta     ext
@x:     rts
@skip:  dec     ext
        lda     ext
        cmp     #1
        bne     @x
        lda     #0
        sta     ext
        rts
@n:     lda     num
        bne     :+
        jmp     sgr_reset
:       cmp     #1
        bne     :+
        sta     s_bold
        rts
:       cmp     #4
        bne     :+
        sta     s_ul
        rts
:       cmp     #5
        beq     @bl
        cmp     #6
        bne     :+
@bl:    lda     #1
        sta     s_blink
        rts
:       cmp     #7
        bne     :+
        lda     #4
        sta     s_rev
        rts
:       ldy     #0
        cmp     #22
        bne     :+
        sty     s_bold
        rts
:       cmp     #24
        bne     :+
        sty     s_ul
        rts
:       cmp     #25
        bne     :+
        sty     s_blink
        rts
:       cmp     #27
        bne     :+
        sty     s_rev
        rts
:       cmp     #38
        beq     @ext
        cmp     #48
        bne     :+
@ext:   lda     #1
        sta     ext
        rts
:       cmp     #39
        bne     :+
        lda     #7
        sta     s_fg
        sty     s_fgb
        rts
:       cmp     #49
        bne     :+
        sty     s_bg
        sty     s_bgb
        rts
:       sec                     ; 30-37, 40-47, 90-97, 100-107
        sbc     #30
        cmp     #8
        bcs     :+
        sta     s_fg
        sty     s_fgb
        rts
:       sbc     #10
        cmp     #8
        bcs     :+
        sta     s_bg
        sty     s_bgb
        rts
:       sbc     #50
        cmp     #8
        bcs     :+
        sta     s_fg
        lda     #1
        sta     s_fgb
        rts
:       sbc     #10
        cmp     #8
        bcs     @r
        sta     s_bg
        lda     #1
        sta     s_bgb
@r:     rts

sgr_reset:
        lda     #0
        sta     s_bold
        sta     s_ul
        sta     s_blink
        sta     s_rev
        sta     s_fgb
        sta     s_bg
        sta     s_bgb
        lda     #7
        sta     s_fg
        rts

; how light each colour looks (black red green yellow blue magenta cyan white,
; then the bright ones)
lum:        .byte   0, 3, 5, 7, 1, 4, 6, 9
            .byte   4, 7, 10, 13, 6, 9, 12, 15

b1_txt:     .byte   ";1", 0
b4_txt:     .byte   ";4", 0
b7_txt:     .byte   ";7", 0

; ---- the bell -----------------------------------------------------------------------------
; a short beep on the AY card's channel A (nothing happens without the card)
bell:   lda     #0
        ldx     #142            ; about 880 Hz: 2 MHz / (16 x 142)
        jsr     ay_set
        lda     #1
        ldx     #0
        jsr     ay_set
        lda     #7
        ldx     #$3E            ; mixer: tone A only
        jsr     ay_set
        lda     #8
        ldx     #12
        jsr     ay_set
        lda     #12             ; for 0.12 s
        sta     bell_t
        rts
bell_off:
        lda     #8
        ldx     #0
        jsr     ay_set
        lda     #7
        ldx     #$3F
        ; (on)
; AY register A = X
ay_set: sta     AY_ADDR
        stx     AY_DATA
        rts

; ---- local commands -----------------------------------------------------------------------
local_cmd:
        cmp     #'a'            ; (letters in either case)
        bcc     :+
        cmp     #'z' + 1
        bcs     :+
        and     #$DF
:       ldx     #N_LCMD - 1
@f:     cmp     lcmd_chr,x
        beq     @go
        dex
        bpl     @f
        rts
@go:    txa
        asl
        tax
        lda     lcmd_adr+1,x
        pha
        lda     lcmd_adr,x
        pha
        rts                     ; (to it: its address - 1 was pushed)

lcmd_chr:   .byte   "DXSELCKZAH?Q", 1
N_LCMD      = * - lcmd_chr
lcmd_adr:   .word   dial-1, hangup-1, setup-1, t_echo-1, t_lf-1, t_cmap-1
            .word   t_bs-1, clear-1, send_ca-1, help-1, help-1, quit-1, send_ca-1

; "[TERM: " ... "]" on a line of its own: the text at A/Y
msg:    pha
        tya
        pha
        lda     #<msg_txt
        ldy     #>msg_txt
        jsr     dprint
        pla
        tay
        pla
        jmp     dprint
msg_end:lda     #<end_txt
        ldy     #>end_txt
        jmp     dprint

send_ca:lda     #1
        jmp     mdm_out

clear:  lda     #12
        jmp     dout

help:   lda     #<help_txt
        ldy     #>help_txt
        jmp     dprint

; on/off settings: show the new state
t_echo: ldx     #echo - flags
        lda     #<echo_txt
        ldy     #>echo_txt
        bne     toggle
t_lf:   ldx     #addlf - flags
        lda     #<lf_txt
        ldy     #>lf_txt
        bne     toggle
t_cmap: ldx     #cmap - flags
        lda     #<cmap_txt
        ldy     #>cmap_txt
        bne     toggle
t_bs:   ldx     #bs_swap - flags
        lda     #<bs_txt
        ldy     #>bs_txt
toggle: jsr     msg
        lda     flags,x
        eor     #1
        sta     flags,x
        bne     @on
        lda     #<off_txt
        ldy     #>off_txt
        jsr     dprint
        jmp     msg_end
@on:    lda     #<on_txt
        ldy     #>on_txt
        jsr     dprint
        jmp     msg_end

; ---- the serial port ----------------------------------------------------------------------
; the 6551 as the settings say.  Control: the rate, its own clock (RCS), the
; data bits, the stop bits.  Command: the parity, RTS, receive IRQ on, DTR.
apply_port:
        ldx     baud_i
        lda     baud_codes,x
        ora     #$10
        ldy     data_i
        ora     data_bits,y
        ldy     stop_i
        beq     :+
        ora     #$80
:       sta     MDM_CTRL
        lda     txn_l,x
        sta     txn_lo
        lda     txn_h,x
        sta     txn_hi
        lda     #1
        sta     rts_now
        ; (on)
; the command register: parity, RTS (on, off, or as flow control says), DTR
put_cmd:
        ldy     par_i
        lda     par_bits,y
        ora     dtr             ; (bit 0: DTR on)
        ldx     rts_i
        beq     @on
        cpx     #1
        beq     @w
        ldx     rts_now
        beq     @w
@on:    ora     #$08            ; (TIC = 10: RTS asserted, no transmit IRQ)
@w:     sta     MDM_CMD
        rts

; RTS flow control: let go at FLOW_OFF bytes waiting, assert under FLOW_ON
flow:   lda     ROM_WP
        sec
        sbc     ROM_RP
        ldx     rts_now
        bne     @on
        cmp     #FLOW_ON        ; let go: assert again?
        bcs     @r
        lda     #1
        sta     rts_now
        jmp     put_cmd
@on:    cmp     #FLOW_OFF       ; asserted: let go?
        bcc     @r
        lda     #0
        sta     rts_now
        jmp     put_cmd
@r:     rts

; "[TERM: 1200 8N1]" (with ", RTS FLOW" when it is)
show_port:
        lda     #' '
        sta     psep
        lda     #<port_txt0
        ldy     #>port_txt0
        jsr     msg
        jsr     port_out
        lda     rts_i
        cmp     #2
        bne     :+
        lda     #<flow_txt
        ldy     #>flow_txt
        jsr     dprint
:       jmp     msg_end

; the rate and format, as "1200 8N1", to the screen (dout) or, after
; port_to = 1, the Zimodem as "1200,8N1"
port_out:
        ldx     baud_i
        jsr     baud_str
        jsr     to_dprint
        lda     psep            ; (" " or "," in an ATB)
        jsr     to_out
        lda     #'8'
        sec
        sbc     data_i
        jsr     to_out
        ldx     par_i
        lda     par_chr,x
        jsr     to_out
        lda     stop_i
        clc
        adc     #'1'
        ; (on)
to_out: ldx     port_to
        bne     :+
        jmp     dout
:       jmp     mdm_out
to_dprint:
        ldx     port_to
        bne     :+
        jmp     dprint
:       jmp     mprint

; A/Y = the rate X as text ("1200")
baud_str:
        txa
        asl
        tax
        lda     baud_names,x
        ldy     baud_names+1,x
        rts

N_BAUD      = 13
baud_codes: .byte   $03, $05, $06, $07, $08, $09, $0A, $0B, $0C, $0D, $0E, $0F, $00
txn_l:      .byte   <TXN(110), <TXN(150), <TXN(300), <TXN(600), <TXN(1200), <TXN(1800)
            .byte   <TXN(2400), <TXN(3600), <TXN(4800), <TXN(7200), <TXN(9600), <TXN(19200)
            .byte   <TXN(115200)
txn_h:      .byte   >TXN(110), >TXN(150), >TXN(300), >TXN(600), >TXN(1200), >TXN(1800)
            .byte   >TXN(2400), >TXN(3600), >TXN(4800), >TXN(7200), >TXN(9600), >TXN(19200)
            .byte   >TXN(115200)
baud_names: .word   b110, b150, b300, b600, b1200, b1800, b2400, b3600, b4800, b7200
            .word   b9600, b19200, b115200
b110:       .byte   "110", 0
b150:       .byte   "150", 0
b300:       .byte   "300", 0
b600:       .byte   "600", 0
b1200:      .byte   "1200", 0
b1800:      .byte   "1800", 0
b2400:      .byte   "2400", 0
b3600:      .byte   "3600", 0
b4800:      .byte   "4800", 0
b7200:      .byte   "7200", 0
b9600:      .byte   "9600", 0
b19200:     .byte   "19200", 0
b115200:    .byte   "115200", 0
data_bits:  .byte   $00, $20, $40, $60              ; 8 7 6 5 (control bits 5-6)
par_bits:   .byte   $00, $20, $60, $A0, $E0         ; none odd even mark space (command bits 5-7)
par_chr:    .byte   "NOEMS"

; ---- set-up ---------------------------------------------------------------------------------
; a screen of the settings: a digit changes one (to its next value), S saves
; them in TERM.CFG, Enter or Esc goes back.  The port changes on the way out;
; if its rate or format changed, TERM offers to tell the Zimodem first (ATB,
; sent as the port still is).
N_ITEMS     = 10
setup:  ldx     #3              ; (the port as it is)
@o:     lda     cfg,x
        sta     old_cfg,x
        dex
        bpl     @o
@draw:  jsr     setup_draw
@k:     jsr     kb_wait
        cmp     #13
        beq     @out
        cmp     #27
        beq     @out
        cmp     #'0'
        bne     :+
        lda     #'9' + 1        ; (0 is the tenth)
:       sec
        sbc     #'1'
        cmp     #N_ITEMS
        bcs     @let
        tax                     ; the next value of item X
        inc     cfg,x
        lda     cfg,x
        cmp     item_count,x
        bcc     @draw
        lda     #0
        sta     cfg,x
        beq     @draw
@let:   adc     #'1' - 1        ; (back to the key: carry was set)
        and     #$DF
        cmp     #'S'
        bne     @k
        jsr     cfg_save
        jmp     @k
@out:   lda     #12
        jsr     dout
        ldx     #3              ; the rate or format changed?
@c:     lda     cfg,x
        cmp     old_cfg,x
        bne     @tell
        dex
        bpl     @c
        jsr     put_cmd         ; (DTR, RTS)
        jmp     show_port
@tell:  lda     #','            ; tell the Zimodem?  ATB"rate,8N1"
        sta     psep
        lda     #<tell_txt
        ldy     #>tell_txt
        jsr     msg
        lda     #<atb_txt       ; (shown: port_to is 0)
        ldy     #>atb_txt
        jsr     to_dprint
        jsr     port_out
        lda     #'"'
        jsr     to_out
        lda     #<tell2_txt
        ldy     #>tell2_txt
        jsr     dprint
        jsr     kb_wait
        and     #$DF
        cmp     #'Y'
        bne     @set
        lda     #1              ; (sent with the port as it was)
        sta     port_to
        lda     #<atb_txt
        ldy     #>atb_txt
        jsr     to_dprint
        jsr     port_out
        lda     #'"'
        jsr     to_out
        lda     #13
        jsr     to_out
        lda     #0
        sta     port_to
        lda     #50             ; (its OK comes the old way)
        jsr     wait_ticks
@set:   jsr     msg_end
        jsr     apply_port
        jmp     show_port

; the set-up screen
setup_draw:
        lda     #12
        jsr     dout
        lda     #<setup_txt
        ldy     #>setup_txt
        jsr     dprint
        ldx     #0
@l:     stx     item
        lda     #' '            ; "  1  BAUD RATE     1200      (hint)"
        jsr     dout
        jsr     dout
        txa
        clc
        adc     #'1'
        cmp     #'9' + 1
        bne     :+
        lda     #'0'
:       jsr     dout
        lda     #' '
        jsr     dout
        jsr     dout
        txa
        asl
        tax
        lda     item_names,x
        ldy     item_names+1,x
        jsr     dprint
        lda     #$0E            ; (the value at column 20)
        jsr     dout
        lda     #20
        jsr     dout
        ldx     item            ; the value's name: in the item's list, at
        txa                     ;  the value x 2
        asl
        tax
        lda     item_lists,x
        sta     @lo+1
        sta     @hi+1
        lda     item_lists+1,x
        sta     @lo+2
        sta     @hi+2
        ldx     item
        lda     cfg,x
        asl
        tay
@lo:    lda     $FFFF,y
        pha
        iny
@hi:    lda     $FFFF,y
        tay
        pla
        jsr     dprint
        lda     #$0E            ; (the hint at column 30)
        jsr     dout
        lda     #30
        jsr     dout
        lda     item
        asl
        tax
        lda     item_hints,x
        ldy     item_hints+1,x
        jsr     dprint
        lda     #13
        jsr     dout
        lda     #10
        jsr     dout
        ldx     item
        inx
        cpx     #N_ITEMS
        beq     :+
        jmp     @l
:       lda     #<setup2_txt
        ldy     #>setup2_txt
        jmp     dprint

; each item: its name, how many values, their names, a hint
item_names: .word   in1, in2, in3, in4, in5, in6, in7, in8, in9, in10
in1:        .byte   "BAUD RATE", 0
in2:        .byte   "DATA BITS", 0
in3:        .byte   "PARITY", 0
in4:        .byte   "STOP BITS", 0
in5:        .byte   "DTR", 0
in6:        .byte   "RTS", 0
in7:        .byte   "LOCAL ECHO", 0
in8:        .byte   "LF AFTER CR", 0
in9:        .byte   "COLOURS", 0
in10:       .byte   "BACKSPACE", 0
item_count: .byte   N_BAUD, 4, 5, 2, 2, 3, 2, 2, 2, 2
item_lists: .word   baud_names, l_data, l_par, l_stop, l_offon, l_rts, l_offon, l_offon, l_cmap, l_bs
l_data:     .word   v8, v7, v6, v5
l_par:      .word   vnone, vodd, veven, vmark, vspace
l_stop:     .word   v1, v2
l_offon:    .word   voff, von
l_rts:      .word   von, voff, vflow
l_cmap:     .word   vsent, vmono
l_bs:       .word   vdel, vbs
v8:         .byte   "8", 0
v7:         .byte   "7", 0
v6:         .byte   "6", 0
v5:         .byte   "5", 0
vnone:      .byte   "NONE", 0
vodd:       .byte   "ODD", 0
veven:      .byte   "EVEN", 0
vmark:      .byte   "MARK", 0
vspace:     .byte   "SPACE", 0
v1:         .byte   "1", 0
v2:         .byte   "2", 0
voff:       .byte   "OFF", 0
von:        .byte   "ON", 0
vflow:      .byte   "FLOW", 0
vsent:      .byte   "AS SENT", 0
vmono:      .byte   "MONO", 0
vdel:       .byte   "DEL", 0
vbs:        .byte   "BS", 0
item_hints: .word   ih1, ih2, ih3, ih4, ih5, ih6, ih7, ih8, ih9, ih10
ih1:        .byte   "110 - 19200; 115200 NEEDS THE EXTERNAL CLOCK", 0
ih2:        .byte   "8 FOR BBSS", 0
ih3:        .byte   "NONE FOR BBSS", 0
ih4:        .byte   "1 FOR BBSS", 0
ih5:        .byte   "OFF: THE 6551 STOPS RECEIVING", 0
ih6:        .byte   "FLOW: OFF WHILE THE BUFFER IS FULL", 0
ih7:        .byte   "SHOW WHAT YOU TYPE", 0
ih8:        .byte   "FOR SYSTEMS THAT SEND CR ALONE", 0
ih9:        .byte   "ANSI COLOURS: MONO OR AS SENT", 0
ih10:       .byte   "WHAT THE BACKSPACE KEY SENDS", 0

setup_txt:  .byte   27, "[0m", "TERM SET-UP: THE SERIAL PORT (THE 6551 AT $7F14) AND MORE", 13, 10, 13, 10, 0
setup2_txt: .byte   13, 10, "  A DIGIT: THE NEXT VALUE     S: SAVE AS TERM.CFG     ENTER OR ESC: BACK", 13, 10, 0
port_txt0:  .byte   "PORT ", 0
flow_txt:   .byte   ", RTS FLOW", 0
tell_txt:   .byte   "THE PORT CHANGES. SEND THE ZIMODEM ", 0
tell2_txt:  .byte   " FIRST (Y/N)? ", 0

; ---- TERM.CFG -------------------------------------------------------------------------------
; the defaults: 1200 8N1 (the Zimodem's own), DTR and RTS on, colours as mono
cfg_default:
        ldx     #CFG_LEN - 1
@c:     lda     cfg_def,x
        sta     cfg,x
        dex
        bpl     @c
        rts
cfg_def:    .byte   4, 0, 0, 0, 1, 0, 0, 0, 1, 0

; the settings from TERM.CFG: carry clear if they were read
cfg_load:
        jsr     drive_in
        bcs     @no
        jsr     cfg_name
        jsr     ch_open
        cmp     #USB_INT_SUCCESS
        bne     @no
        lda     #<fbuf
        sta     ch_ptr
        lda     #>fbuf
        sta     ch_ptr+1
        lda     #CFG_LEN + 4
        sta     ch_len
        lda     #0
        sta     ch_len+1
        jsr     ch_read
        jsr     ch_close
        lda     ch_got
        cmp     #CFG_LEN + 4
        bne     @no
        ldx     #3
@s:     lda     fbuf,x
        cmp     cfg_sig,x
        bne     @no
        dex
        bpl     @s
        ldx     #CFG_LEN - 1    ; (each in range, else the default)
@c:     lda     fbuf+4,x
        cmp     item_count,x
        bcc     :+
        lda     cfg_def,x
:       sta     cfg,x
        dex
        bpl     @c
        clc
        rts
@no:    sec
        rts

; the settings to TERM.CFG (set-up's S): says how it went
cfg_save:
        ldx     #3
@s:     lda     cfg_sig,x
        sta     fbuf,x
        dex
        bpl     @s
        ldx     #CFG_LEN - 1
@c:     lda     cfg,x
        sta     fbuf+4,x
        dex
        bpl     @c
        jsr     drive_in
        bcs     @err
        jsr     cfg_name
        jsr     ch_create
        cmp     #USB_INT_SUCCESS
        bne     @err
        lda     #<fbuf
        sta     ch_ptr
        lda     #>fbuf
        sta     ch_ptr+1
        lda     #CFG_LEN + 4
        sta     ch_len
        lda     #0
        sta     ch_len+1
        jsr     ch_write
        cmp     #USB_INT_SUCCESS
        bne     @err
        jsr     ch_close_w
        cmp     #USB_INT_SUCCESS
        bne     @err
        lda     #<saved_txt
        ldy     #>saved_txt
        jmp     dprint
@err:   pha
        lda     #<save_err_txt
        ldy     #>save_err_txt
        jsr     dprint
        pla
        jsr     dhex
        lda     #13
        jsr     dout
        lda     #10
        jmp     dout

; A/Y = "TERM.CFG" (in the current folder) or "/TERM.CFG" (the top one)
cfg_name:
        lda     #<cfg_file
        ldy     #>cfg_file
        ldx     cwd_buf
        bne     :+
        lda     #<cfg_path
        ldy     #>cfg_path
:       rts

; into the monitor's folder: the drive as the monitor left it, or started
; afresh; carry set if it can't be done
drive_in:
        jsr     ch_check
        bcs     @r
        jsr     go_in
        beq     @ok
        jsr     ch_start
        bcs     @r
        jsr     go_in
        beq     @ok
        sec
        rts
@ok:    clc
@r:     rts

; into the folder (the top: open "/"): Z set if it went well
go_in:  lda     cwd_buf
        bne     @in
        lda     #<root_txt
        ldy     #>root_txt
        jsr     ch_open
        cmp     #ERR_OPEN_DIR
        rts
@in:    lda     #<cwd_buf
        ldy     #>cwd_buf
        jsr     ch_enter
        cmp     #ERR_OPEN_DIR
        rts

cfg_sig:    .byte   "TCF1"
root_txt:   .byte   "/", 0
cfg_path:   .byte   "/"
cfg_file:   .byte   "TERM.CFG", 0
saved_txt:  .byte   "  SAVED IN TERM.CFG", 13, 10, 0
save_err_txt:.byte  "  NOT SAVED: USB DRIVE ERROR $", 0

; A in hex to the screen
dhex:   pha
        lsr
        lsr
        lsr
        lsr
        jsr     @d
        pla
        and     #$0F
@d:     cmp     #10
        bcc     :+
        adc     #'A' - '0' - 10 - 1
:       adc     #'0'
        jmp     dout

; dial: ask for host:port, send ATDT"host:port" (":23" added if no port)
dial:   lda     #<dial_txt
        ldy     #>dial_txt
        jsr     msg
        ldx     #0
        stx     line_len
@k:     jsr     kb_wait
        cmp     #13
        beq     @go
        cmp     #27
        beq     @no
        cmp     #8
        beq     @bs
        cmp     #127
        beq     @bs
        cmp     #' ' + 1
        bcc     @k
        ldx     line_len
        cpx     #LINE_MAX
        bcs     @k
        sta     line,x
        inc     line_len
        jsr     dout
        jmp     @k
@bs:    ldx     line_len
        beq     @k
        dec     line_len
        lda     #8
        jsr     dout
        lda     #' '
        jsr     dout
        lda     #8
        jsr     dout
        jmp     @k
@no:    jmp     msg_end
@go:    jsr     msg_end
        ldx     line_len
        beq     @r
        lda     #<atdt_txt
        ldy     #>atdt_txt
        jsr     mprint
        lda     #0              ; is there a port?
        sta     tmp
        ldx     #0
@s:     lda     line,x
        cmp     #':'
        bne     :+
        sta     tmp
:       jsr     mdm_out
        inx
        cpx     line_len
        bne     @s
        lda     tmp
        bne     :+
        lda     #<port_txt
        ldy     #>port_txt
        jsr     mprint
:       lda     #'"'
        jsr     mdm_out
        lda     #13
        jmp     mdm_out
@r:     rts

; hang up: a second of nothing, +++, a second, ATH
hangup: lda     #<hang_txt
        ldy     #>hang_txt
        jsr     msg
        jsr     msg_end
        lda     #110
        jsr     wait_ticks
        lda     #<plus_txt
        ldy     #>plus_txt
        jsr     mprint
        lda     #110
        jsr     wait_ticks
        lda     #<ath_txt
        ldy     #>ath_txt
        jmp     mprint

quit:   lda     #<quit_txt
        ldy     #>quit_txt
        jsr     msg
        jsr     kb_wait
        and     #$DF
        cmp     #'Y'
        beq     @q
        jmp     msg_end
@q:     jsr     msg_end
        jsr     bell_off
        lda     #8              ; (the AY quiet)
        ldx     #0
        jsr     ay_set
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     dprint
        lda     #CTRL_ROM       ; the serial port as the ROM had it
        sta     MDM_CTRL
        lda     #CMD_IRQ
        sta     MDM_CMD
        sta     DSP_CMD         ; the keyboard by interrupt again
        lda     ier_t1          ; the gamepad's interrupt back
        beq     :+
        lda     #$C0
        sta     VIA_IER
:       jmp     SBC_MENU

; ---- text ---------------------------------------------------------------------------------
init_txt:   .byte   27, "[0m", 27, "[r", 12          ; (and 18 00 before it: normal text)
            .byte   "TERM - A TERMINAL FOR BBSS THROUGH ZIMODEM", 13, 10, 0
hello_txt:  .byte   "TYPE AT COMMANDS TO THE ZIMODEM, OR CTRL-A D TO DIAL A BBS.", 13, 10
            .byte   "CTRL-A H: HELP", 13, 10, 0
help_txt:   .byte   13, 10, "TERM: CTRL-A, THEN", 13, 10
            .byte   "  D  DIAL A BBS (HOST:PORT)     X  HANG UP", 13, 10
            .byte   "  S  SET-UP: THE SERIAL PORT    E  LOCAL ECHO ON/OFF", 13, 10
            .byte   "  L  LF AFTER CR ON/OFF         C  ANSI COLOURS AS MONO ON/OFF", 13, 10
            .byte   "  K  BACKSPACE SENDS DEL/BS     Z  CLEAR THE SCREEN", 13, 10
            .byte   "  A  SEND CTRL-A                H  THIS HELP      Q  QUIT", 13, 10, 0
msg_txt:    .byte   13, 10, "[TERM: ", 0
end_txt:    .byte   "]", 13, 10, 0
loaded_txt: .byte   "SETTINGS FROM TERM.CFG", 0
echo_txt:   .byte   "LOCAL ECHO ", 0
lf_txt:     .byte   "LF AFTER CR ", 0
cmap_txt:   .byte   "ANSI COLOURS AS MONO ", 0
bs_txt:     .byte   "BACKSPACE SENDS BS (NOT DEL) ", 0
on_txt:     .byte   "ON", 0
off_txt:    .byte   "OFF", 0
dial_txt:   .byte   "DIAL HOST:PORT (ESC: NO) ", 0
hang_txt:   .byte   "HANGING UP", 0
quit_txt:   .byte   "QUIT (Y)? ", 0
bye_txt:    .byte   27, "[0m", "BYE", 13, 10, 0
atb_txt:    .byte   "ATB", '"', 0
atdt_txt:   .byte   "ATDT", '"', 0
port_txt:   .byte   ":23", 0
plus_txt:   .byte   "+++", 0
ath_txt:    .byte   "ATH", 13, 0

; ---- variables ----------------------------------------------------------------------------
        .segment "BSS"
cfg:                            ; the settings (TERM.CFG), in set-up's order
baud_i:     .res 1              ; 0-12: 110 ... 19200, 115200 (external clock)
data_i:     .res 1              ; 0-3: 8 7 6 5 data bits
par_i:      .res 1              ; 0-4: none odd even mark space
stop_i:     .res 1              ; 0-1: 1 or 2 stop bits
dtr:        .res 1              ; 1: on
rts_i:      .res 1              ; 0 on, 1 off, 2 flow control
flags:                          ; (the on/off ones)
echo:       .res 1
addlf:      .res 1
cmap:       .res 1              ; 1: colours as mono
bs_swap:    .res 1
CFG_LEN     = * - cfg
old_cfg:    .res 4              ; (the port as it was when set-up began)
rts_now:    .res 1              ; flow control: RTS asserted now
item:       .res 1
port_to:    .res 1              ; port_out: 0 to the screen, 1 to the Zimodem
psep:       .res 1              ;  and between the rate and the format: " " or ","
cwd_buf:    .res CWD_MAX + 1
fbuf:       .res CFG_LEN + 4
txn_lo:     .res 1              ; the serial port's byte time (wait loop turns)
txn_hi:     .res 1
ier_t1:     .res 1
cmd_mode:   .res 1
rx_state:   .res 1              ; 0 text, 1 after ESC, 2 in ESC [, 3 a long one
csi_len:    .res 1
csi_buf:    .res CSI_MAX
kb_r:       .res 1
kb_w:       .res 1
kbbuf:      .res KB_SIZE
bell_t:     .res 1
wt:         .res 1
s_fg:       .res 1              ; the colours and attributes asked for
s_bg:       .res 1
s_fgb:      .res 1
s_bgb:      .res 1
s_bold:     .res 1
s_ul:       .res 1
s_blink:    .res 1
s_rev:      .res 1              ; (0 or 4)
out_last:   .res 1              ; what the display was last told: bits 1 bold, 2 ul, 4 rev
ext:        .res 1
num:        .res 2
tmp:        .res 1
tmp2:       .res 1
line_len:   .res 1
line:       .res LINE_MAX
