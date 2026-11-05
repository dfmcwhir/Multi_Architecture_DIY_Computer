VT100 TERMINAL - EXTENDED VERSION 1.4
=====================================
Based on Geoff Graham's PIC32MX250F128B VT100 terminal (v1.3).
Original copyright and licence are retained unchanged in every source file.
This product includes software developed by Geoff Graham (projects@geoffg.net).

TESTING STATUS - PLEASE READ
----------------------------
* NOT built with XC32 and NOT run on real hardware (no toolchain/hardware here).
* Video.c and vt100.c were compiled with gcc (-std=gnu89, -Wall -Wextra) against a
  stubbed plib and driven by a test harness that reads the pixel buffer back
  (host_test/): 456 checks pass in VGA mode (including 150 random runs, see below), 403 in PAL composite mode.
* Rendered demo images were inspected for the fonts, box drawing, DEC graphics,
  attributes, scroll regions and insert-character.
* NOT verified: keyboard code, flash fit.
* THE SET-UP MENU HAS BEEN REMOVED (to make the program fit in flash).  The settings are fixed at the
  defaults (every item of the settings page erased): VGA 24 lines (PAL for composite), US keyboard,
  8 bits no parity, one stop bit, normal serial polarity, 115200 baud when no baud jumpers are
  fitted (the jumpers still select 2400 to 115200), start up message shown, CP437 extended characters,
  control codes 01-1F ON.  F12 with Shift now does nothing.  The settings page in flash (Option[]) is
  still reserved but nothing writes to it any more.
* RAM: the PIC32MX250 has very little RAM and the linker needs 1024 bytes for the stack
  (the original build had almost none to spare, and XC32 v1.40 may use a little more than
  v1.33).  This version frees RAM by: SERIAL_TX_BUF_SIZE 128 instead of 256 (Main.c); the
  escape sequence buffer VTBUF_SIZE 20 instead of 40; bit packed tab stops; not using
  sprintf() in the normal build (IntToStr() in vt100.c instead, which keeps the C library's
  printf out of the program); and the shared video/receive buffer (below).
  There is one block of RAM (VideoBuf) shared by the video buffer and the serial receive
  buffer, whichever video mode is in use (VGA and composite share it, composite does not
  have a buffer of its own).  The receive buffer is what is left after the video buffer:
      video buffer:  VGA 36 lines 27648,  VGA 24 lines 18432,  PAL 12096,  NTSC 9360 bytes
  The block has to be big enough for the biggest mode that is built in, and that was
  the 36 line VGA mode, which is why the receive buffer there is so small.  In Terminal.h:
      ALLOW_36_LINES  0 (default) = VGA is always 24 lines , which
                      frees 9216 bytes of RAM.   1 = the original 24 or 36 line choice.
      RX_BUF_BYTES    the receive buffer size in the biggest mode that is built in (default 6144).
  Receive buffer sizes (bytes):
      ALLOW_36_LINES 0, RX_BUF_BYTES 6144:  VGA 24 lines 6144,  PAL 12480,  NTSC 15216
      ALLOW_36_LINES 1, RX_BUF_BYTES 1536:  VGA 36 lines 1536,  VGA 24 lines 10752, PAL 17248
  With ALLOW_36_LINES 1 you must keep RX_BUF_BYTES small or the program will not fit in RAM.
  After a successful build the linker's memory summary (dist/.../memoryfile.xml) shows how
  much data memory is free; the stack needs 1024 of it, so you can spend the rest on the
  receive buffer (RX_BUF_BYTES) or on more tile slots (TILE_POOL_BYTES in vt100.c).
* Flash: the program space with the bootloader is about 99KB.  The extra fonts (CP437, DEC
  graphics and PC symbols for both fonts) are stored packed in FontsExt.h (12 bits per pixel
  column for the small font, 20 for the large one, about 8.5KB in all) and unpacked when a
  glyph is drawn.  The sprite layer is about 7.5KB of code; if the link fails with "could not
  allocate program memory" set SPRITE_LAYER to 0 in Terminal.h (that also frees 4KB of RAM).

