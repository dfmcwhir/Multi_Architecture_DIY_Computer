; ============================================================================
; doom2.s - "6502 DOOM2": the 6502 DOOM engine with a new picture and new
;           maps, for the 6502 SBC, CPU Rev2, on the PICO9918 card
;
;   build:  make.bat 4     run:  L DOOM2 0800   then   R
;   (MAP01.LVL .. MAP05.LVL on the drive; loaded with SBC_LOAD)
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  frames (1/60 s) a game frame takes at least: 6 = 10 a second
;   $0804  controls at start: 0 keyboard, 1 gamepad
;   $0805  sound at start: 0 on, 1 off (M switches)
;
; The engine (the ray caster, the things, doors, enemies, the sound) is the
; first DOOM's.  The picture is new (view.s): Graphics II, the view 240 x 144
; screen pixels drawn at their own resolution, 120 columns of 2 pixels;
; textured walls, things as 32 x 48 pictures scaled to their distance, the
; ceiling and floor fading to black; the gun is ECM2 sprites.  The art is
; gen_tables.py's, the maps mklevels.py's.  No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 6             ; frames a game frame (10 a second)

; ---- VRAM (Graphics II) --------------------------------------------------------------
V_PAT           = $0000         ; patterns, three thirds of 2K
V_COL           = $2000         ; colours, the same
V_NAME          = $3800         ; names (the view's laid out by cell column)
V_SATTR         = $3B00         ; sprite attributes (the gun)
V_SPR           = $1800         ; sprite patterns: plane 0; plane 1 at + $400
VDP_NAME        = V_NAME
P_FONT          = $60           ; third 3: character c is pattern c + $60
TXT_ROW         = 18            ; rows 18-23: text by name
C_VIEW          = $F1           ; (the bitmap's colours before a picture)
C_TEXT          = $A1           ; text in the bitmap: light grey on black
C_HUD           = $E1           ; the status lines' text: yellow on black

; ---- memory ----------------------------------------------------------------------
LEVEL_BUF       = $7900         ; the level file is loaded here (to $7EFF)
LEVEL_MAX       = $0600
MAP             = LEVEL_BUF + 64
THING_SRC       = LEVEL_BUF + 64 + 1024

; ---- game --------------------------------------------------------------------------
MAXT            = 32            ; things per level
HUD_STATS       = 19            ; the status lines (text rows)
HUD_KILLS       = 20
HUD_LEVEL       = 21
HUD_MSG         = 22
HUD_HELP        = 23
T_GRUNT         = 1
T_BRUTE         = 2
T_MEDKIT        = 3
T_AMMO          = 4
S_GONE          = 0             ; thing states
S_IDLE          = 1             ; (items use S_IDLE for "lying here")
S_CHASE         = 2
S_ATTACK        = 3
S_DEAD          = 4
TILE_DOOR       = 4
TILE_EXIT       = 5
RADIUS          = $40           ; the player's size, 1/4 tile
TERM            = $FF

; ============================================================================
        .segment "RODATA"
        .include "tables.inc"     ; constants and lookup tables (gen_tables.py)
        .segment "CODE"

        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  0               ; controls at start: 0 keyboard, 1 gamepad
mute_def:.byte  0               ; sound at start: 0 on, 1 off
ground: .byte   0               ; (spare)
        .byte   0               ; spare

SFX_SND         = 1             ; (sfx_snd, sfx_toggle)
        .include "ay/sfx.s"     ; music and effects on the AY-3-8910 card
        .include "lib/vdp.s"    ; the PICO9918 routines
        .include "view.s"       ; the picture

getc            = SBC_CHRIN     ; carry set = key in A

frame_idle:
        jmp     sfx_poll

; 16 bit Galois LFSR.  Returns a random byte in A.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait about A x 50 ms (3 frames each), dropping keys
delay_long:
        sta     tmp
@l:     lda     #3
        sta     wf_n
@f:     jsr     vdp_frame
        dec     wf_n
        bne     @f
        jsr     flush_in
        dec     tmp
        bne     @l
        rts

.macro MENU_IDLE
        jsr     vdp_frame
        jsr     rand
.endmacro

; ---- the game's pace: a frame takes at least speed / 60 s (the ROM's 60 Hz
; counter), the sound going on meanwhile
game_pace:
        jsr     sfx_poll
        jsr     SBC_TICKS
        sec
        sbc     last_tick
        cmp     speed
        bcc     game_pace
        jsr     SBC_TICKS
        sta     last_tick
        rts

; ============================================================================
; text
; ============================================================================
; text cursor: column X, row Y (0-31, 0-23)
t_at:   stx     t_col
        sty     t_row
        rts

; character A at the cursor, which moves on.  Preserves X, Y.
t_putc: stx     t_sx
        sty     t_sy
        sta     t_ch
        lda     t_row
        cmp     #TXT_ROW
        bcc     @bm
        ldx     t_col           ; the status lines: a name
        ldy     t_row
        jsr     vdp_at
        lda     t_ch
        clc
        adc     #P_FONT
        sta     VDP_DATA
        jmp     @next
@bm:    jsr     cell_addr       ; the bitmap: the letter's 8 bytes, and white
        lda     t_ca            ; on black
        sta     VDP_CTRL
        lda     t_ca+1
        ora     #$40
        sta     VDP_CTRL
        lda     t_ch            ; font + (c - $20) * 8
        sec
        sbc     #$20
        sta     t_fa
        lda     #0
        asl     t_fa
        rol
        asl     t_fa
        rol
        asl     t_fa
        rol
        clc
        adc     #>font
        sta     @f+2
        lda     t_fa
        clc
        adc     #<font
        sta     @f+1
        bcc     :+
        inc     @f+2
:       ldx     #0
@f:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #8
        bne     @f
        lda     t_ca
        sta     VDP_CTRL
        lda     t_ca+1
        ora     #$40 + >V_COL
        sta     VDP_CTRL
        lda     #C_TEXT
        ldx     #8
@c:     sta     VDP_DATA
        dex
        bne     @c
@next:  inc     t_col
        ldx     t_sx
        ldy     t_sy
        rts

; t_ca = the pattern address of cell t_col, t_row: rows 0-15 at third *
; $800 + col * 64 + (row & 7) * 8; rows 16-17 at $1000 + col * 16 +
; (row - 16) * 8
cell_addr:
        lda     t_row
        cmp     #16
        bcs     @low
        and     #7
        asl
        asl
        asl
        sta     t_ca
        lda     t_col           ; col * 64
        lsr
        lsr
        sta     t_ca+1
        lda     t_col
        asl
        asl
        asl
        asl
        asl
        asl
        ora     t_ca
        sta     t_ca
        lda     t_row
        and     #8              ; (third 1: + 8 pages)
        ora     t_ca+1
        sta     t_ca+1
        rts
@low:   and     #1
        asl
        asl
        asl
        sta     t_ca
        lda     t_col
        asl
        asl
        asl
        asl
        ora     t_ca
        sta     t_ca
        lda     t_col
        lsr
        lsr
        lsr
        lsr
        ora     #$10
        sta     t_ca+1
        rts

; print the string at A/Y (ended by TERM or 0).  Preserves nothing.
t_puts: sta     @r+1
        sty     @r+2
        ldy     #0
@r:     lda     $FFFF,y
        beq     @d
        cmp     #TERM
        beq     @d
        jsr     t_putc
        iny
        bne     @r
@d:     rts

; a table of texts: column, row, .word text ... $FF
t_table:sta     @rd+1
        sty     @rd+2
        ldx     #0
@l:     stx     tt_i
        jsr     @rd
        cmp     #$FF
        beq     @done
        sta     tt_c
        inx
        jsr     @rd
        tay
        ldx     tt_c
        jsr     t_at
        ldx     tt_i
        inx
        inx
        jsr     @rd
        pha
        inx
        jsr     @rd
        tay
        pla
        jsr     t_puts
        lda     tt_i
        clc
        adc     #4
        tax
        bne     @l
@done:  rts
@rd:    lda     $FFFF,x
        rts

; A in decimal, 3 places (spaces before)
pr_dec3:ldx     #' '
        stx     t_lead
        ldx     #0
@h:     cmp     #100
        bcc     @hd
        sbc     #100
        inx
        bne     @h
@hd:    pha
        txa
        beq     @h0
        ora     #'0'
        jsr     t_putc
        lda     #'0'
        sta     t_lead
        bne     @t
@h0:    lda     #' '
        jsr     t_putc
@t:     pla
        ; (on into the tens and ones, with leading t_lead)
        ldx     #0
@tl:    cmp     #10
        bcc     @td
        sbc     #10
        inx
        bne     @tl
@td:    pha
        txa
        bne     @tn
        lda     t_lead
        jmp     @tp
@tn:    ora     #'0'
@tp:    jsr     t_putc
        pla
        ora     #'0'
        jmp     t_putc

; A in decimal, 2 places
pr_dec2:ldx     #0
@t:     cmp     #10
        bcc     @d
        sbc     #10
        inx
        bne     @t
@d:     pha
        txa
        ora     #'0'
        jsr     t_putc
        pla
        ora     #'0'
        jmp     t_putc

; A as 2 hex digits
pr_hex: pha
        lsr
        lsr
        lsr
        lsr
        jsr     @dig
        pla
        and     #$0F
@dig:   cmp     #10
        bcc     @n
        adc     #6
@n:     adc     #'0'
        jmp     t_putc

; text row Y: blank (rows 18-23: names; the bitmap: zeros)
t_clear_row:
        cpy     #TXT_ROW
        bcc     @bm
        ldx     #0
        jsr     vdp_at
        lda     #' ' + P_FONT
        ldx     #32
@n:     sta     VDP_DATA
        dex
        bne     @n
        rts
@bm:    sty     t_row
        lda     #0
        sta     t_col
@bc:    jsr     cell_addr
        lda     t_ca
        ldy     t_ca+1
        jsr     vdp_waddr
        lda     #0
        ldx     #8
@bz:    sta     VDP_DATA
        dex
        bne     @bz
        inc     t_col
        lda     t_col
        cmp     #32
        bne     @bc
        rts

; ============================================================================
; the display
; ============================================================================
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup       ; (VRAM cleared: all black)
        ldx     #0              ; the F18A's registers
@r:     stx     tmp
        lda     f18a_regs+1,x
        pha
        lda     f18a_regs,x
        tax
        pla
        jsr     vdp_reg
        ldx     tmp
        inx
        inx
        cpx     #F18A_N * 2
        bne     @r
        lda     #$C0            ; the palette: VR47 = $C0 (from 0, on)
        ldx     #47
        jsr     vdp_reg
        ldx     #0
@p:     lda     pal_data,x
        sta     VDP_DATA
        inx
        cpx     #128
        bne     @p
        lda     #0
        ldx     #47
        jsr     vdp_reg
        jsr     hide_sprites
        jsr     load_gun
        ; the names: rows 0-7 and 8-15: col * 8 + (row & 7); rows 16-17:
        ; col * 2 + row - 16; rows 18-23 spaces
        lda     #<V_NAME
        ldy     #>V_NAME
        jsr     vdp_waddr
        lda     #2
        sta     tmp2
@third: ldy     #0              ; (row)
@nr:    ldx     #0              ; (col)
@nc:    txa
        asl
        asl
        asl
        sty     tmp
        ora     tmp
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @nc
        iny
        cpy     #8
        bne     @nr
        dec     tmp2
        bne     @third
        ldy     #0
@n16:   ldx     #0
@n16c:  txa
        asl
        sty     tmp
        ora     tmp
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @n16c
        iny
        cpy     #2
        bne     @n16
        ldx     #6*32
        lda     #' ' + P_FONT
@n3:    sta     VDP_DATA
        dex
        bne     @n3
        ; the font: third 3's patterns $80-$BF, yellow on black
        lda     #<(V_PAT + $1000 + ($20 + P_FONT) * 8)
        ldy     #>(V_PAT + $1000 + ($20 + P_FONT) * 8)
        jsr     vdp_waddr
        lda     #<font
        sta     vdp_src
        lda     #>font
        sta     vdp_src+1
        lda     #<(64 * 8)
        sta     vdp_n
        lda     #>(64 * 8)
        sta     vdp_n+1
        jsr     vdp_copy
        lda     #<(V_COL + $1000 + ($20 + P_FONT) * 8)
        ldy     #>(V_COL + $1000 + ($20 + P_FONT) * 8)
        jsr     vdp_waddr
        lda     #<(64 * 8)
        sta     vdp_n
        lda     #>(64 * 8)
        sta     vdp_n+1
        lda     #C_HUD
        jsr     vdp_fill
        jsr     cls
        lda     #$C2            ; R1: display on, 16K, 16 x 16 sprites, no
        ldx     #1              ; interrupt (bit 5 off!)
        jmp     vdp_reg

; before going back to the console: the PICO9918 resets itself and its
; palette (VR50 = $C0)
pal_restore:
        lda     #$C0
        ldx     #50
        jmp     vdp_reg

; a clear screen: the bitmap black, the status lines blank, no gun
cls:    jsr     hide_sprites
        lda     #<V_PAT         ; the bitmap: 2 thirds + 64 cells
        ldy     #>V_PAT
        jsr     vdp_waddr
        lda     #<(256 * 8 * 2)
        sta     vdp_n
        lda     #>(256 * 8 * 2)
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        lda     #<(V_PAT + $1000)
        ldy     #>(V_PAT + $1000)
        jsr     vdp_waddr
        lda     #<(64 * 8)
        sta     vdp_n
        lda     #>(64 * 8)
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        lda     #<V_COL         ; (colours: grey on black)
        ldy     #>V_COL
        jsr     vdp_waddr
        lda     #<(256 * 8 * 2)
        sta     vdp_n
        lda     #>(256 * 8 * 2)
        sta     vdp_n+1
        lda     #C_VIEW
        jsr     vdp_fill
        lda     #<(V_COL + $1000)
        ldy     #>(V_COL + $1000)
        jsr     vdp_waddr
        lda     #<(64 * 8)
        sta     vdp_n
        lda     #>(64 * 8)
        sta     vdp_n+1
        lda     #C_VIEW
        jsr     vdp_fill
        ldy     #TXT_ROW
@r:     jsr     t_clear_row
        iny
        cpy     #24
        bne     @r
        rts

PAD_A           = $01           ; bits returned by SBC_PADSTATE
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



; print the controls line on the title screen
show_ctrl:
        ldx     #1
        ldy     #16
        jsr     t_at
        lda     ctrl
        beq     @kb
        lda     #<ctrl_pad_txt
        ldy     #>ctrl_pad_txt
        jmp     t_puts
@kb:    lda     #<ctrl_kb_txt
        ldy     #>ctrl_kb_txt
        jmp     t_puts

; ============================================================================
; level loading
; ============================================================================
; load the file named in lp_name to LEVEL_BUF.  Carry set on failure (message
; shown, key waited for).
load_level:
        jsr     cls
        ldx     #10
        ldy     #8
        jsr     t_at
        lda     #<loading_txt
        ldy     #>loading_txt
        jsr     t_puts
        lda     #<lp_name
        ldy     #>lp_name
        jsr     t_puts
        lda     has_load
        beq     @builtin
        lda     #<lp_block
        ldy     #>lp_block
        jsr     SBC_LOAD
        bcc     @check
        sta     load_err
        ldx     #3
        ldy     #10
        jsr     t_at
        lda     #<loaderr_txt
        ldy     #>loaderr_txt
        jsr     t_puts
        lda     load_err
        jsr     pr_hex
        jmp     @fail
@builtin:
        jmp     @noload
@check: lda     LEVEL_BUF       ; is it a level?
        cmp     #'D'
        bne     @bad
        lda     LEVEL_BUF+1
        cmp     #'6'
        bne     @bad
        clc
        rts
@bad:   ldx     #4
        ldy     #10
        jsr     t_at
        lda     #<badlvl_txt
        ldy     #>badlvl_txt
        jsr     t_puts
        jmp     @fail
@noload:ldx     #1
        ldy     #10
        jsr     t_at
        lda     #<noload_txt
        ldy     #>noload_txt
        jsr     t_puts
@fail:  ldx     #10
        ldy     #13
        jsr     t_at
        lda     #<anykey_txt
        ldy     #>anykey_txt
        jsr     t_puts
        jsr     flush_in
        jsr     menu_key
        sec
        rts

; the next byte of the logo's runs
logo_get:
        lda     $FFFF
        inc     logo_get+1
        bne     :+
        inc     logo_get+2
:       rts

; ============================================================================
; start, title
; ============================================================================
start:  cld
        ldx     #$FF
        txs
        lda     #0              ; clear every variable (RAM is random at power-up)
        tax
        ldy     #>(bss_end - bss_start + $FF)   ; whole pages (past the end is free RAM)
@c1:    sta     bss_start,x
        inx
        bne     @c1
        inc     @c1+2
        dey
        bne     @c1
        lda     ctrl_def
        sta     ctrl
        lda     #$A7
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
@pico:  lda     SBC_LOAD        ; is there a JMP at $FE15?
        cmp     #$4C
        bne     @nol
        lda     #1
        sta     has_load
@nol:   jsr     read_pad
        jsr     sfx_init
        lda     mute_def
        sta     sfx_mute
        jsr     gfx_init

title:  jsr     sfx_off
        jsr     cls
        lda     #<logo_rle      ; the logo: cell columns 1-30, lines 8-55
        sta     logo_get+1
        lda     #>logo_rle
        sta     logo_get+2
        ldx     #1
@lg:    stx     tt_c
        txa                     ; patterns: col * 64 + 8
        asl
        asl
        asl
        asl
        asl
        asl
        ora     #8
        sta     t_ca
        txa
        lsr
        lsr
        sta     t_ca+1
        lda     t_ca
        ldy     t_ca+1
        jsr     vdp_waddr
        lda     #48
        sta     tt_i
@run:   jsr     logo_get
        tax
        jsr     logo_get
@rp:    sta     VDP_DATA
        dec     tt_i
        dex
        bne     @rp
        lda     tt_i
        bne     @run
        lda     t_ca+1          ; its colours
        clc
        adc     #>V_COL
        tay
        lda     t_ca
        jsr     vdp_waddr
        ldy     #0
@lc:    lda     logo_col,y
        sta     VDP_DATA
        iny
        cpy     #48
        bne     @lc
        ldx     tt_c
        inx
        cpx     #31
        bne     @lg
        lda     #<title_txt
        ldy     #>title_txt
        jsr     t_table
        lda     has_load
        bne     @hl
        lda     #<noload_note
        ldy     #>noload_note
        jsr     t_table
@hl:    jsr     show_ctrl
        jsr     read_pad
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @nq
        jsr     sfx_off
        jsr     pal_restore
        jsr     SBC_CONRESET    ; the console's text screen back
        jmp     SBC_MENU
@nq:    cmp     #'M'            ; sound on / off
        bne     @nm
        jsr     sfx_toggle
        jmp     @wait
@nm:    cmp     #'G'
        bne     @ng
        lda     ctrl
        eor     #1
        sta     ctrl
        jsr     show_ctrl
        jmp     @wait
@ng:    cmp     #PAD_GO
        bne     @np
        lda     #1
        sta     ctrl
        bne     new_game
@np:    cmp     #' '
        bne     @wait

new_game:
        lda     #100
        sta     health
        lda     #50
        sta     ammo
        ldx     #12             ; the first map
@n:     lda     first_name,x
        sta     lp_name,x
        dex
        bpl     @n
play_level:
        lda     ammo            ; what to go back to after dying
        sta     ammo0
        jsr     load_level
        bcc     @ok
        jmp     title
@ok:    jsr     init_level
        jsr     screen_setup
        jsr     sfx_off         ; the music
        lda     #MUS_DREAD
        jsr     sfx_snd
        lda     #MUS_DREAD+1
        jsr     sfx_snd
        jsr     SBC_TICKS
        sta     last_tick

; ============================================================================
; the game loop
; ============================================================================
game_loop:
        jsr     sfx_poll
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     move_player
        lda     use
        beq     @2
        jsr     do_use
@2:     jsr     pickups
        jsr     update_things
        jsr     view_changed    ; nothing in view changed: skip the drawing
        bcs     @draw
        jsr     do_fire
        jsr     view_changed    ; (the gun went off?)
        bcs     @rd
        jmp     @hud
@rd:    jsr     render_view
        jsr     render_things
        jmp     @gun
@draw:  jsr     render_view
        jsr     render_things
        jsr     do_fire
@gun:   jsr     draw_view
@hud:   jsr     put_gun
        jsr     hud_update
        jsr     game_pace       ; (a frame takes at least speed / 60 s)
        inc     frame
        lda     health
        bne     @alive
        jmp     died
@alive: lda     done
        beq     game_loop
        jmp     level_done

; clear the screen, the status lines
screen_setup:
        jsr     cls
        lda     #<hud_txt
        ldy     #>hud_txt
        jsr     t_table
        ldx     #0
        ldy     #HUD_LEVEL
        jsr     t_at
        lda     #<lp_name       ; "E1M1.LVL THE AIRLOCK"
        ldy     #>lp_name
        jsr     t_puts
        lda     #' '
        jsr     t_putc
        ldx     #0
@nm:    lda     LEVEL_BUF+6,x
        jsr     t_putc
        inx
        cpx     #16
        bne     @nm
        ldx     #0
        ldy     #HUD_HELP
        jsr     t_at
        lda     ctrl
        bne     @pad
        lda     #<help_kb
        ldy     #>help_kb
        jmp     @h
@pad:   lda     #<help_pad
        ldy     #>help_pad
@h:     jsr     t_puts
        lda     #$FF
        sta     sh_health
        sta     sh_ammo
        sta     sh_kills
        sta     sh_items
        rts

; ---- status lines -----------------------------------------------------------------------
hud_update:
        lda     health
        cmp     sh_health
        beq     @1
        sta     sh_health
        ldx     #7
        ldy     #HUD_STATS
        jsr     t_at
        lda     health
        jsr     pr_dec3
@1:     lda     ammo
        cmp     sh_ammo
        beq     @2
        sta     sh_ammo
        ldx     #18
        ldy     #HUD_STATS
        jsr     t_at
        lda     ammo
        jsr     pr_dec3
@2:     lda     kills
        cmp     sh_kills
        beq     @3
        sta     sh_kills
        ldx     #6
        ldy     #HUD_KILLS
        jsr     t_at
        lda     kills
        jsr     pr_dec2
        lda     #'/'
        jsr     t_putc
        lda     kills_max
        jsr     pr_dec2
@3:     lda     items
        cmp     sh_items
        beq     @4
        sta     sh_items
        ldx     #22
        ldy     #HUD_KILLS
        jsr     t_at
        lda     items
        jsr     pr_dec2
        lda     #'/'
        jsr     t_putc
        lda     items_max
        jsr     pr_dec2
@4:     lda     msg_t           ; the message line times out
        beq     @r
        dec     msg_t
        bne     @r
        ldy     #HUD_MSG
        jmp     t_clear_row
@r:     rts

; show the message at A / Y on the message line
message:sta     tmp
        sty     tmp2
        ldy     #HUD_MSG
        jsr     t_clear_row
        ldx     #0
        ldy     #HUD_MSG
        jsr     t_at
        lda     tmp
        ldy     tmp2
        jsr     t_puts
        lda     #20
        sta     msg_t
        rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        lda     #<paused_txt
        ldy     #>paused_txt
        jsr     message
        jsr     flush_in
@w:     jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @go
        jsr     getc
        bcc     @w
@go:    jsr     flush_in
        lda     #1
        sta     msg_t
        rts

; ============================================================================
; dying, finishing a level
; ============================================================================
died:   jsr     sfx_off
        lda     #SND_DIED
        jsr     sfx_snd
        lda     #<died_txt
        ldy     #>died_txt
        jsr     message
        ldx     #0
        ldy     #HUD_HELP
        jsr     t_at
        lda     #<died2_txt
        ldy     #>died2_txt
        jsr     t_puts
        lda     #20
        jsr     delay_long
        jsr     flush_in
        jsr     menu_key
        cmp     #'Q'
        bne     @again
        jmp     title
@again: lda     #100            ; back to the start of the level
        sta     health
        lda     ammo0
        cmp     #20
        bcs     @a
        lda     #20
@a:     sta     ammo
        jmp     play_level

level_done:
        jsr     sfx_off
        lda     #SND_DONE
        jsr     sfx_snd
        jsr     cls
        ldx     #8
        ldy     #6
        jsr     t_at
        lda     #<done_txt
        ldy     #>done_txt
        jsr     t_puts
        lda     #<lp_name
        ldy     #>lp_name
        jsr     t_puts
        ldx     #10
        ldy     #8
        jsr     t_at
        lda     #<done2_txt
        ldy     #>done2_txt
        jsr     t_puts
        lda     kills
        jsr     pr_dec2
        lda     #'/'
        jsr     t_putc
        lda     kills_max
        jsr     pr_dec2
        ldx     #10
        ldy     #9
        jsr     t_at
        lda     #<done3_txt
        ldy     #>done3_txt
        jsr     t_puts
        lda     items
        jsr     pr_dec2
        lda     #'/'
        jsr     t_putc
        lda     items_max
        jsr     pr_dec2
        lda     LEVEL_BUF+22    ; the next map, or the end
        bne     @next
        lda     #<win_txt
        ldy     #>win_txt
        jsr     t_table
        jsr     flush_in
        jsr     menu_key
        jmp     title
@next:  lda     #<next_txt
        ldy     #>next_txt
        jsr     t_table
        ldx     #11
@n:     lda     LEVEL_BUF+22,x
        sta     lp_name,x
        dex
        bpl     @n
        lda     #0
        sta     lp_name+12
        lda     #20
        jsr     delay_long
        jsr     flush_in
        jsr     menu_key
        cmp     #'Q'
        bne     @go
        jmp     title
@go:    jmp     play_level

; ============================================================================
; maths
; ============================================================================

; m_lo/m_hi = A * Y (unsigned 8 x 8), with quarter squares:
; a*b = f(a+b) - f(a-b), f(n) = n*n/4.  Changes X.
mul8:   sta     m_a
        sty     m_b
        clc
        adc     m_b
        tax
        bcs     @big
        lda     sq_lo,x
        sta     m_lo
        lda     sq_hi,x
        sta     m_hi
        jmp     @diff
@big:   lda     sq2_lo,x
        sta     m_lo
        lda     sq2_hi,x
        sta     m_hi
@diff:  lda     m_a
        sec
        sbc     m_b
        bcs     @pos
        eor     #$FF
        adc     #1              ; (carry is clear)
@pos:   tax
        lda     m_lo
        sec
        sbc     sq_lo,x
        sta     m_lo
        lda     m_hi
        sbc     sq_hi,x
        sta     m_hi
        rts

; r_lo/r_hi = (A * w) >> 8, w = w_lo/w_hi unsigned 16 bit.
; Two quarter-square products: a*b = sq(a+b) - sq(a-b), sq(n) = n*n/4
; (sq2 is the table for sums of 256 and more).
mul8x16:sta     mf
        sec                     ; low product: only its high byte is needed
        sbc     w_lo
        bcs     @d1
        eor     #$FF
        adc     #1
@d1:    tay                     ; |f - w_lo|
        lda     mf
        clc
        adc     w_lo
        tax                     ; f + w_lo
        bcs     @b1
        sec
        lda     sq_lo,x
        sbc     sq_lo,y
        lda     sq_hi,x
        sbc     sq_hi,y
        sta     r_lo
        jmp     @p2
@b1:    sec
        lda     sq2_lo,x
        sbc     sq_lo,y
        lda     sq2_hi,x
        sbc     sq_hi,y
        sta     r_lo
@p2:    lda     mf              ; high product, added in
        sec
        sbc     w_hi
        bcs     @d2
        eor     #$FF
        adc     #1
@d2:    tay
        lda     mf
        clc
        adc     w_hi
        tax
        bcs     @b2
        sec
        lda     sq_lo,x
        sbc     sq_lo,y
        sta     tmp
        lda     sq_hi,x
        sbc     sq_hi,y
        jmp     @add
@b2:    sec
        lda     sq2_lo,x
        sbc     sq_lo,y
        sta     tmp
        lda     sq2_hi,x
        sbc     sq_hi,y
@add:   sta     r_hi
        lda     tmp
        clc
        adc     r_lo
        sta     r_lo
        bcc     @r
        inc     r_hi
@r:     rts

; r = w * A / 128: A signed s.7 (a sine), w signed 8.8.  Changes w.
smul:   sta     sm_s
        eor     w_hi
        sta     sm_sign
        lda     sm_s
        bpl     @a
        eor     #$FF
        clc
        adc     #1
@a:     sta     sm_a
        lda     w_hi
        bpl     @w
        lda     #0
        sec
        sbc     w_lo
        sta     w_lo
        lda     #0
        sbc     w_hi
        sta     w_hi
@w:     lda     sm_a
        jsr     mul8x16
        asl     r_lo
        rol     r_hi
        lda     sm_sign
        bpl     @r
        lda     #0
        sec
        sbc     r_lo
        sta     r_lo
        lda     #0
        sbc     r_hi
        sta     r_hi
@r:     rts

; n0..n2 = n0..n2 / d0..d1 (unsigned 24 / 16 bit)
udiv24: lda     #0
        sta     rm0
        sta     rm1
        ldx     #24
@l:     asl     n0
        rol     n1
        rol     n2
        rol     rm0
        rol     rm1
        lda     rm0
        sec
        sbc     d0
        tay
        lda     rm1
        sbc     d1
        bcc     @s
        sta     rm1
        sty     rm0
        inc     n0
@s:     dex
        bne     @l
        rts

; A = sin(angle a_lo / a_hi), signed s.7.  get_cos: cos of the same angle
get_cos:lda     a_hi
        clc
        adc     #1
        and     #3
        jmp     sin_hi
get_sin:lda     a_hi
        and     #3
sin_hi: clc
        adc     #>sin_tab
        sta     @rd+2
        lda     #<sin_tab
        clc
        adc     a_lo
        sta     @rd+1
        bcc     @rd
        inc     @rd+2
@rd:    lda     $FFFF
        rts

; tile at X, Y (0..31) -> A.  Outside the map counts as wall.  Preserves X, Y.
tile_at:cpx     #32
        bcs     @wall
        cpy     #32
        bcs     @wall
        txa
        clc
        adc     maprow_lo,y
        sta     @rd+1
        lda     maprow_hi,y
        adc     #0
        sta     @rd+2
@rd:    lda     $FFFF
        rts
@wall:  lda     #1
        rts

; set the tile at X, Y to A
tile_set:
        inc     mapver          ; (the view must be drawn again)
        pha
        txa
        clc
        adc     maprow_lo,y
        sta     @wr+1
        lda     maprow_hi,y
        adc     #0
        sta     @wr+2
        pla
@wr:    sta     $FFFF
        rts

; ============================================================================
; the renderer
; ============================================================================

; cast one ray per column and draw the walls into FB
; cast the ray for column col: z-buffer, height, pattern and block hit
cast_ray:
        ldx     col
        lda     pa_lo           ; the ray's angle
        clc
        adc     coloff_lo,x
        sta     ra_lo
        lda     pa_hi
        adc     coloff_hi,x
        and     #3
        sta     ra_hi
        ldy     ra_lo           ; |1/cos| and |1/sin| from the quarter table
        lda     invc_lo,y
        sta     ta_lo
        lda     invc_hi,y
        sta     ta_hi
        tya
        beq     @r0
        eor     #$FF
        clc
        adc     #1              ; 256 - r
        tay
        lda     invc_lo,y
        sta     tb_lo
        lda     invc_hi,y
        sta     tb_hi
        jmp     @rr
@r0:    lda     #$FF            ; 1/cos(90) = "infinite"
        sta     tb_lo
        lda     #$7F
        sta     tb_hi
@rr:    lda     ra_hi
        and     #1
        bne     @odd
        lda     ta_lo           ; quarters 0 and 2
        sta     dx_lo
        lda     ta_hi
        sta     dx_hi
        lda     tb_lo
        sta     dy_lo
        lda     tb_hi
        sta     dy_hi
        jmp     @sx
@odd:   lda     tb_lo           ; quarters 1 and 3
        sta     dx_lo
        lda     tb_hi
        sta     dx_hi
        lda     ta_lo
        sta     dy_lo
        lda     ta_hi
        sta     dy_hi
@sx:    lda     ra_hi           ; x goes up in quarters 0 and 3
        beq     @xp
        cmp     #3
        beq     @xp
        lda     px_lo
        sta     ff
        lda     #$FF
        sta     spx_lo
        sta     spx_hi
        jmp     @xd
@xp:    lda     px_lo
        eor     #$FF
        sta     ff
        lda     #1
        sta     spx_lo
        lda     #0
        sta     spx_hi
@xd:    lda     dx_lo           ; first x side = fraction * |1/cos|
        sta     w_lo
        lda     dx_hi
        sta     w_hi
        lda     ff
        jsr     mul8x16
        lda     r_lo
        sta     sx_lo
        lda     r_hi
        sta     sx_hi
        lda     ra_hi           ; y goes up (south) in quarters 0 and 1
        cmp     #2
        bcc     @yp
        lda     py_lo
        sta     ff
        lda     #$E0            ; -32
        sta     spy_lo
        lda     #$FF
        sta     spy_hi
        jmp     @yd
@yp:    lda     py_lo
        eor     #$FF
        sta     ff
        lda     #32
        sta     spy_lo
        lda     #0
        sta     spy_hi
@yd:    lda     dy_lo
        sta     w_lo
        lda     dy_hi
        sta     w_hi
        lda     ff
        jsr     mul8x16
        lda     r_lo
        sta     sy_lo
        lda     r_hi
        sta     sy_hi
        lda     pbase_lo
        sta     @rd+1
        lda     pbase_hi
        sta     @rd+2
@dda:   lda     sx_hi           ; step along whichever side is nearer
        cmp     sy_hi
        bcc     @xs
        bne     @ys
        lda     sx_lo
        cmp     sy_lo
        bcs     @ys
@xs:    lda     @rd+1           ; next block in x
        clc
        adc     spx_lo
        sta     @rd+1
        lda     @rd+2
        adc     spx_hi
        sta     @rd+2
        ldx     #0
        beq     @rd
@ys:    lda     @rd+1           ; next block in y
        clc
        adc     spy_lo
        sta     @rd+1
        lda     @rd+2
        adc     spy_hi
        sta     @rd+2
        ldx     #1
@rd:    lda     $FFFF           ; (address = the map cell being tested)
        bne     @hit            ; (the map always has walls round the edge)
        txa
        bne     @ay
        lda     sx_lo           ; the next x side
        clc
        adc     dx_lo
        sta     sx_lo
        lda     sx_hi
        adc     dx_hi
        sta     sx_hi
        bcc     @dda
        lda     #$FF
        sta     sx_lo
        sta     sx_hi
        bne     @dda
@ay:    lda     sy_lo           ; the next y side
        clc
        adc     dy_lo
        sta     sy_lo
        lda     sy_hi
        adc     dy_hi
        sta     sy_hi
        bcc     @dda
        lda     #$FF
        sta     sy_lo
        sta     sy_hi
        beq     *+5
        jmp     @dda
@hit:   stx     side
        and     #7
        sta     tile
        lda     sx_lo           ; distance to the side that was hit
        ldy     sx_hi
        cpx     #0
        beq     @dh
        lda     sy_lo
        ldy     sy_hi
@dh:    sta     dist_lo
        sty     dist_hi
        lda     @rd+1           ; the cell that was hit
        sta     mp_lo
        lda     @rd+2
        sta     mp_hi
        ; perpendicular distance = distance * cos(column offset)
        lda     dist_lo
        sta     w_lo
        lda     dist_hi
        sta     w_hi
        ldx     col
        lda     cosfix,x
        jsr     mul8x16
        ldx     col
        lda     r_lo
        sta     zb_lo,x
        lda     r_hi
        sta     zb_hi,x
        cmp     zmax            ; the farthest wall seen this frame
        bcc     @zm
        sta     zmax
@zm:    jsr     dist_index      ; -> idx, hgt
        ; shading band by distance
        lda     idx_hi
        bne     @b3
        lda     idx_lo
        cmp     #48
        bcc     @b0
        cmp     #112
        bcc     @b1
        cmp     #224
        bcc     @b2
@b3:    lda     #3
        bne     @bs
@b2:    lda     #2
        bne     @bs
@b1:    lda     #1
        bne     @bs
@b0:    lda     #0
@bs:    sta     band
        lda     tile            ; pattern = style * 8 + side * 4 + band
        asl
        asl
        asl
        ora     band
        ldx     side
        beq     @s0
        ora     #4
@s0:    ldx     col
        sta     c_pidx,x
        jsr     hit_u           ; (where on the face: c_u)
        ldx     col
        lda     hgt
        sta     c_hgt,x
        lda     mp_lo
        sta     c_mplo,x
        lda     mp_hi
        sta     c_mphi,x
        rts

; c_u (col) = where the ray hit the face: the fraction of the tile along it
; (side 0, a face across x: y = py + dist sin; side 1: x = px + dist cos)
hit_u:  lda     ra_lo
        sta     a_lo
        lda     ra_hi
        sta     a_hi
        lda     dist_lo
        sta     w_lo
        lda     dist_hi
        sta     w_hi
        lda     side
        bne     @x
        jsr     get_sin
        jsr     smul
        lda     py_lo
        jmp     @u
@x:     jsr     get_cos
        jsr     smul
        lda     px_lo
@u:     clc
        adc     r_lo
        ldx     col
        sta     c_u,x
        rts

; r_lo/r_hi = a distance (8.8 tiles) -> idx (distance in 1/32 tile, max 1023)
; and hgt = the height in pixels of a wall that far away
dist_index:
        lda     r_hi
        cmp     #32
        bcc     @ok
        lda     #$FF
        sta     idx_lo
        lda     #3
        sta     idx_hi
        jmp     @h
@ok:    lsr
        lsr
        lsr
        sta     idx_hi
        lda     r_hi
        asl
        asl
        asl
        asl
        asl
        sta     tmp
        lda     r_lo
        lsr
        lsr
        lsr
        ora     tmp
        sta     idx_lo
@h:     lda     #<htab
        clc
        adc     idx_lo
        sta     @rd+1
        lda     #>htab
        adc     idx_hi
        sta     @rd+2
@rd:    lda     $FFFF
        sta     hgt
        rts

; ---- things ------------------------------------------------------------------------
; project every thing that is in front of the player; nearest drawn last
render_things:
        lda     #0
        sta     nvis
        lda     pa_lo
        sta     a_lo
        lda     pa_hi
        sta     a_hi
        jsr     get_sin
        sta     psin
        jsr     get_cos
        sta     pcos
        ldx     #0
@t:     jsr     sfx_poll        ; (the sound goes on: once a thing)
        stx     ti
        lda     t_state,x
        bne     @go
        jmp     @next
@go:    lda     t_x_lo,x        ; dx, dy from the player
        sec
        sbc     px_lo
        sta     tdx_lo
        lda     t_x_hi,x
        sbc     px_hi
        sta     tdx_hi
        clc
        adc     #20
        cmp     #40
        bcc     *+5           ; too far
        jmp     @skip
        lda     t_y_lo,x
        sec
        sbc     py_lo
        sta     tdy_lo
        lda     t_y_hi,x
        sbc     py_hi
        sta     tdy_hi
        clc
        adc     #20
        cmp     #40
        bcc     *+5
        jmp     @skip
        ; depth = dx cos + dy sin
        jsr     wdx
        lda     pcos
        jsr     smul
        jsr     r2acc
        jsr     wdy
        lda     psin
        jsr     smul
        jsr     acc_add_r
        lda     acc_hi
        bpl     *+5           ; behind
        jmp     @skip
        bne     @front
        lda     acc_lo
        cmp     #$40
        bcs     *+5           ; too close
        jmp     @skip
@front: lda     acc_hi          ; beyond every wall in view?
        cmp     zmax
        beq     @fr
        bcc     @fr
        jmp     @skip
@fr:    lda     acc_lo
        sta     dep_lo
        lda     acc_hi
        sta     dep_hi
        ; lateral = dy cos - dx sin
        jsr     wdy
        lda     pcos
        jsr     smul
        jsr     r2acc
        jsr     wdx
        lda     psin
        jsr     smul
        jsr     acc_sub_r
        ; |lateral| < 2 * depth, or it is well off the screen
        lda     acc_hi
        sta     lat_sign
        bpl     @lp
        lda     #0
        sec
        sbc     acc_lo
        sta     acc_lo
        lda     #0
        sbc     acc_hi
        sta     acc_hi
@lp:    lda     dep_lo
        asl
        sta     tmp
        lda     dep_hi
        rol
        cmp     acc_hi
        bcs     *+5
        jmp     @skip
        bne     @in
        lda     tmp
        cmp     acc_lo
        bcs     *+5
        jmp     @skip
@in:    ; column offset = |lateral| * FOCAL / depth
        lda     acc_lo
        sta     w_lo
        lda     acc_hi
        sta     w_hi
        lda     #FOCAL
        jsr     mul8x16_full    ; n0..n2 = FOCAL * |lateral|
        lda     dep_lo
        sta     d0
        lda     dep_hi
        sta     d1
        jsr     udiv24
        lda     n1
        bne     @skip
        lda     n0
        cmp     #120
        bcs     @skip
        ldx     nvis            ; record it
        ldy     ti
        tya
        sta     v_t,x
        lda     lat_sign
        bmi     @left
        lda     #COLS / 2
        clc
        adc     n0
        sta     v_sx_lo,x
        lda     #0
        adc     #0
        sta     v_sx_hi,x
        jmp     @dep
@left:  lda     #COLS / 2
        sec
        sbc     n0
        sta     v_sx_lo,x
        lda     #0
        sbc     #0
        sta     v_sx_hi,x
@dep:   lda     dep_lo
        sta     v_d_lo,x
        sta     r_lo
        lda     dep_hi
        sta     v_d_hi,x
        sta     r_hi
        jsr     dist_index
        ldx     nvis
        lda     hgt
        sta     v_h,x
        inc     nvis
        jmp     @next
@skip:
@next:  ldx     ti
        inx
        cpx     #MAXT
        beq     @sort
        jmp     @t
@sort:  ; sort far to near (insertion sort on depth)
        ldx     #1
@s1:    cpx     nvis
        bcc     :+
        jmp     @draw
:
        stx     sj
@s2:    lda     v_d_hi-1,x      ; the one before nearer than this one? swap
        cmp     v_d_hi,x
        bcc     @swap
        bne     @s3
        lda     v_d_lo-1,x
        cmp     v_d_lo,x
        bcs     @s3
@swap:  jsr     swap_vis        ; (keeps X)
        dex
        bne     @s2
@s3:    ldx     sj
        inx
        jmp     @s1
@draw:  rts

; swap visible entries X-1 and X
swap_vis:
        .repeat 6, K
        lda     v_t + K*MAXT - 1,x
        pha
        lda     v_t + K*MAXT,x
        sta     v_t + K*MAXT - 1,x
        pla
        sta     v_t + K*MAXT,x
        .endrepeat
        rts

wdx:    lda     tdx_lo
        sta     w_lo
        lda     tdx_hi
        sta     w_hi
        rts
wdy:    lda     tdy_lo
        sta     w_lo
        lda     tdy_hi
        sta     w_hi
        rts
r2acc:  lda     r_lo
        sta     acc_lo
        lda     r_hi
        sta     acc_hi
        rts
acc_add_r:
        lda     acc_lo
        clc
        adc     r_lo
        sta     acc_lo
        lda     acc_hi
        adc     r_hi
        sta     acc_hi
        rts
acc_sub_r:
        lda     acc_lo
        sec
        sbc     r_lo
        sta     acc_lo
        lda     acc_hi
        sbc     r_hi
        sta     acc_hi
        rts

; n0..n2 = A * w (unsigned 8 x 16, full 24 bit result)
mul8x16_full:
        sta     mf
        ldy     w_lo
        jsr     mul8
        lda     m_lo
        sta     n0
        lda     m_hi
        sta     n1
        lda     mf
        ldy     w_hi
        jsr     mul8
        lda     m_lo
        clc
        adc     n1
        sta     n1
        lda     m_hi
        adc     #0
        sta     n2
        rts

; the sprite for thing X -> A
thing_sprite:
        lda     t_state,x
        cmp     #S_DEAD
        bne     @1
        lda     #SPR_DEAD
        rts
@1:     lda     t_type,x
        cmp     #T_MEDKIT
        bne     @2
        lda     #SPR_MEDKIT
        rts
@2:     cmp     #T_AMMO
        bne     @3
        lda     #SPR_AMMO
        rts
@3:     ldy     #SPR_GRUNT1
        cmp     #T_GRUNT
        beq     @4
        ldy     #SPR_BRUTE1
@4:     sty     tmp
        lda     t_state,x
        cmp     #S_ATTACK
        bne     @5
        lda     tmp
        clc
        adc     #2              ; firing frame
        rts
@5:     lda     t_anim,x
        and     #1
        clc
        adc     tmp
        rts

; carry set if anything the view is drawn from changed since the last call:
; where the player is and faces, the things, the gun, the doors
view_changed:
        lda     force
        sta     vchg
        lda     #0
        sta     force
.macro VCHK var, slot
        lda     var
        cmp     vstate + slot
        beq     :+
        sta     vstate + slot
        inc     vchg
:
.endmacro
        VCHK    px_lo, 0
        VCHK    px_hi, 1
        VCHK    py_lo, 2
        VCHK    py_hi, 3
        VCHK    pa_lo, 4
        VCHK    pa_hi, 5
        VCHK    mapver, 7
        ldx     #MAXT-1
@t:
.macro VCHKT arr, base
        lda     arr,x
        cmp     base,x
        beq     :+
        sta     base,x
        inc     vchg
:
.endmacro
        VCHKT   t_state, vt_state
        VCHKT   t_x_lo, vt_x_lo
        VCHKT   t_x_hi, vt_x_hi
        VCHKT   t_y_lo, vt_y_lo
        VCHKT   t_y_hi, vt_y_hi
        VCHKT   t_anim, vt_anim
        dex
        bpl     @t
        lda     vchg
        cmp     #1              ; carry set if anything changed
        rts


; set up the loaded level: player, things, counters
init_level:
        lda     LEVEL_BUF+3
        sta     px_hi
        lda     LEVEL_BUF+4
        sta     py_hi
        lda     #$80
        sta     px_lo
        sta     py_lo
        lda     LEVEL_BUF+5     ; 0..255 -> 0..1023
        asl
        sta     pa_lo
        lda     #0
        rol
        sta     pa_hi
        asl     pa_lo
        rol     pa_hi
        lda     #0
        sta     kills
        sta     kills_max
        sta     items
        sta     items_max
        sta     gun_t
        sta     cool
        sta     msg_t
        sta     done
        ldx     #MAXT-1
@clr:   sta     t_state,x
        dex
        bpl     @clr
        lda     LEVEL_BUF+34
        cmp     #MAXT+1
        bcc     @n
        lda     #MAXT
@n:     sta     tcount
        lda     #<THING_SRC
        sta     @rd+1
        lda     #>THING_SRC
        sta     @rd+2
        ldx     #0
@t:     cpx     tcount
        bcs     @done
        jsr     @get
        sta     t_type,x
        jsr     @get
        sta     t_x_hi,x
        jsr     @get
        sta     t_y_hi,x
        jsr     @get
        lda     #$80
        sta     t_x_lo,x
        sta     t_y_lo,x
        lda     #S_IDLE
        sta     t_state,x
        lda     #0
        sta     t_timer,x
        sta     t_anim,x
        lda     t_type,x
        cmp     #T_GRUNT
        bne     @b
        lda     #30
        sta     t_hp,x
        inc     kills_max
        jmp     @nx
@b:     cmp     #T_BRUTE
        bne     @it
        lda     #90
        sta     t_hp,x
        inc     kills_max
        jmp     @nx
@it:    inc     items_max
@nx:    inx
        jmp     @t
@done:  ldx     #31             ; make sure the map has walls round its edge
@tb:    lda     MAP,x           ; (the ray caster relies on it)
        bne     @tb1
        lda     #1
        sta     MAP,x
@tb1:   lda     MAP+31*32,x
        bne     @tb2
        lda     #1
        sta     MAP+31*32,x
@tb2:   dex
        bpl     @tb
        lda     #<MAP
        sta     @lr+1
        sta     @lw+1
        lda     #>MAP
        sta     @lr+2
        sta     @lw+2
        ldx     #32
@lr0:   ldy     #0
        jsr     @fix
        ldy     #31
        jsr     @fix
        lda     @lr+1
        clc
        adc     #32
        sta     @lr+1
        sta     @lw+1
        bcc     @lr1
        inc     @lr+2
        inc     @lw+2
@lr1:   dex
        bne     @lr0
        rts
@fix:
@lr:    lda     $FFFF,y
        bne     @fx
        lda     #1
@lw:    sta     $FFFF,y
@fx:    rts
@get:
@rd:    lda     $FFFF
        inc     @rd+1
        bne     @g
        inc     @rd+2
@g:     rts


; ============================================================================
; input and moving
; ============================================================================
read_input:
        lda     #0
        sta     mv_fwd
        sta     mv_turn
        sta     mv_strafe
        sta     fire
        sta     use
        sta     quit
        lda     ctrl
        beq     @keys
        jsr     read_pad        ; gamepad: buttons held
        lda     pad
        and     #PAD_UP
        beq     @u
        lda     #40
        sta     mv_fwd
@u:     lda     pad
        and     #PAD_DOWN
        beq     @d
        lda     #<-40
        sta     mv_fwd
@d:     lda     pad
        and     #PAD_SELECT     ; Select + left / right: strafe
        beq     @turn
        lda     pad
        and     #PAD_LEFT
        beq     @sr
        lda     #<-40
        sta     mv_strafe
@sr:    lda     pad
        and     #PAD_RIGHT
        beq     @ab
        lda     #40
        sta     mv_strafe
        jmp     @ab
@turn:  lda     pad
        and     #PAD_LEFT
        beq     @tr
        lda     #<-20
        sta     mv_turn
@tr:    lda     pad
        and     #PAD_RIGHT
        beq     @ab
        lda     #20
        sta     mv_turn
@ab:    lda     pad
        and     #PAD_A
        beq     @b
        lda     #1
        sta     fire
@b:     lda     padnew
        and     #PAD_B
        beq     @st
        lda     #1
        sta     use
@st:    lda     padnew
        and     #PAD_START
        beq     @keys
        jsr     pause
@keys:
@k2:    jsr     getc
        bcc     @done
        jsr     handle_key
        jmp     @k2
@done:  rts

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
        jmp     @fwd
:       cmp     #'B'
        bne     :+
        jmp     @back
:       cmp     #'C'
        bne     :+
        jmp     @right
:       cmp     #'D'
        bne     :+
        jmp     @left
:       rts
@plain: cmp     #$1B
        bne     @np
        inc     esc_st
        rts
@np:    cmp     #KEY_UP         ; the AVR keyboard's arrow keys
        beq     @fwd
        cmp     #KEY_DOWN
        beq     @back
        cmp     #KEY_LEFT
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
        ldx     ctrl
        beq     @kb
        jsr     pad_typed       ; gamepad mode: ignore what the pad types
        bcc     @kb
        rts
@kb:    cmp     #'a'
        bcc     @uc
        cmp     #'z'+1
        bcs     @uc
        and     #$DF
@uc:    cmp     #'W'
        beq     @fwd
        cmp     #'S'
        beq     @back
        cmp     #'A'
        beq     @left
        cmp     #'D'
        beq     @right
        cmp     #','
        beq     @sl
        cmp     #'.'
        beq     @sr
        cmp     #' '
        beq     @fire
        cmp     #'F'
        beq     @fire
        cmp     #'E'
        beq     @use
        cmp     #'Q'
        beq     @quit
        cmp     #'P'
        beq     @pause
        cmp     #'M'
        bne     @rr
        jmp     sfx_toggle
@rr:    rts
@fwd:   lda     #64
        sta     mv_fwd
        rts
@back:  lda     #<-64
        sta     mv_fwd
        rts
@left:  lda     mv_turn         ; key repeat faster than the frames:
        cmp     #<-32           ; turn up to twice as far
        beq     @l2
        lda     #<-32
        .byte   $2C             ; (BIT abs: skips the next LDA)
@l2:    lda     #<-64
        sta     mv_turn
        rts
@right: lda     mv_turn
        cmp     #32
        beq     @r2
        lda     #32
        .byte   $2C
@r2:    lda     #64
        sta     mv_turn
        rts
@sl:    lda     #<-64
        sta     mv_strafe
        rts
@sr:    lda     #64
        sta     mv_strafe
        rts
@fire:  lda     #1
        sta     fire
        rts
@use:   lda     #1
        sta     use
        rts
@quit:  lda     #1
        sta     quit
        rts
@pause: jmp     pause


; turn, then move forward / sideways with wall sliding
move_player:
        lda     mv_turn         ; angle += turn (signed)
        beq     @mv
        clc
        adc     pa_lo
        sta     pa_lo
        lda     mv_turn
        bmi     @neg
        lda     pa_hi
        adc     #0
        jmp     @set
@neg:   lda     pa_hi
        adc     #$FF
@set:   and     #3
        sta     pa_hi
@mv:    lda     #0
        sta     mx_lo
        sta     mx_hi
        sta     my_lo
        sta     my_hi
        lda     pa_lo
        sta     a_lo
        lda     pa_hi
        sta     a_hi
        lda     mv_fwd
        beq     @st
        jsr     sext_w          ; forward: (cos, sin) * step
        jsr     get_cos
        jsr     smul
        jsr     add_mx
        lda     mv_fwd
        jsr     sext_w
        jsr     get_sin
        jsr     smul
        jsr     add_my
@st:    lda     mv_strafe
        beq     @go
        jsr     sext_w          ; sideways (right): (-sin, cos) * step
        jsr     get_cos
        jsr     smul
        jsr     add_my
        lda     mv_strafe
        jsr     sext_w
        jsr     get_sin
        jsr     smul
        jsr     sub_mx
@go:    jmp     try_move

; w = A sign extended (a step in 1/256 tile)
sext_w: sta     w_lo
        lda     #0
        ldx     w_lo
        bpl     @p
        lda     #$FF
@p:     sta     w_hi
        rts
add_mx: lda     mx_lo
        clc
        adc     r_lo
        sta     mx_lo
        lda     mx_hi
        adc     r_hi
        sta     mx_hi
        rts
sub_mx: lda     mx_lo
        sec
        sbc     r_lo
        sta     mx_lo
        lda     mx_hi
        sbc     r_hi
        sta     mx_hi
        rts
add_my: lda     my_lo
        clc
        adc     r_lo
        sta     my_lo
        lda     my_hi
        adc     r_hi
        sta     my_hi
        rts

; move by mx, my: x and y separately, so walls can be slid along
try_move:
        lda     mx_lo
        ora     mx_hi
        beq     @y
        lda     px_lo           ; new x
        clc
        adc     mx_lo
        sta     nx_lo
        lda     px_hi
        adc     mx_hi
        sta     nx_hi
        lda     nx_lo           ; the edge of the player in that direction
        ldx     mx_hi
        bmi     @xl
        clc
        adc     #RADIUS
        lda     nx_hi
        adc     #0
        jmp     @xc
@xl:    sec
        sbc     #RADIUS
        lda     nx_hi
        sbc     #0
@xc:    tax
        stx     edge
        jsr     clear_rows      ; free at py +- radius?
        bcc     @xok
        ldx     edge            ; no, but the middle of the player would
        ldy     py_hi           ; fit: slide towards the middle of the row
        jsr     tile_at         ; (getting through doorways is easier)
        bne     @y
        lda     py_lo
        jsr     to_middle
        sta     py_lo
        jmp     @y
@xok:   lda     nx_lo
        sta     px_lo
        lda     nx_hi
        sta     px_hi
@y:     lda     my_lo
        ora     my_hi
        beq     @done
        lda     py_lo
        clc
        adc     my_lo
        sta     ny_lo
        lda     py_hi
        adc     my_hi
        sta     ny_hi
        lda     ny_lo
        ldx     my_hi
        bmi     @yu
        clc
        adc     #RADIUS
        lda     ny_hi
        adc     #0
        jmp     @yc
@yu:    sec
        sbc     #RADIUS
        lda     ny_hi
        sbc     #0
@yc:    tay
        sty     edge
        jsr     clear_cols      ; free at px +- radius?
        bcc     @yok
        ldx     px_hi           ; the same sliding as for x
        ldy     edge
        jsr     tile_at
        bne     @done
        lda     px_lo
        jsr     to_middle
        sta     px_lo
        rts
@yok:   lda     ny_lo
        sta     py_lo
        lda     ny_hi
        sta     py_hi
@done:  rts

; A = a position within a tile -> moved up to 1/8 tile towards the middle
to_middle:
        cmp     #$80
        bcs     @hi
        adc     #32
        cmp     #$80
        bcc     @r
        lda     #$80
@r:     rts
@hi:    sbc     #32
        cmp     #$80
        bcs     @r
        lda     #$80
        rts

; carry clear if column X is floor at the rows of py - radius and py + radius
clear_rows:
        lda     py_lo
        sec
        sbc     #RADIUS
        lda     py_hi
        sbc     #0
        tay
        jsr     tile_at
        bne     @no
        lda     py_lo
        clc
        adc     #RADIUS
        lda     py_hi
        adc     #0
        tay
        jsr     tile_at
        bne     @no
        clc
        rts
@no:    sec
        rts

; carry clear if row Y is floor at the columns of px - radius and px + radius
clear_cols:
        lda     px_lo
        sec
        sbc     #RADIUS
        lda     px_hi
        sbc     #0
        tax
        jsr     tile_at
        bne     @no
        lda     px_lo
        clc
        adc     #RADIUS
        lda     px_hi
        adc     #0
        tax
        jsr     tile_at
        bne     @no
        clc
        rts
@no:    sec
        rts

; ---- use: open a door or press the exit switch in front of the player --------------
do_use: lda     pa_lo
        sta     a_lo
        lda     pa_hi
        sta     a_hi
        lda     #$C0            ; probe 3/4 of a tile ahead
        jsr     sext_w
        lda     #0
        sta     w_hi
        jsr     get_cos
        jsr     smul
        lda     px_lo
        clc
        adc     r_lo
        lda     px_hi
        adc     r_hi
        sta     ux
        lda     #$C0
        sta     w_lo
        lda     #0
        sta     w_hi
        jsr     get_sin
        jsr     smul
        lda     py_lo
        clc
        adc     r_lo
        lda     py_hi
        adc     r_hi
        sta     uy
        ldx     ux
        ldy     uy
        jsr     tile_at
        cmp     #TILE_DOOR
        bne     @ex
        lda     #SND_DOOR
        jsr     sfx_snd
        lda     #0
        ldx     ux
        ldy     uy
        jsr     tile_set
        lda     #<door_txt
        ldy     #>door_txt
        jmp     message
@ex:    cmp     #TILE_EXIT
        bne     @no
        lda     #1
        sta     done
@no:    rts

; ---- picking things up ------------------------------------------------------------------
pickups:ldx     #MAXT-1
@l:     lda     t_state,x
        cmp     #S_IDLE
        bne     @n
        lda     t_type,x
        cmp     #T_MEDKIT
        bcc     @n              ; an enemy
        lda     t_x_hi,x        ; on the same tile as the player?
        cmp     px_hi
        bne     @n
        lda     t_y_hi,x
        cmp     py_hi
        bne     @n
        lda     t_type,x
        cmp     #T_MEDKIT
        bne     @am
        lda     health
        cmp     #100
        bcs     @n              ; not needed: leave it
        adc     #25
        cmp     #101
        bcc     @h
        lda     #100
@h:     sta     health
        lda     #SND_PICKUP
        jsr     sfx_snd
        lda     #S_GONE
        sta     t_state,x
        inc     items
        stx     ti
        lda     #<medkit_txt
        ldy     #>medkit_txt
        jsr     message
        ldx     ti
        jmp     @n
@am:    lda     ammo
        clc
        adc     #10
        cmp     #200
        bcc     @a
        lda     #199
@a:     sta     ammo
        lda     #SND_PICKUP
        jsr     sfx_snd
        lda     #S_GONE
        sta     t_state,x
        inc     items
        stx     ti
        lda     #<ammo_txt
        ldy     #>ammo_txt
        jsr     message
        ldx     ti
@n:     dex
        bpl     @l
        rts

; ============================================================================
; enemies
; ============================================================================
update_things:
        ldx     #0
@l:     stx     ti
        lda     t_state,x
        cmp     #S_IDLE
        bcc     @n
        cmp     #S_DEAD
        bcs     @n
        lda     t_type,x
        cmp     #T_MEDKIT
        bcs     @n              ; items don't think
        jsr     think
@n:     ldx     ti
        inx
        cpx     #MAXT
        bne     @l
        lda     cool
        beq     @r
        dec     cool
@r:     rts

; enemy ti: wake, chase, shoot
think:  ldx     ti
        lda     px_lo           ; vector to the player
        sec
        sbc     t_x_lo,x
        sta     tdx_lo
        lda     px_hi
        sbc     t_x_hi,x
        sta     tdx_hi
        lda     py_lo
        sec
        sbc     t_y_lo,x
        sta     tdy_lo
        lda     py_hi
        sbc     t_y_hi,x
        sta     tdy_hi
        jsr     approx_dist     ; -> edist (whole tiles, capped 255)
        ldx     ti
        lda     t_state,x
        cmp     #S_ATTACK
        bne     @na
        dec     t_timer,x
        bne     @r
        jsr     resolve_attack
        ldx     ti
        lda     #S_CHASE
        sta     t_state,x
@r:     rts
@na:    cmp     #S_IDLE
        bne     @chase
        lda     edist           ; asleep: wakes if it can see the player close by
        cmp     #8
        bcs     @r
        jsr     line_of_sight
        bcs     @r
        lda     #SND_WAKE
        jsr     sfx_snd
        ldx     ti
        lda     #S_CHASE
        sta     t_state,x
        rts
@chase: lda     edist           ; shoot?
        cmp     #12
        bcs     @move
        jsr     rand
        ldx     ti
        ldy     t_type,x
        cmp     shoot_chance-1,y
        bcs     @move
        jsr     line_of_sight
        bcs     @move
        lda     #SND_ESHOOT
        jsr     sfx_snd
        ldx     ti
        lda     #S_ATTACK
        sta     t_state,x
        lda     #3
        sta     t_timer,x
        rts
@move:  ldx     ti              ; close in, but not right on top
        lda     edist
        bne     *+5
        jmp     @r2
        inc     t_anim,x
        ldy     t_type,x
        lda     walk_speed-1,y
        sta     estep
        ; x
        lda     tdx_hi
        ora     tdx_lo
        beq     @my
        lda     t_x_lo,x
        ldy     tdx_hi
        bmi     @xm
        clc
        adc     estep
        sta     nx_lo
        lda     t_x_hi,x
        adc     #0
        jmp     @xs
@xm:    sec
        sbc     estep
        sta     nx_lo
        lda     t_x_hi,x
        sbc     #0
@xs:    sta     nx_hi
        tax                     ; free there? (its own row)
        ldy     ti
        lda     t_y_hi,y
        tay
        jsr     tile_at
        bne     @my
        ldx     ti
        lda     nx_lo
        sta     t_x_lo,x
        lda     nx_hi
        sta     t_x_hi,x
@my:    ldx     ti
        lda     tdy_hi
        ora     tdy_lo
        beq     @r2
        lda     t_y_lo,x
        ldy     tdy_hi
        bmi     @ym
        clc
        adc     estep
        sta     ny_lo
        lda     t_y_hi,x
        adc     #0
        jmp     @ys
@ym:    sec
        sbc     estep
        sta     ny_lo
        lda     t_y_hi,x
        sbc     #0
@ys:    sta     ny_hi
        tay
        lda     t_x_hi,x
        tax
        jsr     tile_at
        bne     @r2
        ldx     ti
        lda     ny_lo
        sta     t_y_lo,x
        lda     ny_hi
        sta     t_y_hi,x
@r2:    rts

; an enemy's shot or blow lands (or not)
resolve_attack:
        ldx     ti
        lda     t_type,x
        cmp     #T_BRUTE
        beq     @brute
        jsr     rand            ; grunt: 60 % to hit for 3-10
        cmp     #150
        bcs     @miss
        jsr     rand
        and     #7
        clc
        adc     #3
        jmp     hurt
@brute: lda     edist           ; brute: close up it hits hard
        cmp     #2
        bcs     @far
        jsr     rand
        and     #15
        clc
        adc     #10
        jmp     hurt
@far:   jsr     rand
        cmp     #110
        bcs     @miss
        jsr     rand
        and     #7
        clc
        adc     #6
        jmp     hurt
@miss:  rts

; the player loses A health
hurt:   sta     tmp3
        lda     #SND_OUCH
        jsr     sfx_snd
        lda     health
        sec
        sbc     tmp3
        bcs     @ok
        lda     #0
@ok:    sta     health
        lda     #<ouch_txt
        ldy     #>ouch_txt
        jmp     message

; edist = roughly the distance in tiles from tdx, tdy (max + min / 2)
approx_dist:
        lda     tdx_hi
        bpl     @x
        lda     tdx_lo          ; |dx| in whole tiles (rounded)
        eor     #$FF
        clc
        adc     #1
        lda     tdx_hi
        eor     #$FF
        adc     #0
@x:     sta     tmp
        lda     tdy_hi
        bpl     @y
        lda     tdy_lo
        eor     #$FF
        clc
        adc     #1
        lda     tdy_hi
        eor     #$FF
        adc     #0
@y:     sta     tmp2
        cmp     tmp
        bcc     @s
        lda     tmp             ; tmp = max, tmp2 = min
        ldy     tmp2
        sta     tmp2
        sty     tmp
@s:     lda     tmp2
        lsr
        clc
        adc     tmp
        bcc     @d
        lda     #255
@d:     sta     edist
        rts

; carry clear if enemy ti can see the player: 16 samples along the line
line_of_sight:
        ldx     ti
        lda     t_x_lo,x
        sta     lx_lo
        lda     t_x_hi,x
        sta     lx_hi
        lda     t_y_lo,x
        sta     ly_lo
        lda     t_y_hi,x
        sta     ly_hi
        lda     tdx_lo          ; step = d / 16 (arithmetic shift)
        sta     sx_lo
        lda     tdx_hi
        sta     sx_hi
        lda     tdy_lo
        sta     sy_lo
        lda     tdy_hi
        sta     sy_hi
        ldx     #4
@sh:    lda     sx_hi
        cmp     #$80
        ror     sx_hi
        ror     sx_lo
        lda     sy_hi
        cmp     #$80
        ror     sy_hi
        ror     sy_lo
        dex
        bne     @sh
        lda     #15
        sta     guard
@l:     lda     lx_lo
        clc
        adc     sx_lo
        sta     lx_lo
        lda     lx_hi
        adc     sx_hi
        sta     lx_hi
        lda     ly_lo
        clc
        adc     sy_lo
        sta     ly_lo
        lda     ly_hi
        adc     sy_hi
        sta     ly_hi
        ldx     lx_hi
        ldy     ly_hi
        jsr     tile_at
        bne     @no
        dec     guard
        bne     @l
        clc
        rts
@no:    sec
        rts

; ---- the player's gun -------------------------------------------------------------------
do_fire:lda     fire
        beq     @r
        lda     cool
        bne     @r
        lda     ammo
        bne     @shoot
        lda     #SND_CLICK
        jsr     sfx_snd
        lda     #<noammo_txt
        ldy     #>noammo_txt
        jsr     message
        lda     #8
        sta     cool
@r:     rts
@shoot: dec     ammo
        lda     #SND_PISTOL
        jsr     sfx_snd
        lda     #2
        sta     gun_t
        lda     #3
        sta     cool
        ; the noise wakes enemies nearby
        ldx     #MAXT-1
@wk:    lda     t_state,x
        cmp     #S_IDLE
        bne     @wn
        lda     t_type,x
        cmp     #T_MEDKIT
        bcs     @wn
        lda     t_x_hi,x        ; within 8 tiles?
        sec
        sbc     px_hi
        clc
        adc     #8
        cmp     #17
        bcs     @wn
        lda     t_y_hi,x
        sec
        sbc     py_hi
        clc
        adc     #8
        cmp     #17
        bcs     @wn
        lda     #S_CHASE
        sta     t_state,x
@wn:    dex
        bpl     @wk
        ; hit the nearest enemy on screen across the middle column
        lda     #$FF
        sta     hit
        ldx     nvis
@h:     dex
        bmi     @hd
        ldy     v_t,x
        lda     t_type,y
        cmp     #T_MEDKIT
        bcs     @h
        lda     t_state,y
        cmp     #S_CHASE
        bcc     @h
        cmp     #S_DEAD
        bcs     @h
        lda     v_h,x           ; half width in columns = h / 6 + 1
        ldy     #0
        sty     tmp
        lsr
        lsr
        sta     tmp2
        lsr
        clc
        adc     tmp2            ; (h / 4 + h / 8 ... about h / 6 + h / 8: generous)
        lsr
        clc
        adc     #1
        sta     tmp
        lda     v_sx_lo,x       ; |sx - 60| <= half width ?
        sec
        sbc     #COLS / 2
        sta     tmp2
        lda     v_sx_hi,x
        sbc     #0
        bpl     @hp
        lda     #0
        sec
        sbc     tmp2
        sta     tmp2
        lda     #0              ; (beyond -255 can't happen)
@hp:    bne     @h
        lda     tmp2
        cmp     tmp
        bcs     @h
        lda     v_d_hi,x        ; in front of the wall in the middle?
        cmp     zb_hi+COLS/2
        bcc     @hv
        bne     @h
        lda     v_d_lo,x
        cmp     zb_lo+COLS/2
        bcs     @h
@hv:    stx     hit             ; drawn far to near: the last one is nearest
        jmp     @hd
@hd:    ldx     hit
        bmi     @r2
        ldy     v_t,x
        sty     ti
        jsr     rand
        and     #15
        clc
        adc     #12
        sta     tmp
        ldx     ti
        lda     t_hp,x
        sec
        sbc     tmp
        bcc     @kill
        beq     @kill
        sta     t_hp,x
        lda     #SND_PAIN
        jmp     sfx_snd
@kill:  lda     #SND_KILL
        jsr     sfx_snd
        lda     #S_DEAD
        sta     t_state,x
        inc     kills
        lda     #<kill_txt
        ldy     #>kill_txt
        jmp     message
@r2:    rts


        .segment "RODATA"
        .include "doom_sound.inc"       ; the music and effects (game_sounds.py)

maprow_lo:
.repeat 32, I
        .byte   <(MAP + I * 32)
.endrepeat
maprow_hi:
.repeat 32, I
        .byte   >(MAP + I * 32)
.endrepeat
bitmask:.byte   $01, $02, $04, $08, $10, $20, $40, $80
thing_col:      ; (by type) the colour, high nibble
        .byte   0, C_GREEN << 4, C_BRICK << 4, C_STONE << 4, C_YELLOW << 4
shoot_chance:   .byte 18, 26            ; per frame, out of 256 (grunt, brute)
walk_speed:     .byte 22, 16            ; 1/256 tile per frame

first_name:     .byte "MAP01.LVL", 0, 0, 0, 0


; ---- the display: R0-R7 (Graphics II: patterns $0000, colours $2000, names
; $3800, sprite attributes $3B00, sprite patterns $1800; display off until
; gfx_init; black around)
vdp_regs:
        .byte   $02, $82, V_NAME/$400, $FF, $03, V_SATTR/$80, V_SPR/$800, $01
f18a_regs:      ; register, value
        .byte   24, 0
        .byte   29, $40                 ; sprite planes 1K apart
        .byte   30, 31                  ; 31 sprites a line
        .byte   50, 0
        .byte   49, $02                 ; ECM2 sprites (the bitmap as ever)
F18A_N = 5

; ---- text (tables: column, row, .word text ... $FF; rows 18-23 are the
; status lines, the rest is drawn into the bitmap) ----------------------------------
need_txt:
        .byte   13, 10, "DOOM2 NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
title_txt:
        .byte   14, 7
        .word   t_6502
        .byte   4, 9
        .word   t_t1
        .byte   10, 10
        .word   t_t2
        .byte   0, 11
        .word   t_t3
        .byte   0, 12
        .word   t_t4
        .byte   0, 13
        .word   t_t5
        .byte   0, 14
        .word   t_t6
        .byte   0, 15
        .word   t_t7
        .byte   4, 21
        .word   t_t8
        .byte   $FF
t_6502: .byte   "6502", 0
t_t1:   .byte   "A FIRST PERSON SHOOTER,", 0
t_t2:   .byte   "MORE OR LESS", 0
t_t3:   .byte   "KEYS: W/S MOVE  A/D TURN", 0
t_t4:   .byte   "  , . STRAFE  SPACE FIRE  E USE", 0
t_t5:   .byte   "  P PAUSE  M SOUND  Q QUIT", 0
t_t6:   .byte   "PAD: D-PAD MOVE/TURN  A FIRE", 0
t_t7:   .byte   "  B USE  SELECT+L/R STRAFE", 0
t_t8:   .byte   "SPACE OR START: NEW GAME", 0
noload_note:
        .byte   0, 19
        .word   t_nl
        .byte   $FF
t_nl:   .byte   "NO SBC_LOAD: ONLY THE FIRST MAP", 0
loading_txt:    .byte "LOADING ", 0
loaderr_txt:    .byte "COULD NOT LOAD IT: ERROR $", 0
badlvl_txt:     .byte "THAT IS NOT A LEVEL FILE", 0
noload_txt:     .byte "NO SBC_LOAD TO LOAD MORE MAPS", 0
anykey_txt:     .byte "PRESS A KEY", 0
hud_txt:
        .byte   0, 18
        .word   h_line
        .byte   0, 19
        .word   h_health
        .byte   13, 19
        .word   h_ammo
        .byte   0, 20
        .word   h_kills
        .byte   16, 20
        .word   h_items
        .byte   $FF
h_line: .byte   "--------------------------------", 0
h_health:.byte  "HEALTH", 0
h_ammo: .byte   "AMMO", 0
h_kills:.byte   "KILLS", 0
h_items:.byte   "ITEMS", 0
help_kb:.byte   "WS MOVE AD TURN SPC FIRE E USE", 0
help_pad:
        .byte   "A FIRE B USE SELECT+<> STRAFE", 0
paused_txt:     .byte "PAUSED", 0
door_txt:       .byte "THE DOOR OPENS", 0
medkit_txt:     .byte "PICKED UP A MEDKIT", 0
ammo_txt:       .byte "PICKED UP SOME AMMO", 0
noammo_txt:     .byte "OUT OF AMMO!", 0
ouch_txt:       .byte "OUCH! YOU ARE HIT", 0
kill_txt:       .byte "GOT ONE!", 0
died_txt:       .byte "YOU DIED.", 0
died2_txt:      .byte "SPACE/START: AGAIN   Q: TITLE  ", 0
done_txt:       .byte "FINISHED ", 0
done2_txt:      .byte "KILLS ", 0
done3_txt:      .byte "ITEMS ", 0
next_txt:
        .byte   0, 12
        .word   n_1
        .byte   $FF
n_1:    .byte   "SPACE/START: ON TO THE NEXT MAP", 0
win_txt:
        .byte   0, 12
        .word   w_1
        .byte   9, 14
        .word   w_2
        .byte   $FF
w_1:    .byte   "THAT WAS THE LAST MAP. YOU WIN!", 0
w_2:    .byte   "(A KEY: TITLE)", 0
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD (G: PAD)    ", 0
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD  (G: KEYS)   ", 0

; ---- the SBC_LOAD parameter block ------------------------------------------------------
        .segment "DATA"
lp_block:
        .word   LEVEL_BUF       ; load address
        .word   LEVEL_MAX       ; most bytes to load
lp_name:.res    13              ; "NAME.EXT", 0


        .segment "BSS"
bss_start:
; ---- the PICO9918 display
wf_n:       .res 1
last_tick:  .res 1
t_col:      .res 1
t_row:      .res 1
t_sx:       .res 1
t_sy:       .res 1
t_ch:       .res 1
t_ca:       .res 2
t_fa:       .res 1
t_lead:     .res 1
tt_i:       .res 1
tt_c:       .res 1
pgrp:       .res 1
grp:        .res 8
dg_k:       .res 1
dg_t:       .res 1
dg_b0:      .res 4
dg_b1:      .res 4
dg_b2:      .res 4
attr:       .res 1
ctrl:       .res 1
pad:        .res 1              ; gamepad buttons held
padold:     .res 1
padnew:     .res 1              ; newly pressed this tick
rng:        .res 2
has_load:   .res 1
load_err:   .res 1
lead:       .res 1
; maths
m_a:        .res 1
m_b:        .res 1
m_lo:       .res 1
m_hi:       .res 1
mf:         .res 1
w_lo:       .res 1
w_hi:       .res 1
r_lo:       .res 1
r_hi:       .res 1
sm_s:       .res 1
sm_a:       .res 1
sm_sign:    .res 1
n0:         .res 1
n1:         .res 1
n2:         .res 1
d0:         .res 1
d1:         .res 1
rm0:        .res 1
rm1:        .res 1
a_lo:       .res 1
a_hi:       .res 1
; the player
px_lo:      .res 1
px_hi:      .res 1
py_lo:      .res 1
py_hi:      .res 1
pa_lo:      .res 1
pa_hi:      .res 1
health:     .res 1
ammo:       .res 1

ammo0:      .res 1
kills:      .res 1
kills_max:  .res 1
items:      .res 1
items_max:  .res 1
sh_health:  .res 1
sh_ammo:    .res 1
sh_kills:   .res 1
sh_items:   .res 1
msg_t:      .res 1
gun_t:      .res 1
cool:       .res 1
done:       .res 1
frame:      .res 1
; input
mv_fwd:     .res 1
mv_turn:    .res 1
mv_strafe:  .res 1
fire:       .res 1
use:        .res 1
quit:       .res 1
esc_st:     .res 1
mx_lo:      .res 1
mx_hi:      .res 1
my_lo:      .res 1
my_hi:      .res 1
nx_lo:      .res 1
nx_hi:      .res 1
ny_lo:      .res 1
ny_hi:      .res 1
ux:         .res 1
uy:         .res 1
; ray casting
col:        .res 1
ra_lo:      .res 1
ra_hi:      .res 1
ta_lo:      .res 1
ta_hi:      .res 1
tb_lo:      .res 1
tb_hi:      .res 1
dx_lo:      .res 1
dx_hi:      .res 1
dy_lo:      .res 1
dy_hi:      .res 1
ff:         .res 1
spx_lo:     .res 1
spx_hi:     .res 1
spy_lo:     .res 1
spy_hi:     .res 1
sx_lo:      .res 1
sx_hi:      .res 1
sy_lo:      .res 1
sy_hi:      .res 1
mp_lo:      .res 1
mp_hi:      .res 1
pbase_lo:   .res 1
pbase_hi:   .res 1
item:       .res 1              ; drawing an item (half size)
edge:       .res 1              ; the tile at the edge of a move
zmax:       .res 1              ; farthest wall this frame (whole tiles)
guard:      .res 1
side:       .res 1
tile:       .res 1
dist_lo:    .res 1
dist_hi:    .res 1
idx_lo:     .res 1
idx_hi:     .res 1
hgt:        .res 1
band:       .res 1
pat:        .res 1
lastc_lo:   .res 1
lastc_hi:   .res 1
lastside:   .res 1
y0:         .res 1
y1:         .res 1
r0:         .res 1
r1:         .res 1
t0:         .res 1
t1:         .res 1
lo4:        .res 1
hi4:        .res 1
msk:        .res 1
zb_lo:      .res COLS
zb_hi:      .res COLS
c_hgt:      .res COLS          ; per column: wall height
c_pidx:     .res COLS          ;   pattern index (style*8 + side*4 + band)
c_mplo:     .res COLS          ;   map address of the block hit
c_mphi:     .res COLS
; sending the frame
prow:       .res 1
pcol:       .res 1
cur_r:      .res 1
cur_c:      .res 1
val:        .res 1
force:      .res 1              ; draw the next frame whatever
pace:       .res 1              ; the terminal answers IDENTIFY: frames are paced
rp_out:     .res 1              ; IDENTIFYs not answered yet
rp_in:      .res 1              ; in an answer (its S or P came, not its 1)
rp_t:       .res 1              ; ms left to wait
kbuf:       .res 1              ; a key kept by idle_wait
kbuf_n:     .res 1
iw_n:       .res 1

vchg:       .res 1
mapver:     .res 1              ; counts changes to the map (doors)
vstate:     .res 8              ; what the last frame was drawn from
vt_state:   .res MAXT
vt_x_lo:    .res MAXT
vt_x_hi:    .res MAXT
vt_y_lo:    .res MAXT
vt_y_hi:    .res MAXT
vt_anim:    .res MAXT
cur_rep:    .res 1              ; the repeat count the terminal has now
need:       .res 1
runl:       .res 1
kcnt:       .res 1
; things
tcount:     .res 1
t_type:     .res MAXT
t_x_lo:     .res MAXT
t_x_hi:     .res MAXT
t_y_lo:     .res MAXT
t_y_hi:     .res MAXT
t_state:    .res MAXT
t_hp:       .res MAXT
t_timer:    .res MAXT
t_anim:     .res MAXT
; things on screen this frame (6 arrays in this order, see swap_vis)
v_t:        .res MAXT
v_sx_lo:    .res MAXT
v_sx_hi:    .res MAXT
v_d_lo:     .res MAXT
v_d_hi:     .res MAXT
v_h:        .res MAXT
nvis:       .res 1
vi:         .res 1
si:         .res 1
sj:         .res 1
ti:         .res 1
psin:       .res 1
pcos:       .res 1
tdx_lo:     .res 1
tdx_hi:     .res 1
tdy_lo:     .res 1
tdy_hi:     .res 1
acc_lo:     .res 1
acc_hi:     .res 1
dep_lo:     .res 1
dep_hi:     .res 1
lat_sign:   .res 1
sh:         .res 1
sdep_lo:    .res 1
sdep_hi:    .res 1
st_lo:      .res 1
st_hi:      .res 1
x0_lo:      .res 1
x0_hi:      .res 1
cc:         .res 1
bu0:        .res 1
bu1:        .res 1
rr:         .res 1
kk:         .res 1
cm:         .res 1
cf:         .res 1
tm:         .res 1
tf:         .res 1
vtab:       .res VH
edist:      .res 1
estep:      .res 1
lx_lo:      .res 1
lx_hi:      .res 1
ly_lo:      .res 1
ly_hi:      .res 1
hit:        .res 1
col_on:     .res 1              ; colours: draw_group writes them
pfull:      .res 1              ; present: draw every group
gun_y:      .res 1              ; 56 = the gun fired this frame, else 0
dg_cell:    .res 1
dg_n:       .res 1
cl_b:       .res 1
cl_f:       .res 1
cl_2:       .res 1
cl_g:       .res 1              ; the gun's colour this frame
tmp:        .res 1
tmp2:       .res 1
tmp3:       .res 1
; ---- the picture (view.s)
c_u:        .res COLS           ; where each column's ray hit its face (1/256)
pb:         .res VH             ; a cell column: its patterns,
cb:         .res VH             ;   colours,
bp:         .res 8              ;   where its columns walls start and end
dmin:       .res 1              ;   the lines it changed
dmax:       .res 1
pf_v:       .res 1
pf_b:       .res 2
pf_x:       .res 1
cy0:        .res 4              ; its columns' tops and bottoms
cy1:        .res 4
th_x0_lo:   .res MAXT           ; the visible things: first column,
th_x0_hi:   .res MAXT
th_w:       .res MAXT           ;   width,
th_y0:      .res MAXT           ;   lines
th_y1:      .res MAXT
th_vs_lo:   .res MAXT           ;   texel steps
th_vs_hi:   .res MAXT
th_us_lo:   .res MAXT
th_us_hi:   .res MAXT
th_art_lo:  .res MAXT           ;   picture, colour
th_art_hi:  .res MAXT
th_col:     .res MAXT
ga:         .res 1
gb:         .res 1
ia:         .res 1
ib:         .res 1
vx:         .res 1
c0:         .res 1
ymin:       .res 1
ymax:       .res 1
ymin1:      .res 1
ymax1:      .res 1
hbest:      .res 1
cbest:      .res 1
fgc:        .res 1
tj:         .res 1
th:         .res 1
tmask:      .res 1
ty0:        .res 1
l0:         .res 1
l1:         .res 1
tk:         .res 1
ta_c:       .res 2
ta_b:       .res 2
any:        .res 1
en:         .res 4
mk:         .res 4
tcol:       .res 1
tvs:        .res 2
vacc:       .res 2
tl:         .res 1
tl1:        .res 1
tmk:        .res 1
tbd:        .res 1
tmp4:       .res 1
gn:         .res 1
bob:        .res 1
gbx:        .res 1
gby:        .res 1
bss_end:
