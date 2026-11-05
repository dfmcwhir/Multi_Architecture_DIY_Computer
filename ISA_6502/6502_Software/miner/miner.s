; ============================================================================
; miner.s - MINER MOS, a single screen platform game for the 6502 SBC, in the
; style of the 1983 classic: collect the keys in each room, then get to the
; portal before the air runs out
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal in its
; control code mode (setup item J), with the terminal's sprite layer
; (control code 1C: the firmware with the sprite layer, VGA).
;
;   build:  make.bat  (or make)     needs ../sbc_api.inc (CLOCK_MHZ)
;   run:    L MINER 0500   then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  frame time in ms (default 40; real ms at any clock)
;   $0504  controls at start: 0 keyboard, 1 gamepad
;   $0505  sound at start: 0 on, 1 off (M switches)
;
; Sound: the AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s (timed by
; the VIA's timer 2): "In the Hall of the Mountain King" (Grieg; public
; domain) and effects, in miner_sound.inc (made by ../ay/tools/
; game_sounds.py).  Without the card the game is just silent.
;
; Keys:    A / D or Left / Right  walk      Space, W or Up  jump
;          P pause   M sound on / off   Q quit
; Gamepad: left / right walk, A, B or up jump, Start pause
;
; The screen: the room on text rows 0-19 (40 x 20 tiles of 4 x 4 pixels,
; each 2 block graphics characters), its name on row 20, the air on row 21,
; the score on row 23.  The tiles are characters, drawn when the room
; starts and again only when one changes (a key taken, a crumbling floor).
; Willy, the guardians and the portal are the terminal's sprites: each frame
; only what changed goes, between HOLD and SHOW, then IDENTIFY, whose answer
; the next frame waits for.  Coordinates are the sprite layer's pixels (160
; x 96, 3 x 3 screen pixels each).  The rules of movement are in phys.py
; too (the same, step by step), for the room checks and the tests.  No zero
; page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 40            ; ms per frame

; ---- terminal --------------------------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
TC_SPR          = $1C
ATTR_TEXT       = $00
ATTR_GFX        = $80
TERM            = $FF
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'
SPR_PLACE       = 2
SPR_MOVE        = 3
SPR_PIC         = 4
SPR_HIDE        = 6

; ---- the room ----------------------------------------------------------------------
COLS            = 40            ; tiles
ROWS            = 20
NTILE           = COLS * ROWS
EMPTY           = 0             ; tiles
FLOOR           = 1
WALL            = 2
CONV_L          = 3
CONV_R          = 4
CR0             = 5             ; crumbling floor, 3 stages
CR2             = 7
HAZARD          = 8
KEY             = 9
NAME_ROW        = 20
AIR_ROW         = 21
AIR_COL         = 4
AIR_RATE        = 12            ; frames a unit of air lasts

; ---- Willy -------------------------------------------------------------------------
W_W             = 6             ; his box
W_H             = 8
FALL_MAX        = 24            ; a fall longer than this kills
CRUMBLE_T       = 6             ; frames on a crumbling floor per stage
ST_STAND        = 0
ST_JUMP         = 1
ST_FALL         = 2

; ---- sprite slots (higher on top) -----------------------------------------------------
NSLOT           = 16
SL_WILLY        = 15
SL_GUARD        = 8             ; 8-14
MAXG            = 7
SL_PORTAL       = 0

; ============================================================================
        .segment "RODATA"
        .include "miner_data.inc"
        .include "miner_sound.inc"      ; the music and effects (game_sounds.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0, 0

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; music and effects on the AY-3-8910 card

; ----------------------------------------------------------------------------
; I/O helpers
; ----------------------------------------------------------------------------
; carry set = key in A.  After IDENTIFY (1C 0C) the terminal answers S P 1:
; those are taken as its answer (rp_got), not as keys, until the 1 comes or
; the next IDENTIFY.  (Keys come in lower case; any one of the three will do.)
getc:   jsr     SBC_CHRIN
        bcc     @r
        pha
        lda     rp_on
        beq     @key
        pla
        cmp     #'S'
        beq     @rep
        cmp     #'P'
        beq     @rep
        cmp     #'1'
        bne     @k2
        lda     #0
        sta     rp_on
@rep:   lda     #1
        sta     rp_got
        jmp     getc
@k2:    sec
        rts
@key:   pla
        sec
@r:     rts

; send A (counts the bytes, for the frame timing).  Preserves A, X, Y.
putc:   inc     nbytes
        bne     @p
        inc     nbytes+1
@p:     jsr     sfx_poll        ; (the sound goes on while drawing)
        jmp     SBC_CHROUT

; cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
        lda     #TC_COL
        jsr     putc
        txa
        jmp     putc

txt_mode:
        lda     #ATTR_TEXT
        beq     setattr
gfx_mode:
        lda     #ATTR_GFX
setattr:cmp     attr
        beq     @r
        sta     attr
        pha
        lda     #TC_ATTR
        jsr     putc
        pla
        jmp     putc
@r:     rts

; a block graphics character (00-1F and 7F need the 1A prefix)
putblk: cmp     #$20
        bcc     @lit
        cmp     #$7F
        bne     @out
@lit:   pha
        lda     #TC_LIT
        jsr     putc
        pla
@out:   jmp     putc

; print the string at A (lo) / Y (hi), ended by TERM (any length)
print:  sta     @ld+1
        sty     @ld+2
@ld:    lda     $FFFF
        cmp     #TERM
        beq     @done
        jsr     putc
        inc     @ld+1
        bne     @ld
        inc     @ld+2
        bne     @ld
@done:  lda     #$FF            ; (strings may change the attribute)
        sta     attr
        rts

; print A as two BCD digits
prbcd:  pha
        lsr
        lsr
        lsr
        lsr
        ora     #'0'
        jsr     putc
        pla
        and     #$0F
        ora     #'0'
        jmp     putc

; print A (0-99) as two decimal digits
prdec2: ldx     #'0'
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     pha
        txa
        jsr     putc
        pla
        ora     #'0'
        jmp     putc

; 16 bit Galois LFSR.  A = a random byte.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait about A ms.  The inner loop is sized for the clock (CLOCK_MHZ in
; sbc_api.inc): 5 + 4 * (CLOCK_MHZ - 1) cycles a turn, DELAY_N turns a ms.
DELAY_N = (1000 * CLOCK_MHZ - 7) / (5 + 4 * (CLOCK_MHZ - 1))
delay_ms:
        tax
        beq     @done
@o:     jsr     sfx_poll        ; (and while waiting)
        ldy     #DELAY_N
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

; wait about A x 50 ms, dropping keys pressed meanwhile
delay_long:
        sta     tmp
@l:     lda     #50
        jsr     delay_ms
        jsr     flush_in
        dec     tmp
        bne     @l
        rts

.macro MENU_IDLE
        jsr     rand            ; (waiting stirs the random numbers)
        jsr     sfx_poll
.endmacro
CTRL_COL        = 19
CTRL_ROW        = 20

; ============================================================================
; gamepad and menu input (shared by the SBC games)
; ============================================================================
PAD_A           = $01           ; bits returned by SBC_PADSTATE
PAD_B           = $02
PAD_SELECT      = $04
PAD_START       = $08
PAD_UP          = $10
PAD_DOWN        = $20
PAD_LEFT        = $40
PAD_RIGHT       = $80
PAD_GO          = $80           ; menu_key's answer for gamepad A or Start

; read the gamepad: pad = buttons held now, padnew = buttons pressed since
; the last call.  Preserves X and Y (SBC_PADSTATE only changes A).
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

; throw away waiting characters
flush_in:
        jsr     getc
        bcs     flush_in
        rts

; carry set if A is one of the characters the gamepad driver types for the
; pad (W A S D and space).  Those are ignored in gamepad mode so that one
; press doesn't act twice.  Preserves A.
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

; wait for a menu choice.  Returns a key (letters in upper case), or
; PAD_GO for the gamepad's A or Start button.
menu_key:
@l:     MENU_IDLE
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
@pad:   jsr     flush_in        ; the space the driver typed for it
        lda     #PAD_GO
        rts

; print the controls line (CTRL_COL, CTRL_ROW)
show_ctrl:
        jsr     txt_mode
        ldx     #CTRL_COL
        ldy     #CTRL_ROW
        jsr     gotoxy
        lda     ctrl
        beq     @kb
        lda     #<ctrl_pad_txt
        ldy     #>ctrl_pad_txt
        jmp     print
@kb:    lda     #<ctrl_kb_txt
        ldy     #>ctrl_kb_txt
        jmp     print

; ============================================================================
; start, title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear the variables (RAM is random at power-up)
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
        lda     #$FF
        sta     attr
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
        jsr     spr_setup       ; the terminal's sprites (or back to the menu)

title:  jsr     sfx_off
        lda     #0
        sta     rp_on
        jsr     new_screen
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     txt_mode        ; the high score
        ldx     #34
        ldy     #18
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jsr     prbcd
        ldx     #NTSPR-1        ; Willy and the guardians, for show
@ts:    lda     tspr_n,x
        sta     des_n
        lda     tspr_x,x
        sta     des_x
        lda     #32 + 44
        sta     des_y
        lda     #TC_SPR
        jsr     putc
        lda     #SPR_PLACE
        jsr     putc
        txa
        jsr     putc
        lda     des_n
        jsr     putc
        lda     des_x
        jsr     putc
        lda     des_y
        jsr     putc
        lda     #0
        jsr     putc
        dex
        bpl     @ts
        jsr     show_ctrl
        lda     #<start_txt
        ldy     #>start_txt
        jsr     print
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
@notm:  cmp     #'G'
        bne     @notg
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@notg:  cmp     #PAD_GO
        bne     @notp
        lda     #1
        sta     ctrl
        jmp     new_game
@notp:  cmp     #' '
        bne     @wait
        jmp     new_game

exit_game:
        jsr     sfx_off
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
        jmp     SBC_MENU

; clear the screen (which hides the sprites) and forget what it showed
new_screen:
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        ldx     #NSLOT-1
        lda     #0
@f:     sta     sl_on,x
        sta     des_on,x
        dex
        bpl     @f
        lda     #1              ; (nothing to wait for)
        sta     rp_got
        rts

; ============================================================================
; the terminal's sprite layer: IDENTIFY, then the pictures; without it, a
; word and back to the boot menu
; ============================================================================
spr_setup:
        jsr     flush_in
        lda     #<ident_txt
        ldy     #>ident_txt
        jsr     print
        lda     #200            ; up to 200 ms
        sta     rp_t
@w:     jsr     SBC_CHRIN
        bcs     @c
@w1:    lda     #1
        jsr     delay_ms
        dec     rp_t
        bne     @w
        lda     #<nospr_txt     ; no answer
        ldy     #>nospr_txt
        jsr     print
        jsr     menu_key
        jmp     SBC_MENU
@c:     cmp     #'S'
        beq     @yes
        cmp     #'P'
        beq     @yes
        cmp     #'1'
        bne     @w1
@yes:   lda     #20             ; (the rest of the answer)
        jsr     delay_ms
        jsr     flush_in
        lda     #<spr_defs      ; the pictures (SPR_DEFS bytes)
        sta     @ld+1
        lda     #>spr_defs
        sta     @ld+2
        lda     #<SPR_DEFS
        sta     tmp
        lda     #>SPR_DEFS
        sta     tmp+1
@ld:    lda     $FFFF
        jsr     SBC_CHROUT
        inc     @ld+1
        bne     @n
        inc     @ld+2
@n:     lda     tmp
        bne     @dd
        dec     tmp+1
@dd:    dec     tmp
        lda     tmp
        ora     tmp+1
        bne     @ld
        rts

; ---- pacing: IDENTIFY after each frame; the next waits for the answer ----
ASK_MS          = 60
ask_send:
        lda     #1
        sta     rp_on
        lda     #0
        sta     rp_got
        lda     #<ident_txt
        ldy     #>ident_txt
        jmp     print

ask_wait:
        lda     rp_got
        bne     @r
        lda     #ASK_MS
        sta     rp_t
@l:     jsr     getc
        bcc     @none
        jsr     handle_key      ; (a key meanwhile)
        jmp     @chk
@none:  lda     #1
        jsr     delay_ms
        dec     rp_t
        beq     @r
@chk:   lda     rp_got
        beq     @l
@r:     rts

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
        sta     score
        sta     score+1
        sta     score+2
        sta     room
        sta     quit
        lda     #3
        sta     lives
start_room:
        jsr     load_room
        jsr     new_screen
        jsr     draw_room
        lda     #<clip_txt      ; sprites only in the room
        ldy     #>clip_txt
        jsr     print
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        lda     #0
        sta     frame
        sta     air_t
        sta     jhold
        sta     mv_hold
        jsr     sfx_off         ; the tune, from its start
        lda     #MUS_HALL
        jsr     sfx_snd
        lda     #MUS_HALL+1
        jsr     sfx_snd

; ---- the frame loop --------------------------------------------------------------
game_loop:
        jsr     sfx_poll
        lda     #0
        sta     nbytes
        sta     nbytes+1
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     ask_wait        ; the terminal has drawn the last frame
        lda     #<hold_txt
        ldy     #>hold_txt
        jsr     print
        jsr     guards_move
        lda     in_d
        ldx     in_j
        jsr     willy_step
        jsr     willy_touch     ; hazards, keys
        jsr     guards_hit
        jsr     air_tick
        jsr     set_sprites
        jsr     spr_send
        lda     #<show_txt
        ldy     #>show_txt
        jsr     print
        jsr     ask_send
        jsr     hud_update
        jsr     pace
        inc     frame
        lda     w_dead
        beq     @2
        jmp     life_lost
@2:     lda     keys_left       ; all the keys, and in the portal?
        bne     game_loop
        jsr     in_portal
        bcc     game_loop
        jmp     room_done

; wait out the rest of the frame: about (speed - what the frame took) ms:
; the bytes at 115200 baud (87 us each) and the 6502's work (about 4 ms at
; 1 MHz, measured in the emulator)
WORK_MS         = 4 / CLOCK_MHZ
pace:   lda     nbytes+1
        bne     @r
        lda     nbytes          ; bytes * 0.087 ~ bytes / 16 + bytes / 32
        lsr
        lsr
        lsr
        lsr
        sta     tmp
        lsr
        adc     tmp
        adc     #WORK_MS
        sta     tmp
        lda     speed
        sec
        sbc     tmp
        bcc     @r
        beq     @r
        jmp     delay_ms
