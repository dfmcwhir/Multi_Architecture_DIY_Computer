/****************************************************************************************
 vt100.c

	vt100 decoder for the VT100 Terminal program


	Copyright (C) 2014 Geoff Graham (projects@geoffg.net)
	All rights reserved.

	This file and the program created from it are FREE FOR COMMERCIAL AND
	NON-COMMERCIAL USE as long as the following conditions are aheared to.

	Copyright remains Geoff Graham's, and as such any Copyright notices in the
	code are not to be removed.  If this code is used in a product, Geoff Graham
	should be given attribution as the author of the parts used.  This can be in
	the form of a textual message at program startup or in documentation (online
	or textual) provided with the program or product.

	Redistribution and use in source and binary forms, with or without modification,
	are permitted provided that the following conditions  are met:
	1. Redistributions of source code must retain the copyright notice, this list
	   of conditions and the following disclaimer.
	2. Redistributions in binary form must reproduce the above copyright notice, this
	   list of conditions and the following disclaimer in the documentation and/or
	   other materials provided with the distribution.
	3. All advertising materials mentioning features or use of this software must
	   display the following acknowledgement:
	   This product includes software developed by Geoff Graham (projects@geoffg.net)

	THIS SOFTWARE IS PROVIDED BY GEOFF GRAHAM ``AS IS'' AND  ANY EXPRESS OR IMPLIED
	WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
	MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT
	SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
	SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
	PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
	BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
	CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING
	IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
	SUCH DAMAGE.

	The licence and distribution terms for any publically available version or
	derivative of this code cannot be changed.  i.e. this code cannot simply be copied
	and put under another distribution licence (including the GNU Public Licence).
****************************************************************************************/

/****************************************************************************************
 Modifications (2026)

 The decoder for ANSI/VT100 control sequences (ESC [ ...) has been rewritten as a state
 machine.  Compared with the original table driven decoder it:
   - accepts any number of parameters (for example ESC[1;4;7m)
   - silently ignores sequences that it does not support (the original printed the
     remains of them on the screen)
   - supports many more commands:  scrolling regions, insert/delete of lines and
     characters, tab stops, more cursor movement commands, origin mode, insert mode,
     application cursor keys, DEC special graphics (line drawing) via ESC ( 0 and
     SO/SI, bold, etc.
 The original table is still used for VT52 mode and for the short (non CSI) escape
 sequences.  All of the original sequences continue to work, including the non standard
 ones (ESC[Z...Z for graphics, ESC[>, ESC[=, ESC[n q for the LEDs and ESC[?9h).
****************************************************************************************/


#define _SUPPRESS_PLIB_WARNING

#include <p32xxxx.h>
#include <plib.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>
#include "Terminal.h"
#include "video.h"
#include "vt100.h"

// if this is true the standard SGR codes 3 and 6 select the large fonts (as they always have in this terminal)
// set it to false if you would prefer them to be ignored (some programs use ESC[3m for italics)
#define SGR_SELECTS_FONTS   true

#define VTBUF_SIZE  20
unsigned char vtbuf[VTBUF_SIZE + 1];                                // buffer for chars waiting to be decoded
int vtcnt;                                                          // count of the number of chars in vtbuf

#define MAXARGS     16
short arg[MAXARGS];                                                 // (short to save RAM)
int argc;                                             // arguments to a command

struct s_cmdtbl {                                                   // structure of the command table
    char *name;                                                     // the string
    int mode;                                                       // 1 = ANSI only, 2 = VT52, 3 = both
    void (*fptr)(void);                                             // pointer to the function that will interpret that command
};
int CmdTblSize;
extern const struct s_cmdtbl cmdtbl[];

int mode;                                                           // current mode.  can be VT100 or VT52

int AttribUL, AttribRV, AttribInvis, AttribBold;                    // attributes that can be turned on/off
int AppCursorKeys, NewLineMode, InsertMode, OriginMode;             // modes that can be turned on/off

// the saved state for ESC 7 and ESC 8
int SaveX, SaveY, SaveUL, SaveRV, SaveInvis, SaveBold, SaveFontNbr;
int SaveOrigin, SaveShift, SaveSet0, SaveSet1;

// the state of the CSI decoder
static unsigned char csiActive;                                               // true while a CSI sequence is being collected
static unsigned char csiMarker;                                               // the private marker (one of < = > ?) or zero
static unsigned char csiInter;                                                // the first intermediate character (0x20 - 0x2f) or zero
static unsigned char csiHave;                                                 // true if we are part way through a number
static signed char csiIdx;                                                   // the index of the argument being collected
static unsigned char csiSemi;                                                 // true if the last character was a separator
static unsigned char csiDraw;                                                 // true if this is the graphics command (ESC [ Z .... Z)
static unsigned char csiFirst;                                                // true if the next character is the first after the [
static unsigned char csiBad;                                                  // true if the sequence is malformed

// the state of the control code decoder (see CCChar() below)
static unsigned char ccPending;                                     // the code that is waiting for its following byte(s) or zero
static unsigned char ccHave;                                        // how many parameter bytes of the pending code have been received so far
static unsigned char ccArg;                                         // the first parameter byte
static unsigned short ccCount;                                      // the number of data bytes of a tile received so far
static unsigned short ccBase;                                       // where in the tile pool the tile being defined starts (0xffff = ignore the data)
static unsigned short ccTotal;                                      // the number of data bytes in the tile being defined
static unsigned char ccCols;                                        // the number of columns in the tile being defined

// tiles.  A tile is a block of characters (any number of columns and rows) that is stored with SET TILE and drawn with SEND TILE.
// Tile n starts at byte n * columns * rows of the tile pool, so the highest slot is TILE_POOL_BYTES / (columns * rows) - 1.
// Tiles of different sizes share the pool so a slot of one size can overlap slots of another size
#ifndef TILE_POOL_BYTES
#define TILE_POOL_BYTES 512                                         // RAM for tile data (256 to 512 suggested)
#endif
#ifndef TILE_MAX_SLOTS
#define TILE_MAX_SLOTS  128                                         // the number of slots that can have a size recorded (slot numbers 0 to this - 1)
#endif
static unsigned char Tiles[TILE_POOL_BYTES];
static unsigned char TileCols[TILE_MAX_SLOTS];                      // the size of each tile.  Zero columns means that the slot has not been defined
static unsigned char TileRows[TILE_MAX_SLOTS];

// the value of argument i or the default value d if it was not supplied (or was zero)
#define PARAM(i, d)     (((i) < argc && arg[i] > 0) ? arg[i] : (d))

static void CSIDispatch(int c);



/***************************************************************************************************************************************
 Utility functions
***************************************************************************************************************************************/

void VideoPrintString(char *p) {
    while(*p) VideoPutc(*p++);
}


// utility function to move the cursor.  x and y are 1 based and are limited to the screen
void CursorPosition(int x, int y) {
    int cw = fontWidth * fontScale;
    int ch = fontHeight * fontScale;
    int cols = HRes / cw;
    int rows = VRes / ch;

    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused

    if(x < 1) x = 1;
    if(x > cols) x = cols;
    if(y < 1) y = 1;
    if(y > rows) y = rows;

    CursorX = cw * (x - 1);
    CursorY = ch * (y - 1);
    CharPosX = x;                                                   // update the horizontal character position
    CharPosY = y;                                                   // update the vertical character position
}


// get the first and last line of the scrolling region (1 = top line)
static void RegionLines(int *first, int *last) {
    int rows = TextRows();
    *first = ScrollTop ? ScrollTop : 1;
    *last = ScrollBot ? ScrollBot : rows;
    if(*last > rows) *last = rows;
    if(*first >= *last) { *first = 1; *last = rows; }
}


// move the cursor to an absolute position.  If origin mode is on the row is relative to the top of the scrolling region
static void SetCursor(int col, int row) {
    if(OriginMode) {
        int rt, rb;
        RegionLines(&rt, &rb);
        row += rt - 1;
        if(row > rb) row = rb;
    }
    CursorPosition(col, row);
}


// move the cursor up (n is negative) or down (n is positive) but stop at the edge of the scrolling region if we are in it
static void MoveRows(int n) {
    int rt, rb, y, lim;
    RegionLines(&rt, &rb);
    y = CharPosY + n;
    if(n < 0) {
        lim = (CharPosY >= rt) ? rt : 1;
        if(y < lim) y = lim;
    } else {
        lim = (CharPosY <= rb) ? rb : TextRows();
        if(y > lim) y = lim;
    }
    CursorPosition(CharPosX, y);
}


static void SyncCharPos(void) {
    CharPosX = (CursorX / (fontWidth * fontScale)) + 1;
    CharPosY = (CursorY / (fontHeight * fontScale)) + 1;
}



/***************************************************************************************************************************************
 Command functions
 These are used by the command table and by the CSI decoder.  When called from the table the arguments are in arg[] and argc
***************************************************************************************************************************************/

// cursor up one or more lines
void cmd_CurUp(void) {
    if(argc == 0 || arg[0] == 0) arg[0] = 1;
    MoveRows(-arg[0]);
}


// cursor down one or more lines
void cmd_CurDown(void) {
    if(argc == 0 || arg[0] == 0) arg[0] = 1;
    MoveRows(arg[0]);
}


// cursor left one or more chars
void cmd_CurLeft(void) {
    if(argc == 0 || arg[0] == 0) arg[0] = 1;
    CursorPosition(CharPosX - arg[0], CharPosY);
}


// cursor right one or more chars
void cmd_CurRight(void) {
    if(argc == 0 || arg[0] == 0) arg[0] = 1;
    CursorPosition(CharPosX + arg[0], CharPosY);
}


// cursor home
void cmd_CurHome(void) {
    CursorPosition(1, 1);
}


// position cursor
void cmd_CurPosition(void) {
    if(argc < 1 || arg[0] == 0) arg[0] = 1;
    if(argc < 2 || arg[1] == 0) arg[1] = 1;
    SetCursor(arg[1], arg[0]);                                      // note that the argument order is Y, X
}


// enter VT52 mode
void cmd_VT52mode(void) {
    mode = VT52;
}


// enter VT100 mode
void cmd_VT100mode(void) {
    mode = VT100;
}


// clear to end of line
void cmd_ClearEOL(void) {
    int x, y;
    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
    SPR_BEGIN(CursorX, CursorY, HRes, CursorY + (fontHeight * fontScale));
    for(y = CursorY; y < CursorY + (fontHeight * fontScale); y++)
        for(x = CursorX; x < HRes; x++)
            plot(x, y, 0);
    SPR_END();
}


// clear to end of screen
void cmd_ClearEOS(void) {
    int y, n;
    cmd_ClearEOL();
    y = CursorY + (fontHeight * fontScale);
    n = VBuf*(HBuf/8) - (y * (HBuf/8));
    SPR_BEGIN(0, y, HRes, VRes);
    if(y < VBuf) memset((char *)VideoBuf + (y * (HBuf/8)), 0, n);
    SPR_END();
}


// clear from the beginning of the line to the cursor
void cmd_ClearBOL(void) {
    int x, y;
    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
    SPR_BEGIN(0, CursorY, CursorX, CursorY + (fontHeight * fontScale));
    for(y = CursorY; y < CursorY + (fontHeight * fontScale); y++)
        for(x = 0; x < CursorX; x++)
            plot(x, y, 0);
    SPR_END();
}


// clear from home to the cursor
void cmd_ClearBOS(void) {
    int x, y;
    cmd_ClearBOL();
    SPR_BEGIN(0, 0, HRes, CursorY);
    for(y = CursorY - 1; y >= 0; y--)
        for(x = 0; x < HRes; x++)
            plot(x, y, 0);
    SPR_END();
}


// turn the cursor off
void cmd_CursorOff(void) {
    CursorOff = true;
}


// turn the cursor on
void cmd_CursorOn(void) {
    CursorOff = false;
}


// clear the whole line
void cmd_ClearLine(void) {
    cmd_ClearBOL();
    cmd_ClearEOL();
}


// save the current attributes
void cmd_CurSave(void) {
    SaveX = CharPosX;
    SaveY = CharPosY;
    SaveUL = AttribUL;
    SaveRV = AttribRV;
    SaveInvis = AttribInvis;
    SaveBold = AttribBold;
    SaveFontNbr = fontNbr;
    SaveOrigin = OriginMode;
    SaveShift = ShiftOut;
    SaveSet0 = CharSet[0];
    SaveSet1 = CharSet[1];
}


// restore the saved attributes
void cmd_CurRestore(void) {
    if(SaveFontNbr == -1) return;
    OriginMode = SaveOrigin;
    CursorPosition(SaveX, SaveY);
    AttribUL = SaveUL;
    AttribRV = SaveRV;
    AttribInvis = SaveInvis;
    AttribBold = SaveBold;
    ShiftOut = SaveShift;
    CharSet[0] = SaveSet0;
    CharSet[1] = SaveSet1;
    initFont(SaveFontNbr);
}


// set the keyboard to numbers mode
void cmd_SetNumLock(void) {
    NumLock = false;
    setLEDs(CapsLock,  false, 0);
}


// set the keyboard to arrows mode
void cmd_ExitNumLock(void) {
    NumLock = true;
    setLEDs(CapsLock,  true, 0);
}


// respond as a VT52
void cmd_VT52ID(void) {
    putSerialString("\033[/Z");
}


// respond as a VT52 (this is the real VT52 response)
void cmd_VT52ID2(void) {
    putSerialString("\033/Z");
}


// respond as a VT100 thats OK
void cmd_VT100OK(void) {
    putSerialString("\033[0n");
}


// respond as a VT100 with no optiond
void cmd_VT100ID(void) {
    putSerialString("\033[?1;0c");    // vt100 with no options
}


// reset the terminal (RIS)
void cmd_Reset(void) {
    mode = VT100;
    initFont(1);
    ConfigBuffers(Option[O_LINES24]);
    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
    ClearScreen();
    CursorPosition(1, 1);
    AttribUL = 0;
    AttribRV = 0;
    AttribInvis = 0;
    AttribBold = 0;
    SaveFontNbr = -1;
    CharSet[0] = CharSet[1] = CS_ASCII;
    ShiftOut = false;
    ScrollTop = ScrollBot = 0;
    OriginMode = false;
    InsertMode = false;
    NewLineMode = false;
    AppCursorKeys = false;
    AutoLineWrap = true;
    CursorOff = false;
    ResetTabStops();
    CursorBlink = true;
    CursorChar = -1;
    MosaicMode = false;
    CharRepeat = 0;
    ccPending = 0;
}


// soft reset (DECSTR).  Like a reset but leaves the screen contents and cursor position alone
static void cmd_SoftReset(void) {
    AttribUL = AttribRV = AttribInvis = AttribBold = 0;
    initFont(1);
    SaveFontNbr = -1;
    CharSet[0] = CharSet[1] = CS_ASCII;
    ShiftOut = false;
    ScrollTop = ScrollBot = 0;
    OriginMode = false;
    InsertMode = false;
    AppCursorKeys = false;
    AutoLineWrap = true;
    CursorOff = false;
}


// control the keyboard leds
void cmd_LEDs(void) {
    static int led1 = 0;
    static int led2 = 0;
    static int led3 = 0;
    int i;

    if(argc == 0) { arg[0] = 0; argc = 1; }
    for(i = 0; i < argc; i++) {
        if(arg[i] == 0) led1 = led2 = led3 = 0;
        if(arg[i] == 2) led1 = 1;
        if(arg[i] == 1) led2 = 1;
        if(arg[i] == 3) led3 = 1;
    }
    setLEDs(led1, led2, led3);
}


// set attributes (SGR).  There can be any number of arguments
void cmd_Attributes(void) {
    int i;

    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
    if(argc == 0) { arg[0] = 0; argc = 1; }                         // no arguments is the same as zero
    for(i = 0; i < argc; i++) {
        switch(arg[i]) {
            case 0:  AttribUL = AttribRV = AttribInvis = AttribBold = 0;
                     initFont(1);
                     break;
            case 1:  AttribBold = 1; break;
            case 3:  if(SGR_SELECTS_FONTS) initFont(2); break;
            case 4:  AttribUL = 1; break;
            case 6:  if(SGR_SELECTS_FONTS) initFont(3); break;
            case 7:  AttribRV = 1; break;
            case 8:  AttribInvis = 1; break;
            case 22: AttribBold = 0; break;
            case 23: if(SGR_SELECTS_FONTS && fontNbr == 2) initFont(1); break;
            case 24: AttribUL = 0; break;
            case 27: AttribRV = 0; break;
            case 28: AttribInvis = 0; break;
            case 38:                                                // extended colours (38;5;n and 38;2;r;g;b) are skipped over
            case 48: if(i + 1 < argc) i += (arg[i + 1] == 5) ? 2 : ((arg[i + 1] == 2) ? 4 : 1);
                     break;
            default: break;                                         // colours, blink, etc cannot be shown on a monochrome display
        }
    }
}


