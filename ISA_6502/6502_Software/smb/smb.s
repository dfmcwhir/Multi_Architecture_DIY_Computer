; ============================================================================
; smb.s - SUPER MOS BROS., a side-scrolling platform game for the 6502 SBC
;
; Runs from the monitor at $0500 and draws on the PIC32 terminal in its
; control code mode (setup item J), terminal firmware v1.4 or later.
;
;   build:  make.bat  (or make)     needs ../sbc_api.inc (CLOCK_MHZ)
;   run:    L SMB 0500   then   R
;
; Header (patchable from the monitor):
;   $0500  JMP start
;   $0503  frame time in ms (default 50; real ms at any clock)
;   $0504  controls at start: 0 keyboard, 1 gamepad (default)
;   $0505  0: the terminal scrolls the view (code 16 in a scroll region,
;          firmware 1.4 with sideways scrolling); 1: redraw it instead
;   $0506  sound at start: 0 on, 1 off (M switches)
;
; Sound (SMB.BIN; SMBSW.BIN has no room for it): music and effects on the
; AY-3-8910 card at $7F22/$7F23, through ../ay/sfx.s, timed by the VIA's
; timer 2.  The tunes and effects are in sound.py (-> smb_sound.inc).
; Without the card the game is just silent.
;
; Keys:    D / A or Right / Left   walk that way (press again: run)
;          S or Down  stop    W, Space or Up  jump    P pause   Q quit
;          M  sound on / off
; Gamepad: left / right walk, B (held) run, A jump (hold it to jump higher),
;          Start pause
;
; The world is a map of 8 x 8 pixel tiles, 11 high, up to 255 wide.  A tile
; is 4 x 2 block graphics characters.  The view is text rows 2-23 (80 x 22
; characters, 160 x 88 pixels); row 0 is the status line.
;
; The view is kept in RAM (wc: a page a text row, indexed by the world
; column & 255, so scrolling only fills in the columns coming into view),
; and so is what the terminal shows (sh, indexed the same way).  They are
; compared and only the characters that differ are sent, runs of the same
; character with the terminal's repeat count.  The view scrolls a character
; at a time: the terminal moves it (code 16, in the scroll region of text
; rows 3-24), so only the new column on the right, the cells under the
; sprites (this frame and the last) and tiles that changed are compared.
; Sprites are stored for both pixel positions across a cell and shifted
; down and mirrored as they are drawn, with a mask (gen.py).
;
; Positions are 16.8 fixed point pixels (x) and signed 8.8 (y), speeds 8.8.
; No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 50            ; ms per frame

; ---- terminal --------------------------------------------------------------------
TC_CURSOR       = $02
TC_CLS          = $0C
TC_COL          = $0E
TC_ROW          = $0F
TC_ATTR         = $18
TC_LIT          = $1A
TC_SCROLL       = $16           ; scroll left (a character; the scroll region)
TC_TILE         = $0B           ; n: draw terminal tile n (19 SET TILE: SMBSPR.SMB)
ATTR_TEXT       = $00
ATTR_GFX        = $80
TERM            = $FF
.define RV_ON   $1B, '[', '7', 'm'
.define RV_OFF  $1B, '[', '2', '7', 'm'

; ---- the view ----------------------------------------------------------------------
COLS            = 80
PROWS           = 22            ; text rows of the view
PF_ROW          = 2             ; ... starting on this text row
MAPROWS         = 11
VIEW_H          = 88            ; pixels

; ---- objects -----------------------------------------------------------------------
NOBJ            = 10
O_MOS           = 0
O_FIRST         = 1             ; 1-6: enemies, shells, mushrooms, the dragon, its fire
O_LAST          = 6
O_COIN          = 7             ; a coin popping out of a block
O_FIRE          = 8             ; 8-9: MOS's electrons
K_NONE          = 0
K_MOS           = 1
K_BUG           = 2             ; an AND gate
K_FLAT          = 3             ; a squashed one (for a moment)
K_SHELLY        = 4             ; an OR gate
K_SHELL         = 5             ; ... pulled in
K_MUSH          = 6
K_COIN          = 7
K_ONEUP         = 8             ; the mushroom from a hidden block
K_FLOWER        = 9
K_FIRE          = 10            ; an electron
K_DRAGON        = 11            ; KIL
K_BREATH        = 12            ; its fire
K_OC            = 13            ; the overclock device
K_FISH          = 14            ; a gate swimming on its side (liquid cooling)
K_FAN           = 15            ; a flying fan
K_CLOUD         = 16            ; the cloud: it throws gates down
K_PRINCESS      = 17            ; Princess Graphics Card
REVIVE          = 160           ; frames before a still shell walks again
FAN_TOP         = 12            ; how high the high fans fly
FISH_V          = $0100         ; how fast the fish swim

; MOS's states
MS_PLAY         = 0
MS_FLAG         = 1             ; sliding down the pole
MS_WALK         = 2             ; walking to the castle
MS_IN           = 3             ; in the castle: time bonus
MS_DEAD         = 4
MS_RESET        = 5             ; pressed RESET: the bridge falls
MS_PIPE         = 6             ; going down a pipe
MS_RESCUE       = 7             ; found the princess

; ---- physics (8.8 pixels per frame) -------------------------------------------------
WALK_MAX        = $01C0
RUN_MAX         = $0300
ACCEL           = $0020
DECEL           = $0020
SKID            = $0048
JUMP_V          = $0600         ; + speed / 8
GRAV_HOLD       = $0080         ; rising with jump held
GRAV            = $0180
MAX_FALL        = $0600
STOMP_V         = $0480
BUG_V           = $00A0
SHELL_V         = $0300
MUSH_V          = $00C0
OBJ_GRAV        = $0100
INVULN          = 60            ; frames after shrinking
FIRE_V          = $0380         ; electrons: across
FIRE_BOUNCE     = $0280         ; ... up, when they bounce
FIRE_GRAV       = $0060
DRAGON_HP       = 5
OC_TIME         = 200           ; frames of overclock (10 s)
SWIM_V          = $0180         ; under the coolant: a stroke
GRAV_W          = $0018
MAX_FALL_W      = $0100
WATER_MAX       = $0100         ; ... and the most speed across
TIME_TICK       = 9             ; frames per unit of the timer (about 0.4 s)

; SOFT_SPRITES = 1 builds SMBSW.BIN: the 6502 draws the sprites itself, for a
; terminal without the sprite layer.  The default (0) builds SMB.BIN: the
; pictures are sent to the terminal from SMBSPR.SMB at start and the terminal
; draws them (control code 1C), which frees about 3.6 KB here.
.ifndef SOFT_SPRITES
SOFT_SPRITES    = 0
.endif
; SOUND = 0 builds without the sound (SMBSW.BIN has no room for it)
.ifndef SOUND
SOUND           = !SOFT_SPRITES
.endif
; UNC_TILE = 1 (ca65 -D): hide the terminal's sprites over a tile before it changes
; (for terminal firmware that left old pixels under a sprite; each HIDE
; outside HOLD waits for the vertical blank on the newer firmware, so 0)
.ifndef UNC_TILE
UNC_TILE        = 0
.endif
UNC_TILES       = UNC_TILE .and (.not SOFT_SPRITES)
TC_SPR          = $1C           ; the terminal's sprite layer: 1C command args
SPR_PLACE       = 2
SPR_MOVE        = 3
SPR_PIC         = 4
SPR_FLAGS       = 5
SPR_HIDE        = 6
SPR_HIDEALL     = 7
SPR_HOLD        = 9
SPR_SHOW        = 10
SPR_CLIP        = 11
SPR_IDENT       = 12
SPR_STATUS      = 13            ; (newer firmware: lost bytes, buffer peak)

; ============================================================================
        .segment "RODATA"
        .include "smb_data.inc"
.if SOUND
        .include "smb_sound.inc"     ; the music and effects (sound.py)
.endif

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
noscroll:.byte  0               ; 0: the terminal scrolls the view (16, firmware
                                ;    with scroll regions); 1: redraw it instead
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0

.if SOUND
SFX_VARS        = $0100         ; the engine's 123 bytes: the bottom of the stack
                                ; page (the game's stack stays above $01E0)
        .include "ay/sfx.s"     ; the sound engine (AY-3-8910 card)
.endif

; ----------------------------------------------------------------------------
; I/O helpers
; ----------------------------------------------------------------------------
.if SOFT_SPRITES
getc            = SBC_CHRIN     ; carry set = key in A
.else
; carry set = key in A.  After IDENTIFY (1C 0C) the terminal answers S P 1:
; those are taken as its reply (rp_got), not as keys, until the 1 comes or
; the next IDENTIFY.  (A reply character can be missed: any one will do.)
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
.endif

; send A (counts the bytes, for the frame timing).  Preserves A, X, Y.
putc:   inc     nbytes
        bne     @p
        inc     nbytes+1
@p:
.if SOUND
        jsr     sfx_poll        ; (the sound goes on while drawing)
.endif
        jmp     SBC_CHROUT

; cursor to column X, row Y.  Preserves X and Y.
gotoxy: lda     #TC_ROW
        jsr     putc
        tya
        jsr     putc
setcol: lda     #TC_COL
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

; repeat every character A times from now on (1..15), block graphics
set_rep:sta     cur_rep
        cmp     #2
        bcc     @one
        asl
        asl
        asl
        ora     #ATTR_GFX
        jmp     setattr         ; (sends it only if it changes)
@one:   lda     #ATTR_GFX
        jmp     setattr

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

; print A as two hex digits
prhex:  pha
        lsr
        lsr
        lsr
        lsr
        jsr     @d
        pla
        and     #$0F
@d:     cmp     #10
        bcc     @n
        adc     #'A' - '0' - 10 - 1
@n:     adc     #'0'
        jmp     putc

; print A (0-99) in decimal, without a leading zero
prdec:  ldx     #'0'
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     pha
        cpx     #'0'
        beq     @one
        txa
        jsr     putc
@one:   pla
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
@o:
.if SOUND
        jsr     sfx_poll        ; (and while waiting)
.endif
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
.if SOUND
        jsr     sfx_poll
.endif
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
.if SOUND
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
.endif
.if !SOFT_SPRITES
        jsr     spr_setup
.endif

title:
.if SOUND
        jsr     sfx_off
.endif
.if !SOFT_SPRITES
        lda     #0              ; (S P 1 are keys again)
        sta     rp_on
.endif
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
.if SOFT_SPRITES
        jsr     gfx_mode        ; the banner
        lda     #<banner
        sta     @b+1
        lda     #>banner
        sta     @b+2
@line:  jsr     @next           ; text row (0: the end)
        beq     @txt
        tay
        jsr     @next           ; first column
        tax
        jsr     gotoxy
        jsr     @next           ; how many
        sta     tmp
@ch:    jsr     @next
        jsr     putblk
        dec     tmp
        bne     @ch
        beq     @line
@next:
@b:     lda     $FFFF
        inc     @b+1
        bne     @nr
        inc     @b+2
@nr:    cmp     #0
        rts
.else
        jsr     gfx_mode        ; the banner: two terminal tiles (SMBSPR.SMB
        ldx     #BAN0_COL       ; defined them)
        ldy     #BAN0_ROW
        jsr     gotoxy
        lda     #TC_TILE
        jsr     putc
        lda     #BAN0_SLOT
        jsr     putc
        ldx     #BAN1_COL
        ldy     #BAN1_ROW
        jsr     gotoxy
        lda     #TC_TILE
        jsr     putc
        lda     #BAN1_SLOT
        jsr     putc
.endif
@txt:   lda     #<title_txt
        ldy     #>title_txt
        jsr     print
        jsr     txt_mode
        ldx     #33
        ldy     #18
        jsr     gotoxy
        lda     #<hi_txt
        ldy     #>hi_txt
        jsr     print
        lda     hiscore+2
        jsr     prhex
        lda     hiscore+1
        jsr     prhex
        lda     hiscore
        jsr     prhex
        jsr     show_ctrl
        jsr     read_pad
        jsr     flush_in
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @notq
        jmp     exit_game
@notq:
.if SOUND
        cmp     #'M'            ; sound on / off
        bne     @notm
        jsr     toggle_sound
        jmp     @wait
@notm:
.endif
        cmp     #'G'
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
.if SOUND
        jsr     sfx_off
.endif
        lda     #<bye_txt
        ldy     #>bye_txt
        jsr     print
        jmp     SBC_MENU

; ============================================================================
; a game
; ============================================================================
new_game:
        lda     #0
.if !SOFT_SPRITES
        sta     rp_miss
.endif
        sta     score
        sta     score+1
        sta     score+2
        sta     bits
        sta     bytes
        sta     lvl
        sta     big
        sta     fire
        lda     #1
        sta     world
        sta     wsrc
        lda     #3
        sta     lives

; ---- a level: "WORLD 1-1  x 3" for a moment, then play -------------------------------
start_level:
        jsr     get_world       ; (worlds 2 and up: from the USB drive)
        bcc     @ok
        lda     wsrc            ; (no 1-1 at all: a word, and back to the title)
        cmp     #1
        bne     @nd
        lda     lvl
        bne     @nd
        lda     #<noworld_txt
        ldy     #>noworld_txt
        jsr     print
        lda     #100
        jsr     delay_long
        jmp     title
@nd:    lda     #<nodisk_txt    ; no more worlds: around again
        ldy     #>nodisk_txt
        jsr     print
        lda     wsrc
        ora     #'0'
        jsr     putc
        lda     #<nodisk2_txt
        ldy     #>nodisk2_txt
        jsr     print
        lda     #60
        jsr     delay_long
        lda     #1
        sta     wsrc
        lda     #0
        sta     lvl
        jmp     start_level
@ok:    lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        ldx     #35
        ldy     #9
        jsr     gotoxy
        lda     #<world_txt
        ldy     #>world_txt
        jsr     print
        jsr     pr_world
        ldx     #36
        ldy     #12
        jsr     gotoxy
        lda     #<lives_txt
        ldy     #>lives_txt
        jsr     print
        lda     lives
        jsr     prdec
        jsr     load_level
        lda     #30
        jsr     delay_long
        jsr     new_screen
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        lda     lv_flags        ; a castle: a word about KIL
        and     #1
        beq     @nk
        lda     #<kil_txt
        ldy     #>kil_txt
        jsr     print
@nk:    lda     #1
        sta     hud_dirty
        sta     full
.if SOUND
        jsr     sfx_off
        jsr     music_level
.endif

; ---- the frame loop --------------------------------------------------------------
game_loop:
        lda     #0
        sta     nbytes
        sta     nbytes+1
        sta     ncells
        sta     ncmp
        sta     ncmp+1
        sta     nrows_seen
        sta     scrolled
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:
.if !SOFT_SPRITES
        jsr     heal_tick       ; tiles changed a while ago: send them again
.endif
        jsr     mos_update
        jsr     obj_update
        jsr     fire_update
        jsr     obj_collide
        jsr     camera
        jsr     spawn_enemies
        jsr     clock
        jsr     render
        jsr     hud_update
.if !SOFT_SPRITES
        jsr     ask_send        ; the terminal answers when it has drawn it all
.endif
        jsr     pace
        inc     frame
        lda     mstate          ; the end of a life, or of the level?
        cmp     #MS_DEAD
        bne     @2
        lda     mtimer
        cmp     #75
        bcc     game_loop
        jmp     life_lost
@2:     cmp     #MS_RESCUE
        bne     @3
        lda     mtimer
        cmp     #30
        bcs     *+5
        jmp     game_loop
        jmp     the_end
@3:     cmp     #MS_IN
        beq     *+5
        jmp     game_loop
        lda     mtimer
        cmp     #20
        bcs     *+5
        jmp     game_loop
        jmp     level_done

; Princess Graphics Card: the end of the game
the_end:
.if SOUND
        jsr     fanfare
.endif
        lda     #<end_txt
        ldy     #>end_txt
        jsr     print
        lda     #100
        jsr     delay_long
        jmp     game_over

life_lost:
        lda     #0
        sta     big
        sta     fire
        dec     lives
        bne     @more
        lda     #1
        sta     hud_dirty
        jsr     hud_update
        jmp     game_over
@more:  jmp     start_level

level_done:
        inc     lvl
        lda     lv_flags        ; the last level of its world?
        and     #8
        beq     @n
.if SOUND
        jsr     fanfare
.endif
        lda     #<castle_txt    ; the end of a world
        ldy     #>castle_txt
        jsr     print
        lda     #80
        jsr     delay_long
        lda     #0
        sta     lvl
        inc     world
        inc     wsrc
@n:     jmp     start_level

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
@nohi:
.if SOUND
        jsr     sfx_off
        lda     #SND_GOVERA
        jsr     snd
        lda     #SND_GOVERB
        jsr     snd
.endif
.if !SOFT_SPRITES
        lda     #<hideall_txt   ; (the sprites off the box)
        ldy     #>hideall_txt
        jsr     print
        jsr     spr_forget
.endif
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print
.if !SOFT_SPRITES
        jsr     st_show         ; the terminal's own count of lost bytes
.endif
        lda     #20
        jsr     delay_long
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @nq
        jmp     title
@nq:
.if SOUND
        cmp     #'M'
        bne     @nm
        jsr     toggle_sound
        jmp     @wait
@nm:
.endif
        cmp     #' '
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game

; print the world and level: "1-1"
pr_world:
        lda     world
        jsr     prdec
        lda     #'-'
        jsr     putc
        lda     lvl
        clc
        adc     #1
        jmp     prdec

; clear the screen and forget what it showed
new_screen:
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        ldx     #0
        lda     #0
@c:     .repeat PROWS, K
        sta     sh + K * 256,x
        .endrepeat
        inx
        bne     @c
        ldx     #PROWS-1
@d:     lda     #$FF
        sta     dmin,x
        lda     #1
        sta     sh_empty,x
        lda     #0
        sta     dmax,x
        dex
        bpl     @d
        sta     nrect
        lda     #<region_txt    ; the view (text rows 3-24) scrolls by itself
        ldy     #>region_txt
.if SOFT_SPRITES
        jmp     print
.else
        jsr     print
        lda     #<clip_txt      ; (the clear hid the sprites; they stay in the view)
        ldy     #>clip_txt
        jsr     print
spr_forget:
        lda     #1              ; (nothing to wait for before the first frame)
        sta     rp_got
        ldx     #HEAL_N-1
        lda     #0
@hl:    sta     hl_t,x
        dex
        bpl     @hl
        ldx     #NOBJ-1         ; none showing
        lda     #0
.if UNC_TILES
        sta     tch_n
.endif
@f:     sta     sl_on,x
        dex
        bpl     @f
        rts
.endif

; ---- the levels -------------------------------------------------------------------
; every world is a file, WORLDn.SMB (n: wsrc), loaded with SBC_LOAD into wc
; (free until the level starts) each time one of its levels starts.
; Carry set if it can't be had (no SBC_LOAD in the ROM, no file, not a world,
; no level lvl in it).
get_world:
        lda     wsrc
        cmp     #10
        bcs     @fail
        lda     SBC_LOAD        ; a JMP there: the ROM has SBC_LOAD
        cmp     #$4C
        bne     @fail
        lda     wsrc
        ora     #'0'
        sta     load_name+5
        lda     #<load_blk
        ldy     #>load_blk
        jsr     SBC_LOAD
        bcs     @fail
        lda     wc              ; "SM", version 2
        cmp     #'S'
        bne     @fail
        lda     wc+1
        cmp     #'M'
        bne     @fail
        lda     wc+2
        cmp     #2
        bne     @fail
        lda     lvl             ; (levels in it: wc+3)
        cmp     wc+3
        bcs     @fail
        rts
@fail:  sec
        rts

; ---- load the level (in wc): the map, MOS, the timer, no objects ---------------------
load_level:
        ldx     #0              ; an empty map
        txa
@clr:   .repeat MAPROWS, K
        sta     map + K * 256,x
        .endrepeat
        inx
        bne     @clr
        lda     lvl             ; the level: at wc + its offset (wc+4 + lvl * 2)
        asl
        tay
        clc
        lda     wc+4,y
        adc     #<wc
        sta     @rd+1
        lda     wc+5,y
        adc     #>wc
        sta     @rd+2
        ldx     #0              ; width, start, time, flags, room, exit pipe
@in:    jsr     @get
        sta     lv_w,x
        inx
        cpx     #8
        bne     @in
        lda     #0
        sta     tmp3            ; the rows, unpacked: (count, tile) ... 0
@row:   lda     tmp3
        clc
        adc     #>map
        sta     @wr+2
        ldx     #0              ; map column
@run:   jsr     @get
        beq     @nrow
        tay                     ; count
        jsr     @get            ; tile
@wr:    sta     map,x
        inx
        dey
        bne     @wr
        beq     @run
@nrow:  inc     tmp3
        lda     tmp3
        cmp     #MAPROWS
        bne     @row
        ldx     #0              ; then the enemies: copied out (a world from
@en:    jsr     @get            ; the disk is in wc, which the view will use)
        sta     en_buf,x
        cmp     #$FF
        beq     @ene
        inx
        bne     @en
        dex
        lda     #$FF
        sta     en_buf,x
@ene:   lda     #0
        sta     en_i
        ; the furthest the view goes: width * 4 - 80 characters
        lda     #0
        sta     max_sc+1
        lda     lv_w
        asl
        rol     max_sc+1
        asl
        rol     max_sc+1
        sec
        sbc     #COLS
        sta     max_sc
        lda     max_sc+1
        sbc     #0
        sta     max_sc+1
        lda     #0
        sta     scroll
        sta     scroll+1
        sta     sc2
        sta     sc2+1
        sta     time_div
        sta     inv_t
        sta     mstate
        sta     mtimer
        sta     facing
        sta     kdir
        sta     krun
        sta     khold
        sta     jump_buf
        sta     fire_req
        sta     quit
        sta     dr_flash
        sta     in_room
        sta     oc_t
        sta     sw_t
        sta     duck
        sta     br_w
        ldx     #NOBJ-1
@o:     sta     o_kind,x
        dex
        bpl     @o
        jsr     clear_obj0
        lda     #K_MOS
        sta     o_kind
        lda     lv_sx           ; start: tile x * 8, tile y * 8 (bottom row of MOS)
        sta     o_xl
        lda     #0
        asl     o_xl
        rol
        asl     o_xl
        rol
        asl     o_xl
        rol
        sta     o_xh
        lda     lv_sy
        asl
        asl
        asl
        ldx     big
        beq     @sm
        sec
        sbc     #8
@sm:    sta     o_y
        lda     lv_time
        sta     time
        lda     lv_time+1
        sta     time+1
        lda     #1
        sta     onground
        rts
@get:
@rd:    lda     $FFFF
        inc     @rd+1
        bne     @g
        inc     @rd+2
@g:     cmp     #0
        rts

; clear object X's position and speed (keeps its kind)
clear_obj0:
        ldx     #0
clear_obj:
        lda     #0
        sta     o_xf,x
        sta     o_xl,x
        sta     o_xh,x
        sta     o_yf,x
        sta     o_y,x
        sta     o_vxl,x
        sta     o_vxh,x
        sta     o_vyl,x
        sta     o_vyh,x
        sta     o_t,x
        sta     o_r,x
        rts

; wait out the rest of the frame: about (speed - what the frame took) ms.
; The frame took roughly: the bytes sent at 115200 baud (87 us each) plus
; the 6502's work / CLOCK_MHZ.  The work, measured in the emulator
; (test/fit.py), in ms at 1 MHz: about 6 + 0.093 a byte sent + 0.03 a
; character compared + 0.48 a sprite cell + 5 if the view scrolled (16 when
; it is redrawn instead of scrolled by the terminal).
pace:   lda     nbytes          ; tmp = bytes / 8 (at most 255)
        sta     tmp
        lda     nbytes+1
        sta     tmp+1
        ldx     #3
@s:     lsr     tmp+1
        ror     tmp
        dex
        bne     @s
        lda     tmp+1
        bne     @none
        lda     tmp             ; bytes / 8 * 0.75
        lsr
        sta     used
        lsr
        clc
        adc     used
        sta     used
        lda     ncmp+1          ; + compared / 32 (/ 16 for SMB.BIN)
        sta     tmp2
        lda     ncmp
        ldx     #PACE_CMP
@c:     lsr     tmp2
        ror
        dex
        bne     @c
        ldx     tmp2
        bne     @none
        clc
        adc     used
        bcs     @none
        sta     used
        lda     ncells          ; + cells * 0.5
        lsr
        clc
        adc     used
        bcs     @none
        ldx     scrolled        ; + a scroll: 5 (16 redrawing), + 6
        beq     @b
        ldx     noscroll
        beq     @hw
        adc     #11
        bcs     @none
@hw:    adc     #PACE_SCROLL
        bcs     @none
@b:     adc     #PACE_BASE
        bcs     @none
.if CLOCK_MHZ > 1
        ldx     #CLOCK_MHZ
        jsr     div_ax          ; / the clock
.endif
        sta     used
        lda     tmp             ; serial: bytes * 87 us = bytes / 8 * 0.7
        lsr                     ;   ~ bytes / 8 * (1/2 + 1/4)
        sta     tmp2
        lsr
        adc     tmp2
        adc     used
        bcs     @none
        sta     used
        lda     speed           ; the rest of the frame time
        sec
        sbc     used
        bcc     @none
        beq     @none
        jmp     delay_ms
@none:  rts

; the timing model's figures (test/fit.py), at 1 MHz
.if SOFT_SPRITES
PACE_CMP        = 5             ; compared characters: / 32
PACE_SCROLL     = 5             ; a scroll: ms
PACE_BASE       = 6             ; ms
.else
PACE_CMP        = 4             ; (the terminal draws the sprites: less to do
PACE_SCROLL     = 10            ;  each frame, but more per character compared)
PACE_BASE       = 4
.endif

; A = A / X (unsigned)
div_ax: stx     tmp4
        ldx     #0
@l:     cmp     tmp4
        bcc     @d
        sbc     tmp4
        inx
        bne     @l
@d:     txa
        rts

; ============================================================================
; input
; ============================================================================
; in_dir: -1 / 0 / 1, in_run, hold (jump held), jump_buf (frames a jump
; press waits for MOS to be on the ground)
read_input:
        lda     ctrl
        beq     @keys
        jsr     read_pad
        lda     #0
        sta     in_dir
        lda     pad
        and     #PAD_RIGHT
        beq     @l
        inc     in_dir
@l:     lda     pad
        and     #PAD_LEFT
        beq     @b
        dec     in_dir
@b:     lda     pad
        and     #PAD_DOWN
        sta     in_down
        lda     pad
        and     #PAD_B
        sta     in_run
        lda     pad
        and     #PAD_A
        sta     hold
        lda     padnew
        and     #PAD_A
        beq     @f
        lda     #JUMP_BUF
        sta     jump_buf
@f:     lda     padnew          ; B pressed: an electron (held: run)
        and     #PAD_B
        beq     @st
        sta     fire_req
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:  jsr     getc
        bcc     @held
        jsr     handle_key
        jmp     @keys
@held:  lda     ctrl
        bne     @done
        lda     kdir            ; keyboard: the direction stays until changed
        sta     in_dir
        lda     krun
        sta     in_run
        lda     #0
        sta     hold
        sta     in_down
        lda     kduck           ; S / down: duck for a while (key repeat
        beq     @kh             ; keeps it going while held)
        dec     kduck
        inc     in_down
@kh:    lda     #0
        lda     khold           ; a jump key "holds" the jump for a while
        beq     @done
        dec     khold
        inc     hold
@done:  rts
JUMP_BUF        = 4
KEY_HOLD        = 12
KEY_DUCK        = 15

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
        ldx     ctrl
        bne     @r0
        cmp     #'A'
        beq     @jump
        cmp     #'B'
        beq     @stop
        cmp     #'C'
        beq     @right
        cmp     #'D'
        beq     @left
@r0:    rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
.if SOUND
        cmp     #'M'
        beq     @mute
.endif
        ldx     ctrl            ; gamepad mode: the rest come from the pad
        bne     @r0
        cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #'W'
        beq     @jump
        cmp     #' '
        beq     @jump
        cmp     #'S'
        beq     @stop
        cmp     #'F'
        beq     @fire
        cmp     #'E'
        beq     @fire
        rts
@fire:  sta     fire_req
        rts
@right: lda     #1
        bne     @dir
@left:  lda     #$FF
@dir:   cmp     kdir            ; the same way again: run
        beq     @run
        sta     kdir
        lda     #0
        sta     krun
        rts
@run:   lda     #1
        sta     krun
        rts
@stop:  lda     #0
        sta     kdir
        sta     krun
        lda     #KEY_DUCK
        sta     kduck
        rts
@jump:  lda     #JUMP_BUF
        sta     jump_buf
        lda     #KEY_HOLD
        sta     khold
        rts
@pause: jmp     pause
.if SOUND
@mute:  jmp     toggle_sound
.endif
@quit:  lda     #1
        sta     quit
        rts

pause:
.if SOUND
        jsr     sfx_hush        ; (quiet while paused)
.endif
        jsr     txt_mode
        ldx     #70
        ldy     #0
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
        ldy     #0
        jsr     gotoxy
        lda     #<unpaused_txt
        ldy     #>unpaused_txt
        jmp     print