@r:     rts

; Willy is gone: he blinks, a life goes, and the room starts again
life_lost:
        jsr     sfx_off         ; the tune stops
        lda     #SND_DIEA
        jsr     sfx_snd
        lda     #SND_DIEC
        jsr     sfx_snd
        ldx     #8
@b:     stx     tmp3
        txa
        and     #1
        beq     @hd
        jsr     set_sprites     ; (shown)
        jmp     @sd
@hd:    lda     #0              ; (hidden)
        sta     des_on+SL_WILLY
@sd:    jsr     spr_send
        lda     #80
        jsr     delay_ms
        ldx     tmp3
        dex
        bne     @b
        dec     lives
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        lda     lives
        bne     @more
        jmp     game_over
@more:  jmp     start_room

; through the portal: the air left goes to the score, then the next room
room_done:
        lda     #<hideall_txt
        ldy     #>hideall_txt
        jsr     print
        ldx     #NSLOT-1
        lda     #0
@f:     sta     sl_on,x
        dex
        bpl     @f
        jsr     sfx_off
        lda     #SND_ROOM
        jsr     sfx_snd
        lda     #10
        jsr     delay_long
@a:     lda     air             ; 10 points a unit of air
        beq     @next
        and     #3              ; (a tick every 4)
        bne     @nt
        lda     #SND_AIRTICK
        jsr     sfx_snd
@nt:    jsr     air_down
        lda     #$10
        ldy     #0
        jsr     add_score
        jsr     hud_update
        lda     #8
        jsr     delay_ms
        jmp     @a
@next:  lda     #10
        jsr     delay_long
        inc     room
        lda     room
        cmp     #NROOM
        bcc     @r
        lda     #0              ; all of them: round again
        sta     room
        lda     #SND_ALLA
        jsr     sfx_snd
        lda     #SND_ALLB
        jsr     sfx_snd
        lda     #<allclear_txt
        ldy     #>allclear_txt
        jsr     print
        lda     #40
        jsr     delay_long
@r:     jmp     start_room

game_over:
        ldx     #2              ; new high score?
@hc:    lda     score,x
        cmp     hiscore,x
        bcc     @nohi
        bne     @hi
        dex
        bpl     @hc
        bmi     @nohi
@hi:    ldx     #2
@hs:    lda     score,x
        sta     hiscore,x
        dex
        bpl     @hs
        lda     #1
        sta     hud_dirty
        jsr     hud_update
@nohi:  lda     #SND_OVER
        jsr     sfx_snd
        lda     #<hideall_txt
        ldy     #>hideall_txt
        jsr     print
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
        lda     #20
        jsr     delay_long
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
; the room
; ============================================================================
; the room's data (room_lo / hi, room) into its variables and map
load_room:
        ldx     room
        lda     room_lo,x
        sta     src
        lda     room_hi,x
        sta     src+1
        lda     #32             ; (the name is drawn from there)
        jsr     src_add
        jsr     src_get         ; air
        sta     air
        jsr     src_get         ; Willy
        sta     w_x
        jsr     src_get
        sta     w_y
        jsr     src_get         ; the portal
        sta     p_x
        jsr     src_get
        sta     p_y
        jsr     src_get         ; the guardians
        sta     ng
        ldx     #0
@g:     cpx     ng
        beq     @gd
        jsr     src_get
        sta     g_kind,x
        jsr     src_get
        sta     g_axis,x
        jsr     src_get
        sta     g_x,x
        jsr     src_get
        sta     g_y,x
        jsr     src_get
        sta     g_lo,x
        jsr     src_get
        sta     g_hi,x
        jsr     src_get
        sta     g_slow,x
        lda     #1
        sta     g_dir,x
        lda     #0
        sta     g_t,x
        inx
        bne     @g
@gd:    lda     #0              ; the tiles, two to a byte
        sta     keys_left
        sta     tmp2            ; (map index, 16 bits: tmp2 / tmp3)
        sta     tmp3
@t:     jsr     src_get
        pha
        and     #$0F
        jsr     @put
        pla
        lsr
        lsr
        lsr
        lsr
        jsr     @put
        lda     tmp3
        cmp     #>(NTILE)
        bne     @t
        lda     tmp2
        cmp     #<(NTILE)
        bne     @t
        lda     #0              ; Willy: standing, facing right
        sta     w_mode
        sta     w_jt
        sta     w_jdx
        sta     w_anim
        sta     w_crt
        sta     w_dead
        sta     w_face
        lda     w_y
        sta     w_ytop
        rts
@put:   cmp     #KEY
        bne     @p1
        inc     keys_left
@p1:    pha
        lda     #<map
        clc
        adc     tmp2
        sta     @w+1
        lda     #>map
        adc     tmp3
        sta     @w+2
        pla
@w:     sta     $FFFF
        inc     tmp2
        bne     @p2
        inc     tmp3
@p2:    rts

; the next byte of the room data (src), and src + A
src_get:
        lda     src
        sta     @l+1
        lda     src+1
        sta     @l+2
@l:     lda     $FFFF
        inc     src
        bne     @r
        inc     src+1
@r:     rts
src_add:clc
        adc     src
        sta     src
        bcc     @r
        inc     src+1
@r:     rts

; draw the whole room, its name and the air
draw_room:
        lda     #<nowrap_txt
        ldy     #>nowrap_txt
        jsr     print
        lda     #0
        sta     dr_r
@row:   jsr     gfx_mode
        ldx     #0
        ldy     dr_r
        jsr     gotoxy
        ldx     dr_r            ; the row's 80 characters into rowbuf
        lda     rowoff_lo,x
        clc
        adc     #<map
        sta     @m+1
        lda     rowoff_hi,x
        adc     #>map
        sta     @m+2
        ldx     #0
        ldy     #0
@c:
@m:     lda     $FFFF,x
        sty     tmp4
        tay
        lda     tile_l,y
        pha
        lda     tile_r,y
        ldy     tmp4
        sta     rowbuf+1,y
        pla
        sta     rowbuf,y
        iny
        iny
        inx
        cpx     #COLS
        bne     @c
        jsr     put_row         ; and out, runs with the repeat count
        inc     dr_r
        lda     dr_r
        cmp     #ROWS
        bne     @row
        lda     #<name_txt      ; the name, reversed
        ldy     #>name_txt
        jsr     print
        ldx     room
        lda     room_lo,x
        sta     @n+1
        lda     room_hi,x
        sta     @n+2
        ldx     #0
@n:     lda     $FFFF,x
        jsr     putc
        inx
        cpx     #32
        bne     @n
        lda     #<rvoff_txt
        ldy     #>rvoff_txt
        jsr     print
        lda     #<air_txt       ; the air
        ldy     #>air_txt
        jsr     print
        jsr     gfx_mode
        lda     air
        lsr
        tax
        beq     @h
@a:     lda     #$FF
        jsr     putc
        dex
        bne     @a
@h:     lda     air
        and     #1
        beq     @r
        lda     #$55
        jsr     putc
@r:     rts

; send rowbuf (80 block graphics characters): a run of 3 or more of the same
; one goes once, with the repeat count
put_row:
        ldx     #0
@l:     lda     rowbuf,x
        sta     tmp
        ldy     #1              ; the run
@r:     txa
        sty     tmp4
        clc
        adc     tmp4
        cmp     #COLS * 2
        bcs     @e
        tay
        lda     rowbuf,y
        cmp     tmp
        bne     @e
        ldy     tmp4
        iny
        cpy     #15
        bcc     @r
        bcs     @e2
@e:     ldy     tmp4
@e2:    sty     tmp4
        cpy     #3
        bcs     @run
        lda     #1              ; one or two: one at a time
        jsr     set_rep
        lda     tmp
        jsr     putblk
        inx
        jmp     @n
@run:   tya
        jsr     set_rep
        lda     tmp
        jsr     putblk
        txa
        clc
        adc     tmp4
        tax
@n:     cpx     #COLS * 2
        bcc     @l
        lda     #1
        jmp     set_rep

; repeat every character A times from now on (1..15), block graphics
set_rep:cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        jmp     setattr         ; (sends it only if it changes)
@one:   lda     #ATTR_GFX
        jmp     setattr

; draw tile tc, tr as the map has it
draw_tile:
        lda     tc
        asl
        tax
        ldy     tr
        jsr     gfx_mode
        jsr     gotoxy
        jsr     tile_get
        tay
        lda     tile_l,y
        jsr     putblk
        lda     tile_r,y
        jmp     putblk

; A = the tile at tc, tr (empty outside the room); tile_adr = its address
tile_get:
        lda     tr
        cmp     #ROWS
        bcs     @out
        lda     tc
        cmp     #COLS
        bcs     @out
        ldx     tr
        lda     rowoff_lo,x
        clc
        adc     tc
        sta     tile_adr
        lda     rowoff_hi,x
        adc     #0
        sta     tile_adr+1
        lda     tile_adr
        clc
        adc     #<map
        sta     tile_adr
        sta     @l+1
        lda     tile_adr+1
        adc     #>map
        sta     tile_adr+1
        sta     @l+2
@l:     lda     $FFFF
        rts
@out:   lda     #EMPTY
        rts

; set the tile at tile_adr (from tile_get) to A
tile_set:
        pha
        lda     tile_adr
        sta     @s+1
        lda     tile_adr+1
        sta     @s+2
        pla
@s:     sta     $FFFF
        rts

; ============================================================================
; Willy (see phys.py: the same rules, step by step)
; ============================================================================
; his columns: c0 = x / 4 .. c1 = (x + 5) / 4
w_cols: lda     w_x
        lsr
        lsr
        sta     c0
        lda     w_x
        clc
        adc     #W_W - 1
        lsr
        lsr
        sta     c1
        rts

; carry set if something holds him up (a floor tile under his feet)
support:
        lda     w_y
        clc
        adc     #W_H
        lsr
        lsr
        cmp     #ROWS
        bcs     @no
        sta     tr
        jsr     w_cols
        lda     c0
        sta     tc
@l:     jsr     tile_get
        cmp     #FLOOR
        bcc     @n
        cmp     #CR2 + 1
        bcc     @yes
@n:     inc     tc
        lda     tc
        cmp     c1
        beq     @l
        bcc     @l
@no:    clc
        rts
@yes:   sec
        rts

; A = the conveyor under his feet: 1 right, $FF left, 0 none
conveyor:
        lda     w_y
        clc
        adc     #W_H
        lsr
        lsr
        sta     tr
        jsr     w_cols
        lda     c0
        sta     tc
@l:     jsr     tile_get
        cmp     #CONV_L
        beq     @left
        cmp     #CONV_R
        beq     @right
        inc     tc
        lda     tc
        cmp     c1
        beq     @l
        bcc     @l
        lda     #0
        rts
@left:  lda     #$FF
        rts
@right: lda     #1
        rts

; carry set if column tc has a wall in his rows (y / 4 .. (y + 7) / 4)
wall_rows:
        lda     w_y
        lsr
        lsr
        sta     tr
        lda     w_y
        clc
        adc     #W_H - 1
        lsr
        lsr
        sta     tmp4
@l:     jsr     tile_get
        cmp     #WALL
        beq     @yes
        inc     tr
        lda     tr
        cmp     tmp4
        beq     @l
        bcc     @l
        clc
        rts
@yes:   sec
        rts

; move him A (1 or $FF) across unless a wall or the edge stops him; carry
; set if he moved
move_x: sta     tmp
        cmp     #1
        bne     @left
        lda     w_x             ; right: x + 1 + 5 <= 159
        cmp     #COLS * 4 - W_W
        bcs     @no
        clc
        adc     #W_W            ; (x + 1 + 5) / 4
        lsr
        lsr
        bpl     @chk
@left:  lda     w_x
        beq     @no
        sec
        sbc     #1
        lsr
        lsr
@chk:   sta     tc
        jsr     wall_rows
        bcs     @no
        lda     w_x
        clc
        adc     tmp
        sta     w_x
        sec
        rts
@no:    clc
        rts

; carry set if a wall is just above his head (or the top)
head_blocked:
        lda     w_y
        beq     @yes
        sec
        sbc     #1
        lsr
        lsr
        sta     tr
        jsr     w_cols
        lda     c0
        sta     tc
@l:     jsr     tile_get
        cmp     #WALL
        beq     @yes
        inc     tc
        lda     tc
        cmp     c1
        beq     @l
        bcc     @l
        clc
        rts
@yes:   sec
        rts

; on the ground again: a fall from too high kills
land:   lda     #SND_LAND
        jsr     sfx_snd
        lda     #ST_STAND
        sta     w_mode
        lda     w_y
        sec
        sbc     w_ytop
        cmp     #FALL_MAX + 1
        bcc     @r
        lda     #1
        sta     w_dead
@r:     rts

; carry set if his feet are on a tile's top and something holds him up
on_ground:
        lda     w_y
        clc
        adc     #W_H
        and     #3
        bne     @no
        jmp     support
@no:    clc
        rts

; one frame of Willy: A = -1 / 0 / 1 (left, none, right), X = jump pressed
willy_step:
        sta     w_d
        stx     w_j
        lda     w_mode
        beq     @stand
        cmp     #ST_JUMP
        bne     @fall0
        jmp     @jump
@fall0: jmp     @fall
@stand: jsr     support
        bcs     @held
        lda     #ST_FALL        ; nothing under him: down he goes
        sta     w_mode
        lda     w_y
        sta     w_ytop
        rts
@held:  jsr     conveyor        ; a conveyor takes him its way
        beq     @nc
        sta     w_d
@nc:    lda     w_j
        beq     @walk
        lda     #SND_JUMP
        jsr     sfx_snd
        lda     #ST_JUMP        ; a jump, the way he is going
        sta     w_mode
        lda     #0
        sta     w_jt
        lda     w_d
        sta     w_jdx
        beq     @j0
        jsr     set_face
@j0:    lda     w_y
        sta     w_ytop
        jmp     @jump
@walk:  lda     w_d
        beq     @crum
        jsr     set_face
        lda     w_d
        jsr     move_x
        bcc     @crum
        lda     w_anim
        clc
        adc     #1
        and     #7
        sta     w_anim
@crum:  lda     w_y             ; a crumbling floor under his feet
        clc
        adc     #W_H
        lsr
        lsr
        sta     tr
        jsr     w_cols
        lda     #0
        sta     tmp3            ; (any?)
        lda     c0
        sta     tc
@cl:    jsr     tile_get
        cmp     #CR0
        bcc     @cn
        cmp     #CR2 + 1
        bcs     @cn
        inc     tmp3
@cn:    inc     tc
        lda     tc
        cmp     c1
        beq     @cl
        bcc     @cl
        lda     tmp3
        beq     @r
        inc     w_crt
        lda     w_crt
        cmp     #CRUMBLE_T
        bcc     @r
        lda     #0
        sta     w_crt
        lda     c0              ; each one a stage on
        sta     tc
@cs:    jsr     tile_get
        cmp     #CR0
        bcc     @cs2
        cmp     #CR2 + 1
        bcs     @cs2
        cmp     #CR2
        bne     @cs1
        lda     #<(EMPTY - 1)   ; (gone)
@cs1:   clc
        adc     #1
        jsr     tile_set
        jsr     draw_tile
@cs2:   inc     tc
        lda     tc
        cmp     c1
        beq     @cs
        bcc     @cs
@r:     rts

@jump:  ldx     w_jt            ; this frame's rise or fall
        lda     jtab,x
        sta     w_dy
        inc     w_jt
        lda     w_jdx
        beq     @jy
        jsr     move_x
        bcs     @jy
        lda     #0              ; (a wall: straight on)
        sta     w_jdx
@jy:    lda     w_dy
        beq     @jend
        bpl     @down
@up:    jsr     head_blocked    ; up, a pixel at a time
        bcc     @up1
        lda     #ST_FALL
        sta     w_mode
        rts
@up1:   dec     w_y
        lda     w_y
        sta     w_ytop
        inc     w_dy
        bne     @up
        beq     @jend
@down:  jsr     on_ground       ; down, a pixel at a time, landing on a floor
        bcc     @dn1
        jmp     land
@dn1:   inc     w_y
        dec     w_dy
        bne     @down
@jend:  lda     w_jt
        cmp     #JTAB_LEN
        bne     @jr
        lda     #ST_FALL
        sta     w_mode
@jr:    rts

@fall:  lda     #2              ; 2 pixels a frame, straight down
        sta     w_dy
@fl:    jsr     on_ground
        bcc     @fl1
        jmp     land
@fl1:   inc     w_y
        dec     w_dy
        bne     @fl
        lda     w_y             ; out of the bottom
        clc
        adc     #W_H
        cmp     #ROWS * 4 + 1
        bcc     @fr
        lda     #1
        sta     w_dead
@fr:    rts

set_face:
        lda     w_d
        bmi     @l
        lda     #0
        sta     w_face
        rts
@l:     lda     #1
        sta     w_face
        rts

; the tiles he is on: a hazard kills, a key is his
willy_touch:
        jsr     w_cols
        lda     w_y
        lsr
        lsr
        sta     tr
        lda     w_y
        clc
        adc     #W_H - 1
        lsr
        lsr
        sta     tmp3            ; the last row
@r:     lda     c0
        sta     tc
@c:     jsr     tile_get
        cmp     #HAZARD
        bne     @k
        lda     #1
        sta     w_dead
        bne     @n
@k:     cmp     #KEY
        bne     @n
        lda     #SND_KEY
        jsr     sfx_snd
        lda     #EMPTY
        jsr     tile_set
        jsr     draw_tile
        dec     keys_left
        lda     #$00            ; 100 points
        ldy     #$01
        jsr     add_score
@n:     inc     tc
        lda     tc
        cmp     c1
        beq     @c
        bcc     @c
        inc     tr
        lda     tr
        cmp     tmp3
        beq     @r
        bcc     @r
        rts

; carry set if he is in the portal (boxes overlap)
in_portal:
        lda     w_x             ; x + 5 >= px and x <= px + 7
        clc
        adc     #W_W - 1
        cmp     p_x
        bcc     @no
        lda     p_x
        clc
        adc     #7
        cmp     w_x
        bcc     @no
        lda     w_y             ; y + 7 >= py and y <= py + 7
        clc
        adc     #W_H - 1
        cmp     p_y
        bcc     @no
        lda     p_y
        clc
        adc     #7
        cmp     w_y
        bcc     @no
        sec
        rts
@no:    clc
        rts

; ============================================================================
; the guardians: to and fro between lo and hi, a pixel a frame (or every
; second frame if slow)
; ============================================================================
guards_move:
        ldx     ng
        dex
        bmi     @r
@g:     lda     g_t,x
        eor     #1
        sta     g_t,x
        beq     @go
        lda     g_slow,x
        bne     @n
@go:    lda     g_axis,x
        bne     @v
        lda     g_x,x
        jsr     @turn
        sta     g_x,x
        jmp     @n
@v:     lda     g_y,x
        jsr     @turn
        sta     g_y,x
@n:     dex
        bpl     @g
@r:     rts
@turn:  sta     tmp             ; A = its place: turn at the ends, then move
        lda     g_dir,x
        bmi     @tl
        lda     tmp
        cmp     g_hi,x
        bcc     @ok
        lda     #$FF
        sta     g_dir,x
        bne     @ok
@tl:    lda     tmp
        cmp     g_lo,x
        beq     @tr
        bcs     @ok
@tr:    lda     #1
        sta     g_dir,x
@ok:    lda     tmp
        clc
        adc     g_dir,x
        rts

; a guardian touching Willy kills him (its box 1 pixel in on each side)
guards_hit:
        ldx     ng
        dex
        bmi     @r
@g:     lda     g_x,x           ; x + 5 >= gx + 1 and x <= gx + 6
        clc
        adc     #1
        sta     tmp
        lda     w_x
        clc
        adc     #W_W - 1
        cmp     tmp
        bcc     @n
        lda     g_x,x
        clc
        adc     #6
        cmp     w_x
        bcc     @n
        lda     g_y,x           ; y + 7 >= gy + 1 and y <= gy + 6
        clc
        adc     #1
        sta     tmp
        lda     w_y
        clc
        adc     #W_H - 1
        cmp     tmp
        bcc     @n
        lda     g_y,x
        clc
        adc     #6
        cmp     w_y
        bcc     @n
        lda     #1
        sta     w_dead
@n:     dex
        bpl     @g
@r:     rts

; ============================================================================
; the air: a unit every AIR_RATE frames; none left kills
; ============================================================================
air_tick:
        inc     air_t
        lda     air_t
        cmp     #AIR_RATE
        bcc     @r
        lda     #0
        sta     air_t
        lda     air
        beq     @dead
        jsr     air_down
        lda     air
        bne     @r
@dead:  lda     #1
        sta     w_dead
@r:     rts

; one unit less, and its half character of the bar
air_down:
        dec     air
        lda     air
        lsr
        clc
        adc     #AIR_COL
        tax
        ldy     #AIR_ROW
        jsr     gfx_mode
        jsr     gotoxy
        lda     air
        and     #1
        beq     @e
        lda     #$55
        jmp     putblk
@e:     lda     #$00
        jmp     putblk

; ============================================================================
; the sprites: where each slot should be (des_*), and what changed is sent
; ============================================================================
set_sprites:
        ldx     #NSLOT-1
        lda     #0
@c:     sta     des_on,x
        dex
        bpl     @c
        lda     #1              ; Willy
        sta     des_on+SL_WILLY
        lda     w_anim
        lsr
        and     #3
        clc
        adc     #PIC_WILLY
        sta     des_n+SL_WILLY
        lda     w_x
        clc
        adc     #32
        sta     des_x+SL_WILLY
        lda     w_y
        clc
        adc     #32
        sta     des_y+SL_WILLY
        lda     w_face
        sta     des_f+SL_WILLY
        lda     #1              ; the portal: shut, or flashing when open
        sta     des_on+SL_PORTAL
        lda     #PIC_PORTAL
        ldx     keys_left
        bne     @ps
        lda     frame
        lsr
        lsr
        and     #1
        clc
        adc     #PIC_PORTAL + 1
@ps:    sta     des_n+SL_PORTAL
        lda     p_x
        clc
        adc     #32
        sta     des_x+SL_PORTAL
        lda     p_y
        clc
        adc     #32
        sta     des_y+SL_PORTAL
        lda     #0
        sta     des_f+SL_PORTAL
        ldx     ng              ; the guardians
        dex
        bmi     @r
@g:     lda     #1
        sta     des_on+SL_GUARD,x
        ldy     g_kind,x
        lda     g_axis,x        ; its frame from where it is
        bne     @gv
        lda     g_x,x
        jmp     @gf
@gv:    lda     g_y,x
@gf:    lsr
        lsr
        and     #1
        clc
        adc     guard_pic,y
        sta     des_n+SL_GUARD,x
        lda     g_x,x
        clc
        adc     #32
        sta     des_x+SL_GUARD,x
        lda     g_y,x
        clc
        adc     #32
        sta     des_y+SL_GUARD,x
        lda     #0              ; facing the way it goes (across)
        ldy     g_axis,x
        bne     @gs
        ldy     g_dir,x
        bpl     @gs
        lda     #1
@gs:    sta     des_f+SL_GUARD,x
        dex
        bpl     @g
@r:     rts

; send what changed in the slots (des_* against sl_*, what the terminal shows)
spr_send:
        ldx     #NSLOT-1
@l:     stx     hs_i
        lda     des_on,x
        bne     *+5
        jmp     @off
        lda     sl_on,x
        beq     @place
        lda     des_f,x
        cmp     sl_f,x
        bne     @place
        lda     des_n,x
        cmp     sl_n,x
        beq     @samen
        lda     #SPR_PIC
        jsr     spr_cmd
        lda     des_n,x
        jsr     putc
@samen: lda     des_x,x
        cmp     sl_x,x
        bne     @move
        lda     des_y,x
        cmp     sl_y,x
        beq     @keep
@move:  lda     #SPR_MOVE
        jsr     spr_cmd
        lda     des_x,x
        jsr     putc
        lda     des_y,x
        jsr     putc
        jmp     @keep
@place: lda     #SPR_PLACE
        jsr     spr_cmd
        lda     des_n,x
        jsr     putc
        lda     des_x,x
        jsr     putc
        lda     des_y,x
        jsr     putc
        lda     des_f,x
        jsr     putc
@keep:  lda     #1
        sta     sl_on,x
        lda     des_n,x
        sta     sl_n,x
        lda     des_x,x
        sta     sl_x,x
        lda     des_y,x
        sta     sl_y,x
        lda     des_f,x
        sta     sl_f,x
        jmp     @n
@off:   lda     sl_on,x
        beq     @n
        lda     #0
        sta     sl_on,x
        lda     #SPR_HIDE
        jsr     spr_cmd
@n:     ldx     hs_i
        dex
        bmi     *+5
        jmp     @l
        rts

; send 1C, command A, slot hs_i.  X = hs_i after.
spr_cmd:pha
        lda     #TC_SPR
        jsr     putc
        pla
        jsr     putc
        lda     hs_i
        jsr     putc
        ldx     hs_i
        rts

; ============================================================================
; the status line, the score
; ============================================================================
hud_update:
        lda     hud_dirty
        bne     @go
        rts
@go:    lda     #0
        sta     hud_dirty
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        lda     score+2
        jsr     prbcd
        lda     score+1
        jsr     prbcd
        lda     score
        jsr     prbcd
        lda     #<hi2_txt
        ldy     #>hi2_txt
        jsr     print
        lda     hiscore+2
        jsr     prbcd
        lda     hiscore+1
        jsr     prbcd
        lda     hiscore
        jsr     prbcd
        lda     #<lives_txt
        ldy     #>lives_txt
        jsr     print
        lda     lives
        ora     #'0'
        jsr     putc
        lda     #<room_txt
        ldy     #>room_txt
        jsr     print
        lda     room
        clc
        adc     #1
        jmp     prdec2

; add A (BCD, low) / Y (BCD, high) to the score.  Every 10000: a life.
add_score:
        ldx     score+2
        stx     tmp
        php
        sei
        sed
        clc
        adc     score
        sta     score
        tya
        adc     score+1
        sta     score+1
        lda     score+2
        adc     #0
        sta     score+2
        cld
        plp
        lda     score+2         ; the 10000s changed: a life
        cmp     tmp
        beq     @n
        lda     lives
        cmp     #9
        bcs     @n
        inc     lives
@n:     lda     #1
        sta     hud_dirty
        rts

; ============================================================================
; input
; ============================================================================
read_input:
        lda     #0
        sta     in_d
        sta     in_j
        lda     ctrl
        beq     @keys
        jsr     read_pad
        lda     pad
        and     #PAD_LEFT
        beq     @r
        lda     #$FF
        sta     in_d
@r:     lda     pad
        and     #PAD_RIGHT
        beq     @a
        lda     #1
        sta     in_d
@a:     lda     pad             ; jump: A, B or up, held
        and     #PAD_A | PAD_B | PAD_UP
        beq     @st
        lda     #1
        sta     in_j
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  jsr     getc
        bcc     @held
        jsr     handle_key
        jmp     @keys
@held:  lda     ctrl            ; keyboard: a key goes on for a few frames
        bne     @done           ; (key repeat is slower than the frames)
        lda     mv_hold
        beq     @jh
        dec     mv_hold
        lda     mv_dir
        sta     in_d
@jh:    lda     jhold
        beq     @done
        dec     jhold
        lda     #1
        sta     in_j
@done:  rts
HOLD_MOVE       = 4
HOLD_JUMP       = 2

