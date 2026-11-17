; ============================================================================
; talk.s - text to speech on the SPO256-AL2 (CPU Rev2, any display)
;
;   build:  make.bat  (TALK.BIN, loads and runs at $0800)
;
; Type a line and it is spoken.  Commands:
;   /F NAME   speak a text file (the current drive and folder); Esc stops
;   /P        show the allophones as they are spoken (on / off)
;   /A ...    speak allophones by name or number:  /A HH1 EH LL OW
;   /?        help
;   /Q        quit (back to the file manager or the boot menu)
;
; How (tts_ref.py is the same thing in Python, and the test's reference):
;  1. normalise: upper case; numbers to words (0-65535, longer ones digit by
;     digit); , ; : -> ','   . ! -> '.'   ? '-' kept; the rest spaces
;  2. xlate: the US Naval Research Lab's letter-to-sound rules (NRL Report
;     7948, 1976: 329 rules, public domain) turn letters into phonemes;
;     a short word list (words.txt) is checked first
;  3. allo: phonemes -> SPO256 allophones, choosing by the sounds around
;     (KK1/KK2/KK3, DD1/DD2, R-coloured vowels, ...), short pauses before
;     stops, PA3 between words, PA4 at commas, PA5 at full stops
;  4. SBC_SAY queues them (the ROM feeds the chip from the VIA interrupt)
;
; No zero page is used.
; ============================================================================

        .include "sbc_api.inc"

SPO_PORT        = $7F26
TB_MAX          = 190           ; a chunk of text (numbers may add 60)
LINE_MAX        = 120
AB_FLUSH        = 200           ; allophones queued at once (at a pause)
K_BS            = $08
K_CR            = $0D
K_ESC           = $1B

; character classes (ctab)
C_VOW           = $01           ; A E I O U Y
C_CON           = $02           ; the other letters
C_VCD           = $04           ; B D V G J L M N R W Z
C_FRN           = $08           ; E I Y
C_LET           = $10
C_SIB           = $20           ; S C G Z X J
C_LNG           = $40           ; T S R D L Z N J

        .segment "CODE"
start:  cld
        lda     #0
        sta     show
        sta     spo
        lda     SPO_PORT        ; an idle SPO256: STBY = 1, /LRQ = 0
        and     #$03
        cmp     #$01
        bne     :+
        inc     spo
:       lda     #<s_hello
        ldy     #>s_hello
        jsr     puts
        lda     spo
        bne     main
        lda     #<s_nochip
        ldy     #>s_nochip
        jsr     puts
        lda     #1
        sta     show

main:   lda     #<s_prompt
        ldy     #>s_prompt
        jsr     puts
        jsr     getline
        lda     llen
        beq     main
        lda     line
        cmp     #'/'
        bne     @say
        jsr     command
        jmp     main
@say:   lda     #<line          ; speak the line
        sta     src
        lda     #>line
        sta     src+1
        lda     llen
        clc
        adc     #<line
        sta     send
        lda     #>line
        adc     #0
        sta     send+1
        lda     #0
        sta     echo
        jsr     speak
        jmp     main

; ----------------------------------------------------------------------------
; commands
; ----------------------------------------------------------------------------
command:
        lda     line+1
        cmp     #'a'
        bcc     :+
        and     #$DF
:       cmp     #'Q'
        bne     @nq
        jsr     SBC_CONRESET
        jmp     SBC_MENU
@nq:    cmp     #'P'
        bne     @np
        lda     show
        eor     #1
        sta     show
        lda     #<s_showon
        ldy     #>s_showon
        ldx     show
        bne     :+
        lda     #<s_showoff
        ldy     #>s_showoff
:       jmp     puts
@np:    cmp     #'F'
        bne     @nf
        jmp     cmd_file
@nf:    cmp     #'A'
        bne     @na
        jmp     cmd_allo
@na:    lda     #<s_help
        ldy     #>s_help
        jmp     puts

; /F NAME: load the file and speak it, showing the text
cmd_file:
        ldx     #2              ; the name (after spaces)
@sp:    cpx     llen
        bcs     @noname
        lda     line,x
        cmp     #' '
        bne     @nm
        inx
        bne     @sp
@nm:    ldy     #0
@cp:    cpx     llen
        bcs     @e
        lda     line,x
        cmp     #'a'
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:       sta     ldblk+4,y
        inx
        iny
        cpy     #13
        bcc     @cp
@e:     lda     #0
        sta     ldblk+4,y
        lda     #<ldblk
        ldy     #>ldblk
        jsr     SBC_LOAD
        bcc     @ok
        pha
        lda     #<s_ferr
        ldy     #>s_ferr
        jsr     puts
        pla
        jsr     puthex
        jmp     crlf
@noname:
        lda     #<s_help
        ldy     #>s_help
        jmp     puts
@ok:    stx     t1              ; X/Y = the length
        lda     #<fbuf
        sta     src
        clc
        adc     t1
        sta     send
        lda     #>fbuf
        sta     src+1
        tya
        adc     #>fbuf
        sta     send+1
        lda     #1
        sta     echo
        jsr     crlf
        jsr     speak
        jmp     crlf

; /A names or numbers: those allophones
cmd_allo:
        lda     #0
        sta     na
        ldx     #2
@tok:   cpx     llen            ; the next word
        bcc     :+
        jmp     @say
:       ; (far)
        lda     line,x
        cmp     #' '
        bne     @w
        inx
        bne     @tok
@w:     stx     t2              ; its start
@we:    cpx     llen
        bcs     @wd
        lda     line,x
        cmp     #' '
        beq     @wd
        inx
        bne     @we
@wd:    stx     t3              ; its end
        ldx     t2
        lda     line,x
        cmp     #'0'
        bcc     @name
        cmp     #'9'+1
        bcs     @name
        lda     #0              ; a number
        sta     t4
@dig:   cpx     t3
        bcs     @num
        lda     t4              ; t4 = t4 * 10 + digit
        asl
        asl
        adc     t4
        asl
        sta     t4
        lda     line,x
        and     #$0F
        clc
        adc     t4
        sta     t4
        inx
        bne     @dig
@num:   lda     t4
        cmp     #64
        bcs     @bad
        bcs     :+
        jmp     @put
:       ; (far)
@name:  lda     t3              ; a name: 1-3 letters against al_name
        sec
        sbc     t2
        cmp     #4
        bcs     @bad
        sta     t5              ; (its length)
        lda     #0
        sta     t4
@try:   lda     t4              ; t6 = 3 * t4
        asl
        adc     t4
        sta     t6
        ldx     #0
@c:     cpx     t5
        beq     @tail
        txa
        clc
        adc     t2
        tay
        lda     line,y
        cmp     #'a'
        bcc     :+
        and     #$DF
:       sta     t1
        txa
        clc
        adc     t6
        tay
        lda     al_name,y
        cmp     t1
        bne     @next
        inx
        bne     @c
@tail:  cpx     #3              ; the rest of the name blank?
        beq     @found
        txa
        clc
        adc     t6
        tay
        lda     al_name,y
        cmp     #' '
        beq     @found
@next:  inc     t4
        lda     t4
        cmp     #64
        bcc     @try
@bad:   lda     #'?'            ; not one: shown, skipped
        jsr     SBC_CHROUT
        ldx     t2
@bl:    cpx     t3
        bcs     @bn
        lda     line,x
        jsr     SBC_CHROUT
        inx
        bne     @bl
@bn:    lda     #' '
        jsr     SBC_CHROUT
        jmp     @nx
@found: lda     t4
@put:   ldx     na
        sta     abuf,x
        inc     na
@nx:    ldx     t3
        jmp     @tok
@say:   jsr     crlf
        jmp     flush

; ----------------------------------------------------------------------------
; speak src .. send: a chunk at a time (Esc / Q between chunks stops it)
; ----------------------------------------------------------------------------
speak:  lda     #0
        sta     na
@ch:    jsr     at_end
        bcs     @r
        jsr     normalise
        jsr     xlate
        jsr     allo
        jsr     flush
        lda     show
        beq     :+
        jsr     crlf
:       jsr     SBC_CHRIN       ; stop?
        bcc     @ch
        cmp     #K_ESC
        beq     @r
        cmp     #KEY_ESC
        beq     @r
        and     #$DF
        cmp     #'Q'
        bne     @ch
@r:     rts

; C=1 at the end of the text
at_end: lda     src
        cmp     send
        lda     src+1
        sbc     send+1
        rts

; A = the next character of the text (echoed in file mode)
src_get:
        lda     src
        sta     @rd+1
        lda     src+1
        sta     @rd+2
@rd:    lda     $FFFF
        inc     src
        bne     :+
        inc     src+1
:       ldx     echo
        beq     @r
        pha
        cmp     #K_CR
        beq     @e
        cmp     #10
        bne     :+
        lda     #K_CR           ; (LF alone: a new line too)
        jsr     SBC_CHROUT
        lda     #10
:       cmp     #9
        bne     :+
        lda     #' '
:       cmp     #' '
        bcc     @n
@e:     jsr     SBC_CHROUT
@n:     pla
@r:     rts

; ----------------------------------------------------------------------------
; normalise: text -> tbuf (tbuf[0-2] = 0, tbuf[3] = ' ', the words, ' ', 0),
; up to about TB_MAX characters, stopping between words
; ----------------------------------------------------------------------------
normalise:
        lda     #0
        sta     tbuf
        sta     tbuf+1
        sta     tbuf+2
        sta     tbuf+255
        lda     #' '
        sta     tbuf+3
        lda     #4
        sta     ti
@l:     jsr     at_end
        bcs     @done
        lda     ti
        cmp     #TB_MAX
        bcc     @get
        ldx     ti              ; full: stop after a space
        lda     tbuf-1,x
        cmp     #' '
        beq     @done
