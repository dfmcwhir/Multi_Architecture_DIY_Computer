; ============================================================================
; stacker.s - a falling-blocks game for the 6502 SBC, CPU Rev2, on the
;             PICO9918 card (TMS9918A Graphics I mode)
;
;   build:  make.bat  (ca65 -I .. stacker.s, ld65 -C stacker.cfg)
;   run:    L STACKER 0800    then   R
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  speed      frames per game tick (1 = 60 a second, the normal speed)
;   $0804  controls   at start: 0 keyboard, 1 gamepad
;   $0805  sound      at start: 0 on, 1 off
;
; The screen (32 x 24 cells of 8 x 8 pixels): the well is 10 x 20 cells,
; one cell a square, at columns 11-20, rows 2-21.  Each kind of square is a
; pattern in its own colour group (gen.py).  The game keeps the picture of
; the well in RAM (disp) and writes only the squares that changed (shown is
; what the screen has).
;
; The game logic (pieces, turning, locking, lines, scoring) is the PIC32
; version's, unchanged.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

; ---- VRAM (Graphics I) ---------------------------------------------------------------
V_PAT           = $0000
V_NAME          = $1800
V_SATTR         = $1B00
V_COLOUR        = $2000
V_SPAT          = $3800
VDP_NAME        = V_NAME
P_SQUARE        = $60           ; square g = P_SQUARE + g * 8
P_WALL          = $C0
P_FLOOR         = $C8

; ---- layout ------------------------------------------------------------------------
BW              = 10            ; board width
BH              = 22            ; board height, rows 0 and 1 hidden
HIDDEN          = 2
VIS             = 200           ; visible squares (10 x 20)
BX              = 11            ; cell column of the board's left edge
BY              = 2             ; cell row of its top (visible row 0)
NX              = 23            ; the next piece: cell column, row
NY              = 4
SX              = 22            ; the numbers on the right
G_EMPTY         = 0             ; squares (see gen.py)
G_GHOST         = 8
G_FLASH         = 9
G_BLANK         = 10

LOCK_TICKS      = 30            ; grounded this long: the piece locks
LOCK_RESETS     = 15            ; moves that may restart the lock timer
DAS_DELAY       = 12            ; gamepad: ticks before a held move repeats
DAS_RATE        = 3             ; ... and between repeats

; ============================================================================
        .segment "CODE"

        jmp     start
speed:  .byte   1
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0            ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; music and effects on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines

getc            = SBC_CHRIN     ; carry set = key in A

; called by vdp_frame while it waits
frame_idle:
        jsr     sfx_poll
        jmp     rand

; 16 bit Galois LFSR.  A = a random byte.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait A frames (keys pressed meanwhile are dropped)
wait_frames:
        sta     wf_n
@l:     jsr     vdp_frame
        jsr     flush_in
        dec     wf_n
        bne     @l
        rts

; print a table of texts: column, row, .word address ... 0
print_table:
        sta     @rd+1
        sty     @rd+2
        ldx     #0
@l:     stx     pt_i
        jsr     @rd
        beq     @done
        sta     pt_c
        inx
        jsr     @rd
        tay
        ldx     pt_c
        jsr     vdp_at
        ldx     pt_i
        inx
        inx
        jsr     @rd
        pha
        inx
        jsr     @rd
        tay
        pla
        jsr     vdp_puts
        lda     pt_i
        clc
        adc     #4
        tax
        bne     @l
@done:  rts
@rd:    lda     $FFFF,x
        rts

; ============================================================================
; gamepad and menu input
; ============================================================================
PAD_A           = $01
PAD_B           = $02
PAD_SELECT      = $04
PAD_START       = $08
PAD_UP          = $10
PAD_DOWN        = $20
PAD_LEFT        = $40
PAD_RIGHT       = $80
PAD_GO          = $80           ; menu_key's answer for gamepad A or Start

read_pad:
        jsr     SBC_PADSTATE
        cmp     #$FF            ; every button "pressed" = no pad
        bne     @ok
        lda     #0
@ok:    sta     pad
        lda     padold
        eor     #$FF
        and     pad
        sta     padnew
        lda     pad
        sta     padold
        rts

flush_in:
        jsr     getc
        bcs     flush_in
        rts

; carry set if A is a character the gamepad driver types (W A S D space)
pad_typed:
        cmp     #' '
        beq     @y
        cmp     #'W'
        beq     @y
        cmp     #'A'
        beq     @y
        cmp     #'S'
        beq     @y
        cmp     #'D'
        beq     @y
        clc
        rts
@y:     sec
        rts

; wait for a menu choice: a key (letters in upper case) or PAD_GO
menu_key:
@l:     jsr     vdp_frame
        jsr     read_pad
        lda     padnew
        and     #PAD_A | PAD_START
        bne     @pad
        jsr     getc
        bcc     @l
        cmp     #' '            ; a space typed by the pad's A button?
        bne     @up
        jsr     read_pad
        lda     pad
        and     #PAD_A
        bne     @pad
        lda     #' '
        rts
@up:    cmp     #'a'
        bcc     @r
        cmp     #'z'+1
        bcs     @r
        and     #$DF
@r:     rts
@pad:   jsr     flush_in
        lda     #PAD_GO
        rts

show_ctrl:
        ldx     #1
        ldy     #19
        jsr     vdp_at
        lda     ctrl
        beq     @kb
        lda     #<ctrl_pad_txt
        ldy     #>ctrl_pad_txt
        jmp     vdp_puts
@kb:    lda     #<ctrl_kb_txt
        ldy     #>ctrl_kb_txt
        jmp     vdp_puts

; ============================================================================
; start, title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear the variables
        tax
        ldy     #>(bss_end - bss_start + $FF)
@c1:    sta     bss_start,x
        inx
        bne     @c1
        inc     @c1+2
        dey
        bne     @c1
        lda     ctrl_def
        sta     ctrl
        lda     #$5A
        sta     rng
        ; the PICO9918?  (CPU Rev2 ROM: a JMP at $FE1B, SBC_SYSINFO)
        lda     SBC_SYSINFO
        cmp     #$4C
        bne     @nopico
        jsr     SBC_SYSINFO
        cmp     #DISP_PICO
        beq     @pico
@nopico:
        ldx     #0
@m:     lda     need_txt,x
        beq     @bye
        jsr     SBC_CHROUT
        inx
        bne     @m
@bye:   jmp     SBC_MENU
@pico:  jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
        jsr     gfx_init

title:  jsr     sfx_off
        jsr     clear_names
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print_table
        jsr     draw_banner
        jsr     show_start_level
        jsr     show_hiscore_title
        jsr     show_ctrl
        jsr     read_pad
        jsr     flush_in
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @notq
        jmp     exit_game
@notq:  cmp     #'M'            ; sound on / off
        bne     @notm
        jsr     sfx_toggle
        jmp     @wait
@notm:  cmp     #'G'            ; switch keyboard / gamepad
        bne     @notg
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@notg:  cmp     #PAD_GO         ; A or Start on the pad: play with the pad
        bne     @notp
        lda     #1
        sta     ctrl
        jmp     new_game
@notp:  cmp     #' '
        bne     @digit
        jmp     new_game
@digit: cmp     #'0'            ; 0..9: the starting level
        bcc     @wait
        cmp     #'9'+1
        bcs     @wait
        and     #$0F
        sta     start_level
        jsr     show_start_level
        jmp     @wait

; the title banner, made of squares
draw_banner:
        lda     #<banner
        sta     @rd+1
        lda     #>banner
        sta     @rd+2
        ldy     #2              ; cell row
@row:   ldx     #(32 - BANNER_W) / 2
        jsr     vdp_at
        lda     #BANNER_W
        sta     tmp3
@rd:    lda     $FFFF
        jsr     sq_name
        sta     VDP_DATA
        inc     @rd+1
        bne     @n
        inc     @rd+2
@n:     dec     tmp3
        bne     @rd
        iny
        cpy     #2 + BANNER_H
        bne     @row
        rts

; A = the name (pattern) of square A.  Preserves X and Y.
sq_name:
        cmp     #G_BLANK
        bcs     @blank
        asl
        asl
        asl
        adc     #P_SQUARE
        rts
@blank: lda     #0
        rts

show_start_level:
        ldx     #26
        ldy     #17
        jsr     vdp_at
        lda     start_level
        ora     #'0'
        sta     VDP_DATA
        rts

show_hiscore_title:
        ldx     #18
        ldy     #21
        jsr     vdp_at
        ; (on into pr_hiscore)
pr_hiscore:
        lda     hiscore+2
        jsr     vdp_bcd
        lda     hiscore+1
        jsr     vdp_bcd
        lda     hiscore
        jmp     vdp_bcd

exit_game:
        jsr     sfx_off
        jsr     SBC_CONRESET    ; the console's text screen back
        jmp     SBC_MENU        ; back to the boot menu

; set up the VDP and load the patterns and colours
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup
        lda     #<(V_PAT + $20*8)       ; the font
        ldy     #>(V_PAT + $20*8)
        jsr     vdp_waddr
        lda     #<gfx_font
        ldx     #>gfx_font
        ldy     #>(64*8)
        jsr     copy_vram
        lda     #<(V_PAT + P_SQUARE*8)  ; the squares, 8 patterns apart
        sta     tmp
        lda     #>(V_PAT + P_SQUARE*8)
        sta     tmp2
        lda     #<gfx_squares
        sta     vdp_src
        lda     #>gfx_squares
        sta     vdp_src+1
        lda     #10
        sta     tmp3
@sq:    lda     tmp
        ldy     tmp2
        jsr     vdp_waddr
        lda     #8
        sta     vdp_n
        lda     #0
        sta     vdp_n+1
        jsr     vdp_copy
        lda     vdp_src
        clc
        adc     #8
        sta     vdp_src
        bcc     :+
        inc     vdp_src+1
:       lda     tmp
        clc
        adc     #64
        sta     tmp
        bcc     :+
        inc     tmp2
:       dec     tmp3
        bne     @sq
        lda     #<(V_PAT + P_WALL*8)    ; the well's side and floor
        ldy     #>(V_PAT + P_WALL*8)
        jsr     vdp_waddr
        lda     #<gfx_well
        sta     vdp_src
        lda     #>gfx_well
        sta     vdp_src+1
        lda     #8
        sta     vdp_n
        jsr     vdp_copy
        lda     #<(V_PAT + P_FLOOR*8)
        ldy     #>(V_PAT + P_FLOOR*8)
        jsr     vdp_waddr
        lda     #<(gfx_well+8)
        sta     vdp_src
        lda     #>(gfx_well+8)
        sta     vdp_src+1
        jsr     vdp_copy
        lda     #<V_COLOUR
        ldy     #>V_COLOUR
        jsr     vdp_waddr
        lda     #<gfx_colours
        ldx     #>gfx_colours
        ldy     #0
        jsr     copy_vram32
        lda     #<V_SATTR       ; no sprites
        ldy     #>V_SATTR
        jsr     vdp_waddr
        lda     #$D0
        sta     VDP_DATA
        lda     #$C0            ; R1: display on (8 x 8 sprites, none used)
        ldx     #1
        jmp     vdp_reg

; copy A/X (low/high) -> VRAM: Y pages (copy_vram), or 32 bytes (copy_vram32)
copy_vram:
        sta     vdp_src
        stx     vdp_src+1
        lda     #0
        sta     vdp_n
        sty     vdp_n+1
        jmp     vdp_copy
copy_vram32:
        sta     vdp_src
        stx     vdp_src+1
        lda     #32
        sta     vdp_n
        lda     #0
        sta     vdp_n+1
        jmp     vdp_copy

; the whole name table blank
clear_names:
        lda     #<V_NAME
        ldy     #>V_NAME
        jsr     vdp_waddr
        lda     #<768
        sta     vdp_n
        lda     #>768
        sta     vdp_n+1
        lda     #0
        jmp     vdp_fill

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        ldx     #BW * BH - 1    ; empty board
@b:     sta     board,x
        dex
        cpx     #$FF
        bne     @b
        ldx     #VIS - 1        ; the screen shows nothing yet
        lda     #$FF
@s:     sta     shown,x
        dex
        cpx     #$FF
        bne     @s
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     lines
        sta     lines+1
        sta     quit
        sta     dead
        sta     bag_n
        lda     start_level
        sta     level
        lda     #10
        sta     to_next
        jsr     screen_setup
        jsr     bag_next
        sta     next
        jsr     spawn
        jsr     show_stats
        jsr     sfx_off         ; the music
        lda     #MUS_THEME
        jsr     sfx_snd
        lda     #MUS_THEME+1
        jsr     sfx_snd

game_loop:
        lda     speed           ; one tick a frame (or every speed frames)
        sta     wf_n
@f:     jsr     vdp_frame
        dec     wf_n
        bne     @f
        jsr     sfx_poll
        inc     ticks
        jsr     input
        lda     quit
        beq     @1
        jmp     title
@1:     lda     need_lock
        bne     @lock
        jsr     gravity
        lda     need_lock
        beq     @2
@lock:  jsr     lock_piece
        lda     dead
        beq     @2
        jmp     game_over
@2:     lda     dirty
        beq     game_loop
        jsr     compose
        jsr     present
        lda     #0
        sta     dirty
        jmp     game_loop

; ---- the screen around the board ------------------------------------------------
screen_setup:
        jsr     clear_names
        lda     #<game_txt
        ldy     #>game_txt
        jsr     print_table
        lda     ctrl            ; the controls for this game
        beq     @kb
        lda     #<help_pad_txt
        ldy     #>help_pad_txt
        jsr     print_table
        jmp     @well
@kb:    lda     #<help_kb_txt
        ldy     #>help_kb_txt
        jsr     print_table
@well:  ldy     #BY             ; the sides
@side:  ldx     #BX-1
        jsr     vdp_at
        lda     #P_WALL
        sta     VDP_DATA
        ldx     #BX+BW
        jsr     vdp_at
        lda     #P_WALL
        sta     VDP_DATA
        iny
        cpy     #BY+20
        bne     @side
        ldx     #BX-1           ; the floor
        jsr     vdp_at
        ldx     #BW+2
        lda     #P_FLOOR
@fl:    sta     VDP_DATA
        dex
        bne     @fl
        rts

; score, lines, level, high score
show_stats:
        jsr     show_score
        ldx     #SX+1
        ldy     #12
        jsr     vdp_at
        lda     lines+1
        jsr     vdp_bcd
        lda     lines
        jsr     vdp_bcd
        ldx     #SX+1
        ldy     #15
        jsr     vdp_at
        lda     level           ; (binary, 0-99)
        ldx     #'0'
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     stx     VDP_DATA
        ora     #'0'
        sta     VDP_DATA
        ldx     #SX+1
        ldy     #18
        jsr     vdp_at
        jmp     pr_hiscore

show_score:
        ldx     #SX+1
        ldy     #9
        jsr     vdp_at
        lda     score+2
        jsr     vdp_bcd
        lda     score+1
        jsr     vdp_bcd
        lda     score
        jmp     vdp_bcd

; the next piece in its box (4 x 2 squares)
draw_next:
        ldx     #7
        lda     #G_BLANK
@c:     sta     nbuf,x
        dex
        bpl     @c
        lda     next
        asl
        asl
        asl
        asl
        tay                     ; rotation 0 of that piece
        ldx     #4
@sq:    lda     pc_y,y
        asl
        asl
        clc
        adc     pc_x,y
        sta     tmp
        lda     next
        clc
        adc     #1
        stx     tmp2
        ldx     tmp
        sta     nbuf,x
        ldx     tmp2
        iny
        dex
        bne     @sq
        ldx     #NX
        ldy     #NY
        jsr     vdp_at
        ldx     #0
@r0:    lda     nbuf,x
        jsr     sq_name
        sta     VDP_DATA
        inx
        cpx     #4
        bne     @r0
        ldx     #NX
        iny
        jsr     vdp_at
        ldx     #4
@r1:    lda     nbuf,x
        jsr     sq_name
        sta     VDP_DATA
        inx
        cpx     #8
        bne     @r1
        rts

; ---- pieces (unchanged from the PIC32 version) --------------------------------------
; ---- pieces -----------------------------------------------------------------------
; the next piece from the bag: each run of 7 has every piece once
bag_next:
        lda     bag_n
        bne     @take
        ldx     #6              ; refill and shuffle (Fisher-Yates)
@f:     txa
        sta     bag,x
        dex
        bpl     @f
        ldx     #6
@sh:    stx     tmp
@r:     jsr     rand            ; j = random 0..x
        and     #7
        cmp     tmp
        beq     @ok
        bcs     @r
@ok:    tay
        lda     bag,x
        pha
        lda     bag,y
        sta     bag,x
        pla
        sta     bag,y
        dex
        bne     @sh
        lda     #7
        sta     bag_n
@take:  dec     bag_n
        ldx     bag_n
        lda     bag,x
        rts

; the next piece comes in at the top
spawn:  inc     npieces
        lda     next
        sta     ptype
        jsr     bag_next
        sta     next
        lda     #3
        sta     px
        lda     #1
        sta     py
        lda     #0
        sta     prot
        sta     ltimer
        sta     lresets
        sta     gcount
        sta     need_lock
        lda     #1
        sta     dirty
        jsr     draw_next
        jsr     fits_here
        bcc     @ok
        lda     #1              ; no room: the game is over
        sta     dead
@ok:    rts

; carry clear if the piece fits at px, py, prot
fits_here:
        lda     px
        sta     tx
        lda     py
        sta     ty
        lda     prot
        sta     trot
; carry clear if piece ptype fits at tx, ty, trot
fits:   lda     ptype
        asl
        asl
        adc     trot            ; (carry clear: ptype < 64)
        asl
        asl
        sta     pidx            ; ptype * 16 + trot * 4
        tay
        ldx     #4
@sq:    lda     pc_x,y
        clc
        adc     tx
        cmp     #BW             ; off the side (or < 0: >= 128)
        bcs     @no
        sta     tmp
        lda     pc_y,y
        clc
        adc     ty
        cmp     #BH             ; below the floor
        bcs     @no
        stx     tmp2
        tax
        lda     rowoff,x
        clc
        adc     tmp
        tax
        lda     board,x
        bne     @no2
        ldx     tmp2
        iny
        dex
        bne     @sq
        clc
        rts
@no2:   ldx     tmp2
@no:    sec
        rts

; a move or turn worked: if the piece is on the ground, it gets a little
; more time before it locks (but not for ever)
moved:  lda     #1
        sta     dirty
        lda     lresets
        cmp     #LOCK_RESETS
        bcs     @r
        inc     lresets
        lda     #0
        sta     ltimer
@r:     rts

; move sideways by A (1 or -1)
move:   clc
        adc     px
        sta     tx
        lda     py
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcs     @r
        lda     tx
        sta     px
        lda     #SND_MOVE
        jsr     sfx_snd
        jmp     moved
@r:     rts

; turn by A (1 clockwise, 3 back); if it doesn't fit, try nudging it sideways
rotate: clc
        adc     prot
        and     #3
        sta     trot
        lda     py
        sta     ty
        ldx     #0
@k:     stx     kick
        lda     px
        clc
        adc     kicks,x
        sta     tx
        jsr     fits
        bcc     @ok
        ldx     kick
        inx
        cpx     #3              ; I pieces may go 2 squares
        bne     @k2
        lda     ptype
        bne     @r              ; (I is piece 0)
@k2:    cpx     #5
        bne     @k
@r:     rts
@ok:    lda     tx
        sta     px
        lda     trot
        sta     prot
        lda     #SND_ROTATE
        jsr     sfx_snd
        jmp     moved

; one row down (a soft drop): if it can't, it locks now
soft_drop:
        jsr     down1
        bcs     @lock
        lda     #1
        jsr     add_score
        lda     #0
        sta     gcount
        rts