handle_key:
        ldx     esc_st          ; arrow keys: ESC [ A / C / D
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
        beq     @jump
        cmp     #'C'
        beq     @right
        cmp     #'D'
        beq     @left
        rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    ldx     ctrl            ; gamepad mode: ignore what the pad types
        beq     @kb
        jsr     pad_typed
        bcc     @kb
        rts
@kb:    cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #' '
        beq     @jump
        cmp     #'W'
        beq     @jump
        cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        bne     @r
        jmp     sfx_toggle
@r:     rts
@left:  lda     #$FF
        bne     @mv
@right: lda     #1
@mv:    sta     mv_dir
        sta     in_d
        lda     #HOLD_MOVE
        sta     mv_hold
        rts
@jump:  lda     #1
        sta     in_j
        lda     #HOLD_JUMP
        sta     jhold
        rts
@pause: jmp     pause
@quit:  lda     #1
        sta     quit
        rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        jsr     txt_mode
        ldx     #70
        ldy     #23
        jsr     gotoxy
        lda     #<paused_txt
        ldy     #>paused_txt
        jsr     print
        jsr     flush_in
@w:     jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @go
        jsr     getc
        bcc     @w
@go:    jsr     flush_in
        jsr     txt_mode
        ldx     #70
        ldy     #23
        jsr     gotoxy
        lda     #<unpaused_txt
        ldy     #>unpaused_txt
        jmp     print

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
rowoff_lo:
        .repeat ROWS, K
        .byte   <(K * COLS)
        .endrepeat
rowoff_hi:
        .repeat ROWS, K
        .byte   >(K * COLS)
        .endrepeat
NTSPR           = 7             ; the title's sprites
tspr_n: .byte   PIC_WILLY, PIC_ROBOT, PIC_BIRD, PIC_BLOB, PIC_SPIN, PIC_SKULL, PIC_JELLY
tspr_x: .byte   32 + 40, 32 + 54, 32 + 66, 32 + 78, 32 + 90, 32 + 102, 32 + 114

cls_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, 0, TERM
ident_txt:
        .byte   TC_SPR, $0C, TERM       ; IDENTIFY (the answer: S P 1)
hold_txt:
        .byte   TC_SPR, $09, TERM
show_txt:
        .byte   TC_SPR, $0A, TERM
hideall_txt:
        .byte   TC_SPR, $07, TERM
clip_txt:                               ; sprites only in the room: text rows 0-19
        .byte   TC_SPR, $0B, 0, ROWS - 1, TERM
nowrap_txt:
        .byte   $1B, "[?7l", TERM       ; no line wrap: the last column is safe
title_txt:
        .byte   TC_ROW, 2, TC_COL, 34, RV_ON, "  MINER  MOS  ", RV_OFF
        .byte   TC_ROW, 5, TC_COL, 13, "MOS THE MINER IS DEEP IN THE 6502, AND HIS AIR IS RUNNING OUT."
        .byte   TC_ROW, 7, TC_COL, 13, "TAKE EVERY KEY IN A ROOM, THEN GET TO THE PORTAL. KEEP CLEAR OF"
        .byte   TC_ROW, 8, TC_COL, 13, "THE GUARDIANS AND THE SPIKES, AND DON'T FALL TOO FAR. CRUMBLING"
        .byte   TC_ROW, 9, TC_COL, 13, "FLOORS GIVE WAY, AND CONVEYORS TAKE YOU THEIR WAY.", TERM
hi_txt: .byte   "HIGH SCORE ", TERM
name_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_ROW, NAME_ROW, TC_COL, 24, RV_ON, TERM
rvoff_txt:
        .byte   RV_OFF, TERM
air_txt:.byte   TC_ATTR, ATTR_TEXT, TC_ROW, AIR_ROW, TC_COL, 0, "AIR ", TERM
status_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_ROW, 23, TC_COL, 0, "SCORE ", TERM
hi2_txt:.byte   "   HIGH ", TERM
lives_txt:
        .byte   "   LIVES ", TERM
room_txt:
        .byte   "   ROOM ", TERM
allclear_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS
        .byte   TC_ROW, 10, TC_COL, 25, "EVERY ROOM CLEARED. ROUND AGAIN!", TERM
paused_txt:
        .byte   RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   "        ", TERM
over_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 7, TC_COL, 31, RV_ON, "                  "
        .byte   TC_ROW, 8, TC_COL, 31, "    GAME  OVER    "
        .byte   TC_ROW, 9, TC_COL, 31, "                  "
        .byte   TC_ROW, 10, TC_COL, 31, " SPACE/A: AGAIN   "
        .byte   TC_ROW, 11, TC_COL, 31, " Q: TITLE         "
        .byte   TC_ROW, 12, TC_COL, 31, "                  ", RV_OFF, TERM
bye_txt:.byte   TC_ATTR, ATTR_TEXT, TC_CLS, TC_CURSOR, '_', $1B, "[?7h", TERM
nospr_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS
        .byte   TC_ROW, 8, TC_COL, 12, "MINER MOS NEEDS THE TERMINAL'S SPRITE LAYER (CODE 1C)."
        .byte   TC_ROW, 10, TC_COL, 12, "THE TERMINAL DIDN'T ANSWER: LOAD THE FIRMWARE WITH SPRITES."
        .byte   TC_ROW, 13, TC_COL, 12, "PRESS A KEY.", TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM
start_txt:
        .byte   TC_ROW, 23, TC_COL, 13, "SPACE OR START: PLAY   G: KEYBOARD / GAMEPAD   M: SOUND   Q: QUIT", TERM

; ============================================================================
; variables
; ============================================================================
        .segment "BSS"
bss_start:
ctrl:       .res 1
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed
rng:        .res 2
attr:       .res 1
nbytes:     .res 2              ; bytes sent this frame
esc_st:     .res 1
quit:       .res 1
frame:      .res 1
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
lives:      .res 1
room:       .res 1
hud_dirty:  .res 1
in_d:       .res 1              ; this frame's controls: -1 / 0 / 1
in_j:       .res 1              ;   jump
mv_dir:     .res 1
mv_hold:    .res 1
jhold:      .res 1
rp_on:      .res 1              ; IDENTIFY sent: S P 1 are its answer
rp_got:     .res 1              ; ... and it came
rp_t:       .res 1
air:        .res 1              ; units of air left
air_t:      .res 1
keys_left:  .res 1
p_x:        .res 1              ; the portal
p_y:        .res 1
w_x:        .res 1              ; Willy: his top left
w_y:        .res 1
w_mode:     .res 1              ;   ST_*
w_jt:       .res 1              ;   frames into a jump
w_jdx:      .res 1              ;   a jump's way across
w_ytop:     .res 1              ;   the highest he has been since he stood
w_face:     .res 1              ;   1: left
w_anim:     .res 1
w_crt:      .res 1              ;   frames on a crumbling floor
w_dead:     .res 1
w_d:        .res 1
w_j:        .res 1
w_dy:       .res 1
ng:         .res 1              ; the guardians
g_kind:     .res MAXG
g_axis:     .res MAXG
g_x:        .res MAXG
g_y:        .res MAXG
g_lo:       .res MAXG
g_hi:       .res MAXG
g_slow:     .res MAXG
g_dir:      .res MAXG
g_t:        .res MAXG
des_on:     .res NSLOT          ; the slots as they should be ...
des_n:      .res NSLOT
des_x:      .res NSLOT
des_y:      .res NSLOT
des_f:      .res NSLOT
sl_on:      .res NSLOT          ; ... and as the terminal shows them
sl_n:       .res NSLOT
sl_x:       .res NSLOT
sl_y:       .res NSLOT
sl_f:       .res NSLOT
hs_i:       .res 1
src:        .res 2
tc:         .res 1              ; a tile: column, row, its address
tr:         .res 1
tile_adr:   .res 2
c0:         .res 1              ; Willy's first and last columns
c1:         .res 1
dr_r:       .res 1
rowbuf:     .res COLS * 2
map:        .res NTILE          ; the room's tiles
tmp:        .res 2
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
bss_end:
