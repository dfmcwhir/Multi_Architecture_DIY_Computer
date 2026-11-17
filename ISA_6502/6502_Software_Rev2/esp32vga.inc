; ============================================================================
; esp32vga.inc - ESP32_VGA card: registers, commands, constants and macros
;
; Shared by the ROM driver (drv_esp32.s) and your own programs:
;       .include "esp32vga.inc"
; Taken from the card firmware v1.0 (bus.h, video.h, video.cpp, input.h,
; audio.h).  Programs drive the card directly with the macros below: every
; access is held with RDY wait states, so there is no "ready" polling and no
; write is ever lost.
;
; Rules
;   * No read-modify-write instructions (INC, DEC, ASL, LSR, ROL, ROR, TSB,
;     TRB) on these registers: their second access isn't stalled.
;   * Reading STATUS clears its VBL bit.  The ROM never reads STATUS, so the
;     VBL bit belongs to your program.
;   * The ROM's interrupt handler only ever READS VGA_KEY, so your program can
;     send display and I/O commands at any time without disabling interrupts.
;   * A display command must be given all its arguments before you print
;     again: until then, printed characters are taken as arguments.
;   * At 4 MHz or below.  Faster needs the card's write latch.
; ============================================================================

; ---- registers ($7F18-$7F1B) ----------------------------------------------
VGA_STATUS      = $7F18         ; read:  status (below)
VGA_CMD         = $7F18         ; write: display command opcode
VGA_RESP        = $7F19         ; read:  display query results
VGA_DATA        = $7F19         ; write: display command arguments, or text to print
VGA_KEY         = $7F1A         ; read:  next key, 0 = none
VGA_IOCMD       = $7F1A         ; write: keyboard / mouse / sound / system opcode
VGA_IORESP      = $7F1B         ; read:  I/O query results (ready on the next read)
VGA_IODATA      = $7F1B         ; write: I/O command arguments

; ---- STATUS bits ------------------------------------------------------------
ST_KEY          = $80           ; a key is waiting
ST_MOUSE        = $40           ; mouse moved or buttons changed
ST_VRESP        = $20           ; display response byte waiting
ST_IORESP       = $10           ; I/O response byte waiting
ST_VBL          = $08           ; vblank started since the last STATUS read (read clears)
ST_VBUSY        = $04           ; display commands still executing
ST_VFULL        = $02           ; display queue over 3/4 full
ST_READY        = $01           ; firmware running

; ---- display commands: VGA_CMD, then the arguments to VGA_DATA ---------------
;      (x16 = 16-bit low byte first; text grid 80x30; bitmap/sprites 320x240)
V_NOP           = $00
V_RESET         = $01           ; everything back to the power-up state
V_CLS           = $02           ; clear the text layer (current colours)
V_COLOR         = $03           ; fg, bg                 (bg bit 6 = transparent)
V_LOCATE        = $04           ; col, row
V_CURSOR        = $05           ; 0 off, 1 underline, 2 block
V_SCROLLRGN     = $06           ; top, bottom            text rows that scroll
V_PUTRAW        = $07           ; n, n glyphs            (no control codes)
V_TSCROLL       = $08           ; 0 up, 1 down           (in the scroll region)
V_FILLTEXT      = $09           ; col, row, w, h, char   (current colours)
V_DEFGLYPH      = $0A           ; char, 16 bytes         (8x16, top row first)
V_SETATTR       = $0B           ; col, row, w, h         (current colours)
V_GETCHAR       = $0D           ; col, row -> char, fg, bg
V_DEFFONT       = $0E           ; back to the built-in font
V_LAYERS        = $10           ; mask: LAYER_TEXT | LAYER_BITMAP | LAYER_SPRITES
V_BACKDROP      = $11           ; colour behind everything
V_WAITVBL       = $12           ; display queue waits for the next vblank
V_SCROLL        = $13           ; x16, y                 bitmap scroll offset
V_GCLS          = $20           ; colour                 clear the bitmap
V_PLOT          = $21           ; x16, y, colour
V_LINE          = $22           ; x16, y, x2_16, y2, colour
V_RECT          = $23           ; x16, y, w16, h, colour
V_FILLRECT      = $24           ; x16, y, w16, h, colour
V_CIRCLE        = $25           ; x16, y, r, colour
V_FILLCIRC      = $26           ; x16, y, r, colour
V_BLIT          = $27           ; x16, y, w16, h, then w*h pixels ($40 bit = skip)
V_COPYRECT      = $28           ; sx16, sy, w16, h, dx16, dy
V_GETPIXEL      = $29           ; x16, y -> colour
V_GTEXT         = $2B           ; x16, y, fg, bg, n, n chars  (text into the bitmap)
V_SPRDEF        = $30           ; pattern (0-31), then 256 pixels (16x16, $40 bit = clear)
V_SPRSET        = $31           ; sprite (0-15), pattern, x16, y16, flags
V_SPRMOVE       = $32           ; sprite, x16, y16       (signed: can go off screen)
V_SPRHIDE       = $33           ; sprite, or $FF = all
V_SPRHITS       = $34           ; sprite -> mask lo, mask hi (overlapping sprites)
V_SPRPAT        = $35           ; sprite, pattern
V_INFO          = $40           ; -> 'V', major, minor, cols, rows, w lo, w hi, h
V_GETCURSOR     = $41           ; -> col, row
V_SYNC          = $42           ; -> $AA once every earlier command has run
V_MOUSEPTR      = $50           ; 0/1 built-in mouse pointer off/on

LAYER_TEXT      = $01
LAYER_BITMAP    = $02
LAYER_SPRITES   = $04

SPR_VISIBLE     = $01           ; V_SPRSET flags
SPR_HFLIP       = $02
SPR_VFLIP       = $04

; ---- I/O commands: VGA_IOCMD, then the arguments to VGA_IODATA ----------------
;      (results are in VGA_IORESP on the very next read)
IO_KBDFLUSH     = $01
IO_KEYDOWN      = $02           ; code -> 1 if held now (unshifted code / KEY_ below)
IO_KBDMODS      = $03           ; -> b0 shift, b1 ctrl, b2 alt, b3 caps
IO_MOUSE        = $10           ; -> buttons, x16, y16   (pointer position)
IO_MDELTA       = $11           ; -> buttons, dx, dy     (since the last read)
IO_MBOUNDS      = $12           ; xmax16, ymax16
IO_MSETPOS      = $13           ; x16, y16
IO_SNDFREQ      = $20           ; voice, hz16
IO_SNDWAVE      = $21           ; voice, wave, duty
IO_SNDVOL       = $22           ; voice, volume
IO_SNDENV       = $23           ; voice, attack, decay, sustain, release (0-15 each)
IO_SNDGATE      = $24           ; voice, 0/1
IO_SNDNOTE      = $25           ; voice, midi note, frames (1/60 s, 0 = hold)
IO_SNDMAST      = $26           ; master volume
IO_SNDBEEP      = $27           ; hz16, frames
IO_SNDSTOP      = $28
IO_SNDSTAT      = $29           ; -> mask of voices playing
IO_IRQEN        = $F0           ; mask of ST_KEY | ST_MOUSE | ST_VBL that hold /IRQ low
IO_PING         = $F1           ; -> $A5, $5A
IO_VERSION      = $F2           ; -> major, minor
IO_FRAME        = $F3           ; -> frame counter lo, hi
IO_RESET        = $FF           ; keys flushed, IRQs off, sound off

WAVE_SQUARE     = 0
WAVE_TRIANGLE   = 1
WAVE_SAW        = 2
WAVE_SINE       = 3
WAVE_NOISE      = 4

; ---- the card's own key codes (VGA_KEY / IO_KEYDOWN) ---------------------------
; Printable keys are ASCII; Enter $0D, Backspace $08, Tab $09, Esc $1B, Del $7F.
; NOTE: the ROM's console converts these to the same codes the AVR keyboard
; gives (sbc_api.inc).  These are for IO_KEYDOWN, and for programs that read
; VGA_KEY themselves.
KEY_V_UP        = $80
KEY_V_DOWN      = $81
KEY_V_LEFT      = $82
KEY_V_RIGHT     = $83
KEY_V_HOME      = $84
KEY_V_END       = $85
KEY_V_PGUP      = $86
KEY_V_PGDN      = $87
KEY_V_INS       = $88
KEY_V_F1        = $90           ; F1-F12 = $90-$9B
KEY_V_LSHIFT    = $A0           ; IO_KEYDOWN only
KEY_V_RSHIFT    = $A1
KEY_V_LCTRL     = $A2
KEY_V_RCTRL     = $A3
KEY_V_LALT      = $A4
KEY_V_RALT      = $A5

; ---- colours: %00RRGGBB ------------------------------------------------------
C_BLACK         = $00
C_BLUE          = $03
C_GREEN         = $0C
C_CYAN          = $0F
C_RED           = $30
C_MAGENTA       = $33
C_YELLOW        = $3C
C_WHITE         = $3F
C_GREY          = $15
C_LTGREY        = $2A
C_TRANSPARENT   = $40

; ---- macros ---------------------------------------------------------------------
.macro VCMD op                  ; display command
        lda     #op
        sta     VGA_CMD
.endmacro
.macro VARG val                 ; one argument byte (constant)
        lda     #val
        sta     VGA_DATA
.endmacro
.macro VARG16 val               ; 16-bit argument (constant), low byte first
        lda     #<(val)
        sta     VGA_DATA
        lda     #>(val)
        sta     VGA_DATA
.endmacro
.macro IOCMD op                 ; I/O command
        lda     #op
        sta     VGA_IOCMD
.endmacro
.macro IOARG val                ; one I/O argument byte (constant)
        lda     #val
        sta     VGA_IODATA
.endmacro