@lock:  lda     #1
        sta     need_lock
        rts

; all the way down, and lock
hard_drop:
        lda     #0
        sta     tmp3
@l:     jsr     down1
        bcs     @done
        inc     tmp3
        bne     @l
@done:  lda     tmp3
        asl
        jsr     add_score
        lda     #SND_DROP
        jsr     sfx_snd
        lda     #1
        sta     need_lock
        rts

; move the piece down a row if it can (carry clear)
down1:  lda     px
        sta     tx
        lda     py
        clc
        adc     #1
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcs     @r
        inc     py
        lda     #1
        sta     dirty
        clc
@r:     rts

; the piece falls a row every so often; on the ground the lock timer runs
gravity:
        inc     gcount
        ldx     level
        cpx     #NSPEED
        bcc     @l
        ldx     #NSPEED-1
@l:     lda     gcount
        cmp     fall_ticks,x
        bcc     @ground
        lda     #0
        sta     gcount
        jsr     down1
        bcs     @ground
        lda     #0              ; a fresh row: a fresh lock timer
        sta     ltimer
        rts
@ground:lda     px              ; standing on something?
        sta     tx
        lda     py
        clc
        adc     #1
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcc     @air
        inc     ltimer
        lda     ltimer
        cmp     #LOCK_TICKS
        bcc     @r
        lda     #1
        sta     need_lock
@r:     rts
@air:   lda     #0
        sta     ltimer
        rts

; ---- locking, lines ------------------------------------------------------------------
lock_piece:
        lda     #SND_LOCK       ; (a hard drop's sound wins: it's louder)
        jsr     sfx_snd
        lda     #0
        sta     need_lock
        lda     px              ; write the piece into the board
        sta     tx
        lda     py
        sta     ty
        lda     prot
        sta     trot
        jsr     fits            ; (sets pidx)
        ldy     pidx
        ldx     #4
@sq:    stx     tmp2
        lda     pc_y,y
        clc
        adc     py
        tax
        lda     rowoff,x
        clc
        adc     pc_x,y
        adc     px
        tax
        lda     ptype
        clc
        adc     #1
        sta     board,x
        ldx     tmp2
        iny
        dex
        bne     @sq
        ; full rows?
        lda     #0
        sta     nfull
        ldx     #BH-1
@row:   stx     tmp
        lda     rowoff,x
        tay
        ldx     #BW
@c:     lda     board,y
        beq     @notfull
        iny
        dex
        bne     @c
        ldx     nfull
        lda     tmp
        sta     full,x
        inc     nfull
@notfull:
        ldx     tmp
        dex
        bpl     @row
        lda     nfull
        beq     @next
        jsr     clear_lines
@next:  jmp     spawn

; flash the full rows, remove them, score
clear_lines:
        lda     nfull           ; 4 lines: a bigger sound
        cmp     #4
        lda     #SND_LINE
        bcc     @s
        lda     #SND_LINES
@s:     jsr     sfx_snd
        jsr     compose_board   ; the board without a falling piece
        ldx     nfull           ; show the full rows as solid
@f:     dex
        bmi     @show
        lda     full,x
        sec
        sbc     #HIDDEN
        bcc     @f
        tay
        lda     rowoff,y
        tay
        lda     #BW
        sta     tmp
        lda     #G_FLASH
@fc:    sta     disp,y
        iny
        dec     tmp
        bne     @fc
        jmp     @f
@show:  jsr     present
        lda     #12
        jsr     wait_frames
        ; remove them: full[] is from the bottom up, so take the highest first
        ldx     nfull
@rm:    dex
        bmi     @scored
        stx     tmp3
        lda     full,x
        jsr     remove_row
        ldx     tmp3
        jmp     @rm
@scored:lda     nfull           ; points: 40, 100, 300, 1200 x (level + 1)
        asl
        asl                     ; *4 (3 bytes each, the first unused)
        sec
        sbc     #4
        tax
        lda     level
        sta     tmp3
@pts:   php
        sei
        sed
        clc
        lda     score
        adc     line_pts,x
        sta     score
        lda     score+1
        adc     line_pts+1,x
        sta     score+1
        lda     score+2
        adc     line_pts+2,x
        sta     score+2
        bcc     @nc
        lda     #$99            ; (999999 is the most)
        sta     score
        sta     score+1
        sta     score+2
@nc:    cld
        plp
        dec     tmp3
        bpl     @pts
        lda     nfull           ; lines, level
        sta     tmp3
@ln:    php
        sei
        sed
        clc
        lda     lines
        adc     #1
        sta     lines
        lda     lines+1
        adc     #0
        sta     lines+1
        cld
        plp
        dec     to_next
        bne     @nl
        lda     #10
        sta     to_next
        lda     level
        cmp     #99
        bcs     @nl
        inc     level
        lda     #SND_LEVEL
        jsr     sfx_snd
@nl:    dec     tmp3
        bne     @ln
        jmp     show_stats

; remove board row A: everything above it moves down one
remove_row:
        tax
        lda     rowoff,x
        clc
        adc     #BW-1
        tax                     ; last square of the row
@m:     cpx     #BW
        bcc     @top
        lda     board-BW,x
        sta     board,x
        dex
        bne     @m              ; (X >= BW here, so never 0)
@top:   lda     #0              ; a new empty row at the top
@t:     sta     board,x
        dex
        bpl     @t
        rts

; add A (0..99, binary) to the score
add_score:
        tax
        beq     @r
@l:     php
        sei
        sed
        clc
        lda     score
        adc     #1
        sta     score
        lda     score+1
        adc     #0
        sta     score+1
        lda     score+2
        adc     #0
        sta     score+2
        cld
        plp
        dex
        bne     @l
        lda     #1
        sta     score_dirty
@r:     rts

; ---- drawing the board ---------------------------------------------------------
; disp = the visible board
compose_board:
        ldx     #VIS-1
@c:     lda     board + HIDDEN * BW,x
        sta     disp,x
        dex
        cpx     #$FF
        bne     @c
        rts

; disp = the board + the ghost + the falling piece
compose:
        jsr     compose_board
        lda     px              ; the ghost: as far down as it goes
        sta     tx
        lda     py
        sta     gy
@g:     inc     gy
        lda     gy
        sta     ty
        lda     prot
        sta     trot
        jsr     fits
        bcc     @g
        dec     gy
        lda     gy
        ldx     #G_GHOST
        jsr     put_piece
        lda     ptype
        clc
        adc     #1
        tax
        lda     py
        ; fall through
; put glyph X at the squares of the piece (at px, row A, prot) in disp
put_piece:
        sta     tmp
        stx     tmp3
        lda     ptype
        asl
        asl
        clc
        adc     prot
        asl
        asl
        tay
        ldx     #4
@sq:    stx     tmp2
        lda     pc_y,y
        clc
        adc     tmp
        sec
        sbc     #HIDDEN
        bcc     @n              ; in the hidden rows
        tax
        lda     rowoff,x
        clc
        adc     pc_x,y
        adc     px
        tax
        lda     tmp3
        sta     disp,x
@n:     ldx     tmp2
        iny
        dex
        bne     @sq
        rts

; send the squares that differ from what the terminal shows.  A run of the
; same square is sent once with the repeat count (18 n, then 0B tile).

; write the squares that differ from what the screen shows
present:
        lda     score_dirty
        beq     @p
        lda     #0
        sta     score_dirty
        jsr     show_score
@p:     ldx     #0              ; square index
        lda     #0
        sta     prow
@row:   lda     #0
        sta     pcol
@sq:    lda     disp,x
        cmp     shown,x
        beq     @same
        sta     shown,x
        jsr     sq_name
        sta     val
        stx     tmp2
        lda     pcol
        clc
        adc     #BX
        tax
        lda     prow
        clc
        adc     #BY
        tay
        jsr     vdp_at
        lda     val
        sta     VDP_DATA
        ldx     tmp2
@same:  inx
        inc     pcol
        lda     pcol
        cmp     #BW
        bne     @sq
        inc     prow
        lda     prow
        cmp     #20
        bne     @row
        rts


; ============================================================================
input:  lda     padold          ; the pad works in either mode
        sta     pad_prev
        jsr     read_pad
        lda     padnew          ; left / right: move now, repeat when held
        and     #PAD_LEFT | PAD_RIGHT
        beq     @held
        lda     #0
        sta     das
        jsr     pad_move
        jmp     @rot
@held:  lda     pad
        and     #PAD_LEFT | PAD_RIGHT
        beq     @rot
        inc     das
        lda     das
        cmp     #DAS_DELAY
        bcc     @rot
        lda     #DAS_DELAY - DAS_RATE
        sta     das
        jsr     pad_move
@rot:   lda     padnew
        and     #PAD_A
        beq     @b
        lda     #1
        jsr     rotate
@b:     lda     padnew
        and     #PAD_B
        beq     @up
        lda     #3
        jsr     rotate
@up:    lda     padnew
        and     #PAD_UP
        beq     @dn
        jsr     hard_drop
        jmp     @st
@dn:    lda     pad
        and     #PAD_DOWN
        beq     @st
        inc     sdcount
        lda     sdcount
        and     #1
        beq     @st
        jsr     soft_drop
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  lda     need_lock       ; (stop once the piece is down)
        bne     @done
        jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @keys
@done:  rts

pad_move:
        lda     pad
        and     #PAD_LEFT
        beq     @r
        lda     #$FF
        jmp     move
@r:     lda     #1
        jmp     move

