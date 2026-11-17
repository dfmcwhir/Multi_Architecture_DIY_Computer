; ============================================================================
; smb.s - SUPER MOS BROS. for the 6502 SBC, CPU Rev2, on the PICO9918 card
;
;   build:  make.bat  (ca65 -I .. smb.s, ld65 -C smb.cfg)
;   run:    L SMB 0800   then  R       (WORLD1.SMB ... WORLD5.SMB on the drive)
;
; Header (patchable from the monitor):
;   $0800  JMP start
;   $0803  speed      frames (1/60 s) per game frame: 3 = 20 a second, the
;                     speed the game was made for
;   $0804  controls   at start: 0 keyboard, 1 gamepad
;   $0805  (spare)
;   $0806  sound      at start: 0 on, 1 off
;
; The game (MOS, the objects, the levels, the sound) is the PIC32 version's;
; the drawing is new, for the PICO9918 in its F18A mode:
;   - everything is drawn at the screen's full resolution, in the F18A's
;     enhanced colour mode ECM2: each tile and each sprite has 3 colours of
;     its own (art_hd.py, gen_pico.py -> smb_pico.inc).
;   - tile layer 1 (Graphics I): the level: a tile (8 x 8 game pixels) is
;     2 x 2 cells of 16 x 16 pixels of art.  Two name table pages side by
;     side make a ring 32 tiles wide; it scrolls smoothly with the hardware
;     scroll (R27, and the page bit in R2), and only the tile columns coming
;     into view are written.  11 tile rows = cell rows 2-23.
;   - tile layer 2, on top: the status lines (cell rows 0-1) and the texts;
;     everything else on it is pattern 0, see-through.
;   - the sprites: 16 x 16, each picture cut into parts (MOS: a second layer
;     for his hair, eyes and shoes); mirrored with the F18A's flip bit.  Each
;     hardware sprite has its own pattern: a part is copied into it when
;     that sprite's part changes.
;   A game pixel is 2 x 2 screen pixels; the view is 128 x 88 game pixels.
; No zero page is used.
; ============================================================================

        .setcpu "6502"
        .include "sbc_api.inc"

SPEED_DEFAULT   = 3             ; frames per game frame