WHAT CHANGED
------------
1. Extended characters (codes 0x80-0xFF) in both fonts (6x12 and 13x20/26x40):
   - CP437 (default): accented letters, Greek, maths symbols, box drawing,
     shade and block characters.
   - Off: characters with the top bit set are ignored (original behaviour).
   (An ISO 8859-1 font was in an earlier version and has been removed to save flash.)
   (Extended characters are fixed at CP437 now that the set-up menu is gone.)
2. Graphics character set: DEC Special Graphics, selected by ESC ( 0 / ESC ) 0 and
   SO (0x0E) / SI (0x0F); ESC ( B / ESC ) B returns to ASCII; ESC ( A selects UK
   (# shows as pound sign).
3. Much larger VT100/ANSI escape sequence set (see below).
4. Bug fixes (see below).

CONTROL CODE MODE (always ON)
---------------------------------------------------
The mode is always on now.  (To turn it off, in VT100Putc() in vt100.c change  Option[O_CTRLCODES] == O_CC_ON  to  0.)
Note that with the mode on, 0E and 0F are the column and row codes, not SO and SI.
Quick check: send 0E 05 0F 02 58.  If an X appears at column 6, row 3 the mode is on.
When on, the control codes 0x01-0x1F and 0x7F directly control the display (similar to
Grant Searle's design).  ANSI/VT100 escape sequences (ESC) still work.  Codes marked n,
x, y are followed by one or two raw bytes, which may have any value (even control codes).
  01 cursor home                          10 erase start of line to the cursor
  02 n define cursor character (0 = off)  11 erase cursor to end of line
  03 cursor blinks                        12 erase start of screen to the cursor
  04 cursor solid                         13 erase cursor to end of screen
  05 x y set a graphics pixel             14 scroll up one line
  06 x y reset a graphics pixel           15 scroll down one line
  08 backspace   09 tab                   16 scroll left (see below)
  0A line feed   0D carriage return       17 scroll right (see below)
  0B n send tile n (see below)            18 n set the character attribute
  0C clear screen and home                19 n c r data  set tile n
  0E n set column (0 = left)              1A n draw the next byte as a character
  0F n set row (0 = top)                  1B ESC (ANSI sequences)
  1C sprite layer command prefix (see below; cursor right is now ESC [ C)
  1D cursor left  1E up  1F down   7F delete character at the cursor
All other codes are as in ANSI mode.  SO/SI (0E/0F) are therefore not available for the
DEC graphics character set in this mode (ESC ( 0 still works).

Notes - these are my own interpretation where the description left details open:
* Pixels: x and y are in units of 3x3 screen pixels (a character in the small font is
  2 units wide and 4 high), so x is 0-159 and y is 0-95 (24 lines) or 0-143 (36 lines).
  This fits in a byte, unlike pixel coordinates up to 480.  Drawing a pixel does not
  clear text underneath; clear the screen (0C) first if needed (there is no text buffer).
  The cursor is drawn by inverting pixels so move it away or turn it off (02 00).
* Attribute byte (18):  bit 0 = 40 character lines (0 = small font, 80 columns; 1 = large
  font, 36 columns), bit 1 = bold, bit 2 = double height, bits 3-6 = repeat count,
  bit 7 = block graphics.  So 18 00 is normal text, 18 80 is block graphics in the small
  font, and 18 81 is block graphics in the large font (cells 13 x 20).
  Bit 2 cannot be a real double height (the terminal
  scales characters equally in both directions) so it selects the double size font
  (18 columns); it overrides bit 0.  Underline and reverse are not in this byte: use
  ESC [ 4 m and ESC [ 7 m.  The attribute applies to everything sent afterwards (not just
  the current line, there is no text buffer).  When the font changes the cursor is moved
  to the nearest character cell of the new font.
* Repeat (bits 3-6 of 18): every printable character, block graphic or 1A literal is drawn
  that many times (0 or 1 = once, up to 15).  Control codes are not repeated, and text
  wraps onto the next line as normal.  Example: 18 18 followed by 'a' draws aaa (bits 3-6
  = 3 is 0x18).  18 00 turns it off.
* Sideways scrolling (16 and 17): scrolls the lines of the scrolling region (the whole
  screen unless one was set with ESC [ top ; bottom r, so a game can leave its score lines
  alone).  With a repeat count of 0 (18 00, the default) it moves one character cell;
  with a repeat count of 1 to 15 (18 08 .. 18 78) it moves that many PIXELS, so
  18 08 17 is a one pixel step and 18 18 16 a three pixel step.  The scroll works on whole
  32 bit words, only on the words that hold visible pixels, with no per-word range checks,
  so it should be several times faster than before (not timed on hardware).
  Remember that the repeat count also repeats characters and tiles: put it back to 0 with
  18 00 before printing.  Composite video still uses the old slow method.
* Tiles: a tile is a block of c columns by r rows of characters, stored in a pool of
  TILE_POOL_BYTES (512) bytes of RAM.
    19 n c r b0 b1 ... b(c*r-1)    SET TILE n, c columns, r rows, then exactly c*r bytes
                                   (row by row), e.g. 19 01 02 04 31 32 33 34 35 36 37 38
    0B n                           SEND TILE n, which then draws   12
                                                                  34
                                                                  56
                                                                  78
  Slot n starts at byte n*c*r of the pool, so the highest slot for a given tile size is
  TILE_POOL_BYTES / (c*r) - 1 (2x4 tiles: slots 0-63; 1x1 tiles: slots 0-127, which is
  the limit TILE_MAX_SLOTS).  The size of every slot is remembered, so each slot can
  have a different shape.  Slots of different sizes share the pool, so a big tile can
  overlap the bytes of other slots: use one size, or plan the slot numbers (for example 8x2
  tiles in slots 0-31 and 2x4 tiles in slots 2, 3, ... would overlap).
  A SET TILE with a bad slot (too high for its size, or 128 and up), zero columns or zero
  rows is ignored.  Its data bytes are still swallowed (c*r of them) so a bad tile
  cannot garble the screen, but a wild c or r therefore swallows up to c*r bytes.
  The data must be exactly c*r bytes; there is no end marker.
  Repeat applies to tiles: 18 18 0B 01 draws tile 1 three times side by side.  The
  cursor ends on the top line of the tile just to the right of the last copy.
  The bytes can be any value (including 00-1F) as they are drawn as literals, so a tile
  is normally used with block graphics on (18 80).  If the tile would run off the bottom
  of the screen the screen scrolls up to make room (the usual case when the cursor is on
  the bottom line).  Parts of a tile or repeat that run off the right edge are not drawn.
  Tiles survive a terminal reset; power off clears them.  The tile codes use 19 and 0B,
  which were free.  Only 00 and 07 are now unused.  Tile RAM is TILE_POOL_BYTES plus
  2 * TILE_MAX_SLOTS (256) bytes for the sizes, both set at the top of the control code
  section of vt100.c (or with -D options).
* Sprite layer (1C): see "SPRITE LAYER" below.
* 1A n draws n as a character even if it is a control code.  Codes 01-1F show the PC
  (DOS) symbols (smiley, card suits, arrows ...).
* 02 n: the cursor is the glyph of character n (any code, including CP437 characters
  such as 0xDB, a full block) with its pixels inverted.  Without 02 it is the original
  blinking underline.
* 7F deletes the character at the cursor and pulls the rest of the line left.

SUPPORTED SEQUENCES (VT100 mode)
--------------------------------
Cursor:      ESC[nA B C D  CUU CUD CUF CUB      ESC[nE CNL   ESC[nF CPL
             ESC[nG CHA    ESC[n` HPA  ESC[nd VPA  ESC[na HPR  ESC[ne VPR
             ESC[r;cH / f  CUP/HVP  (honours origin mode)
             ESC D IND   ESC E NEL   ESC M RI   ESC 7/8 save/restore
             ESC[s / ESC[u  save/restore cursor
Erase:       ESC[nJ  ESC[nK  ESC[nX ECH
Insert/del:  ESC[nL IL   ESC[nM DL   ESC[n@ ICH   ESC[nP DCH
Scroll:      ESC[nS SU   ESC[nT SD   ESC[t;br DECSTBM (scroll region)
Tabs:        ESC H HTS   ESC[g / ESC[3g TBC   ESC[nI CHT   ESC[nZ CBT
Attributes:  ESC[...m  multiple parameters: 0 reset, 1 bold, 4 underline,
             5 blink (shown as bold), 7 reverse, 22/24/25/27 off. Colours are
             accepted and ignored (monochrome display).
Modes (h/l): 4 IRM insert, 20 LNM newline; private ?1 DECCKM application cursor
             keys, ?6 DECOM origin, ?7 DECAWM wrap, ?25 cursor visible
Reports:     ESC[5n status, ESC[6n cursor position (CPR), ESC[c / ESC Z DA
Reset:       ESC c RIS, ESC[!p DECSTR, ESC # 8 DECALN (fill with E)
VT52 mode keeps its own sequences, including ESC Y and ESC Z.
The legacy single-escape commands of the original terminal are retained.
Unknown sequences are now consumed silently instead of being printed.

DEC SPECIAL GRAPHICS MAPPING (characters 0x5F-0x7E)
---------------------------------------------------
_ blank   ` diamond   a checker   b-f HT FF CR LF degree (HT FF CR LF NL VT
symbols are shown blank)   g plus/minus   h NL   i VT   j k l m corners
n cross   o p q r s scan lines (q = horizontal line)   t u v w tees
x vertical line   y <=   z >=   { pi   | not-equal   } pound   ~ bullet

BEHAVIOUR CHANGES / FIXES
-------------------------
* getSerial sign handling fixed (characters >= 0x80 were mishandled).
* ESC[6n now returns a correct cursor position report.
* Tab stops are real, settable stops (default every 8).
* NEL now does CR+LF. Scrolling works correctly with wrap off.
* Font 2 cursor alignment corrected.
* Enter sends CR (or CR LF when LNM is set).
* Application cursor keys send ESC O A..D when DECCKM is set.

SPRITE LAYER (control code 1C)
------------------------------
Implements "PIC32 Terminal Sprite Layer: Command Spec" (revision 11).  16 sprites (slots
0-15, higher slots on top) are drawn over whatever the existing codes draw, with 64 pictures
of 1-32 x 1-32 pixels (with an optional mask) kept in a RAM pool.  A sprite pixel is 3 x 3
screen pixels (the units of control code 05); the screen is 160 x 96 sprite pixels, with
2 x 4 sprite pixels in each 80 x 24 character cell.  Coordinates on the wire have 32 added.

  1C 01 n w h f data   DEFINE picture n   (f bit 0 = a mask follows the bits; data is h rows
                       of (w+7)/8 bytes, bit 7 = leftmost pixel; mask 1 = drawn, bit = lit or dark)
  1C 02 s n x y f      PLACE slot s, picture n, at (x-32, y-32), flags f
  1C 03 s x y          MOVE slot s
  1C 04 s n            PICTURE: slot s shows picture n
  1C 05 s f            FLAGS: bit 0 mirror, bit 1 flip, bit 7 hidden
  1C 06 s              HIDE slot s            1C 07  HIDE ALL
  1C 08                CLEAR: hide everything and forget all pictures (also ends a HOLD)
  1C 09 / 1C 0A        HOLD / SHOW: slot changes are held and then shown together
  1C 0B t b            CLIP: sprites are only drawn in text rows t to b (0-23)
  1C 0C                IDENTIFY: the terminal sends back  S P 1

Existing codes draw into the background and the sprites stay on top: text, block
graphics, tiles, pixels, lines, erase, insert/delete, the scroll codes 14-17 and the VT100
scrolling all work with sprites showing (the sprites stay where they are and the scenery
moves under them).  0C / ESC [ 2 J hide all the sprites and reset the clip rows (the pictures
are kept).  Slot changes are shown at once unless a HOLD is active.  Bad numbers (slot 16+,
picture 64+, bad CLIP rows) are ignored but the right number of argument bytes is still
read.  A DEFINE that does not fit in the pool is read and thrown away (the picture stays
undefined, or keeps its old definition).  Redefining a picture that is showing redraws it.
Redefining a picture smaller or the same size reuses its place in the pool; a bigger one
takes new pool space (the old space is only recovered by CLEAR).

How it works and what to know (differences from the spec are marked *):
  There is no copy of the screen in the terminal, so the background of a cell is only
  saved while a sprite covers it: 1920 bytes (one per cell) + 240 bytes of flags.  Each time a sprite
  moves the cells it left and now covers are drawn again; before another drawing code
  changes a covered cell the background is put back and the sprites are drawn again after it.
  * The saved background of a covered cell is 8 block pixels (sampled at the middle of each
    3 x 3 block).  Block graphics, graphics pixels and tiles are kept exactly, but text or
    any fine detail under a sprite is reduced to blocks and does not come back when the
    sprite leaves.  Use CLIP to keep sprites out of text rows.  (The spec says the text comes back.)
  * Sideways pixel scrolls (the 18 repeat count, 1 to 15 pixels): the saved background can only
    move in steps of 3 pixels (one block), so the 1 or 2 pixels left over are remembered for each
    row of cells (24 bytes) and used when the background is put back, and when the sprite is
    drawn again.  Under a sprite the scenery therefore follows a 1 pixel a frame scroll to within
    1 pixel, and the scenery that leaves from under a sprite is exact.  (Before this, a scroll
    of 1 or 2 pixels left the scenery under a sprite where it was and the old picture came back
    when the sprite moved away.)  Scrolling by whole blocks (3, 6, 9, 12 or 15 pixels or a whole
    character) is exact.  Something other than a scroll that redraws part of a row of cells with
    a left over of 1 or 2 pixels may be off by up to 1 pixel.
  * Sprites only work with VGA video and the first 24 text rows (a 36 line screen gets sprites
    in its top 24 rows).  With composite video the commands are read and ignored.
  * DEFINE with a width or height of 0 or over 32 is ignored and no data bytes are
    assumed to follow (the length cannot be known).
  * Flicker.  Moving or changing sprites (a MOVE outside HOLD, or SHOW, or DEFINE of a picture that
    is showing), a CLIP and a scroll with sprites on the rows being scrolled first wait for the
    vertical blank (SprSync() in SpriteLayer.h, it gives up after about 20 ms so a missing video
    interrupt cannot hang the terminal), then work from the top of the screen down so that the
    work stays ahead of the beam.  A cell is written once, with its final pixels (background
    with the sprites on it), so the bare background is never written for a moment.  Sideways
    scrolls are done one row of cells at a time: put the row's covered cells back, shift the
    row, draw the row's sprites.  The wait is for the START of the blank, so a second MOVE
    straight after the first does not wait again (they share one blank), and a game that wants
    one frame per update should still HOLD, change the slots and SHOW once.  Ordinary text
    drawing is not synchronised (it only touches a few cells).
  * Control code 1C used to be cursor right.  It is now the sprite prefix; use ESC [ C.
  * Speed (an estimate, not measured on the hardware): moving a 16 x 16 sprite redraws about
    50 cells, roughly 1 to 2 ms at 40 MHz; a sideways or vertical scroll with sprites on the
    screen redraws every cell that they cover as well.  Hold and show a whole frame together.
  * RAM: the layer uses about 4.0 KB (SPR_POOL_BYTES 1280 for pictures, 256 for the picture
    table, 192 for the slots, 2160 for the cell background, and 130 for the rest).  To pay for
    it the default receive buffer is now 6144 bytes (RX_BUF_BYTES in Terminal.h, was 8192).
    A game that uses sprites sends far fewer bytes.  If your build says there is not enough memory
    for the stack, lower RX_BUF_BYTES, TILE_POOL_BYTES (vt100.c) or SPR_POOL_BYTES (SpriteLayer.h);
    if it has memory to spare you can raise RX_BUF_BYTES again.  The memory summary
    (dist/.../memoryfile.xml) says how much is free; the stack needs about 1040.
  * demo/demo_sprites.bin is raw terminal data: send it from a PC to the terminal's serial input.  It is not a 6502 program.
    To run it from the SBC's monitor use demo/DEMOSPR.BIN (L DEMOSPR 0500, then R), a small 6502 program that sends the
    same bytes through SBC_CHROUT ($FE03) and returns to the monitor (tools/make_6502_demo.py makes it).
  * The code is in SpriteLayer.h, which is part of Video.c (it is #included at the end of it, so
    the MPLAB X project needs no new file).  demo/demo_sprites.bin shows it working.

LIMITATIONS
-----------
* Monochrome: colours ignored. SGR 3 and 6 select the big fonts as in the
  original; set SGR_SELECTS_FONTS to 0 in vt100.c to disable.
* Alternate screen (?1049) is approximated by clearing the screen.
* No DECCOLM, DECSCNM or double-height/width lines.
* Keyboard cannot produce characters >= 0x80 (those codes are special keys).
* C0 graphic glyphs (0x01-0x1F) are not displayed.
* Insert mode (IRM) is slow because there is no text buffer.
* NTSC setup menu may wrap (44 columns) - pre-existing.

REGENERATING FONTS
------------------
tools/genfont.py builds FontsExt.h from the original Fonts.h plus DejaVu Sans Mono
(needs Python, Pillow, numpy, fontTools):
   python3 genfont.py Terminal/Fonts.h Terminal/FontsExt.h

HOST TEST
---------
host_test/: fuzz.inc runs random drawing with and without moving sprites and compares the
screens (FUZZN=3000 ./hosttest runs 3000 seeds; FUZZ1=n TRACE=1 ./hosttest shows one).  Build with   sh build.sh <path to Terminal folder>   (gcc),
run ./hosttest (VGA) or ./hosttest pal. tools/make_demo.py and make_demo_cc.py make
demo/demo_cp437.bin and demo/demo_controlcodes.bin (control code mode): send them raw to the terminal (e.g. cat to the serial port at
115200 baud) to see the new features.

BUILDING
--------
Open the project in MPLAB X as before; FontsExt.h is a new header included by
Video.c. Files are CRLF like the originals.

Defaults: the baud rate used when all three speed jumpers are open is now 115200 (it was
1200) and control code mode is on.  These are only defaults for a blank settings page:
if you have saved settings (set-up item M) the saved values are used, and a settings page
saved by the previous version of this firmware had control codes stored as 0, which now
means OFF.  Use set-up K (reset defaults) then M, or set J again, after upgrading.


Keeping pace with the terminal (sprite frames)
----------------------------------------------
* SHOW, and any scroll that passes under a sprite, waits for the vertical blank so the picture does not tear.  It waits at most once
  per video frame, and not at all when more than 1024 bytes are waiting in the receive buffer, so a busy stream is never slowed further.
* The receive buffer (6144 bytes) can still overflow if a program sends faster than the terminal draws.  The terminal now drops the
  new byte when the buffer is full (before, it could wrap round and wipe the buffer, which garbled the screen).  Dropped bytes still
  corrupt the picture, so pace your frames: send  1C 0C  (IDENTIFY) after each frame and wait for the "1" of the reply "SP1".
* STATUS (1C 0D): the terminal replies "ST" dd pppp (hex digits): dd = how many received bytes it had to throw away (receive buffer
  full, or a UART error) since the last STATUS, 00 to FF; pppp = the most bytes that were waiting in the receive buffer.  Both counters
  start again from 0.  If a game leaves bits of objects behind, send 1C 0D at the end of a run: any dd above 00 means bytes were lost
  and the screen cannot be right.  (The terminal's receive buffer is 6144 bytes; pppp near 1800 (hex) means it was nearly full.)
* Text and fine detail under a sprite is saved only as 3x3 pixel blocks.  When a sprite has passed over a character or a tile with fine
  detail, the character comes back looking blocky.  Block graphics, filled areas and blank space come back exactly.

Demos (demo/)
-------------
* DEMOSPR.BIN: sprite demo.  L DEMOSPR 0500, then R.  Four sprites move over a block graphics background; the tank eats a row of
  pellets (text erased under a sprite).  After every frame it sends IDENTIFY and waits for the reply.  Part 1 is paced, part 2 sends
  the same frames as fast as it can; the bottom row shows the STATUS result of each part.  Q quits.
* DEMOSCRL.BIN: scrolling demo.  L DEMOSCRL 0500, then R.  Part 1 is a four layer parallax landscape (each layer has its own
  scrolling region and speed, pixel scrolls of 1 and 3 pixels, a whole character scroll for the ground and the text ticker) with three
  sprites on top.  Part 2 is a star field scrolling down (code 15) with a ship over it.  Q quits.
* demo/source/ has the ca65 sources (demo_sprites.s, demo_scroll.s, terminal_macros.inc, terminal_lib.inc, pics.inc, scrolldata.inc made
  by make_scrolldata.py) and make_demo.bat.  run6502.py runs a demo in an emulator (py65) and records what it sent to the terminal;
  host_test/replay_check.py replays such a recording through the host test and checks that, after HIDE ALL, the screen equals the
  same stream played without any sprite commands.