handle_key:
        ldx     esc_st          ; arrow keys: ESC [ A..D
        beq     @plain
        cpx     #1
        bne     @esc2
        cmp     #'['
        beq     @br
        cmp     #'O'
        beq     @br
        lda     #0
        sta     esc_st
        rts
@br:    inc     esc_st
        rts
@esc2:  ldx     #0
        stx     esc_st
        cmp     #'A'
        bne     :+
        jmp     @rot
:       cmp     #'B'
        bne     :+
        jmp     @down
:
        cmp     #'C'
        beq     @right
        cmp     #'D'
        beq     @left
        rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    cmp     #KEY_LEFT       ; the AVR keyboard's arrow keys
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
        cmp     #KEY_UP
        beq     @rot
        cmp     #KEY_DOWN
        beq     @down
        jsr     pad_typed       ; W A S D space typed by the pad?
        bcc     @kb
        ldx     ctrl            ; gamepad mode: always ignored
        bne     @ign
        ldx     pad             ; or while a pad button is (was) held
        bne     @ign
        ldx     pad_prev
        beq     @kb
@ign:   rts
@kb:    cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #'W'
        beq     @rot
        cmp     #'X'
        beq     @rot
        cmp     #'Z'
        beq     @back
        cmp     #'S'
        beq     @down
        cmp     #' '
        beq     @drop
        cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@left:  lda     #$FF
        jmp     move
@right: lda     #1
        jmp     move
@rot:   lda     #1
        jmp     rotate
@back:  lda     #3
        jmp     rotate
@down:  jmp     soft_drop
@drop:  jmp     hard_drop
@pause: jmp     pause
@quit:  lda     #1
        sta     quit
        rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        ldx     #SX
        ldy     #21
        jsr     vdp_at
        lda     #<paused_txt
        ldy     #>paused_txt
        jsr     vdp_puts
        jsr     flush_in
@w:     jsr     rand
        jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @go
        jsr     getc
        bcc     @w
@go:    jsr     flush_in
        ldx     #SX
        ldy     #21
        jsr     vdp_at
        lda     #<unpaused_txt
        ldy     #>unpaused_txt
        jmp     vdp_puts

; ============================================================================
; game over
; ============================================================================
game_over:
        jsr     sfx_off         ; the music stops
        lda     #SND_OVERA
        jsr     sfx_snd
        lda     #SND_OVERB
        jsr     sfx_snd
        jsr     compose         ; show where it ended
        jsr     present
        lda     #VIS - BW       ; fill the well from the bottom up
        sta     tmp3
@fill:  ldx     tmp3
        ldy     #BW
        lda     #G_FLASH
@f:     sta     disp,x
        inx
        dey
        bne     @f
        jsr     present
        lda     #2
        jsr     wait_frames
        lda     tmp3
        sec
        sbc     #BW
        sta     tmp3
        bcs     @fill
        ldx     #2              ; new high score?
@hc:    lda     score,x
        cmp     hiscore,x
        bcc     @nohi
        bne     @hi
        dex
        bpl     @hc
        bmi     @nohi           ; equal
@hi:    ldx     #2
@hs:    lda     score,x
        sta     hiscore,x
        dex
        bpl     @hs
        jsr     show_stats
@nohi:  lda     #<over_txt
        ldy     #>over_txt
        jsr     print_table
        lda     #30
        jsr     wait_frames     ; ignore keys for half a second
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @nq
        jmp     title
@nq:    cmp     #'M'
        bne     @nm
        jsr     sfx_toggle
        jmp     @wait
@nm:    cmp     #' '
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
        .include "stacker_data.inc"
        .include "stacker_sound.inc"    ; the music and effects (game_sounds.py)

; R0-R7: Graphics I, display off for now, no VDP interrupt; names $1800,
; colours $2000, patterns $0000, sprites $1B00 / $3800; black
vdp_regs:
        .byte   $00, $80, V_NAME/$400, V_COLOUR/$40, V_PAT/$800, V_SATTR/$80, V_SPAT/$800, $01

rowoff:
.repeat BH, R
        .byte   R * BW
.endrepeat
kicks:  .byte   0, $FF, 1, $FE, 2       ; sideways nudges when turning
; ticks (frames) per row by level
fall_ticks:
        .byte   48, 43, 38, 33, 28, 23, 18, 13, 8, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2
NSPEED = * - fall_ticks
line_pts:       ; BCD, 4 bytes each (1 to 4 lines)
        .byte   $40, $00, $00, 0
        .byte   $00, $01, $00, 0
        .byte   $00, $03, $00, 0
        .byte   $00, $12, $00, 0

; texts: column, row, .word address ... 0
title_txt:
        .byte   5, 9
        .word   t_sub
        .byte   1, 11
        .word   t_k1
        .byte   1, 12
        .word   t_k2
        .byte   1, 13
        .word   t_k3
        .byte   1, 14
        .word   t_k4
        .byte   1, 15
        .word   t_k5
        .byte   4, 17
        .word   t_lvl
        .byte   7, 21
        .word   t_hi
        .byte   6, 23
        .word   t_press
        .byte   0
t_sub:  .byte   "A FALLING BLOCKS GAME", 0
t_k1:   .byte   "KEYS: A/D MOVE  W TURN  Z BACK", 0
t_k2:   .byte   "      S DOWN  SPACE DROP", 0
t_k3:   .byte   "PAD:  LEFT/RIGHT MOVE  A/B TURN", 0
t_k4:   .byte   "      DOWN DOWN  UP DROP", 0
t_k5:   .byte   "P/START PAUSE  M SOUND  Q QUIT", 0
t_lvl:  .byte   "STARTING LEVEL (0-9):", 0
t_hi:   .byte   "HIGH SCORE", 0
t_press:.byte   "SPACE OR START: PLAY", 0
game_txt:
        .byte   12, 0
        .word   t_name
        .byte   SX+1, NY-2
        .word   t_next
        .byte   SX, 8
        .word   t_score
        .byte   SX, 11
        .word   t_lines
        .byte   SX, 14
        .word   t_level
        .byte   SX, 17
        .word   t_high
        .byte   0
t_name: .byte   "STACKER", 0
t_next: .byte   "NEXT", 0
t_score:.byte   "SCORE", 0
t_lines:.byte   "LINES", 0
t_level:.byte   "LEVEL", 0
t_high: .byte   "HIGH", 0
help_kb_txt:
        .byte   1, 4
        .word   h_k1
        .byte   1, 5
        .word   h_k2
        .byte   1, 6
        .word   h_k3
        .byte   1, 7
        .word   h_k4
        .byte   1, 8
        .word   h_k5
        .byte   1, 11
        .word   h_k6
        .byte   1, 12
        .word   h_k7
        .byte   1, 13
        .word   h_k8
        .byte   0
h_k1:   .byte   "A D MOVE", 0
h_k2:   .byte   "W   TURN", 0
h_k3:   .byte   "Z   BACK", 0
h_k4:   .byte   "S   DOWN", 0
h_k5:   .byte   "SPC DROP", 0
h_k6:   .byte   "P PAUSE", 0
h_k7:   .byte   "M SOUND", 0
h_k8:   .byte   "Q QUIT", 0
help_pad_txt:
        .byte   0, 4
        .word   h_p1
        .byte   0, 5
        .word   h_p2
        .byte   0, 6
        .word   h_p3
        .byte   0, 7
        .word   h_p4
        .byte   0, 8
        .word   h_p5
        .byte   0, 11
        .word   h_p6
        .byte   0, 12
        .word   h_p7
        .byte   0, 13
        .word   h_p8
        .byte   0
h_p1:   .byte   "<> MOVE", 0
h_p2:   .byte   "A  TURN", 0
h_p3:   .byte   "B  BACK", 0
h_p4:   .byte   "DN DOWN", 0
h_p5:   .byte   "UP DROP", 0
h_p6:   .byte   "STRT PAUSE", 0
h_p7:   .byte   "M  SOUND", 0
h_p8:   .byte   "Q  QUIT", 0
paused_txt:
        .byte   "PAUSED", 0
unpaused_txt:
        .byte   "      ", 0
over_txt:
        .byte   BX, 9
        .word   o_1
        .byte   BX, 10
        .word   o_2
        .byte   BX, 11
        .word   o_1
        .byte   BX, 12
        .word   o_3
        .byte   BX, 13
        .word   o_4
        .byte   BX, 14
        .word   o_1
        .byte   0
o_1:    .byte   "          ", 0
o_2:    .byte   "GAME  OVER", 0
o_3:    .byte   "SPC/A:PLAY", 0
o_4:    .byte   "Q: TITLE  ", 0
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: PAD)   ", 0
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD  (G: KEYS)  ", 0
need_txt:
        .byte   13, 10, "STACKER NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0

; ============================================================================
; variables (not in the file; cleared at start)
; ============================================================================
        .segment "BSS"
bss_start:
ctrl:       .res 1              ; 0 keyboard, 1 gamepad
pad:        .res 1              ; gamepad buttons held
pad_prev:   .res 1              ; ... last tick
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
esc_st:     .res 1
quit:       .res 1
ticks:      .res 1              ; counts game ticks
npieces:    .res 1              ; counts pieces
dead:       .res 1
start_level:.res 1
level:      .res 1
to_next:    .res 1              ; lines to the next level
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
lines:      .res 2              ; BCD
score_dirty:.res 1
ptype:      .res 1              ; the falling piece: 0..6
px:         .res 1              ; its box's square (may be < 0)
py:         .res 1              ; its box's row (0 = the top hidden row)
prot:       .res 1
next:       .res 1
tx:         .res 1              ; a place to test
ty:         .res 1
trot:       .res 1
pidx:       .res 1
gy:         .res 1              ; the ghost's row
kick:       .res 1
gcount:     .res 1              ; ticks since the last fall
ltimer:     .res 1              ; ticks on the ground
lresets:    .res 1
need_lock:  .res 1
dirty:      .res 1              ; the board picture changed
das:        .res 1
sdcount:    .res 1
bag:        .res 7
bag_n:      .res 1
nfull:      .res 1
full:       .res 4              ; full rows, bottom first
nbuf:       .res 8
prow:       .res 1
pcol:       .res 1
val:        .res 1
wf_n:       .res 1
pt_i:       .res 1
pt_c:       .res 1
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
board:      .res BW * BH
disp:       .res VIS
shown:      .res VIS
bss_end:
