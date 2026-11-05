; vga.inc - ESP32-S3 VGA / keyboard / mouse / sound adapter definitions (ca65)
;
; The adapter uses 4 registers (A1:A0). Every access is held with RDY wait
; states until the ESP32 has handled it, so there is no need to poll a busy
; bit before writing: just STA. W65C02S only (RDY must be able to stall writes).
;
; Do NOT use read-modify-write instructions (INC, DEC, ASL, LSR, ROL, ROR,
; TSB, TRB) on adapter registers.

.ifndef VGA_BASE
VGA_BASE    = $7F18         ; adapter registers $7F18-$7F1B (decoded by gal/VGAGLUE.PLD)
.endif

; ------------------------------------------------------------------ registers
VGA_STATUS  = VGA_BASE+0    ; R  status bits (reading clears ST_VBL)
VGA_CMD     = VGA_BASE+0    ; W  display command opcode
VGA_RESP    = VGA_BASE+1    ; R  display response bytes (queries)
VGA_DATA    = VGA_BASE+1    ; W  command arguments, or text to print
VGA_KEY     = VGA_BASE+2    ; R  next key from the keyboard queue, 0 = none
IO_CMD      = VGA_BASE+2    ; W  I/O command opcode (keyboard/mouse/sound/system)
IO_RESP     = VGA_BASE+3    ; R  I/O response bytes
IO_DATA     = VGA_BASE+3    ; W  I/O command arguments

; ------------------------------------------------------------------ STATUS bits
ST_KEY      = $80           ; key waiting
ST_MOUSE    = $40           ; mouse moved / buttons changed
ST_VRESP    = $20           ; display response byte waiting
ST_IORESP   = $10           ; I/O response byte waiting
ST_VBL      = $08           ; vertical blank since last STATUS read
ST_VBUSY    = $04           ; display commands still executing
ST_VFULL    = $02           ; display FIFO over 3/4 full
ST_READY    = $01           ; firmware running

; ------------------------------------------------------------------ colours
; 64 colours, byte = %00RRGGBB, each channel 0-3
.define RGB(r,g,b) (((r) << 4) | ((g) << 2) | (b))
BLACK       = RGB(0,0,0)
WHITE       = RGB(3,3,3)
GREY        = RGB(2,2,2)
RED         = RGB(3,0,0)
GREEN       = RGB(0,3,0)
BLUE        = RGB(0,0,3)
YELLOW      = RGB(3,3,0)
CYAN        = RGB(0,3,3)
MAGENTA     = RGB(3,0,3)
TRANSPARENT = $40           ; text background / sprite / BLIT pixel: see-through

; ------------------------------------------------------------------ display commands
; Write the opcode to VGA_CMD, then the arguments to VGA_DATA.
; 16-bit values are sent low byte first. Bytes written to VGA_DATA when no
; command is collecting arguments are printed as text (CR, LF, BS, TAB,
; FF = clear screen, BEL = beep; other control codes are ignored).
V_NOP       = $00           ;
V_RESET     = $01           ;                     everything back to power-on state
V_CLS       = $02           ;                     clear text layer, cursor home
V_COLOR     = $03           ; fg, bg              text colours (bg $40 = transparent)
V_LOCATE    = $04           ; col, row            0-79, 0-29
V_CURSOR    = $05           ; mode                0 off, 1 underline, 2 block
V_SCROLLRGN = $06           ; top, bottom         text scroll region rows
V_PUTRAW    = $07           ; n, n glyphs         print glyphs 0-255 without control codes
V_TSCROLL   = $08           ; dir                 0 up, 1 down (scroll region)
V_FILLTEXT  = $09           ; col,row,w,h,char    fill cells with char + current colours
V_DEFGLYPH  = $0A           ; char, 16 bytes      redefine a font glyph (tiles!)
V_SETATTR   = $0B           ; col,row,w,h         recolour cells with current colours
V_GETCHAR   = $0D           ; col,row  -> char,fg,bg
V_DEFFONT   = $0E           ;                     restore default font
V_LAYERS    = $10           ; mask                1 text, 2 bitmap, 4 sprites
V_BACKDROP  = $11           ; colour              shown when bitmap layer is off
V_WAITVBL   = $12           ;                     command queue pauses until next vblank
V_SCROLL    = $13           ; x16, y              bitmap viewport offset (wraps)
V_GCLS      = $20           ; colour              clear 320x240 bitmap
V_PLOT      = $21           ; x16, y, colour
V_LINE      = $22           ; x0_16,y0,x1_16,y1,colour
V_RECT      = $23           ; x16,y,w16,h,colour
V_FILLRECT  = $24           ; x16,y,w16,h,colour
V_CIRCLE    = $25           ; x16,y,r,colour
V_FILLCIRC  = $26           ; x16,y,r,colour
V_BLIT      = $27           ; x16,y,w16,h, w*h pixels   ($40 pixels are skipped)
V_COPYRECT  = $28           ; sx16,sy,w16,h,dx16,dy
V_GETPIXEL  = $29           ; x16,y    -> colour
V_GTEXT     = $2B           ; x16,y,fg,bg,n, n chars    8x16 text into the bitmap
V_SPRDEF    = $30           ; pattern, 256 pixels       0-31, $40 = transparent
V_SPRSET    = $31           ; id,pattern,x16,y16,flags  flags: 1 show, 2 hflip, 4 vflip
V_SPRMOVE   = $32           ; id,x16,y16                (x,y signed, 320x240 space)
V_SPRHIDE   = $33           ; id                        $FF = all
V_SPRHITS   = $34           ; id      -> mask lo, mask hi (overlapping sprites)
V_SPRPAT    = $35           ; id,pattern                change animation frame
V_INFO      = $40           ;         -> 'V',major,minor,cols,rows,wlo,whi,h
V_GETCURSOR = $41           ;         -> col,row
V_SYNC      = $42           ;         -> $AA when all earlier commands are done
V_MOUSEPTR  = $50           ; on/off                    built-in mouse pointer

; ------------------------------------------------------------------ I/O commands
; Write the opcode to IO_CMD, then the arguments to IO_DATA. I/O commands run
; immediately: results are in IO_RESP on the very next read.
IO_KBDFLUSH = $01           ;
IO_KEYDOWN  = $02           ; keycode  -> 1 if held (e.g. 'a', KEY_LEFT)
IO_KBDMODS  = $03           ;          -> %0000CASs caps, alt, ctrl, shift
IO_MOUSE    = $10           ;          -> buttons, x lo, x hi, y lo, y hi
IO_MDELTA   = $11           ;          -> buttons, dx, dy (signed, since last)
IO_MBOUNDS  = $12           ; xmax16, ymax16
IO_MSETPOS  = $13           ; x16, y16
IO_SNDFREQ  = $20           ; voice, hz16
IO_SNDWAVE  = $21           ; voice, wave, duty    wave: 0 sq,1 tri,2 saw,3 sine,4 noise
IO_SNDVOL   = $22           ; voice, volume        0-255
IO_SNDENV   = $23           ; voice, a, d, s, r    each 0-15 (SID-like times)
IO_SNDGATE  = $24           ; voice, on/off
IO_SNDNOTE  = $25           ; voice, midi, frames  play note (frames 1/60 s, 0 = hold)
IO_SNDMAST  = $26           ; volume
IO_SNDBEEP  = $27           ; hz16, frames
IO_SNDSTOP  = $28           ;
IO_SNDSTAT  = $29           ;          -> mask of voices sounding
IO_IRQEN    = $F0           ; mask                 ST_KEY|ST_MOUSE|ST_VBL drive /IRQ
IO_PING     = $F1           ;          -> $A5, $5A
IO_VERSION  = $F2           ;          -> major, minor
IO_FRAME    = $F3           ;          -> frame counter lo, hi
IO_RESET    = $FF           ;                      flush keys, stop sound, IRQs off

; ------------------------------------------------------------------ key codes
; VGA_KEY returns ASCII for printable keys (shift/caps/ctrl applied),
; $0D Enter, $08 Backspace, $09 Tab, $1B Esc, $7F Delete, and:
KEY_UP      = $80
KEY_DOWN    = $81
KEY_LEFT    = $82
KEY_RIGHT   = $83
KEY_HOME    = $84
KEY_END     = $85
KEY_PGUP    = $86
KEY_PGDN    = $87
KEY_INS     = $88
KEY_F1      = $90           ; F1..F12 = $90..$9B
; IO_KEYDOWN also accepts modifier codes:
KEY_LSHIFT  = $A0
KEY_RSHIFT  = $A1
KEY_LCTRL   = $A2
KEY_RCTRL   = $A3
KEY_LALT    = $A4
KEY_RALT    = $A5

; ------------------------------------------------------------------ macros
.macro VCMD op              ; display command
        lda #op
        sta VGA_CMD
.endmacro
.macro VARG val             ; 8-bit display argument
        lda #val
        sta VGA_DATA
.endmacro
.macro VARG16 val           ; 16-bit display argument
        lda #<(val)
        sta VGA_DATA
        lda #>(val)
        sta VGA_DATA
.endmacro
.macro IOCMD op
        lda #op
        sta IO_CMD
.endmacro
.macro IOARG val
        lda #val
        sta IO_DATA
.endmacro
