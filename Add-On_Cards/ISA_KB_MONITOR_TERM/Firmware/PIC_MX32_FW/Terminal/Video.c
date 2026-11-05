/****************************************************************************************
 Video.c

	Video driver for the VT100 Terminal program


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



#define _SUPPRESS_PLIB_WARNING

#include <p32xxxx.h>
#include <plib.h>
#include <string.h>
#include "Terminal.h"
#include "video.h"
#include "Fonts.h"
#include "FontsExt.h"
#include "vt100.h"

/*   The video generator is based on an idea and code by Lucio Di Jasio presented in his excellent book
     "Programming 32-bit Microcontrollers in C - Exploring the PIC32".
*/

// Parameters for VGA video with 31.5KHz horizontal scanning and 60Hz vertical refresh
// When using 36 lines we have 480x432 pixels.  This gives us 80 chars per line and 36 lines per screen
// When using 24 lines these values are changed in ConfigBuffers()
#define VGA_VRES	 	432                                         // Vert graphics resolution (pixels)
#define VGA_HRES	 	480                                         // Horiz graphics resolution (pixels)
#define VGA_H_OFFSET    5                                           // Number of blank pixels at the start of a line (horiz position)
#define VGA_HBUFF	 	((VGA_HRES + VGA_H_OFFSET + 31)/32)         // Number of words of memory to allocate for a horiz line
#define VGA_LINE_N   	525                                         // number of lines in VGA frame
#define VGA_LINE_T   	1270                                        // Tpb clock in a line (31.777us)
#define VGA_VSYNC_N  	2                                           // V sync lines
#define VGA_VBLANK_N 	(VGA_LINE_N - VGA_VRES - VGA_VSYNC_N)       // Nbr of blank lines
#define VGA_PREEQ_N  	((VGA_VBLANK_N/2) - 12)                     // Nbr blank lines at the bottom of the screen
#define VGA_POSTEQ_N 	VGA_VBLANK_N - VGA_PREEQ_N                  // Nbr blank lines at the top of the screen
#define VGA_PIX_T    	2                                           // Tpb clock per pixel
#define VGA_HSYNC_T  	152                                         // Tpb clock width horizontal pulse

// Common parameters for Composite video
#define C_PIX_T      	4                                           // Tpb clock per pixel
#define C_HSYNC_T    	187        									// Tpb clock width horizontal pulse
#define C_BLANKPAD   	8											// number of zero words (4 bytes each) before sending data
#define C_VSYNC_N    	3          									// V sync lines
#define C_H_OFFSET      8                                           // Number of blank pixels at the start of a line (horiz position)

// Parameters for PAL composite video
// Graphics is 388x216 pixels.  This gives us 48 chars per line and 18 lines per screen
#define PAL_VRES	    216											// Vert graphics resolution (pixels)
#define PAL_HRES	    288 										// Horiz graphics resolution (pixels)
//#define PAL_HBUFF	 	((PAL_HRES + C_H_OFFSET + 31)/32)           // Number of words of memory to allocate for a horiz line
#define PAL_HBUFF	 	((PAL_HRES + C_H_OFFSET + PAL_HRES/2 + C_H_OFFSET/2 + 31)/32)           // Number of words of memory to allocate for a horiz line
#define PAL_LINE_N     	312        									// number of lines in PAL frames
#define PAL_LINE_T     	2560       									// Tpb clock in a line (64us) 5115 //
#define PAL_VBLANK_N   	(PAL_LINE_N - PAL_VRES - C_VSYNC_N)  		// Nbr of blank lines
#define PAL_PREEQ_N    	((PAL_VBLANK_N/2) - 8)         				// Nbr blank lines at the bottom of the screen
#define PAL_POSTEQ_N   	(PAL_VBLANK_N - PAL_PREEQ_N)  				// Nbr blank lines at the top of the screen

// Parameters for NTSC composite video
// Graphics is 388x180 pixels.  This gives us 48 chars per line and 15 lines per screen
#define NTSC_VRES     	180											// Vert graphics resolution (pixels)
#define NTSC_HRES	    264											// Horiz graphics resolution (pixels)
#define NTSC_HBUFF	 	((NTSC_HRES + C_H_OFFSET + NTSC_HRES/2 + C_H_OFFSET/2 + 31)/32)          // Number of words of memory to allocate for a horiz line
#define NTSC_LINE_N     262	        								// number of lines in NTSC frames
#define NTSC_LINE_T     2540       									// Tpb clock in a line (63.55us)
#define NTSC_VBLANK_N   (NTSC_LINE_N - NTSC_VRES - C_VSYNC_N)  		// Nbr of blank lines
#define NTSC_PREEQ_N    ((NTSC_VBLANK_N/2) - 8)         			// Nbr blank lines at the bottom of the screen
#define NTSC_POSTEQ_N   (NTSC_VBLANK_N - NTSC_PREEQ_N)  			// Nbr blank lines at the top of the screen


// states of the vertical sync state machine
#define SV_PREEQ    0												// generating blank lines before the vert sync
#define SV_SYNC     1												// generating the vert sync
#define SV_POSTEQ   2												// generating blank lines after the vert sync
#define SV_LINE     3												// visible lines, send the video data out

// define the video buffer
// note that this can differ from the pixel resolution, for example for composite HRes is not an even multiple of 32 where HBuf is
int VBuf, HBuf;														// Global vert and horiz resolution of the video buffer
int VRes, HRes;														// Global vert and horiz resolution in pixels on the screen

// allocate the video buffer, the last part of this is also used for the serial Rx buffer
// simply use as much memory as we can
int VideoBuf[BUFFER_SIZE/4];

#if ((ALLOW_36_LINES ? VGA_VRES : (VGA_VRES / 3) * 2) * VGA_HBUFF * 4) + 4 > BUFFER_SIZE
    #error Not enough memory allocated
#endif

int vga;															// true if we are using the internal VGA video
unsigned int SvSyncT;												// used to determine the timing for the SV_SYNC state;

// the state machine is used to keep track of what part of the video frame we are generating (vert sysch, post equ, etc)
int VS[4] = { SV_SYNC, SV_POSTEQ, SV_LINE, SV_PREEQ };				// the next state table
int VC[4];															// the next counter table (initialise in initVideo() below)
volatile int VCount;												// counter for the number of lines in a frame
volatile unsigned int VFrame;                                       // counts the frames: it goes up when the visible lines end (the vertical blank starts)
volatile int VState;												// the state of the state machine

const int zero[] = {0, 0, 0, 0, 0, 0, 0, 0};                        // 32 bytes of zero used to pad the start of composite video

const unsigned int PalVgaOption = 0xffffffff;					    // use to hold the pal/vga setting in flash

// these keep track of where the next char will be written
int CursorX, CursorY;												// position in pixels (home is 0, 0)
int CharPosX, CharPosY;												// position in characters (home is 1, 1)
int AutoLineWrap;													// global used to track if we want automatic line wrap
int Display24Lines;                                                 // true if we are displaying 24 lines

// the font table and the current height and width of the font
int fontNbr;

// details of the current font
unsigned int *fontPtr;                                              // pointer to a font using 32 bit words
int fontWidth;
int fontHeight;
int fontStart;
int fontEnd;
int fontScale;

// the extra glyph tables that go with the current font (see FontsExt.h), each glyph is fontWidth words
static const unsigned char *fontExt437;                             // IBM code page 437, chars 0x80 - 0xFF (see FontsExt.h, the glyphs are packed)
static const unsigned char *fontExtC0;                              // the PC glyphs for codes 0x01 - 0x1F
static const unsigned char *fontExtDEC;                             // DEC special graphics, chars 0x5F - 0x7E
static int fontExtBytes, fontExtBits;                               // the bytes in a packed glyph and the bits in each pixel column of one
static unsigned int GlyphBuf[13];                                   // a glyph from the packed tables after it has been unpacked

int CharSet[2];                                                     // the character sets designated as G0 and G1
int ShiftOut;                                                       // true if G1 is the active character set
int CursorBlink = true;                                             // true if the cursor blinks, false if it is solid
int CursorChar = -1;                                                // the character used for the cursor or -1 for the standard underline
unsigned char CharRepeat = 0;                                       // each printable character is drawn this many times (0 or 1 = once)
int MosaicMode = false;                                             // true if characters are drawn as 2x4 block graphics
static int ForceChar = false;                                       // true if the next character must be drawn rather than acted on as a control char
static void DrawLineRaw(int x1, int y1, int x2, int y2, int colour);   // a line with no regard for sprites (used for the cursor)
int ScrollTop, ScrollBot;                                           // scrolling region (text lines), zero = full screen


/**************************************************************************************************
Initialise the video components
***************************************************************************************************/
void initVideo(void) {

    AutoLineWrap = 1;

    // test if there is a monitor plugged into the VGA connector
    CNPUASET = (1 << 4);                                            // set a pullup on the video output pin
    uSec(300);                                                      // allow it to settle
    vga = !PORTAbits.RA4;                                           // the pin will be pulled low if the monitor is there
    CNPUACLR = (1 << 4);

    ////////////////////////////
    // setup SPI2 which is the video generator.  the output of this module is a stream of bits which are the pixels in a horiz scan line
    if(vga)
        PPSOutput(3, RPA4, SDO2);                                   // B5 is the video out for VGA
    else
        PPSOutput(3, RPB2, SDO2);                                   // B2 is the video out for composite
    PPSInput(4, SS2, RPB9);                                         // B9 is the framing input
    #define P_VIDEO_SPI         2                                   // the SPI peripheral used for video
    #define P_SPI_INPUT         SPI2BUF                             // input buffer for the SPI peripheral
    #define P_SPI_INTERRUPT     _SPI2_TX_IRQ                        // interrupt used by the SPI peripheral when it needs more data

    ////////////////////////////
    // the horizontal sync uses Timer 3 and Output Compare 3 to generate the pulse and interrupt level 7
    PPSOutput(4, RPB14, OC3);                                       // B14 is the horizontal sync output (ie, the output from OC3)
    #define P_VID_OC_OPEN       OpenOC3                             // the function used to open the output compare
    #define P_VID_OC_REG        OC3R                                // the output compare register

    ////////////////////////////
    // the vertical sync uses B13
    TRISBCLR = (1<<13);                                             // Vert sync output used by VGA
    #define P_VERT_SET_HI		LATBSET = (1 << 13)                 // set vert sync hi
    #define P_VERT_SET_LO		LATBCLR = (1 << 13)                 // set vert sync lo

    // calculate the paramaters for each video mode and setup Timer 3 to generate the horiz synch and interrupt on its leading edge
    if(vga) {
        // set up for VGA output
	    HRes = VGA_HRES;                                            // HRes is the number of horiz pixels to use
	    HBuf = VGA_HBUFF * 32;                                      // HBuf is the horiz buffer size (in pixels)
        ConfigBuffers(Option[O_LINES24]);                           // setup the buffer pointers and VBuf, VRes
		VC[0] = VGA_VSYNC_N;										// setup the table used to count lines
		VC[1] = VGA_POSTEQ_N;
	    P_VID_OC_OPEN(OC_ON | OC_TIMER3_SRC | OC_CONTINUE_PULSE, 0, VGA_HSYNC_T);	// enable the output compare which is used to time the width of the horiz sync pulse
	    OpenTimer3( T3_ON | T3_PS_1_1 | T3_SOURCE_INT, VGA_LINE_T-1);	            // enable timer 3 and set to the horizontal scanning frequency
	}
    else if(Option[O_PAL]) {
		// this is for the PAL composite output and is the same as VGA with timing differences
	    VBuf = VRes = PAL_VRES;
	    HRes = PAL_HRES;
	    HBuf = PAL_HBUFF * 32;                                      // HBuf is the horiz buffer size (in pixels)
        ConfigBuffers(0);
	    SvSyncT = PAL_LINE_T - C_HSYNC_T;
		VC[0] = C_VSYNC_N;
		VC[1] = PAL_POSTEQ_N;
		VC[2] = PAL_VRES;
		VC[3] = PAL_PREEQ_N;
	    P_VID_OC_OPEN(OC_ON | OC_TIMER3_SRC | OC_CONTINUE_PULSE, 0, C_HSYNC_T);	    // enable the output compare which is used to time the width of the horiz sync pulse
	    OpenTimer3(T3_ON | T3_PS_1_1 | T3_SOURCE_INT, PAL_LINE_T-1);	            // enable timer 3 and set to the horizontal scanning frequency
    }
	else {
		// this is for the NTSC composite output and is similar again
	    VBuf = VRes = NTSC_VRES;
	    HRes = NTSC_HRES;
	    HBuf = NTSC_HBUFF * 32;                                     // HBuf is the horiz buffer size (in pixels)
        ConfigBuffers(0);
	    SvSyncT = NTSC_LINE_T - C_HSYNC_T;
		VC[0] = C_VSYNC_N;
		VC[1] = NTSC_POSTEQ_N;
		VC[2] = NTSC_VRES;
		VC[3] = NTSC_PREEQ_N;
	    P_VID_OC_OPEN(OC_ON | OC_TIMER3_SRC | OC_CONTINUE_PULSE, 0, C_HSYNC_T);	    // enable the output compare which is used to time the width of the horiz sync pulse
	    OpenTimer3(T3_ON | T3_PS_1_1 | T3_SOURCE_INT, NTSC_LINE_T-1);	            // enable timer 3 and set to the horizontal scanning frequency
	}

    // set priority level 7 for the timer 3 interrupt (horiz synch) and enable it
    mT3SetIntPriority(7);
    mT3IntEnable(1);

    // initialise the state machine and set the count so that the first interrupt will increment the state
	VState = SV_PREEQ;
    VCount = 1;

    // setup the SPI channel then DMA channel which will copy the memory bitmap buffer to the SPI channel
    if(vga) {
        // open the SPI in framing mode.  Note that SPI_OPEN_DISSDI will disable the input (which we do not need)
	    SpiChnOpen(P_VIDEO_SPI, SPICON_ON | SPICON_MSTEN | SPICON_MODE32 | SPICON_FRMEN | SPICON_FRMSYNC | SPICON_FRMPOL | SPI_OPEN_DISSDI, VGA_PIX_T);
        SPI2CON2 = (1<<9) | (1<<8);                                         // instruct the SPI module to ignore any errors that might occur
        DmaChnOpen(1, 1, DMA_OPEN_DEFAULT);                                 // setup DMA 1 to send data to SPI channel 2
        DmaChnSetEventControl(1, DMA_EV_START_IRQ_EN | DMA_EV_START_IRQ(P_SPI_INTERRUPT));
	    DmaChnSetTxfer(1, (void*)VideoBuf, (void *)&P_SPI_INPUT, HBuf/8, 4, 4);
    } else {
	    SpiChnOpen(P_VIDEO_SPI, SPICON_ON | SPICON_MSTEN | SPICON_MODE32 | SPICON_FRMEN | SPICON_FRMSYNC | SPICON_FRMPOL | SPI_OPEN_DISSDI, C_PIX_T);
        SPI2CON2 = (1<<9) | (1<<8);                                         // instruct the SPI module to ignore any errors that might occur
        DmaChnOpen(1, 1, DMA_OPEN_DEFAULT);    	                            // setup DMA 1 is the blank padding at the start of a scan line
        DmaChnSetEventControl(1, DMA_EV_START_IRQ_EN | DMA_EV_START_IRQ(P_SPI_INTERRUPT));
	    DmaChnSetTxfer(1, (void*)zero, (void *)&P_SPI_INPUT, C_BLANKPAD, 4, 4);
    	DmaChnOpen( 0, 0, DMA_OPEN_DEFAULT);		                        // setup DMA 0 to pump the data from the graphics buffer to the SPI peripheral
    	DmaChnSetEventControl(0, DMA_EV_START_IRQ_EN | DMA_EV_START_IRQ(P_SPI_INTERRUPT));
	    DmaChnSetTxfer(0, (void*)VideoBuf, (void *)&P_SPI_INPUT, HBuf/8 + 6, 4, 4);
    	DmaChnSetControlFlags(0, DMA_CTL_CHAIN_EN | DMA_CTL_CHAIN_DIR);    	// chain DMA 0 so that it will start on completion of the DMA 1 transfer
    }
}


void ConfigBuffers(int lines24) {
#if !ALLOW_36_LINES
    lines24 = true;                                                 // 36 lines is not supported in this build
#endif
    if(vga) {
        Display24Lines = lines24;                                   // set the 24 line flag
        if(lines24) {                                               // and adjust the vertical paramaters accordingly
            VBuf = VRes = (VGA_VRES / 3) * 2;
            VC[2] = VGA_VRES - 1;
            VC[3] = VGA_PREEQ_N + 1;
        } else {
            VBuf = VRes = VGA_VRES;
            VC[2] = VGA_VRES;
            VC[3] = VGA_PREEQ_N;
        }
    } else {
        Display24Lines = false;                                     // composite cannot have 24 lines
    }
    SerialRxBuf = (char *)&VideoBuf[(VBuf * HBuf)/32];              // this is the end of the area used for video
    RxBufferSize = BUFFER_SIZE - ((VBuf * HBuf)/8) - 4;             // we take what is left for the Rx buffer (-4 is to allow for word/byte alignment)
    SerialRxBufHead = 0;
    SerialRxBufTail = 0;
    RxDropped = 0;
    RxPeak = 0;
    USBSerialRxBufTail = 0;
}


/**************************************************************************************************
Timer 3 interrupt.
Used to generate the horiz and vert sync pulse under control of the state machine
***************************************************************************************************/
void __ISR(_TIMER_3_VECTOR, IPL7SOFT) T3Interrupt(void) {
    static int *VPtr;
    static unsigned char AlternateField = 0;                        // used to count odd/even fields in composite video
    static unsigned int LineCnt = 1;

    switch ( VState) {    											// vertical state machine
        case SV_PREEQ:  // 0            							// prepare for the new horizontal line
            VPtr = VideoBuf;
            LineCnt = 1;
            break;

        case SV_SYNC:   // 1
            if(!vga) {                                              // if the video is composite
                P_VID_OC_REG = SvSyncT;                             // start the vertical sync pulse for composite
            	VCount += AlternateField;                           // in composite video the alternative field has one extra line
            	AlternateField ^= 1;
            }
            P_VERT_SET_LO;										    // start the vertical sync pulse for vga
            break;

        case SV_POSTEQ: // 2
        	if(!vga) P_VID_OC_REG = C_HSYNC_T; 			            // end of the vertical sync pulse for composite
            P_VERT_SET_HI;                                          // end of the vertical sync pulse for vga
            break;

        case SV_LINE:   // 3
            P_SPI_INPUT = 0;                                        // preload the SPI with 4 zero bytes to pad the start of the video
            if(vga)
                DCH1SSA = KVA_TO_PA((void*) (VPtr));                // update the DMA1 source address (DMA1 is used for VGA data)
            else
                DCH0SSA = KVA_TO_PA((void*) (VPtr - 1));            // update the DMA0 source address (DMA0 is used for composite data)
            if(!Display24Lines || LineCnt++ % 3) VPtr += HBuf/32;   // move the pointer to the start of the next line
            DmaChnEnable(1);                                        // arm the DMA transfer
            break;
   }

    if (--VCount == 0) {											// count down the number of lines
        if(VState == SV_LINE) VFrame++;                             // the visible lines are over
        VCount = VC[VState&3];										// set the new count
        VState = VS[VState&3];    									// and advance the state machine
    }

    mT3ClearIntFlag();    											// clear the interrupt flag
}



/**************************************************************************************************
Turn on or off a single pixel in the graphics buffer
***************************************************************************************************/
void plot(int x, int y, int b) {
    int t;
    if(x >= 0 && x < HRes && y >= 0 && y < VRes) {
        if(vga)
            x += VGA_H_OFFSET;                                                      // this positions the start of the video
        else {
            // for composite video we need to duplicate every second pixel to get the aspect correct ratio
            // this means that we must multiple the x cordinate by 1.5
            // but that leaves gaps in the pixels so we need to figure out if there will be a gap and, if so,
            // turn on a second pixel to fill in the gap
            t = ((x << 1) + x) >> 1;                                                // multiply by 1.5
            if(((((x + 1) << 1) + (x + 1)) >> 1) - t > 1) {                         // will there be a gap?
                x = t + C_H_OFFSET + 1;                                             // this positions the start of the video
                if(b == 0)
                    VideoBuf[y * (HBuf/32) + x/32] &= ~(0x80000000>>(x & 0x1f));   	// turn off the pixel
                else if(b == -1)
                    VideoBuf[y * (HBuf/32) + x/32] ^= (0x80000000>>(x & 0x1f));		// invert the pixel
                else
                    VideoBuf[y * (HBuf/32) + x/32] |= (0x80000000>>(x & 0x1f));		// turn on the pixel
            }
            // if there is no gap we can proceed normally
            x = t + C_H_OFFSET;                                                     // this positions the start of the video
        }

      	if(b == 0)
            VideoBuf[y * (HBuf/32) + x/32] &= ~(0x80000000>>(x & 0x1f));   		    // turn off the pixel
        else if(b == -1)
        	VideoBuf[y * (HBuf/32) + x/32] ^= (0x80000000>>(x& 0x1f));			    // invert the pixel
        else
    	    VideoBuf[y * (HBuf/32) + x/32] |= (0x80000000>>(x & 0x1f));			    // turn on the pixel
    }
}



/**************************************************************************************************
scroll the screen
***************************************************************************************************/
// work out the scrolling region in pixels (bot is the first pixel row below the region)
static void Region(int *top, int *bot) {
    int ch = fontHeight * fontScale;
    *top = ScrollTop ? (ScrollTop - 1) * ch : 0;
    *bot = ScrollBot ? ScrollBot * ch : VRes;
    if(*bot > VRes) *bot = VRes;
    if(*top >= *bot) { *top = 0; *bot = VRes; }                     // the region is not valid (for example after a font change)
}


// scroll the pixel rows top to bot-1.  dy > 0 scrolls up and dy < 0 scrolls down, the rows vacated are cleared
static void ScrollRegion(int top, int bot, int dy) {
    int pw = HBuf / 32;                                             // words in a pixel row
    int h = bot - top;
    int d = dy < 0 ? -dy : dy;
    int *p = VideoBuf + top * pw;

    if(h <= 0 || d == 0) return;
    ShowCursor(false);                                              // turn off the cursor so that it is not scrolled with the text
    if(d > h) d = h;
    SPR_SYNC(top, bot);                                             // with sprites showing do all of this in the vertical blank if we can
    SPR_BEGIN(0, top, HRes, bot);
    SPR_VSHIFT(top, bot, dy < 0 ? -d : d);
    if(d < h) {
        if(dy > 0)
            memmove(p, p + d * pw, (h - d) * pw * sizeof(int));     // scroll up
        else
            memmove(p + d * pw, p, (h - d) * pw * sizeof(int));     // scroll down
    }
    if(dy > 0)
        memset(p + (h - d) * pw, 0, d * pw * sizeof(int));          // clear the new lines at the bottom
    else
        memset(p, 0, d * pw * sizeof(int));                         // or at the top
    SPR_END();
}


// scroll the scrolling region up by one text line
void ScrollUp(void) {
    int top, bot;
    Region(&top, &bot);
    ScrollRegion(top, bot, fontHeight * fontScale);
}


// scroll the scrolling region down by one text line
void ScrollDown(void) {
    int top, bot;
    Region(&top, &bot);
    ScrollRegion(top, bot, -(fontHeight * fontScale));
}


// scroll the text lines topLine to botLine (1 is the top line) by n lines.  Up if n is positive and down if negative
void ScrollArea(int topLine, int botLine, int n) {
    int ch = fontHeight * fontScale;
    int top = (topLine - 1) * ch;
    int bot = botLine * ch;
    if(top < 0) top = 0;
    if(bot > VRes) bot = VRes;
    if(n == 0 || bot <= top) return;
    ScrollRegion(top, bot, n * ch);
}


// move the cursor down one line.  If it is on the bottom line of the scrolling region the region is scrolled instead
void IndexDown(void) {
    int ch = fontHeight * fontScale;
    int top, bot, inside;

    Region(&top, &bot);
    inside = (CursorY >= top && (ScrollBot == 0 || CursorY < bot));
    if(inside && CursorY + 2 * ch > bot + 1) {
        ScrollRegion(top, bot, ch);
        if(CursorY + ch > bot + 1) CursorY = (bot / ch - 1) * ch;   // the cursor was beyond the last line so put it back on it
    } else if(CursorY + 2 * ch <= VRes + 1)
        CursorY += ch;
    CharPosY = (CursorY / ch) + 1;
}


// move the cursor up one line.  If it is on the top line of the scrolling region the region is scrolled instead
void ReverseIndex(void) {
    int ch = fontHeight * fontScale;
    int top, bot;

    ShowCursor(false);
    Region(&top, &bot);
    if(CursorY >= top && CursorY < top + ch)
        ScrollRegion(top, bot, -ch);
    else if(CursorY >= ch)
        CursorY -= ch;
    CharPosY = (CursorY / ch) + 1;
}


int TextCols(void) { return HRes / (fontWidth * fontScale); }
int TextRows(void) { return VRes / (fontHeight * fontScale); }



/**************************************************************************************************
Read a pixel from the graphics buffer.  This is the inverse of plot() and returns 0 or 1
***************************************************************************************************/
int pixel(int x, int y) {
    if(x < 0 || x >= HRes || y < 0 || y >= VRes) return 0;
    if(vga)
        x += VGA_H_OFFSET;
    else
        x = (((x << 1) + x) >> 1) + C_H_OFFSET;                     // the same mapping as used by plot() for composite video
    return (((unsigned int)VideoBuf[y * (HBuf/32) + x/32]) >> (31 - (x & 0x1f))) & 1;
}



/**************************************************************************************************
Insert, delete and erase characters on the current line.  These work on the pixels as the screen
does not keep a copy of the text.
***************************************************************************************************/
void InsertChars(int n) {
    int cw = fontWidth * fontScale, ch = fontHeight * fontScale;
    int x, y, shift;

    ShowCursor(false);
    if(n < 1) n = 1;
    if(n > HRes / cw) n = HRes / cw;
    shift = n * cw;
    SPR_BEGIN(CursorX, CursorY, HRes, CursorY + ch);
    for(y = CursorY; y < CursorY + ch; y++) {
        for(x = HRes - 1; x >= CursorX + shift; x--) plot(x, y, pixel(x - shift, y));
        for(x = CursorX; x < CursorX + shift && x < HRes; x++) plot(x, y, 0);
    }
    SPR_END();
}


void DeleteChars(int n) {
    int cw = fontWidth * fontScale, ch = fontHeight * fontScale;
    int x, y, shift;

    ShowCursor(false);
    if(n < 1) n = 1;
    if(n > HRes / cw) n = HRes / cw;
    shift = n * cw;
    SPR_BEGIN(CursorX, CursorY, HRes, CursorY + ch);
    for(y = CursorY; y < CursorY + ch; y++)
        for(x = CursorX; x < HRes; x++)
            plot(x, y, (x + shift < HRes) ? pixel(x + shift, y) : 0);
    SPR_END();
}


void EraseChars(int n) {
    int cw = fontWidth * fontScale, ch = fontHeight * fontScale;
    int x, y, xend;

    ShowCursor(false);
    if(n < 1) n = 1;
    xend = CursorX + n * cw;
    if(xend > HRes || xend < CursorX) xend = HRes;
    SPR_BEGIN(CursorX, CursorY, xend, CursorY + ch);
    for(y = CursorY; y < CursorY + ch; y++)
        for(x = CursorX; x < xend; x++) plot(x, y, 0);
    SPR_END();
}



/**************************************************************************************************
Tab stops.  There is one flag for each column (the first column is zero)
***************************************************************************************************/
#define MAX_TABS    96                                              // widest possible line is 80 columns
static unsigned char TabStops[MAX_TABS / 8];                        // one bit per column (saves RAM)
#define TAB_GET(c)  ((TabStops[(c) >> 3] >> ((c) & 7)) & 1)
#define TAB_SET(c)  (TabStops[(c) >> 3] |= (unsigned char)(1 << ((c) & 7)))
#define TAB_CLR(c)  (TabStops[(c) >> 3] &= (unsigned char)~(1 << ((c) & 7)))

void ResetTabStops(void) {
    int i;
    for(i = 0; i < MAX_TABS; i++) { if(i != 0 && (i % 8) == 0) TAB_SET(i); else TAB_CLR(i); }
}


void SetTabStop(void) {
    int col = CursorX / (fontWidth * fontScale);
    if(col >= 0 && col < MAX_TABS) TAB_SET(col);
}


void ClearTabStop(int all) {
    int i, col = CursorX / (fontWidth * fontScale);
    if(all)
        for(i = 0; i < MAX_TABS / 8; i++) TabStops[i] = 0;
    else if(col >= 0 && col < MAX_TABS)
        TAB_CLR(col);
}


void TabForward(int n) {
    int cw = fontWidth * fontScale;
    int col = CursorX / cw;
    int last = TextCols() - 1;

    while(n-- > 0) {
        col++;
        while(col < last && !(col < MAX_TABS && TAB_GET(col))) col++;
        if(col > last) col = last;
    }
    CursorX = col * cw;
}



/**************************************************************************************************
clear the screen
***************************************************************************************************/
void ClearScreen(void) {
    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
	memset(VideoBuf, 0, VBuf*(HBuf/8));
    SprScreenCleared();                                             // any sprites are hidden
}



// Find the glyph for a character code taking into account the character sets in use.  returns NULL if it cannot be displayed
// A glyph is fontWidth words, one for each pixel column with bit 0 being the top row
// unpack glyph n of one of the extended tables into GlyphBuf (the same format as the glyphs in Fonts.h)
static const unsigned int *Unpack(const unsigned char *table, int n) {
    const unsigned char *p = table + n * fontExtBytes;
    unsigned int acc = 0;
    int j, have = 0;
    for(j = 0; j < fontWidth; j++) {
        while(have < fontExtBits) { acc = (acc << 8) | *p++; have += 8; }
        have -= fontExtBits;
        GlyphBuf[j] = (acc >> have) & ((1u << fontExtBits) - 1);
        acc &= (1u << have) - 1;
    }
    return GlyphBuf;
}


static const unsigned int *FindGlyph(int c) {
    if(c >= ' ' && c <= '~') {
        int set = CharSet[ShiftOut ? 1 : 0];
        if(set == CS_DEC && c >= 0x5f) return Unpack(fontExtDEC, c - 0x5f);
        if(set == CS_UK && c == '#') return Unpack(fontExt437, 0x9c - 0x80);     // the pound sign is 0x9C in CP437
        return fontPtr + (c - ' ') * fontWidth;
    }
    if(c >= 0x80) {
        if(Option[O_EXTCHARS] == O_EXT_OFF) return NULL;
        return Unpack(fontExt437, c - 0x80);
    }
    return NULL;
}


// as for FindGlyph() but codes 0x01 - 0x1F show the PC (DOS) symbols.  Used for the cursor and for literal characters
static const unsigned int *FindGlyphLit(int c) {
    if(c >= 1 && c <= 31) return Unpack(fontExtC0, c - 1);
    return FindGlyph(c);
}


// Draw a block graphics character.  The character cell is divided into 2 columns by 4 rows and each bit in c controls one block:
//      bit 0   bit 1
//      bit 2   bit 3
//      bit 4   bit 5
//      bit 6   bit 7
static void DrawMosaic(int x, int y, int c) {
    int cw = fontWidth * fontScale, ch = fontHeight * fontScale;
    int i, j, k, t, x0, x1, y0, y1;

    SPR_BEGIN(x, y, x + cw, y + ch);
    for(i = 0; i < 8; i++) {
        t = (c >> i) & 1;
        if(AttribInvis) t = 0;
        if(AttribRV) t = !t;
        x0 = (i & 1) ? cw / 2 : 0;
        x1 = (i & 1) ? cw : cw / 2;
        y0 = ((i >> 1) * ch) / 4;
        y1 = (((i >> 1) + 1) * ch) / 4;
        for(k = y0; k < y1; k++)
            for(j = x0; j < x1; j++) plot(x + j, y + k, t);
    }
    SPR_END();
}


// Invert the pixels of a glyph.  Used to draw the cursor when it is not the standard underline
static void InvertGlyph(int x, int y, const unsigned int *glyph) {
    int j, k, h, w;
    for(j = 0; j < fontWidth; j++)
        for(k = 0; k < fontHeight; k++)
            if((glyph[j] >> k) & 1)
                for(h = 0; h < fontScale; h++)
                    for(w = 0; w < fontScale; w++)
                        plot(x + (j * fontScale) + w, y + (k * fontScale) + h, -1);
}


// Write a glyph on the video using the graphic bit font
void DrawGlyph(int x, int y, const unsigned int *glyph) {           // x and y are in pixels
    int j, k, h, w;                     					// Loop counters, j for horizontal, y for vertical
    int t;
    unsigned int col, smear;

    SPR_BEGIN(x, y, x + fontWidth * fontScale, y + fontHeight * fontScale);
    for(j = 0; j < fontWidth; j++) {                                // Loop through each word (ie, horizontal scan line)
        col = glyph[j];
        smear = (AttribBold && j > 0) ? glyph[j - 1] : 0;           // bold is done by overstriking the glyph one pixel to the right
        for(k = 0; k < fontHeight; k++) {                           // Loop through the bits in the word (ie, vertical pixels)
            t = ((col | smear) >> k) & 1;
            if(AttribUL && k == fontHeight - 3) t = 1;              // implement underline
            if(AttribInvis) t = 0;                                  // don't draw if invisible
            if(AttribRV) t = !t;                                    // reverse video (if required)
            for(h = 0; h < fontScale; h++)
                for(w = 0; w < fontScale; w++)
                    plot(x + (j * fontScale) + w, y + (k * fontScale) + h, t);	// Draw the pixel
        }
    }
    SPR_END();
}




// select a font
void initFont(int fnt) {
    ShowCursor(false);                                              // turn off the cursor to prevent it from getting confused
    if(fnt == 1) {
        fontPtr = (unsigned int *)fontOne;
        fontExt437 = &fontOneX437[0][0];
        fontExtC0 = &fontOneXC0[0][0];
        fontExtDEC = &fontOneXDEC[0][0];
        fontExtBytes = sizeof(fontOneXC0[0]); fontExtBits = 12;
        fontHeight = 12;
        fontWidth = 6;
        fontStart = ' ';
        fontEnd = '~';
        fontScale = 1;
        fontNbr = 1;
    }

    if(fnt == 2 || fnt == 3) {
        fontPtr = (unsigned int *)fontTwo;
        fontExt437 = &fontTwoX437[0][0];
        fontExtC0 = &fontTwoXC0[0][0];
        fontExtDEC = &fontTwoXDEC[0][0];
        fontExtBytes = sizeof(fontTwoXC0[0]); fontExtBits = 20;
        fontHeight = 20;
        fontWidth = 13;
        fontStart = ' ';
        fontEnd = '~';
        fontScale = (fnt == 2) ? 1 : 2;
        fontNbr = fnt;
    }
}


// Put a char onto the video screen
// c is a character code from 0 to 255.  Codes with the top bit set are shown using the code page chosen in the set-up menu
void VideoPutc(int ci) {
    const unsigned int *glyph;
    int cw, c = ci & 0xff;
    int lit = ForceChar;                                            // true if this is a literal character (see VideoPutLiteral())
    int mosaic, printable;

    ForceChar = false;
    if(!lit && c == 0x0e) { ShiftOut = true;  return; }             // SO - make G1 the active character set
    if(!lit && c == 0x0f) { ShiftOut = false; return; }             // SI - make G0 the active character set

    ShowCursor(false);                                              // turn off the cursor to prevent fragments of it cluttering the screen

    if(AutoLineWrap) {
		if(CursorX < 0) CursorX = 0;
		if(CursorY < 0) CursorY = 0;
		if(CursorY > VRes) CursorY = VRes;
	}
    cw = fontWidth * fontScale;

    mosaic = MosaicMode && (lit || (c >= 0x20 && c != 0x7f));       // in block graphics mode all printable codes are drawn as blocks
    glyph = mosaic ? NULL : (lit ? FindGlyphLit(c) : FindGlyph(c));
    printable = mosaic || glyph != NULL;
    if(printable) {
        int reps = (CharRepeat > 1) ? CharRepeat : 1;               // the character can be repeated (see CCAttribute() in vt100.c)
        while(reps-- > 0) {
            // check if we need to wrap to the next line
            if(CursorX + cw > HRes && AutoLineWrap) {               // if we are at the end of a line
                CursorX = 0;                                        // wrap to the next
                IndexDown();                                        // which will scroll if we are on the bottom line
            }
            if(InsertMode) InsertChars(1);                          // make room if we are in insert mode
            if(mosaic)
                DrawMosaic(CursorX, CursorY, c);
            else
                DrawGlyph(CursorX, CursorY, glyph);
            CursorX += cw;                                          // and update our position
        }
    } else {
        // if it is not a printable char we need to check for control chars
        switch(c) {
            case '\r': CursorX = 0;                                 // for a return set the horizontal position to zero
                       break;
            case '\n':                                              // line feed, vertical tab and form feed
            case 0x0b:
            case 0x0c: IndexDown();                                 // move down a line (scrolling if needed)
                       if(NewLineMode) CursorX = 0;                 // in new line mode a line feed also does a return
                       break;
            case '\t': TabForward(1);                               // for a tab move the horiz position to the next tab stop
                       break;
            case '\b': CursorX -= cw;                               // for a backspace move the horiz position back by a char width
                       if(CursorX < 0) CursorX = 0;
                       break;
        }
    }

    CharPosX = (CursorX / cw) + 1;                                  // update the horizontal character position
    CharPosY = (CursorY / (fontHeight * fontScale)) + 1;            // update the vertical character position
}



// Put a literal character onto the video.  Codes 0x01 - 0x1F are drawn as the PC (DOS) symbols rather than being treated as control codes
void VideoPutLiteral(int c) {
    ForceChar = true;
    VideoPutc(c);
}



// control the cursor
void ShowCursor(int show) {
	static int visible = false;
    const unsigned int *g;

	if(CursorOff || (CursorBlink && CursorTimer > CURSOR_ON)) show = false;
	if(visible == show) return;                                     // no change required so skip the rest
    if(CursorChar >= 0) {                                           // a user defined cursor is the character with its pixels inverted
        g = FindGlyphLit(CursorChar);
        if(g) InvertGlyph(CursorX, CursorY, g);
    } else
	    DrawLineRaw(CursorX - 1, CursorY + (fontHeight * fontScale) - 3, CursorX + (fontWidth * fontScale) - 1, CursorY + (fontHeight * fontScale) - 3, -1);	// invert the underline
	visible = show;
}



// Set or reset a graphics pixel.  The graphics coordinates are in units of 3 x 3 screen pixels (so a character in the small font is 2 units wide and 4 high)
void GfxPixel(int x, int y, int on) {
    int i, j;
    ShowCursor(false);
    SPR_BEGIN(x * 3, y * 3, x * 3 + 3, y * 3 + 3);
    for(j = 0; j < 3; j++)
        for(i = 0; i < 3; i++) plot(x * 3 + i, y * 3 + j, on);
    SPR_END();
}



// Scroll the pixel rows y0 to y1-1 sideways by "shift" pixels.  left is true to scroll the picture to the left.
// For VGA the work is done a 32 bit word at a time, only on the words that can hold visible pixels, and the loops are as short as possible
void ScrollHorizPixels(int y0, int y1, int shift, int left) {
    int x, y, i, s, t, aw, m, wm, ya, yb, sh;
    unsigned int cur, nxt, *r;

    ShowCursor(false);
    if(y0 < 0) y0 = 0;
    if(y1 > VRes) y1 = VRes;
    if(shift < 1 || shift >= HRes) return;
    if(!vga) {                                                      // for composite video the pixels are stretched so we must do it the slow way (there are no sprites)
        for(y = y0; y < y1; y++) {
            if(left) for(x = 0; x < HRes; x++) plot(x, y, (x + shift < HRes) ? pixel(x + shift, y) : 0);
            else     for(x = HRes - 1; x >= 0; x--) plot(x, y, (x - shift >= 0) ? pixel(x - shift, y) : 0);
        }
        return;
    }
    m = VGA_H_OFFSET + HRes;                                        // the first pixel after the visible part of the line
    wm = m / 32;                                                    // the word that holds it.  Words after this one are always zero
    aw = wm + 1;                                                    // the number of words that we have to work on
    if(aw > VGA_HBUFF) aw = VGA_HBUFF;
    SPR_SYNC(y0, y1);                                               // with sprites showing start in the vertical blank (if we are not in it we wait for it)
    for(ya = y0; ya < y1; ya = yb) {                                // sprites are lifted and put back a row of cells (12 pixel rows) at a time, from the top down,
        yb = SprOn ? (ya / 12 + 1) * 12 : y1;                       // so that the work stays ahead of the beam and they are only missing while their row is moved
        if(yb > y1) yb = y1;
        SPR_BEGIN(0, ya, HRes, yb);
        sh = shift;
        while(sh > 0) {                                             // shifts of 32 or more are done in steps (the font sizes never need this)
            s = (sh > 31) ? 31 : sh;
            sh -= s;
            t = 32 - s;
            for(y = ya; y < yb; y++) {
                r = (unsigned int *)VideoBuf + y * (HBuf / 32);
                if(left) {
                    cur = r[0];
                    for(i = 1; i < aw; i++) { nxt = r[i]; r[i - 1] = (cur << s) | (nxt >> t); cur = nxt; }
                    r[aw - 1] = cur << s;
                } else {
                    for(i = aw - 1; i > 0; i--) r[i] = (r[i] >> s) | (r[i - 1] << t);
                    r[0] >>= s;
                }
                r[0] &= 0xffffffffu >> VGA_H_OFFSET;                // clear the margin at the left of the line
                if(m % 32 == 0) { if(wm < VGA_HBUFF) r[wm] = 0; }   // and the margin at the right
                else r[wm] &= ~(0xffffffffu >> (m % 32));
            }
        }
        SPR_HSHIFT(ya, left ? shift : -shift);
        SPR_END();
    }
}


// Scroll the whole screen sideways by one character.  left is true to scroll the text to the left
void ScrollHoriz(int left) {
    ScrollHorizPixels(0, VRes, fontWidth * fontScale, left);
}



void DisplayString(char *p) {
   while(*p) VideoPutc(*p++);
}



/**************************************************************************************************
Draw a line on a the video output
	x1, y1 - the start coordinate
	x2, y2 - the end coordinate
	colour - zero for erase, non zero to draw
***************************************************************************************************/
#define abs( a)     (((a)> 0) ? (a) : -(a))

static void DrawLineRaw(int x1, int y1, int x2, int y2, int colour) {
    int  x, y, addx, addy, dx, dy;
    int P;
    int i;

    dx = abs(x2 - x1);
    dy = abs(y2 - y1);
    x = x1;
    y = y1;

    if(x1 > x2)
       addx = -1;
    else
       addx = 1;

    if(y1 > y2)
       addy = -1;
    else
       addy = 1;

    if(dx >= dy) {
       P = 2*dy - dx;
       for(i=0; i<=dx; ++i) {
          plot(x, y, colour);
          if(P < 0) {
             P += 2*dy;
             x += addx;
          } else {
             P += 2*dy - 2*dx;
             x += addx;
             y += addy;
          }
       }
    } else {
       P = 2*dx - dy;
       for(i=0; i<=dy; ++i) {
          plot(x, y, colour);
          if(P < 0) {
             P += 2*dx;
             y += addy;
          } else {
             P += 2*dx - 2*dy;
             x += addx;
             y += addy;
          }
       }
    }
}




// draw a line on the video, keeping any sprites out of its way
void DrawLine(int x1, int y1, int x2, int y2, int colour) {
    SPR_BEGIN((x1 < x2 ? x1 : x2), (y1 < y2 ? y1 : y2), (x1 < x2 ? x2 : x1) + 1, (y1 < y2 ? y2 : y1) + 1);
    DrawLineRaw(x1, y1, x2, y2, colour);
    SPR_END();
}



/**********************************************************************************************
Draw a box on the video output
     x1, y1 - the start coordinate
     x2, y2 - the end coordinate
     fill  - 0 or 1
     colour - 0 or 1
***********************************************************************************************/
void DrawBox(int x1, int y1, int x2, int y2, int fill, int colour) {

   if(fill) {
      int y, ymax;                          // Find the y min and max
      if(y1 < y2) {
         y = y1;
         ymax = y2;
      } else {
         y = y2;
         ymax = y1;
      }

      for(; y<=ymax; ++y)                    // Draw lines to fill the rectangle
         DrawLine(x1, y, x2, y, colour);
   } else {
      DrawLine(x1, y1, x2, y1, colour);      	// Draw the 4 sides
      DrawLine(x1, y2, x2, y2, colour);
      DrawLine(x1, y1, x1, y2, colour);
      DrawLine(x2, y1, x2, y2, colour);
   }
}



/***********************************************************************************************
Draw a circle on the video output
	x, y - the center of the circle
	radius - the radius of the circle
	fill - non zero
	colour - to use for both the circle and fill
	aspect - the ration of the x and y axis (a float).  0.83 gives an almost perfect circle
***********************************************************************************************/
void DrawCircle(int x, int y, int radius, int fill, int colour, float aspect) {
   int a, b, P;
   int A, B;
   int asp;

   a = 0;
   b = radius;
   P = 1 - radius;
   asp = aspect * (float)(1 << 10);
   SPR_BEGIN(x - radius - 1, y - (int)(radius * aspect) - 2, x + radius + 2, y + (int)(radius * aspect) + 3);
   do {
     A = (a * asp) >> 10;
     B = (b * asp) >> 10;
     if(fill) {
         DrawLine(x-A, y+b, x+A, y+b, colour);
         DrawLine(x-A, y-b, x+A, y-b, colour);
         DrawLine(x-B, y+a, x+B, y+a, colour);
         DrawLine(x-B, y-a, x+B, y-a, colour);
      } else {
         plot(A+x, b+y, colour);
         plot(B+x, a+y, colour);
         plot(x-A, b+y, colour);
         plot(x-B, a+y, colour);
         plot(B+x, y-a, colour);
         plot(A+x, y-b, colour);
         plot(x-A, y-b, colour);
         plot(x-B, y-a, colour);
      }

      if(P < 0)
         P+= 3 + 2*a++;
      else
         P+= 5 + 2*(a++ - b--);

    } while(a <= b);
   SPR_END();
}


#if SPRITE_LAYER
#include "SpriteLayer.h"
#else
// the sprite layer is switched off (SPRITE_LAYER in Terminal.h): the hooks do nothing and a 1C command is swallowed
int SprOn, SprDepth;
void SprBeginOp(int x0, int y0, int x1, int y1) {}
void SprEndOp(void) {}
void SprScreenCleared(void) {}
void SprSync(int y0, int y1) {}
void SprHShift(int y, int sigma) {}
void SprVShift(int top, int bot, int dy) {}
void SprStart(void) {}
int SprFeed(int c) { return false; }
#endif
