; ============================================================================
; edit.s - EDIT: a full-screen text editor with a markdown viewer, for the
; 6502 SBC and its PIC32 display card (80 x 24, ANSI cursor codes)
;
;   L EDIT 0500
;   R
;
; Files come from (and go to) the USB drive, in the monitor's current folder
; (SBC_CWD), as YMPLAY, SEQ and TERM find theirs.  Up to about 13 KB of text to edit; bigger files can be viewed.
;
; EDIT MODE                         VIEW MODE (^R)
;   arrows Home End PgUp PgDn        arrows, PgUp PgDn (Space, B), Home End
;   ^A ^E line start/end             M     markdown formatting on/off
;   ^Y ^V page up/down               Esc   back to editing (^R too)
;   ^T ^B top/bottom of the file
;   Backspace, Del (^D)
;   Tab: spaces to the next stop     In view mode a .MD file is shown
;   ^K cut line (again: add next)    formatted: headings, **bold**, *emphasis*
;   ^U paste                         (underlined), `code` (reverse), lists,
;   ^F find  ^N find next            quotes, rules, tables, code blocks, links
;   ^L go to line                    (the text shown, the address hidden).
;   ^S save  ^W save as  ^O open     Lines are wrapped at word boundaries.
;   ^R view  ^G help     ^Q quit
;
; Text is kept with LF line ends; a file read with CR LF is written back with
; CR LF (new files too).  UTF-8 is shown as the nearest CP437 character (the
; display's own set): accented letters, dashes, quotes, bullets, box lines.
;
; How it works: the text is a gap buffer (the text before the cursor at the
; bottom of the buffer, the text after it at the top, the free space between),
; so typing costs nothing however long the file is.  The screen is redrawn
; only where it changed, and not at all while keys are still waiting.
; ============================================================================

        .include "sbc_api.inc"
.ifndef SBC_CWD
SBC_CWD         = $FE18
.endif
CH_WRITE        = 1             ; (ch376r.s: writing too)

; ---- the screen -------------------------------------------------------------
.ifndef ROWS
ROWS            = 24
.endif
.ifndef COLS
COLS            = 80
.endif
.ifndef USE_SCROLL
USE_SCROLL      = 1             ; scroll a row with ESC [ M / ESC [ L (0: redraw)
.endif
TROWS           = ROWS - 1      ; the text rows (the last one is the status line)
WIDTH           = COLS - 1      ; columns used: never the last (no wrap or scroll)
TABW            = 4             ; tab stops (a power of 2)

; ---- memory -------------------------------------------------------------------
CLIP_SIZE       = 2048          ; the cut / paste buffer, at the top of RAM
CLIP            = $7F00 - CLIP_SIZE
BUF_END         = CLIP          ; the text buffer: textbuf (after the program) to here
MAXIN           = 40            ; the longest answer to a prompt
CWD_MAX         = 64
PMAX            = 112           ; a whole path

; ---- keys ---------------------------------------------------------------------
K_UP            = $80
K_DN            = $81
K_RT            = $82
K_LT            = $83
K_HOME          = $84
K_END           = $85
K_PGUP          = $86
K_PGDN          = $87
K_DEL           = $88
K_INS           = $89
K_NONE          = $FF
ESC             = 27
LF              = 10
CR              = 13

; ---- attributes -------------------------------------------------------------------
A_BOLD          = 1
A_UL            = 2
A_REV           = 4

; ---- wrapping (view mode) ---------------------------------------------------------
W_WORD          = 0
W_CHAR          = 1
W_NONE          = 2

; ---- zero page (EhBASIC's scratch number buffer: free while EDIT runs) -------------
tp              = $F0           ; the text pointer (tgetc)
lp              = $F2           ; view: the line being laid out
sp              = $F4           ; copies: source
dp              = $F6           ;  and destination
glo             = $F8           ; the gap: its first byte (= the cursor) ...
ghi             = $FA           ;  ... and the first byte after it
zt              = $FC           ; a spare pointer
strp            = $FE           ; prints

; ---- macros -----------------------------------------------------------------------
.macro INC16 v
        inc     v
        bne     *+5             ; (no labels in the macros: a branch past
        inc     a:v+1           ;  one to a ":" would land inside it)
.endmacro
.macro DEC16 v
        lda     v
        bne     *+5
        dec     a:v+1
        dec     v
.endmacro
.macro LDW v, val
        lda     #<(val)
        sta     v
        lda     #>(val)
        sta     v+1
.endmacro
.macro MOVW d, s
        lda     s
        sta     d
        lda     s+1
        sta     d+1
.endmacro
; compare two words: C = (a >= b), Z = (a = b)
.macro CMPW va, vb
        lda     va+1
        cmp     vb+1
        bne     *+8
        lda     a:va
        cmp     a:vb
.endmacro
.macro CMPWI va, val
        lda     va+1
        cmp     #>(val)
        bne     *+7
        lda     a:va
        cmp     #<(val)
.endmacro
.macro PRINT s
        lda     #<s
        ldy     #>s
        jsr     prints
.endmacro
.macro GFN target
        lda     #<target
        sta     gfn_j+1
        lda     #>target
        sta     gfn_j+2
.endmacro
.macro MSG s
        lda     #<s
        ldy     #>s
        jsr     set_msg
.endmacro

        .segment "CODE"
start:  jmp     main

; ============================================================================
; output
; ============================================================================
out     = SBC_CHROUT

; the 0-ended string at A/Y
prints: sta     strp
        sty     strp+1
        ldy     #0
@l:     lda     (strp),y
        beq     @r
        jsr     out
        iny
        bne     @l
        inc     strp+1
        bne     @l
@r:     rts

csi:    lda     #ESC
        jsr     out
        lda     #'['
        jmp     out

; A (0-255) in decimal
out_dec:
        ldx     #'0'
        cmp     #100
        bcc     @t0
@h:     cmp     #100
        bcc     @hd
        sbc     #100
        inx
        bne     @h
@hd:    pha
        txa
        jsr     out
        pla
        ldx     #'0'
        jmp     @t
@t0:    cmp     #10
        bcc     @one
@t:     cmp     #10
        bcc     @td
        sbc     #10
        inx
        bne     @t
@td:    pha
        txa
        jsr     out
        pla
@one:   ora     #'0'
        jmp     out

; the cursor to row X, column Y (from 0)
goto_rc:
        stx     g_r
        sty     g_c
        jsr     csi
        lda     g_r
        clc
        adc     #1
        jsr     out_dec
        lda     #';'
        jsr     out
        lda     g_c
        clc
        adc     #1
        jsr     out_dec
        lda     #'H'
        jmp     out

clr_eol:
        jsr     csi
        lda     #'K'
        jmp     out

; the attributes A (A_BOLD A_UL A_REV), sent only when they change
set_attr:
        cmp     cur_attr
        beq     @r
        sta     cur_attr
        jsr     csi
        lda     #'0'
        jsr     out
        lda     cur_attr
        and     #A_BOLD
        beq     :+
        lda     #';'
        jsr     out
        lda     #'1'
        jsr     out
:       lda     cur_attr
        and     #A_UL
        beq     :+
        lda     #';'
        jsr     out
        lda     #'4'
        jsr     out
:       lda     cur_attr
        and     #A_REV
        beq     :+
        lda     #';'
        jsr     out
        lda     #'7'
        jsr     out
:       lda     #'m'
        jmp     out
@r:     rts

; clear the screen (and the attributes)
cls:    lda     #$FF
        sta     cur_attr
        lda     #0
        jsr     set_attr
        jsr     csi
        lda     #'2'
        jsr     out
        lda     #'J'
        jsr     out
        jsr     csi
        lda     #'H'
        jmp     out

; the text rows up one (the top one goes) / down one (a blank one at the top)
scr_up: lda     #0
        jsr     set_attr
        ldx     #0
        ldy     #0
        jsr     goto_rc
        jsr     csi
        lda     #'M'
        jmp     out
scr_down:
        lda     #0
        jsr     set_attr
        ldx     #0
        ldy     #0
        jsr     goto_rc
        jsr     csi
        lda     #'L'
        jmp     out

; ============================================================================
; keys
; ============================================================================
WAITN   = 100 * CLOCK_MHZ       ; ~10 ms of tries for the rest of an ESC sequence

; a byte, waiting up to ~10 ms: carry set + A, or carry clear
getc_wait:
        lda     #<WAITN
        sta     wcnt
        lda     #>WAITN
        sta     wcnt+1
@l:     jsr     SBC_CHRIN
        bcs     @r
        lda     wcnt
        bne     :+
        dec     wcnt+1
:       dec     wcnt
        lda     wcnt
        ora     wcnt+1
        bne     @l
        clc
@r:     rts

; a key if one is waiting: carry set + A (ESC sequences as K_..), else carry clear
key_nb: jsr     SBC_CHRIN
        bcc     @r
        cmp     #ESC
        beq     @esc
        sec
@r:     rts
@esc:   jsr     getc_wait
        bcc     @lone
        cmp     #'['
        beq     @csi
        cmp     #'O'
        beq     @csi
        lda     #K_NONE         ; (Alt-something)
        sec
        rts
@lone:  lda     #ESC
        sec
        rts
@csi:   lda     #0
        sta     kparm
        sta     kskip
@nx:    jsr     getc_wait
        bcc     @none
        cmp     #';'
        beq     @semi
        cmp     #'0'
        bcc     @int
        cmp     #'9'+1
        bcs     @fin
        ldx     kskip
        bne     @nx
        and     #$0F            ; kparm = kparm * 10 + digit
        sta     ktmp
        lda     kparm
        asl
        asl
        adc     kparm
        asl
        adc     ktmp
        sta     kparm
        jmp     @nx
@semi:  sta     kskip
        jmp     @nx
@int:   jmp     @nx             ; (other bytes before the last one)
@fin:   cmp     #'~'
        beq     @tilde
        ldx     #fin_n - 1
@f:     cmp     fin_c,x
        beq     @fk
        dex
        bpl     @f
@none:  lda     #K_NONE
        sec
        rts
@fk:    lda     fin_k,x
        sec
        rts
@tilde: ldx     kparm
        cpx     #9
        bcs     @none
        lda     tilde_k,x
        sec
        rts

fin_c:  .byte   'A', 'B', 'C', 'D', 'H', 'F'
fin_n   = * - fin_c
fin_k:  .byte   K_UP, K_DN, K_RT, K_LT, K_HOME, K_END
tilde_k:.byte   K_NONE, K_HOME, K_INS, K_DEL, K_END, K_PGUP, K_PGDN, K_HOME, K_END

; wait for a key
key_wait:
        jsr     key_nb
        bcc     key_wait
        rts

; ============================================================================
; UTF-8 to the display's characters (CP437)
;   feed: one byte of text in A; for each character it makes, the routine at
;   gfn_j is called with it in A (TAB stays 9; other control codes become
;   '.').  A byte $80-$C1, or $F5 up, that isn't part of a UTF-8 sequence is
;   taken as a CP437 character itself.
; ============================================================================
dec_reset:
        lda     #0
        sta     u_need
        rts

feed_end:
        lda     u_need
        beq     @r
        lda     #0
        sta     u_need
        lda     #'?'
        jmp     gfn_j
@r:     rts

feed:   ldx     u_need
        bne     @cont
@new:   cmp     #$C2
        bcc     @plain
        cmp     #$F5
        bcs     @plain
        cmp     #$E0            ; a lead byte: how many follow
        bcs     @l3
        and     #$1F
        ldx     #1
        bne     @lead
@l3:    cmp     #$F0
        bcs     @l4
        and     #$0F
        ldx     #2
@lead:  sta     u_cp
        stx     u_need
        lda     #0
        sta     u_cp+1
        sta     u_big
        rts
@l4:    ldx     #3
        stx     u_need
        stx     u_big
        rts
@plain: cmp     #9
        beq     gfn_j
        cmp     #' '
        bcc     @dot
        cmp     #$7F
        bne     gfn_j
@dot:   lda     #'.'
        jmp     gfn_j
@cont:  cmp     #$80
        bcc     @broken
        cmp     #$C0
        bcs     @broken
        and     #$3F
        sta     u_t
        ldx     #6
@sh:    asl     u_cp
        rol     u_cp+1
        dex
        bne     @sh
        lda     u_cp
        ora     u_t
        sta     u_cp
        dec     u_need
        bne     @r
        jsr     umap
        beq     @r
        jmp     gfn_j
@r:     rts
@broken:pha                     ; the sequence ended early: '?' for it
        lda     #0
        sta     u_need
        lda     #'?'
        jsr     gfn_j
        pla
        jmp     @new

gfn_j:  jmp     $FFFF           ; (set with GFN)

; the character for code point u_cp: A (0 = none, Z set)
umap:   lda     u_big
        bne     @q
        lda     u_cp+1
        bne     @tab
        lda     u_cp
        cmp     #$A0
        bcc     @q
        sbc     #$A0
        tax
        lda     lat1,x
        rts
@tab:   ldx     #0
@l:     lda     umt+1,x
        beq     @q
        cmp     u_cp+1
        bne     @nx
        lda     umt,x
        cmp     u_cp
        bne     @nx
        lda     umt+2,x
        rts
@nx:    inx
        inx
        inx
        bne     @l
@q:     lda     #'?'
        rts

; U+00A0 - U+00FF
lat1:   .byte   ' ', $AD, $9B, $9C, '?', $9D, '|', '?', '"', 'c', $A6, $AE, $AA, '-', 'r', '-'
        .byte   $F8, $F1, $FD, '3', $27, $E6, '?', $FA, ',', '1', $A7, $AF, $AC, $AB, '?', $A8
        .byte   'A', 'A', 'A', 'A', $8E, $8F, $92, $80, 'E', $90, 'E', 'E', 'I', 'I', 'I', 'I'
        .byte   'D', $A5, 'O', 'O', 'O', 'O', $99, 'x', 'O', 'U', 'U', 'U', $9A, 'Y', '?', $E1
        .byte   $85, $A0, $83, 'a', $84, $86, $91, $87, $8A, $82, $88, $89, $8D, $A1, $8C, $8B
        .byte   '?', $A4, $95, $A2, $93, 'o', $94, $F6, 'o', $97, $A3, $96, $81, 'y', '?', $98
; others: code point (low, high), character (0 = shown as nothing)
umt:    .byte   $13,$20,'-',  $14,$20,'-',  $18,$20,$27,  $19,$20,$27,  $1A,$20,$27
        .byte   $1C,$20,'"',  $1D,$20,'"',  $1E,$20,'"',  $22,$20,$F9,  $26,$20,'.'
        .byte   $0B,$20,0,    $FF,$FE,0,    $90,$21,'<',  $92,$21,'>',  $91,$21,'^'
        .byte   $93,$21,'v',  $12,$22,'-',  $64,$22,$F3,  $65,$22,$F2,  $1E,$22,$EC
        .byte   $48,$22,$F7,  $61,$22,$F0,  $1A,$22,$FB,  $13,$27,$FB,  $14,$27,$FB
        .byte   $17,$27,'x',  $18,$27,'x',  $C0,$03,$E3,  $A3,$03,$E4,  $C3,$03,$E5
        .byte   $A9,$03,$EA,  $B1,$03,$E0,  $B2,$03,$E1,  $BC,$03,$E6,  $00,$25,$C4
        .byte   $02,$25,$B3,  $0C,$25,$DA,  $10,$25,$BF,  $14,$25,$C0,  $18,$25,$D9
        .byte   $1C,$25,$C3,  $24,$25,$B4,  $2C,$25,$C2,  $34,$25,$C1,  $3C,$25,$C5
        .byte   $50,$25,$CD,  $51,$25,$BA,  $88,$25,$DB,  $91,$25,$B0,  $92,$25,$B1
        .byte   $93,$25,$B2,  $A0,$25,$FE,  $CF,$25,'o',  $AA,$20,'?'
        .byte   0, 0, 0

; ============================================================================
; the status line: built in sbuf, then shown in reverse on the last row
; ============================================================================
sb_clr: lda     #0
        sta     sblen
        rts

sb_chr: stx     sbx
        ldx     sblen
        cpx     #WIDTH
        bcs     @r
        sta     sbuf,x
        inc     sblen
@r:     ldx     sbx
        rts

sb_str: sta     strp
        sty     strp+1
        ldy     #0
@l:     lda     (strp),y
        beq     @r
        jsr     sb_chr
        iny
        bne     @l
@r:     rts

; spaces up to column A
sb_pad: sta     sbx2
@l:     lda     sblen
        cmp     sbx2
        bcs     @r
        lda     #' '
        jsr     sb_chr
        jmp     @l
@r:     rts

; num (16 bit) in decimal
sb_dec: lda     #0
        sta     dflag
        ldx     #0
@d:     ldy     #'0'
@s:     lda     num
        sec
        sbc     p10lo,x
        sta     dtmp
        lda     num+1
        sbc     p10hi,x
        bcc     @o
        sta     num+1
        lda     dtmp
        sta     num
        iny
        bne     @s
@o:     tya
        cmp     #'0'
        bne     @p
        ldy     dflag
        beq     @n
@p:     jsr     sb_chr
        lda     #1
        sta     dflag
@n:     inx
        cpx     #4
        bne     @d
        lda     num
        ora     #'0'
        jmp     sb_chr
p10lo:  .byte   <10000, <1000, <100, <10
p10hi:  .byte   >10000, >1000, >100, >10

; A in hex
sb_hex: pha
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
        jmp     sb_chr

; a message for the status line, until the next key: A/Y (msg_kind: 0, or
; 1 = then msg_num in decimal, 2 = then msg_num in hex)
set_msg:
        sta     msgp
        sty     msgp+1
        lda     #0
        sta     msg_kind
        lda     #1
        sta     dirty
        rts
set_msg_n:
        jsr     set_msg
        lda     #1
        sta     msg_kind
        rts
set_msg_x:
        jsr     set_msg
        lda     #2
        sta     msg_kind
        rts

draw_status:
        jsr     sb_clr
        lda     #' '
        jsr     sb_chr
        lda     msgp+1
        beq     @info
        lda     msgp
        ldy     msgp+1
        jsr     sb_str
        lda     msg_kind
        bne     @fx28
        jmp     @show
@fx28:
        cmp     #2
        beq     @hx
        MOVW    num, msg_num
        jsr     sb_dec
        jmp     @show
@hx:    lda     #'$'
        jsr     sb_chr
        lda     msg_num
        jsr     sb_hex
        jmp     @show
@info:  lda     vmode
        beq     @ed
        lda     #<view_txt
        ldy     #>view_txt
        jsr     sb_str
@ed:    jsr     sb_name
        lda     modified
        beq     :+
        lda     #<mod_txt
        ldy     #>mod_txt
        jsr     sb_str
:       lda     #32
        jsr     sb_pad
        lda     #<line_txt
        ldy     #>line_txt
        jsr     sb_str
        lda     vmode
        beq     @el
        lda     vl_ok
        bne     :+
        lda     #'?'
        jsr     sb_chr
        jmp     @tot
:       MOVW    num, vline
        jsr     sb_dec
        jmp     @tot
@el:    MOVW    num, cur_line
        jsr     sb_dec
@tot:   lda     big
        beq     :+
        jsr     sb_where
        jmp     @tv
:       lda     #'/'
        jsr     sb_chr
        MOVW    num, nlines
        jsr     sb_dec
@tv:
        lda     vmode
        bne     @vm
        lda     #<col_txt
        ldy     #>col_txt
        jsr     sb_str
        lda     ccol
        clc
        adc     #1
        sta     num
        lda     ccol+1
        adc     #0
        sta     num+1
        jsr     sb_dec
        lda     #WIDTH - 10
        jsr     sb_pad
        lda     #<help_hint
        ldy     #>help_hint
        jsr     sb_str
        jmp     @show
@vm:    lda     big             ; (no room for it with a large file)
        bne     @vh
        lda     #<md_txt
        ldy     #>md_txt
        ldx     mdon
        bne     :+
        lda     #<txt_txt
        ldy     #>txt_txt
:       jsr     sb_str
@vh:    lda     #WIDTH - 25
        jsr     sb_pad
        lda     #<vhint_txt
        ldy     #>vhint_txt
        jsr     sb_str
@show:  lda     #WIDTH
        jsr     sb_pad
        ldx     #TROWS
        ldy     #0
        jsr     goto_rc
        lda     #A_REV
        jsr     set_attr
        ldx     #0
@o:     lda     sbuf,x
        jsr     out
        inx
        cpx     sblen
        bne     @o
        lda     #0
        jmp     set_attr

; the file's name, or [NEW FILE]
sb_name:
        lda     fname
        bne     @n
        lda     #<new_txt
        ldy     #>new_txt
        jmp     sb_str
@n:     lda     #<fname
        ldy     #>fname
        jmp     sb_str

view_txt:   .byte   "VIEW  ", 0
mod_txt:    .byte   " (changed)", 0
new_txt:    .byte   "[new file]", 0
line_txt:   .byte   "Line ", 0
col_txt:    .byte   "  Col ", 0
help_hint:  .byte   "^G = help", 0
md_txt:     .byte   "   markdown", 0
txt_txt:    .byte   "   plain", 0
vhint_txt:  .byte   "Esc: edit  M: md  ^G help", 0

; ============================================================================
; a question on the status line: A/Y = the question; the answer is typed in
; inbuf (it starts with what is in it: inlen bytes).  Carry set if Esc.
; ============================================================================
prompt: sta     prm
        sty     prm+1
        ldx     #TROWS
        ldy     #0
        jsr     goto_rc
        lda     #A_REV
        jsr     set_attr
        lda     #' '
        jsr     out
        lda     prm
        ldy     prm+1
        jsr     prints
        lda     #' '
        jsr     out
        lda     #0
        jsr     set_attr
        lda     #' '
        jsr     out
        ldx     inlen
        lda     #0
        sta     inbuf,x
        PRINT   inbuf
        jsr     clr_eol
@k:     jsr     key_wait
        cmp     #CR
        beq     @ok
        cmp     #LF
        beq     @ok
        cmp     #ESC
        beq     @esc
        cmp     #8
        beq     @bs
        cmp     #$7F
        beq     @bs
        cmp     #' '
        bcc     @k
        cmp     #$7F
        bcs     @k
        ldx     inlen
        cpx     #MAXIN
        bcs     @k
        sta     inbuf,x
        inx
        stx     inlen
        pha
        lda     #0
        sta     inbuf,x
        pla
        jsr     out
        jmp     @k
@bs:    ldx     inlen
        beq     @k
        dex
        stx     inlen
        lda     #0
        sta     inbuf,x
        jsr     csi
        lda     #'D'
        jsr     out
        lda     #' '
        jsr     out
        jsr     csi
        lda     #'D'
        jsr     out
        jmp     @k
@ok:    clc
        bcc     @end
@esc:   sec
@end:   lda     #1
        sta     dirty
        rts

; a Y / N / Esc question: A/Y the text (the name is added): A = 'Y', 'N' or ESC
ask_yn: sta     prm
        sty     prm+1
        ldx     #TROWS
        ldy     #0
        jsr     goto_rc
        lda     #A_REV
        jsr     set_attr
        lda     #' '
        jsr     out
        lda     prm
        ldy     prm+1
        jsr     prints
        lda     #0
        jsr     set_attr
        jsr     clr_eol
@k:     jsr     key_wait
        cmp     #ESC
        beq     @r
        and     #$DF
        cmp     #'Y'
        beq     @r
        cmp     #'N'
        bne     @k
@r:     ldx     #1
        stx     dirty
        rts

; inbuf to upper case
upcase: ldx     #0
@l:     lda     inbuf,x
        beq     @r
        cmp     #'a'
        bcc     @n
        cmp     #'z'+1
        bcs     @n
        and     #$DF
        sta     inbuf,x
@n:     inx
        bne     @l
@r:     rts

; inbuf as a number: num (0 if none or not a number)
in_num: lda     #0
        sta     num
        sta     num+1
        ldx     #0
@l:     lda     inbuf,x
        beq     @r
        sec
        sbc     #'0'
        cmp     #10
        bcs     @bad
        sta     dtmp
        lda     num             ; num = num * 10 + digit
        sta     ktmp
        lda     num+1
        sta     ktmp+1
        asl     num
        rol     num+1
        asl     num
        rol     num+1
        lda     num
        clc
        adc     ktmp
        sta     num
        lda     num+1
        adc     ktmp+1
        sta     num+1
        asl     num
        rol     num+1
        lda     num
        clc
        adc     dtmp
        sta     num
        bcc     :+
        inc     num+1
:       inx
        bne     @l
@bad:   lda     #0
        sta     num
        sta     num+1
@r:     rts

; ============================================================================
; the gap buffer
;   textbuf .. glo-1      the text before the cursor
;   glo .. ghi-1          free
;   ghi .. BUF_END-1      the text after the cursor
; ============================================================================
buf_empty:
        LDW     glo, textbuf
        LDW     ghi, BUF_END
        LDW     cur_line, 1
        LDW     nlines, 1
        LDW     top_line, 1
        lda     #0
        sta     hs
        sta     hs+1
        sta     modified
        sta     wcol_ok
        sta     vmode
        sta     big
        rts

; the next text byte at tp, stepping over the gap: carry set at the end
tgetc:  lda     tp
        cmp     glo
        bne     @n
        lda     tp+1
        cmp     glo+1
        bne     @n
        MOVW    tp, ghi
@n:     lda     tp+1
        cmp     #>BUF_END
        bne     @g
        lda     tp
        cmp     #<BUF_END
        bne     @g
        sec
        rts
@g:     ldy     #0
        lda     (tp),y
        inc     tp
        bne     :+
        inc     tp+1
:       clc
        rts

; A into the text at the cursor: carry set if there is no room
ins_byte:
        pha
        CMPW    glo, ghi
        bne     @ok
        pla
        sec
        rts
@ok:    pla
        ldy     #0
        sta     (glo),y
        INC16   glo
        clc
        rts

; the cursor one byte left / right (cur_line kept): carry set if it can't
mv_left:
        CMPWI   glo, textbuf
        beq     @no
        DEC16   glo
        DEC16   ghi
        ldy     #0
        lda     (glo),y
        sta     (ghi),y
        cmp     #LF
        bne     @r
        DEC16   cur_line
@r:     clc
        rts
@no:    sec
        rts

mv_right:
        CMPWI   ghi, BUF_END
        beq     @no
        ldy     #0
        lda     (ghi),y
        sta     (glo),y
        pha
        INC16   glo
        INC16   ghi
        pla
        cmp     #LF
        bne     @r
        INC16   cur_line
@r:     clc
        rts
@no:    sec
        rts

; the byte before / after the cursor in A: carry set if there is none
peek_back:
        CMPWI   glo, textbuf
        beq     @no
        lda     glo
        sec
        sbc     #1
        sta     zt
        lda     glo+1
        sbc     #0
        sta     zt+1
        ldy     #0
        lda     (zt),y
        clc
        rts
@no:    sec
        rts

peek_fwd:
        CMPWI   ghi, BUF_END
        beq     @no
        ldy     #0
        lda     (ghi),y
        clc
        rts
@no:    sec
        rts

; how many bytes the character after the cursor takes: X (0 at the end)
glen_fwd:
        ldx     #0
        CMPWI   ghi, BUF_END
        beq     @r
        ldy     #0
        lda     (ghi),y
        ldx     #1
        cmp     #$C2
        bcc     @r
        cmp     #$F5
        bcs     @r
        ldy     #1              ; how many may follow
        cmp     #$E0
        bcc     :+
        iny
        cmp     #$F0
        bcc     :+
        iny
:       sty     gl_n
        MOVW    zt, ghi
@l:     INC16   zt
        CMPWI   zt, BUF_END
        beq     @r
        ldy     #0
        lda     (zt),y
        and     #$C0
        cmp     #$80
        bne     @r
        inx
        dec     gl_n
        bne     @l
@r:     rts

; how many bytes the character before the cursor takes: X (0 at the start)
glen_back:
        ldx     #0
        jsr     peek_back       ; (zt = its address)
        bcs     @r
        ldx     #1
        and     #$C0
        cmp     #$80
        bne     @r              ; not a continuation byte
@l:     CMPWI   zt, textbuf
        beq     @one
        DEC16   zt
        inx
        ldy     #0
        lda     (zt),y
        cmp     #$80
        bcc     @one
        cmp     #$C0
        bcc     @more           ; another continuation byte
        cmp     #$C2
        bcc     @one
        cmp     #$F5
        bcs     @one
        ldy     #2              ; a lead byte: is X what it starts?
        cmp     #$E0
        bcc     :+
        iny
        cmp     #$F0
        bcc     :+
        iny
:       sty     gl_n
        cpx     gl_n
        beq     @r
@one:   ldx     #1
@r:     rts
@more:  cpx     #4
        bcc     @l
        bcs     @one

; to the start / end of the cursor's line
to_ls:  jsr     peek_back
        bcs     @r
        cmp     #LF
        beq     @r
        jsr     mv_left
        jmp     to_ls
@r:     rts

to_le:  jsr     peek_fwd
        bcs     @r
        cmp     #LF
        beq     @r
        jsr     mv_right
        jmp     to_le
@r:     rts

; the gap moved cnt bytes left / right, as blocks (cur_line not changed)
gap_left_n:
@l:     lda     cnt
        ora     cnt+1
        beq     @r
        lda     glo
        bne     :+
        dec     glo+1
:       dec     glo
        lda     ghi
        bne     :+
        dec     ghi+1
:       dec     ghi
        ldy     #0
        lda     (glo),y
        sta     (ghi),y
        lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        jmp     @l
@r:     rts

gap_right_n:
@l:     lda     cnt
        ora     cnt+1
        beq     @r
        ldy     #0
        lda     (ghi),y
        sta     (glo),y
        inc     glo
        bne     :+
        inc     glo+1
:       inc     ghi
        bne     :+
        inc     ghi+1
:       lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        jmp     @l
@r:     rts

; the cursor to the start / end of the text
gap_to_start:
        lda     glo
        sec
        sbc     #<textbuf
        sta     cnt
        lda     glo+1
        sbc     #>textbuf
        sta     cnt+1
        jsr     gap_left_n
        LDW     cur_line, 1
        rts

gap_to_end:
        lda     #<BUF_END
        sec
        sbc     ghi
        sta     cnt
        lda     #>BUF_END
        sbc     ghi+1
        sta     cnt+1
        jsr     gap_right_n
        MOVW    cur_line, nlines
        rts

; with the gap at the end: the cursor to offset pos (cur_line not changed)
gap_set:
        lda     glo
        sec
        sbc     #<textbuf
        sta     cnt
        lda     glo+1
        sbc     #>textbuf
        sta     cnt+1
        lda     cnt
        sec
        sbc     pos
        sta     cnt
        lda     cnt+1
        sbc     pos+1
        sta     cnt+1
        jmp     gap_left_n

; the cursor's offset in the text: pos
get_pos:
        lda     glo
        sec
        sbc     #<textbuf
        sta     pos
        lda     glo+1
        sbc     #>textbuf
        sta     pos+1
        rts

; the line feeds from textbuf to glo, plus 1: num  (the cursor's line, with
; the text before it)
count_line:
        LDW     num, 1
        LDW     zt, textbuf
@l:     CMPW    zt, glo
        beq     @r
        ldy     #0
        lda     (zt),y
        cmp     #LF
        bne     :+
        INC16   num
:       INC16   zt
        jmp     @l
@r:     rts

; ============================================================================
; where the cursor is: ls = its line's start, ccol = its column on the screen
; ============================================================================
cur_info:
        MOVW    sp, glo
@b:     CMPWI   sp, textbuf
        beq     @s
        lda     sp
        sec
        sbc     #1
        sta     zt
        lda     sp+1
        sbc     #0
        sta     zt+1
        ldy     #0
        lda     (zt),y
        cmp     #LF
        beq     @s
        MOVW    sp, zt
        jmp     @b
@s:     MOVW    ls, sp
        lda     #0
        sta     col
        sta     col+1
        jsr     dec_reset
        GFN     c_cnt
@f:     CMPW    sp, glo
        beq     @d
        ldy     #0
        lda     (sp),y
        jsr     feed
        INC16   sp
        jmp     @f
@d:     MOVW    ccol, col
        rts

; a character's width: col moved on past it
c_cnt:  cmp     #9
        bne     @one
        lda     col
        ora     #TABW - 1
        sta     col
@one:   INC16   col
        rts

; ============================================================================
; drawing in edit mode
; ============================================================================
; the line at tp on row X; tp then at the next line.  Carry set if the text
; ended (no line after it)
draw_row:
        ldy     #0
        jsr     goto_rc
        lda     #0
        sta     col
        sta     col+1
        jsr     dec_reset
        GFN     r_put
@l:     jsr     tgetc
        bcs     @end
        cmp     #LF
        beq     @lf
        jsr     feed
        jmp     @l
@lf:    jsr     feed_end
        jsr     clr_eol
        clc
        rts
@end:   jsr     feed_end
        jsr     clr_eol
        sec
        rts

; past the line at tp (not drawn): carry set if the text ended
skip_line:
        jsr     tgetc
        bcs     @r
        cmp     #LF
        bne     skip_line
        clc
@r:     rts

; a character on the row, if it is in the columns shown (hs ...)
r_put:  cmp     #9
        bne     r_put1
@t:     lda     #' '
        jsr     r_put1
        lda     col
        and     #TABW - 1
        bne     @t
        rts
r_put1: pha
        CMPW    col, hs
        bcc     @skip
        lda     col
        sec
        sbc     hs
        tax
        lda     col+1
        sbc     hs+1
        bne     @skip
        cpx     #WIDTH
        bcs     @skip
        pla
        jsr     out
        INC16   col
        rts
@skip:  pla
        INC16   col
        rts

; rows to draw: rd_from (and all below it), rd_one, the cursor's row if
; rd_cur; $FF = none
rd_none:
        lda     #$FF
        sta     rd_from
        sta     rd_one
        lda     #0
        sta     rd_cur
        rts

; the cursor's row from rd_from down (its row: 0 if it is above the screen)
rd_from_cur:
        lda     cur_line
        sec
        sbc     top_line
        tax
        lda     cur_line+1
        sbc     top_line+1
        bcc     @z
        bne     @r              ; (below the screen: it will be redrawn whole)
        cpx     #TROWS
        bcs     @r
        cpx     rd_from
        bcs     @r
        stx     rd_from
@r:     lda     #0
        sta     rd_cur
        rts
@z:     lda     #0
        sta     rd_from
        sta     rd_cur
        rts

; the cursor is leaving its line: if it was changed, its row is to be drawn
flush_cur:
        lda     rd_cur
        beq     @r
        jmp     rd_from_cur
@r:     rts

; the start of the top row's line: tp  (crow lines above the cursor's line)
top_ptr:
        MOVW    tp, ls
        ldx     crow
        beq     @r
@l:     DEC16   tp              ; onto the line feed before
@b:     CMPWI   tp, textbuf
        beq     @n
        lda     tp
        sec
        sbc     #1
        sta     zt
        lda     tp+1
        sbc     #0
        sta     zt+1
        ldy     #0
        lda     (zt),y
        cmp     #LF
        beq     @n
        MOVW    tp, zt
        jmp     @b
@n:     dex
        bne     @l
@r:     rts

; bring the screen up to date (when no keys are waiting)
refresh:
        lda     dirty
        bne     :+
        rts
:       lda     #0
        sta     dirty
        lda     vmode
        beq     :+
        jmp     v_refresh
:       jsr     cur_info
        ; the columns: the cursor's must be shown
        CMPW    ccol, hs
        bcc     @hfix
        lda     ccol
        sec
        sbc     hs
        tax
        lda     ccol+1
        sbc     hs+1
        bne     @hfix
        cpx     #WIDTH
        bcc     @hok
@hfix:  lda     ccol            ; hs = ccol - 40, to a multiple of 8, at least 0
        sec
        sbc     #40
        sta     hs
        lda     ccol+1
        sbc     #0
        sta     hs+1
        bcs     :+
        lda     #0
        sta     hs
        sta     hs+1
:       lda     hs
        and     #$F8
        sta     hs
        lda     #0
        sta     rd_from
@hok:   ; the rows: the cursor's line must be on the screen
        lda     cur_line
        sec
        sbc     top_line
        sta     crow
        lda     cur_line+1
        sbc     top_line+1
        bcc     @above
        bne     @center
        lda     crow
        cmp     #TROWS
        bcc     @vok
        bne     @center
.if USE_SCROLL
        lda     rd_from         ; one below: scroll a row, unless all is redrawn
        cmp     #$FF
        bne     @center
        INC16   top_line
        jsr     scr_up
        lda     #TROWS - 1
        sta     rd_one
        sta     crow
        jmp     @vok
.else
        jmp     @center
.endif
@above:
.if USE_SCROLL
        cmp     #$FF            ; one above?
        bne     @center
        lda     crow
        cmp     #$FF
        bne     @center
        lda     rd_from
        cmp     #$FF
        bne     @center
        DEC16   top_line
        jsr     scr_down
        lda     #0
        sta     rd_one
        sta     crow
        jmp     @vok
.endif
@center:lda     cur_line        ; the cursor's line in the middle
        sec
        sbc     #TROWS / 2
        sta     top_line
        lda     cur_line+1
        sbc     #0
        sta     top_line+1
        bcc     @t1
        ora     top_line
        bne     @tok
@t1:    LDW     top_line, 1
@tok:   lda     cur_line
        sec
        sbc     top_line
        sta     crow
        lda     #0
        sta     rd_from
@vok:   ; draw the rows asked for
        jsr     top_ptr
        lda     #0
        sta     eot
        ldx     #0
@rl:    stx     t_row
        lda     rd_from
        cmp     #$FF
        beq     :+
        cpx     rd_from
        bcs     @draw
:       cpx     rd_one
        beq     @draw
        lda     rd_cur
        beq     @skip
        cpx     crow
        beq     @draw
@skip:  lda     eot
        bne     @next
        jsr     skip_line
        rol     eot
        jmp     @next
@draw:  lda     eot
        bne     @blank
        jsr     draw_row
        rol     eot
        jmp     @next
@blank: ldy     #0
        jsr     goto_rc
        jsr     clr_eol
@next:  ldx     t_row
        inx
        cpx     #TROWS
        bne     @rl
        jsr     rd_none
        jsr     draw_status
        ; the cursor where it is
        lda     ccol
        sec
        sbc     hs
        tay
        ldx     crow
        jmp     goto_rc

; ============================================================================
; editing
; ============================================================================
changed:
        lda     #1
        sta     modified
        lda     #0
        sta     wcol_ok
        rts

full_msg:
        MSG     full_txt
        rts

; a character typed
k_char: jsr     ins_byte
        bcs     full_msg
        lda     #1
        sta     rd_cur
        jmp     changed

; Tab: spaces to the next stop
k_tab:  jsr     cur_info
        lda     ccol
        and     #TABW - 1
        eor     #TABW - 1
        tax
        inx
@l:     lda     #' '
        stx     t_n
        jsr     k_char
        ldx     t_n
        dex
        bne     @l
        rts

; Enter: a new line
k_enter:
        jsr     rd_from_cur
        lda     #LF
        jsr     ins_byte
        bcs     full_msg
        INC16   cur_line
        INC16   nlines
        jmp     changed

; Backspace
k_bs:   jsr     peek_back
        bcs     @r
        cmp     #LF
        beq     @join
        jsr     glen_back
@d:     DEC16   glo
        dex
        bne     @d
        lda     #1
        sta     rd_cur
        jmp     changed
@join:  DEC16   glo
        DEC16   cur_line
        DEC16   nlines
        jsr     rd_from_cur
        jmp     changed
@r:     rts

; Del
k_del:  jsr     peek_fwd
        bcs     @r
        cmp     #LF
        beq     @join
        jsr     glen_fwd
@d:     INC16   ghi
        dex
        bne     @d
        lda     #1
        sta     rd_cur
        jmp     changed
@join:  INC16   ghi
        DEC16   nlines
        jsr     rd_from_cur
        jmp     changed
@r:     rts

; Left / Right: a character (over a line end to the next line)
k_left: jsr     glen_back
        cpx     #0
        beq     @r
        stx     t_n
        jsr     peek_back
        cmp     #LF
        bne     :+
        jsr     flush_cur
:       ldx     t_n
@m:     jsr     mv_left
        dex
        bne     @m
        lda     #0
        sta     wcol_ok
@r:     rts

k_right:
        jsr     glen_fwd
        cpx     #0
        beq     @r
        stx     t_n
        jsr     peek_fwd
        cmp     #LF
        bne     :+
        jsr     flush_cur
:       ldx     t_n
@m:     jsr     mv_right
        dex
        bne     @m
        lda     #0
        sta     wcol_ok
@r:     rts

k_home: jsr     to_ls
        lda     #0
        sta     wcol_ok
        rts

k_end:  jsr     to_le
        lda     #0
        sta     wcol_ok
        rts

; the column to keep while going up and down
want_col:
        lda     wcol_ok
        bne     @r
        jsr     cur_info
        MOVW    wcol, ccol
        lda     #1
        sta     wcol_ok
@r:     rts

; from the start of a line, on to the column wcol (or the line's end)
goto_wcol:
        lda     #0
        sta     col
        sta     col+1
@l:     jsr     peek_fwd
        bcs     @r
        cmp     #LF
        beq     @r
        jsr     glen_fwd
        stx     t_len
        MOVW    colsv, col
        jsr     dec_reset
        GFN     c_cnt
        ldy     #0
@f:     lda     (ghi),y
        sty     t_y
        jsr     feed
        ldy     t_y
        iny
        cpy     t_len
        bne     @f
        jsr     feed_end
        CMPW    wcol, col
        bcc     @stop
        ldx     t_len
@m:     jsr     mv_right
        dex
        bne     @m
        jmp     @l
@stop:  MOVW    col, colsv
@r:     rts

; down a line: carry set if there is none
down1:  MOVW    zt, ghi
@s:     CMPWI   zt, BUF_END
        beq     @no
        ldy     #0
        lda     (zt),y
        cmp     #LF
        beq     @go
        INC16   zt
        jmp     @s
@go:    jsr     peek_fwd
        pha
        jsr     mv_right
        pla
        cmp     #LF
        bne     @go
        jsr     goto_wcol
        clc
        rts
@no:    sec
        rts

; up a line: carry set if there is none
up1:    lda     cur_line+1
        bne     @ok
        lda     cur_line
        cmp     #2
        bcc     @no
@ok:    jsr     to_ls
        jsr     mv_left
        jsr     to_ls
        jsr     goto_wcol
        clc
        rts
@no:    sec
        rts

k_down: jsr     flush_cur
        jsr     want_col
        jmp     down1

k_up:   jsr     flush_cur
        jsr     want_col
        jmp     up1

; a page down / up: the cursor and the top line move together
k_pgdn: jsr     flush_cur
        jsr     want_col
        lda     #0
        sta     t_n
@l:     jsr     down1
        bcs     @d
        inc     t_n
        lda     t_n
        cmp     #TROWS - 1
        bne     @l
@d:     lda     top_line
        clc
        adc     t_n
        sta     top_line
        bcc     :+
        inc     top_line+1
:       lda     #0
        sta     rd_from
        rts

k_pgup: jsr     flush_cur
        jsr     want_col
        lda     #0
        sta     t_n
@l:     jsr     up1
        bcs     @d
        inc     t_n
        lda     t_n
        cmp     #TROWS - 1
        bne     @l
@d:     lda     top_line
        sec
        sbc     t_n
        sta     top_line
        lda     top_line+1
        sbc     #0
        sta     top_line+1
        bcc     @one
        ora     top_line
        bne     @r
@one:   LDW     top_line, 1
@r:     lda     #0
        sta     rd_from
        rts

k_top:  jsr     flush_cur
        jsr     gap_to_start
        lda     #0
        sta     wcol_ok
        rts

k_bottom:
        jsr     flush_cur
        jsr     gap_to_end
        lda     #0
        sta     wcol_ok
        rts

; ^K: the cursor's line to the clipboard (again straight after: added to it)
k_cut:  lda     lastkey
        cmp     #$0B
        beq     :+
        lda     #0
        sta     clip_n
        sta     clip_n+1
:       jsr     rd_from_cur
        jsr     to_ls
        CMPWI   ghi, BUF_END
        beq     @r
@l:     CMPWI   ghi, BUF_END
        beq     @ch
        CMPWI   clip_n, CLIP_SIZE
        beq     @full
        lda     #<CLIP
        clc
        adc     clip_n
        sta     zt
        lda     #>CLIP
        adc     clip_n+1
        sta     zt+1
        ldy     #0
        lda     (ghi),y
        sta     (zt),y
        pha
        INC16   clip_n
        INC16   ghi
        pla
        cmp     #LF
        bne     @l
        DEC16   nlines
@ch:    lda     #0
        sta     wcol_ok
        jmp     changed
@full:  jsr     changed
        MSG     clipfull_txt
@r:     rts

; ^U: the clipboard into the text at the cursor
k_paste:
        lda     clip_n
        ora     clip_n+1
        beq     @r
        jsr     rd_from_cur
        LDW     zt, CLIP
        MOVW    cnt, clip_n
@l:     ldy     #0
        lda     (zt),y
        jsr     ins_byte
        bcs     @full
        ldy     #0
        lda     (zt),y
        cmp     #LF
        bne     :+
        INC16   cur_line
        INC16   nlines
:       INC16   zt
        lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        lda     cnt
        ora     cnt+1
        bne     @l
        jmp     changed
@full:  jsr     changed
        jmp     full_msg
@r:     rts

; ^F: find (from after the cursor, round to the start): ^N again
k_find: lda     #0
        ldx     flen
@c:     lda     fbuf,x
        sta     inbuf,x
        dex
        bpl     @c
        lda     flen
        sta     inlen
        lda     #<find_q
        ldy     #>find_q
        jsr     prompt
        bcs     @r
        ldx     inlen
        stx     flen
@s:     lda     inbuf,x
        sta     fbuf,x
        dex
        bpl     @s
        jmp     find_go
@r:     rts

k_next: lda     flen
        beq     k_find
find_go:
        lda     flen
        bne     @fx27
        jmp     @r
@fx27:
        jsr     flush_cur
        jsr     get_pos
        MOVW    fpos, pos
        MOVW    fline, cur_line
        jsr     gap_to_end      ; (the text in one piece)
        ; from the cursor + 1 to the end
        lda     #<textbuf
        clc
        adc     fpos
        sta     sp
        lda     #>textbuf
        adc     fpos+1
        sta     sp+1
        INC16   sp
        MOVW    dp, glo
        jsr     search
        bcc     @found
        ; then from the start to the cursor
        LDW     sp, textbuf
        lda     #<textbuf
        clc
        adc     fpos
        sta     dp
        lda     #>textbuf
        adc     fpos+1
        sta     dp+1
        INC16   dp
        jsr     search
        bcc     @found
        MOVW    pos, fpos       ; not found: back where it was
        jsr     gap_set
        MOVW    cur_line, fline
        MSG     notfound_txt
@r:     rts
@found: lda     sp
        sec
        sbc     #<textbuf
        sta     pos
        lda     sp+1
        sbc     #>textbuf
        sta     pos+1
        jsr     gap_set
        jsr     count_line
        MOVW    cur_line, num
        lda     #0
        sta     wcol_ok
        rts

; fbuf in the text (in one piece, ending at glo): a match starting at sp ..
; dp-1, any case.  Carry clear and sp = it, or carry set
search:
@l:     CMPW    sp, dp
        bcs     @no
        ; does it fit before the end?
        lda     sp
        clc
        adc     flen
        sta     zt
        lda     sp+1
        adc     #0
        sta     zt+1
        CMPW    glo, zt
        bcc     @no
        ldy     #0
@c:     lda     (sp),y
        jsr     lower
        sta     ktmp
        lda     fbuf,y
        jsr     lower
        cmp     ktmp
        bne     @n
        iny
        cpy     flen
        bne     @c
        clc
        rts
@n:     INC16   sp
        jmp     @l
@no:    sec
        rts

lower:  cmp     #'A'
        bcc     @r
        cmp     #'Z'+1
        bcs     @r
        ora     #$20
@r:     rts

; ^L: go to a line
k_goto: lda     #0
        sta     inlen
        lda     #<goto_q
        ldy     #>goto_q
        jsr     prompt
        bcc     @fx26
        jmp     @r
@fx26:
        jsr     in_num
        lda     num
        ora     num+1
        bne     @fx25
        jmp     @r
@fx25:
        CMPW    num, nlines
        bcc     :+
        MOVW    num, nlines
:       MOVW    fline, num
        jsr     flush_cur
        jsr     gap_to_end
        LDW     sp, textbuf     ; the start of line fline
        LDW     cnt, 1
@l:     CMPW    cnt, fline
        beq     @at
@f:     ldy     #0
        lda     (sp),y
        pha
        INC16   sp
        pla
        cmp     #LF
        bne     @f
        INC16   cnt
        jmp     @l
@at:    lda     sp
        sec
        sbc     #<textbuf
        sta     pos
        lda     sp+1
        sbc     #>textbuf
        sta     pos+1
        jsr     gap_set
        MOVW    cur_line, fline
        lda     #0
        sta     wcol_ok
@r:     rts

full_txt:       .byte   "The text buffer is full", 0
clipfull_txt:   .byte   "The clipboard is full (2 KB): cut no more", 0
notfound_txt:   .byte   "Not found", 0
find_q:         .byte   "Find:", 0
goto_q:         .byte   "Go to line:", 0

; ============================================================================
; files
; ============================================================================
; fname_in (upper case) as a path: pbuf = the whole path; dir_root set if the
; file is in the top folder; fo = the name to open (after entering pbuf's
; folder: pbuf is cut at its last "/")
mk_path:
        ldx     #0
        lda     fname_in
        cmp     #'/'
        beq     @abs
        ldy     #0
@c:     lda     cwd_buf,y
        beq     @cd
        sta     pbuf,x
        inx
        iny
        bne     @c
@cd:    lda     #'/'
        sta     pbuf,x
        inx
@abs:   ldy     #0
@n:     lda     fname_in,y
        sta     pbuf,x
        beq     @e
        inx
        iny
        cpx     #PMAX - 1
        bcc     @n
        lda     #0
        sta     pbuf,x
@e:     ldx     #0              ; the last "/"
        ldy     #0
@f:     lda     pbuf,x
        beq     @fd
        cmp     #'/'
        bne     :+
        txa
        tay
:       inx
        bne     @f
@fd:    tya
        bne     @sub
        lda     #1              ; in the top folder: open "/NAME"
        sta     dir_root
        LDW     fo, pbuf
        rts
@sub:   lda     #0
        sta     dir_root
        sta     pbuf,y          ; the folder: pbuf; the name after it
        iny
        tya
        clc
        adc     #<pbuf
        sta     fo
        lda     #>pbuf
        adc     #0
        sta     fo+1
        rts

; the drive ready, in the path's folder: carry set if not (A = what failed)
fs_ready:
        jsr     ch_check
        bcc     :+
        lda     #1
        rts
:       jsr     fs_in
        beq     @ok
        jsr     ch_start
        bcs     @r
        jsr     fs_in
        beq     @ok
        sec
        rts
@ok:    clc
@r:     rts

fs_in:  lda     dir_root
        beq     @sub
        lda     #<root_txt
        ldy     #>root_txt
        jsr     ch_open
        cmp     #ERR_OPEN_DIR
        rts
@sub:   lda     #<pbuf
        ldy     #>pbuf
        jsr     ch_enter
        cmp     #ERR_OPEN_DIR
        rts

; the error message for a drive status A
usb_err:
        sta     msg_num
        lda     #<usberr_txt
        ldy     #>usberr_txt
        jmp     set_msg_x

; is fname (the file's name) a .MD file?  mdon = 1 if so (or if it has no name)
md_auto:
        lda     #1
        sta     mdon
        ldx     #0
@l:     lda     fname,x
        beq     @r
        inx
        cmp     #'.'
        bne     @l
        lda     fname,x
        cmp     #'M'
        bne     @no
        lda     fname+1,x
        cmp     #'D'
        bne     @no
        lda     fname+2,x
        beq     @r
@no:    lda     #0
        sta     mdon
        lda     fname,x         ; (a later ".": look again)
        bne     @l
@r:     rts

; fname_in into fname
take_name:
        ldx     #0
@l:     lda     fname_in,x
        sta     fname,x
        beq     @r
        inx
        bne     @l
@r:     jmp     md_auto

; read the file fname_in
load_file:
        jsr     mk_path
        jsr     fs_ready
        bcs     usb_err
        lda     fo
        ldy     fo+1
        jsr     ch_open
        cmp     #USB_INT_SUCCESS
        beq     @rd
        cmp     #ERR_MISS_FILE
        beq     @new
        cmp     #ERR_OPEN_DIR
        bne     usb_err
        jsr     ch_close
        MSG     isdir_txt
        rts
@new:   jsr     buf_empty
        lda     #1
        sta     crlf
        jsr     take_name
        MSG     newf_txt
        rts
@rd:    jsr     ch_size
        lda     fsize+3
        ora     fsize+2
        bne     :+
        CMPWI   fsize, BUF_END - textbuf
        bcc     @rd2
:       jmp     big_offer
@rd2:   LDW     ch_ptr, textbuf
        LDW     ch_len, BUF_END - textbuf
        jsr     ch_read
        pha
        jsr     ch_close
        pla
        cmp     #USB_INT_SUCCESS
        beq     :+
        pha
        jsr     buf_empty
        pla
        jmp     usb_err
:       CMPWI   ch_got, BUF_END - textbuf
        bne     @fits
        jsr     buf_empty
        MSG     big_txt
        rts
@fits:  jsr     buf_empty
        ; CR LF to LF (a CR alone too), the lines counted
        lda     #0
        sta     crlf
        LDW     sp, textbuf
        LDW     dp, textbuf
        lda     #<textbuf
        clc
        adc     ch_got
        sta     zt
        lda     #>textbuf
        adc     ch_got+1
        sta     zt+1
@c:     CMPW    sp, zt
        beq     @cd
        ldy     #0
        lda     (sp),y
        INC16   sp
        cmp     #CR
        bne     @st
        CMPW    sp, zt
        beq     @lone
        ldy     #0
        lda     (sp),y
        cmp     #LF
        bne     @lone
        lda     #1
        sta     crlf
        jmp     @c
@lone:  lda     #LF
@st:    ldy     #0
        sta     (dp),y
        INC16   dp
        cmp     #LF
        bne     @c
        INC16   nlines
        jmp     @c
@cd:    MOVW    glo, dp
        jsr     gap_to_start
        jsr     take_name
        MOVW    msg_num, nlines
        lda     #<read_txt
        ldy     #>read_txt
        jmp     set_msg_n

; write the text to fname_in: carry set if it failed
save_file:
        jsr     mk_path
        jsr     fs_ready
        bcs     @err
        lda     fo
        ldy     fo+1
        jsr     ch_create
        cmp     #USB_INT_SUCCESS
        bne     @err
        lda     #0
        sta     obuf_n
        LDW     sp, textbuf
        MOVW    zt, glo
        jsr     save_range
        bcs     @werr
        MOVW    sp, ghi
        LDW     zt, BUF_END
        jsr     save_range
        bcs     @werr
        jsr     obuf_flush
        bcs     @werr
        jsr     ch_close_w
        cmp     #USB_INT_SUCCESS
        bne     @err
        lda     #0
        sta     modified
        jsr     take_name
        MOVW    msg_num, nlines
        lda     #<saved_txt
        ldy     #>saved_txt
        jsr     set_msg_n
        clc
        rts
@werr:  pha
        jsr     ch_close_w
        pla
@err:   jsr     usb_err
        sec
        rts

; the bytes sp .. zt-1 to the file (LF as CR LF if crlf): carry set = failed
save_range:
@l:     CMPW    sp, zt
        beq     @ok
        ldy     #0
        lda     (sp),y
        INC16   sp
        cmp     #LF
        bne     @p
        lda     crlf
        beq     @lf
        lda     #CR
        jsr     obyte
        bcs     @r
@lf:    lda     #LF
@p:     jsr     obyte
        bcc     @l
@r:     rts
@ok:    clc
        rts

; a byte to the file, through obuf (256 bytes)
obyte:  ldx     obuf_n
        sta     obuf,x
        inx
        stx     obuf_n
        bne     @r
        LDW     ch_len, 256
        jmp     owrite
@r:     clc
        rts

obuf_flush:
        lda     obuf_n
        beq     @r
        sta     ch_len
        lda     #0
        sta     ch_len+1
        jmp     owrite
@r:     clc
        rts

owrite: LDW     ch_ptr, obuf
        jsr     ch_write
        cmp     #USB_INT_SUCCESS
        bne     @e
        clc
        rts
@e:     sec
        rts

; the files in the monitor's folder, on the screen
list_files:
        jsr     cls
        PRINT   files_txt
        lda     cwd_buf
        bne     :+
        lda     #'/'
        jsr     out
        jmp     @t
:       PRINT   cwd_buf
@t:     lda     #0
        sta     nfiles
        lda     #'*'
        sta     fname_in
        lda     #0
        sta     fname_in+1
        jsr     mk_path
        jsr     fs_ready
        bcs     @e
        lda     #<dir_ent
        sta     ch_entry_fn
        lda     #>dir_ent
        sta     ch_entry_fn+1
        lda     fo
        ldy     fo+1
        jsr     ch_dir
        cmp     #ERR_MISS_FILE
        bne     @e
        lda     nfiles
        bne     @r
        ldx     #2
        ldy     #0
        jsr     goto_rc
        PRINT   nofiles_txt
@r:     rts
@e:     jmp     usb_err

; a directory entry (ch_ent): its name on the screen, 6 to a row
dir_ent:
        lda     ch_ent+11
        and     #$08            ; (the volume's name)
        bne     @r
        lda     ch_ent
        beq     @r
        cmp     #$E5            ; (deleted)
        beq     @r
        cmp     #'.'
        beq     @r
        lda     nfiles
        cmp     #6 * (TROWS - 3)
        bcs     @r
        ldx     #0              ; row 2 + n / 6, column (n mod 6) * 13
        lda     nfiles
@d:     cmp     #6
        bcc     @m
        sbc     #6
        inx
        bne     @d
@m:     sta     t_n
        asl
        asl
        asl
        clc
        adc     t_n
        adc     t_n
        adc     t_n
        adc     t_n
        adc     t_n
        tay
        inx
        inx
        jsr     goto_rc
        ldx     #0
@n:     lda     ch_ent,x
        cmp     #' '
        beq     @x
        jsr     out
        inx
        cpx     #8
        bne     @n
@x:     lda     ch_ent+8
        cmp     #' '
        beq     @dir
        lda     #'.'
        jsr     out
        ldx     #8
@e:     lda     ch_ent,x
        cmp     #' '
        beq     @dir
        jsr     out
        inx
        cpx     #11
        bne     @e
@dir:   lda     ch_ent+11
        and     #$10
        beq     :+
        lda     #'/'
        jsr     out
:       inc     nfiles
@r:     rts

root_txt:       .byte   "/", 0
usberr_txt:     .byte   "USB drive error ", 0
isdir_txt:      .byte   "That is a folder", 0
newf_txt:       .byte   "A new file", 0
big_txt:        .byte   "Too big for EDIT (13 KB at most)", 0
read_txt:       .byte   "Lines read: ", 0
saved_txt:      .byte   "Saved. Lines: ", 0
files_txt:      .byte   "Files in ", 0
nofiles_txt:    .byte   "(none)", 0

; ============================================================================
; VIEW MODE: the text (in one piece: the gap moved to its end) laid out in
; rows, wrapped at words, a .MD file formatted.  The top of the screen is
; vtop (a line's start) and vsub (how many of its rows are above the screen);
; vfence = inside a ``` code block at vtop.
; ============================================================================
; the rows a line takes: lay_line on the line at lp (with lfence) calls
;   row_begin / row_put / row_end; they draw the rows from vfirst to vlast
;   (counted from vrow 0 at the top, after vskip rows not shown at all)

; a row starts: its prefix (X = 0: pre1, the line's first row; 1: pre2)
row_begin:
        lda     #0
        sta     rcol
        sta     rvis
        lda     vcnt
        bne     @pre
        lda     vskip
        bne     @pre
        lda     vrow
        cmp     vfirst
        bcc     @pre
        cmp     vshow
        beq     :+
        bcs     @pre
:       lda     #1
        sta     rvis
        stx     t_px
        ldx     vrow
        ldy     #0
        jsr     goto_rc
        ldx     t_px
@pre:   cpx     #0
        bne     @p2
        ldx     #0
@l1:    cpx     pre1n
        beq     @d
        lda     pre1,x
        stx     t_px
        ldx     #0
        jsr     row_put
        ldx     t_px
        inx
        bne     @l1
@p2:    ldx     #0
@l2:    cpx     pre2n
        beq     @d
        lda     pre2,x
        stx     t_px
        ldx     #0
        jsr     row_put
        ldx     t_px
        inx
        bne     @l2
@d:     lda     rcol
        sta     rstart
        rts

; a character A with attributes X
row_put:
        ldy     rvis
        beq     @n
        pha
        txa
        jsr     set_attr
        pla
        jsr     out
@n:     inc     rcol
        rts

row_end:
        lda     rvis
        beq     @n
        lda     #0
        jsr     set_attr
        jsr     clr_eol
@n:     lda     vskip
        beq     @c
        dec     vskip
        rts
@c:     lda     vrow
        cmp     #$FF
        beq     :+
        inc     vrow
:       lda     vcnt
        bne     @r
        lda     vrow
        cmp     vlast
        beq     @r
        bcc     @r
        lda     #1
        sta     vstop
@r:     rts

; a character to the wrapper: A, attributes X.  Spaces are where rows break.
w_put:  ldy     wmode
        beq     @word
        dey
        beq     @char
        ldy     rcol            ; W_NONE: what doesn't fit is dropped
        cpy     #WIDTH
        bcs     @r
        jmp     row_put
@char:  ldy     rcol            ; W_CHAR: broken anywhere
        cpy     #WIDTH
        bcc     :+
        pha
        txa
        pha
        jsr     row_end
        ldx     #1
        jsr     row_begin
        pla
        tax
        pla
:       jmp     row_put
@word:  cmp     #' '
        beq     @sp
        ldy     wlen
        sta     wb_g,y
        txa
        sta     wb_a,y
        iny
        sty     wlen
        cpy     wmax
        bcc     @r
        jmp     w_flush
@sp:    stx     sp_attr
        jsr     w_flush
        lda     rcol
        cmp     #WIDTH
        bcs     @r
        cmp     rstart          ; (not at a row's start)
        beq     @r
        lda     #' '
        ldx     sp_attr
        jmp     row_put
@r:     rts

; the word so far to the row (to the next row if it doesn't fit)
w_flush:
        lda     wlen
        beq     @r
        clc
        adc     rcol
        cmp     #WIDTH + 1
        bcc     @fit
        lda     rcol
        cmp     rstart
        beq     @fit
        jsr     row_end
        ldx     #1
        jsr     row_begin
@fit:   ldy     #0
@l:     lda     rcol
        cmp     #WIDTH
        bcc     @p
        sty     t_wy
        jsr     row_end
        ldx     #1
        jsr     row_begin
        ldy     t_wy
@p:     lda     wb_a,y
        tax
        lda     wb_g,y
        sty     t_wy
        jsr     row_put
        ldy     t_wy
        iny
        cpy     wlen
        bne     @l
        lda     #0
        sta     wlen
@r:     rts

; the wrapper's characters, through feed: TAB to spaces
g_inl:  cmp     #9
        bne     :+
        lda     #' '
:       pha
        lda     iattr
        ora     battr
        ldx     incode
        beq     :+
        ora     #A_REV
:       tax
        pla
        jmp     w_put

; raw lines (code, plain text): TAB to the next stop
g_raw:  cmp     #9
        bne     @c
@t:     lda     #' '
        ldx     #0
        jsr     w_put
        lda     rcol
        sec
        sbc     rstart
        and     #TABW - 1
        bne     @t
        rts
@c:     ldx     #0
        jmp     w_put

; ---- one line ----------------------------------------------------------------
; lay out the line at lp (fence state lfence): lp then at the next line, carry
; set if it was the last one
lay_line:
        MOVW    zt, lp          ; its end: le
@e:     CMPW    zt, tend
        beq     @eol
        ldy     #0
        lda     (zt),y
        cmp     #LF
        beq     @eol
        INC16   zt
        jmp     @e
@eol:   MOVW    le, zt
        MOVW    lf_at, zt
        CMPW    le, lp          ; (a CR before the LF: not part of the line)
        beq     @ncr
        lda     le
        sec
        sbc     #1
        sta     zt
        lda     le+1
        sbc     #0
        sta     zt+1
        ldy     #0
        lda     (zt),y
        cmp     #CR
        bne     @ncr
        MOVW    le, zt
@ncr:   lda     #0
        sta     battr
        sta     iattr
        sta     incode
        sta     pre1n
        sta     pre2n
        sta     wlen
        sta     table
        lda     #' '
        sta     prevc
        lda     #W_WORD
        sta     wmode
        lda     #WIDTH
        sta     wmax
        jsr     dec_reset
        lda     mdon
        bne     @md
        GFN     g_raw           ; plain text: as it is, wrapped at words
        jmp     @body
@md:    jsr     is_fence
        bcc     @nf
        lda     lfence
        eor     #1
        sta     lfence
        jmp     @blank
@nf:    lda     lfence
        beq     @norm
@code:  lda     #' '            ; code: indented, broken anywhere
        sta     pre1
        sta     pre1+1
        sta     pre2
        sta     pre2+1
        lda     #2
        sta     pre1n
        sta     pre2n
        lda     #W_CHAR
        sta     wmode
        GFN     g_raw
        jmp     @body
@norm:  MOVW    lpsv, lp        ; > quotes
        jsr     sk_sp
        cpx     #4
        bcs     @nq
        cmp     #'>'
        bne     @nq
        INC16   lp
        jsr     at_c
        cmp     #' '
        bne     :+
        INC16   lp
:       lda     #$B3
        jsr     add_pre12
        lda     #' '
        jsr     add_pre12
        jmp     @norm
@nq:    MOVW    lp, lpsv
        jsr     sk_sp           ; X = the spaces before the text
        stx     t_ind
        CMPW    lp, le
        bne     :+
        jmp     @blank
:       jsr     at_c
        cpx     #4
        bcc     @ni
        lda     pre1n           ; 4 spaces in: a nested list item, or code
        sta     t_sty
        jsr     list_item
        lda     pre1n
        cmp     t_sty
        bne     @inl
        ldx     t_ind
        jmp     @code4
@ni:    cmp     #'#'
        bne     @nh
        jsr     heading
        bcc     @inl
@nh:    jsr     is_rule
        bcc     :+
        jmp     @rule
:       jsr     at_c
        cmp     #'|'
        bne     @nt
        lda     #W_NONE
        sta     wmode
        lda     #1
        sta     table
        jsr     is_sep
        bcc     @inl
        lda     #2
        sta     table
        bne     @inl
@nt:    jsr     list_item
        jmp     @inl
@code4: txa                     ; 4 spaces in: code (more kept)
        sec
        sbc     #4
        sta     cnt
        jsr     back_sp
        jmp     @code
@inl:   GFN     g_inl
        ldx     #0
        jsr     row_begin
        jsr     inline
        jmp     @end
@body:  ldx     #0
        jsr     row_begin
@b:     CMPW    lp, le
        beq     @bend
        ldy     #0
        lda     (lp),y
        jsr     feed
        INC16   lp
        jmp     @b
@bend:  jsr     feed_end
@end:   jsr     w_flush
        jsr     row_end
        jmp     @next
@rule:  ldx     #0
        jsr     row_begin
@rl:    lda     rcol
        cmp     #WIDTH
        bcs     @rd
        lda     #$C4
        ldx     #0
        jsr     row_put
        jmp     @rl
@rd:    jsr     row_end
        jmp     @next
@blank: ldx     #0
        jsr     row_begin
        jsr     row_end
@next:  MOVW    lp, lf_at       ; on to the next line
        CMPW    lp, tend
        beq     @last
        INC16   lp
        clc
        rts
@last:  sec
        rts

; the byte at lp (A), or 0 at the line's end
at_c:   CMPW    lp, le
        beq     @z
        ldy     #0
        lda     (lp),y
        rts
@z:     lda     #0
        rts

; past the spaces at lp: X = how many (a tab counts 4), A = the next byte
sk_sp:  ldx     #0
@l:     jsr     at_c
        cmp     #' '
        beq     @s
        cmp     #9
        bne     @r
        inx
        inx
        inx
@s:     inx
        INC16   lp
        jmp     @l
@r:     rts

; lp back cnt bytes
back_sp:
        lda     lp
        sec
        sbc     cnt
        sta     lp
        lda     lp+1
        sbc     #0
        sta     lp+1
        rts

; A on both prefixes
add_pre12:
        ldx     pre1n
        cpx     #40
        bcs     @r
        sta     pre1,x
        inc     pre1n
        ldx     pre2n
        sta     pre2,x
        inc     pre2n
@r:     rts

; t_ind spaces on the prefixes (1: the first row's, 2: both)
ind_pre:
        ldy     t_ind
        beq     @r
@l:     lda     #' '
        jsr     add_pre12
        dey
        bne     @l
@r:     rts

; is the line at lp a ``` (or ~~~) fence?  carry set if so
is_fence:
        MOVW    zt, lp
        ldx     #0
@s:     ldy     #0
        lda     (zt),y
        cmp     #' '
        bne     @c
        INC16   zt
        inx
        cpx     #4
        bcc     @s
        bcs     @no
@c:     cmp     #'`'
        beq     :+
        cmp     #'~'
        bne     @no
:       sta     ktmp
        ldy     #1
        lda     (zt),y
        cmp     ktmp
        bne     @no
        iny
        lda     (zt),y
        cmp     ktmp
        bne     @no
        ; (all 3 before the line's end: le is after them, or there is no le
        ; yet - lines are ended by LF or the text's end)
        lda     zt
        clc
        adc     #3
        sta     zt
        lda     zt+1
        adc     #0
        sta     zt+1
        CMPW    tend, zt
        bcc     @no
        sec
        rts
@no:    clc
        rts

; # heading: battr, the #s skipped; carry clear if it is one
heading:
        MOVW    zt, lp
        ldx     #0
@l:     ldy     #0
        CMPW    zt, le
        beq     @end
        lda     (zt),y
        cmp     #'#'
        bne     @sp
        INC16   zt
        inx
        cpx     #7
        bcc     @l
        bcs     @no
@sp:    cmp     #' '
        bne     @no
@end:   lda     #A_BOLD
        cpx     #3
        bcs     :+
        lda     #A_BOLD | A_UL
        cpx     #2
        beq     :+
        lda     #A_BOLD | A_REV
:       sta     battr
        MOVW    lp, zt
        jsr     sk_sp
        clc
        rts
@no:    sec
        rts

; a rule (--- *** ___ with spaces between): carry set if so
is_rule:
        MOVW    zt, lp
        ldy     #0
        lda     (zt),y
        cmp     #'-'
        beq     :+
        cmp     #'*'
        beq     :+
        cmp     #'_'
        bne     @no
:       sta     ktmp
        ldx     #0
@l:     CMPW    zt, le
        beq     @end
        ldy     #0
        lda     (zt),y
        INC16   zt
        cmp     #' '
        beq     @l
        cmp     ktmp
        bne     @no
        inx
        bne     @l
@end:   cpx     #3
        bcc     @no
        sec
        rts
@no:    clc
        rts

; a table's |---|:--| line: carry set if so
is_sep: MOVW    zt, lp
        ldx     #0
@l:     CMPW    zt, le
        beq     @end
        ldy     #0
        lda     (zt),y
        INC16   zt
        cmp     #'-'
        bne     :+
        inx
        bne     @l
:       cmp     #'|'
        beq     @l
        cmp     #':'
        beq     @l
        cmp     #' '
        beq     @l
        clc
        rts
@end:   cpx     #1
        rts

; "- ", "* ", "+ ", "1. ", "2) ": the prefixes (a bullet, or the number),
; the marker skipped
list_item:
        jsr     at_c
        cmp     #'-'
        bne     @fx24
        jmp     @b
@fx24:
        cmp     #'*'
        bne     @fx23
        jmp     @b
@fx23:
        cmp     #'+'
        bne     @fx22
        jmp     @b
@fx22:
        ; a number?
        MOVW    zt, lp
        ldx     #0
@n:     CMPW    zt, le
        bne     @fx2
        jmp     @no
@fx2:
        ldy     #0
        lda     (zt),y
        cmp     #'0'
        bcc     @nd
        cmp     #'9'+1
        bcs     @nd
        INC16   zt
        inx
        cpx     #4
        bcc     @n
        bcs     @no
@nd:    cpx     #0
        beq     @no
        cmp     #'.'
        beq     :+
        cmp     #')'
        bne     @no
:       ldy     #1              ; and a space
        lda     (zt),y
        cmp     #' '
        bne     @no
        jsr     ind_pre
@nc:    ldy     #0              ; the number to pre1, spaces to pre2
        lda     (lp),y
        INC16   lp
        ldx     pre1n
        sta     pre1,x
        inc     pre1n
        ldx     pre2n
        lda     #' '
        sta     pre2,x
        inc     pre2n
        CMPW    lp, zt
        bne     @nc
        ldy     #0
        lda     (lp),y          ; the . or )
        INC16   lp
        ldx     pre1n
        sta     pre1,x
        inc     pre1n
        ldx     pre2n
        lda     #' '
        sta     pre2,x
        inc     pre2n
        jsr     add_pre12
        jsr     sk_sp
@no:    rts
@b:     ldy     #1              ; a bullet: then a space
        lda     (lp),y
        cmp     #' '
        bne     @no
        INC16   lp
        INC16   lp
        jsr     ind_pre
        lda     #$F9
        ldx     pre1n
        sta     pre1,x
        inc     pre1n
        ldx     pre2n
        lda     #' '
        sta     pre2,x
        inc     pre2n
        lda     #' '
        jsr     add_pre12
        jmp     sk_sp

; ---- inline markdown: lp .. le -------------------------------------------------
inline: lda     #WIDTH
        sec
        sbc     pre2n
        sta     wmax
inl_l:  CMPW    lp, le
        bne     :+
        jmp     feed_end
:       ldy     #0
        lda     (lp),y
        ldx     incode
        bne     @incode
        ldx     table
        beq     :+
        cpx     #2
        beq     @sep
        cmp     #'|'
        beq     @bar
:       cmp     #'\'
        bne     @fx32
        jmp     @esc
@fx32:
        cmp     #'`'
        beq     @tick
        cmp     #'*'
        bne     @fx21
        jmp     @emph
@fx21:
        cmp     #'_'
        bne     @fx20
        jmp     @emph
@fx20:
        cmp     #'['
        bne     @fx19
        jmp     @link
@fx19:
        cmp     #'!'
        bne     @fx18
        jmp     @img
@fx18:
        cmp     #'<'
        bne     @fx17
        jmp     @angle
@fx17:
        cmp     #'~'
        bne     @fx1
        jmp     @tilde
@fx1:
@plain: jsr     feed
        ldy     #0
        lda     (lp),y
        sta     prevc
        INC16   lp
        jmp     inl_l
@incode:cmp     #'`'
        bne     @plain
@tick:  lda     incode
        eor     #1
        sta     incode
        lda     #'`'
        sta     prevc
        INC16   lp
        jmp     inl_l
@bar:   lda     #$B3
        jsr     gfn_j
        INC16   lp
        jmp     inl_l
@sep:   cmp     #'|'            ; a table's |---|---| line
        bne     :+
        lda     #$C5
        bne     @sg
:       cmp     #' '
        bne     :+
        lda     #' '
        bne     @sg
:       lda     #$C4
@sg:    ldx     #0
        jsr     w_put
        INC16   lp
        jmp     inl_l
@esc:   INC16   lp              ; \x: x as it is
        CMPW    lp, le
        bne     :+
        lda     #'\'
        jmp     gfn_j
:       ldy     #0
        lda     (lp),y
        jmp     @plain
@tilde: ldy     #1              ; ~~ (struck out): shown plain
        lda     (lp),y
        cmp     #'~'
        beq     :+
        lda     #'~'
        jmp     @plain
:       INC16   lp
        INC16   lp
        jmp     inl_l
@emph:  jmp     emph
@link:  jmp     link
@img:   ldy     #1
        lda     (lp),y
        cmp     #'['
        beq     :+
        lda     #'!'
        jmp     @plain
:       INC16   lp
        jsr     link_try
        bcc     :+
        lda     #'!'            ; not a link after all
        jsr     gfn_j
:       jmp     inl_l
@angle: jsr     angle
        jmp     inl_l

; * _ ** __ *** ___ : emphasis on or off
emph:   sta     ktmp            ; the character
        MOVW    zt, lp
        ldx     #0
@c:     CMPW    zt, le
        beq     @cd
        ldy     #0
        lda     (zt),y
        cmp     ktmp
        bne     @cd
        INC16   zt
        inx
        cpx     #3
        bcc     @c
@cd:    stx     t_n             ; the run's length
        lda     #A_UL
        cpx     #1
        beq     :+
        lda     #A_BOLD
        cpx     #2
        beq     :+
        lda     #A_BOLD | A_UL
:       sta     t_sty
        ; the character after the run (' ' at the end)
        lda     #' '
        CMPW    zt, le
        beq     :+
        ldy     #0
        lda     (zt),y
:       sta     t_nx
        lda     iattr
        and     t_sty
        cmp     t_sty
        beq     @close
        ; opening: not before a space; "_" not inside a word
        lda     t_nx
        cmp     #' '
        beq     @lit
        lda     ktmp
        cmp     #'_'
        bne     @on
        lda     prevc
        jsr     is_alnum
        bcs     @lit
@on:    lda     iattr
        ora     t_sty
        sta     iattr
        jmp     @skip
@close: lda     prevc           ; closing: not after a space
        cmp     #' '
        beq     @lit
        lda     ktmp
        cmp     #'_'
        bne     @off
        lda     t_nx
        jsr     is_alnum
        bcs     @lit
@off:   lda     t_sty
        eor     #$FF
        and     iattr
        sta     iattr
@skip:  lda     ktmp
        sta     prevc
        MOVW    lp, zt
        jmp     inl_l
@lit:   ldx     t_n             ; just the characters
@ll:    lda     ktmp
        stx     t_n
        jsr     gfn_j
        ldx     t_n
        dex
        bne     @ll
        lda     ktmp
        sta     prevc
        MOVW    lp, zt
        jmp     inl_l

; carry set if A is a letter or a digit
is_alnum:
        cmp     #'0'
        bcc     @no
        cmp     #'9'+1
        bcc     @yes
        and     #$DF
        cmp     #'A'
        bcc     @no
        cmp     #'Z'+1
        bcc     @yes
@no:    clc
        rts
@yes:   sec
        rts

link:   jsr     link_try
        bcc     :+
        lda     #'['
        jsr     gfn_j
        INC16   lp
:       jmp     inl_l

; [text](address) at lp: the text underlined, the address not shown, lp past
; it; carry clear.  Carry set (lp unchanged) if it isn't one.
link_try:
        MOVW    zt, lp          ; the ]
        INC16   zt
@b:     CMPW    zt, le
        bne     @fx16
        jmp     @no
@fx16:
        ldy     #0
        lda     (zt),y
        cmp     #']'
        beq     @rb
        INC16   zt
        jmp     @b
@rb:    MOVW    lk_end, zt
        INC16   zt              ; then (
        CMPW    zt, le
        beq     @no
        ldy     #0
        lda     (zt),y
        cmp     #'('
        bne     @no
@p:     CMPW    zt, le          ; and )
        beq     @no
        ldy     #0
        lda     (zt),y
        cmp     #')'
        beq     @ok
        INC16   zt
        jmp     @p
@ok:    INC16   zt
        MOVW    lk_next, zt
        INC16   lp
        lda     iattr
        pha
        ora     #A_UL
        sta     iattr
@t:     CMPW    lp, lk_end
        beq     @te
        ldy     #0
        lda     (lp),y
        jsr     feed
        INC16   lp
        jmp     @t
@te:    pla
        sta     iattr
        MOVW    lp, lk_next
        lda     #')'
        sta     prevc
        clc
        rts
@no:    sec
        rts

; <...>: <http://x> or <a@b> shown underlined; an HTML tag <b> </p> <br/>
; not shown; else the <
angle:  MOVW    zt, lp
        INC16   zt
@f:     CMPW    zt, le
        beq     @lit
        ldy     #0
        lda     (zt),y
        cmp     #'>'
        beq     @got
        INC16   zt
        jmp     @f
@got:   MOVW    lk_end, zt
        ldy     #1
        lda     (lp),y
        jsr     is_alnum
        bcs     @ok
        cmp     #'/'
        beq     @tag
        cmp     #'!'
        beq     @tag
@lit:   lda     #'<'
        jsr     gfn_j
        INC16   lp
        rts
@ok:    ; an address (has : or @) or a tag
        MOVW    zt, lp
@a:     INC16   zt
        CMPW    zt, lk_end
        beq     @tag
        ldy     #0
        lda     (zt),y
        cmp     #':'
        beq     @addr
        cmp     #'@'
        beq     @addr
        jmp     @a
@tag:   MOVW    lp, lk_end      ; (not shown)
        INC16   lp
        rts
@addr:  INC16   lp
        lda     iattr
        pha
        ora     #A_UL
        sta     iattr
@t:     CMPW    lp, lk_end
        beq     @te
        ldy     #0
        lda     (lp),y
        jsr     feed
        INC16   lp
        jmp     @t
@te:    pla
        sta     iattr
        INC16   lp
        rts

; ---- the screen in view mode ---------------------------------------------------
; the rows from vtop (vsub of them not shown): rows vfirst .. vshow drawn.
; v_end = the text's end is on the screen; v_blank = the empty rows after it
v_render:
        MOVW    lp, vtop
        lda     vfence
        sta     lfence
        lda     vsub
        sta     vskip
        lda     #0
        sta     vrow
        sta     vstop
        sta     vcnt
        sta     v_end
        sta     v_blank
        lda     #TROWS - 1
        sta     vlast
@l:     jsr     lay_line
        bcs     @last
        lda     vstop
        beq     @l
        rts
@last:  lda     big
        beq     :+
        lda     weof
        beq     @r
:       lda     vrow
        cmp     #TROWS + 1
        bcs     @r
        lda     #1
        sta     v_end
        lda     #TROWS
        sec
        sbc     vrow
        sta     v_blank
@bl:    lda     vrow            ; the rows after the end: empty
        cmp     #TROWS
        bcs     @r
        cmp     vfirst
        bcc     @nb
        cmp     vshow
        beq     :+
        bcs     @nb
:       tax
        ldy     #0
        jsr     goto_rc
        jsr     clr_eol
@nb:    inc     vrow
        bne     @bl
@r:     rts

; how many rows the line at lp takes (lfence its fence state): A
line_rows:
        lda     #1
        sta     vcnt
        lda     #0
        sta     vrow
        sta     vskip
        jsr     lay_line
        lda     #0
        sta     vcnt
        lda     vrow
        rts

; the rows of vtop's line: A (kept until vtop changes)
vt_rows_get:
        lda     vt_ok
        bne     @r
        MOVW    lp, vtop
        lda     vfence
        sta     lfence
        jsr     line_rows
        sta     vt_rows
        lda     #1
        sta     vt_ok
@r:     lda     vt_rows
        rts

; lp on to the next line's start: carry set if there is none
next_line:
@l:     CMPW    lp, tend
        beq     @no
        ldy     #0
        lda     (lp),y
        INC16   lp
        cmp     #LF
        bne     @l
        clc
        rts
@no:    sec
        rts

; does the line at lp open or close a code block?  A = 1 if so
fence_bit:
        lda     mdon
        beq     @z
        jsr     is_fence
        lda     #0
        rol
        rts
@z:     lda     #0
        rts

; the top a row down / up: carry set if it can't
v_down1:
        jsr     win_check
        jsr     vt_rows_get
        ldx     vsub
        inx
        txa
        cmp     vt_rows
        bcs     @nl
        inc     vsub
        clc
        rts
@nl:    MOVW    lp, vtop
        jsr     fence_bit
        sta     t_f
        MOVW    lp, vtop
        jsr     next_line
        bcs     @no
        MOVW    vtop, lp
        lda     vfence
        eor     t_f
        sta     vfence
        INC16   vline
        lda     #0
        sta     vsub
        sta     vt_ok
        clc
@no:    rts

v_up1:  jsr     win_check
        lda     vsub
        beq     @pl
        dec     vsub
        clc
        rts
@pl:    CMPW    vtop, tstart
        beq     @no
        lda     vtop            ; back over the line feed, to the line's start
        sec
        sbc     #1
        sta     lp
        lda     vtop+1
        sbc     #0
        sta     lp+1
@b:     CMPWI   lp, textbuf
        beq     @s
        lda     lp
        sec
        sbc     #1
        sta     zt
        lda     lp+1
        sbc     #0
        sta     zt+1
        ldy     #0
        lda     (zt),y
        cmp     #LF
        beq     @s
        MOVW    lp, zt
        jmp     @b
@s:     MOVW    vtop, lp
        DEC16   vline
        jsr     fence_bit
        eor     vfence
        sta     vfence
        lda     #0
        sta     vt_ok
        jsr     vt_rows_get
        sec
        sbc     #1
        sta     vsub
        clc
        rts
@no:    sec
        rts

; the fence state at vtop: from the start
v_fence_at:
        MOVW    lp, tstart
        lda     #0
        sta     vfence
@l:     CMPW    lp, vtop
        beq     @r
        jsr     fence_bit
        eor     vfence
        sta     vfence
        jsr     next_line
        bcc     @l
@r:     rts

v_refresh:
        lda     v_full
        bne     @full
        lda     v_mv
        beq     @st
        cmp     #1
        bne     @up
.if USE_SCROLL
        jsr     scr_up          ; a row down: the rest moves up, one row drawn
        lda     #TROWS - 1
        sta     vfirst
        sta     vshow
        jsr     v_render
        jmp     @st
.else
        jmp     @full
.endif
@up:
.if USE_SCROLL
        jsr     scr_down
        lda     #0
        sta     vfirst
        sta     vshow
        jsr     v_render
        jmp     @st
.endif
@full:  jsr     v_full_draw
        lda     v_blank         ; empty rows at the bottom: back up to fill them
        beq     @st
        sta     t_n
        lda     #0
        sta     t_f
@fu:    jsr     v_up1
        bcs     @fr
        inc     t_f
        dec     t_n
        bne     @fu
@fr:    lda     t_f
        beq     @st
        jsr     v_full_draw
@st:    lda     #0
        sta     v_full
        sta     v_mv
        jsr     draw_status
        ldx     #TROWS
        ldy     #WIDTH
        jmp     goto_rc

v_full_draw:
        lda     #0
        sta     vfirst
        lda     #TROWS - 1
        sta     vshow
        jmp     v_render

; ---- into and out of view mode --------------------------------------------------
k_view: jsr     flush_cur
        jsr     get_pos
        MOVW    v_pos, pos
        MOVW    v_cl, cur_line
        MOVW    v_tl, top_line
        jsr     gap_to_end
        MOVW    tend, glo
        LDW     lp, textbuf     ; vtop = the start of the top line
        LDW     cnt, 1
@l:     CMPW    cnt, top_line
        bcs     @at
        jsr     next_line
        bcs     @at
        INC16   cnt
        jmp     @l
@at:    MOVW    vtop, lp
        MOVW    vline, cnt
        LDW     tstart, textbuf
        lda     #1
        sta     vl_ok
        jsr     v_fence_at
        lda     #0
        sta     vsub
        sta     vt_ok
        sta     v_moved
        sta     v_mv
        lda     #1
        sta     vmode
        sta     v_full
        sta     dirty
        rts

; back to editing: at the line on top if the view was moved, else as it was
v_leave:
        lda     big
        beq     :+
        MSG     bigro_txt
        rts
:       lda     v_moved
        beq     @back
        lda     vtop
        sec
        sbc     #<textbuf
        sta     pos
        lda     vtop+1
        sbc     #>textbuf
        sta     pos+1
        MOVW    cur_line, vline
        MOVW    top_line, vline
        jmp     @set
@back:  MOVW    pos, v_pos
        MOVW    cur_line, v_cl
        MOVW    top_line, v_tl
@set:   jsr     gap_set
        lda     #0
        sta     vmode
        sta     wcol_ok
        sta     rd_from
        lda     #1
        sta     dirty
        rts

; ---- view mode keys -------------------------------------------------------------
vw_key: cmp     #K_DN
        bne     @fx31
        jmp     v_kdn
@fx31:
        cmp     #'j'
        bne     @fx33
        jmp     v_kdn
@fx33:
        cmp     #K_UP
        bne     @fx30
        jmp     v_kup
@fx30:
        cmp     #'k'
        bne     @fx29
        jmp     v_kup
@fx29:
        cmp     #K_PGDN
        bne     @fx15
        jmp     v_pgdn
@fx15:
        cmp     #' '
        bne     @fx14
        jmp     v_pgdn
@fx14:
        cmp     #$16            ; ^V
        bne     @fx13
        jmp     v_pgdn
@fx13:
        cmp     #K_PGUP
        bne     @fx12
        jmp     v_pgup
@fx12:
        cmp     #$19            ; ^Y
        bne     @fx11
        jmp     v_pgup
@fx11:
        cmp     #K_HOME
        bne     @fx10
        jmp     v_home
@fx10:
        cmp     #$14            ; ^T
        bne     @fx9
        jmp     v_home
@fx9:
        cmp     #K_END
        bne     @fx8
        jmp     v_endk
@fx8:
        cmp     #$02            ; ^B
        bne     @fx7
        jmp     v_endk
@fx7:
        cmp     #ESC
        bne     @fx6
        jmp     v_leave
@fx6:
        cmp     #$12            ; ^R
        bne     @fx5
        jmp     v_leave
@fx5:
        cmp     #$11            ; ^Q
        bne     :+
        jmp     k_quit
:       cmp     #$13            ; ^S
        bne     :+
        lda     big
        beq     @fx1
        jmp     v_leave
@fx1:
        jmp     k_save
:       cmp     #$0F            ; ^O
        bne     :+
        jmp     k_open
:       cmp     #$07            ; ^G
        bne     :+
        jmp     k_help
:       and     #$DF
        cmp     #'B'
        beq     v_pgup
        cmp     #'E'
        bne     @fx4
        jmp     v_leave
@fx4:
        cmp     #'M'
        bne     @fx3
        jmp     v_md
@fx3:
        rts

v_kdn:  lda     #1
        sta     v_moved
        lda     v_mv
        ora     v_full
        bne     @many
        lda     v_end           ; (the end on the screen: no further)
        bne     @r
        jsr     v_down1
        bcs     @r
        lda     #1
        sta     v_mv
@r:     rts
@many:  jsr     v_down1
        bcs     @r
        lda     #1
        sta     v_full
        rts

v_kup:  lda     #1
        sta     v_moved
        lda     v_mv
        ora     v_full
        bne     @many
        jsr     v_up1
        bcs     @r
        lda     #$FF
        sta     v_mv
@r:     rts
@many:  jsr     v_up1
        bcs     @r
        lda     #1
        sta     v_full
        rts

v_pgdn: lda     #TROWS - 1
        sta     t_n
@l:     jsr     v_down1
        bcs     v_moved_full
        dec     t_n
        bne     @l
v_moved_full:
        lda     #1
        sta     v_moved
        sta     v_full
        rts

v_pgup: lda     #TROWS - 1
        sta     t_n
@l:     jsr     v_up1
        bcs     v_moved_full
        dec     t_n
        bne     @l
        beq     v_moved_full

v_home: lda     big
        beq     :+
        jsr     big_home
        jmp     v_moved_full
:       MOVW    vtop, textbuf_w
        LDW     vline, 1
        lda     #0
        sta     vsub
        sta     vfence
        sta     vt_ok
        beq     v_moved_full

v_endk: lda     big
        beq     v_endl
        jsr     big_end
v_endl: MOVW    lp, vtop        ; to the last line
        jsr     fence_bit
        sta     t_f
        MOVW    lp, vtop
        jsr     next_line
        bcs     @last
        MOVW    vtop, lp
        lda     vfence
        eor     t_f
        sta     vfence
        INC16   vline
        jmp     v_endl
@last:  lda     #0
        sta     vt_ok
        jsr     vt_rows_get     ; its last row on top, then a screen back
        sec
        sbc     #1
        sta     vsub
        lda     #TROWS - 1
        sta     t_n
@u:     jsr     v_up1
        bcc     @fx2
        jmp     v_moved_full
@fx2:
        dec     t_n
        bne     @u
        bne     @fx1
        jmp     v_moved_full
@fx1:

; M: markdown formatting on / off
v_md:   lda     mdon
        eor     #1
        sta     mdon
        jsr     v_fence_at
        lda     #0
        sta     vsub
        sta     vt_ok
        lda     #1
        sta     v_full
        rts

textbuf_w:  .word   textbuf

; ============================================================================
; LARGE FILES: read-only, in view mode, through a window
;   The buffer holds a piece of the file: file offset wbase is at textbuf.
;   tstart .. tend-1 are whole lines (a partial line at either end is left
;   out).  Scrolling near the window's ends moves it: the far part is
;   dropped and the next piece read from the drive.
; ============================================================================
MARGIN_F        = 5120          ; less than this after the top: read on
MARGIN_B        = 2048          ; less than this before the top: read back
BACK_KEEP       = 4096          ; what is kept above the top when reading on
BACK_READ       = 6144          ; how much is read back at a time

; the file's size from the drive (the file open): fsize
ch_size:
        lda     #$0C            ; GET_FILE_SIZE
        jsr     ch_cmd
        lda     #$68
        jsr     ch_wr
        ldx     #0
@l:     jsr     ch_rd
        sta     fsize,x
        inx
        cpx     #4
        bne     @l
        rts

; the file (open, too big to edit): view it?
big_offer:
        jsr     ch_close
        lda     #<bigq_txt
        ldy     #>bigq_txt
        jsr     ask_yn
        cmp     #'Y'
        beq     @y
        MSG     big_txt
        rts
@y:     jsr     buf_empty
        jsr     take_name
        lda     #1
        sta     big
        jsr     big_home
        bcc     :+
        pha
        jsr     buf_empty
        pla
        jmp     usb_err
:       lda     #0
        sta     v_moved
        sta     v_mv
        lda     #1
        sta     vmode
        sta     v_full
        sta     dirty
        rts

; the window at the file's start / end
big_home:
        lda     #0
        sta     wbase
        sta     wbase+1
        sta     wbase+2
        jsr     win_full
        php
        MOVW    vtop, tstart
        LDW     vline, 1
        lda     #1
        sta     vl_ok
        lda     #0
        sta     vsub
        sta     vfence
        sta     vt_ok
        plp
        rts

big_end:
        lda     fsize           ; wbase = the size - the buffer's
        sec
        sbc     #<(BUF_END - textbuf)
        sta     wbase
        lda     fsize+1
        sbc     #>(BUF_END - textbuf)
        sta     wbase+1
        lda     fsize+2
        sbc     #0
        sta     wbase+2
        jsr     win_full
        MOVW    vtop, tstart
        lda     #0
        sta     vl_ok           ; (the line numbers aren't known from here)
        sta     vsub
        sta     vfence
        sta     vt_ok
        rts

; the window read whole, from wbase: carry set (A) if the drive failed
win_full:
        lda     wbase
        sta     io_off
        lda     wbase+1
        sta     io_off+1
        lda     wbase+2
        sta     io_off+2
        LDW     io_ptr, textbuf
        LDW     io_len, BUF_END - textbuf
        jsr     win_io
        bcs     @r
        lda     #<textbuf
        clc
        adc     ch_got
        sta     tend
        lda     #>textbuf
        adc     ch_got+1
        sta     tend+1
        lda     #0
        sta     weof
        CMPWI   ch_got, BUF_END - textbuf
        beq     :+
        inc     weof
:       LDW     tstart, textbuf
        jsr     skip_head
        jsr     trim_tail
        clc
@r:     rts

; read io_len bytes from file offset io_off to io_ptr (the file opened
; afresh: nothing else has to keep it open): ch_got; carry set (A) if failed
win_io: ldx     #0
@c:     lda     fname,x
        sta     fname_in,x
        beq     :+
        inx
        bne     @c
:       jsr     mk_path
        jsr     fs_ready
        bcs     @r
        lda     fo
        ldy     fo+1
        jsr     ch_open
        cmp     #USB_INT_SUCCESS
        bne     @e
        lda     io_off
        sta     ch_off
        lda     io_off+1
        sta     ch_off+1
        lda     io_off+2
        sta     ch_off+2
        lda     #0
        sta     ch_off+3
        jsr     ch_seek
        cmp     #USB_INT_SUCCESS
        bne     @ec
        MOVW    ch_ptr, io_ptr
        MOVW    ch_len, io_len
        jsr     ch_read
        pha
        jsr     ch_close
        pla
        cmp     #USB_INT_SUCCESS
        bne     @e
        clc
        rts
@ec:    pha
        jsr     ch_close
        pla
@e:     sec
@r:     rts

; past a partial first line (unless the window starts the file)
skip_head:
        lda     wbase
        ora     wbase+1
        ora     wbase+2
        beq     @r
        MOVW    zt, tstart
@l:     CMPW    zt, tend
        beq     @r              ; (no line end at all: kept as it is)
        ldy     #0
        lda     (zt),y
        INC16   zt
        cmp     #LF
        bne     @l
        MOVW    tstart, zt
@r:     rts

; a partial last line left out (unless the window reaches the file's end)
trim_tail:
        lda     weof
        bne     @r
        MOVW    zt, tend
@l:     CMPW    zt, tstart
        beq     @r
        lda     zt
        sec
        sbc     #1
        sta     sp
        lda     zt+1
        sbc     #0
        sta     sp+1
        ldy     #0
        lda     (sp),y
        cmp     #LF
        beq     @c
        MOVW    zt, sp
        jmp     @l
@c:     MOVW    tend, zt
@r:     rts

; the file offset of the address in zt: off (3 bytes)
p2off:  lda     zt
        sec
        sbc     #<textbuf
        sta     off
        lda     zt+1
        sbc     #>textbuf
        sta     off+1
        lda     off
        clc
        adc     wbase
        sta     off
        lda     off+1
        adc     wbase+1
        sta     off+1
        lda     wbase+2
        adc     #0
        sta     off+2
        rts

; cnt bytes from sp to dp (either way round)
mmove:  CMPW    dp, sp
        beq     @r
        bcs     @down
@up:    lda     cnt             ; dp below sp: from the start
        ora     cnt+1
        beq     @r
        ldy     #0
        lda     (sp),y
        sta     (dp),y
        INC16   sp
        INC16   dp
        lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        jmp     @up
@down:  lda     sp              ; dp above sp: from the end
        clc
        adc     cnt
        sta     sp
        lda     sp+1
        adc     cnt+1
        sta     sp+1
        lda     dp
        clc
        adc     cnt
        sta     dp
        lda     dp+1
        adc     cnt+1
        sta     dp+1
@dl:    lda     cnt
        ora     cnt+1
        beq     @r
        DEC16   sp
        DEC16   dp
        ldy     #0
        lda     (sp),y
        sta     (dp),y
        lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        jmp     @dl
@r:     rts

; near the window's ends?  Move it.
win_check:
        lda     big
        beq     @r
        lda     weof
        bne     @b
        lda     tend            ; tend - vtop < MARGIN_F: read on
        sec
        sbc     vtop
        lda     tend+1
        sbc     vtop+1
        cmp     #>MARGIN_F
        bcs     @b
        jsr     win_fwd
@b:     lda     vtop            ; vtop - tstart < MARGIN_B: read back
        sec
        sbc     tstart
        lda     vtop+1
        sbc     tstart+1
        cmp     #>MARGIN_B
        bcs     @r
        jsr     win_back
@r:     rts

; on: keep from the line start BACK_KEEP before the top, read what follows
win_fwd:
        lda     vtop
        sec
        sbc     #<BACK_KEEP
        sta     zt
        lda     vtop+1
        sbc     #>BACK_KEEP
        sta     zt+1
        bcc     @ts
        CMPW    zt, tstart
        bcs     @s
@ts:    MOVW    zt, tstart
        jmp     @have
@s:     CMPW    zt, vtop        ; on to a line's start
        bcs     @have
        ldy     #0
        lda     (zt),y
        INC16   zt
        cmp     #LF
        bne     @s
@have:  CMPWI   zt, textbuf
        bne     :+
        rts                     ; (nothing to drop)
:       MOVW    ns, zt
        jsr     p2off           ; the new wbase
        ldx     #2
:       lda     off,x
        sta     nwb,x
        dex
        bpl     :-
        MOVW    zt, tend        ; where the reading goes on
        jsr     p2off
        lda     tend            ; kk = what is kept
        sec
        sbc     ns
        sta     kk
        lda     tend+1
        sbc     ns+1
        sta     kk+1
        MOVW    sp, ns
        LDW     dp, textbuf
        MOVW    cnt, kk
        jsr     mmove
        lda     vtop            ; vtop moves down as much
        sec
        sbc     ns
        sta     vtop
        lda     vtop+1
        sbc     ns+1
        sta     vtop+1
        lda     vtop
        clc
        adc     #<textbuf
        sta     vtop
        lda     vtop+1
        adc     #>textbuf
        sta     vtop+1
        ldx     #2
:       lda     nwb,x
        sta     wbase,x
        lda     off,x
        sta     io_off,x
        dex
        bpl     :-
        lda     #<textbuf
        clc
        adc     kk
        sta     io_ptr
        lda     #>textbuf
        adc     kk+1
        sta     io_ptr+1
        lda     #<(BUF_END - textbuf)
        sec
        sbc     kk
        sta     io_len
        lda     #>(BUF_END - textbuf)
        sbc     kk+1
        sta     io_len+1
        LDW     tstart, textbuf
        jsr     win_io
        bcc     :+
        jsr     usb_err
        LDW     ch_got, 0
        lda     #1              ; (don't try again and again)
        sta     weof
        bne     @t
:       lda     #0
        sta     weof
        CMPW    ch_got, io_len
        beq     @t
        inc     weof
@t:     lda     io_ptr
        clc
        adc     ch_got
        sta     tend
        lda     io_ptr+1
        adc     ch_got+1
        sta     tend+1
        jmp     trim_tail

; back: read up to BACK_READ before the window, keep what fits after it
win_back:
        MOVW    zt, tstart
        jsr     p2off
        lda     off
        ora     off+1
        ora     off+2
        bne     :+
        rts                     ; (the file's start is in)
:       LDW     dd, BACK_READ   ; dd = min(off, BACK_READ)
        lda     off+2
        bne     :+
        CMPWI   off, BACK_READ
        bcs     :+
        MOVW    dd, off
:       lda     off             ; the new wbase = off - dd
        sec
        sbc     dd
        sta     nwb
        lda     off+1
        sbc     dd+1
        sta     nwb+1
        lda     off+2
        sbc     #0
        sta     nwb+2
        lda     tend            ; kk = the lines kept: min(tend - tstart, size - dd)
        sec
        sbc     tstart
        sta     kk
        lda     tend+1
        sbc     tstart+1
        sta     kk+1
        lda     #0
        sta     cut
        lda     #<(BUF_END - textbuf)
        sec
        sbc     dd
        sta     cnt
        lda     #>(BUF_END - textbuf)
        sbc     dd+1
        sta     cnt+1
        CMPW    kk, cnt
        bcc     :+
        beq     :+
        MOVW    kk, cnt
        inc     cut
:       MOVW    sp, tstart      ; up to textbuf + dd
        lda     #<textbuf
        clc
        adc     dd
        sta     dp
        lda     #>textbuf
        adc     dd+1
        sta     dp+1
        MOVW    cnt, kk
        jsr     mmove
        lda     vtop            ; vtop = vtop - tstart + textbuf + dd
        sec
        sbc     tstart
        sta     vtop
        lda     vtop+1
        sbc     tstart+1
        sta     vtop+1
        lda     vtop
        clc
        adc     #<textbuf
        sta     vtop
        lda     vtop+1
        adc     #>textbuf
        sta     vtop+1
        lda     vtop
        clc
        adc     dd
        sta     vtop
        lda     vtop+1
        adc     dd+1
        sta     vtop+1
        lda     #<textbuf       ; tend = textbuf + dd + kk
        clc
        adc     dd
        sta     tend
        lda     #>textbuf
        adc     dd+1
        sta     tend+1
        lda     tend
        clc
        adc     kk
        sta     tend
        lda     tend+1
        adc     kk+1
        sta     tend+1
        ldx     #2
:       lda     nwb,x
        sta     wbase,x
        sta     io_off,x
        dex
        bpl     :-
        LDW     io_ptr, textbuf
        MOVW    io_len, dd
        jsr     win_io
        bcc     :+
        jmp     usb_err         ; (the window as it was, less its start)
:       LDW     tstart, textbuf
        lda     cut
        beq     :+
        lda     #0
        sta     weof
        jsr     trim_tail
:       jmp     skip_head

; "  Line n  37/120 KB" in the status line: where the top is
sb_where:
        lda     #' '
        jsr     sb_chr
        jsr     sb_chr
        MOVW    zt, vtop
        jsr     p2off
        jsr     sb_kb
        lda     #'/'
        jsr     sb_chr
        ldx     #2
:       lda     fsize,x
        sta     off,x
        dex
        bpl     :-
        jsr     sb_kb
        lda     #<kb_txt
        ldy     #>kb_txt
        jmp     sb_str

; off (3 bytes) / 1024 in decimal
sb_kb:  lda     off+1
        sta     num
        lda     off+2
        sta     num+1
        lsr     num+1
        ror     num
        lsr     num+1
        ror     num
        jmp     sb_dec

bigq_txt:   .byte   "Too big to edit (13 KB at most). View it? (Y/N)", 0
bigro_txt:  .byte   "A large file: view only. ^O opens another file, ^Q quits", 0
kb_txt:     .byte   " KB", 0


; ============================================================================
; edit mode keys
; ============================================================================
ed_key: cmp     #$80
        bcs     @spec
        cmp     #' '
        bcc     @ctl
        cmp     #$7F
        bne     :+
        jmp     k_bs
:       jmp     k_char
@ctl:   asl
        tax
        lda     ctl_tab+1,x
        pha
        lda     ctl_tab,x
        pha
        rts
@spec:  cmp     #K_INS + 1
        bcs     k_nop
        and     #$7F
        asl
        tax
        lda     spec_tab+1,x
        pha
        lda     spec_tab,x
        pha
k_nop:  rts

ctl_tab:.word   k_nop-1, k_home-1, k_bottom-1, k_nop-1          ; ^@ ^A ^B ^C
        .word   k_del-1, k_end-1, k_find-1, k_help-1            ; ^D ^E ^F ^G
        .word   k_bs-1, k_tab-1, k_enter-1, k_cut-1             ; ^H ^I ^J ^K
        .word   k_goto-1, k_enter-1, k_next-1, k_open-1         ; ^L ^M ^N ^O
        .word   k_nop-1, k_quit-1, k_view-1, k_save-1           ; ^P ^Q ^R ^S
        .word   k_top-1, k_paste-1, k_pgdn-1, k_saveas-1        ; ^T ^U ^V ^W
        .word   k_nop-1, k_pgup-1, k_nop-1, k_nop-1             ; ^X ^Y ^Z Esc
        .word   k_nop-1, k_nop-1, k_nop-1, k_nop-1
spec_tab:.word  k_up-1, k_down-1, k_right-1, k_left-1           ; K_UP K_DN K_RT K_LT
        .word   k_home-1, k_end-1, k_pgup-1, k_pgdn-1           ; Home End PgUp PgDn
        .word   k_del-1, k_nop-1                                ; Del Ins

; ---- saving, opening, quitting ------------------------------------------------------
; save to the file's name (asks for one if it has none): carry set if not saved
k_save:
do_save:lda     fname
        beq     do_saveas
        ldx     #0
@c:     lda     fname,x
        sta     fname_in,x
        beq     :+
        inx
        bne     @c
:       jmp     save_file

k_saveas:
do_saveas:
        ldx     #0
@c:     lda     fname,x
        sta     inbuf,x
        beq     :+
        inx
        bne     @c
:       stx     inlen
        lda     #<saveas_q
        ldy     #>saveas_q
        jsr     prompt
        bcs     @r
        jsr     upcase
        lda     inbuf
        bne     :+
        sec
@r:     rts
:       ldx     #0
@n:     lda     inbuf,x
        sta     fname_in,x
        beq     :+
        inx
        bne     @n
:       jmp     save_file

; changed and not saved: ask.  Carry set = don't go on
ask_save:
        lda     modified
        beq     @ok
        lda     #<savechg_q
        ldy     #>savechg_q
        jsr     ask_yn
        cmp     #'N'
        beq     @ok
        cmp     #'Y'
        beq     do_save
        sec
        rts
@ok:    clc
        rts

k_quit: jsr     ask_save
        bcs     @r
        jsr     cls
        jmp     SBC_MENU
@r:     rts

k_open: jsr     ask_save
        bcs     @r
        jmp     open_ask
@r:     rts

; which file?  (Esc: keep what there is)
open_ask:
        lda     #0
        sta     inlen
        lda     #<open_q
        ldy     #>open_q
        jsr     prompt
        bcs     @done
        lda     inbuf
        beq     @new
        cmp     #'?'
        bne     @f
        lda     inbuf+1
        bne     @f
        jsr     list_files
        jmp     open_ask
@f:     jsr     upcase
        ldx     #0
@c:     lda     inbuf,x
        sta     fname_in,x
        beq     :+
        inx
        bne     @c
:       jsr     load_file
        jmp     @done
@new:   jsr     buf_empty
        lda     #0
        sta     fname
        lda     #1
        sta     crlf
        sta     mdon
@done:  lda     #0
        sta     rd_from
        lda     #1
        sta     dirty
        rts

; ^G: the keys
k_help: jsr     cls
        LDW     zt, help_txt
        ldx     #0
@l:     stx     t_row
        ldy     #0
        jsr     goto_rc
        ldy     #0
        lda     (zt),y
        beq     @w
        lda     zt
        ldy     zt+1
        jsr     prints          ; (it ends with strp + Y at the line's 0)
        tya
        sec                     ; (+ 1: past the 0)
        adc     strp
        sta     zt
        lda     strp+1
        adc     #0
        sta     zt+1
        ldx     t_row
        inx
        cpx     #TROWS
        bcc     @l
@w:     jsr     key_wait
        lda     #0
        sta     rd_from
        lda     #1
        sta     v_full
        sta     dirty
        rts

saveas_q:   .byte   "Save as:", 0
savechg_q:  .byte   "The text has changed. Save it first? (Y/N, Esc: cancel)", 0
open_q:     .byte   "Open file (Enter: a new one, ? = list):", 0
help_txt:
        .byte   "EDIT - the keys", 0
        .byte   " ", 0
        .byte   "  Arrows, Home, End, PgUp, PgDn  move  (also ^A ^E line start/end, ^Y ^V page)", 0
        .byte   "  ^T  ^B        the top / the bottom of the file", 0
        .byte   "  Backspace     delete to the left     Del or ^D   delete to the right", 0
        .byte   "  Tab           spaces to the next stop (every 4 columns)", 0
        .byte   "  ^K            cut the line (^K again: the next line too)    ^U  paste", 0
        .byte   "  ^F            find (any case)    ^N  find the next    ^L  go to a line", 0
        .byte   "  ^S            save    ^W  save as    ^O  open another file", 0
        .byte   "  ^R            view mode: the text wrapped, markdown shown formatted", 0
        .byte   "  ^Q            quit (asks if the text was changed)", 0
        .byte   " ", 0
        .byte   "View mode", 0
        .byte   "  Up, Down (j k), PgUp, PgDn (Space, B), Home, End    scroll", 0
        .byte   "  M             markdown formatting on / off (on for .MD files)", 0
        .byte   "  Esc or ^R     back to editing (at the line on top, if you scrolled)", 0
        .byte   " ", 0
        .byte   "Files are in the monitor's current folder (L DIR there first), or give a", 0
        .byte   "path: /DOCS/NOTES.MD.  ? at the Open question lists the folder.", 0
        .byte   "A file over 13 KB can be viewed, but not edited.", 0
        .byte   " ", 0
        .byte   "Press a key", 0
        .byte   0

; ============================================================================
main:   cld
        ldx     #<(vars_end - vars_start)       ; the variables to 0
        lda     #<vars_start
        sta     zt
        lda     #>vars_start
        sta     zt+1
        LDW     cnt, vars_end - vars_start
@z:     ldy     #0
        tya
        sta     (zt),y
        INC16   zt
        lda     cnt
        bne     :+
        dec     cnt+1
:       dec     cnt
        lda     cnt
        ora     cnt+1
        bne     @z
        lda     SBC_CWD         ; the monitor's current folder (SBC_CWD)
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
@nocwd: jsr     buf_empty
        lda     #1
        sta     crlf
        sta     mdon
        lda     #$FF
        sta     lastkey
        jsr     rd_none
        jsr     cls
        jsr     open_ask
loop:   jsr     key_nb
        bcs     @k
        jsr     refresh
        jsr     key_wait
@k:     sta     curkey
        lda     #0              ; a message lasts until the next key
        sta     msgp+1
        lda     #1
        sta     dirty
        lda     curkey
        ldx     vmode
        bne     @v
        jsr     ed_key
        jmp     @lk
@v:     jsr     vw_key
@lk:    lda     curkey
        sta     lastkey
        jmp     loop

; wait about A ms (for the USB drive code; as in ay/common.s)
DELAY_N = (1000 * CLOCK_MHZ - 7) / (5 + 4 * (CLOCK_MHZ - 1))
delay_ms:
        tax
        beq     @done
@o:     ldy     #DELAY_N
@i:
.repeat CLOCK_MHZ - 1
        nop
        nop
.endrepeat
        dey
        bne     @i
        dex
        bne     @o
@done:  rts

        .include "ay/ch376r.s"  ; the USB drive

; ============================================================================
        .segment "BSS"
vars_start:
g_r:        .res 1
g_c:        .res 1
cur_attr:   .res 1
wcnt:       .res 2
kparm:      .res 1
kskip:      .res 1
ktmp:       .res 2
u_need:     .res 1
u_cp:       .res 2
u_big:      .res 1
u_t:        .res 1
sblen:      .res 1
sbx:        .res 1
sbx2:       .res 1
sbuf:       .res COLS
dflag:      .res 1
dtmp:       .res 1
num:        .res 2
msgp:       .res 2
msg_kind:   .res 1
msg_num:    .res 2
dirty:      .res 1
vmode:      .res 1
modified:   .res 1
mdon:       .res 1
ccol:       .res 2
prm:        .res 2
inbuf:      .res MAXIN + 2
inlen:      .res 1
cur_line:   .res 2
nlines:     .res 2
top_line:   .res 2
hs:         .res 2
wcol_ok:    .res 1
wcol:       .res 2
gl_n:       .res 1
cnt:        .res 2
pos:        .res 2
ls:         .res 2
col:        .res 2
colsv:      .res 2
rd_from:    .res 1
rd_one:     .res 1
rd_cur:     .res 1
crow:       .res 1
eot:        .res 1
t_row:      .res 1
t_n:        .res 1
t_len:      .res 1
t_y:        .res 1
lastkey:    .res 1
curkey:     .res 1
clip_n:     .res 2
flen:       .res 1
fbuf:       .res MAXIN + 2
fpos:       .res 2
fline:      .res 2
fname_in:   .res MAXIN + 2
fname:      .res MAXIN + 2
pbuf:       .res PMAX
dir_root:   .res 1
fo:         .res 2
crlf:       .res 1
obuf_n:     .res 1
nfiles:     .res 1
cwd_buf:    .res CWD_MAX + 1
rcol:       .res 1
rvis:       .res 1
vcnt:       .res 1
vskip:      .res 1
vrow:       .res 1
vfirst:     .res 1
vshow:      .res 1
vlast:      .res 1
vstop:      .res 1
t_px:       .res 1
rstart:     .res 1
wmode:      .res 1
wlen:       .res 1
wmax:       .res 1
wb_g:       .res COLS
wb_a:       .res COLS
sp_attr:    .res 1
t_wy:       .res 1
iattr:      .res 1
battr:      .res 1
incode:     .res 1
table:      .res 1
prevc:      .res 1
pre1:       .res 44
pre1n:      .res 1
pre2:       .res 44
pre2n:      .res 1
lfence:     .res 1
le:         .res 2
tend:       .res 2
lpsv:       .res 2
t_ind:      .res 1
t_sty:      .res 1
t_nx:       .res 1
lk_end:     .res 2
lk_next:    .res 2
vtop:       .res 2
vsub:       .res 1
vfence:     .res 1
vline:      .res 2
vt_rows:    .res 1
vt_ok:      .res 1
v_end:      .res 1
v_blank:    .res 1
v_full:     .res 1
v_mv:       .res 1
v_moved:    .res 1
v_pos:      .res 2
v_cl:       .res 2
v_tl:       .res 2
t_f:        .res 1
big:        .res 1
weof:       .res 1
tstart:     .res 2
vl_ok:      .res 1
fsize:      .res 4
wbase:      .res 3
lf_at:      .res 2
nwb:        .res 3
off:        .res 3
ns:         .res 2
kk:         .res 2
dd:         .res 2
cut:        .res 1
io_ptr:     .res 2
io_len:     .res 2
io_off:     .res 3
vars_end:
obuf:       .res 256

        .segment "TEXTBUF"
textbuf:
