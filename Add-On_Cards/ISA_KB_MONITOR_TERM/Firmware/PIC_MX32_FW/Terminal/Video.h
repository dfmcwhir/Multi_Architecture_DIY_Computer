/****************************************************************************************
 Video.h

	Header file for the video driver for the VT100 Terminal program


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

// Global variables provided by Video.c
extern int VRes, HRes;						    // Global vert and horiz resolution in pixels on the screen
extern int screenWidth, screenHeight;				    // Global vert and horiz resolution in the currently selected font
extern int VBuf, HBuf;						    // Global vert and horiz resolution of the video buffer
extern int CursorX, CursorY;
extern int CharPosX, CharPosY;
extern int MMCharPos;
extern int vga;							    // true if we are using the internal monochrome vga

extern int VideoBuf[];						    // video buffer

#define VCHARS (VRes / (fontHeight * fontScale))                    // number of lines in a screenfull

// Facilities provided by Video.c
extern void MMCursor(int b);
extern void ClearScreen(void);
extern void initVideo(void);
extern void initFont(int);
extern void plot(int x, int y, int b);
extern int CursorBlink;                                             // true if the cursor blinks
extern int CursorChar;                                              // the character used for the cursor or -1 for the standard underline
extern unsigned char CharRepeat;                                    // each printable character is drawn this many times (0 or 1 = once)
extern int MosaicMode;                                              // true if printable characters are drawn as 2x4 block graphics
extern void VideoPutLiteral(int c);                                 // draw a character even if it is a control code (0x01 - 0x1F shows PC symbols)
extern void GfxPixel(int x, int y, int on);                         // set or reset a pixel (units of 3x3 screen pixels)
extern void ScrollHorizPixels(int y0, int y1, int shift, int left);   // scroll pixel rows y0 to y1-1 sideways by shift pixels
extern void ScrollHoriz(int left);                                  // scroll the whole screen sideways by one character

extern int pixel(int x, int y);
extern void DrawLine(int x1, int y1, int x2, int y2, int colour) ;
extern void DrawCircle(int x, int y, int radius, int fill, int colour, float aspect) ;
extern void DrawBox(int x1, int y1, int x2, int y2, int fill, int colour);
extern void VideoPutc(int c);
extern void DisplayString(char *p);
extern void ScrollUp(void);
extern void ScrollDown(void);
extern void ShowCursor(int show);
extern void ConfigBuffers(int lines24);
extern int AutoLineWrap;                                            // true if auto line wrap is on
extern int Display24Lines;                                          // true if displaying 24 lines

#define CONFIG_PAL		0b111                               // PAL is the default for the Maximite
#define CONFIG_NTSC		0b001
#define CONFIG_DISABLED         0b010
extern const unsigned int PalVgaOption;

// define the blink rate for the cursor
extern int CursorOff;
extern volatile int CursorTimer;
#define CURSOR_OFF		350											// cursor off time in mS
#define CURSOR_ON		650											// cursor on time in mS

// cursor definition
typedef enum {C_OFF = 0, C_STANDARD, C_INSERT } Cursor_e ;
extern Cursor_e Cursor;
extern int AutoLineWrap;		// true if auto line wrap is on
extern int PrintPixelMode;      // global used to track the pixel mode when we are printing

// the font table and the current height and width of the font
extern int fontNbr;

// details of the current font
extern unsigned int *fontPtr;                                              // pointer to a font using 32 bit words
extern int fontWidth;
extern int fontHeight;
extern int fontStart;
extern int fontEnd;
extern int fontScale;

// ---------------------------------------------------------------------------------------------
// Additions for extended characters, character sets, scrolling regions and insert/delete
// ---------------------------------------------------------------------------------------------

// character sets that can be designated as G0 or G1 (ESC ( x and ESC ) x) and selected with SI/SO
#define CS_ASCII        0                                           // US ASCII
#define CS_DEC          1                                           // DEC special graphics (line drawing) ESC ( 0
#define CS_UK           2                                           // UK, the # character is shown as a pound sign
extern int CharSet[2];                                              // the character sets designated as G0 and G1
extern int ShiftOut;                                                // true if G1 is active (SO), false if G0 is active (SI)

// the scrolling region.  these are text line numbers (1 = top of the screen), zero means the full screen
extern int ScrollTop, ScrollBot;

extern int pixel(int x, int y);
extern void IndexDown(void);                                        // move down one line, scrolling the region if needed
extern void ReverseIndex(void);                                     // move up one line, scrolling the region if needed
extern void ScrollArea(int topLine, int botLine, int n);            // scroll text lines topLine to botLine by n lines (up if n > 0)
extern void InsertChars(int n);                                     // insert n blank characters at the cursor
extern void DeleteChars(int n);                                     // delete n characters at the cursor
extern void EraseChars(int n);                                      // blank n characters at the cursor
extern void SetTabStop(void);                                       // set a tab stop at the cursor
extern void ClearTabStop(int all);                                  // clear the tab stop at the cursor (or all of them)
extern void ResetTabStops(void);                                    // set a tab stop every 8 columns
extern void TabForward(int n);                                      // move forward n tab stops
extern int TextCols(void);                                          // number of text columns in the current font
extern int TextRows(void);                                          // number of text rows in the current font

// The sprite layer (SpriteLayer.h, which is part of Video.c)
extern int SprOn, SprDepth;                                         // SprOn is true if any sprite is showing
extern void SprBeginOp(int x0, int y0, int x1, int y1);             // the drawing code is about to change these screen pixels (x1 and y1 are not included)
extern void SprEndOp(void);                                         // and it has finished
extern void SprScreenCleared(void);                                 // the screen has been cleared
extern void SprStart(void);                                         // control code 0x1C has arrived
extern void SprSync(int y0, int y1);                                // if a sprite is showing on pixel rows y0 to y1-1 wait for the start of the vertical blank (gives up after about a frame)
extern void SprHShift(int y, int sigma);                            // a sideways scroll of the sprite row starting at pixel row y by sigma pixels (negative for right) has been done
extern void SprVShift(int top, int bot, int dy);                    // the pixel rows top to bot-1 have been scrolled up (dy > 0) or down
extern int SprFeed(int c);                                          // the next byte after control code 0x1C.  Returns true if more bytes are needed
#define SPR_BEGIN(x0, y0, x1, y1)   do { if(SprOn) SprBeginOp((x0), (y0), (x1), (y1)); } while(0)
#define SPR_END()                   do { if(SprDepth) SprEndOp(); } while(0)
#define SPR_SYNC(y0, y1)            do { if(SprOn) SprSync((y0), (y1)); } while(0)
#define SPR_HSHIFT(y, sigma)        do { if(SprDepth) SprHShift((y), (sigma)); } while(0)
#define SPR_VSHIFT(top, bot, dy)    do { if(SprOn) SprVShift((top), (bot), (dy)); } while(0)