@get:   jsr     src_get
        cmp     #'a'
        bcc     :+
        cmp     #'z'+1
        bcs     :+
        and     #$DF
:       cmp     #'A'
        bcc     @nl
        cmp     #'Z'+1
        bcs     @nl
@put:   jsr     tput
        jmp     @l
@nl:    cmp     #$27            ; '
        beq     @put
        cmp     #'0'
        bcc     @punct
        cmp     #'9'+1
        bcs     @punct
        jsr     number
        jmp     @l
@punct: ldx     #0
@pl:    ldy     p_from,x
        beq     @sp
        cmp     p_from,x
        beq     @pf
        inx
        bne     @pl
@pf:    lda     p_to,x          ; " , "  " . "  " ? "  " - "
        pha
        jsr     tspace
        pla
        jsr     tput
        lda     #' '
        jsr     tput
        jmp     @l
@sp:    jsr     tspace
        jmp     @l
@done:  jsr     tspace
        lda     #0
        ldx     ti
        sta     tbuf,x
        rts

; tbuf += A (kept short of the end)
tput:   ldx     ti
        cpx     #250
        bcs     @r
        sta     tbuf,x
        inc     ti
@r:     rts

; a space, unless there is one
tspace: ldx     ti
        lda     tbuf-1,x
        cmp     #' '
        beq     @r
        lda     #' '
        jmp     tput
@r:     rts

; a run of digits (the first in A): up to 5 digits and <= 65535 as words,
; longer ones digit by digit
number: ldx     #0
        stx     nv
        stx     nv+1
        stx     nbig
@d:     and     #$0F
        sta     dg,x
        cpx     #5
        bcc     :+
        inc     nbig            ; (6 digits or more)
        bne     @next
:       stx     t5
        jsr     mul10
        ldx     t5
@next:  inx
        cpx     #16
        bcs     @more           ; (very long: the rest is skipped)
        stx     t5
        jsr     next_dig
        ldx     t5
        bcc     @end
        jsr     src_get
        ldx     t5
        jmp     @d
@more:  jsr     next_dig        ; skip the rest of the digits
        bcc     @end
        jsr     src_get
        jmp     @more
@end:   stx     ndig
        lda     nbig
        bne     @each
        lda     nv              ; the value in words
        ora     nv+1
        bne     :+
        lda     #0
        jmp     word            ; ZERO
:       lda     nv+1            ; thousands
        cmp     #>1000
        bcc     @h
        bne     @th
        lda     nv
        cmp     #<1000
        bcc     @h
@th:    ldx     #0              ; nv / 1000 -> X, nv % 1000 -> nv
@ts:    lda     nv
        sec
        sbc     #<1000
        tay
        lda     nv+1
        sbc     #>1000
        bcc     @tq
        sta     nv+1
        sty     nv
        inx
        bne     @ts
@tq:    txa
        jsr     words3
        lda     #W_THOUSAND
        jsr     word
@h:     lda     nv              ; (< 1000: nv+1 is 0-3)
        ldx     nv+1
        jmp     words3x
@each:  ldx     #0              ; digit by digit
@el:    cpx     ndig
        bcs     @r
        stx     t5
        lda     dg,x
        jsr     word
        ldx     t5
        inx
        bne     @el
@r:     rts

; C=1 if the text goes on with a digit
next_dig:
        jsr     at_end
        bcs     @no
        lda     src
        sta     @pk+1
        lda     src+1
        sta     @pk+2
@pk:    lda     $FFFF
        cmp     #'0'
        bcc     @no
        cmp     #'9'+1
        bcs     @no
        sec
        rts
@no:    clc
        rts

; nv = nv * 10 + A (nbig = 1 past 65535)
mul10:  sta     t1
        lda     nv
        sta     t2
        lda     nv+1
        sta     t3
        asl     nv              ; * 4
        rol     nv+1
        bcs     @big
        asl     nv
        rol     nv+1
        bcs     @big
        lda     nv              ; + itself: * 5
        clc
        adc     t2
        sta     nv
        lda     nv+1
        adc     t3
        sta     nv+1
        bcs     @big
        asl     nv              ; * 10
        rol     nv+1
        bcs     @big
        lda     nv              ; + the digit
        clc
        adc     t1
        sta     nv
        bcc     @r
        inc     nv+1
        beq     @big
@r:     rts
@big:   lda     #1
        sta     nbig
        rts

; A (0-255) in words; words3x: X/A (0-999)
words3: ldx     #0
words3x:
        sta     wv
        stx     wv+1
        ldx     #0              ; hundreds
@hs:    lda     wv
        sec
        sbc     #100
        tay
        lda     wv+1
        sbc     #0
        bcc     @hq
        sta     wv+1
        sty     wv
        inx
        bne     @hs
@hq:    txa
        beq     @t
        jsr     word            ; ONE .. NINE
        lda     #W_HUNDRED
        jsr     word
@t:     lda     wv              ; < 100
        cmp     #20
        bcc     @o
        ldx     #0
@tn:    cmp     #10
        bcc     @tw
        sbc     #10
        inx
        bne     @tn
@tw:    sta     wv
        txa                     ; TWENTY .. NINETY = word 18 + tens
        clc
        adc     #W_TENS-2
        jsr     word
        lda     wv
        beq     @r
@o:     lda     wv
        beq     @r
        jmp     word
@r:     rts

; word A (num_w) into tbuf, with spaces round it
word:   asl
        tax
        lda     num_w,x
        sta     @rd+1
        lda     num_w+1,x
        sta     @rd+2
        jsr     tspace
        ldy     #0
@rd:    lda     $FFFF,y
        beq     @e
        sty     t6
        jsr     tput
        ldy     t6
        iny
        bne     @rd
@e:     lda     #' '
        jmp     tput

; ----------------------------------------------------------------------------
; xlate: tbuf -> phonemes in pbuf (pn of them)
; ----------------------------------------------------------------------------
xlate:  lda     #0
        sta     pn
        lda     #4
        sta     ti
@l:     ldx     ti
        lda     tbuf,x
        beq     @r
        lda     tbuf-1,x        ; a word's start: the word list first
        cmp     #' '
        bne     @rules
        lda     tbuf,x
        jsr     cls
        and     #C_LET
        beq     @rules
        jsr     dict
        bcs     @l
@rules: ldx     ti
        lda     tbuf,x
        sec
        sbc     #$20
        bcc     @skip
        cmp     #$3B
        bcs     @skip
        asl
        tay
        lda     rg_tab,y
        sta     rp
        lda     rg_tab+1,y
        sta     rp+1
        ora     rp
        beq     @skip
@rule:  jsr     rule
        bcs     @l              ; (a rule took it)
        lda     nxt             ; the next rule
        sta     rp
        lda     nxt+1
        sta     rp+1
        lda     rend
        beq     @rule
@skip:  inc     ti              ; no rule: skipped
        jmp     @l
@r:     rts

; rb: A = byte Y of the rule / word at rp
rb:     lda     $FFFF,y
        rts
set_rb: lda     rp
        sta     rb+1
        lda     rp+1
        sta     rb+2
        rts

; try the rule at rp: C=1 if it matched (its phonemes added, ti moved);
; C=0: nxt = the next rule, rend = 1 if this was the group's end
rule:   jsr     set_rb
        lda     #0
        sta     rend
        ldy     #0
        jsr     rb
        cmp     #$FF
        bne     :+
        inc     rend
        clc
        rts
:       ldx     #0              ; find the parts: left 0 match 0 right 0 ph $FF
        ldy     #0
@f:     jsr     rb
        bne     @fn
        inx
        cpx     #1
        bne     :+
        sty     llen2           ; (the left context's length)
        iny
        sty     mofs
        dey
:       cpx     #2
        bne     :+
        iny
        sty     rofs
        dey
:       cpx     #3
        bne     @fn
        iny
        sty     pofs
        jmp     @ph
@fn:    iny
        bne     @f
@ph:    jsr     rb              ; to the $FF
        cmp     #$FF
        beq     @pe
        iny
        bne     @ph
@pe:    iny
        tya
        clc
        adc     rp
        sta     nxt
        lda     rp+1
        adc     #0
        sta     nxt+1
        ldy     mofs            ; the text itself
        ldx     ti
@m:     jsr     rb
        beq     @me
        cmp     tbuf,x
        bne     @no
        iny
        inx
        bne     @m
@me:    stx     tend
        jsr     left_ok
        bcc     @no
        jsr     right_ok
        bcc     @no
        ldy     pofs            ; matched: its phonemes
@pp:    jsr     rb
        cmp     #$FF
        beq     @pd
        jsr     padd
        iny
        bne     @pp
@pd:    lda     tend
        sta     ti
        sec
        rts
@no:    clc
        rts

padd:   ldx     pn
        cpx     #250
        bcs     @r
        sta     pbuf,x
        inc     pn
@r:     rts

; the word at ti in the word list?  C=1: its phonemes added, ti moved
dict:   lda     #<dict_t
        sta     rp
        lda     #>dict_t
        sta     rp+1
@e:     jsr     set_rb
        ldy     #0
        jsr     rb
        bne     :+
        clc                     ; (the list's end)
        rts
:       ldx     ti
@c:     jsr     rb
        beq     @we
        cmp     tbuf,x
        bne     @skip
        iny
        inx
        bne     @c
@we:    lda     tbuf,x          ; the word must end there too
        cmp     #$27
        beq     @skip
        jsr     cls
        and     #C_LET
        bne     @skip
        stx     tend
        iny
@p:     jsr     rb
        cmp     #$FF
        beq     @done
        jsr     padd
        iny
        bne     @p
@done:  lda     tend
        sta     ti
        sec
        rts
@skip:  jsr     rb              ; to the entry's $FF
        cmp     #$FF
        beq     @nx
        iny
        bne     @skip
@nx:    iny
        tya
        clc
        adc     rp
        sta     rp
        bcc     @e
        inc     rp+1
        bne     @e

; A = the classes of character A (0 above 'Z')
cls:    cmp     #'Z'+1
        bcs     @z
        stx     cx
        tax
        lda     ctab,x
        ldx     cx
        rts
@z:     lda     #0
        rts

; ----------------------------------------------------------------------------
; the contexts.  left_ok: the pattern (stored reversed) Y = 0 .. llen2-1,
; the text from ti-1 going back.  right_ok: from rofs, the text from tend.
; C=1 if it fits.
; ----------------------------------------------------------------------------
left_ok:
        lda     #$FF            ; (dir: back)
        sta     dir
        ldx     ti
        dex
        ldy     #0
@p:     cpy     llen2
        bcs     ok
        jsr     rb
        iny
        sty     py
        jsr     ctx
        bcc     no
        ldy     py
        jmp     @p

right_ok:
        lda     #1
        sta     dir
        ldx     tend
        ldy     rofs
@p:     jsr     rb
        beq     ok
        iny
        sty     py
        jsr     ctx
        bcc     no
        ldy     py
        jmp     @p
ok:     sec
        rts
no:     clc
        rts

; one pattern character A against the text at X (moving X by dir): C=1 fits
ctx:    cmp     #' '
        bne     @n1
        lda     tbuf,x          ; not a letter
        jsr     cls
        and     #C_LET
        beq     :+
        jmp     @no
:       ; (far)
        jmp     step
@n1:    cmp     #'#'
        bne     @n2
        lda     #1
        bne     @vow
@n2:    cmp     #'!'
        bne     @n3
        lda     #2
@vow:   sta     cnt             ; cnt or more vowels
@vl:    lda     tbuf,x
        jsr     cls
        and     #C_VOW
        beq     @ve
        jsr     step
        dec     cnt
        jmp     @vl
@ve:    lda     cnt
        bne     :+
        jmp     @ok
:       ; (far)
        bpl     :+
        jmp     @ok
:       ; (far)
        clc
        rts
@n3:    cmp     #':'
        bne     @n4
        lda     #0
        beq     @con
@n4:    cmp     #'*'
        bne     @n5
        lda     #1
@con:   sta     cnt             ; cnt or more consonants
@cl:    lda     tbuf,x
        jsr     cls
        and     #C_CON
        beq     @ve
        jsr     step
        dec     cnt
        jmp     @cl
@n5:    ldy     #C_CON
        cmp     #'^'
        beq     @one
        ldy     #C_VCD
        cmp     #'.'
        beq     @one
        ldy     #C_FRN
        cmp     #'+'
        beq     @one
        cmp     #'%'
        beq     @pct
        cmp     #'&'
        beq     @amp
        cmp     #'@'
        beq     @at
        cmp     tbuf,x          ; a letter or '
        bne     @no
        jmp     step
@one:   sty     cnt             ; one character of class cnt
        lda     tbuf,x
        jsr     cls
        and     cnt
        beq     @no
        jmp     step
@pct:   lda     tbuf,x          ; (right only) ING, or E...
        cmp     #'E'
        beq     step
        cmp     #'I'
        bne     @no
        lda     tbuf+1,x
        cmp     #'N'
        bne     @no
        lda     tbuf+2,x
        cmp     #'G'
        bne     @no
        inx
        inx
        inx
        sec
        rts
@amp:   lda     #C_SIB
        ldy     #'C'            ; CH SH, or one of S C G Z X J
        bne     @two
@at:    lda     #C_LNG          ; TH CH SH, or one of T S R D L Z N J
        ldy     #'T'
@two:   sta     cnt
        sty     t7
        jsr     hpair
        bcs     @ok
        lda     tbuf,x
        jsr     cls
        and     cnt
        beq     @no
        jmp     step
@ok:    sec
        rts
@no:    clc
        rts

; X += dir (C=1)
step:   txa
        clc
        adc     dir
        tax
        sec
        rts

; an "xH" pair at X (CH, SH, or TH when t7 = 'T'), in the direction of
; travel: C=1 and X past it
hpair:  lda     dir
        bmi     @back
        lda     tbuf+1,x        ; forwards: x, then H
        cmp     #'H'
        bne     @no
        lda     tbuf,x
        jsr     @first
        bcc     @no
        inx
        inx
        sec
        rts
@back:  lda     tbuf,x          ; backwards: H, then x before it
        cmp     #'H'
        bne     @no
        lda     tbuf-1,x
        jsr     @first
        bcc     @no
        dex
        dex
        sec
        rts
@no:    clc
        rts
@first: cmp     #'C'
        beq     @y
        cmp     #'S'
        beq     @y
        cmp     t7
        beq     @y
        clc
        rts
@y:     sec
        rts

; ----------------------------------------------------------------------------
; allo: phonemes -> allophones (abuf, queued at the pauses)
; ----------------------------------------------------------------------------
allo:   lda     #0
        sta     k
allo_l: ldx     k
        cpx     pn
        bcc     :+
        rts
:       lda     pbuf,x
        sta     cur
        lda     #P_GAP          ; prev, nxt, nxt2 (a gap beyond the ends)
        cpx     #0
        beq     :+
        lda     pbuf-1,x
:       sta     prev
        jsr     allo_pk           ; nxt
        sta     nxt1
        inx
        jsr     allo_pk
        sta     nxt2
        lda     cur
        cmp     #4
        bcs     @snd
        tax                     ; a pause: PA3 / PA4 / PA5
        lda     gap_al,x
        jsr     apause
        jmp     allo_n
@snd:   tax                     ; PP -> P
        lda     ph_kind,x
        and     #1
        bne     :+
        lda     cur
        cmp     prev
        bne     :+
        jmp     allo_n
:       ; (far)
:       lda     prev            ; start of a word?
        cmp     #4
        lda     #0
        rol
        eor     #1
        sta     wstart          ; (1 = the first sound of a word)
        bne     @nost
        ldx     cur             ; a stop in a word: a short pause first
        lda     ph_kind,x
        and     #$0C
        beq     @nost
        jsr     last_pa
        bcs     @nost
        ldx     cur
        lda     ph_kind,x
        and     #4
        beq     :+
        lda     #A_PA1              ; (= 0: no bne)
        jmp     @pa
:       lda     #A_PA2
@pa:    jsr     aput
@nost:  ldx     cur             ; an R-coloured vowel?
        lda     ph_rcol,x
        beq     @nr
        ldy     nxt1
        cpy     #P_R
        bne     @nr
        ldy     nxt2
        pha
        lda     ph_kind,y
        lsr
        pla
        bcs     @nr
        jsr     aput
        inc     k
        jmp     allo_n
@nr:    lda     cur             ; AX L at a word's end: EL
        cmp     #P_AX
        bne     @ne
        lda     nxt1
        cmp     #P_L
        bne     @ne
        lda     nxt2
        cmp     #4
        bcs     @ne
        lda     #A_EL
        jsr     aput
        inc     k
        jmp     allo_n
@ne:    ldx     cur
        lda     ph_map,x
        bmi     allo_sp
        jsr     aput
allo_n: inc     k
        jmp     allo_l
allo_sp:  and     #$7F
        asl
        tax
        lda     spec_go+1,x
        pha
        lda     spec_go,x
        pha
        rts                     ; (the choice ends with jmp put_adv)
allo_pk:  inx                     ; A = pbuf[X+1] or a gap
        cpx     pn
        bcc     :+
        dex
        lda     #P_GAP
        rts
:       lda     pbuf,x
        dex
        rts

; the choices by context (nxt1 = the next phoneme)
sp_uw:  lda     #A_UW2          ; UW1 after Y ("you"), else UW2
        ldx     prev
        cpx     #P_Y
        bne     put_adv
        lda     #A_UW1
        bne     put_adv
sp_y:   lda     #A_YY1          ; YY2 starting a word
        ldx     wstart
        beq     put_adv
        lda     #A_YY2
        bne     put_adv
sp_b:   lda     #A_BB1
        ldx     wstart
        beq     put_adv
        lda     #A_BB2
        bne     put_adv
sp_d:   lda     #A_DD1          ; DD2 before a vowel
        jsr     nx_vow
        beq     put_adv
        lda     #A_DD2
        bne     put_adv
sp_t:   lda     #A_TT1          ; TT2 before a vowel
        jsr     nx_vow
        beq     put_adv
        lda     #A_TT2
        bne     put_adv
put_adv:
        jsr     aput
        jmp     allo_n

sp_k:   ldx     nxt1            ; KK1 front vowel, KK3 other vowel, KK2
        lda     ph_kind,x
        lsr
        bcc     :+
        lsr
        lda     #A_KK3
        bcc     put_adv
        lda     #A_KK1
        bne     put_adv
:       lda     #A_KK2
        bne     put_adv
sp_g:   ldx     nxt1            ; GG1 front vowel, GG2 other vowel, GG3
        lda     ph_kind,x
        lsr
        bcc     :+
        lsr
        lda     #A_GG2
        bcc     put_adv
        lda     #A_GG1
        bne     put_adv
:       lda     #A_GG3
        bne     put_adv
sp_n:   lda     #A_NN1          ; NN2 starting a word
        ldx     wstart
        beq     put_adv
        lda     #A_NN2
        bne     put_adv
sp_r:   lda     #A_RR1          ; RR2 after a consonant in a word
        ldx     wstart
        bne     put_adv
        ldx     prev
        ldy     ph_kind,x
        tya
        lsr
        lda     #A_RR1
        bcs     put_adv
        lda     #A_RR2
        bne     put_adv
sp_hh:  ldx     nxt1            ; HH1 before a front vowel
        lda     ph_kind,x
        and     #2
        beq     :+
        lda     #A_HH1
        bne     put_adv
:       lda     #A_HH2
        bne     put_adv
sp_dh:  lda     #A_DH2
        ldx     wstart
        beq     put_adv
        lda     #A_DH1
        bne     put_adv

; Z=0 if the next phoneme is a vowel
nx_vow: ldx     nxt1
        pha
        lda     ph_kind,x
        and     #1
        tax
        pla
        cpx     #0
        rts

; a pause A: none at the start; it replaces (the longer wins) one just put;
; a full buffer is queued here
apause: ldx     na
        beq     @r              ; (nothing yet)
        sta     t7
        jsr     last_pa
        bcc     @new
        ldx     na
        lda     abuf-1,x
        cmp     t7
        bcs     @q
        lda     t7
        sta     abuf-1,x
        jmp     @q
@new:   lda     t7
        jsr     aput
@q:     lda     na
        cmp     #AB_FLUSH
        bcc     @r
        jmp     flush
@r:     rts

; C=1 if the last allophone put is a pause
last_pa:
        ldx     na
        beq     @y              ; (the start counts as a pause)
        lda     abuf-1,x
        cmp     #5
        bcc     @y
        clc
        rts
@y:     sec
        rts

; put allophone A (shown with /P)
aput:   ldx     na
        cpx     #250
        bcs     @r
        sta     abuf,x
        inc     na
        ldx     show
        beq     @r
        sta     t6              ; its name
        asl
        adc     t6
        tax
        lda     al_name,x
        jsr     SBC_CHROUT
        lda     al_name+1,x
        jsr     SBC_CHROUT
        lda     al_name+2,x
        cmp     #' '
        beq     :+
        jsr     SBC_CHROUT
:       lda     #' '
        jmp     SBC_CHROUT
@r:     rts

; queue what is in abuf
flush:  ldx     na
        beq     @r
        lda     #$FF
        sta     abuf,x
        lda     #<abuf
        ldy     #>abuf
        jsr     SBC_SAY
        lda     #0
        sta     na
@r:     rts

; ----------------------------------------------------------------------------
; the console
; ----------------------------------------------------------------------------
getline:
        lda     #0
        sta     llen
@k:     jsr     SBC_CHRIN
        bcc     @k
        cmp     #K_CR
        beq     @cr
        cmp     #K_BS
        beq     @bs
        cmp     #$7F
        beq     @bs
        cmp     #' '
        bcc     @k
        cmp     #$7F
        bcs     @k
        ldx     llen
        cpx     #LINE_MAX
        bcs     @k
        sta     line,x
        inc     llen
        jsr     SBC_CHROUT
        jmp     @k
@bs:    lda     llen
        beq     @k
        dec     llen
        lda     #K_BS
        jsr     SBC_CHROUT
        lda     #' '
        jsr     SBC_CHROUT
        lda     #K_BS
        jsr     SBC_CHROUT
        jmp     @k
@cr:    jmp     crlf

puts:   sta     @rd+1
        sty     @rd+2
        ldx     #0
@rd:    lda     $FFFF,x
        beq     @r
        jsr     SBC_CHROUT
        inx
        bne     @rd
        inc     @rd+2
        bne     @rd
@r:     rts

crlf:   lda     #K_CR
        jsr     SBC_CHROUT
        lda     #10
        jmp     SBC_CHROUT

puthex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     @d
        pla
        and     #15
@d:     cmp     #10
        bcc     :+
        adc     #6
:       adc     #'0'
        jmp     SBC_CHROUT

; ============================================================================
        .segment "RODATA"
s_hello:
        .byte   13, 10, "TALK - text to speech on the SPO256", 13, 10
        .byte   "Type something and press Enter.  /? for help.", 13, 10, 0
s_nochip:
        .byte   "(No SPO256 found: the allophones are only shown.)", 13, 10, 0
s_prompt:
        .byte   13, 10, "> ", 0
s_help: .byte   "  text      speak it", 13, 10
        .byte   "  /F NAME   speak a text file (Esc stops)", 13, 10
        .byte   "  /P        show the allophones on / off", 13, 10
        .byte   "  /A ...    speak allophones: /A HH1 EH LL OW  (or numbers)", 13, 10
        .byte   "  /Q        quit", 13, 10, 0
s_showon:
        .byte   "Allophones shown.", 13, 10, 0
s_showoff:
        .byte   "Allophones not shown.", 13, 10, 0
s_ferr: .byte   "?Can't read it, error $", 0

; punctuation: what it becomes
p_from: .byte   ",;:.!?-", 0
p_to:   .byte   ",,,..?-"

; the pause for each pause phoneme: GAP COMMA STOP ASK
gap_al: .byte   A_PA3, A_PA4, A_PA5, A_PA5

spec_go:
        .word   sp_uw-1, sp_y-1, sp_b-1, sp_d-1, sp_t-1, sp_k-1, sp_g-1
        .word   sp_n-1, sp_r-1, sp_hh-1, sp_dh-1

; number words (spelt for the word list)
W_HUNDRED       = 28
W_THOUSAND      = 29
W_TENS          = 20            ; TWENTY is word 20
num_w:  .word   w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10, w11, w12, w13
        .word   w14, w15, w16, w17, w18, w19, w20, w30, w40, w50, w60, w70
        .word   w80, w90, w100, w1000
w0:     .byte   "ZERO", 0
w1:     .byte   "ONE", 0
w2:     .byte   "TWO", 0
w3:     .byte   "THREE", 0
w4:     .byte   "FOUR", 0
w5:     .byte   "FIVE", 0
w6:     .byte   "SIX", 0
w7:     .byte   "SEVEN", 0
w8:     .byte   "EIGHT", 0
w9:     .byte   "NINE", 0
w10:    .byte   "TEN", 0
w11:    .byte   "ELEVEN", 0
w12:    .byte   "TWELVE", 0
w13:    .byte   "THIRTEEN", 0
w14:    .byte   "FOURTEEN", 0
w15:    .byte   "FIFTEEN", 0
w16:    .byte   "SIXTEEN", 0
w17:    .byte   "SEVENTEEN", 0
w18:    .byte   "EIGHTEEN", 0
w19:    .byte   "NINETEEN", 0
w20:    .byte   "TWENTY", 0
w30:    .byte   "THIRTY", 0
w40:    .byte   "FORTY", 0
w50:    .byte   "FIFTY", 0
w60:    .byte   "SIXTY", 0
w70:    .byte   "SEVENTY", 0
w80:    .byte   "EIGHTY", 0
w90:    .byte   "NINETY", 0
w100:   .byte   "HUNDRED", 0
w1000:  .byte   "THOUSAND", 0

; character classes, $00-$5A
ctab:   .res    $27, 0                  ; $00-$26
        .byte   0                       ; '
        .res    $41 - $28, 0            ; $28-$40
        .byte   C_LET|C_VOW                     ; A
        .byte   C_LET|C_CON|C_VCD               ; B
        .byte   C_LET|C_CON|C_SIB               ; C
        .byte   C_LET|C_CON|C_VCD|C_LNG         ; D
        .byte   C_LET|C_VOW|C_FRN               ; E
        .byte   C_LET|C_CON                     ; F
        .byte   C_LET|C_CON|C_VCD|C_SIB         ; G
        .byte   C_LET|C_CON                     ; H
        .byte   C_LET|C_VOW|C_FRN               ; I
        .byte   C_LET|C_CON|C_VCD|C_SIB|C_LNG   ; J
        .byte   C_LET|C_CON                     ; K
        .byte   C_LET|C_CON|C_VCD|C_LNG         ; L
        .byte   C_LET|C_CON|C_VCD               ; M
        .byte   C_LET|C_CON|C_VCD|C_LNG         ; N
        .byte   C_LET|C_VOW                     ; O
        .byte   C_LET|C_CON                     ; P
        .byte   C_LET|C_CON                     ; Q
        .byte   C_LET|C_CON|C_VCD|C_LNG         ; R
        .byte   C_LET|C_CON|C_SIB|C_LNG         ; S
        .byte   C_LET|C_CON|C_LNG               ; T
        .byte   C_LET|C_VOW                     ; U
        .byte   C_LET|C_CON|C_VCD               ; V
        .byte   C_LET|C_CON|C_VCD               ; W
        .byte   C_LET|C_CON|C_SIB               ; X
        .byte   C_LET|C_VOW|C_FRN               ; Y
        .byte   C_LET|C_CON|C_VCD|C_SIB|C_LNG   ; Z

ldblk:  .word   fbuf
        .word   $7F00 - fbuf
        .res    14

        .include "rules.inc"

; ============================================================================
        .segment "BSS"
show:   .res    1
spo:    .res    1
echo:   .res    1
llen:   .res    1
line:   .res    LINE_MAX + 1
src:    .res    2
send:   .res    2
ti:     .res    1
tend:   .res    1
pn:     .res    1
na:     .res    1
rp:     .res    2
nxt:    .res    2
rend:   .res    1
mofs:   .res    1
rofs:   .res    1
pofs:   .res    1
llen2:  .res    1
py:     .res    1
dir:    .res    1
cnt:    .res    1
cx:     .res    1
k:      .res    1
cur:    .res    1
prev:   .res    1
nxt1:   .res    1
nxt2:   .res    1
wstart: .res    1
nv:     .res    2
nbig:   .res    1
ndig:   .res    1
dg:     .res    16
wv:     .res    2
t1:     .res    1
t2:     .res    1
t3:     .res    1
t4:     .res    1
t5:     .res    1
t6:     .res    1
t7:     .res    1
tbuf:   .res    256
pbuf:   .res    256
abuf:   .res    256
fbuf:                           ; a text file, to $7EFF
