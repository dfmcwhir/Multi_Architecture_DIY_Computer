; ============================================================================
; piano.s - PIANO: play the AY-3-8910 card from the keyboard
;
;   build:  make.bat  (or make)        run:  L PIANO 0500   then   R
;
; Two rows of the keyboard are two octaves of a piano, as in the old trackers:
;
;      2 3   5 6 7   9 0                S D   G H J
;     Q W E R T Y U I O P   (higher)   Z X C V B N M ,   (lower)
;
; The lower row starts at C of the octave shown, the upper row an octave up
; (Q and , are the same C).  The picture of the keyboard shows the keys, and
; each key lights up while its note sounds.
;
;   [ ]  or Tab   the sound: PIANO HARP ORGAN STRINGS CHIP CHORD BUZZ DRUMS
;   - =           octave down / up (1-6)
;   space         all notes off
;   Esc           quit
;
; The terminal says when a key is pressed, never when it is let go, so every
; note ends by itself: each sound has its own shape (the attack, a fall to a
; sustain level, how long that lasts, then the release).  Holding a key down
; still holds the note: the keyboard repeats the key, and a repeat of a note
; that is still sounding keeps it going instead of starting it again.
;
; Three notes at once (the chip's three channels): a new note takes a free
; channel, or the one that has sounded longest.  BUZZ uses the chip's envelope
; as a saw wave (one at a time, on channel A).  DRUMS: each pair of keys is a
; drum: kick, snare, closed hi-hat, open hi-hat, tom (it follows the key),
; crash.
;
; Timing: VIA timer 2, polled (its interrupt stays off), 100 ticks a second;
; the sounds move on every other tick.  Keys are read all the time, and a note
; starts the moment its key comes in.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

VIA_T2CL        = $7F08
VIA_T2CH        = $7F09
VIA_ACR         = $7F0B
VIA_IFR         = $7F0D
VIA_IER         = $7F0E
TICK            = CLOCK_MHZ * 10000 - 2     ; 1/100 s (the timer runs count + 2)
.assert TICK < 65536, error, "the clock is too fast for a 1/100 s tick"

; the screen
SOUND_ROW       = 2
OCT_ROW         = 3
KB_COL          = 6             ; the keyboard picture: 68 columns,
KB_TOP          = 7             ;  rows 7-14; its labels on 6 and 15
CH_ROW          = 17            ; the channels: "A  C-4  bar", rows 17-19
BAR_COL         = 9
HELP_ROW        = 21
CELLS_MAX       = 10            ; screen changes sent at most a frame

        .segment "CODE"
        jmp     start

        .include "common.s"
        .include "ay.s"
        .include "synth.s"

; ---- start ---------------------------------------------------------------------------
start:  cld
        ldx     #$FF
        txs
        jsr     ay_silence
        jsr     syn_init
        lda     VIA_ACR         ; timer 2: one shot, its interrupt off
        and     #$DF
        sta     VIA_ACR
        lda     #$20
        sta     VIA_IER
        ldx     #2
@c:     lda     #$FF
        sta     key,x
        dex
        bpl     @c
        lda     #0
        sta     sound
        lda     #3
        sta     octave
        jsr     draw_screen
        jsr     t_start

; ---- the main loop: keys all the time, the sounds every other tick ----------------------
main:   jsr     getkey
        bcc     @t
        jsr     do_key
@t:     lda     VIA_IFR
        and     #$20
        beq     main
        jsr     t_start
        lda     tick
        eor     #1
        sta     tick
        beq     main
        jsr     step_all
        jsr     show
        jmp     main

t_start:lda     #<TICK
        sta     VIA_T2CL
        lda     #>TICK
        sta     VIA_T2CH        ; (starts it, clears the flag)
        rts

; ---- keys ----------------------------------------------------------------------------
do_key: cmp     #27
        bne     @k1
        jmp     quit
@k1:    ldx     #N_KEYS - 1     ; a note key?
@f:     cmp     key_chr,x
        beq     @note
        dex
        bpl     @f
        cmp     #' '
        bne     :+
        jmp     all_off
:
        cmp     #'['
        beq     @prev
        cmp     #']'
        beq     @next
        cmp     #9
        beq     @next
        cmp     #'-'
        beq     @down
        cmp     #'='
        beq     @up
        cmp     #'+'
        beq     @up
        rts
@note:  lda     key_ofs,x
        jmp     note_on
@prev:  jsr     sound_off_hl
        dec     sound
        bpl     @s
        lda     #N_SOUNDS - 1
        sta     sound
@s:     jmp     sound_on_hl
@next:  jsr     sound_off_hl
        inc     sound
        lda     sound
        cmp     #N_SOUNDS
        bcc     @s
        lda     #0
        sta     sound
        beq     @s
@down:  lda     octave
        cmp     #2
        bcc     @r
        dec     octave
        jmp     show_oct
@up:    lda     octave
        cmp     #6
        bcs     @r
        inc     octave
        jmp     show_oct
@r:     rts

; the key with offset A (0-28 from C of the octave) pressed
note_on:
        sta     k_ofs
        lda     octave          ; the note: (octave - 1) x 12 + the offset
        sec
        sbc     #1
        sta     tmp
        asl
        adc     tmp             ; x 3
        asl
        asl                     ; x 12
        clc
        adc     k_ofs
        sta     k_note
        lda     sound           ; the sound (DRUMS: the drum for the key)
        cmp     #DRUM_KIT - 1
        bne     @ins
        lda     k_ofs
        jsr     mod12
        lsr
        clc
        adc     #DRUM_KIT
@ins:   sta     k_ins
        jsr     ins_ptr
        ldx     #2              ; is the key's note still sounding?
@same:  lda     st,x
        beq     @sn
        lda     key,x
        cmp     k_ofs
        bne     @sn
        lda     ins,x
        cmp     k_ins
        beq     @rep
@sn:    dex
        bpl     @same
        ldy     #I_FLAGS        ; BUZZ: always channel A
        lda     cur_ins,y
        and     #F_BUZZ
        beq     @free
        ldx     #0
        beq     @go
@free:  ldx     #2              ; a free channel
@fr:    lda     st,x
        beq     @go
        dex
        bpl     @fr
        ldx     #0              ; or the one that has sounded longest
        lda     age
        cmp     age+1
        bcs     @o1
        ldx     #1
        lda     age+1
@o1:    cmp     age+2
        bcs     @go
        ldx     #2
        bne     @go
@go:    lda     k_ofs           ; (for lighting its key)
        sta     key,x
        jmp     syn_start
@rep:   ldy     #I_REP          ; again soon after: a key repeat, it holds
        lda     last,x
        cmp     cur_ins,y
        bcs     @go             ; (later: played again)
        lda     #HOLD
        sta     hold,x
        lda     #0
        sta     last,x
        rts

; ---- the screen ------------------------------------------------------------------------
; the cursor to column X, row Y (keeps A, X, Y)
goto:   pha
        lda     #$0E
        jsr     SBC_CHROUT
        txa
        jsr     SBC_CHROUT
        lda     #$0F
        jsr     SBC_CHROUT
        tya
        jsr     SBC_CHROUT
        pla
        rts

; the attribute A (only sent when it changes; keeps X, Y)
set_attr:
        cmp     cur_attr
        beq     @r
        sta     cur_attr
        pha
        lda     #$18
        jsr     SBC_CHROUT
        pla
        jsr     SBC_CHROUT
@r:     rts

; a graphics cell A (under $20: as 1A n)
gcell:  cmp     #$20
        bcs     @p
        pha
        lda     #$1A
        jsr     SBC_CHROUT
        pla
@p:     jmp     SBC_CHROUT

draw_screen:
        lda     #$FF
        sta     cur_attr
        lda     #0
        jsr     set_attr
        lda     #12
        jsr     SBC_CHROUT
        PRINT   title_txt
        jsr     draw_sounds
        jsr     show_oct
        ldx     #0
        ldy     #HELP_ROW
        jsr     goto
        PRINT   help_txt
        ldx     #KB_COL - 1     ; the labels: black keys above, white below
        ldy     #KB_TOP - 1
        jsr     goto
        PRINT   black_txt
        ldx     #KB_COL - 1
        ldy     #KB_TOP + 8
        jsr     goto
        PRINT   white_txt
        ldx     #0              ; the channels
@ch:    stx     cx
        ldy     cx
        tya
        clc
        adc     #CH_ROW
        tay
        ldx     #0
        jsr     goto
        lda     cx
        clc
        adc     #'A'
        jsr     SBC_CHROUT
        ldx     cx
        lda     #$FE            ; (to be shown)
        sta     note_shown,x
        inx
        cpx     #3
        bne     @ch
        ldx     #0              ; nothing lit, the bars empty
        lda     #0
@z:     sta     lit_shown,x
        inx
        cpx     #29
        bne     @z
        ldx     #23
@zb:    sta     bar_shown,x
        dex
        bpl     @zb
        ; the keyboard: 8 rows of 68 cells
        lda     #<kb_cells
        sta     @ld+1
        lda     #>kb_cells
        sta     @ld+2
        lda     #0
        sta     tmp2            ; the row
@row:   ldx     #KB_COL
        lda     tmp2
        clc
        adc     #KB_TOP
        tay
        jsr     goto
        lda     #$80
        jsr     set_attr
        ldx     #68
@ld:    lda     $FFFF
        jsr     gcell
        inc     @ld+1
        bne     :+
        inc     @ld+2
:       dex
        bne     @ld
        inc     tmp2
        lda     tmp2
        cmp     #8
        bne     @row
        lda     #0
        jmp     set_attr

; the sound names, the one in use in reverse
draw_sounds:
        lda     sound
        pha
        lda     #0
        sta     sound
@l:     jsr     sound_off_hl
        inc     sound
        lda     sound
        cmp     #N_SOUNDS
        bne     @l
        pla
        sta     sound
        jmp     sound_on_hl

sound_on_hl:
        jsr     sound_at
        PRINT   rev_txt
        jsr     sound_name
        PRINT   norm_txt
        rts
sound_off_hl:
        jsr     sound_at
        jmp     sound_name

; the cursor to the name of sound (sound): column 9 x n
sound_at:
        lda     sound
        asl
        asl
        asl
        adc     sound
        tax
        ldy     #SOUND_ROW
        jmp     goto

; print the name of sound (sound)
sound_name:
        lda     sound
        asl
        asl
        asl
        clc
        adc     #<names
        pha
        lda     #0
        adc     #>names
        tay
        pla
        jmp     print8

; print 8 characters at A/Y
print8: sta     @ld+1
        sty     @ld+2
        ldx     #0
@ld:    lda     $FFFF,x
        jsr     SBC_CHROUT
        inx
        cpx     #8
        bne     @ld
        rts

show_oct:
        ldx     #0
        ldy     #OCT_ROW
        jsr     goto
        PRINT   oct_txt
        lda     octave
        ora     #'0'
        jsr     SBC_CHROUT
        PRINT   oct2_txt
        lda     octave          ; the lower row's C, and the top of the upper
        ora     #'0'
        jsr     SBC_CHROUT
        PRINT   oct3_txt
        lda     octave
        clc
        adc     #'2'
        jmp     SBC_CHROUT

; once a frame: what changed, at most CELLS_MAX things
show:   lda     #CELLS_MAX
        sta     n_left
        ldx     #28             ; the keys lit: those of the notes sounding
        lda     #0
@w0:    sta     lit_want,x
        dex
        bpl     @w0
        ldx     #2
@w1:    lda     st,x
        beq     @w2
        ldy     key,x
        lda     #1
        sta     lit_want,y
@w2:    dex
        bpl     @w1
        ldx     #0
@k:     lda     lit_want,x
        cmp     lit_shown,x
        beq     @kn
        sta     lit_shown,x
        stx     tmp3
        lda     #$90            ; (block graphics, repeated twice)
        jsr     set_attr
        lda     mk_row,x
        clc
        adc     #KB_TOP
        tay
        lda     mk_col,x
        clc
        adc     #KB_COL
        tax
        jsr     goto
        ldx     tmp3
        lda     mk_norm,x
        ldy     lit_shown,x
        beq     :+
        lda     mk_on,x
:       jsr     gcell
        dec     n_left
        bne     :+
        jmp     @done
:       ldx     tmp3
@kn:    inx
        cpx     #29
        bne     @k
        ldx     #0              ; the channels: the note's name and a bar
@c:     stx     cx
        lda     #$FF            ; (off: "---")
        ldy     st,x
        beq     :+
        lda     note,x
:       cmp     note_shown,x
        beq     @bar
        sta     note_shown,x
        pha
        lda     #0
        jsr     set_attr
        txa
        clc
        adc     #CH_ROW
        tay
        ldx     #3
        jsr     goto
        pla
        jsr     pr_note
        ldx     cx
        dec     n_left
        beq     @done
@bar:   lda     vol,x           ; the bar: the volume, 8 cells of 2 levels
        lsr
        lsr
        lsr
        lsr
        sta     tmp             ; level 0-15
        txa
        asl
        asl
        asl
        sta     tmp3            ; the channel's first cell
        lda     #1
        sta     tmp2            ; the cell's lower level
@bc:    lda     #0
        ldy     tmp
        cpy     tmp2
        bcc     @bv
        lda     #$55            ; (the left half)
        beq     @bv
        iny
        dey
        cpy     tmp2
        beq     @bv
        lda     #$FF
@bv:    ldy     tmp3
        cmp     bar_shown,y
        beq     @bn
        sta     bar_shown,y
        pha
        lda     #$80
        jsr     set_attr
        lda     cx
        clc
        adc     #CH_ROW
        tay
        lda     tmp3
        and     #7
        clc
        adc     #BAR_COL
        tax
        jsr     goto
        pla
        jsr     gcell
        dec     n_left
        beq     @done
@bn:    inc     tmp3
        inc     tmp2
        inc     tmp2
        lda     tmp3
        and     #7
        bne     @bc
        ldx     cx
        inx
        cpx     #3
        beq     @done
        jmp     @c
@done:  lda     #0
        jmp     set_attr

; print note A as "C#4" ($FF: "---")
pr_note:
        cmp     #$FF
        bne     @n
        PRINT   none_txt
        rts
@n:     ldx     #1              ; the octave: note / 12 + 1
@o:     cmp     #12
        bcc     @s
        sbc     #12
        inx
        bne     @o
@s:     asl
        tay
        lda     note_names,y
        jsr     SBC_CHROUT
        lda     note_names+1,y
        jsr     SBC_CHROUT
        txa
        ora     #'0'
        jmp     SBC_CHROUT

quit:   jsr     ay_silence
        lda     #0
        jsr     set_attr
        PRINT   norm_txt
        lda     #12
        jsr     SBC_CHROUT
        PRINT   bye_txt
        jmp     SBC_MENU

; ---- tables ---------------------------------------------------------------------------
; the note keys and their offsets from C of the octave
key_chr:    .byte   "ZSXDCVGBHNJM,"
            .byte   "Q2W3ER5T6Y7UI9O0P"
key_ofs:    .byte   0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
            .byte   12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28
N_KEYS      = key_ofs - key_chr

note_names: .byte   "C-C#D-D#E-F-F#G-G#A-A#B-"

; the keyboard picture: 8 rows of 68 cells (2 x 4 pixels each), white keys
; 8 pixels wide, black keys 4 wide and 20 high; then where each key's marker
; goes (a key lights up by these 2 cells changing)
kb_cells:
        .byte   $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00
        .byte   $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF
        .byte   $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF
        .byte   $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00
        .byte   $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF
        .byte   $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF
        .byte   $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00
        .byte   $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF
        .byte   $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF
        .byte   $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00
        .byte   $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF
        .byte   $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF
        .byte   $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00
        .byte   $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF
        .byte   $FF, $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF
        .byte   $00, $00, $FF, $FF, $55, $FF, $FF, $FF, $00, $00, $FF, $FF, $00, $00, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF
        .byte   $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF
        .byte   $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF
        .byte   $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF
        .byte   $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF
        .byte   $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF
        .byte   $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55
        .byte   $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF
        .byte   $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF
        .byte   $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF
        .byte   $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55, $FF, $FF, $FF, $55
; markers, for key offsets 0-28: column, row, the cell as drawn, pressed
mk_col: .byte   1, 3, 5, 7, 9, 13, 15, 17, 19, 21, 23, 25, 29, 31, 33, 35, 37, 41, 43, 45, 47, 49, 51, 53, 57, 59, 61, 63, 65
mk_row: .byte   7, 4, 7, 4, 7, 7, 4, 7, 4, 7, 4, 7, 7, 4, 7, 4, 7, 7, 4, 7, 4, 7, 4, 7, 7, 4, 7, 4, 7
mk_norm:.byte   $FF, $00, $FF, $00, $FF, $FF, $00, $FF, $00, $FF, $00, $FF, $FF, $00, $FF, $00, $FF, $FF, $00, $FF, $00, $FF, $00, $FF, $FF, $00, $FF, $00, $FF
mk_on:  .byte   $0F, $FF, $0F, $FF, $0F, $0F, $FF, $0F, $FF, $0F, $FF, $0F, $0F, $FF, $0F, $FF, $0F, $0F, $FF, $0F, $FF, $0F, $FF, $0F, $0F, $FF, $0F, $FF, $0F

; ---- text -----------------------------------------------------------------------------
title_txt:  .byte   "PIANO - PLAY THE AY-3-8910 FROM THE KEYBOARD", 0
oct_txt:    .byte   "OCTAVE ", 0
oct2_txt:   .byte   "    Z = C", 0
oct3_txt:   .byte   "   P = E", 0
help_txt:   .byte   "[ ] OR TAB: SOUND   - =: OCTAVE   SPACE: ALL OFF   ESC: QUIT", 13, 10
            .byte   "NOTES END BY THEMSELVES; HOLD A KEY DOWN TO HOLD ITS NOTE", 0
black_txt:  .byte   "    S   D       G   H   J       2   3       5   6   7       9   0", 0
white_txt:  .byte   "  Z   X   C   V   B   N   M   Q   W   E   R   T   Y   U   I   O   P", 0
none_txt:   .byte   "---", 0
rev_txt:    .byte   27, "[7m", 0
norm_txt:   .byte   27, "[0m", 0
bye_txt:    .byte   "BYE", 13, 10, 0

; ---- variables -------------------------------------------------------------------------
        .segment "BSS"
sound:      .res 1
octave:     .res 1
tick:       .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
k_ofs:      .res 1
n_left:     .res 1
cur_attr:   .res 1
key:        .res 3              ;  the key (offset), for lighting it
note_shown: .res 3
lit_want:   .res 29
lit_shown:  .res 29
bar_shown:  .res 24