; ---- VRAM -----------------------------------------------------------------------
V_TP0           = $0000         ; tile patterns (both layers), plane 0
V_TP1           = $0800         ;   plane 1
V_SP0           = $1000         ; sprite patterns, plane 0: sprite k at names 4 k
V_SP1           = $1400         ;   plane 1 (1K on: R29's SPGS = 01)
V_NAME1         = $1800         ; layer 1 names: pages $1800 and $1C00
V_NAME2         = $2000         ; layer 2 names
V_ATT1          = $2300         ; layer 1 attributes (one a pattern)
V_ATT2          = $2400         ; layer 2 attributes
V_SATTR         = $2500         ; sprite attributes
VDP_NAME        = V_NAME2       ; (vdp_at, vdp_puts: layer 2, the texts)
MAXSPR          = 31            ; hardware sprites used at most

; ---- the view ----------------------------------------------------------------------
MAPROWS         = 11
VIEW_H          = 88            ; game pixels
VIEW_W          = 128           ; game pixels (16 tiles)
VIEW_T          = 16            ; tiles across
VIEW_COLS       = VIEW_W / 2    ; in the old "characters" (2 game pixels):
                                ; the game keeps scroll in those
TOP_Y           = 16            ; screen y of the view's top (2 status rows)
LOADMAX         = 16 * 256      ; the world file buffer (wc)

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
SOUND           = 1

; ============================================================================
        .segment "RODATA"
        .include "smb_pico.inc"
        .include "smb_sound.inc"     ; the music and effects (sound.py)

        .segment "CODE"
        jmp     start
speed:  .byte   SPEED_DEFAULT
ctrl_def:.byte  1               ; controls at start: 0 keyboard, 1 gamepad
        .byte   0               ; (spare)
mute_def:.byte  0               ; sound at start: 0 on, 1 off
        .byte   0

        .include "ay/sfx.s"     ; the sound engine (AY-3-8910 card)
        .include "lib/vdp.s"    ; the PICO9918 routines

; ----------------------------------------------------------------------------
; helpers
; ----------------------------------------------------------------------------
getc            = SBC_CHRIN     ; carry set = key in A

; called by vdp_frame while it waits
frame_idle:
        jmp     sfx_poll

; 16 bit Galois LFSR.  A = a random byte.  Preserves X and Y.
rand:   lda     rng+1
        lsr
        ror     rng
        bcc     @n
        eor     #$B4
@n:     sta     rng+1
        eor     rng
        rts

; wait A frames (1/60 s), dropping keys
wait_frames:
        sta     wf_n
@l:     jsr     vdp_frame
        jsr     flush_in
        dec     wf_n
        bne     @l
        rts

; wait about A x 50 ms (as the PIC32 version: 3 frames each)
delay_long:
        sta     tmp
@l:     lda     #3
        jsr     wait_frames
        dec     tmp
        bne     @l
        rts

; layer 2 text: print a table of column, row, .word text ... $FF
print_table:
        sta     @rd+1
        sty     @rd+2
        ldx     #0
@l:     stx     pt_i
        jsr     @rd
        cmp     #$FF            ; (the end; column 0 is a column)
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

; A as two hex digits (layer 2, at the address set).  Keeps X, Y.
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
        sta     VDP_DATA
        rts

; A (0-99) in decimal, without a leading zero.  Keeps Y.
prdec:  ldx     #'0'
@t:     cmp     #10
        bcc     @u
        sbc     #10
        inx
        bne     @t
@u:     cpx     #'0'
        beq     @one
        stx     VDP_DATA
@one:   ora     #'0'
        sta     VDP_DATA
        rts

; A as two BCD digits.  Keeps X, Y.
prbcd = vdp_bcd

; layer 2: rows Y.. (A of them) see-through again
clear_rows:
        sta     tmp2
@r:     ldx     #0
        jsr     vdp_at
        ldx     #32
        lda     #0
@c:     sta     VDP_DATA
        dex
        bne     @c
        iny
        dec     tmp2
        bne     @r
        rts

; layer 2: a box of A rows of spaces (opaque black) from row Y, for text
black_rows:
        sta     tmp2
@r:     ldx     #0
        jsr     vdp_at
        ldx     #32
        lda     #' '
@c:     sta     VDP_DATA
        dex
        bne     @c
        iny
        dec     tmp2
        bne     @r
        rts

.macro MENU_IDLE
        jsr     vdp_frame       ; (a frame at a time: the sound goes on)
        jsr     rand            ; (waiting stirs the random numbers)
.endmacro

; ============================================================================
; the display
; ============================================================================

;
; set up the VDP: the registers, the tile patterns (2 planes), their
; attributes, the palette, the F18A's features
gfx_init:
        lda     #<vdp_regs
        ldy     #>vdp_regs
        jsr     vdp_setup
        lda     #<V_TP0
        ldy     #>V_TP0
        jsr     vdp_waddr
        lda     #<tile_p0
        ldx     #>tile_p0
        jsr     @copy
        lda     #<V_TP1
        ldy     #>V_TP1
        jsr     vdp_waddr
        lda     #<tile_p1
        ldx     #>tile_p1
        jsr     @copy
        lda     #<V_ATT1
        ldy     #>V_ATT1
        jsr     vdp_waddr
        jsr     @attr
        lda     #<V_ATT2
        ldy     #>V_ATT2
        jsr     vdp_waddr
        jsr     @attr
        lda     #$C0            ; the palette (R47: the data port writes it,
        ldx     #47             ; counting up from entry 0)
        jsr     vdp_reg
        ldx     #0
@pl:    lda     pal_data,x
        sta     VDP_DATA
        inx
        bpl     @pl
        lda     #0              ; (the data port: VRAM again)
        ldx     #47
        jsr     vdp_reg
        ldx     #0              ; the F18A registers
@fr:    stx     tmp
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
        bne     @fr
        jsr     forget_parts
        jsr     no_sprites
        jsr     put_sprites
        lda     #$C2            ; R1: display on, 16 x 16 sprites, no
        ldx     #1              ; interrupt
        jmp     vdp_reg
@copy:  sta     vdp_src
        stx     vdp_src+1
        lda     #<(NPAT * 8)
        sta     vdp_n
        lda     #>(NPAT * 8)
        sta     vdp_n+1
        jmp     vdp_copy
@attr:  lda     #<tile_attr
        sta     vdp_src
        lda     #>tile_attr
        sta     vdp_src+1
        lda     #0
        sta     vdp_n
        lda     #1
        sta     vdp_n+1
        jmp     vdp_copy

; a text screen: layer 1 blank, black, no scroll, no sprites, layer 2 clear
text_screen:
        jsr     no_sprites
        jsr     put_sprites
        lda     #0
        ldx     #27
        jsr     vdp_reg
        lda     #V_NAME1/$400
        ldx     #2
        jsr     vdp_reg
        lda     #$01            ; R7: black
        ldx     #7
        jsr     vdp_reg
        lda     #<V_NAME1
        ldy     #>V_NAME1
        jsr     vdp_waddr
        lda     #0
        sta     vdp_n
        lda     #8
        sta     vdp_n+1
        lda     #0
        jsr     vdp_fill
        ldy     #0
        lda     #24
        jmp     clear_rows

; the sprite table: none
no_sprites:
        lda     #$D0
        sta     spr_tab
        lda     #0
        sta     nspr
        rts

; the sprite table to VRAM (in the frame's blank, best): first the parts
; that changed into their sprites' patterns
put_sprites:
        ldx     #0
@pp:    cpx     nspr
        bcs     @tab
        lda     sl_want,x
        cmp     sl_have,x
        beq     @pn
        sta     sl_have,x
        stx     ps_k
        jsr     load_part
        ldx     ps_k
@pn:    inx
        bne     @pp
@tab:   lda     #<V_SATTR
        ldy     #>V_SATTR
        jsr     vdp_waddr
        ldx     #0
@l:     lda     spr_tab,x
        sta     VDP_DATA
        cmp     #$D0            ; (the end: only on a Y byte)
        bne     @n
        txa
        and     #3
        beq     @r
@n:     inx
        bne     @l
@r:     rts

; part A into sprite X's pattern: 32 bytes into each plane
load_part:
        sta     tmp                     ; spr_parts + part * 64
        lda     #0
        sta     tmp+1
        ldy     #6
@m:     asl     tmp
        rol     tmp+1
        dey
        bne     @m
        lda     tmp
        clc
        adc     #<spr_parts
        sta     @a+1
        sta     @b+1
        lda     tmp+1
        adc     #>spr_parts
        sta     @a+2
        sta     @b+2
        txa                             ; V_SP0 / V_SP1 + 32 x
        lsr
        lsr
        lsr
        sta     tmp+1
        txa
        asl
        asl
        asl
        asl
        asl
        sta     tmp
        lda     tmp+1
        clc
        adc     #>V_SP0
        tay
        lda     tmp
        jsr     vdp_waddr
        ldx     #0
@a:     lda     $FFFF,x
        sta     VDP_DATA
        inx
        cpx     #32
        bne     @a
        lda     tmp+1
        clc
        adc     #>V_SP1
        tay
        lda     tmp
        jsr     vdp_waddr
@b:     lda     $FFFF,x                 ; (x 32-63: plane 1)
        sta     VDP_DATA
        inx
        cpx     #64
        bne     @b
        rts

; every sprite's part forgotten (they are loaded again)
forget_parts:
        ldx     #31
        lda     #$FF
@f:     sta     sl_have,x
        dex
        bpl     @f
        rts

; ---- the level on layer 1 ---------------------------------------------------------

; put tile htc, htr on the screen (into the ring).  Preserves X.
put_tile:
        stx     pt_x
        lda     htr             ; the map row's page
        clc
        adc     #>map
        sta     @m+2
        ldy     htc
@m:     ldx     map,y           ; tile code (number * 4)
        lda     htc             ; ring column: (htc & 31) * 2 cells, page
        and     #15             ; (htc & 16)
        asl
        sta     pt_cc
        lda     htc
        and     #16
        lsr
        lsr                     ; page 1: +4 to the address' high byte
        sta     pt_pg
        lda     htr             ; cell row 2 + 2 * htr: address = row * 32
        asl
        clc
        adc     #2
        sta     pt_r
        jsr     @addr
        lda     tile_nm,x
        sta     VDP_DATA
        lda     tile_nm+1,x
        sta     VDP_DATA
        inc     pt_r
        jsr     @addr
        lda     tile_nm+2,x
        sta     VDP_DATA
        lda     tile_nm+3,x
        sta     VDP_DATA
        ldx     pt_x
        rts
@addr:  lda     pt_r            ; low: (row & 7) * 32 + column
        asl
        asl
        asl
        asl
        asl
        ora     pt_cc
        sta     VDP_CTRL
        lda     pt_r            ; high: row / 8 + page + write
        lsr
        lsr
        lsr
        ora     pt_pg
        ora     #$40 + >V_NAME1
        sta     VDP_CTRL
        rts

; tile column A, all 11 rows
put_col:
        sta     htc
        lda     htr
        pha
        lda     #0
        sta     htr
@r:     jsr     put_tile
        inc     htr
        lda     htr
        cmp     #MAPROWS
        bne     @r
        pla
        sta     htr
        rts

; the tile at htc, htr changed (the map has it): draw it if it is in the ring
tile_changed:
        lda     htc             ; htc - the view's first tile: 0 .. VIEW_T + 1?
        sec
        sbc     cam_t
        cmp     #VIEW_T + 2
        bcs     @r
        lda     htc             ; (and drawn already)
        cmp     drawn_hi
        bcs     @r
        jmp     put_tile
@r:     rts

; put tile A at htc, htr and show it
set_tile:
        pha
        lda     htr
        clc
        adc     #>map
        sta     @w+2
        ldy     htc
        pla
@w:     sta     map,y
        jmp     tile_changed

; ---- each frame: the scroll, new columns, the sprites ----------------------------
render: lda     sc2+1           ; cam_t = the view's first tile (sc2 / 8)
        sta     tmp
        lda     sc2
        lsr     tmp
        ror
        lsr     tmp
        ror
        lsr     tmp
        ror
        sta     cam_t
        lda     full            ; all of it again?
        beq     @cols
        lda     #0
        sta     full
        lda     cam_t
        sta     drawn_hi
@cols:  lda     cam_t           ; draw up to the view's last tile + 1
        clc
        adc     #VIEW_T + 1
        bcc     @c1
        lda     #$FF
@c1:    sta     tmp2
@c:     lda     drawn_hi
        cmp     tmp2
        beq     @c2
        bcs     @spr
@c2:    jsr     put_col
        inc     drawn_hi
        bne     @c              ; (column 255: the end)
@spr:   jmp     make_sprites

; the hardware scroll: screen x = sc2 * 2 (mod 512).  In the frame's blank.
set_scroll:
        lda     sc2
        asl
        ldx     #27
        jsr     vdp_reg
        lda     sc2+1
        rol
        and     #1
        ora     #V_NAME1/$400
        ldx     #2
        jmp     vdp_reg

; the sprite table for this frame (MOS first: on top)
make_sprites:
        lda     #0
        sta     nspr
        ldx     #O_MOS
        lda     o_kind
        beq     @objs
        jsr     mos_frame
        bcs     @objs
        jsr     add_obj
@objs:  ldx     #1
@l:     stx     ms_i
        lda     o_kind,x
        beq     @n
        jsr     obj_frame
        bcs     @n
        ldx     ms_i
        jsr     add_obj
@n:     ldx     ms_i
        inx
        cpx     #NOBJ
        bne     @l
        lda     nspr            ; the end of the list
        asl
        asl
        tax
        lda     #$D0
        sta     spr_tab,x
        rts

; object X with picture A (mirrored if smir): its blocks into the table
add_obj:
        asl
        ora     smir
        tay
        lda     sp_lo,y
        sta     @rd+1
        lda     sp_hi,y
        sta     @rd+2
        sec                     ; x on the screen (game pixels): x - sc2
        lda     o_xl,x
        sbc     sc2
        sta     ao_x
        lda     o_xh,x
        sbc     sc2+1
        sta     ao_x+1
        lda     o_y,x           ; y (signed: above the view is negative)
        sta     ao_y
        ldy     #0
        jsr     @rd             ; the count
        sta     ao_n
        bne     @b
        jmp     @r
@b:     lda     nspr
        cmp     #MAXSPR
        bcc     :+
        jmp     @r
:       iny
        jsr     @rd             ; dx (signed)
        sta     tmp
        iny
        jsr     @rd             ; dy
        sta     tmp2
        iny
        jsr     @rd
        sta     ao_p            ; part
        iny
        jsr     @rd
        sta     ao_c            ; attribute: colour group, flip
        sty     ao_i
        ; screen x = (x + dx) * 2: -16..255 shows (negative: the early clock)
        lda     tmp
        bpl     :+
        dec     ao_x+1          ; (sign-extend dx)
:       clc
        adc     ao_x
        sta     ao_sx
        lda     ao_x+1
        adc     #0
        sta     ao_sx+1
        lda     tmp             ; (undo the sign extension for the next)
        bpl     :+
        inc     ao_x+1
:       asl     ao_sx
        rol     ao_sx+1
        lda     ao_sx+1
        beq     @xok            ; 0..255
        cmp     #$FF
        beq     :+
        jmp     @skip
:
        lda     ao_sx           ; -32..-1: early clock, x + 32
        cmp     #$E0
        bcs     :+
        jmp     @skip
:       adc     #31             ; (carry set: +32)
        sta     ao_sx
        lda     ao_c
        ora     #$80
        sta     ao_c
@xok:   ; screen y = (y + dy) * 2 + TOP_Y: the top, -16 .. 191 shows
        lda     ao_y
        clc
        adc     tmp2
        sta     tmp
        lda     #0              ; (y is signed: bit 7)
        bit     ao_y
        bpl     :+
        lda     #$FF
:       adc     #0
        sta     tmp+1
        asl     tmp
        rol     tmp+1
        lda     tmp
        clc
        adc     #TOP_Y
        sta     tmp
        bcc     :+
        inc     tmp+1
:       lda     tmp+1
        beq     @yok            ; 0..255: under 192 only
        cmp     #$FF
        bne     @skip
        lda     tmp
        cmp     #$F0            ; -16..-1
        bcc     @skip
        bcs     @yset
@yok:   lda     tmp
        cmp     #192
        bcs     @skip
@yset:  lda     nspr            ; into the table: y - 1, x, pattern, colour
        asl
        asl
        tax
        lda     tmp
        sec
        sbc     #1
        cmp     #$D0            ; ($D0 would end the list)
        bne     :+
        lda     #$D1
:       sta     spr_tab,x
        lda     ao_sx
        sta     spr_tab+1,x
        txa                     ; its own pattern: names 4 n (= x)
        sta     spr_tab+2,x
        lda     ao_c
        sta     spr_tab+3,x
        txa                     ; ... and its part
        lsr
        lsr
        tax
        lda     ao_p
        sta     sl_want,x
        inc     nspr
@skip:  ldy     ao_i
        dec     ao_n
        beq     @r
        jmp     @b
@r:     ldx     ms_i
        rts
@rd:    lda     $FFFF,y
        rts

; ---- the frame's timing --------------------------------------------------------
; a game frame is speed frames: wait for them (the first comes at once if
; the game's work took longer than a frame), then show it: the scroll and
; the sprites go in at the start of the frame's blank.
pace:   lda     speed
        sta     wf_n
@w:     jsr     vdp_frame
        dec     wf_n
        bne     @w
        jsr     set_scroll
        jmp     put_sprites

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
        jsr     text_screen
        jsr     title_scene
        lda     #<title_txt
        ldy     #>title_txt
        jsr     print_table
        ldx     #18
        ldy     #13
        jsr     vdp_at
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
@notq:  cmp     #'M'            ; sound on / off
        bne     @notm
        jsr     toggle_sound
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

; the title's picture: some ground, a pipe, a ? block, a brick, MOS (layer 1)
title_scene:
        ldx     #0              ; an empty map
        txa
@clr:   .repeat MAPROWS, K
        sta     map + K * 256,x
        .endrepeat
        inx
        bne     @clr
        ldx     #15
@g:     lda     #T_GROUND
        sta     map + 10 * 256,x
        sta     map + 9 * 256,x
        dex
        bpl     @g
        lda     #T_PIPETL
        sta     map + 7 * 256 + 12
        lda     #T_PIPETR
        sta     map + 7 * 256 + 13
        lda     #T_PIPEL
        sta     map + 8 * 256 + 12
        lda     #T_PIPER
        sta     map + 8 * 256 + 13
        lda     #0
        sta     sc2
        sta     sc2+1
        lda     #$05            ; R7: sky
        ldx     #7
        jsr     vdp_reg
        lda     #1
        sta     full
        lda     #0              ; MOS on the ground, and an AND gate
        ldx     #NOBJ-1
@o:     sta     o_kind,x
        dex
        bpl     @o
        jsr     clear_obj0
        lda     #K_MOS
        sta     o_kind
        lda     #40
        sta     o_xl
        lda     #64
        sta     o_y
        lda     #1
        sta     onground
        ldx     #1
        jsr     clear_obj
        lda     #K_BUG
        sta     o_kind+1
        lda     #80
        sta     o_xl+1
        lda     #64
        sta     o_y+1
        lda     #0
        sta     big
        sta     mstate
        sta     duck
        sta     inv_t
        sta     oc_t
        sta     facing
        jsr     render
        jsr     set_scroll
        jmp     put_sprites

exit_game:
        jsr     sfx_off
        lda     #$C0            ; the PICO9918 back to its defaults (VR50: a
        ldx     #50             ; reset, the palette too)
        jsr     vdp_reg
        jsr     SBC_CONRESET    ; the console's text screen back
        jmp     SBC_MENU

; the controls line on the title screen
show_ctrl:
        ldx     #1
        ldy     #15
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
; a game
; ============================================================================
new_game:
        lda     #0
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

; ---- a level: "CELL 1-1  MOS x 3" for a moment, then play -------------------------
start_level:
        jsr     text_screen
        jsr     get_world       ; (worlds from the USB drive)
        bcc     @ok
        lda     wsrc            ; (no 1-1 at all: a word, and back to the title)
        cmp     #1
        bne     @nd
        lda     lvl
        bne     @nd
        lda     #<noworld_txt
        ldy     #>noworld_txt
        jsr     print_table
        lda     #100
        jsr     delay_long
        jmp     title
@nd:    lda     #<nodisk_txt    ; no more worlds: around again
        ldy     #>nodisk_txt
        jsr     print_table
        ldx     #15
        ldy     #10
        jsr     vdp_at
        lda     wsrc
        ora     #'0'
        sta     VDP_DATA
        lda     #60
        jsr     delay_long
        lda     #1
        sta     wsrc
        lda     #0
        sta     lvl
        jmp     start_level
@ok:    ldx     #12
        ldy     #9
        jsr     vdp_at
        lda     #<world_txt
        ldy     #>world_txt
        jsr     vdp_puts
        jsr     pr_world
        ldx     #12
        ldy     #12
        jsr     vdp_at
        lda     #<lives_txt
        ldy     #>lives_txt
        jsr     vdp_puts
        lda     lives
        jsr     prdec
        jsr     load_level
        lda     lv_flags        ; a castle: a word about KIL
        and     #1
        beq     @nk
        lda     #<kil_txt
        ldy     #>kil_txt
        jsr     print_table
@nk:    lda     #30
        jsr     delay_long
        jsr     new_screen
        jsr     sfx_off
        jsr     music_level

; ---- the frame loop --------------------------------------------------------------
game_loop:
        jsr     read_input
        lda     quit
        beq     @1
        jmp     title
@1:     jsr     mos_update
        jsr     obj_update
        jsr     fire_update
        jsr     obj_collide
        jsr     camera
        jsr     spawn_enemies
        jsr     clock
        jsr     render
        jsr     hud_update
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
        jsr     fanfare
        ldy     #3
        lda     #8
        jsr     black_rows
        lda     #<end_txt
        ldy     #>end_txt
        jsr     print_table
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
        jsr     fanfare
        jsr     text_screen     ; the end of a world
        lda     #<castle_txt
        ldy     #>castle_txt
        jsr     print_table
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
@nohi:  jsr     sfx_off
        lda     #SND_GOVERA
        jsr     snd
        lda     #SND_GOVERB
        jsr     snd
        ldy     #8
        lda     #6
        jsr     black_rows
        lda     #<over_txt
        ldy     #>over_txt
        jsr     print_table
        lda     #20
        jsr     delay_long
@wait:  jsr     menu_key
        cmp     #'Q'
        bne     @nq
        jmp     title
@nq:    cmp     #'M'
        bne     @nm
        jsr     toggle_sound
        jmp     @wait
@nm:    cmp     #' '
        beq     @again
        cmp     #PAD_GO
        bne     @wait
@again: jmp     new_game

; print the world and level: "1-1" (layer 2, at the address set)
pr_world:
        lda     world
        jsr     prdec
        lda     #'-'
        sta     VDP_DATA
        lda     lvl
        clc
        adc     #1
        jmp     prdec

; the playing screen: the status lines, the colour of the sky, the whole
; view drawn again (render, full)
new_screen:
        jsr     no_sprites
        jsr     put_sprites
        ldy     #0              ; the status lines: black
        lda     #2
        jsr     black_rows
        ldy     #2              ; the rest of layer 2: see-through
        lda     #22
        jsr     clear_rows
        lda     #<status_txt
        ldy     #>status_txt
        jsr     print_table
        lda     lv_flags        ; the sky: light blue; a castle, a room or
        and     #1              ; under the bricks: black; the coolant: dark
        bne     @blk            ; blue
        lda     lv_flags
        and     #2
        bne     @blu
        lda     in_room
        bne     @blk
        lda     lvl
        cmp     #1
        beq     @blk
        lda     #$05
        bne     @set
@blk:   lda     #$01
        bne     @set
@blu:   lda     #$04
@set:   ldx     #7
        jsr     vdp_reg
        lda     #1
        sta     hud_dirty
        sta     full
        rts

; the status lines (layer 2, rows 0-1)
hud_update:
        lda     hud_dirty
        bne     @go
        rts
@go:    lda     #0
        sta     hud_dirty
        ldx     #5
        ldy     #0
        jsr     vdp_at
        lda     score+2
        jsr     prhex
        lda     score+1
        jsr     prhex
        lda     score
        jsr     prhex
        ldx     #17
        jsr     vdp_at
        jsr     pr_world
        lda     #' '
        sta     VDP_DATA
        ldx     #28
        jsr     vdp_at
        lda     time+1
        and     #$0F
        ora     #'0'
        sta     VDP_DATA
        lda     time
        jsr     prbcd
        ldx     #6
        ldy     #1
        jsr     vdp_at
        lda     bytes
        jsr     prhex
        lda     #' '            ; the byte being filled: a 1 for each bit
        sta     VDP_DATA
        ldx     #8
@b:     lda     #'0'
        cpx     bits
        beq     @b1
        bcs     @b0
@b1:    lda     #'1'
@b0:    sta     VDP_DATA
        dex
        bne     @b
        ldx     #30
        jsr     vdp_at
        lda     lives
        jsr     prdec
        lda     #' '
        sta     VDP_DATA
        rts

; ---- the view follows MOS (forward only), a game pixel at a time -----------------
; sc2 = the view's left edge in game pixels (x - 64), scroll = sc2 / 2 (in the
; old characters, as the rest of the game keeps it)
camera: sec
        lda     o_xl
        sbc     #64
        sta     tmp
        lda     o_xh
        sbc     #0
        sta     tmp+1
        bcc     @r              ; (before the start)
        lda     tmp             ; further on than now?
        cmp     sc2
        lda     tmp+1
        sbc     sc2+1
        bcc     @r
        lda     max_sc          ; but not past the end: max_sc * 2
        asl
        sta     tmp2
        lda     max_sc+1
        rol
        sta     tmp3
        lda     tmp
        cmp     tmp2
        lda     tmp+1
        sbc     tmp3
        bcc     @set
        lda     tmp2
        sta     tmp
        lda     tmp3
        sta     tmp+1
@set:   lda     tmp
        sta     sc2
        lda     tmp+1
        sta     sc2+1
        lsr
        sta     scroll+1
        lda     tmp
        ror
        sta     scroll
@r:     rts

pause:  jsr     sfx_hush        ; (quiet while paused)
        ldy     #10
        lda     #1
        jsr     black_rows
        ldx     #13
        ldy     #10
        jsr     vdp_at
        lda     #<paused_txt
        ldy     #>paused_txt
        jsr     vdp_puts
        jsr     flush_in
@w:     jsr     read_pad
        lda     padnew
        and     #PAD_START
        bne     @go
        jsr     getc
        bcc     @w
@go:    jsr     flush_in
        ldy     #10
        lda     #1
        jmp     clear_rows

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
        sbc     #VIEW_COLS
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


; ============================================================================
; input
; ============================================================================
; in_dir: -1 / 0 / 1, in_run, hold (jump held), jump_buf (frames a jump
; press waits for MOS to be on the ground)
read_input:
        lda     ctrl            ; keyboard mode, but the pad is used: the pad
        bne     @pm
        jsr     read_pad
        lda     padnew
        beq     @keys
        lda     #1
        sta     ctrl
@pm:
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
        bne     :+
        jmp     @jump
:       cmp     #'B'
        bne     :+
        jmp     @stop
:       cmp     #'C'
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
@uc:    ldx     ctrl            ; the AVR keyboard's arrow keys
        bne     @ua
        cmp     #KEY_LEFT
        beq     @left
        cmp     #KEY_RIGHT
        beq     @right
        cmp     #KEY_UP
        beq     @jump
        cmp     #KEY_DOWN
        beq     @stop
@ua:    cmp     #'P'
        beq     @pause
        cmp     #'Q'
        beq     @quit
        cmp     #'M'
        beq     @mute
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
@mute:  jmp     toggle_sound
@quit:  lda     #1
        sta     quit
        rts


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
        bne     @c1
        jsr     music_level     ; (over: the level's music again)
@c1:
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
        jsr     music_stop
        lda     #SND_SLIDE
        jsr     snd
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
        lda     #SND_CLEARA     ; the level's done
        jsr     snd
        lda     #SND_CLEARB
        jsr     snd
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
        lda     time            ; (a tick for each 3 counts)
        ora     time+1
        beq     @nt
        lda     #SND_TICK
        jsr     snd
@nt:
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
        jsr     music_stop      ; (the castle's tune ends with KIL)
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
        lda     #SND_CRUMBLE
        jsr     snd
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
        jsr     music_stop
        lda     #SND_DIEA
        jsr     snd
        lda     #SND_DIEB
        jsr     snd
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
        lda     big
        beq     @js
        lda     #SND_JUMPBIG-SND_JUMP
@js:    clc
        adc     #SND_JUMP
        jsr     snd
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
        lda     #SND_SWIM
        jsr     snd
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
        lda     #SND_PIPE
        jsr     snd
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
        jmp     music_level     ; (the room has its own)

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
        pha
        lda     #SND_BUMP
        jsr     snd
        pla
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
        lda     #SND_SPROUT
        jsr     snd
        lda     #8              ; it rises out of the block for 8 frames
        sta     o_t,x
@k:     jmp     bump_kill
@brick: lda     big
        beq     @k
        lda     #SND_BREAK
        jsr     snd
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
        lda     #SND_COIN
        jsr     snd
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
        lda     #SND_KICK
        jsr     snd
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
        lda     #SND_BREATH
        jsr     snd
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
        lda     #SND_FIRE
        jsr     snd
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
        cpy     #VIEW_W
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
        lda     #SND_HIT
        jsr     snd
        lda     #8
        sta     dr_flash
        dec     dr_hp
        bne     @r
        lda     #SND_KILDIE
        jsr     snd
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
@x:     clc                     ; x + 16 - the view's left edge: 0..VIEW_W + 47
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
        cpy     #VIEW_W + 48
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
        lda     #SND_ONEUP
        jsr     snd
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
        lda     #SND_POWERUP
        jsr     snd
        lda     #MUS_STAR       ; its own music while it lasts
        jsr     music
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
        lda     #SND_POWERUP
        jsr     snd
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
        lda     #SND_KICK
        jsr     snd
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
        lda     #SND_STOMP
        jsr     snd
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
        lda     #SND_HURT
        jsr     snd
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
        adc     #VIEW_T + 2
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
        lda     time            ; 100 left: hurry
        bne     @h
        lda     time+1
        cmp     #1
        bne     @h
        lda     #SND_HURRY
        jsr     snd
@h:
        lda     time
        ora     time+1
        bne     @r
        jmp     die
@r:     rts

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
load_blk:                       ; SBC_LOAD's parameters: WORLDn.SMB into wc
        .word   wc
        .word   LOADMAX
load_name:
        .byte   "WORLD1.SMB", 0
.define FLAG_PTS 100, 200, 400, 500, 800, 1000, 2000, 3000, 4000, 5000
flag_pts_lo:                    ; 100 .. 5000 points by height
        .lobytes FLAG_PTS
flag_pts_hi:
        .hibytes FLAG_PTS



; ---- the display: registers and texts (layer 2: column, row, .word text ... $FF)
; R0-R7: Graphics I, display off (gfx_init turns it on), 16 x 16 sprites;
; layer 1 names $1800 (pages $1800/$1C00), attributes $2300, tile patterns
; $0000, sprite attributes $2500, sprite patterns $1000; backdrop: sky
vdp_regs:
        .byte   $00, $82, V_NAME1/$400, V_ATT1/$40, V_TP0/$800, V_SATTR/$80, V_SP0/$800, $05
; the F18A's: register, value
f18a_regs:
        .byte   10, V_NAME2 / $400      ; layer 2 names
        .byte   11, V_ATT2 / $40        ; layer 2 attributes
        .byte   24, 0                   ; (palette selects: ECM ignores them)
        .byte   29, $42                 ; sprite planes 1K apart; layer 1 two pages across
        .byte   30, 31                  ; 31 sprites a line
        .byte   50, 0                   ; layer 2 on top of everything
        .byte   49, $A2                 ; layer 2 on, ECM2 tiles, ECM2 sprites
F18A_N          = (* - f18a_regs) / 2

need_txt:
        .byte   13, 10, "SMB NEEDS THE PICO9918 CARD AND A CPU REV2 ROM", 13, 10, 0
title_txt:
        .byte   8, 1
        .word   t_t0
        .byte   0, 3
        .word   t_t1
        .byte   0, 4
        .word   t_t2
        .byte   0, 5
        .word   t_t3
        .byte   0, 7
        .word   t_t4
        .byte   0, 8
        .word   t_t5
        .byte   0, 9
        .word   t_t6
        .byte   0, 10
        .word   t_t7
        .byte   0, 11
        .word   t_t8
        .byte   8, 13
        .word   t_hi
        .byte   6, 16
        .word   t_t9
        .byte   $FF
t_t0:   .byte   " SUPER MOS BROS. ", 0
t_t1:   .byte   "STOMP THE GATES, GRAB THE FLOWER", 0
t_t2:   .byte   " PRESS RESET ON KIL, THE DRAGON ", 0
t_t3:   .byte   "8 BITS: A BYTE.  $0C BYTES: 1UP ", 0
t_t4:   .byte   "PAD: <> WALK  B RUN/FIRE  A JUMP", 0
t_t5:   .byte   "     DOWN DUCK/PIPE  START PAUSE", 0
t_t6:   .byte   "KEYS: A/D WALK (AGAIN: RUN)     ", 0
t_t7:   .byte   "  S STOP+DUCK  W/SPACE JUMP     ", 0
t_t8:   .byte   "  F FIRE P PAUSE M SOUND Q QUIT ", 0
t_hi:   .byte   "HIGH DATA ", 0
t_t9:   .byte   "SPACE OR START: PLAY", 0
ctrl_kb_txt:
        .byte   "CONTROLS: KEYBOARD  (G: PAD)  ", 0
ctrl_pad_txt:
        .byte   "CONTROLS: GAMEPAD   (G: KEYS) ", 0
status_txt:
        .byte   0, 0
        .word   s_data
        .byte   12, 0
        .word   s_cell
        .byte   21, 0
        .word   s_cyc
        .byte   0, 1
        .word   s_bytes
        .byte   24, 1
        .word   s_lives
        .byte   $FF
s_data: .byte   "DATA", 0
s_cell: .byte   "CELL", 0
s_cyc:  .byte   "CYCLES", 0
s_bytes:.byte   "BYTES", 0
s_lives:.byte   "LIVES", 0
world_txt:
        .byte   "CELL ", 0
lives_txt:
        .byte   "MOS x ", 0
paused_txt:
        .byte   " PAUSED ", 0
over_txt:
        .byte   9, 9
        .word   o_1
        .byte   9, 11
        .word   o_2
        .byte   9, 12
        .word   o_3
        .byte   $FF
o_1:    .byte   "  GAME  OVER", 0
o_2:    .byte   "SPACE/A: AGAIN", 0
o_3:    .byte   "Q: TITLE", 0
castle_txt:
        .byte   8, 6
        .word   c_1
        .byte   1, 9
        .word   c_2
        .byte   3, 12
        .word   c_3
        .byte   6, 15
        .word   c_4
        .byte   $FF
c_1:    .byte   "THANK YOU, MOS!", 0
c_2:    .byte   "BUT THE PRINCESS IS IN ANOTHER", 0
c_3:    .byte   "ROM ... (KIL HAS BEEN RESET", 0
c_4:    .byte   "TO $FFFC)  ON TO THE", 0
nodisk_txt:
        .byte   1, 8
        .word   n_1
        .byte   1, 10
        .word   n_2
        .byte   1, 13
        .word   n_3
        .byte   $FF
n_1:    .byte   "MOS HAS RUN EVERY CELL THERE IS:", 0
n_2:    .byte   "NO WORLD .SMB ON THE DISK.", 0
n_3:    .byte   "JMP $0800 ... AROUND AGAIN!", 0
noworld_txt:
        .byte   1, 8
        .word   w_1
        .byte   1, 9
        .word   w_2
        .byte   1, 12
        .word   w_3
        .byte   1, 13
        .word   w_4
        .byte   $FF
w_1:    .byte   "NO WORLD1.SMB ON THE DISK (OR", 0
w_2:    .byte   "NO SBC_LOAD IN THE ROM).", 0
w_3:    .byte   "COPY THE WORLD FILES (WORLD1.SMB", 0
w_4:    .byte   "...) TO THE USB DRIVE.", 0
kil_txt:
        .byte   1, 16
        .word   k_1
        .byte   1, 17
        .word   k_2
        .byte   $FF
k_1:    .byte   "KIL THE DRAGON HALTS THE CPU.", 0
k_2:    .byte   "PRESS RESET (5 ELECTRONS HELP)", 0
end_txt:                        ; (over the castle, with her in view)
        .byte   1, 4
        .word   e_1
        .byte   1, 5
        .word   e_2
        .byte   1, 7
        .word   e_3
        .byte   1, 8
        .word   e_4
        .byte   10, 10
        .word   e_5
        .byte   $FF
e_1:    .byte   "HI MOS! I'M PRINCESS GRAPHICS", 0
e_2:    .byte   "CARD. THANK YOU FOR RESCUING ME!", 0
e_3:    .byte   "HOPEFULLY WE CAN MAKE BETTER", 0
e_4:    .byte   "GRAPHICS IN THE FUTURE.", 0
e_5:    .byte   "- THE END -", 0

        .segment "BUFS"
map:        .res MAPROWS * 256  ; the level: a page a row, tile number * 4
wc:         .res LOADMAX        ; a world file, as loaded

        .segment "BSS"
bss_start:
; ---- the PICO9918 drawing
wf_n:       .res 1
pt_i:       .res 1
pt_c:       .res 1
pt_x:       .res 1
pt_cc:      .res 1
pt_pg:      .res 1
pt_r:       .res 1
cam_t:      .res 1              ; the view's first tile column
drawn_hi:   .res 1              ; tile columns drawn into the ring: up to this - 1
nspr:       .res 1              ; hardware sprites this frame
ms_i:       .res 1
ao_x:       .res 2
ao_y:       .res 1
ao_n:       .res 1
ao_i:       .res 1
ao_p:       .res 1
ao_c:       .res 1
ao_sx:      .res 2
spr_tab:    .res 32 * 4 + 1     ; the sprite attributes for VRAM
sl_want:    .res 32             ; each sprite's part this frame
sl_have:    .res 32             ; ... and in its pattern now
ps_k:       .res 1
snd_a:      .res 1
snd_x:      .res 1
snd_y:      .res 1
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
duck:       .res 1              ; MOS is ducking
in_down:    .res 1
kduck:      .res 1
bss_end:

