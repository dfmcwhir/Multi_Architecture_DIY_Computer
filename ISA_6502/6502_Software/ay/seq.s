; ============================================================================
; seq.s - SEQ: a step sequencer for the AY-3-8910 card (a small "Fruity Loops")
;
;   build:  make.bat  (or make)        run:  L SEQ 0500   then   R
;
; A pattern is 16 steps (16th notes) of 7 tracks: five drums (KICK, SNARE,
; HI-HAT, OPEN HAT, CRASH) and two note tracks (BASS and LEAD), each with a
; sound from PIANO's eight.  There are 4 patterns, A-D: playing goes through
; the ones in use, A to the last that has anything in it, and round again (or
; ";" keeps it on the pattern on screen).  The sounds are PIANO's (synth.s).
;
;   arrows          move (up/down: the track, left/right: the step)
;   note keys       a note on BASS or LEAD (as in PIANO: Z S X D C V G B H N
;                   J M , and Q 2 W 3 E R 5 T 6 Y 7 U I 9 O 0 P), heard as it
;                   goes in, and on to the next step; on a drum: the drum on
;   space           a drum on/off, a note out
;   .               a note held on from the step before
;   Backspace       out, and back a step
;   Enter           play / stop                ;  all patterns / this one
;   - =             tempo (40-250)             [ ]  octave of the note keys
;   K L             the pattern: A B C D       Tab  the sound of BASS/LEAD
;   F               files: S save, L load (to BEAT1.SEQ ... BEAT9.SEQ in the
;                   monitor's current folder), N new, C copy the pattern before
;   Esc             quit (it asks)
;
; The three channels: A plays BASS, B plays LEAD, C the drums (one at a time:
; on a step with more than one, kick, then snare, crash, open hat, hi-hat).
; A note sounds for its step, longer if the next steps hold it (".").
;
; Timing: VIA timer 2, polled, 100 ticks a second; the steps come from the
; tempo with an exact running count (no drift), the sounds move every other
; tick.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"
CH_WRITE        = 1             ; (ch376r.s: writing too)

VIA_T2CL        = $7F08
VIA_T2CH        = $7F09
VIA_ACR         = $7F0B
VIA_IFR         = $7F0D
VIA_IER         = $7F0E
TICK            = CLOCK_MHZ * 10000 - 2     ; 1/100 s (the timer runs count + 2)
.assert TICK < 65536, error, "the clock is too fast for a 1/100 s tick"
.ifndef SBC_CWD
SBC_CWD         = $FE18
.endif
CWD_MAX         = 31

N_TRACKS        = 7
N_DRUMS         = 5
T_BASS          = 5
T_LEAD          = 6
STEPS           = 16
N_PATS          = 4
EMPTY           = $FF           ; a note step: nothing
TIE             = $FE           ;  the note before, held on

; the screen
GRID_COL        = 11            ; step s at GRID_COL + 4 s + s / 4
NUM_ROW         = 3
HEAD_ROW        = 4
TRACK_ROW       = 5             ; the tracks: rows 5-11
SND_ROW         = 13
HELP_ROW        = 15
MSG_ROW         = 20

        .segment "CODE"
        jmp     start

        .include "common.s"
        .include "ay.s"
        .include "synth.s"
        .include "ch376r.s"

; ---- start ---------------------------------------------------------------------------
start:  cld
        ldx     #$FF
        txs
        jsr     ay_silence
        jsr     syn_init
        lda     #1
        sta     gate_mode
        lda     VIA_ACR         ; timer 2: one shot, its interrupt off
        and     #$DF
        sta     VIA_ACR
        lda     #$20
        sta     VIA_IER
        lda     #0              ; the monitor's current folder (SBC_CWD), as
        sta     cwd_buf         ;  in YMPLAY: files go there
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
@nocwd: jsr     song_new
        lda     #0
        sta     pat
        sta     playing
        sta     loop_one
        sta     cur_tr
        sta     cur_st
        sta     tick
        lda     #3
        sta     octave
        jsr     draw_screen
        jsr     t_start

; ---- the main loop: keys all the time; steps from the tempo; sounds every other tick ----
main:   jsr     getkey
        bcc     @t
        jsr     do_key
@t:     lda     VIA_IFR
        and     #$20
        beq     main
        jsr     t_start
        lda     playing         ; the steps: acc += tempo a tick, a step at 1500
        beq     @snd            ;  (1500 / tempo ticks = a 16th note)
        lda     acc
        clc
        adc     song_tempo
        sta     acc
        bcc     :+
        inc     acc+1
:       lda     acc+1
        cmp     #>1500
        bcc     @snd
        bne     @st
        lda     acc
        cmp     #<1500
        bcc     @snd
@st:    lda     acc
        sec
        sbc     #<1500
        sta     acc
        lda     acc+1
        sbc     #>1500
        sta     acc+1
        jsr     play_step
@snd:   lda     tick
        eor     #1
        sta     tick
        beq     main
        jsr     step_all
        jmp     main

t_start:lda     #<TICK
        sta     VIA_T2CL
        lda     #>TICK
        sta     VIA_T2CH
        rts

; ---- playing ---------------------------------------------------------------------------
; Enter: play from the start of the pattern on screen / stop
play_stop:
        lda     playing
        beq     @go
        lda     #0
        sta     playing
        jsr     all_off
        jsr     head_off
        jmp     show_play
@go:    lda     pat
        sta     play_pat
        lda     #$FF            ; (the first step comes at once)
        sta     play_pos
        lda     #<1500
        sta     acc
        lda     #>1500
        sta     acc+1
        lda     #1
        sta     playing
        jmp     show_play

; the next step: its drum and notes
play_step:
        inc     play_pos
        lda     play_pos
        cmp     #STEPS
        bcc     @in
        lda     #0              ; the end of the pattern: the next one (or
        sta     play_pos        ;  this one again)
        lda     loop_one
        bne     @one
        inc     play_pat
        lda     play_pat
        cmp     #N_PATS
        bcs     @first
        jsr     pat_used        ; (patterns after the last in use: back to A)
        bne     @shown
        lda     play_pat
        jsr     later_used
        bne     @shown
@first: lda     #0
        sta     play_pat
        beq     @shown
@one:   lda     pat
        sta     play_pat
@shown: jsr     show_play
@in:    jsr     head_show
        lda     play_pat        ; Y = the step's index: pattern x 16 + step
        asl
        asl
        asl
        asl
        ora     play_pos
        sta     sx
        ; the drum: the first in kick, snare, crash, open hat, hi-hat order
        tay
        lda     drums,y
        beq     @notes
        ldx     #0
@pr:    ldy     drum_order,x
        and     drum_bit,y
        bne     @hit
        ldy     sx
        lda     drums,y
        inx
        cpx     #N_DRUMS
        bne     @pr
        beq     @notes
@hit:   lda     drum_ins,y
        sta     k_ins
        lda     #0
        sta     k_note
        ldx     #2
        jsr     syn_start
        ; the notes: BASS on channel A, LEAD on B
@notes: ldy     sx
        lda     bass,y
        ldx     #0
        jsr     step_note
        ldy     sx
        lda     lead,y
        ldx     #1
        ; (on into step_note)

; channel X, step value A: a note, a held one, or nothing
step_note:
        cmp     #EMPTY
        beq     @r
        cmp     #TIE
        bne     @note
        lda     st,x            ; held on: longer, if it still sounds
        beq     @r
        lda     hold,x
        clc
        adc     gate
        bcc     :+
        lda     #255
:       sta     hold,x
        lda     #ST_SUS         ; (back to the sustain if it had let go)
        cmp     st,x
        bcs     @r
        sta     st,x
@r:     rts
@note:  sta     k_note
        lda     snd,x
        sta     k_ins
        lda     gate
        sta     hold,x
        jmp     syn_start

; Z clear if pattern play_pat has anything in it
pat_used:
        lda     play_pat
        ; (on)
; Z clear if pattern A has anything in it (keeps X)
used_a: asl
        asl
        asl
        asl
        tay
        lda     #STEPS
        sta     cnt
@l:     lda     drums,y
        bne     @y
        lda     bass,y
        cmp     #EMPTY
        bne     @y
        lda     lead,y
        cmp     #EMPTY
        bne     @y
        iny
        dec     cnt
        bne     @l
        lda     #0
        rts
@y:     lda     #1
        rts

; Z clear if a pattern after A has anything in it
later_used:
        sta     tmp
@l:     inc     tmp
        lda     tmp
        cmp     #N_PATS
        bcs     @n
        jsr     used_a
        beq     @l
        rts
@n:     lda     #0
        rts

; the gate: frames in a step (750 / tempo at 50 frames a second), + 1
set_gate:
        lda     #<750
        sta     acc2
        lda     #>750
        sta     acc2+1
        ldx     #0
@d:     lda     acc2
        sec
        sbc     song_tempo
        tay
        lda     acc2+1
        sbc     #0
        bcc     @e
        sta     acc2+1
        sty     acc2
        inx
        bne     @d
@e:     inx
        stx     gate
        rts

; ---- keys ----------------------------------------------------------------------------
do_key: cmp     #27
        bne     :+
        jmp     esc_key
:       ldx     #N_KEYS - 1     ; a note key?
@f:     cmp     key_chr,x
        beq     @note
        dex
        bpl     @f
        ldx     #N_CMDS - 1     ; a command
@c:     cmp     cmd_chr,x
        beq     @cmd
        dex
        bpl     @c
        rts
@note:  lda     key_ofs,x
        jmp     note_key
@cmd:   txa
        asl
        tax
        lda     cmd_adr+1,x
        pha
        lda     cmd_adr,x
        pha
        rts                     ; (to the command: its address - 1 is pushed)

cmd_chr:    .byte   " ", ".", 8, 127, 13, ";", "-", "=", "+", "[", "]", "K", "L", 9, "F"
N_CMDS      = * - cmd_chr
cmd_adr:    .word   space_key-1, tie_key-1, back_key-1, back_key-1, play_stop-1, loop_key-1
            .word   tempo_dn-1, tempo_up-1, tempo_up-1, oct_dn-1, oct_up-1
            .word   pat_prev-1, pat_next-1, sound_key-1, file_key-1

; Esc: an arrow key (Esc [ A-D, or Esc O A-D), or quit
esc_key:
        jsr     key_wait        ; (the rest of the sequence comes at once)
        bcc     @quit
        cmp     #'['
        beq     @arr
        cmp     #'O'
        bne     @quit
@arr:   jsr     key_wait
        bcc     @r
        cmp     #'A'
        beq     up_key
        cmp     #'B'
        beq     down_key
        cmp     #'C'
        beq     right_key
        cmp     #'D'
        beq     left_key
@r:     rts
@quit:  jmp     quit_ask

; a key within about 20 ms: carry set and A = it (as typed), or carry clear
key_wait:
        lda     #20
        sta     cnt
@l:     jsr     SBC_CHRIN
        bcs     @r
        lda     #1
        jsr     delay_ms
        dec     cnt
        bne     @l
        clc
@r:     rts

up_key: jsr     cell_plain
        dec     cur_tr
        bpl     cur_show
        lda     #N_TRACKS - 1
        sta     cur_tr
        bne     cur_show
down_key:
        jsr     cell_plain
        inc     cur_tr
        lda     cur_tr
        cmp     #N_TRACKS
        bcc     cur_show
        lda     #0
        sta     cur_tr
        beq     cur_show
left_key:
        jsr     cell_plain
step_back:
        dec     cur_st
        bpl     cur_show
        lda     #STEPS - 1
        sta     cur_st
        bne     cur_show
right_key:
        jsr     cell_plain
step_on:
        inc     cur_st
        lda     cur_st
        cmp     #STEPS
        bcc     cur_show
        lda     #0
        sta     cur_st
cur_show:
        jmp     cell_cursor

; Y = the index of the cursor's step (pattern x 16 + step)
cur_idx:
        lda     pat
        asl
        asl
        asl
        asl
        ora     cur_st
        tay
        rts

; space: a drum on/off; a note out
space_key:
        jsr     cur_idx
        lda     cur_tr
        cmp     #N_DRUMS
        bcs     @n
        tax
        lda     drums,y
        eor     drum_bit,x
        sta     drums,y
        and     drum_bit,x
        beq     @s
        jsr     drum_hear
@s:     jmp     cell_cursor
@n:     lda     #EMPTY
        jsr     put_note
        jmp     cell_cursor

; Backspace: out, and back a step
back_key:
        jsr     cur_idx
        lda     cur_tr
        cmp     #N_DRUMS
        bcs     @n
        tax
        lda     drum_bit,x
        eor     #$FF
        and     drums,y
        sta     drums,y
        jmp     @b
@n:     lda     #EMPTY
        jsr     put_note
@b:     jsr     cell_plain
        jmp     step_back

; ".": the note before held on
tie_key:
        lda     cur_tr
        cmp     #N_DRUMS
        bcc     @r
        jsr     cur_idx
        lda     #TIE
        jsr     put_note
        jsr     cell_plain
        jmp     step_on
@r:     rts

; the step's note on its track = A (Y = its index)
put_note:
        ldx     cur_tr
        cpx     #T_BASS
        bne     @l
        sta     bass,y
        rts
@l:     sta     lead,y
        rts

; a note key (offset A from C of the octave): the note in, heard, on a step;
; on a drum track: the drum on, heard
note_key:
        sta     tmp
        lda     cur_tr
        cmp     #N_DRUMS
        bcs     @note
        jsr     cur_idx
        ldx     cur_tr
        lda     drums,y
        ora     drum_bit,x
        sta     drums,y
        jsr     drum_hear
        jmp     cell_cursor
@note:  lda     octave          ; the note: (octave - 1) x 12 + the offset
        sec
        sbc     #1
        sta     tmp2
        asl
        adc     tmp2
        asl
        asl
        clc
        adc     tmp
        cmp     #AY_NOTES
        bcc     :+
        lda     #AY_NOTES - 1
:       pha
        jsr     cur_idx
        pla
        pha
        jsr     put_note
        pla
        sta     k_note          ; heard: on its channel, for a step
        ldx     cur_tr
        lda     snd-T_BASS,x
        sta     k_ins
        lda     cur_tr
        sec
        sbc     #T_BASS
        tax
        lda     gate
        sta     hold,x
        jsr     syn_start
        jsr     cell_plain
        jmp     step_on

; the cursor's drum, heard on channel C
drum_hear:
        ldx     cur_tr
        lda     drum_ins,x
        sta     k_ins
        lda     #0
        sta     k_note
        ldx     #2
        jmp     syn_start

loop_key:
        lda     loop_one
        eor     #1
        sta     loop_one
        jmp     show_play

tempo_dn:
        lda     song_tempo
        sec
        sbc     #5
        cmp     #40
        bcs     tempo_set
        lda     #40
        bne     tempo_set
tempo_up:
        lda     song_tempo
        clc
        adc     #5
        cmp     #251
        bcc     tempo_set
        lda     #250
tempo_set:
        sta     song_tempo
        jsr     set_gate
        jmp     show_status

oct_dn: lda     octave
        cmp     #2
        bcc     :+
        dec     octave
:       jmp     show_status
oct_up: lda     octave
        cmp     #6
        bcs     :+
        inc     octave
:       jmp     show_status

pat_prev:
        dec     pat
        bpl     :+
        lda     #N_PATS - 1
        sta     pat
:       jmp     pat_shown
pat_next:
        inc     pat
        lda     pat
        cmp     #N_PATS
        bcc     pat_shown
        lda     #0
        sta     pat
pat_shown:
        lda     loop_one        ; (playing just this one: now the new one)
        beq     :+
        lda     pat
        sta     play_pat
:       jsr     show_status
        jsr     draw_grid
        jmp     show_play

; Tab: the next sound for BASS or LEAD (PIANO's first 7: not DRUMS)
sound_key:
        lda     cur_tr
        sec
        sbc     #T_BASS
        bcc     @r
        tax
        inc     snd,x
        lda     snd,x
        cmp     #N_SOUNDS - 1
        bcc     :+
        lda     #0
        sta     snd,x
:       jmp     show_sounds
@r:     rts

; ---- the song --------------------------------------------------------------------------
; all patterns empty, tempo 120, BASS on BUZZ, LEAD on CHIP
song_new:
        ldx     #0
@c:     lda     #0
        sta     drums,x
        lda     #EMPTY
        sta     bass,x
        sta     lead,x
        inx
        cpx     #STEPS * N_PATS
        bne     @c
        ldx     #3
@s:     lda     seq_sig,x
        sta     song,x
        dex
        bpl     @s
        lda     #120
        sta     song_tempo
        lda     #6              ; BUZZ
        sta     snd
        lda     #4              ; CHIP
        sta     snd+1
        jmp     set_gate

; ---- files: BEAT1.SEQ ... BEAT9.SEQ in the monitor's current folder ------------------
file_key:
        lda     playing         ; (stopped first)
        beq     :+
        jsr     play_stop
:       jsr     msg_at
        PRINT   file_txt
        jsr     waitkey
        cmp     #'S'
        beq     @save
        cmp     #'L'
        bne     :+
        jmp     @load
:       cmp     #'N'
        beq     @new
        cmp     #'C'
        beq     @copy
        jmp     msg_clear
@new:   jsr     msg_at
        PRINT   sure_txt
        jsr     waitkey
        cmp     #'Y'
        beq     :+
        jmp     msg_clear
:       jsr     song_new
        jsr     draw_screen
        jsr     msg_at
        PRINT   new_txt
        rts
@copy:  lda     pat             ; the pattern before (A: from D) into this one
        sec
        sbc     #1
        and     #3
        asl
        asl
        asl
        asl
        tax
        jsr     cur_idx
        tya
        and     #$F0
        tay
        lda     #STEPS
        sta     cnt
@cp:    lda     drums,x
        sta     drums,y
        lda     bass,x
        sta     bass,y
        lda     lead,x
        sta     lead,y
        inx
        iny
        dec     cnt
        bne     @cp
        jsr     draw_grid
        jsr     msg_at
        PRINT   copied_txt
        rts
@save:  jsr     slot_ask
        bcc     @r
        jsr     drive_in
        bcs     @err
        lda     fname_a
        ldy     fname_a+1
        jsr     ch_create
        cmp     #USB_INT_SUCCESS
        bne     @err
        lda     #<song
        sta     ch_ptr
        lda     #>song
        sta     ch_ptr+1
        lda     #<SONG_LEN
        sta     ch_len
        lda     #>SONG_LEN
        sta     ch_len+1
        jsr     ch_write
        cmp     #USB_INT_SUCCESS
        bne     @err
        jsr     ch_close_w
        cmp     #USB_INT_SUCCESS
        bne     @err
        jsr     msg_at
        PRINT   saved_txt
        jmp     msg_name
@r:     jmp     msg_clear
@err:   pha
        jsr     msg_at
        PRINT   ferr_txt
        pla
        jmp     prhex
@load:  jsr     slot_ask
        bcc     @r
        jsr     drive_in
        bcs     @err
        lda     fname_a
        ldy     fname_a+1
        jsr     ch_open
        cmp     #USB_INT_SUCCESS
        bne     @nf
        lda     #<fbuf
        sta     ch_ptr
        lda     #>fbuf
        sta     ch_ptr+1
        lda     #<SONG_LEN
        sta     ch_len
        lda     #>SONG_LEN
        sta     ch_len+1
        jsr     ch_read
        jsr     ch_close
        lda     ch_got
        cmp     #<SONG_LEN
        bne     @bad
        ldx     #3
@sig:   lda     fbuf,x
        cmp     seq_sig,x
        bne     @bad
        dex
        bpl     @sig
        ldx     #0
@cp2:   lda     fbuf,x
        sta     song,x
        inx
        cpx     #<SONG_LEN
        bne     @cp2
        lda     song_tempo      ; (kept in range)
        cmp     #40
        bcs     :+
        lda     #120
        sta     song_tempo
:       ldx     #1
@sn:    lda     snd,x
        cmp     #N_SOUNDS - 1
        bcc     :+
        lda     #0
        sta     snd,x
:       dex
        bpl     @sn
        jsr     set_gate
        lda     #0
        sta     pat
        jsr     draw_screen
        jsr     msg_at
        PRINT   loaded_txt
        jmp     msg_name
@nf:    jsr     msg_at
        PRINT   nofile_txt
        jmp     msg_name
@bad:   jsr     msg_at
        PRINT   badfile_txt
        jmp     msg_name

; which slot (1-9)?  carry set: fname = "BEATn.SEQ", fname_a its address (with
; a "/" in front for the top folder)
slot_ask:
        jsr     msg_at
        PRINT   slot_txt
        jsr     waitkey
        cmp     #'1'
        bcc     @no
        cmp     #'9' + 1
        bcs     @no
        sta     fname_n
        lda     #<fname
        ldy     #>fname
        ldx     cwd_buf
        bne     :+
        lda     #<fpath
        ldy     #>fpath
:       sta     fname_a
        sty     fname_a+1
        sec
        rts
@no:    clc
        rts

; into the folder: the drive as the monitor left it, or started afresh;
; carry set and A = the status if it can't be done
drive_in:
        jsr     ch_check
        lda     #1
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

; into the folder (the top: open "/"): Z set if it went well, else A = the status
go_in:  lda     cwd_buf
        bne     @in
        lda     #<fpath_root
        ldy     #>fpath_root
        jsr     ch_open
        cmp     #ERR_OPEN_DIR
        rts
@in:    lda     #<cwd_buf
        ldy     #>cwd_buf
        jsr     ch_enter
        cmp     #ERR_OPEN_DIR
        rts

; the file's name and folder after a message
msg_name:
        PRINT   fname
        PRINT   in_txt
        lda     cwd_buf
        bne     :+
        lda     #'/'
        jmp     SBC_CHROUT
:       PRINT   cwd_buf
        rts

; Esc: quit?
quit_ask:
        jsr     msg_at
        PRINT   quit_txt
        jsr     waitkey
        cmp     #'Y'
        beq     :+
        jmp     msg_clear
:       jsr     ay_silence
        PRINT   norm_txt
        lda     #12
        jsr     SBC_CHROUT
        PRINT   bye_txt
        jmp     SBC_MENU

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

msg_at: ldx     #0
        ldy     #MSG_ROW
        jsr     goto
        PRINT   blank_txt       ; (the line cleared)
        ldx     #0
        ldy     #MSG_ROW
        jmp     goto
msg_clear:
        jsr     msg_at
        rts

draw_screen:
        PRINT   norm_txt
        lda     #12
        jsr     SBC_CHROUT
        PRINT   title_txt
        ldx     #GRID_COL       ; the step numbers
        ldy     #NUM_ROW
        jsr     goto
        ldx     #0
@n:     stx     sx
        txa
        jsr     step_col
        tax
        ldy     #NUM_ROW
        jsr     goto
        lda     sx
        clc
        adc     #1
        jsr     prdec2
        ldx     sx
        inx
        cpx     #STEPS
        bne     @n
        ldx     #0              ; the track names
@t:     stx     sx
        txa
        clc
        adc     #TRACK_ROW
        tay
        ldx     #0
        jsr     goto
        lda     sx
        asl
        asl
        asl
        clc
        adc     #<track_names
        pha
        lda     #0
        adc     #>track_names
        tay
        pla
        jsr     print8
        ldx     sx
        inx
        cpx     #N_TRACKS
        bne     @t
        ldx     #0
        ldy     #HELP_ROW
        jsr     goto
        PRINT   help_txt
        lda     #$FF
        sta     head_col
        jsr     show_status
        jsr     show_sounds
        jsr     show_play
        ; (on into draw_grid)

; every cell of the pattern on screen
draw_grid:
        lda     cur_tr
        pha
        lda     cur_st
        pha
        lda     #0
        sta     cur_tr
@tr:    lda     #0
        sta     cur_st
@st:    jsr     cell_plain
        inc     cur_st
        lda     cur_st
        cmp     #STEPS
        bne     @st
        inc     cur_tr
        lda     cur_tr
        cmp     #N_TRACKS
        bne     @tr
        pla
        sta     cur_st
        pla
        sta     cur_tr
        jmp     cell_cursor

; A = the column of step A
step_col:
        sta     tmp
        asl
        asl
        clc
        adc     #GRID_COL
        sta     tmp2
        lda     tmp
        lsr
        lsr
        clc
        adc     tmp2
        rts

; the cursor's cell, in reverse / as it is
cell_cursor:
        PRINT   rev_txt
        jsr     cell_draw
        PRINT   norm_txt
        rts
cell_plain:
        ; (on)
; the cell at cur_tr, cur_st: " # " / " . " (drums), "C#4" " . " " - " (notes)
cell_draw:
        lda     cur_st
        jsr     step_col
        tax
        lda     cur_tr
        clc
        adc     #TRACK_ROW
        tay
        jsr     goto
        jsr     cur_idx
        lda     cur_tr
        cmp     #N_DRUMS
        bcs     @note
        tax
        lda     drums,y
        and     drum_bit,x
        beq     @dot
        PRINT   hit_txt
        rts
@dot:   PRINT   dot_txt
        rts
@note:  cmp     #T_BASS
        bne     @l
        lda     bass,y
        jmp     @p
@l:     lda     lead,y
@p:     cmp     #EMPTY
        beq     @dot
        cmp     #TIE
        bne     @nn
        PRINT   tie_txt
        rts
@nn:    ldx     #1              ; "C#4": the octave = note / 12 + 1
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

; the play head: "*" over the step playing, when its pattern is on screen
head_show:
        jsr     head_off
        lda     play_pat
        cmp     pat
        bne     @r
        lda     play_pos
        jsr     step_col
        sta     head_col
        tax
        inx
        ldy     #HEAD_ROW
        jsr     goto
        lda     #'*'
        jmp     SBC_CHROUT
@r:     rts
head_off:
        ldx     head_col
        cpx     #$FF
        beq     @r
        inx
        ldy     #HEAD_ROW
        jsr     goto
        lda     #' '
        jsr     SBC_CHROUT
        lda     #$FF
        sta     head_col
@r:     rts

; "PATTERN A   TEMPO 120   OCTAVE 3"
show_status:
        ldx     #44
        ldy     #0
        jsr     goto
        PRINT   pat_txt
        lda     pat
        clc
        adc     #'A'
        jsr     SBC_CHROUT
        PRINT   tempo_txt
        lda     song_tempo
        jsr     prdec3
        PRINT   oct_txt
        lda     octave
        ora     #'0'
        jmp     SBC_CHROUT

; "STOPPED" / "PLAYING B (ALL)" / "(THIS ONE)"
show_play:
        ldx     #44
        ldy     #1
        jsr     goto
        lda     playing
        bne     @p
        PRINT   stopped_txt
        jmp     @m
@p:     PRINT   playing_txt
        lda     play_pat
        clc
        adc     #'A'
        jsr     SBC_CHROUT
@m:     lda     loop_one
        bne     @o
        PRINT   all_txt
        rts
@o:     PRINT   one_txt
        rts

; "BASS: BUZZ      LEAD: CHIP"
show_sounds:
        ldx     #0
        ldy     #SND_ROW
        jsr     goto
        PRINT   bass_txt
        lda     snd
        jsr     snd_name
        PRINT   lead_txt
        lda     snd+1
        jsr     snd_name
        PRINT   tab_txt
        rts
snd_name:
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
        ; (on into print8)

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

; A as 3 digits (100-250: "120"; under 100: " 80")
prdec3: ldx     #' '
        cmp     #100
        bcc     @t
        ldx     #'1'
        sbc     #100
        cmp     #100
        bcc     @t
        ldx     #'2'
        sbc     #100
@t:     pha
        txa
        jsr     SBC_CHROUT
        pla
        jmp     prdec2

; ---- tables ---------------------------------------------------------------------------
key_chr:    .byte   "ZSXDCVGBHNJM,"
            .byte   "Q2W3ER5T6Y7UI9O0P"
key_ofs:    .byte   0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
            .byte   12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28
N_KEYS      = key_ofs - key_chr

note_names: .byte   "C-C#D-D#E-F-F#G-G#A-A#B-"
track_names:.byte   "KICK    SNARE   HI-HAT  OPEN HATCRASH   BASS    LEAD    "
drum_bit:   .byte   1, 2, 4, 8, 16
drum_ins:   .byte   DRUM_KIT, DRUM_KIT + 1, DRUM_KIT + 2, DRUM_KIT + 3, DRUM_KIT + 5
drum_order: .byte   0, 1, 4, 3, 2   ; kick, snare, crash, open hat, hi-hat
seq_sig:    .byte   "SEQ1"

; ---- text -----------------------------------------------------------------------------
title_txt:  .byte   "SEQ - STEP SEQUENCER", 0
help_txt:   .byte   "ARROWS: MOVE   NOTE KEYS (AS IN PIANO): A NOTE / A DRUM ON   SPACE: ON/OFF", 13, 10
            .byte   ".: HOLD THE NOTE ON   BACKSPACE: OUT, BACK   ENTER: PLAY/STOP   ;: ALL/THIS ONE", 13, 10
            .byte   "- =: TEMPO   [ ]: OCTAVE   K L: PATTERN   TAB: SOUND   F: FILES   ESC: QUIT", 0
pat_txt:    .byte   "PATTERN ", 0
tempo_txt:  .byte   "   TEMPO ", 0
oct_txt:    .byte   "   OCTAVE ", 0
stopped_txt:.byte   "STOPPED  ", 0
playing_txt:.byte   "PLAYING ", 0
all_txt:    .byte   "   (ALL PATTERNS)", 0
one_txt:    .byte   "   (THIS ONE)    ", 0
bass_txt:   .byte   "BASS: ", 0
lead_txt:   .byte   "   LEAD: ", 0
tab_txt:    .byte   "   (TAB ON ITS ROW: ANOTHER)", 0
hit_txt:    .byte   " # ", 0
dot_txt:    .byte   " . ", 0
tie_txt:    .byte   " - ", 0
file_txt:   .byte   "FILES: S SAVE, L LOAD, N NEW, C COPY THE PATTERN BEFORE INTO THIS ONE (ESC: NO)", 0
slot_txt:   .byte   "WHICH ONE, 1-9 (BEAT1.SEQ ... BEAT9.SEQ)? ", 0
sure_txt:   .byte   "NEW: ALL 4 PATTERNS EMPTIED. SURE (Y)? ", 0
new_txt:    .byte   "ALL NEW", 0
copied_txt: .byte   "COPIED", 0
saved_txt:  .byte   "SAVED ", 0
loaded_txt: .byte   "LOADED ", 0
in_txt:     .byte   " IN ", 0
nofile_txt: .byte   "NOT FOUND: ", 0
badfile_txt:.byte   "NOT A SEQ FILE: ", 0
ferr_txt:   .byte   "USB DRIVE ERROR $", 0
quit_txt:   .byte   "QUIT (Y)? ", 0
blank_txt:  .byte   "                                                                               ", 0
rev_txt:    .byte   27, "[7m", 0
norm_txt:   .byte   27, "[0m", 0
bye_txt:    .byte   "BYE", 13, 10, 0
fpath_root: .byte   "/", 0
fpath:      .byte   "/"
fname:      .byte   "BEAT"
fname_n:    .byte   "1.SEQ", 0

; ---- variables -------------------------------------------------------------------------
        .segment "BSS"
; the song, saved as it is: "SEQ1", tempo, the sounds of BASS and LEAD, a
; spare byte, then the 4 patterns' drums (a bit each), BASS and LEAD notes
song:       .res 4
song_tempo: .res 1
snd:        .res 2
            .res 1
drums:      .res STEPS * N_PATS
bass:       .res STEPS * N_PATS
lead:       .res STEPS * N_PATS
SONG_LEN    = * - song
fbuf:       .res SONG_LEN       ; a file being loaded
pat:        .res 1              ; the pattern on screen
cur_tr:     .res 1              ; the cursor: track
cur_st:     .res 1              ;  and step
octave:     .res 1
playing:    .res 1
loop_one:   .res 1
play_pat:   .res 1
play_pos:   .res 1
acc:        .res 2              ; tempo x ticks, a step each 1500
acc2:       .res 2
gate:       .res 1              ; frames in a step
tick:       .res 1
head_col:   .res 1
sx:         .res 1
cnt:        .res 1
tmp:        .res 1
tmp2:       .res 1
fname_a:    .res 2
cwd_buf:    .res CWD_MAX + 1