// respond with the current cursor position
// write the decimal text of a number (0 - 99999999, negative numbers as zero) to p and return the number of characters written.  This is used
// instead of sprintf() because the C library's printf uses a lot of RAM
int IntToStr(char *p, int v) {
    char t[10];
    int n = 0, i = 0;
    if(v < 0) v = 0;
    do { t[n++] = '0' + (v % 10); v /= 10; } while(v && n < 9);
    while(n) p[i++] = t[--n];
    p[i] = 0;
    return i;
}


void cmd_ReportPosition(void) {
    char s[24];
    char *p = s;
    int row = CharPosY, col = CharPosX, rt, rb;
    if(col > TextCols()) col = TextCols();
    if(OriginMode) {
        RegionLines(&rt, &rb);
        row -= rt - 1;
        if(row < 1) row = 1;
    }
    *p++ = 033; *p++ = '[';
    p += IntToStr(p, row);
    *p++ = ';';
    p += IntToStr(p, col);
    *p++ = 'R'; *p = 0;
    putSerialString(s);
}


// do a line feed
void cmd_Lf(void) {
    VideoPutc('\n');
}


// index (ESC D).  A line feed that does not do a carriage return even in new line mode
void cmd_LineFeed(void) {
    ShowCursor(false);
    IndexDown();
}


// next line (ESC E).  This is a carriage return followed by a line feed
void cmd_NextLine(void) {
    ShowCursor(false);
    CursorX = 0;
    IndexDown();
    SyncCharPos();
}


// do an upwards line feed with a reverse scroll
void cmd_ReverseLineFeed(void) {
    ReverseIndex();
}


// set a tab stop at the cursor (ESC H)
void cmd_SetTab(void) {
    SetTabStop();
}


// designate the character set for G0 or G1.  The character selecting the set (eg, 0 or B) is in arg[0] with 31 subtracted
static int CharSetFromCode(int c) {
    switch(c + 31) {
        case '0':
        case '2': return CS_DEC;                                    // special graphics (the alternate ROM version is the same)
        case 'A': return CS_UK;
        default:  return CS_ASCII;                                  // B (US ASCII) and anything that we do not have
    }
}
void cmd_SetG0(void) { CharSet[0] = CharSetFromCode(arg[0]); }
void cmd_SetG1(void) { CharSet[1] = CharSetFromCode(arg[0]); }


// screen alignment test (ESC # 8).  Fill the screen with the letter E.  Other ESC # commands (double height, etc) are ignored
void cmd_Hash(void) {
    int i, n, wrap = AutoLineWrap;
    if(arg[0] + 31 != '8') return;
    ScrollTop = ScrollBot = 0;
    AutoLineWrap = true;
    ClearScreen();
    CursorPosition(1, 1);
    n = TextRows() * TextCols();
    for(i = 0; i < n; i++) VideoPutc('E');
    AutoLineWrap = wrap;
    CursorPosition(1, 1);
}


// turn on automatic line wrap, etc.  This is used for the legacy form ESC [ ? n h
void cmd_SetMode(void) {
    if(arg[0] == 7) AutoLineWrap = true;
    if(arg[0] == 9 && vga) {
        cmd_CurHome();
        ConfigBuffers(true);
        ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
        ClearScreen();
        CursorPosition(1, 1);
    }
}


// turn off automatic line wrap, etc
void cmd_ResetMode(void) {
    if(arg[0] == 7) AutoLineWrap = false;
    if(arg[0] == 9 && vga) {
        ConfigBuffers(false);
        ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
        ClearScreen();
        CursorPosition(1, 1);
    }
}


// draw graphics
void cmd_Draw(void) {
    if(arg[0] == 1) DrawLine(arg[1], arg[2], arg[3], arg[4], 1);
    if(arg[0] == 2) DrawBox(arg[1], arg[2], arg[3], arg[4], 0, 1);
    if(arg[0] == 3) DrawBox(arg[1], arg[2], arg[3], arg[4], 1, 1);
    if(arg[0] == 4) DrawCircle(arg[1], arg[2], arg[3], 0, 1, vga ? 1.14 : 1.0);
    if(arg[0] == 5) DrawCircle(arg[1], arg[2], arg[3], 1, 1, vga ? 1.14 : 1.0);
}


// do nothing for escape sequences that are not implemented
void cmd_NULL(void) {}



/***************************************************************************************************************************************
 The command table
 This is used for VT52 mode and for the escape sequences that are not CSI (ie, do not start with ESC [) in VT100 mode.
 It is scanned from top to bottom by VT100Putc()
 Characters are matched exactly (ie, case sensitive) except for the @ character which is a wild card character representing
 zero or more decimal characters of an argument and ^ which represents a single char and the value returned is the char - 31
 The CSI sequences for VT100 mode are decoded by CSIChar() and CSIDispatch() below.
**************************************************************************************************************************************/
const struct s_cmdtbl cmdtbl[]  = {
    { "\033A",          VT52,       cmd_CurUp },
    { "\033B",          VT52,       cmd_CurDown },
    { "\033C",          VT52,       cmd_CurRight },
    { "\033D",          VT52,       cmd_CurLeft },
    { "\033H",          VT52,       cmd_CurHome },
    { "\033I",          VT52,       cmd_ReverseLineFeed },
    { "\033[^^",        VT52,       cmd_CurPosition },
    { "\033Y^^",        VT52,       cmd_CurPosition },              // the real VT52 direct cursor address

    { "\033J",          VT52,       cmd_ClearEOS },
    { "\033K",          VT52,       cmd_ClearEOL },

    { "\033>",          VT52,       cmd_SetNumLock },
    { "\033=",          VT52,       cmd_ExitNumLock },

    { "\033[Z",         VT52,       cmd_VT52ID },
    { "\033Z",          VT52,       cmd_VT52ID2 },
    { "\033<",          VT52,       cmd_VT100mode },
    { "\033F",          VT52,       cmd_NULL },
    { "\033G",          VT52,       cmd_NULL },

    { "\0337",          VT100,      cmd_CurSave },
    { "\0338",          VT100,      cmd_CurRestore },
    { "\0336n",         VT100,      cmd_ReportPosition },           // (this has always been here but is not a real sequence, the real one is ESC [ 6 n)

    { "\033D",          VT100,      cmd_LineFeed },
    { "\033M",          VT100,      cmd_ReverseLineFeed },
    { "\033E",          VT100,      cmd_NextLine },
    { "\033H",          VT100,      cmd_SetTab },
    { "\033Z",          VT100,      cmd_VT100ID },

    { "\033(^",         VT100,      cmd_SetG0 },                    // select the character sets
    { "\033)^",         VT100,      cmd_SetG1 },
    { "\033*^",         VT100,      cmd_NULL },                     // G2 and G3 are not supported
    { "\033+^",         VT100,      cmd_NULL },
    { "\033#^",         VT100,      cmd_Hash },
    { "\033%^",         VT100,      cmd_NULL },                     // character set selection (UTF-8, etc) is ignored
    { "\033O^",         VT100,      cmd_NULL },                     // SS3 sequences are ignored
    { "\033=",          VT100,      cmd_NULL },                     // keypad modes are ignored
    { "\033>",          VT100,      cmd_NULL },

    { "\033c" ,         BOTH,       cmd_Reset },
};                                                                  // must be last in the table



/***************************************************************************************************************************************
 The decoder for CSI sequences (ESC [ ...)
 The format is:   ESC [  [marker]  [number ; number ; ...]  [intermediate]  final
***************************************************************************************************************************************/

static void CSIStart(void) {
    csiActive = true;
    csiMarker = csiInter = 0;
    csiHave = csiSemi = csiDraw = csiBad = false;
    csiFirst = true;
    csiIdx = -1;
    argc = 0;
    arg[0] = 0;
}


// set or reset a mode for ESC [ ? n h and ESC [ ? n l
static void PrivateMode(int n, int set) {
    switch(n) {
        case 1:    AppCursorKeys = set; break;                      // DECCKM  cursor keys send ESC O A instead of ESC [ A
        case 2:    if(!set) mode = VT52; break;                     // DECANM  reset enters VT52 mode
        case 6:    OriginMode = set;                                // DECOM   origin mode
                   SetCursor(1, 1);
                   break;
        case 7:    AutoLineWrap = set; break;                       // DECAWM  auto wrap
        case 9:    arg[0] = 9;                                      // (not standard) 24 or 36 lines on VGA
                   if(set) cmd_SetMode(); else cmd_ResetMode();
                   break;
        case 25:   CursorOff = !set; break;                         // DECTCEM show or hide the cursor
        case 47:                                                    // alternate screen.  There is no memory for a second screen so
        case 1047:                                                  // this just clears the screen when switching (and saves and
        case 1049: if(set) {                                        // restores the cursor for 1049)
                       if(n == 1049) cmd_CurSave();
                       ShowCursor(false);
                       ClearScreen();
                       CursorPosition(1, 1);
                   } else {
                       ShowCursor(false);
                       ClearScreen();
                       if(n == 1049) cmd_CurRestore();
                   }
                   break;
        default:   break;                                           // everything else is ignored (blink, mouse, etc)
    }
}


// execute a completed CSI sequence.  The arguments are in arg[] and argc, c is the final character
static void CSIDispatch(int c) {
    int i, n, rt, rb;

    if(csiDraw) {                                                   // this is the (non standard) graphics command
        if(c == 'Z' && argc >= 4) cmd_Draw();
        return;
    }

    if(csiMarker == '?') {                                          // DEC private modes
        if(c == 'h' || c == 'l')
            for(i = 0; i < argc; i++) PrivateMode(arg[i], c == 'h');
        return;
    }
    if(csiMarker) return;                                           // other private sequences are not supported

    if(csiInter) {                                                  // sequences with an intermediate character
        if(csiInter == '!' && c == 'p') cmd_SoftReset();            // DECSTR - soft reset.  (all others, eg DECSCUSR, are ignored)
        return;
    }

    RegionLines(&rt, &rb);
    switch(c) {
        // cursor movement
        case 'A': cmd_CurUp();    break;                            // CUU
        case 'B': cmd_CurDown();  break;                            // CUD
        case 'C': cmd_CurRight(); break;                            // CUF
        case 'D': cmd_CurLeft();  break;                            // CUB
        case 'E': CursorPosition(1, CharPosY); MoveRows(PARAM(0, 1)); break;        // CNL
        case 'F': CursorPosition(1, CharPosY); MoveRows(-PARAM(0, 1)); break;       // CPL
        case 'G':                                                   // CHA
        case '`': CursorPosition(PARAM(0, 1), CharPosY); break;     // HPA
        case 'a': CursorPosition(CharPosX + PARAM(0, 1), CharPosY); break;          // HPR
        case 'd': SetCursor(CharPosX, PARAM(0, 1)); break;          // VPA
        case 'e': MoveRows(PARAM(0, 1)); break;                     // VPR
        case 'H':                                                   // CUP
        case 'f': SetCursor(PARAM(1, 1), PARAM(0, 1)); break;       // HVP
        case 's': if(argc == 0) cmd_CurSave(); break;               // SCOSC (ANSI.SYS)
        case 'u': if(argc == 0) cmd_CurRestore(); break;            // SCORC (ANSI.SYS)

        // erasing
        case 'J': n = argc ? arg[0] : 0;                            // ED
                  if(n == 0) cmd_ClearEOS();
                  else if(n == 1) cmd_ClearBOS();
                  else if(n == 2) ClearScreen();
                  break;                                            // (3, erase the scroll back, is ignored)
        case 'K': n = argc ? arg[0] : 0;                            // EL
                  if(n == 0) cmd_ClearEOL();
                  else if(n == 1) cmd_ClearBOL();
                  else if(n == 2) cmd_ClearLine();
                  break;
        case 'X': EraseChars(PARAM(0, 1)); break;                   // ECH

        // inserting and deleting
        case '@': InsertChars(PARAM(0, 1)); break;                  // ICH
        case 'P': DeleteChars(PARAM(0, 1)); break;                  // DCH
        case 'L': if(CharPosY >= rt && CharPosY <= rb)              // IL
                      ScrollArea(CharPosY, rb, -PARAM(0, 1));
                  break;
        case 'M': if(CharPosY >= rt && CharPosY <= rb)              // DL
                      ScrollArea(CharPosY, rb, PARAM(0, 1));
                  break;
        case 'S': ScrollArea(rt, rb, PARAM(0, 1)); break;           // SU
        case 'T': if(argc <= 1) ScrollArea(rt, rb, -PARAM(0, 1));   // SD
                  break;

        // tabs
        case 'I': TabForward(PARAM(0, 1)); SyncCharPos(); break;    // CHT
        case 'g': n = argc ? arg[0] : 0;                            // TBC
                  if(n == 0) ClearTabStop(false);
                  else if(n == 3) ClearTabStop(true);
                  break;

        // attributes, modes and reports
        case 'm': cmd_Attributes(); break;                          // SGR
        case 'h':                                                   // SM
        case 'l': for(i = 0; i < argc; i++) {                       // RM
                      if(arg[i] == 4) InsertMode = (c == 'h');      // IRM
                      if(arg[i] == 20) NewLineMode = (c == 'h');    // LNM
                  }
                  break;
        case 'r': n = PARAM(1, TextRows());                         // DECSTBM - set the scrolling region
                  if(n > TextRows()) n = TextRows();
                  i = PARAM(0, 1);
                  if(i < n) {
                      if(i == 1 && n == TextRows()) ScrollTop = ScrollBot = 0; else { ScrollTop = i; ScrollBot = n; }
                      SetCursor(1, 1);
                  }
                  break;
        case 'n': n = argc ? arg[0] : 0;                            // DSR
                  if(n == 5) cmd_VT100OK();
                  else if(n == 6) cmd_ReportPosition();
                  break;
        case 'c': if(argc == 0 || arg[0] == 0) cmd_VT100ID(); break;                // DA
        case 'q': cmd_LEDs(); break;                                // DECLL (and the keyboard LEDs)
        default:  break;                                            // anything else is silently ignored
    }
}


// process a character while a CSI sequence is being collected
static void CSIChar(int c) {
    if(c == 0x1b) {                                                 // an ESC cancels the sequence and starts a new one
        csiActive = false;
        vtbuf[0] = 0x1b;
        vtcnt = 1;
        return;
    }
    if(c == 0x18 || c == 0x1a || c >= 0x7f) {                       // CAN, SUB, DEL and 8 bit characters abort the sequence
        csiActive = false;
        return;
    }
    if(c < 0x20) {                                                  // other control characters are executed straight away
        VideoPutc(c);
        return;
    }

    if(csiFirst) {                                                  // the first character after the [ can select a non standard command
        csiFirst = false;
        if(c == 'Z') { csiDraw = true; return; }                    // ESC [ Z ... Z is the graphics command
        if(c == '>') { csiActive = false; cmd_SetNumLock(); return; }       // ESC [ >  and ESC [ = were already in the table
        if(c == '=') { csiActive = false; cmd_ExitNumLock(); return; }
    }

    if(c >= '0' && c <= '9') {                                      // a digit is part of a number
        if(csiInter) { csiBad = true; return; }
        if(!csiHave) {
            csiHave = true;
            csiSemi = false;
            if(argc < MAXARGS) { arg[argc] = 0; csiIdx = argc++; } else csiIdx = -1;
        }
        if(csiIdx >= 0 && arg[csiIdx] < 9999) arg[csiIdx] = arg[csiIdx] * 10 + (c - '0');
        return;
    }

    if(c == ';' || c == ':') {                                      // separator between numbers
        if(csiInter) { csiBad = true; return; }
        if(!csiHave && argc < MAXARGS) arg[argc++] = 0;             // a missing number is the same as zero
        csiHave = false;
        csiSemi = true;
        return;
    }

    if(c >= 0x3c && c <= 0x3f) {                                    // < = > ? are private markers and are only valid at the start
        if(argc == 0 && !csiHave && !csiSemi && !csiMarker && !csiInter) csiMarker = c; else csiBad = true;
        return;
    }

    if(c >= 0x20 && c <= 0x2f) {                                    // intermediate characters (eg, ! or space)
        if(!csiInter) csiInter = c;
        return;
    }

    csiActive = false;                                              // this must be the final character (0x40 - 0x7e)
    if(csiSemi && argc < MAXARGS) arg[argc++] = 0;                  // a separator at the end means that there was a final zero
    if(!csiBad) CSIDispatch(c);
}



/***************************************************************************************************************************************
 Control code mode  (set-up item J)
 In this mode the control codes 0x01 - 0x1F (and 0x7F) directly control the display.  ANSI/VT100 escape sequences (ESC) still work.
 Some of these take one or two following bytes which are used as raw values (they can be any value including control codes).

   01  cursor home                           10  erase from the start of the line to the cursor
   02  n  define cursor character (0 = off)  11  erase from the cursor to the end of the line
   03  cursor blinks                         12  erase from the start of the screen to the cursor
   04  cursor solid                          13  erase from the cursor to the end of the screen
   05  x y  set a graphics pixel             14  scroll the screen up one line
   06  x y  reset a graphics pixel           15  scroll the screen down one line
   08  backspace                             16  scroll the screen left one character
   09  tab                                   17  scroll the screen right one character
   0A  line feed                             18  n  set the character attribute (see CCAttribute())
   0B  n  SEND TILE n (draw a stored tile)    19  n c r b0..b(c*r-1)  SET TILE n (define a c x r tile)
   0C  clear the screen and home the cursor  1A  n  draw the next byte as a character (even if it is 0x01 - 0x1F)
   0D  carriage return                       1B  ESC  (ANSI sequences)
   0E  n  set the column (0 = left)          1C  cursor right     1D  cursor left
   0F  n  set the row (0 = top)              1E  cursor up        1F  cursor down
   7F  delete the character at the cursor (the rest of the line moves left)
***************************************************************************************************************************************/


// code 0x18.  The byte is a set of flags:
//   bit 0 = 40 character lines.  0 selects the small font (80 columns), 1 the large font (about 40 columns)
//   bit 1 = bold
//   bit 2 = double height.  This terminal cannot stretch characters in one direction only so this selects the double size font instead
//   bits 3 - 6 = repeat count (each character is drawn this many times, 0 = 1)
//   bit 7 = block graphics (the characters sent are drawn as 2 x 4 blocks, each bit is a block, see DrawMosaic())
// so 0x00 is normal text and 0x80 is block graphics.  (Underline and reverse video are set with ESC [ 4 m and ESC [ 7 m)
static void CCAttribute(int b) {
    int fnt, cw, ch;

    AttribBold = (b >> 1) & 1;
    CharRepeat = (b >> 3) & 0x0f;
    MosaicMode = (b >> 7) & 1;
    fnt = (b & 4) ? 3 : ((b & 1) ? 2 : 1);
    if(fnt != fontNbr) {
        initFont(fnt);                                              // change the font and align the cursor with the new character grid
        cw = fontWidth * fontScale;
        ch = fontHeight * fontScale;
        CursorPosition((CursorX / cw) + 1, (CursorY / ch) + 1);
    }
}


// code 0x0B.  Draw tile n at the cursor, repeated CharRepeat times side by side.  If the tile will not fit above the bottom of the screen the
// screen is scrolled up to make room (as it would be for text).  The cursor ends up on the first line of the tile and just to the right of
// the last copy so that tiles can be sent side by side.  Parts of a tile that run off the right edge of the screen are not drawn
static void SendTile(int n) {
    int r, c, k, reps, tc, tr, x, y, rows, cols, save, need;
    unsigned char *p;

    if(n < 0 || n >= TILE_MAX_SLOTS || TileCols[n] == 0) return;
    tc = TileCols[n]; tr = TileRows[n];
    x = CharPosX; y = CharPosY;
    rows = TextRows(); cols = TextCols();
    need = y + tr - 1 - rows;                                       // the number of lines that the tile is below the bottom of the screen
    if(need > rows - 1) need = rows - 1;
    if(need > 0) {
        ShowCursor(false);
        ScrollArea(1, rows, need);                                  // scroll the whole screen up (ignoring any scrolling region)
        y -= need;
    }
    if(x < 1) x = 1;
    reps = (CharRepeat > 1) ? CharRepeat : 1;
    save = CharRepeat;
    CharRepeat = 1;
    for(k = 0; k < reps && x + k * tc <= cols; k++) {
        for(r = 0; r < tr && y + r <= rows; r++) {
            CursorPosition(x + k * tc, y + r);
            p = &Tiles[(n * tc * tr) + r * tc];
            for(c = 0; c < tc && x + k * tc + c <= cols; c++) VideoPutLiteral(p[c]);
        }
    }
    CharRepeat = save;
    CursorPosition(x + reps * tc, y);
    if(x + reps * tc > cols) { CursorX = cols * fontWidth * fontScale; SyncCharPos(); }   // just past the end of the line, like text
}


// codes 0x16 and 0x17.  Scroll the lines of the scrolling region (the whole screen if none has been set with ESC [ t ; b r) sideways.
// If the repeat count (bits 3-6 of the 18 attribute) is zero this is one character cell, otherwise it is that many pixels (1 to 15)
static void HorizScroll(int left) {
    int ch = fontHeight * fontScale;
    int first, last;

    if(ScrollTop || ScrollBot) {
        RegionLines(&first, &last);
        ScrollHorizPixels((first - 1) * ch, last * ch, CharRepeat ? CharRepeat : fontWidth * fontScale, left);
    } else
        ScrollHorizPixels(0, VRes, CharRepeat ? CharRepeat : fontWidth * fontScale, left);
}


// process one character in control code mode.  returns true if the character was used
static int CCChar(int c) {
    if(ccPending) {                                                 // this is a parameter for a previous code
        switch(ccPending) {
            case 0x02: ShowCursor(false);
                       if(c == 0) CursorOff = true; else { CursorOff = false; CursorChar = c; }
                       break;
            case 0x05:
            case 0x06: if(!ccHave) { ccArg = c; ccHave = true; return true; }
                       GfxPixel(ccArg, c, ccPending == 0x05);
                       break;
            case 0x0e: CursorPosition(c + 1, CharPosY); break;
            case 0x0f: CursorPosition(CharPosX, c + 1); break;
            case 0x18: CCAttribute(c); break;
            case 0x1a: VideoPutLiteral(c); break;
            case 0x0b: SendTile(c); break;
            case 0x1c: if(SprFeed(c)) return true; break;                // sprite layer commands (see SpriteLayer.h)
            case 0x19: if(ccHave == 0) { ccArg = c; ccHave = 1; return true; }              // SET TILE n columns rows data...  first the slot
                       if(ccHave == 1) { ccCols = c; ccHave = 2; return true; }                   // then the number of columns
                       if(ccHave == 2) {                                                          // then the number of rows
                           ccTotal = ccCols * c;
                           ccBase = 0xffff;                                                       // data for a bad tile is read and thrown away
                           if(ccTotal != 0 && ccArg < TILE_MAX_SLOTS && (ccArg + 1) * ccTotal <= TILE_POOL_BYTES) {
                               ccBase = ccArg * ccTotal;
                               TileCols[ccArg] = ccCols; TileRows[ccArg] = c;
                           }
                           if(ccTotal == 0) break;                                                // nothing to follow
                           ccHave = 3; ccCount = 0;
                           return true;
                       }
                       if(ccBase != 0xffff) Tiles[ccBase + ccCount] = c;
                       if(++ccCount < ccTotal) return true;                                       // keep going until we have them all
                       break;
        }
        ccPending = 0;
        ccHave = false;
        return true;
    }

    if(vtcnt != 0) return false;                                    // part way through an escape sequence so leave it to the normal decoder

    switch(c) {
        case 0x01: CursorPosition(1, 1); return true;
        case 0x03: ShowCursor(false); CursorBlink = true; return true;
        case 0x04: ShowCursor(false); CursorBlink = false; return true;
        case 0x02: case 0x05: case 0x06: case 0x0b: case 0x0e: case 0x0f: case 0x18: case 0x19: case 0x1a: case 0x1c:
                   if(c == 0x1c) SprStart();
                   ccPending = c; ccHave = false; return true;      // these need one or two following bytes
        case 0x0c: ShowCursor(false); ClearScreen(); CursorPosition(1, 1); return true;
        case 0x10: cmd_ClearBOL(); return true;
        case 0x11: cmd_ClearEOL(); return true;
        case 0x12: cmd_ClearBOS(); return true;
        case 0x13: cmd_ClearEOS(); return true;
        case 0x14: ShowCursor(false); ScrollUp(); return true;
        case 0x15: ShowCursor(false); ScrollDown(); return true;
        case 0x16: HorizScroll(true); return true;
        case 0x17: HorizScroll(false); return true;
        case 0x1d: CursorPosition(CharPosX - 1, CharPosY); return true;
        case 0x1e: CursorPosition(CharPosX, CharPosY - 1); return true;
        case 0x1f: CursorPosition(CharPosX, CharPosY + 1); return true;
        case 0x7f: DeleteChars(1); return true;
    }
    return false;                                                   // everything else (including ESC) is handled in the normal way
}



/***************************************************************************************************************************************
 Process a character received from the host
***************************************************************************************************************************************/
void VT100Putc(int c) {
    int cmd, i, j, partial;

    c &= 0xff;
    if(Option[O_CTRLCODES] == O_CC_ON && !csiActive && CCChar(c)) return;
    if(csiActive) {                                                 // we are part way through a CSI sequence
        CSIChar(c);
        return;
    }
    if(mode == VT100 && c == '[' && vtcnt == 1 && vtbuf[0] == 0x1b) {  // ESC [ in VT100 mode is the start of a CSI sequence
        vtcnt = 0;
        CSIStart();
        return;
    }

    if(vtcnt >= VTBUF_SIZE) return;
    vtbuf[vtcnt++] = c;
    partial = false;

    while(vtcnt) {
        for(cmd = 0; cmd < CmdTblSize; cmd++) {
            if((cmdtbl[cmd].mode & mode) && *cmdtbl[cmd].name == *vtbuf) {   // check the mode then a quick check of the first char
                arg[0] = argc = 0;
                for(j = i = 1; cmdtbl[cmd].name[i] && j < vtcnt; i++, j++) {
                    if(cmdtbl[cmd].name[i] == '^') {
                        arg[argc++] = vtbuf[j] - 31;
                    } else if(cmdtbl[cmd].name[i] == '@') {
                        arg[argc] = 0;
                        while(isdigit(vtbuf[j]))
                            arg[argc] = arg[argc] * 10 + (vtbuf[j++] - '0');
                        j--;                                        // correct for the overshoot, so that the next loop looks at the next char
                        argc++;
                    } else if(cmdtbl[cmd].name[i] != vtbuf[j])
                            goto nextcmd;                           // compare failed, try the next command
                }
                if(cmdtbl[cmd].name[i] == 0) {                      // compare succeded, we have found the command
                    vtcnt = 0;                                      // clear all chars in the queue
                    cmdtbl[cmd].fptr();                             // and execute the command
                    return;
                } else
                    partial = true;                                 // partial compare so set a flag to indicate this
            }
            nextcmd:
            continue;
        }
        if(!partial) {                                              // we have searched the table and have not even found a partial match
            VideoPutc(*vtbuf);                                      // so send the oldest char off
            memcpy(vtbuf, vtbuf + 1, vtcnt--);                      // and shift down the table
        } else
            return;                                                 // have a partial match so keep the characters in the buffer
    }                                                               // keep looping until the buffer is empty
}



void initVT100(void) {
    mode = VT100;
    vtcnt = 0;
    csiActive = false;
    ccPending = 0;
    CmdTblSize =  (sizeof(cmdtbl)/sizeof(struct s_cmdtbl));
    SaveFontNbr = -1;
    CharSet[0] = CharSet[1] = CS_ASCII;
    ShiftOut = false;
    ScrollTop = ScrollBot = 0;
    ResetTabStops();
}