; ============================================================================
; the map
; ============================================================================
; point (object X's position + A across, + Y down) -> ptx, pty.  Preserves X.
set_pt: clc
        adc     o_xl,x
        sta     ptx
        lda     o_xh,x
        adc     #0
        sta     ptx+1
        tya
        clc
        adc     o_y,x
        sta     pty
        rts

; the tile at ptx, pty: A = its code (number * 4), carry set if solid.
; htc, htr = its column and row.  Above or below the map: empty; past the
; end: solid.  Preserves X.
solid_at:
        lda     pty
        cmp     #VIEW_H         ; (negative: above)
        bcs     @out
        lsr
        lsr
        lsr
        sta     htr
        clc
        adc     #>map
        sta     @m+2
        lda     ptx+1           ; column = ptx / 8
        sta     tcol
        lda     ptx
        lsr     tcol
        ror
        lsr     tcol
        ror
        lsr     tcol
        ror
        sta     htc
        ldy     tcol
        bne     @wall
        cmp     lv_w
        bcs     @wall
        tay
@m:     lda     map,y
        tay
        lda     tile_solid,y
        cmp     #1
        tya
        rts
@out:   lda     #$FF
        sta     htr
        lda     #0
        clc
        rts
@wall:  lda     #T_HARD
        sec
        rts

; object X's tile at (A across, Y down): A = code
tile_at:jsr     set_pt
        jmp     solid_at

; put tile A at htc, htr and show it
set_tile:
.if !SOFT_SPRITES
        jsr     heal_add
.endif
        pha
        lda     htr
        clc
        adc     #>map
        sta     @w+2
        ldy     htc
        pla
@w:     sta     map,y
        ; fall through
; the tile at htc, htr changed: draw it into the view if it is in view
tile_changed:
        lda     #0              ; first column on the screen = htc * 4 - scroll
        sta     tcol
        lda     htc
        asl
        rol     tcol
        asl
        rol     tcol
        sta     tc_w            ; (its place in a row of wc)
        sec
        sbc     scroll
        sta     tc_c
        lda     tcol
        sbc     scroll+1
        beq     @in             ; 0..255
        cmp     #$FF            ; -3..-1 only
        bne     @r
        lda     tc_c
        cmp     #$FD
        bcs     @go
@r:     rts
@in:    lda     tc_c
        cmp     #COLS
        bcs     @r
@go:
.if UNC_TILES
        jsr     note_tile       ; (for the terminal's sprites over it)
.endif
        lda     htr             ; the two text rows
        asl
        sta     tc_row
        clc
        adc     #>wc
        sta     @t+2
        adc     #1
        sta     @b+2
        lda     htr
        clc
        adc     #>map
        sta     @m+2
        ldy     htc
@m:     lda     map,y
        sta     tc_code
        lda     #4
        sta     tc_n
        ldx     tc_w
@cell:  ldy     tc_code
        lda     tile_top,y
@t:     sta     wc,x
        lda     tile_bot,y
@b:     sta     wc,x
        lda     tc_c
        cmp     #COLS           ; (also off the left: $FD-$FF)
        bcs     @skip
        ldy     tc_row
        jsr     mark1
        iny
        jsr     mark1
@skip:  inc     tc_code
        inc     tc_c
        inx
        dec     tc_n
        bne     @cell
        rts

; mark cell (column A, row Y) for comparing.  Preserves A, X, Y.
mark1:  cmp     dmin,y
        bcs     @n
        sta     dmin,y
@n:     cmp     dmax,y
        bcc     @x
        sta     dmax,y
@x:     rts

; ============================================================================
; MOS
; ============================================================================
mos_update:
        jsr     set_mh
        lda     mstate
        beq     m_play
        cmp     #MS_FLAG
        bne     @1
        jmp     m_flag
@1:     cmp     #MS_WALK
        bne     @2
        jmp     m_walk
@2:     cmp     #MS_IN
        bne     @3
        jmp     m_in
@3:     cmp     #MS_RESET
        bne     @4
        jmp     m_reset
@4:     cmp     #MS_PIPE
        bne     @5
        jmp     m_pipe
@5:     cmp     #MS_RESCUE
        bne     @6
        jmp     m_rescue
@6:     jmp     m_dead

m_play: lda     inv_t
        beq     @c
        dec     inv_t
@c:     lda     oc_t            ; overclocked: always running
        beq     @c2
        dec     oc_t
.if SOUND
        bne     @c1
        jsr     music_level     ; (over: the level's music again)
@c1:
.endif
        lda     #1
        sta     in_run
@c2:    jsr     pipe_check      ; down on a pipe into the bonus room?
        bcc     @c3
        rts
@c3:    jsr     duck_check
        lda     duck            ; ducking: no walking (he slides to a stop;
        beq     @cc             ;  he can jump, ducked)
        lda     #0
        sta     in_dir
        sta     in_run
@cc:    jsr     mos_control
        jsr     mos_jump
        jsr     mos_move
        lda     lv_flags        ; under the coolant: not above the top
        and     #2
        beq     @fr
        lda     o_y
        cmp     #4
        bcc     @top
        cmp     #$C0
        bcc     @fr
@top:   lda     #4
        sta     o_y
        lda     #0
        sta     o_vyl
        sta     o_vyh
@fr:    lda     fire_req        ; an electron?
        beq     @nf
        lda     #0
        sta     fire_req
        lda     fire
        beq     @nf
        jsr     throw_fire
@nf:    lda     o_y             ; down a pit?
        bmi     @t
        cmp     #VIEW_H + 8
        bcc     @t
        jmp     die
@t:     ; coins (two points down the middle)
        lda     #3
        ldy     #2
        jsr     coin_at
        lda     #3
        ldy     mh
        dey
        dey
        dey
        jsr     coin_at
        ; the flagpole (the right edge)
        lda     #6
        ldy     #2
        jsr     pole_at
        bcs     @r
        lda     #6
        ldy     mh
        dey
        dey
        jmp     pole_at
@r:     rts

coin_at:ldx     #O_MOS
        jsr     tile_at
        cmp     #T_COIN
        bne     @r
        lda     #T_EMPTY
        jsr     set_tile
        jsr     add_coin
@r:     rts

; touching the pole: slide down it
pole_at:ldx     #O_MOS
        jsr     tile_at
        cmp     #T_POLE
        beq     @grab
        cmp     #T_POLETOP
        beq     @grab
        cmp     #T_RESET
        bne     @no
        jmp     press_reset
@no:    clc
        rts
@grab:  jsr     unduck
.if SOUND
        jsr     music_stop
        lda     #SND_SLIDE
        jsr     snd
.endif
        lda     #MS_FLAG
        sta     mstate
        lda     #0
        sta     mtimer
        sta     facing
        jsr     stop_mos
        lda     htc             ; x = column * 8 - 3
        sta     pole_c
        jsr     col_x
        sec
        sbc     #3
        sta     o_xl
        bcs     @x
        dec     o_xh
@x:     ; points for the height: 80 - (y + h), in 8s
        lda     o_y
        clc
        adc     mh
        sta     tmp
        lda     #80
        sec
        sbc     tmp
        bcs     @p
        lda     #0
@p:     lsr
        lsr
        lsr
        cmp     #9
        bcc     @p2
        lda     #9
@p2:    tax
        lda     flag_pts_lo,x
        ldy     flag_pts_hi,x
        jsr     add_score
        ; find the flag in the 2 columns before the pole
        ldx     pole_c
        dex
        dex
        stx     htc
        ldy     #0
@f:     sty     htr
        jsr     map_get
        cmp     #T_FLAGL
        beq     @ff
        ldy     htr
        iny
        cpy     #MAPROWS
        bne     @f
        lda     #$FF            ; (none)
        bne     @fr
@ff:    lda     htr
@fr:    sta     flag_r
        sec
        rts

; A = the map at htc, htr.  Preserves X.
map_get:lda     htr
        clc
        adc     #>map
        sta     @m+2
        ldy     htc
@m:     lda     map,y
        rts

; o_xl/o_xh (MOS) = column htc... A = column A * 8 (low), o_xh = high
col_x:  ldy     #0
        sty     o_xh
        asl
        rol     o_xh
        asl
        rol     o_xh
        asl
        rol     o_xh
        sta     o_xl
        ldy     #0
        sty     o_xf
        rts

stop_mos:
        lda     #0
        sta     o_vxl
        sta     o_vxh
        sta     o_vyl
        sta     o_vyh
        sta     o_xf
        sta     o_yf
        rts

; ---- sliding down the pole, the flag coming down too ----------------------------
m_flag: inc     mtimer
        lda     mtimer          ; the flag: a row every 4 frames, down to row 8
        and     #3
        bne     @mos
        lda     flag_r
        cmp     #8
        bcs     @mos
        sta     htr
        lda     pole_c          ; (2 tiles: "65" "02")
        sta     htc
        dec     htc
        lda     #T_EMPTY
        jsr     set_tile
        dec     htc
        lda     #T_EMPTY
        jsr     set_tile
        inc     htr
        inc     flag_r
        lda     #T_FLAGL
        jsr     set_tile
        inc     htc
        lda     #T_FLAGR
        jsr     set_tile
@mos:   ldx     #O_MOS          ; MOS: 2 pixels a frame until his feet land
        lda     #1
        ldy     mh
        jsr     tile_at
        bcs     @down
        inc     o_y
        inc     o_y
        rts
@down:  lda     flag_r          ; both down (or no flag): off the pole
        cmp     #8
        bcc     @r
        lda     mtimer
        cmp     #40
        bcc     @r
        lda     #MS_WALK
        sta     mstate
.if SOUND
        lda     #SND_CLEARA     ; the level's done
        jsr     snd
        lda     #SND_CLEARB
        jsr     snd
.endif
        lda     o_xl            ; to the other side of the pole
        clc
        adc     #6
        sta     o_xl
        bcc     @r
        inc     o_xh
@r:     rts

; ---- walking into the castle ---------------------------------------------------
m_walk: lda     #1
        sta     in_dir
        lda     #0
        sta     in_run
        sta     hold
        sta     jump_buf
        jsr     mos_control
        jsr     mos_jump
        jsr     mos_move
        ldx     #O_MOS
        lda     #4
        ldy     mh
        dey
        dey
        jsr     tile_at
        cmp     #T_DOOR
        bne     @r
        lda     #MS_IN
        sta     mstate
        lda     #0
        sta     mtimer
@r:     rts

; ---- in the castle: the time left is counted into the score -----------------------
m_in:   jsr     bonus
        bcc     @r
        inc     mtimer
@r:     rts

; 3 counts of the time into the score (50 each); carry set when it's all in
bonus:
.if SOUND
        lda     time            ; (a tick for each 3 counts)
        ora     time+1
        beq     @nt
        lda     #SND_TICK
        jsr     snd
@nt:
.endif
        lda     #3
        sta     tmp3
@l:     lda     time
        ora     time+1
        beq     @done
        sed
        sec
        lda     time
        sbc     #1
        sta     time
        lda     time+1
        sbc     #0
        sta     time+1
        cld
        lda     #<50
        ldy     #>50
        jsr     add_score
        dec     tmp3
        bne     @l
        clc
        rts
@done:  sec
        rts

; ---- RESET: the bridge falls away, KIL with it --------------------------------------
press_reset:
        lda     br_w            ; (the last level: pressed once is enough)
        beq     @p
        clc
        rts
@p:     jsr     unduck
.if SOUND
        jsr     music_stop      ; (the castle's tune ends with KIL)
.endif
        lda     #MS_RESET
        sta     mstate
        lda     #0
        sta     mtimer
        sta     br_w
        jsr     stop_mos
        lda     #9              ; the bridge's end: just left of RESET, row 9
        sta     htr
        ldx     htc
        ldy     #4
@f:     dex
        stx     htc
        sty     tmp3
        jsr     map_get
        ldy     tmp3
        cmp     #T_BRIDGE
        beq     @ok
        dey
        bne     @f
        ldx     #0              ; (none)
@ok:    stx     br_c
        sec
        rts

m_reset:inc     mtimer
        lda     br_c            ; a bridge tile every 2 frames
        beq     @wait
        lda     mtimer
        and     #1
        bne     @r
        lda     br_c
        sta     htc
        lda     #9
        sta     htr
        jsr     map_get
        cmp     #T_BRIDGE
        bne     @end
        lda     #T_EMPTY
        jsr     set_tile
.if SOUND
        lda     #SND_CRUMBLE
        jsr     snd
.endif
        dec     br_c
        rts
@end:   lda     #0
        sta     br_c
        sta     mtimer
        lda     lv_flags        ; (the last level: on to the princess)
        and     #4
        beq     @e2
        lda     #MS_PLAY
        sta     mstate
        sta     br_w            ; (RESET done with)
        inc     br_w
@e2:    rts
@wait:  lda     mtimer          ; then the time bonus, and on
        cmp     #30
        bcc     @r
        dec     mtimer
        jsr     bonus
        bcc     @r
        inc     br_w
        lda     br_w
        cmp     #20
        bcc     @r
        lda     #MS_IN
        sta     mstate
        lda     #20
        sta     mtimer
@r:     rts

; ---- dead: a moment's pause, a hop, and down off the screen ------------------------
m_dead: inc     mtimer
        lda     mtimer
        cmp     #12
        bcc     @r
        bne     @fall
        lda     o_y             ; (fallen down a pit: no hop)
        bmi     @hop
        cmp     #VIEW_H
        bcs     @r
@hop:   lda     #<-$0500
        sta     o_vyl
        lda     #>-$0500
        sta     o_vyh
@fall:  lda     o_y
        bmi     @mv
        cmp     #VIEW_H + 12
        bcs     @r
@mv:    clc
        lda     o_yf
        adc     o_vyl
        sta     o_yf
        lda     o_y
        adc     o_vyh
        sta     o_y
        clc
        lda     o_vyl
        adc     #<(GRAV / 2)
        sta     o_vyl
        lda     o_vyh
        adc     #>(GRAV / 2)
        sta     o_vyh
@r:     rts

; lose a life: MOS dies
die:    lda     mstate
        cmp     #MS_DEAD
        beq     @r
        jsr     unduck
        lda     #MS_DEAD
        sta     mstate
.if SOUND
        jsr     music_stop
        lda     #SND_DIEA
        jsr     snd
        lda     #SND_DIEB
        jsr     snd
.endif
        lda     #0
        sta     mtimer
        jsr     stop_mos
        lda     #0
        sta     fire
        lda     big             ; (the small picture)
        beq     @s
        lda     o_y
        clc
        adc     #8
        sta     o_y
        lda     #0
        sta     big
        lda     #8
        sta     mh
@s:
@r:     rts

; ---- ducking --------------------------------------------------------------------
; MOS's height: 8 small, 16 big; ducking 5 and 8
set_mh: lda     big
        asl
        ora     duck
        tax
        lda     mh_tab,x
        sta     mh
        rts
; A = how much lower his top is when ducking: 3 small, 8 big
duck_d: lda     big
        beq     @s
        lda     #8
        rts
@s:     lda     #3
        rts

; down held on the ground: duck; let go (or jump): stand up if there's room
duck_check:
        lda     duck
        bne     @in
        lda     in_down
        beq     @r
        lda     onground
        beq     @r
        lda     #1
        sta     duck
        jsr     duck_d
        clc
        adc     o_y
        sta     o_y
        jmp     set_mh
@in:    lda     in_down         ; (still down: stays ducked, jumping too)
        bne     @r
@up:    jsr     duck_d          ; the head room: the new top, x + 2 and x + 5
        eor     #$FF
        clc
        adc     #1
        sta     tmp3
        tay
        ldx     #O_MOS
        lda     #2
        jsr     tile_at
        bcs     @r
        ldy     tmp3
        ldx     #O_MOS
        lda     #5
        jsr     tile_at
        bcs     @r
        jmp     unduck
@r:     rts
unduck: lda     duck            ; (stand up at once, room or not)
        beq     @r
        lda     #0
        sta     duck
        jsr     duck_d
        eor     #$FF
        sec
        adc     o_y
        sta     o_y
        jmp     set_mh
@r:     rts

; ---- running and jumping ---------------------------------------------------------
; speed from the controls: towards the top speed for walking or running
mos_control:
        lda     #<WALK_MAX
        sta     vmax
        lda     #>WALK_MAX
        sta     vmax+1
        lda     in_run
        beq     @w
        lda     #<RUN_MAX
        sta     vmax
        lda     #>RUN_MAX
        sta     vmax+1
@w:     lda     lv_flags        ; (swimming: slower)
        and     #2
        beq     @w2
        lda     #<WATER_MAX
        sta     vmax
        lda     #>WATER_MAX
        sta     vmax+1
@w2:    lda     in_dir
        bne     @go
        lda     onground        ; no direction: slow down on the ground
        beq     @r
        lda     o_vxh
        bmi     @neg
        ora     o_vxl
        beq     @r
        jsr     slow
        rts
@neg:   jsr     neg_vx
        jsr     slow
        jmp     neg_vx
@r:     rts
@go:    bpl     @right
        lda     #1
        sta     facing
        jsr     neg_vx          ; (left: the same, mirrored)
        jsr     @fwd
        jmp     neg_vx
@right: lda     #0
        sta     facing
@fwd:   lda     o_vxh
        bpl     @f
        clc                     ; moving the other way: skid
        lda     o_vxl
        adc     #<SKID
        sta     o_vxl
        lda     o_vxh
        adc     #>SKID
        sta     o_vxh
        rts
@f:     sec                     ; below the top speed: speed up
        lda     o_vxl
        sbc     vmax
        lda     o_vxh
        sbc     vmax+1
        bcs     @over
        clc
        lda     o_vxl
        adc     #<ACCEL
        sta     o_vxl
        lda     o_vxh
        adc     #>ACCEL
        sta     o_vxh
        sec
        lda     o_vxl
        sbc     vmax
        lda     o_vxh
        sbc     vmax+1
        bcc     @ok
@max:   lda     vmax
        sta     o_vxl
        lda     vmax+1
        sta     o_vxh
@ok:    rts
@over:  lda     onground        ; above it (stopped running): slow down
        beq     @ok
        sec
        lda     o_vxl
        sbc     #<DECEL
        sta     o_vxl
        lda     o_vxh
        sbc     #>DECEL
        sta     o_vxh
        sec
        lda     o_vxl
        sbc     vmax
        lda     o_vxh
        sbc     vmax+1
        bcc     @max
        rts

; a positive speed slows down by DECEL, not below 0
slow:   sec
        lda     o_vxl
        sbc     #<DECEL
        sta     o_vxl
        lda     o_vxh
        sbc     #>DECEL
        sta     o_vxh
        bpl     @r
        lda     #0
        sta     o_vxl
        sta     o_vxh
@r:     rts

neg_vx: sec
        lda     #0
        sbc     o_vxl
        sta     o_vxl
        lda     #0
        sbc     o_vxh
        sta     o_vxh
        rts

; a jump, and gravity
mos_jump:
        lda     lv_flags        ; under the coolant: swim
        and     #2
        beq     @land
        jmp     swim
@land:  lda     jump_buf
        beq     @grav
        dec     jump_buf
        lda     onground
        beq     @grav
        lda     #0
        sta     jump_buf
        sta     onground
        lda     o_vxl           ; |speed| / 8 more for a running jump
        sta     tmp
        lda     o_vxh
        bpl     @p
        sec
        lda     #0
        sbc     tmp
        sta     tmp
        lda     #0
        sbc     o_vxh
@p:     lsr
        ror     tmp
        lsr
        ror     tmp
        lsr
        ror     tmp
        sta     tmp+1
        clc
        lda     tmp
        adc     #<JUMP_V
        sta     tmp
        lda     tmp+1
        adc     #>JUMP_V
        sta     tmp+1
        sec
        lda     #0
        sbc     tmp
        sta     o_vyl
        lda     #0
        sbc     tmp+1
        sta     o_vyh
.if SOUND
        lda     big
        beq     @js
        lda     #SND_JUMPBIG-SND_JUMP
@js:    clc
        adc     #SND_JUMP
        jsr     snd
.endif
        rts                     ; (no gravity on the first frame)
@grav:  lda     o_vyh           ; rising with the button held: less gravity
        bpl     @hi
        lda     hold
        beq     @hi
        lda     #<GRAV_HOLD
        ldx     #>GRAV_HOLD
        jmp     @add
@hi:    lda     #<GRAV
        ldx     #>GRAV
@add:   clc
        adc     o_vyl
        sta     o_vyl
        txa
        adc     o_vyh
        sta     o_vyh
        bmi     @r
        cmp     #>MAX_FALL
        bcc     @r
        lda     #<MAX_FALL
        sta     o_vyl
        lda     #>MAX_FALL
        sta     o_vyh
@r:     rts

; under the coolant: each press of A (or W) is a stroke up, anywhere;
; MOS sinks slowly
swim:   lda     sw_t            ; (the kick's picture: a few frames)
        beq     @k
        dec     sw_t
@k:     lda     jump_buf
        beq     @g
        lda     #6
        sta     sw_t
.if SOUND
        lda     #SND_SWIM
        jsr     snd
.endif
        lda     #0
        sta     jump_buf
        sta     onground
        lda     #<-SWIM_V
        sta     o_vyl
        lda     #>-SWIM_V
        sta     o_vyh
        rts
@g:     clc
        lda     o_vyl
        adc     #<GRAV_W
        sta     o_vyl
        lda     o_vyh
        adc     #>GRAV_W
        sta     o_vyh
        bmi     @r
        cmp     #>MAX_FALL_W
        bcc     @r
        lda     #<MAX_FALL_W
        sta     o_vyl
        lda     #>MAX_FALL_W
        sta     o_vyh
@r:     rts

; ---- pipes: down into the bonus room, and back up out of the exit pipe -------------
; carry set if MOS stands on a pipe that goes down and down is pressed
pipe_check:
        lda     lv_room
        beq     @no
        lda     in_down
        beq     @no
        lda     onground
        beq     @no
        ldx     #O_MOS
        lda     #1
        ldy     mh
        jsr     tile_at
        jsr     is_pipein
        bcc     @no
        ldx     #O_MOS
        lda     #6
        ldy     mh
        jsr     tile_at
        jsr     is_pipein
        bcc     @no
        jsr     unduck
.if SOUND
        lda     #SND_PIPE
        jsr     snd
.endif
        lda     #MS_PIPE
        sta     mstate
        lda     #0
        sta     mtimer
        jsr     stop_mos
        sec
        rts
@no:    clc
        rts
is_pipein:
        cmp     #T_PIPEINL
        beq     @y
        cmp     #T_PIPEINR
        beq     @y
        clc
        rts
@y:     sec
        rts

; sinking into the pipe; then the bonus room, or back out of the exit pipe
m_pipe: inc     mtimer
        lda     mtimer
        cmp     #9
        bcs     @go
        inc     o_y             ; (down into it)
        rts
@go:    ldx     #NOBJ-1         ; nothing else comes along
        lda     #K_NONE
@cl:    sta     o_kind,x
        dex
        bne     @cl
        lda     in_room
        bne     @out
        lda     #1              ; in: the room fills one screen
        sta     in_room
        lda     lv_w
        sta     lv_wsave
        lda     #255
        sta     lv_w
        lda     scroll
        sta     sc_save
        lda     scroll+1
        sta     sc_save+1
        lda     max_sc
        sta     max_save
        lda     max_sc+1
        sta     max_save+1
        lda     lv_room         ; x = (room + 2) * 8, falling in from the top
        clc
        adc     #2
        jsr     col_x
        lda     #8
        sta     o_y
        lda     #0              ; the view: column room * 4, and stays there
        sta     tmp+1
        lda     lv_room
        asl
        rol     tmp+1
        asl
        rol     tmp+1
        sta     scroll
        sta     max_sc
        lda     tmp+1
        sta     scroll+1
        sta     max_sc+1
        jmp     @view
@out:   lda     #0              ; out: on top of the exit pipe
        sta     in_room
        lda     lv_wsave
        sta     lv_w
        lda     max_save
        sta     max_sc
        lda     max_save+1
        sta     max_sc+1
        lda     lv_out          ; x = pipe * 8 + 4
        jsr     col_x
        lda     o_xl
        clc
        adc     #4
        sta     o_xl
        bcc     @t
        inc     o_xh
@t:     lda     lv_out          ; y: its top, less MOS's height
        sta     htc
        ldy     #0
@f:     sty     htr
        jsr     map_get
        cmp     #T_PIPETL       ; (the pipe's top, not a ceiling over it)
        beq     @top
        cmp     #T_PIPEINL
        beq     @top
        ldy     htr
        iny
        cpy     #MAPROWS
        bne     @f
@top:   lda     htr
        asl
        asl
        asl
        sec
        sbc     mh
        sta     o_y
        sec                     ; the view: (x - 64) / 2, between where it
        lda     o_xl            ; was and the end
        sbc     #64
        sta     tmp
        lda     o_xh
        sbc     #0
        lsr
        ror     tmp
        sta     tmp+1
        lda     tmp
        cmp     sc_save
        lda     tmp+1
        sbc     sc_save+1
        bcs     @a
        lda     sc_save
        sta     tmp
        lda     sc_save+1
        sta     tmp+1
@a:     lda     tmp
        cmp     max_sc
        lda     tmp+1
        sbc     max_sc+1
        bcc     @b
        lda     max_sc
        sta     tmp
        lda     max_sc+1
        sta     tmp+1
@b:     lda     tmp
        sta     scroll
        lda     tmp+1
        sta     scroll+1
@view:  lda     scroll          ; draw it all again
        asl
        sta     sc2
        lda     scroll+1
        rol
        sta     sc2+1
        lda     #MS_PLAY
        sta     mstate
        lda     #0
        sta     onground
        jsr     new_screen
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print
        lda     #1
        sta     hud_dirty
        sta     full
.if SOUND
        jmp     music_level     ; (the room has its own)
.else
        rts
.endif

; ---- the princess: the time bonus, then the end ------------------------------------
m_rescue:
        jsr     bonus
        bcc     @r
        inc     mtimer
@r:     rts

; move MOS across, then up or down, stopping at solid tiles
mos_move:
        ldx     #O_MOS
        jsr     move_x
        lda     o_xl            ; not off the left of the view
        cmp     sc2
        lda     o_xh
        sbc     sc2+1
        bcs     @wall
        lda     sc2
        sta     o_xl
        lda     sc2+1
        sta     o_xh
        lda     #0
        sta     o_xf
        sta     o_vxl
        sta     o_vxh
@wall:  lda     o_vxh           ; into a wall?
        bmi     @left
        ora     o_vxl
        beq     @vert
        lda     #6
        jsr     side
        bcc     @vert
        lda     ptx             ; x = the tile's left - 7
        and     #$F8
        sec
        sbc     #7
        sta     o_xl
        lda     ptx+1
        sbc     #0
        sta     o_xh
        jmp     @stop
@left:  lda     #1
        jsr     side
        bcc     @vert
        lda     ptx             ; x = the tile's right + 1 - 1
        ora     #7
        sta     o_xl
        lda     ptx+1
        sta     o_xh
@stop:  lda     #0
        sta     o_xf
        sta     o_vxl
        sta     o_vxh
@vert:  ldx     #O_MOS
        jsr     move_y
        lda     #0
        sta     onground
        lda     o_vyh
        bmi     @up
        lda     #1              ; the feet
        ldy     mh
        dey
        jsr     tile_at
        bcs     @land
        ldx     #O_MOS
        lda     #6
        ldy     mh
        dey
        jsr     tile_at
        bcs     @land
        rts
@land:  lda     htr             ; stand on the tile
        asl
        asl
        asl
        sec
        sbc     mh
        sta     o_y
        lda     #0
        sta     o_yf
        sta     o_vyl
        sta     o_vyh
        lda     #1
        sta     onground
        rts
@up:    ldx     #O_MOS          ; the head: middle first
        lda     #3
        ldy     #0
        jsr     head_at
        bcs     @head
        ldx     #O_MOS
        lda     #5
        ldy     #0
        jsr     head_at
        bcs     @head
        ldx     #O_MOS
        lda     #2
        ldy     #0
        jsr     head_at
        bcs     @head
        rts
@head:  sta     tmp2            ; (the tile)
        lda     htr
        asl
        asl
        asl
        clc
        adc     #8
        sta     o_y
        lda     #0
        sta     o_yf
        sta     o_vyl
        sta     o_vyh
        lda     tmp2
        jmp     bump

; tile_at for MOS's head: a hidden block is solid too (from below)
head_at:jsr     tile_at
        bcs     @r
        cmp     #T_HIDDEN
        beq     @y
        clc
@r:     rts
@y:     sec
        rts

; MOS's side at A across: carry set if a solid tile is next to it (rows 1,
; the middle when big, and h - 2)
side:   sta     sidex
        ldx     #O_MOS
        ldy     #1
        jsr     tile_at
        bcs     @r
        lda     mh              ; (big and standing: the middle too.  Ducked,
        cmp     #9              ;  8 down is the floor beside his feet)
        bcc     @lo
        ldx     #O_MOS
        lda     sidex
        ldy     #8
        jsr     tile_at
        bcs     @r
@lo:    ldx     #O_MOS
        lda     sidex
        ldy     mh
        dey
        dey
        jsr     tile_at
@r:     rts

; object X: x += vx, y += vy
move_x: clc
        lda     o_xf,x
        adc     o_vxl,x
        sta     o_xf,x
        lda     o_xl,x
        adc     o_vxh,x
        sta     o_xl,x
        lda     o_vxh,x
        and     #$80
        beq     @p
        lda     #$FF
@p:     adc     o_xh,x
        sta     o_xh,x
        rts
move_y: clc
        lda     o_yf,x
        adc     o_vyl,x
        sta     o_yf,x
        lda     o_y,x
        adc     o_vyh,x
        sta     o_y,x
        rts

; MOS's head hit tile A at htc, htr
bump:
.if SOUND
        pha
        lda     #SND_BUMP
        jsr     snd
        pla
.endif
        cmp     #T_QCOIN
        beq     @coin
        cmp     #T_QMUSH
        beq     @mush
        cmp     #T_BRICK
        beq     @brick
        cmp     #T_HIDDEN
        beq     @hid
        cmp     #T_QOC
        beq     @oc
        rts
@oc:    lda     #T_USED         ; an overclock device
        jsr     set_tile
        jsr     free_slot
        bcc     @k
        lda     #K_OC
        bne     @rise
@hid:   lda     #T_USED         ; a hidden block: a 1UP
        jsr     set_tile
        jsr     free_slot
        bcc     @k
        lda     #K_ONEUP
        bne     @rise
@coin:  lda     #T_USED
        jsr     set_tile
        jsr     coin_pop
        jmp     bump_kill
@mush:  lda     #T_USED
        jsr     set_tile
        jsr     free_slot
        bcc     @k
        lda     #K_MUSH         ; (big already: a fire flower)
        ldy     big
        beq     @rise
        lda     #K_FLOWER
@rise:  jsr     obj_at_tile
.if SOUND
        lda     #SND_SPROUT
        jsr     snd
.endif
        lda     #8              ; it rises out of the block for 8 frames
        sta     o_t,x
@k:     jmp     bump_kill
@brick: lda     big
        beq     @k
.if SOUND
        lda     #SND_BREAK
        jsr     snd
.endif
        lda     #T_EMPTY
        jsr     set_tile
        lda     #<50
        ldy     #>50
        jsr     add_score
        jmp     bump_kill

; an object of kind A in slot X at tile htc, htr
obj_at_tile:
        sta     o_kind,x
        jsr     clear_obj
        lda     htc
        asl
        rol     o_xh,x
        asl
        rol     o_xh,x
        asl
        rol     o_xh,x
        sta     o_xl,x
        lda     htr
        asl
        asl
        asl
        sta     o_y,x
        rts

; a coin flies out of the block at htc, htr
coin_pop:
        ldx     #O_COIN
        lda     #K_COIN
        jsr     obj_at_tile
        lda     o_y,x
        sec
        sbc     #8
        sta     o_y,x
        lda     #<-$0400
        sta     o_vyl,x
        lda     #>-$0400
        sta     o_vyh,x
        lda     #14
        sta     o_t,x
add_coin:                       ; (a bit: 8 make a byte; $0C bytes, a life)
.if SOUND
        lda     #SND_COIN
        jsr     snd
.endif
        lda     #<200
        ldy     #>200
        jsr     add_score
        inc     bits
        lda     bits
        cmp     #8
        bcc     @r
        lda     #0
        sta     bits
        inc     bytes
        lda     bytes
        cmp     #$0C
        bcc     @r
        lda     #0
        sta     bytes
        lda     lives
        cmp     #99
        bcs     @r
        inc     lives
@r:     lda     #1
        sta     hud_dirty
        rts

; enemies standing on a bumped block are knocked out
bump_kill:
        ldx     #O_FIRST
@l:     lda     o_kind,x
        cmp     #K_BUG
        beq     @t
        cmp     #K_SHELLY
        beq     @t
        cmp     #K_SHELL
        bne     @n
@t:     lda     o_y,x           ; standing on it: y + 8 = row * 8
        clc
        adc     #8
        sta     tmp
        lda     htr
        asl
        asl
        asl
        cmp     tmp
        bne     @n
        lda     htc             ; and over it: |x - column * 8| < 7
        sta     tmp
        lda     #0
        asl     tmp
        rol
        asl     tmp
        rol
        asl     tmp
        rol
        sta     tmp+1
        sec
        lda     o_xl,x
        sbc     tmp
        sta     tmp
        lda     o_xh,x
        sbc     tmp+1
        jsr     near7
        bcc     @n
        jsr     knock
@n:     inx
        cpx     #O_LAST+1
        bne     @l
        rts

; carry set if the 16 bit number A (high), tmp (low) is within -6..6
near7:  cmp     #0
        beq     @p
        cmp     #$FF
        bne     @no
        lda     tmp
        cmp     #$FA
        rts                     ; (carry set if >= -6)
@p:     lda     tmp
        cmp     #7
        bcs     @no
        sec
        rts
@no:    clc
        rts

; knock out object X (100 points)
knock:
.if SOUND
        lda     #SND_KICK
        jsr     snd
.endif
        lda     #K_NONE
        sta     o_kind,x
        lda     #<100
        ldy     #>100
        jmp     add_score

; carry set and X = a free object slot (1-6)
free_slot:
        ldx     #O_FIRST
@l:     lda     o_kind,x
        beq     @y
        inx
        cpx     #O_LAST+1
        bne     @l
        clc
        rts
@y:     sec
        rts

; ============================================================================
; the other objects
; ============================================================================
obj_update:
        ldx     #O_FIRST
@l:     lda     o_kind,x
        bne     *+5
        jmp     @n
        cmp     #K_FLAT
        bne     *+5
        jmp     @flat
        cmp     #K_COIN
        bne     *+5
        jmp     @coin
        cmp     #K_FIRE         ; (electrons: fire_update)
        bne     *+5
        jmp     @n
        cmp     #K_DRAGON
        bne     @nd
        jsr     dragon
        jmp     @n
@nd:    cmp     #K_BREATH       ; KIL's fire: straight on
        bne     @nb
        jsr     move_x
        jsr     gone
        jmp     @n
@nb:    cmp     #K_FISH         ; fish, fans, the cloud, the princess
        bcc     @nn
        jsr     move_new
        jmp     @n
@nn:    cmp     #K_MUSH
        beq     @rise
        cmp     #K_ONEUP
        beq     @rise
        cmp     #K_OC
        beq     @rise
        cmp     #K_FLOWER
        bne     @walk
@rise:  lda     o_t,x           ; rising out of its block
        beq     @up
        dec     o_y,x
        dec     o_t,x
        beq     *+5
        jmp     @n
        lda     o_kind,x        ; (then a mushroom moves off; a flower stays)
        cmp     #K_FLOWER
        bne     *+5
        jmp     @n
        lda     #<MUSH_V
        sta     o_vxl,x
        lda     #>MUSH_V
        sta     o_vxh,x
        beq     *+5
        jmp     @n
@up:    lda     o_kind,x
        cmp     #K_FLOWER
        bne     *+5
        jmp     @n
@walk:  cmp     #K_SHELL        ; (a kicked shell can't hurt MOS at first)
        bne     @w2
        lda     o_t,x
        beq     @s1
        dec     o_t,x
@s1:    lda     o_vxl,x         ; a still shell: out again after a while
        ora     o_vxh,x
        bne     @w2
        inc     o_r,x
        lda     o_r,x
        cmp     #REVIVE
        bcc     @w2
        lda     #K_SHELLY       ; ... walking at MOS
        sta     o_kind,x
        lda     #0
        sta     o_r,x
        lda     #<-BUG_V
        sta     o_vxl,x
        lda     #>-BUG_V
        sta     o_vxh,x
        lda     o_xl,x
        cmp     o_xl
        lda     o_xh,x
        sbc     o_xh
        bcs     @w2
        lda     #<BUG_V
        sta     o_vxl,x
        lda     #>BUG_V
        sta     o_vxh,x
@w2:    jsr     walk_obj
        bcc     @w3
        lda     o_kind,x        ; (the OC device bounces along)
        cmp     #K_OC
        bne     @w3
        lda     #<-$0300
        sta     o_vyl,x
        lda     #>-$0300
        sta     o_vyh,x
@w3:    jsr     gone
        jmp     @n
@flat:  dec     o_t,x
        bne     @n
        beq     @del
@coin:  jsr     move_y
        clc
        lda     o_vyl,x
        adc     #$80
        sta     o_vyl,x
        bcc     @c2
        inc     o_vyh,x
@c2:    dec     o_t,x
        bne     @n
@del:   lda     #K_NONE
        sta     o_kind,x
@n:     inx
        cpx     #O_COIN+1
        beq     *+5
        jmp     @l
        rts

; ---- the newer ones: fish, fans, the cloud, the princess (object X, kind A) ------
move_new:
        cmp     #K_FAN
        beq     fan
        cmp     #K_CLOUD
        bne     *+5
        jmp     cloud
        cmp     #K_PRINCESS
        bne     fish
        rts                     ; (she waits)
; a gate on its side, swimming along, bobbing up and down
fish:   jsr     walk_x
        lda     o_r,x           ; a wavy one: up and down 12 pixels as it goes
        beq     @bob
        clc
        adc     #2
        sta     o_r,x
        lsr
        lsr
        lsr
        tay
        lda     o_t,x
        clc
        adc     wave,y
        sta     o_y,x
        jmp     gone
@bob:   lda     frame
        and     #15
        bne     @g
        lda     frame
        and     #16
        beq     @u
        inc     o_y,x
        bne     @g
@u:     dec     o_y,x
@g:     jmp     gone
; a fan: up 32 pixels from home (o_t) and back down, again and again
fan:    jsr     move_y
        lda     o_vyh,x
        bmi     @up
        lda     o_y,x
        cmp     o_t,x
        bcc     @g
        lda     #<-$0080
        sta     o_vyl,x
        lda     #>-$0080
        sta     o_vyh,x
        bne     @g
@up:    lda     o_r,x           ; (its top)
        cmp     o_y,x
        bcc     @g
        lda     #<$0080
        sta     o_vyl,x
        lda     #>$0080
        sta     o_vyh,x
@g:     jmp     gone
; the cloud: keeps above MOS near the top, and throws AND gates down at him
cloud:  sec                     ; cloud x - MOS x
        lda     o_xl,x
        sbc     o_xl
        sta     tmp
        lda     o_xh,x
        sbc     o_xh
        sta     tmp+1
        bmi     @rt
        bne     @lf             ; (far right)
        lda     tmp
        cmp     #24
        bcs     @lf
        lda     #<-$0080        ; just right of him: drift
        ldy     #>-$0080
        bne     @v
@lf:    lda     #<-$0200
        ldy     #>-$0200
        bne     @v
@rt:    cmp     #$FF
        bne     @rf
        lda     tmp
        cmp     #$E8
        bcc     @rf
        lda     #<$0080
        ldy     #>$0080
        jmp     @v
@rf:    lda     #<$0200
        ldy     #>$0200
@v:     sta     o_vxl,x
        tya
        sta     o_vxh,x
        jsr     move_x
        dec     o_t,x           ; time to throw?
        bne     @r
        lda     #80
        sta     o_t,x
        lda     mstate          ; (not when MOS is done for)
        bne     @r
        stx     tmp4
        jsr     free_slot
        bcc     @x
        lda     #K_BUG
        sta     o_kind,x
        jsr     clear_obj
        ldy     tmp4
        lda     o_xl,y
        sta     o_xl,x
        lda     o_xh,y
        sta     o_xh,x
        lda     o_y,y
        clc
        adc     #4
        sta     o_y,x
        lda     #<-$0200        ; tossed up a little, then it falls
        sta     o_vyl,x
        lda     #>-$0200
        sta     o_vyh,x
        lda     #<-BUG_V        ; and walks at MOS
        sta     o_vxl,x
        lda     #>-BUG_V
        sta     o_vxh,x
        lda     o_xl,x
        cmp     o_xl
        lda     o_xh,x
        sbc     o_xh
        bcs     @x
        lda     #<BUG_V
        sta     o_vxl,x
        lda     #>BUG_V
        sta     o_vxh,x
@x:     ldx     tmp4
@r:     rts

; ---- KIL, the dragon (object X) -----------------------------------------------------
; It paces about its place on the bridge, facing MOS, jumps now and then and
; breathes fire.  5 electrons finish it; RESET drops it in the lava.
dragon: lda     dr_flash
        beq     @f0
        dec     dr_flash
@f0:    lda     dr_dead         ; beaten: just falling
        beq     @alive
        jmp     @grav
@alive: lda     #0              ; face MOS
        sta     dr_face
        lda     o_xl,x
        clc
        adc     #4
        sta     tmp
        lda     o_xh,x
        adc     #0
        sta     tmp+1
        lda     tmp
        cmp     o_xl
        lda     tmp+1
        sbc     o_xh
        bcs     @wk
        inc     dr_face
@wk:    jsr     move_x          ; pace: home - 24 .. home + 8
        sec
        lda     o_xl,x
        sbc     dr_home
        sta     tmp
        lda     o_xh,x
        sbc     dr_home+1
        bmi     @lft
        bne     @back           ; (far right)
        lda     tmp
        cmp     #9
        bcc     @jp
@back:  sec                     ; past home + 8: go left
        lda     #0
        sbc     dr_spd
        sta     o_vxl,x
        lda     #$FF
        sta     o_vxh,x
        bne     @jp
@lft:   lda     tmp             ; left of home: past home - 24?
        cmp     #<-24
        bcs     @jp
        lda     dr_spd
        sta     o_vxl,x
        lda     #0
        sta     o_vxh,x
@jp:    dec     dr_t            ; a jump now and then
        bne     @br
        jsr     rand
        and     #63
        adc     dr_jb
        sta     dr_t
        lda     o_vyl,x
        ora     o_vyh,x
        bne     @br
        lda     #0              ; (up: dr_jv, the high byte)
        sta     o_vyl,x
        lda     dr_jv
        sta     o_vyh,x
@br:    dec     dr_bt           ; fire now and then
        bne     @grav
        jsr     rand
        and     #31
        adc     dr_bb
        sta     dr_bt
        stx     tmp4
        lda     o_y,x
        clc
        adc     #3
        sta     tmp3
        lda     o_xl,x
        sta     tmp2
        lda     o_xh,x
        sta     tmp+1
        jsr     free_slot
        bcc     @nb
.if SOUND
        lda     #SND_BREATH
        jsr     snd
.endif
        lda     #K_BREATH
        sta     o_kind,x
        jsr     clear_obj
        lda     tmp3
        sta     o_y,x
        lda     dr_face
        bne     @fr
        lda     tmp2            ; to the left: x - 6
        sec
        sbc     #6
        sta     o_xl,x
        lda     tmp+1
        sbc     #0
        sta     o_xh,x
        lda     #<-$0180
        sta     o_vxl,x
        lda     #>-$0180
        sta     o_vxh,x
        bne     @nb
@fr:    lda     tmp2            ; to the right: x + 14
        clc
        adc     #14
        sta     o_xl,x
        lda     tmp+1
        adc     #0
        sta     o_xh,x
        lda     #<$0180
        sta     o_vxl,x
        lda     #>$0180
        sta     o_vxh,x
@nb:    ldx     tmp4
@grav:  clc                     ; gravity
        lda     o_vyl,x
        adc     #<OBJ_GRAV
        sta     o_vyl,x
        lda     o_vyh,x
        adc     #>OBJ_GRAV
        sta     o_vyh,x
        cmp     #>MAX_FALL
        bcc     @mv
        lda     #<MAX_FALL
        sta     o_vyl,x
        lda     #>MAX_FALL
        sta     o_vyh,x
@mv:    jsr     move_y
        lda     o_y,x           ; gone down?
        bmi     @in
        cmp     #VIEW_H + 8
        bcc     @in
        lda     #K_NONE
        sta     o_kind,x
        rts
@in:    lda     dr_dead
        bne     @r
        lda     o_vyh,x         ; landing (on its feet: 16 down)
        bmi     @r
        lda     #3
        ldy     #15
        jsr     tile_at
        bcs     @land
        lda     #12
        ldy     #15
        jsr     tile_at
        bcc     @r
@land:  lda     htr
        asl
        asl
        asl
        sec
        sbc     #16
        sta     o_y,x
        lda     #0
        sta     o_yf,x
        sta     o_vyl,x
        sta     o_vyh,x
@r:     rts

; ---- MOS's electrons ---------------------------------------------------------------
; throw one (up to 2 at a time), from MOS's hand
throw_fire:
        ldx     #O_FIRE
        lda     o_kind,x
        beq     @go
        inx
        lda     o_kind,x
        beq     @go
        rts
@go:
.if SOUND
        lda     #SND_FIRE
        jsr     snd
.endif
        lda     #K_FIRE
        sta     o_kind,x
        jsr     clear_obj
        lda     o_y
        clc
        adc     #4
        sta     o_y,x
        lda     facing
        bne     @l
        lda     o_xl            ; right: x + 6
        clc
        adc     #6
        sta     o_xl,x
        lda     o_xh
        adc     #0
        sta     o_xh,x
        lda     #<FIRE_V
        sta     o_vxl,x
        lda     #>FIRE_V
        sta     o_vxh,x
        bne     @v
@l:     lda     o_xl            ; left: x - 2
        sec
        sbc     #2
        sta     o_xl,x
        lda     o_xh
        sbc     #0
        sta     o_xh,x
        lda     #<-FIRE_V
        sta     o_vxl,x
        lda     #>-FIRE_V
        sta     o_vxh,x
@v:     lda     #<$0100
        sta     o_vyl,x
        lda     #>$0100
        sta     o_vyh,x
        rts

; move the electrons: they bounce along the ground, burst on walls, and
; knock out what they hit
fire_update:
        ldx     #O_FIRE
@l:     lda     o_kind,x
        cmp     #K_FIRE
        beq     @go
        jmp     @n
@go:    jsr     move_x
        lda     o_vxh,x         ; a wall: gone
        bmi     @lw
        lda     #3
        bne     @cw
@lw:    lda     #0
@cw:    ldy     #1
        jsr     tile_at
        bcs     @del
        clc                     ; falling
        lda     o_vyl,x
        adc     #<FIRE_GRAV
        sta     o_vyl,x
        lda     o_vyh,x
        adc     #>FIRE_GRAV
        sta     o_vyh,x
        jsr     move_y
        lda     o_vyh,x         ; landing: bounce
        bmi     @hit
        lda     #1
        ldy     #3
        jsr     tile_at
        bcc     @hit
        lda     htr
        asl
        asl
        asl
        sec
        sbc     #4
        sta     o_y,x
        lda     #0
        sta     o_yf,x
        lda     #<-FIRE_BOUNCE
        sta     o_vyl,x
        lda     #>-FIRE_BOUNCE
        sta     o_vyh,x
@hit:   lda     o_y,x           ; down a pit, or out of view?
        bmi     @vx
        cmp     #VIEW_H
        bcs     @del
@vx:    sec
        lda     o_xl,x
        sbc     sc2
        tay
        lda     o_xh,x
        sbc     sc2+1
        bne     @del
        cpy     #160
        bcs     @del
        jsr     fire_hits
        jmp     @n
@del:   lda     #K_NONE
        sta     o_kind,x
@n:     inx
        cpx     #O_FIRE+2
        beq     @r
        jmp     @l
@r:     rts

; electron X against the enemies and KIL
fire_hits:
        ldy     #O_FIRST
@e:     lda     o_kind,y
        cmp     #K_BUG
        beq     @sm
        cmp     #K_SHELLY
        beq     @sm
        cmp     #K_SHELL
        beq     @sm
        cmp     #K_FISH
        beq     @sm
        cmp     #K_FAN
        beq     @sm
        cmp     #K_CLOUD
        beq     @sm
        cmp     #K_DRAGON
        beq     *+5
        jmp     @n
        lda     dr_dead
        beq     *+5
        jmp     @n
        lda     #15             ; KIL: 16 x 16
        sta     tmp2
        lda     #19
        bne     @t
@sm:    lda     #7              ; the rest: 8 x 8
        sta     tmp2
        lda     #11
@t:     sta     tmp3            ; enemy x - electron x + tmp2: 0 .. tmp3 - 1?
        sec
        lda     o_xl,y
        sbc     o_xl,x
        sta     tmp
        lda     o_xh,y
        sbc     o_xh,x
        sta     tmp+1
        clc
        lda     tmp
        adc     tmp2
        sta     tmp
        lda     tmp+1
        adc     #0
        bne     @n
        lda     tmp
        cmp     tmp3
        bcs     @n
        lda     o_y,y           ; the same, down
        sec
        sbc     o_y,x
        clc
        adc     tmp2
        cmp     tmp3
        bcs     @n
        lda     #K_NONE         ; a hit
        sta     o_kind,x
        lda     o_kind,y
        cmp     #K_DRAGON
        beq     @dr
        stx     tmp4
        tya
        tax
        jsr     knock
        ldx     tmp4
        rts
@dr:
.if SOUND
        lda     #SND_HIT
        jsr     snd
.endif
        lda     #8
        sta     dr_flash
        dec     dr_hp
        bne     @r
.if SOUND
        lda     #SND_KILDIE
        jsr     snd
.endif
        lda     #1              ; KIL is beaten: 5000
        sta     dr_dead
        lda     #<-$0300
        sta     o_vyl,y
        lda     #>-$0300
        sta     o_vyh,y
        lda     #<5000
        ldy     #>5000
        jmp     add_score
@n:     iny
        cpy     #O_LAST+1
        beq     *+5
        jmp     @e
@r:     rts

; remove object X if it fell out of the world or is well out of view
gone:   lda     o_y,x
        bmi     @x
        cmp     #VIEW_H + 8
        bcs     @del
@x:     clc                     ; x + 16 - the view's left edge: 0..207
        lda     o_xl,x
        adc     #16
        sta     tmp
        lda     o_xh,x
        adc     #0
        sta     tmp+1
        sec
        lda     tmp
        sbc     sc2
        tay
        lda     tmp+1
        sbc     sc2+1
        bne     @del            ; (off the left, or far off the right)
        cpy     #208
        bcs     @del
        rts
@del:   lda     #K_NONE
        sta     o_kind,x
        rts

; a walking object: turn round at walls, fall off edges
walk_obj:
        jsr     walk_x
        jmp     walk_v
walk_x: lda     o_xf,x          ; (to step back from a wall)
        sta     ox_f
        lda     o_xl,x
        sta     ox_l
        lda     o_xh,x
        sta     ox_h
        jsr     move_x
        lda     o_vxh,x
        bmi     @left
        ora     o_vxl,x
        beq     @r
        lda     #7
        bne     @chk
@left:  lda     #0
@chk:   ldy     #4
        jsr     tile_at
        bcc     @edge
@turn:  lda     ox_f            ; a wall: back, and turn round
        sta     o_xf,x
        lda     ox_l
        sta     o_xl,x
        lda     ox_h
        sta     o_xh,x
        sec
        lda     #0
        sbc     o_vxl,x
        sta     o_vxl,x
        lda     #0
        sbc     o_vxh,x
        sta     o_vxh,x
@r:     rts
@edge:  lda     o_kind,x        ; an OR gate on the ground: not over the edge
        cmp     #K_SHELLY
        bne     @r
        lda     o_vyl,x
        ora     o_vyh,x
        bne     @r
        lda     o_vxh,x         ; (the ground under its front foot)
        bmi     @el
        lda     #7
        bne     @ec
@el:    lda     #0
@ec:    ldy     #8
        jsr     tile_at
        bcs     @r
        bcc     @turn
walk_v: clc                     ; gravity
        lda     o_vyl,x
        adc     #<OBJ_GRAV
        sta     o_vyl,x
        lda     o_vyh,x
        adc     #>OBJ_GRAV
        sta     o_vyh,x
        cmp     #>MAX_FALL
        bcc     @mv
        lda     #<MAX_FALL
        sta     o_vyl,x
        lda     #>MAX_FALL
        sta     o_vyh,x
@mv:    jsr     move_y
        lda     #1              ; the feet
        ldy     #7
        jsr     tile_at
        bcs     @land
        lda     #6
        ldy     #7
        jsr     tile_at
        bcc     @r
@land:  lda     htr
        asl
        asl
        asl
        sec
        sbc     #8
        sta     o_y,x
        lda     #0
        sta     o_yf,x
        sta     o_vyl,x
        sta     o_vyh,x
        sec                     ; (landed)
@r:     rts

; ---- MOS against the objects; shells against the rest -----------------------------
obj_collide:
        lda     mstate
        beq     *+5
        jmp     @shells
        ldx     #O_FIRST
@l:     lda     o_kind,x
        cmp     #K_BUG
        bcs     *+5
        jmp     @n
        cmp     #K_FLAT
        bne     *+5
        jmp     @n
        cmp     #K_COIN
        bne     *+5
        jmp     @n
        cmp     #K_DRAGON       ; KIL: only hurts
        bne     @nk
        jsr     touch_dragon
        bcs     *+5
        jmp     @n
        jsr     hurt
        jmp     @n
@nk:    jsr     touch_mos
        bcs     *+5
        jmp     @n
        lda     o_kind,x
        cmp     #K_BREATH       ; its fire: hurts
        bne     @nf
        jsr     hurt
        jmp     @n
@nf:    cmp     #K_ONEUP        ; a 1UP: a life
        bne     @n1
.if SOUND
        lda     #SND_ONEUP
        jsr     snd
.endif
        lda     #K_NONE
        sta     o_kind,x
        lda     lives
        cmp     #99
        bcs     *+5
        inc     lives
        lda     #1
        sta     hud_dirty
        jmp     @n
@n1:    cmp     #K_FLOWER       ; the fire flower: big, and fire
        bne     @n2
        lda     #1
        sta     fire
        lda     #K_MUSH
@n2:    cmp     #K_MUSH
        beq     @mu
        cmp     #K_OC           ; the overclock device
        bne     @no
        lda     #K_NONE
        sta     o_kind,x
        lda     #OC_TIME
        sta     oc_t
.if SOUND
        lda     #SND_POWERUP
        jsr     snd
        lda     #MUS_STAR       ; its own music while it lasts
        jsr     music
.endif
        lda     #<1000
        ldy     #>1000
        jsr     add_score
        jmp     @n
@no:    cmp     #K_PRINCESS     ; Princess Graphics Card: the end
        bne     @oc
        lda     #MS_RESCUE
        sta     mstate
        lda     #0
        sta     mtimer
        jsr     stop_mos
        rts
@oc:    lda     oc_t            ; overclocked: what MOS touches is knocked out
        beq     @en
        jsr     knock
        jmp     @n
@mu:
.if SOUND
        lda     #SND_POWERUP
        jsr     snd
.endif
        lda     #K_NONE         ; a mushroom: grow
        sta     o_kind,x
        lda     #<1000
        ldy     #>1000
        jsr     add_score
        lda     big
        beq     *+5
        jmp     @n
        stx     tmp4
        jsr     unduck
        ldx     tmp4
        lda     #1
        sta     big
        lda     #16
        sta     mh
        lda     o_y
        sec
        sbc     #8
        sta     o_y
        jmp     @n
@en:    lda     o_kind,x        ; a shell standing still: kick it (from any side)
        cmp     #K_SHELL
        bne     @st
        lda     o_vxl,x
        ora     o_vxh,x
        bne     @st
        lda     o_t,x           ; (just stopped: harmless for a moment)
        bne     @n
        lda     o_vyh           ; landing on it: a little bounce too
        bmi     @kk
        ora     o_vyl
        beq     @kk
        lda     #<-(STOMP_V / 2)
        sta     o_vyl
        lda     #>-(STOMP_V / 2)
        sta     o_vyh
@kk:    lda     #<SHELL_V
        sta     o_vxl,x
        lda     #>SHELL_V
        sta     o_vxh,x
        lda     o_xl,x          ; away from MOS
        cmp     o_xl
        lda     o_xh,x
        sbc     o_xh
        bcs     @k
        sec
        lda     #0
        sbc     o_vxl,x
        sta     o_vxl,x
        lda     #0
        sbc     o_vxh,x
        sta     o_vxh,x
@k:
.if SOUND
        lda     #SND_KICK
        jsr     snd
.endif
        lda     #10
        sta     o_t,x
        lda     #<400
        ldy     #>400
        jsr     add_score
        jmp     @n
@st:    lda     lv_flags        ; (no stomping under the coolant)
        and     #2
        bne     @h2
        jsr     stomped         ; an enemy (or a moving shell): from above?
        bcs     @n
        lda     o_kind,x
        cmp     #K_SHELL
        bne     @h2
        lda     o_t,x           ; (a shell just kicked can't hurt)
        bne     @n
@h2:    jsr     hurt
@n:     inx
        cpx     #O_LAST+1
        beq     *+5
        jmp     @l
@shells:ldx     #O_FIRST        ; a moving shell knocks out what it meets
@s:     lda     o_kind,x
        cmp     #K_SHELL
        bne     @sn
        lda     o_vxl,x
        ora     o_vxh,x
        beq     @sn
        ldy     #O_FIRST
@e:     sty     tmp3
        stx     tmp2
        cpy     tmp2
        beq     @en2
        lda     o_kind,y
        cmp     #K_BUG
        beq     @t
        cmp     #K_SHELLY
        beq     @t
        cmp     #K_SHELL
        bne     @en2
@t:     sec                     ; |dx| < 7 and |dy| < 7
        lda     o_xl,y
        sbc     o_xl,x
        sta     tmp
        lda     o_xh,y
        sbc     o_xh,x
        jsr     near7
        bcc     @en2
        lda     o_y,y
        sec
        sbc     o_y,x
        sta     tmp
        lda     #0
        bit     tmp
        bpl     @dp
        lda     #$FF
@dp:    jsr     near7
        bcc     @en2
        txa
        pha
        ldx     tmp3
        jsr     knock
        pla
        tax
@en2:   ldy     tmp3
        iny
        cpy     #O_LAST+1
        bne     @e
@sn:    inx
        cpx     #O_LAST+1
        bne     @s
        rts

; carry set if KIL (object X) touches MOS: its box is x + 2..13, y + 2..15
touch_dragon:
        lda     dr_dead
        bne     @no
        sec                     ; x - MOS x: -12 .. 4
        lda     o_xl,x
        sbc     o_xl
        sta     tmp
        lda     o_xh,x
        sbc     o_xh
        sta     tmp+1
        clc
        lda     tmp
        adc     #12
        sta     tmp
        lda     tmp+1
        adc     #0
        bne     @no
        lda     tmp
        cmp     #17
        bcs     @no
        lda     o_y,x           ; y - MOS y: -15 .. h - 3
        sec
        sbc     o_y
        clc
        adc     #15
        sta     tmp
        lda     mh
        clc
        adc     #13
        cmp     tmp
        bcc     @no
        beq     @no
        sec
        rts
@no:    clc
        rts

; carry set if object X touches MOS
touch_mos:
        sec                     ; |x - MOS x| < 6
        lda     o_xl,x
        sbc     o_xl
        sta     tmp
        lda     o_xh,x
        sbc     o_xh
        beq     @p
        cmp     #$FF
        bne     @no
        lda     tmp
        cmp     #$FB
        bcc     @no
        bcs     @y
@p:     lda     tmp
        cmp     #6
        bcs     @no
@y:     lda     o_kind,x        ; (the princess is 16 high: her lower half)
        cmp     #K_PRINCESS
        lda     o_y,x           ; dy = y - MOS y: -7 .. h - 2
        bcc     @y2
        adc     #7
@y2:    sec
        sbc     o_y
        clc
        adc     #7              ; 0 .. h + 5
        sta     tmp
        lda     mh
        clc
        adc     #6
        cmp     tmp             ; carry set if h + 6 >= dy + 7 + 1 ... (h + 6 > tmp)
        beq     @no
        bcc     @no
        sec
        rts
@no:    clc
        rts

; MOS lands on object X from above?  Then squash / stop it, bounce, carry set
stomped:
        lda     o_vyh           ; falling
        bmi     @no
        ora     o_vyl
        beq     @no
        lda     o_y             ; MOS's feet within the top 6 rows
        clc
        adc     mh
        sec
        sbc     o_y,x
        sec
        sbc     #1
        cmp     #7
        bcs     @no
        lda     o_kind,x
        cmp     #K_BUG
        bne     @nb
        lda     #K_FLAT
        sta     o_kind,x
        lda     #12
        sta     o_t,x
        bne     @stop
@nb:    cmp     #K_FISH         ; a fan or the cloud: knocked out
        bcc     @sh
        lda     #K_NONE
        sta     o_kind,x
        beq     @stop
@sh:    lda     #K_SHELL        ; a SHELLY, or a moving shell: a still shell
        sta     o_kind,x
        lda     #10
        sta     o_t,x
        lda     #0
        sta     o_r,x
@stop:
.if SOUND
        lda     #SND_STOMP
        jsr     snd
.endif
        lda     #0
        sta     o_vxl,x
        sta     o_vxh,x
        lda     #<100
        ldy     #>100
        jsr     add_score
        lda     #<-STOMP_V
        sta     o_vyl
        lda     #>-STOMP_V
        sta     o_vyh
        sec
        rts
@no:    clc
        rts

; MOS is hit: shrink, or die
hurt:   lda     inv_t
        ora     oc_t            ; (overclocked: nothing hurts)
        bne     @r
        stx     tmp4
        jsr     unduck
        ldx     tmp4
        lda     big
        beq     @die
.if SOUND
        lda     #SND_HURT
        jsr     snd
.endif
        lda     #0
        sta     big
        sta     fire
        lda     #8
        sta     mh
        lda     o_y
        clc
        adc     #8
        sta     o_y
        lda     #INVULN
        sta     inv_t
@r:     rts
@die:   stx     tmp4
        jsr     die
        ldx     tmp4
        rts

; ---- the view follows MOS (forward only) ------------------------------------------
camera: sec                     ; (x - 64) / 2 characters
        lda     o_xl
        sbc     #64
        sta     tmp
        lda     o_xh
        sbc     #0
        bcc     @r
        lsr
        ror     tmp
        sta     tmp+1
        lda     noscroll        ; (redrawing: 2 at a time, half as often)
        beq     @one
        lda     tmp
        and     #$FE
        sta     tmp
@one:   lda     scroll          ; further on than now?
        cmp     tmp
        lda     scroll+1
        sbc     tmp+1
        bcs     @r
        lda     tmp             ; but not past the end
        cmp     max_sc
        lda     tmp+1
        sbc     max_sc+1
        bcc     @set
        lda     max_sc
        sta     tmp
        lda     max_sc+1
        sta     tmp+1
@set:   lda     tmp
        cmp     scroll
        bne     @mv
        lda     tmp+1
        cmp     scroll+1
        beq     @r
@mv:    lda     scroll
        sta     sc_old
        lda     scroll+1
        sta     sc_old+1
        lda     tmp
        sta     scroll
        lda     tmp+1
        sta     scroll+1
        lda     #1
        sta     scrolled
        jsr     shift_marks
        lda     scroll
        asl
        sta     sc2
        lda     scroll+1
        rol
        sta     sc2+1
@r:     rts

; Characters marked for comparing so far this frame (tiles that changed: a
; bit taken, a block bumped) were marked by their screen column before the
; view moved; the marks are by screen column after it, so move them left by
; the scroll (off the left: dropped).  Without this, a tile changed in a frame
; that scrolled was compared d columns too far right, and some of its
; characters were never sent: a bit taken while running left a few pixels.
shift_marks:
        sec
        lda     scroll
        sbc     sc_old
        sta     tmp2
        lda     scroll+1
        sbc     sc_old+1
        bne     @r              ; (a jump: the view is drawn again anyway)
        ldx     #PROWS-1
@m:     lda     dmin,x
        cmp     #$FF
        beq     @n
        lda     dmax,x
        sec
        sbc     tmp2
        bcc     @none
        sta     dmax,x
        lda     dmin,x
        sec
        sbc     tmp2
        bcs     @lo
        lda     #0
@lo:    sta     dmin,x
        jmp     @n
@none:  lda     #$FF
        sta     dmin,x
        lda     #0
        sta     dmax,x
@n:     dex
        bpl     @m
@r:     rts

; ---- enemies come in as their column nears the view -------------------------------
spawn_enemies:
        lda     in_room         ; (in the bonus room: the level's wait)
        beq     *+3
        rts
        lda     scroll+1        ; the view's last column + 2
        sta     tmp
        lda     scroll
        lsr     tmp
        ror
        lsr     tmp
        ror
        clc
        adc     #22
        bcc     @e
        lda     #$FF
@e:     sta     tmp2
@l:     ldy     en_i
        jsr     en_rd
        cmp     #$FF
        bne     *+5
        jmp     @r
        cmp     tmp2
        beq     @go
        bcc     *+5
        jmp     @r
@go:    sta     htc
        iny
        jsr     en_rd
        sta     htr
        iny
        jsr     en_rd
        sta     tmp3
        iny
        sty     en_i
        jsr     free_slot
        bcc     @l
        ldy     tmp3
        cpy     #3
        beq     @dr
        lda     en_kind-1,y
        jsr     obj_at_tile
        lda     o_kind,x
        cmp     #K_PRINCESS
        beq     @l
        cmp     #K_FAN          ; a fan: flies up from where it is, and back
        bne     @nf
        lda     o_y,x
        sta     o_t,x
        sec                     ; (up 32, or a high flyer: up to the top)
        sbc     #32
        bcs     @f1
        lda     #0
@f1:    ldy     tmp3
        cpy     #8
        bne     @f2
        lda     #FAN_TOP
@f2:    sta     o_r,x
        lda     #<-$0080
        sta     o_vyl,x
        lda     #>-$0080
        sta     o_vyh,x
        jmp     @l
@nf:    cmp     #K_CLOUD        ; the cloud: its first throw soon
        bne     @nc
        lda     #40
        sta     o_t,x
        jmp     @l
@nc:    cmp     #K_FISH
        bne     @k
        lda     #<-FISH_V
        sta     o_vxl,x
        lda     #>-FISH_V
        sta     o_vxh,x
        lda     o_y,x           ; (a wavy one: about its row, o_r its phase)
        sta     o_t,x
        ldy     tmp3
        cpy     #9
        beq     *+5
        jmp     @l
        lda     #1
        sta     o_r,x
        jmp     @l
@k:     lda     #<-BUG_V
        sta     o_vxl,x
        lda     #>-BUG_V
        sta     o_vxh,x
        jmp     @l
@dr:    lda     world           ; KIL gets livelier world by world
        cmp     #5
        bcc     @dw
        lda     #5
@dw:    tay
        lda     kil_spd-1,y
        sta     dr_spd
        lda     kil_jmp-1,y
        sta     dr_jb
        lda     kil_brt-1,y
        sta     dr_bb
        lda     kil_jv-1,y
        sta     dr_jv
        lda     #K_DRAGON       ; KIL
        jsr     obj_at_tile
        lda     o_xl,x
        sta     dr_home
        lda     o_xh,x
        sta     dr_home+1
        lda     #DRAGON_HP
        sta     dr_hp
        lda     #0
        sta     dr_dead
        sta     dr_flash
        lda     #<-$0040
        sta     o_vxl,x
        lda     #>-$0040
        sta     o_vxh,x
        lda     #40
        sta     dr_t
        lda     #30
        sta     dr_bt
        jmp     @l
@r:     rts
en_rd:  lda     en_buf,y        ; (the level's enemy list)
        rts

; ---- the timer ------------------------------------------------------------------
clock:  lda     mstate
        bne     @r
        inc     time_div
        lda     time_div
        cmp     #TIME_TICK
        bcc     @r
        lda     #0
        sta     time_div
        sed
        sec
        lda     time
        sbc     #1
        sta     time
        lda     time+1
        sbc     #0
        sta     time+1
        cld
        lda     #1
        sta     hud_dirty
.if SOUND
        lda     time            ; 100 left: hurry
        bne     @h
        lda     time+1
        cmp     #1
        bne     @h
        lda     #SND_HURRY
        jsr     snd
@h:
.endif
        lda     time
        ora     time+1
        bne     @r
        jmp     die
@r:     rts

.if SOUND
; ---- sound ----------------------------------------------------------------------
; play sound A (SND_..., on its voice: sfx_prio's high 4 bits).  Keeps A, X, Y.
snd:    sta     snd_a
        stx     snd_x
        sty     snd_y
        tay
        lda     sfx_prio,y      ; (the voice is in its high 4 bits)
        lsr
        lsr
        lsr
        lsr
        tax
        tya
        jsr     sfx_play
        lda     snd_a
        ldx     snd_x
        ldy     snd_y
        rts

; tune A (MUS_...): its melody and bass on voices 0 and 1
music:  jsr     snd
        clc
        adc     #1
        jmp     snd

music_stop:
        txa
        pha
        ldx     #0
        jsr     sfx_stop
        inx
        jsr     sfx_stop
        pla
        tax
        rts

; the level's tune: the castle; under the bricks (x-2, the bonus rooms) or
; the coolant; outdoors
music_level:
        lda     lv_flags
        lsr
        bcc     @1
        lda     #MUS_CASTLE
        bne     music
@1:     lsr
        bcs     @u              ; (under the coolant)
        lda     in_room
        bne     @u
        lda     lvl
        cmp     #1
        bne     @o
@u:     lda     #MUS_UNDER
        bne     music
@o:     lda     #MUS_OVER       ; (0: a JMP, not a BNE)
        jmp     music

; the end of a world (or the game)
fanfare:jsr     sfx_off
        lda     #SND_CLEARA     ; (the level's fanfare, longer by being
        jsr     snd             ; the only sound)
        lda     #SND_CLEARB
        jmp     snd

; M: sound on / off
toggle_sound:
        lda     sfx_mute
        eor     #1
        sta     sfx_mute
        jmp     sfx_hush
.endif

; ---- points ---------------------------------------------------------------------
; add A (low) + Y (high) to the score (24 bits, shown in hex: it's DATA)
add_score:
        clc
        adc     score
        sta     score
        tya
        adc     score+1
        sta     score+1
        lda     score+2
        adc     #0
        sta     score+2
        lda     #1
        sta     hud_dirty
        rts

hud_update:
        lda     hud_dirty
        bne     @go
        rts
@go:    lda     #0
        sta     hud_dirty
        jsr     txt_mode
        ldx     #5
        ldy     #0
        jsr     gotoxy
        lda     score+2
        jsr     prhex
        lda     score+1
        jsr     prhex
        lda     score
        jsr     prhex
        ldx     #19
        jsr     setcol
        lda     bytes
        jsr     prhex
        lda     #' '            ; the byte being filled: a 1 for each bit
        jsr     putc
        ldx     #8
@b:     lda     #'0'
        cpx     bits
        beq     @b1
        bcs     @b0
@b1:    lda     #'1'
@b0:    jsr     putc
        dex
        bne     @b
        ldx     #38
        jsr     setcol
        jsr     pr_world
        ldx     #52
        jsr     setcol
        lda     time+1
        and     #$0F
        ora     #'0'
        jsr     putc
        lda     time
        jsr     prbcd
        ldx     #65
        jsr     setcol
        lda     lives
        jsr     prdec
        lda     #' '
        jmp     putc

; ============================================================================
; drawing
; ============================================================================
.if SOFT_SPRITES
render: jsr     restore_rects   ; the map back under last frame's sprites
.else
render: jsr     ask_wait        ; the terminal has drawn the last frame
.if UNC_TILES
        jsr     unc_tiles       ; sprites off changed tiles first (not held)
.endif
        lda     #<hold_txt      ; the whole frame between HOLD and SHOW: the
        ldy     #>hold_txt      ; scroll, the scenery and the sprites
        jsr     print
        jsr     render_bg
        jsr     hw_sprites
        lda     #<show_txt
        ldy     #>show_txt
        jmp     print
render_bg:
.endif
        lda     #0
        sta     fullcmp
        lda     full
        beq     @s
        lda     #0              ; the whole view
        sta     full
        lda     scroll+1
        sta     tmp
        lda     scroll
        lsr     tmp
        ror
        lsr     tmp
        ror
        tax
        clc
        adc     #20
        jsr     gen_cols
        jmp     @all
@s:     lda     scrolled
        beq     @spr
        lda     sc_old          ; the tiles that came into view on the right:
        clc                     ; (old scroll + 80) / 4 .. (scroll + 79) / 4
        adc     #COLS
        sta     tmp
        lda     sc_old+1
        adc     #0
        lsr
        ror     tmp
        lsr
        ror     tmp
        lda     scroll
        clc
        adc     #COLS-1
        sta     tmp2
        lda     scroll+1
        adc     #0
        lsr
        ror     tmp2
        lsr
        ror     tmp2
        ldx     tmp
        lda     tmp2
        jsr     gen_cols
        lda     noscroll
        bne     @move
        jsr     scroll_d        ; the terminal moves the view.  First the
.if SOFT_SPRITES
        jsr     draw_objs       ; sprites go to their new places on the view
.endif
        jsr     pre_send        ; as it is now, so that they scroll with it;
        jsr     hw_scroll       ; then only the new columns (and anything
        jmp     present         ; left over) need comparing
@move:  jsr     move_shown      ; (the old way: compare it all)
@all:   lda     #1              ; and compare every row
        sta     fullcmp
        jsr     row_tiles
@spr:
.if SOFT_SPRITES
        jsr     draw_objs
.endif
        jmp     present

; ---- scrolling ------------------------------------------------------------------------
; The copy of what the terminal shows (sh) is kept like wc, by the world
; column, so it stays right when the terminal moves the view itself.

; d = scroll - sc_old characters (at most 80)
scroll_d:
        sec
        lda     scroll
        sbc     sc_old
        tax
        lda     scroll+1
        sbc     sc_old+1
        bne     @big
        cpx     #COLS+1
        bcc     @ok
@big:   ldx     #COLS
@ok:    stx     sd
        rts

; the terminal scrolls the view left d characters (16, d times; the repeat
; count must be 0 for whole characters).  The columns that come in on the
; right are blank: so is the copy there; and they are marked for comparing.
hw_scroll:
        lda     sd
        sta     tmp3
@s:     lda     #1              ; one character: attribute 80, no repeat
.if !SOFT_SPRITES
        ldx     tmp3            ; (SMBSW.BIN: one at a time, for a terminal
        cpx     #2              ; without pixel scrolling)
        bcc     @one
        lda     #12             ; two at once: a 12 pixel scroll (repeat 12;
.endif
@one:   jsr     set_rep         ; the terminal waits for its vertical blank
        lda     #TC_SCROLL      ; once per scroll with sprites showing)
        jsr     putc
        dec     tmp3
        lda     cur_rep
        cmp     #12
        bne     @n
        dec     tmp3
@n:     lda     tmp3
        bne     @s
        lda     scroll          ; the blank columns: world scroll + 80 - d ..
        clc
        adc     #COLS
        sec
        sbc     sd
        sta     tmp
        lda     #COLS           ; ... at screen columns 80 - d .. 79
        sec
        sbc     sd
        sta     tmp2
        ldy     #PROWS-1
@row:   tya
        clc
        adc     #>sh
        sta     @w+2
        ldx     tmp
        lda     sd
        sta     tmp3
        lda     #0
@w:     sta     sh,x
        inx
        dec     tmp3
        bne     @w
        lda     tmp2
        jsr     mark1
        lda     #COLS-1
        jsr     mark1
        lda     #0
        sta     sh_empty,y
        dey
        bpl     @row
        rts

; before the terminal scrolls d characters: send what is marked as it lies
; on the screen now (d columns further right), so that the sprites move
; together with the view and never show in the wrong place behind it
pre_send:
        ldx     #PROWS-1
@s:     lda     dmin,x          ; keep the marks; shift them right by d
        sta     svmin,x
        lda     dmax,x
        sta     svmax,x
        lda     dmin,x
        cmp     #$FF
        beq     @n
        clc
        adc     sd
        cmp     #COLS
        bcs     @off
        sta     dmin,x
        lda     dmax,x
        clc
        adc     sd
        cmp     #COLS
        bcc     @mx
        lda     #COLS-1
@mx:    sta     dmax,x
        jmp     @n
@off:   lda     #$FF
        sta     dmin,x
@n:     dex
        bpl     @s
        lda     sc_old
        sta     pbase
        jsr     present_at
        ldx     #PROWS-1        ; the marks back (for after the scroll)
@r:     lda     svmin,x
        sta     dmin,x
        lda     svmax,x
        sta     dmax,x
        dex
        bpl     @r
        rts

; redrawing instead: the terminal still shows at screen column x what was
; at world column sc_old + x; move the copy to world column scroll + x
move_shown:
        jsr     scroll_d
        ldy     #PROWS-1
@row:   tya
        clc
        adc     #>sh
        sta     @r+2
        sta     @w+2
        ldx     sc_old          ; out to a row buffer ...
        stx     @r+1
        ldx     #0
@r:     lda     sh
        sta     mvbuf,x
        inc     @r+1
        inx
        cpx     #COLS
        bne     @r
        lda     scroll          ; ... and back, further on
        sta     @w+1
        ldx     #0
@b:     lda     mvbuf,x
@w:     sta     sh
        inc     @w+1
        inx
        cpx     #COLS
        bne     @b
        dey
        bpl     @row
        rts

; ---- the view from the map --------------------------------------------------------
; wc holds the view: a page a text row, indexed by the world column & 255.
; Scrolling only has to fill in the columns coming into view.

; tile columns X .. A
gen_cols:
        sta     g_end
@l:     txa
        pha
        jsr     gen_tilecol
        pla
        tax
        cpx     g_end
        inx
        bcc     @l
        rts

; tile column A of the map into wc (22 rows x 4 characters)
gen_tilecol:
        sta     g_cur
        asl
        asl
        sta     g_x
.repeat MAPROWS, R
        ldy     g_cur
        ldx     map + R * 256,y
        ldy     g_x
        lda     tile_top,x
        sta     wc + (2 * R) * 256,y
        lda     tile_top+1,x
        sta     wc + (2 * R) * 256 + 1,y
        lda     tile_top+2,x
        sta     wc + (2 * R) * 256 + 2,y
        lda     tile_top+3,x
        sta     wc + (2 * R) * 256 + 3,y
        lda     tile_bot,x
        sta     wc + (2 * R + 1) * 256,y
        lda     tile_bot+1,x
        sta     wc + (2 * R + 1) * 256 + 1,y
        lda     tile_bot+2,x
        sta     wc + (2 * R + 1) * 256 + 2,y
        lda     tile_bot+3,x
        sta     wc + (2 * R + 1) * 256 + 3,y
.endrepeat
        rts

; trow[r] = 0 if the tile row r has nothing but empty tiles in view
row_tiles:
        lda     scroll+1
        sta     tmp
        lda     scroll
        lsr     tmp
        ror
        lsr     tmp
        ror
        sta     g_cur
.repeat MAPROWS, R
        ldy     g_cur
        ldx     #21
        lda     #0
:       ora     map + R * 256,y
        iny
        dex
        bne     :-
        sta     trow + R
.endrepeat
        rts

; the map into wc: row s_r, screen columns s_c0..s_c1
bg_span:
        clc                     ; the world column
        lda     s_c0
        adc     scroll
        sta     tmp
        tax                     ; (its place in the row)
        lda     scroll+1
        adc     #0
        sta     tmp+1
        lda     tmp
        and     #3
        sta     b_ph
        lsr     tmp+1
        ror     tmp
        lsr     tmp+1
        ror     tmp
        lda     s_r             ; the top or the bottom row of the tiles
        lsr
        bcc     @t
        lda     #<tile_bot
        sta     @g+1
        lda     #>tile_bot
        sta     @g+2
        bne     @t2
@t:     lda     #<tile_top
        sta     @g+1
        lda     #>tile_top
        sta     @g+2
@t2:    lda     s_r
        lsr
        clc
        adc     #>map
        sta     @m+2
        lda     s_r
        clc
        adc     #>wc
        sta     @w+2
        lda     s_c1
        sec
        sbc     s_c0
        sta     b_n             ; (count - 1)
@c:     ldy     tmp
@m:     lda     map,y
        ora     b_ph
        tay
@g:     lda     tile_top,y
@w:     sta     wc,x
        inc     b_ph
        lda     b_ph
        cmp     #4
        bne     @s
        lda     #0
        sta     b_ph
        inc     tmp
@s:     inx
        dec     b_n
        bpl     @c
        rts

; s_c0..s_c1 = columns s_col .. s_col + s_w - 1 that are on the screen;
; carry set if none
clip_cols:
        lda     s_col
        clc
        adc     s_w
        sec
        sbc     #1
        bmi     @none           ; (the right end is off the left)
        cmp     #COLS
        bcc     @c1
        lda     #COLS-1
@c1:    sta     s_c1
        lda     s_col
        bpl     @c0
        lda     #0
@c0:    cmp     #COLS
        bcs     @none
        sta     s_c0
        clc
        rts
@none:  sec
        rts

.if SOFT_SPRITES
; put the map back where last frame's sprites were (the part still in view)
restore_rects:
        ldx     #0
@l:     cpx     nrect
        bne     @go
        rts
@go:    stx     ri
        sec                     ; screen column = world column - scroll
        lda     rc_cl,x
        sbc     scroll
        sta     s_col
        lda     rc_ch,x
        sbc     scroll+1
        beq     @p
        cmp     #$FF
        bne     @n
        lda     s_col
        bmi     @v
        bpl     @n
@p:     lda     s_col
        bmi     @n
@v:     lda     rc_w,x
        sta     s_w
        jsr     clip_cols
        bcs     @n
        ldx     ri
        lda     rc_r,x
        sta     s_r
        lda     rc_h,x
        sta     s_hn
@row:   lda     s_r
        cmp     #PROWS
        bcs     @nr
        jsr     bg_span
        ldy     s_r
        lda     s_c0
        jsr     mark1
        lda     s_c1
        jsr     mark1
@nr:    inc     s_r
        dec     s_hn
        bne     @row
@n:     ldx     ri
        inx
        bne     @l

; ---- sprites -----------------------------------------------------------------
draw_objs:
        lda     #0
        sta     nrect
        ldx     #O_FIRST
@l:     stx     dobj
        lda     o_kind,x
        beq     @n
        jsr     obj_frame
        bcs     @n
        jsr     draw_obj
@n:     ldx     dobj
        inx
        cpx     #NOBJ
        bne     @l
        ldx     #O_MOS          ; MOS last, on top
        lda     o_kind
        beq     @r
        jsr     mos_frame
        bcs     @r
        jsr     draw_obj
@r:     rts

; object X with picture A, mirrored if smir.  The pictures are stored for
; x & 1 with their top on a cell row; they are shifted down 0-3 pixel rows
; (2 bits a row) and mirrored here, cell by cell, column by column.
draw_obj:
        sta     spf
        sec                     ; on the screen: x - scroll * 2
        lda     o_xl,x
        sbc     sc2
        sta     sxl
        lda     o_xh,x
        sbc     sc2+1
        sta     sxh
        lda     o_xh,x          ; in the world: column x / 2
        lsr
        sta     swh
        lda     o_xl,x
        ror
        sta     swl
        lda     o_y,x
        sta     sy
        lda     sxh             ; on the screen?  x -32..159, y -16..87
        beq     @x0
        cmp     #$FF
        bne     @no
        lda     sxl
        cmp     #$E0
        bcc     @no
        bcs     @y
@x0:    lda     sxl
        cmp     #160
        bcs     @no
@y:     lda     sy
        bpl     @y0
        cmp     #$F0
        bcc     @no
        bcs     @go
@y0:    cmp     #VIEW_H
        bcc     @go
@no:    rts
@go:    lda     spf             ; the picture for x & 1
        asl
        sta     tmp
        lda     sxl
        and     #1
        ora     tmp
        tay
        lda     spr_lo,y
        sta     @d0+1
        sta     @d1+1
        sta     @dm+1
        sta     @db+1
        lda     spr_hi,y
        sta     @d0+2
        sta     @d1+2
        sta     @dm+2
        sta     @db+2
        lda     sxh             ; screen column = x / 2, row = y / 4 (signed)
        cmp     #$80
        lda     sxl
        ror
        sta     s_col
        lda     sy
        and     #3              ; shifted down 0-3 pixel rows: 0-6 bits
        asl
        sta     s_sh
        lda     sy
        cmp     #$80
        ror
        cmp     #$80
        ror
        sta     s_r
        ldy     #0
@d0:    lda     $FFFF,y
        sta     s_w
        iny
@d1:    lda     $FFFF,y
        sta     s_h0
        ldx     s_sh            ; (one more row when shifted)
        beq     @h
        clc
        adc     #1
@h:     sta     s_hn
        ldx     nrect           ; remember where, to clear it next frame
        lda     swl
        sta     rc_cl,x
        lda     swh
        sta     rc_ch,x
        lda     s_r
        sta     rc_r,x
        lda     s_w
        sta     rc_w,x
        lda     s_hn
        sta     rc_h,x
        inc     nrect
        jsr     clip_cols
        bcc     *+5
        jmp     @no
        lda     #2              ; the cells, column by column
        sta     s_di
        lda     #0
        sta     s_cc
@col:   lda     s_cc            ; which column of the sprite on the screen
        ldx     smir
        beq     @nm
        lda     s_w
        clc
        sbc     s_cc            ; (w - 1 - cc)
@nm:    sta     tmp
        clc
        adc     s_col
        cmp     #COLS
        bcc     @on
        lda     s_h0            ; off the screen: skip its cells
        asl
        adc     s_di
        sta     s_di
        jmp     @ncol
@on:    lda     tmp
        clc
        adc     swl
        sta     s_wx
        lda     #0
        sta     s_pm
        sta     s_pb
        sta     s_rr
@cell:  lda     s_rr
        cmp     s_h0
        bcs     @zero
        ldy     s_di
@dm:    lda     $FFFF,y
        ldx     smir
        beq     @m1
        tax
        lda     mirror,x
@m1:    sta     s_cm
        iny
@db:    lda     $FFFF,y
        ldx     smir
        beq     @m2
        tax
        lda     mirror,x
@m2:    sta     s_cb
        iny
        sty     s_di
        jmp     @sh
@zero:  lda     #0
        sta     s_cm
        sta     s_cb
@sh:    lda     s_pm            ; (this cell : the one above) << shift
        sta     tlo
        lda     s_cm
        ldx     s_sh
        beq     @s1
@l1:    asl     tlo
        rol
        dex
        bne     @l1
@s1:    eor     #$FF
        sta     s_om
        lda     s_pb
        sta     tlo
        lda     s_cb
        ldx     s_sh
        beq     @s2
@l2:    asl     tlo
        rol
        dex
        bne     @l2
@s2:    sta     s_ob
        lda     s_cm
        sta     s_pm
        lda     s_cb
        sta     s_pb
        lda     s_r
        clc
        adc     s_rr
        cmp     #PROWS
        bcs     @skip
        adc     #>wc
        sta     @a+2
        sta     @w+2
        ldx     s_wx
@a:     lda     wc,x
        and     s_om
        ora     s_ob
@w:     sta     wc,x
        inc     ncells
@skip:  inc     s_rr
        lda     s_rr
        cmp     s_hn
        bcs     *+5
        jmp     @cell
@ncol:  inc     s_cc
        lda     s_cc
        cmp     s_w
        bcs     @mark
        jmp     @col
@mark:  lda     #0              ; mark the rows for comparing
        sta     s_rr
@mr:    lda     s_r
        clc
        adc     s_rr
        cmp     #PROWS
        bcs     @mn
        tay
        lda     s_c0
        jsr     mark1
        lda     s_c1
        jsr     mark1
@mn:    inc     s_rr
        lda     s_rr
        cmp     s_hn
        bcc     @mr
        rts

.else
; ---- the sprites, drawn by the terminal --------------------------------------------
; Each object has a slot in the terminal's sprite layer (MOS: 15, on top;
; object X: X).  Each frame only what changed is sent: MOVE (5 bytes) when
; only the place did, PICTURE or FLAGS when only that did, else PLACE; HIDE
; when it went.  sl_* hold what the terminal was last told.
hw_sprites:
        ldx     #NOBJ-1
@l:     stx     hw_i
        lda     o_kind,x
        bne     *+5
        jmp     @off
        cpx     #O_MOS
        bne     @ob
        jsr     mos_frame
        jmp     @fr
@ob:    jsr     obj_frame
@fr:    bcc     *+5
        jmp     @off
        sta     hw_n
        ldx     hw_i
        sec                     ; x on the wire: x - scroll * 2 + 32 (0 .. 255)
        lda     o_xl,x
        sbc     sc2
        sta     tmp
        lda     o_xh,x
        sbc     sc2+1
        sta     tmp+1
        clc
        lda     tmp
        adc     #32
        sta     hw_x
        lda     tmp+1
        adc     #0
        beq     *+5
        jmp     @off
        lda     o_y,x           ; y: the view starts at screen pixel 8, + 32
        bpl     @y
        cmp     #$D8            ; (above the view by more than 40: off)
        bcs     *+5
        jmp     @off
@y:     clc
        adc     #40
        sta     hw_y
        lda     smir
        and     #1
        sta     hw_f
        lda     sl_on,x         ; showing already?
        beq     @place
        lda     hw_n
        cmp     sl_n,x
        bne     @pic
        lda     hw_f
        cmp     sl_f,x
        bne     @flags
        lda     hw_x            ; the same picture: moved?
        cmp     sl_x,x
        bne     @move
        lda     hw_y
        cmp     sl_y,x
        bne     @move
        jmp     @n
@pic:   lda     hw_f            ; a new picture (only)?
        cmp     sl_f,x
        bne     @place
        jsr     @same_xy
        bne     @place
        lda     #SPR_PIC
        jsr     spr_cmd
        lda     hw_n
        jsr     putc
        jmp     @keep
@flags: jsr     @same_xy        ; turned round (only)?
        bne     @place
        lda     #SPR_FLAGS
        jsr     spr_cmd
        lda     hw_f
        jsr     putc
        jmp     @keep
@move:  lda     #SPR_MOVE
        jsr     spr_cmd
        jmp     @xy
@place: lda     #SPR_PLACE
        jsr     spr_cmd
        lda     hw_n
        jsr     putc
        lda     hw_x
        jsr     putc
        lda     hw_y
        jsr     putc
        lda     hw_f
        jsr     putc
        jmp     @keep
@xy:    lda     hw_x
        jsr     putc
        lda     hw_y
        jsr     putc
@keep:  ldx     hw_i            ; what the terminal shows now
        lda     #1
        sta     sl_on,x
        lda     hw_n
        sta     sl_n,x
        lda     hw_x
        sta     sl_x,x
        lda     hw_y
        sta     sl_y,x
        lda     hw_f
        sta     sl_f,x
        jmp     @n
@off:   ldx     hw_i            ; not drawn: hide it if it shows
        lda     sl_on,x
        beq     @n
        lda     #0
        sta     sl_on,x
        lda     #SPR_HIDE
        jsr     spr_cmd
@n:     ldx     hw_i
        dex
        bmi     @r
        jmp     @l
@r:     rts
@same_xy:                       ; Z set if object hw_i's place is unchanged
        ldx     hw_i
        lda     hw_x
        cmp     sl_x,x
        bne     @s
        lda     hw_y
        cmp     sl_y,x
@s:     rts

; A tile in view changed (screen column tc_c, -3..79; htr): note it, on the
; wire (x tc_c * 2 + 32, y htr * 8 + 40), up to TCH_MAX a frame (more: $FF).
; The terminal keeps the background under a sprite by itself, and a tile
; drawn under one could leave its old pixels behind there when the sprite
; moves off; so the sprites over it are hidden (at once, not held) before
; the tile is drawn, and placed again in the same frame.
.if UNC_TILES
TCH_MAX         = 4
note_tile:
        ldx     tch_n
        cpx     #TCH_MAX
        bcs     @full
        lda     tc_c
        asl
        clc
        adc     #32
        sta     tch_x,x
        lda     htr
        asl
        asl
        asl
        adc     #40
        sta     tch_y,x
        inc     tch_n
        rts
@full:  lda     #$FF
        sta     tch_n
        rts

; before the frame: hide each shown sprite (16 x 16 at most) near a changed
; tile (8 x 8; x with 4 pixels to spare each side for this frame's scroll),
; and when the view scrolls, those over the columns that come in on the right
; (up to 3: screen x 139-159), or all of them if the view is redrawn instead
unc_tiles:
        lda     scrolled
        beq     @sc
        lda     noscroll
        beq     @sc
        lda     #$FF
        sta     tch_n
@sc:    lda     tch_n
        ora     scrolled
        bne     *+3
        rts
        ldx     #NOBJ-1
@o:     stx     hw_i
        lda     sl_on,x
        beq     @n
        lda     scrolled
        beq     @nosc
        lda     sl_x,x
        cmp     #139+32
        bcc     @nosc
        cmp     #160+32
        bcc     @hide
@nosc:  ldy     tch_n
        beq     @n
        bmi     @hide           ; (too many: all of them)
        dey
@t:     lda     tch_x,y         ; tile x - 19 <= sprite x <= tile x + 11
        sec
        sbc     #19
        cmp     sl_x,x
        beq     @x1
        bcs     @nt
@x1:    lda     tch_x,y
        clc
        adc     #11
        cmp     sl_x,x
        bcc     @nt
        lda     tch_y,y         ; tile y - 15 <= sprite y <= tile y + 7
        sec
        sbc     #15
        cmp     sl_y,x
        beq     @y1
        bcs     @nt
@y1:    lda     tch_y,y
        clc
        adc     #7
        cmp     sl_y,x
        bcs     @hide
@nt:    dey
        bpl     @t
        bmi     @n
@hide:  lda     #0
        sta     sl_on,x
        lda     #SPR_HIDE
        jsr     spr_cmd
@n:     ldx     hw_i
        dex
        bpl     @o
        lda     #0
        sta     tch_n
        rts
.endif

; ---- pacing: one frame at a time --------------------------------------------
; After each frame IDENTIFY (1C 0C) goes out; the terminal answers S P 1 when
; it has worked through everything before it.  The next frame waits for that
; (any one of the three characters; up to ASK_MS ms), so the terminal never
; falls behind and its receive buffer never fills.  The 6502 works out the
; next frame meanwhile, so usually there is nothing left to wait for.
ASK_MS          = 150
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
        beq     @miss
@chk:   lda     rp_got
        beq     @l
@r:     rts
@miss:  inc     rp_miss         ; (shown at GAME OVER)
        rts

; ---- GAME OVER: the terminal's STATUS (1C 0D; the reply is "ST", then the
; bytes lost and the receive buffer's peak since the last STATUS, in hex:
; 2 and 4 digits), and the replies to IDENTIFY that didn't come in time.
; A terminal without STATUS doesn't answer: then nothing is shown.
st_show:
        lda     #0
        sta     rp_on
        lda     #<stq_txt
        ldy     #>stq_txt
        jsr     print
        lda     #250            ; wait for the T (it may have work to finish)
        sta     rp_t
@w:     jsr     getc
        bcs     @c
@w1:    lda     #1
        jsr     delay_ms
        dec     rp_t
        bne     @w
        rts
@c:     cmp     #'T'
        bne     @w1
        ldx     #0
@d:     stx     hl_x
        lda     #50
        sta     rp_t
@g:     jsr     getc
        bcs     @s
        lda     #1
        jsr     delay_ms
        dec     rp_t
        bne     @g
        rts
@s:     ldx     hl_x
        sta     st_dig,x
        inx
        cpx     #6
        bne     @d
        lda     #<st1_txt
        ldy     #>st1_txt
        jsr     print
        lda     st_dig
        jsr     putc
        lda     st_dig+1
        jsr     putc
        lda     #<st2_txt
        ldy     #>st2_txt
        jsr     print
        ldx     #2
@p:     lda     st_dig,x
        jsr     putc
        inx
        cpx     #6
        bne     @p
        lda     #<st3_txt
        ldy     #>st3_txt
        jsr     print
        lda     rp_miss
        jmp     prhex

; ---- healing: changed tiles are sent again ------------------------------------
; The terminal keeps the background under a sprite itself.  If a byte is lost
; or the terminal gets a cell under a sprite wrong, a changed tile (a bit
; taken under MOS, a block bumped) could keep old pixels.  So HEAL_T frames
; after a tile changes, once no sprite covers it, its 8 characters are sent
; again (about 20 bytes).
HEAL_N          = 6
HEAL_T          = 10
heal_add:                       ; tile htc, htr changed (A, X, Y kept)
        pha
        txa
        pha
        ldx     #HEAL_N-1
@f:     lda     hl_t,x
        beq     @put
        lda     hl_c,x          ; (the same tile again: start again)
        cmp     htc
        bne     @nx
        lda     hl_r,x
        cmp     htr
        beq     @put
@nx:    dex
        bpl     @f
        bmi     @r              ; (full: never mind)
@put:   lda     htc
        sta     hl_c,x
        lda     htr
        sta     hl_r,x
        lda     #HEAL_T
        sta     hl_t,x
@r:     pla
        tax
        pla
        rts

heal_tick:
        ldx     #HEAL_N-1
@l:     lda     hl_t,x
        beq     @n
        dec     hl_t,x
        bne     @n
        stx     hw_i
        jsr     heal_one
        ldx     hw_i
@n:     dex
        bpl     @l
        rts

; tile hl_*,X is due: if it is in view and no sprite shows over it, mark its
; characters as unknown on the screen (sh) and compare them again
heal_one:
        lda     hl_c,x          ; on the wire: x = column * 8 - scroll * 2 + 32
        sta     hl_x
        lda     #0
        sta     hl_x+1
        asl     hl_x
        rol     hl_x+1
        asl     hl_x
        rol     hl_x+1
        asl     hl_x
        rol     hl_x+1
        sec
        lda     hl_x
        sbc     sc2
        sta     hl_x
        lda     hl_x+1
        sbc     sc2+1
        beq     *+5              ; (out of view, or partly: never mind)
        jmp     @r
        lda     hl_x
        cmp     #160 - 7
        bcc     *+5
        jmp     @r
        adc     #32
        sta     hl_x
        lda     hl_r,x          ; y = row * 8 + 40
        asl
        asl
        asl
        adc     #40
        sta     hl_x+1
        ldy     #NOBJ-1         ; a sprite over it (16 x 16 at most, 2 to spare)?
@s:     lda     sl_on,y
        beq     @ns
        lda     hl_x
        sec
        sbc     #17
        cmp     sl_x,y
        beq     @x1
        bcs     @ns
@x1:    lda     hl_x
        clc
        adc     #9
        cmp     sl_x,y
        bcc     @ns
        lda     hl_x+1
        sec
        sbc     #17
        cmp     sl_y,y
        beq     @y1
        bcs     @ns
@y1:    lda     hl_x+1
        clc
        adc     #9
        cmp     sl_y,y
        bcs     @later
@ns:    dey
        bpl     @s
        lda     hl_r,x          ; the two rows of sh: the characters not known
        asl
        clc
        adc     #>sh
        sta     @a+2
        sta     @b+2
        adc     #1
        sta     @c+2
        sta     @d+2
        lda     hl_c,x
        asl
        asl
        tay
        lda     #4
        sta     hl_x
@a:     lda     sh,y
        eor     #$FF
@b:     sta     sh,y
@c:     lda     sh,y
        eor     #$FF
@d:     sta     sh,y
        iny
        dec     hl_x
        bne     @a
        lda     hl_c,x          ; and compared (sent) again
        sta     htc
        lda     hl_r,x
        sta     htr
        jmp     tile_changed
@later: lda     #3              ; covered: try again a little later
        sta     hl_t,x
@r:     rts

; send 1C, command A and the slot of object hw_i (MOS: 15)
spr_cmd:pha
        lda     #TC_SPR
        jsr     putc
        pla
        jsr     putc
        lda     hw_i
        bne     @s
        lda     #15
@s:     jmp     putc


; at start: is the sprite layer there?  Then send it the pictures (SMBSPR.SMB,
; loaded into wc and sent as it is: DEFINE commands).  Without it, a word,
; and back to the boot menu.
spr_setup:
        jsr     flush_in
        lda     #<ident_txt     ; IDENTIFY: the terminal answers S P 1
        ldy     #>ident_txt
        jsr     print
        ldx     #0              ; wait up to about 200 ms
@w:     stx     tmp4
        lda     #1
        jsr     delay_ms
        jsr     getc
        bcs     @got
        ldx     tmp4
        inx
        cpx     #200
        bne     @w
        jmp     @none
@got:   cmp     #'S'
        bne     @none
        jsr     @next
        cmp     #'P'
        bne     @none
        jsr     @next
        cmp     #'1'
        bne     @none
        lda     SBC_LOAD        ; the pictures from the disk
        cmp     #$4C
        bne     @nofile
        lda     #<spr_blk
        ldy     #>spr_blk
        jsr     SBC_LOAD
        bcs     @nofile
        stx     tmp             ; X/Y: its length
        sty     tmp+1
        lda     #<wc
        sta     @rd+1
        lda     #>wc
        sta     @rd+2
@s:     lda     tmp
        ora     tmp+1
        beq     @done
@rd:    lda     $FFFF
        jsr     SBC_CHROUT
        inc     @rd+1
        bne     @c
        inc     @rd+2
@c:     lda     tmp
        bne     @d
        dec     tmp+1
@d:     dec     tmp
        jmp     @s
@done:  rts
@next:  ldx     #50             ; the next character, within about 50 ms
@nw:    stx     tmp4
        jsr     getc
        bcs     @nr
        lda     #1
        jsr     delay_ms
        ldx     tmp4
        dex
        bne     @nw
        lda     #0
@nr:    rts
@nofile:lda     #<nospr2_txt
        ldy     #>nospr2_txt
        jmp     @say
@none:  lda     #<nospr_txt
        ldy     #>nospr_txt
@say:   pha
        tya
        pha
        lda     #<cls_txt
        ldy     #>cls_txt
        jsr     print
        pla
        tay
        pla
        jsr     print
        lda     #<anykey_txt
        ldy     #>anykey_txt
        jsr     print
@k:     jsr     menu_key
        jmp     exit_game
.endif

; A = MOS's picture (smir: mirrored); carry set if he isn't drawn
mos_frame:
        lda     facing
        sta     smir
        lda     mstate
        cmp     #MS_IN
        bne     *+5
        jmp     @hide
        cmp     #MS_DEAD
        bne     @a
        lda     #0
        sta     smir
        lda     #SP_MOS_DEAD
        clc
        rts
@a:     lda     inv_t           ; blinking
        and     #2
        beq     *+5
        jmp     @hide
        lda     oc_t            ; overclocked: flashing
        beq     @a2
        cmp     #40             ; (slower at the end: a warning)
        lda     frame
        bcs     @a1
        lsr
@a1:    and     #2
        beq     *+5
        jmp     @hide
@a2:
        ldy     #SP_MOS_STAND
        lda     big
        beq     @s
        ldy     #SP_BIG_STAND
        lda     fire
        beq     @s
        ldy     #SP_FIRE_STAND
@s:     lda     duck            ; ducking: the next picture along
        beq     @s2
        lda     mduck_pic,y
        clc
        rts
@s2:    sty     tmp
        lda     mstate
        cmp     #MS_FLAG
        beq     @st
        cmp     #MS_RESET
        beq     @st
        lda     onground
        beq     @jump
        lda     o_vxh           ; walking: the legs change every 4 pixels
        bpl     @p
        sec
        lda     #0
        sbc     o_vxl
        tay
        lda     #0
        sbc     o_vxh
        jmp     @add
@p:     ldy     o_vxl
        cpy     #0
        bne     @add
        cmp     #0
        beq     @st
@add:   sta     tmp2
        tya
        clc
        adc     anim
        sta     anim
        lda     anim+1
        adc     tmp2
        sta     anim+1
        and     #4
        lsr
        lsr
        clc
        adc     #1
        adc     tmp
        clc
        rts
@jump:  lda     lv_flags        ; swimming: legs together, apart for a kick
        and     #2
        beq     @j2
        lda     sw_t
        bne     @st
        ldy     #SP_MOS_SWIM
        lda     big
        beq     @sw
        iny
        lda     fire
        beq     @sw
        iny
@sw:    tya
        clc
        rts
@j2:    lda     #3
        clc
        adc     tmp
        clc
        rts
@st:    lda     tmp
        clc
        rts
@hide:  sec
        rts

; A = object X's picture (smir: mirrored); carry set if it isn't drawn
obj_frame:
        lda     #0
        sta     smir
        lda     o_kind,x
        cmp     #K_BUG
        bne     @1
        lda     frame           ; (the legs: every 8 frames)
        lsr
        lsr
        lsr
        and     #1
        clc
        adc     #SP_AND1
        rts
@1:     cmp     #K_SHELLY
        bne     @2
        lda     frame           ; (every 4)
        lsr
        lsr
        and     #1
        clc
        adc     #SP_OR1
        rts
@2:     cmp     #K_FIRE
        bne     @3
        lda     frame
        lsr
        and     #1
        clc
        adc     #SP_FIREBALL1
        rts
@3:     cmp     #K_DRAGON
        bne     @4
        lda     dr_flash        ; (blinks when hit)
        and     #2
        beq     @d
        sec
        rts
@d:     lda     dr_face
        sta     smir
        lda     frame
        lsr
        lsr
        lsr
        and     #1
        clc
        adc     #SP_DRAGON1
        rts
@4:     cmp     #K_BREATH
        bne     @5
        lda     o_vxh,x         ; (going right: mirrored)
        eor     #$80
        asl
        lda     #0
        rol
        sta     smir
        lda     #SP_BREATH
        clc
        rts
@5:     cmp     #K_FISH
        bne     @6
        lda     o_vxh,x         ; (going right: mirrored)
        eor     #$80
        asl
        lda     #0
        rol
        sta     smir
        lda     frame
        lsr
        lsr
        lsr
        and     #1
        clc
        adc     #SP_FISH1
        rts
@6:     cmp     #K_FAN
        bne     @7
        lda     frame
        lsr
        and     #1
        clc
        adc     #SP_FAN1
        rts
@7:     cmp     #K_SHELL        ; a shell about to come out: its legs show
        bne     @8
        lda     o_r,x
        cmp     #REVIVE - 40
        bcc     @8s
        lda     frame
        and     #4
        beq     @8s
        lda     #SP_OR1
        clc
        rts
@8s:    lda     #K_SHELL
@8:     tay
        lda     kind_pic,y
        clc
        rts

; ---- send what changed ------------------------------------------------------------
; Compare the view (wc) with what the terminal shows (sh) and send the
; characters that differ: the marked range of each row, or every row after
; the view jumped (or scrolled, when the terminal doesn't scroll it).  A run of the same character goes once, with
; the repeat count.  Rows of sky (no tiles, no sprites) that the terminal
; already shows empty are skipped.
present:
        lda     scroll          ; (screen column 0 = world column pbase)
        sta     pbase
present_at:
        lda     attr            ; block graphics (keep a repeat count it has)
        cmp     #$FF
        beq     @gm
        tax
        bmi     @g
@gm:    jsr     gfx_mode
        lda     #1
        sta     cur_rep
@g:     lda     #$FF
        sta     cur_r
        lda     #0
        sta     prow
@row:   ldx     prow
        lda     fullcmp
        beq     @part
        lda     #0              ; all of it, unless it is empty sky shown empty
        sta     p_c0
        lda     #COLS
        sta     blk_end
        lda     dmin,x
        cmp     #$FF
        bne     @ne
        txa
        lsr
        tay
        lda     trow,y
        bne     @ne
        lda     #1              ; (it will be empty once compared)
        ldy     sh_empty,x
        sta     sh_empty,x
        bne     @nrow1
        beq     @scan
@ne:    lda     #0
        sta     sh_empty,x
        beq     @scan
@nrow1: jmp     @nrow
@part:  lda     dmin,x
        cmp     #$FF
        beq     @nrow1
        sta     p_c0
        lda     #0
        sta     sh_empty,x
        lda     dmax,x
        clc
        adc     #1
        sta     blk_end
@scan:  inc     nrows_seen
        lda     blk_end
        sec
        sbc     p_c0
        clc
        adc     ncmp
        sta     ncmp
        bcc     @nc
        inc     ncmp+1
@nc:    txa
        clc
        adc     #>wc
        sta     @fb+2
        sta     @fb1+2
        sta     @fb2+2
        sta     @fb3+2
        sta     @f2+2
        txa
        clc
        adc     #>sh
        sta     @sb+2
        sta     @sb1+2
        sta     @sb2+2
        sta     @sb3+2
        sta     @s2+2
        sta     @sw+2
        lda     p_c0            ; X: the screen column, Y: its place in wc
        tax
        clc
        adc     pbase
        tay
@c:                             ; (4 at a time: it may look a little past
@fb:    lda     wc,y            ;  the end, which does no harm)
@sb:    cmp     sh,y
        bne     @diff
        iny
        inx
@fb1:   lda     wc,y
@sb1:   cmp     sh,y
        bne     @diff
        iny
        inx
@fb2:   lda     wc,y
@sb2:   cmp     sh,y
        bne     @diff
        iny
        inx
@fb3:   lda     wc,y
@sb3:   cmp     sh,y
        bne     @diff
        iny
        inx
        cpx     blk_end
        bcc     @c
        jmp     @nrow
@diff:  cpx     #COLS
        bcc     @dok
        jmp     @nrow
@dok:   sta     val
        stx     pcol
        sty     pwy
        lda     #1              ; the run of this character, and how far
        sta     need            ; into it the last changed one is
        sta     tmp4            ; (k)
        inx
        iny
@rl:    cpx     #COLS
        bcs     @rend
        lda     tmp4
        cmp     #15
        bcs     @rend
@f2:    lda     wc,y
        cmp     val
        bne     @rend
@s2:    cmp     sh,y
        beq     @same
        lda     tmp4
        clc
        adc     #1
        sta     need
        bne     @rs1
@same:  lda     tmp4            ; 3 unchanged since the last change: enough
        sec
        sbc     need
        cmp     #2
        bcs     @rend
@rs1:   inx
        iny
        inc     tmp4
        bne     @rl
@rend:  lda     tmp4
        sta     runl
        lda     cur_rep         ; how many: the count already set if it fits,
        cmp     need            ; one for a single change, else the run
        bcc     @nofit
        cmp     runl
        beq     @setk
        bcc     @setk
@nofit: lda     need
        cmp     #1
        beq     @setk
        cmp     #4
        bcs     @whole
        lda     cur_rep
        cmp     #1
        beq     @setk
@whole: lda     runl
@setk:  sta     kcnt
        lda     cur_r           ; the cursor
        cmp     prow
        bne     @goto
        lda     pcol
        cmp     cur_c
        beq     @put
        ldx     pcol
        jsr     setcol
        jmp     @put
@goto:  ldx     pcol
        lda     prow
        clc
        adc     #PF_ROW
        tay
        jsr     gotoxy
        lda     prow
        sta     cur_r
@put:   lda     kcnt
        jsr     set_rep
        lda     val
        jsr     putblk
        ldy     pwy             ; the terminal shows them now
        ldx     kcnt
        lda     val
@sw:    sta     sh,y
        iny
        dex
        bne     @sw
        lda     pcol
        clc
        adc     kcnt
        tax
        stx     cur_c
        cpx     #COLS
        bcs     @end
        cpx     blk_end
        bcs     @nrow
        jmp     @c
@end:   lda     #$FF            ; the cursor wrapped: position unknown
        sta     cur_r
@nrow:  ldx     prow
        lda     #$FF
        sta     dmin,x
        lda     #0
        sta     dmax,x
        inc     prow
        lda     prow
        cmp     #PROWS
        beq     @done
        jmp     @row
@done:  lda     #1              ; (back to single characters for text)
        jmp     set_rep

; ============================================================================
; data
; ============================================================================
        .segment "RODATA"
mh_tab: .byte   8, 5, 16, 8     ; MOS's height: small, ducking; big, ducking
mduck_pic = * - SP_MOS_STAND    ; (by the standing picture: its duck)
        .byte   SP_MOS_DUCK
        .res    SP_BIG_STAND - SP_MOS_STAND - 1
        .byte   SP_BIG_DUCK
        .res    SP_FIRE_STAND - SP_BIG_STAND - 1
        .byte   SP_FIRE_DUCK
kind_pic:                       ; (the kinds that don't move their legs)
        .byte   0, 0, SP_AND1, SP_AND_FLAT, SP_OR1, SP_OR_SHELL, SP_MUSH, SP_COINPOP, SP_ONEUP, SP_FLOWER
        .byte   0, 0, 0, SP_OC, 0, 0, SP_CLOUD, SP_PRINCESS
en_kind:                        ; the level's enemy types 1 .. 9 (3: KIL, apart;
        .byte   K_BUG, K_SHELLY, 0, K_FISH, K_FAN, K_CLOUD, K_PRINCESS, K_FAN, K_FISH
wave:                           ; 8: a fan that flies high, 9: a wavy fish)
        .byte   0, 2, 5, 7, 8, 10, 11, 12, 12, 12, 11, 10, 8, 7, 5, 2
        .byte   0, <-2, <-5, <-7, <-8, <-10, <-11, <-12, <-12, <-12, <-11, <-10, <-8, <-7, <-5, <-2
kil_spd:.byte   $40, $50, $60, $70, $80     ; KIL by world: pacing speed,
kil_jmp:.byte   50, 40, 32, 26, 20          ; ... frames between jumps (+0..63),
kil_brt:.byte   45, 38, 32, 26, 22          ; ... between fire (+0..31),
kil_jv: .byte   $FC, $FC, $FB, $FB, $FB     ; ... and how high (the speed up)
.if !SOFT_SPRITES
spr_blk:                        ; SBC_LOAD's parameters: SMBSPR.SMB into wc
        .word   wc
        .word   PROWS * 256
        .byte   "SMBSPR.SMB", 0
ident_txt:
        .byte   TC_SPR, SPR_IDENT, TERM
stq_txt:
        .byte   TC_SPR, SPR_STATUS, TERM
st1_txt:
        .byte   TC_ROW, 15, TC_COL, 24, "TERMINAL: LOST ", TERM
st2_txt:
        .byte   "  PEAK ", TERM
st3_txt:
        .byte   "  MISSED ", TERM
hold_txt:
        .byte   TC_SPR, SPR_HOLD, TERM
show_txt:
        .byte   TC_SPR, SPR_SHOW, TERM
hideall_txt:
        .byte   TC_SPR, SPR_HIDEALL, TERM
clip_txt:                       ; sprites only in the view: text rows 2-23
        .byte   TC_SPR, SPR_CLIP, 2, 23, TERM
nospr_txt:
        .byte   TC_ROW, 8, TC_COL, 14, "THIS SMB.BIN NEEDS THE TERMINAL'S SPRITE LAYER (CODE 1C)."
        .byte   TC_ROW, 10, TC_COL, 14, "THE TERMINAL DIDN'T ANSWER.  ON AN OLDER TERMINAL, OR ON"
        .byte   TC_ROW, 11, TC_COL, 14, "COMPOSITE VIDEO, RUN SMBSW.BIN INSTEAD.", TERM
nospr2_txt:
        .byte   TC_ROW, 8, TC_COL, 14, "NO SMBSPR.SMB ON THE DISK (THE PICTURES FOR THE TERMINAL),"
        .byte   TC_ROW, 10, TC_COL, 14, "OR NO SBC_LOAD IN THE ROM.  COPY SMBSPR.SMB TO THE DRIVE,"
        .byte   TC_ROW, 11, TC_COL, 14, "OR RUN SMBSW.BIN INSTEAD.", TERM
anykey_txt:
        .byte   TC_ROW, 14, TC_COL, 14, "PRESS A KEY.", TERM
.endif
load_blk:                       ; SBC_LOAD's parameters: WORLDn.SMB into wc
        .word   wc
        .word   PROWS * 256
load_name:
        .byte   "WORLD1.SMB", 0
.define FLAG_PTS 100, 200, 400, 500, 800, 1000, 2000, 3000, 4000, 5000
flag_pts_lo:                    ; 100 .. 5000 points by height
        .lobytes FLAG_PTS
flag_pts_hi:
        .hibytes FLAG_PTS

cls_txt:.byte   TC_ATTR, ATTR_TEXT, $1B, '[', 'r', TC_CLS, TC_CURSOR, 0, TERM
region_txt:                     ; scroll only text rows 3-24 (the view)
        .byte   $1B, '[', '3', ';', '2', '4', 'r', TERM
title_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 11, TC_COL, 4, "STOMP THE LOGIC GATES, GRAB THE FLOWER, PRESS RESET ON KIL THE DRAGON"
        .byte   TC_ROW, 12, TC_COL, 4, "THE FLOWER THROWS ELECTRONS, OC OVERCLOCKS, DOWN ON A PIPE: BONUS BITS"
        .byte   TC_ROW, 13, TC_COL, 20, "8 BITS MAKE A BYTE, $0C BYTES MAKE A LIFE"
        .byte   TC_ROW, 14, TC_COL, 7, "KEYS: D/A WALK (AGAIN: RUN)  S STOP+DUCK  W/SPACE JUMP  F FIRE"
        .byte   TC_ROW, 15, TC_COL, 13, "(OR THE ARROW KEYS)   P PAUSE   Q QUIT"
.if SOUND
        .byte   "   M SOUND"
.endif
        .byte   TC_ROW, 16, TC_COL, 7, "PAD:  LEFT/RIGHT WALK  DOWN DUCK  B RUN+FIRE  A JUMP (HOLD: HIGHER)"
        .byte   TC_ROW, 23, TC_COL, 23, "SPACE OR START: PLAY      Q: QUIT", TERM
hi_txt: .byte   "HIGH DATA ", TERM
status_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 0, TC_COL, 0, "DATA"
        .byte   TC_COL, 13, "BYTES"
        .byte   TC_COL, 33, "CELL"
        .byte   TC_COL, 45, "CYCLES"
        .byte   TC_COL, 59, "LIVES", TERM
world_txt:
        .byte   "CELL ", TERM
lives_txt:
        .byte   "MOS x ", TERM
paused_txt:
        .byte   RV_ON, " PAUSED ", RV_OFF, TERM
unpaused_txt:
        .byte   "        ", TERM
over_txt:
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 8, TC_COL, 31, RV_ON, "                  "
        .byte   TC_ROW, 9, TC_COL, 31, "    GAME  OVER    "
        .byte   TC_ROW, 10, TC_COL, 31, "                  "
        .byte   TC_ROW, 11, TC_COL, 31, " SPACE/A: AGAIN   "
        .byte   TC_ROW, 12, TC_COL, 31, " Q: TITLE         "
        .byte   TC_ROW, 13, TC_COL, 31, "                  ", RV_OFF, TERM
castle_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS
        .byte   TC_ROW, 8, TC_COL, 32, "THANK YOU, MOS!"
        .byte   TC_ROW, 11, TC_COL, 21, "BUT THE PRINCESS IS IN ANOTHER ROM ..."
        .byte   TC_ROW, 14, TC_COL, 26, "(KIL HAS BEEN RESET TO $FFFC)"
        .byte   TC_ROW, 17, TC_COL, 30, "ON TO THE NEXT CELL!", TERM
nodisk_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS
        .byte   TC_ROW, 8, TC_COL, 21, "MOS HAS RUN EVERY CELL THERE IS: NO"
        .byte   TC_ROW, 10, TC_COL, 21, "WORLD", TERM
noworld_txt:
        .byte   TC_ATTR, ATTR_TEXT, TC_CLS
        .byte   TC_ROW, 8, TC_COL, 18, "NO WORLD1.SMB ON THE DISK (OR NO SBC_LOAD IN THE ROM)."
        .byte   TC_ROW, 11, TC_COL, 14, "COPY THE WORLD FILES (WORLD1.SMB ... ) TO THE USB DRIVE.", TERM
nodisk2_txt:
        .byte   ".SMB ON THE DISK (OR NO SBC_LOAD IN THE ROM)."
        .byte   TC_ROW, 14, TC_COL, 28, "JMP $0500 ... AROUND AGAIN!", TERM
kil_txt:
        .byte   TC_ROW, 1, TC_COL, 9, "KIL THE DRAGON HALTS THE CPU. PRESS RESET (5 ELECTRONS HELP)", TERM
end_txt:                        ; (over the castle, with her in view)
        .byte   TC_ATTR, ATTR_TEXT
        .byte   TC_ROW, 5, TC_COL, 22, "HI MOS! I'M PRINCESS GRAPHICS CARD."
        .byte   TC_ROW, 7, TC_COL, 22, "THANK YOU FOR RESCUING ME!"
        .byte   TC_ROW, 9, TC_COL, 12, "HOPEFULLY WE CAN MAKE BETTER GRAPHICS IN THE FUTURE."
        .byte   TC_ROW, 12, TC_COL, 33, "- THE END -", TERM
bye_txt:.byte   TC_ATTR, ATTR_TEXT, $1B, '[', 'r', TC_CLS, TC_CURSOR, '_', TERM
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD   (G: USE THE GAMEPAD)", TERM
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD    (G: USE THE KEYBOARD)", TERM

; ============================================================================
; variables (not in the file; cleared at start)
; ============================================================================
        .segment "BSS"
bss_start:
.if SOUND
snd_a:      .res 1
snd_x:      .res 1
snd_y:      .res 1
.endif
ctrl:       .res 1
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
attr:       .res 1
cur_rep:    .res 1
nbytes:     .res 2              ; bytes sent this frame
ncells:     .res 1              ; sprite cells drawn
ncmp:       .res 2              ; characters compared
nrows_seen: .res 1
used:       .res 1
esc_st:     .res 1
quit:       .res 1
frame:      .res 1
score:      .res 3              ; BCD, low byte first
hiscore:    .res 3
lives:      .res 1
world:      .res 1
lvl:        .res 1              ; 0.. in the world
hud_dirty:  .res 1
full:       .res 1              ; draw the whole view this frame
lv_w:       .res 1              ; (these six in this order: from the level)
lv_sx:      .res 1
lv_sy:      .res 1
lv_time:    .res 2
lv_flags:   .res 1              ; 1: a castle (RESET and KIL at the end), 2: under
                                ; the coolant, 4: the last (the princess)
lv_room:    .res 1              ; the bonus room's first column (0: none)
lv_out:     .res 1              ; ... and the pipe it comes back out of
wsrc:       .res 1              ; which world's file: WORLDwsrc.SMB
fire:       .res 1              ; MOS has the fire flower
fire_req:   .res 1
dr_hp:      .res 1              ; KIL: electrons left to beat it
dr_t:       .res 1              ; frames to its next jump
dr_bt:      .res 1              ; ... and its next fire
dr_face:    .res 1              ; 1: facing right
dr_flash:   .res 1
dr_dead:    .res 1
dr_home:    .res 2
br_c:       .res 1              ; the bridge's next tile to fall
br_w:       .res 1
smir:       .res 1              ; drawing: mirrored
.if !SOFT_SPRITES
hw_i:       .res 1              ; the terminal's sprites: the object,
hw_n:       .res 1              ;   its picture, place, flags now
hw_x:       .res 1
hw_y:       .res 1
hw_f:       .res 1
sl_on:      .res NOBJ           ;   ... and what the terminal shows
sl_n:       .res NOBJ
sl_x:       .res NOBJ
sl_y:       .res NOBJ
sl_f:       .res NOBJ
rp_on:      .res 1              ; IDENTIFY sent: S P 1 are its reply, not keys
rp_got:     .res 1              ; ... and the reply came
rp_t:       .res 1              ; ms left to wait for it
rp_miss:    .res 1              ; replies that didn't come in time
hl_c:       .res HEAL_N         ; tiles to send again (world column, row)
hl_r:       .res HEAL_N
hl_t:       .res HEAL_N         ;   in this many frames (0: free)
hl_x:       .res 2
st_dig:     .res 6              ; STATUS: its digits
.if UNC_TILES
tch_n:      .res 1              ; tiles changed in view this frame ($FF: many)
tch_x:      .res TCH_MAX        ;   where, on the wire
tch_y:      .res TCH_MAX
.endif
.endif
s_sh:       .res 1
s_h0:       .res 1
s_cc:       .res 1
s_wx:       .res 1
s_pm:       .res 1
s_pb:       .res 1
s_rr:       .res 1
s_cm:       .res 1
s_cb:       .res 1
s_om:       .res 1
s_ob:       .res 1
tlo:        .res 1
time:       .res 2              ; BCD
time_div:   .res 1
en_i:       .res 1
scroll:     .res 2              ; the view's left edge, in characters
sc2:        .res 2              ; ... in pixels
max_sc:     .res 2
scrolled:   .res 1
big:        .res 1
mh:         .res 1              ; MOS's height: 8 or 16
onground:   .res 1
facing:     .res 1              ; 0 right, 1 left
anim:       .res 2
inv_t:      .res 1
mstate:     .res 1
mtimer:     .res 1
pole_c:     .res 1
flag_r:     .res 1
in_dir:     .res 1
in_run:     .res 1
hold:       .res 1
jump_buf:   .res 1
kdir:       .res 1
krun:       .res 1
khold:      .res 1
vmax:       .res 2
sidex:      .res 1
ptx:        .res 2
pty:        .res 1
htc:        .res 1
htr:        .res 1
tcol:       .res 1
tc_c:       .res 1
tc_row:     .res 1
tc_code:    .res 1
tc_n:       .res 1
ox_f:       .res 1
ox_l:       .res 1
ox_h:       .res 1
o_kind:     .res NOBJ
o_xf:       .res NOBJ
o_xl:       .res NOBJ
o_xh:       .res NOBJ
o_yf:       .res NOBJ
o_y:        .res NOBJ
o_vxl:      .res NOBJ
o_vxh:      .res NOBJ
o_vyl:      .res NOBJ
o_vyh:      .res NOBJ
o_t:        .res NOBJ
o_r:        .res NOBJ           ; a still shell: frames until it's out; a fan: its
                                ; top; a wavy fish: its phase
g_cur:      .res 1
b_ph:       .res 1
b_half:     .res 1
s_col:      .res 1
s_w:        .res 1
s_wn:       .res 1
s_r:        .res 1
s_hn:       .res 1
s_c0:       .res 1
s_c1:       .res 1
s_di:       .res 1
ri:         .res 1
dobj:       .res 1
spf:        .res 1
sxl:        .res 1
sxh:        .res 1
sy:         .res 1
nrect:      .res 1
rc_cl:      .res NOBJ           ; last frame's sprites: world column, row, size
rc_ch:      .res NOBJ
rc_r:       .res NOBJ
rc_w:       .res NOBJ
rc_h:       .res NOBJ
trow:       .res MAPROWS        ; 0: a tile row with nothing in view
sh_empty:   .res PROWS          ; 1: the terminal shows the row empty
fullcmp:    .res 1
p_c0:       .res 1
pwy:        .res 1
g_end:      .res 1
g_x:        .res 1
tc_w:       .res 1
b_n:        .res 1
s_sc:       .res 1
swl:        .res 1
swh:        .res 1
sc_old:     .res 2
dmin:       .res PROWS          ; per row: the columns to compare ($FF: none)
dmax:       .res PROWS
blk_end:    .res 1
prow:       .res 1
pcol:       .res 1
cur_r:      .res 1
cur_c:      .res 1
val:        .res 1
need:       .res 1
runl:       .res 1
kcnt:       .res 1
tmp:        .res 2
tmp2:       .res 1
tmp3:       .res 1
tmp4:       .res 1
en_buf:     .res 256            ; the level's enemies: column, row, kind ... $FF
sd:         .res 1
mvbuf:      .res COLS
bits:       .res 1              ; bits picked up (8: a byte)
in_room:    .res 1              ; 1: in the bonus room
oc_t:       .res 1              ; overclocked: frames left
sw_t:       .res 1              ; swimming: frames of the kick's picture left
lv_wsave:   .res 1              ; (the level outside the bonus room)
sc_save:    .res 2
max_save:   .res 2
dr_spd:     .res 1              ; KIL, this world: pacing speed
dr_jb:      .res 1              ; ... jump wait
dr_bb:      .res 1              ; ... fire wait
dr_jv:      .res 1              ; ... jump speed (high byte, up)
bytes:      .res 1              ; bytes ($0C: a life)
pbase:      .res 1
svmin:      .res PROWS
svmax:      .res PROWS
duck:       .res 1              ; MOS is ducking
in_down:    .res 1
kduck:      .res 1
bss_end:

        .segment "BUFS"
map:        .res MAPROWS * 256  ; the level: a page a row, tile number * 4
wc:         .res PROWS * 256    ; the view as it should be (a page a row, by world column)
sh:         .res PROWS * 256    ; the view as the terminal shows it (by world column too)
