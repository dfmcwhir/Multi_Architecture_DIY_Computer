/****************************************************************************************
 SpriteLayer.h

    The sprite layer (see "PIC32 Terminal Sprite Layer: Command Spec").  This file is part
    of Video.c (it is included at the end of it) because it works directly on the video
    buffer.  All of the commands start with the control code 0x1C and are decoded by
    SprFeed().

    How it works
    The screen is 160 x 96 "sprite pixels", each one 3 x 3 screen pixels (the same units
    as the graphics pixels set with control code 05).  The screen is also split into 80 x 24
    cells, each 2 x 4 sprite pixels (6 x 12 screen pixels), exactly the size of a block
    graphics character in the small font.

    The terminal does not keep a copy of the screen so the background of a cell is only
    saved while a sprite covers it:
      - SprCov is set for each cell that is currently covered by a sprite and SprBg holds the
        8 block pixels (bit 0 = top left, bit 1 = top right, bit 2 = second row left ...) of
        the background that the cell had.
      - when a sprite is added, moved or removed each cell that it touched is composited
        again: the saved background with every covering sprite drawn over it, in slot order.
      - before any other drawing code changes the screen (text, graphics, scrolling,
        clearing ...) it calls SprBeginOp() with the pixels that it is going to change.  Any
        covered cell in that area is put back to its background.  After the drawing the
        covered cells are composited again by SprEndOp() (which saves the new background).

    The background of a covered cell is saved as 8 block pixels so anything in it that is
    not block graphics (text, fine detail) is reduced to blocks (sampled at the centre of
    each 3 x 3 block).  Keep sprites out of text rows with CLIP.

    Flicker
    The picture is generated from the video buffer by DMA while the work is done, so the
    order matters.  Anything that changes many cells (moving sprites, SHOW, scrolling) first
    waits for the start of the vertical blank (SprSync(), with a timeout), then works from
    the top of the screen down so that the work stays ahead of the beam.  The final pixels of
    a cell are worked out before they are written, so a cell is written once, as the
    background with the sprites on it.  Sideways scrolling is done one text row at a time
    (lift the sprites in that row, shift the row, put the sprites back).

    Copyright remains Geoff Graham's on the original program.  The terms in Video.c apply.
****************************************************************************************/

#define SPR_SLOTS       16                                          // number of sprites
#define SPR_PICS        64                                          // number of pictures
#define SPR_COLS        80                                          // sprite cells across
#define SPR_ROWS        24                                          // and down (a 36 line screen only gets sprites in the first 24 lines)
#ifndef SPR_POOL_BYTES
#define SPR_POOL_BYTES  1280                                        // RAM for picture data (bits and masks)
#endif

typedef struct {
    short x, y;                                                     // position of the top left in sprite pixels (may be negative)
    unsigned char pic;                                              // picture number
    unsigned char flags;                                            // bit 0 = mirror, bit 1 = flip, bit 7 = hidden
} SprSlot;

typedef struct {
    unsigned short off;                                             // offset of the data in the pool
    unsigned char w;                                                // width in pixels (0 = not defined)
    unsigned char hm;                                               // height in the low 6 bits, bit 7 = has a mask
} SprPicture;

typedef struct { signed char c0, c1, r0, r1; } SprRect;             // a rectangle of cells (inclusive), empty if c1 < c0

static unsigned char SprPool[SPR_POOL_BYTES];                       // picture data.  For each picture the bits (h rows of (w + 7) / 8 bytes) then the mask
static unsigned short SprPoolUsed;                                  // bytes of the pool in use
static SprPicture SprPic[SPR_PICS];
static SprSlot SprS[SPR_SLOTS];                                     // the sprites as shown on the screen
static SprSlot SprP[SPR_SLOTS];                                     // the sprites as they will be after SHOW
static SprRect SprRc[SPR_SLOTS];                                    // the cells that each shown sprite covers (kept up to date by SprRefreshOn())
static unsigned char SprBg[SPR_ROWS * SPR_COLS];                    // background of the covered cells
static unsigned char SprCov[(SPR_ROWS * SPR_COLS) / 8];             // one bit per cell, set if a sprite is drawn on it
static unsigned char SprClipTop, SprClipBot = SPR_ROWS - 1;         // sprites are only drawn in these text rows
static unsigned char SprHold;                                       // true between HOLD and SHOW
int SprOn;                                                          // true if any sprite is showing (the drawing code only calls SprBeginOp() when this is set)
int SprDepth;                                                       // nesting of SprBeginOp() calls (the drawing code only calls SprEndOp() when this is set)
static int SprT0 = SPR_COLS, SprT1 = -1, SprU0 = SPR_ROWS, SprU1 = -1; // the cells touched by the drawing so far
static signed char SprD[SPR_ROWS];                                  // for each row of cells: how far (-1, 0 or 1 pixel) the real background is to the right of the saved one.
                                                                    // The saved backgrounds are blocks of 3 x 3 pixels so after a sideways scroll by a number of pixels that is
                                                                    // not a multiple of 3 this is what is left over (see SprHShift())
#ifndef SPR_SYNC_LOOPS
#define SPR_SYNC_LOOPS  120000                                      // the longest we wait for the vertical blank (about 20ms, more than a frame)
#endif

#define COV_GET(i)      ((SprCov[(i) >> 3] >> ((i) & 7)) & 1)
#define COV_SET(i)      (SprCov[(i) >> 3] |= (1 << ((i) & 7)))
#define COV_CLR(i)      (SprCov[(i) >> 3] &= ~(1 << ((i) & 7)))
#define SNAP_GET(snap, c)   (((snap)[(c) >> 3] >> ((c) & 7)) & 1)   // the same for a copy of the 10 bytes (80 cells) of one row of SprCov


/**************************************************************************************************
Reading and writing a cell of the video buffer (VGA only)
***************************************************************************************************/
#ifdef HOSTTEST                                                     // the host tests keep a log of every row of 6 pixels written, to check the order
int SprLog[80000], SprLogN, SprLogOn;
#define SPR_LOG(x, y)   do { if(SprLogOn && SprLogN < 80000) SprLog[SprLogN++] = ((x) << 16) | (y); } while(0)
#else
#define SPR_LOG(x, y)
#endif

// set 6 screen pixels (the low 6 bits of pat, the most significant is the leftmost) of pixel row y starting at pixel x (which includes VGA_H_OFFSET)
static void SprRow6(int x, int y, unsigned int pat) {
    int pos = x & 31, sh = 26 - pos, n1, n2;
    unsigned int m, *row = (unsigned int *)VideoBuf + y * (HBuf / 32) + (x >> 5);

    SPR_LOG(x, y);

    if(sh >= 0) {                                                   // all in one word
        m = 0x3fu << sh;
        row[0] = (row[0] & ~m) | (pat << sh);
    } else {                                                        // split over two words
        n1 = 32 - pos;                                              // pixels in the first word
        n2 = 6 - n1;                                                // and in the second
        m = (1u << n1) - 1;
        row[0] = (row[0] & ~m) | (pat >> n2);
        m = 0xffffffffu << (32 - n2);
        row[1] = (row[1] & ~m) | ((pat & ((1u << n2) - 1)) << (32 - n2));
    }
}

// set the block pixels of a cell on the screen.  Each of the 8 bits of b becomes 3 x 3 screen pixels.  If d is 1 or -1 the picture is moved one pixel
// to the right or left.  The pixel that comes in at the edge belongs to the cell next door: it is taken from its saved background if that is covered
// (snap is a copy of the row of SprCov) otherwise from the screen
static void SprPutCell(int c, int r, int b, int d, const unsigned char *snap) {
    int k, j, y, edge, nbr = c - d, cov = d && nbr >= 0 && nbr < SPR_COLS && SNAP_GET(snap, nbr);
    unsigned int base, pat;

    for(k = 0; k < 4; k++) {                                        // four rows of block pixels
        base = (((b >> (2 * k)) & 1) ? 0x38 : 0) | (((b >> (2 * k + 1)) & 1) ? 0x07 : 0);  // 6 screen pixels
        for(j = 0; j < 3; j++) {                                    // each 3 screen rows high
            y = r * 12 + 3 * k + j;
            pat = base;
            if(d) {
                if(cov) edge = (SprBg[r * SPR_COLS + nbr] >> (2 * k + (d > 0))) & 1;
                else    edge = pixel(d > 0 ? c * 6 - 1 : c * 6 + 6, y);
                pat = d > 0 ? ((base >> 1) | (edge << 5)) : (((base << 1) & 0x3f) | edge);
            }
            SprRow6(VGA_H_OFFSET + c * 6, y, pat);
        }
    }
}

// put the saved background of a covered cell back on the screen (as it really is, so moved by SprD)
static void SprRestore(int c, int r, const unsigned char *snap) {
    SprPutCell(c, r, SprBg[r * SPR_COLS + c], SprD[r], snap);
}


// read the block pixels of a cell from the screen (sampling the centre pixel of each 3 x 3 block, which is moved by SprD)
static int SprGetCell(int c, int r) {
    int i, b = 0;
    for(i = 0; i < 8; i++)
        if(pixel(c * 6 + (i & 1) * 3 + 1 + SprD[r], r * 12 + (i >> 1) * 3 + 1)) b |= (1 << i);
    return b;
}

// wait for the start of the vertical blank so that the work that follows (done from the top of the screen down) stays ahead of the beam.
// If we are already in the blank there is nothing to wait for.  Gives up after about a frame
#ifndef SPR_BACKLOG
#define SPR_BACKLOG     1024                                        // if more than this many bytes are waiting in the receive buffer we do not wait for the blank
#endif                                                              // (the host is ahead of us: catching up matters more than a flicker, and the buffer must not overflow)
static unsigned int SprLastSync = 0xffffffff;                       // the value of VFrame when we last waited

// Wait until the vertical blank has started so that the work that follows can be done from the top of the screen down and stay ahead of the beam.
// Not done: if we are in the blank already, if we have already waited in this frame (waiting once is enough, the later work follows straight
// on), or if the receive buffer is filling up.  Gives up after about a frame
static void SprWaitBlank(void) {
    int n = SPR_SYNC_LOOPS, backlog;
    if(!vga) return;
    backlog = SerialRxBufHead - SerialRxBufTail;
    if(backlog < 0) backlog += RxBufferSize;
    if(backlog > SPR_BACKLOG) return;
    if(VFrame == SprLastSync) return;
    while(VState == SV_LINE && n-- > 0) ;
    SprLastSync = VFrame;
}

// the same but only if a sprite is showing on the rows of cells that include the pixel rows y0 to y1-1 (used before scrolling, so that ordinary text
// scrolling is not slowed down just because a sprite is showing somewhere else)
void SprSync(int y0, int y1) {
    int s, r0 = y0 / 12, r1 = (y1 - 1) / 12;
    for(s = 0; s < SPR_SLOTS; s++)
        if(SprRc[s].c1 >= SprRc[s].c0 && SprRc[s].r0 <= r1 && SprRc[s].r1 >= r0) { SprWaitBlank(); return; }
}


/**************************************************************************************************
Geometry
***************************************************************************************************/
static int SprVisible(const SprSlot *s) {
    return !(s->flags & 0x80) && s->pic < SPR_PICS && SprPic[s->pic].w != 0;
}

// the cells that a slot covers (clipped to the screen and the clip rows).  Empty if it is hidden
static void SprCells(const SprSlot *s, SprRect *q) {
    int w, h, c0, c1, r0, r1;
    q->c0 = 0; q->c1 = -1; q->r0 = 0; q->r1 = -1;
    if(!SprVisible(s)) return;
    w = SprPic[s->pic].w; h = SprPic[s->pic].hm & 0x3f;
    c0 = s->x >> 1;  c1 = (s->x + w - 1) >> 1;
    r0 = s->y >> 2;  r1 = (s->y + h - 1) >> 2;
    if(c0 < 0) c0 = 0;
    if(c1 > SPR_COLS - 1) c1 = SPR_COLS - 1;
    if(r0 < SprClipTop) r0 = SprClipTop;
    if(r1 > SprClipBot) r1 = SprClipBot;
    if(c1 < c0 || r1 < r0) return;
    q->c0 = c0; q->c1 = c1; q->r0 = r0; q->r1 = r1;
}

// work out which sprites are showing and the cells they cover.  Call after any change to the shown sprites, the pictures or the clip rows
static void SprRefreshOn(void) {
    int s, n = 0;
    for(s = 0; s < SPR_SLOTS; s++) {
        SprCells(&SprS[s], &SprRc[s]);
        if(SprRc[s].c1 >= SprRc[s].c0) n++;
    }
    SprOn = (n != 0 && vga);
    if(!SprOn) memset(SprD, 0, sizeof(SprD));
}

// true if slot s covers the cell
static int SprCovers(int s, int c, int r) {
    const SprRect *q = &SprRc[s];
    return c >= q->c0 && c <= q->c1 && r >= q->r0 && r <= q->r1;
}


/**************************************************************************************************
Compositing
***************************************************************************************************/
// work out what the cell should look like and put it on the screen.  snap is a copy of the row of SprCov from before the cells of the row were changed
static void SprRecompose(int c, int r, const unsigned char *snap) {
    int i, s, w, h, rb, px, py, u, v, sh, bit, mbit, idx = r * SPR_COLS + c;
    unsigned int mo, cm = 0;
    unsigned char b;
    const SprSlot *sl;
    const SprPicture *pd;
    const unsigned char *p;

    if(c < 0 || c >= SPR_COLS || r < 0 || r >= SPR_ROWS) return;
    for(s = 0; s < SPR_SLOTS; s++) if(SprCovers(s, c, r)) cm |= (1u << s);      // the sprites that cover this cell
    if(cm == 0) {                                                   // nothing here (any more): put the background back
        if(COV_GET(idx)) { SprRestore(c, r, snap); COV_CLR(idx); }
        return;
    }
    if(!COV_GET(idx)) { SprBg[idx] = SprGetCell(c, r); COV_SET(idx); }    // save what is there now
    b = SprBg[idx];
    for(s = 0; s < SPR_SLOTS; s++) {
        if(!(cm & (1u << s))) continue;
        sl = &SprS[s]; pd = &SprPic[sl->pic];
        w = pd->w; h = pd->hm & 0x3f; rb = (w + 7) >> 3;
        mo = (pd->hm & 0x80) ? (unsigned int)(h * rb) : 0;          // offset of the mask from the bits
        for(i = 0; i < 8; i++) {
            px = c * 2 + (i & 1); py = r * 4 + (i >> 1);
            u = px - sl->x; v = py - sl->y;
            if(u < 0 || v < 0 || u >= w || v >= h) continue;
            if(sl->flags & 1) u = w - 1 - u;
            if(sl->flags & 2) v = h - 1 - v;
            p = SprPool + pd->off + v * rb + (u >> 3);
            sh = 7 - (u & 7);
            bit = (p[0] >> sh) & 1;
            mbit = mo ? ((p[mo] >> sh) & 1) : bit;
            if(mbit) b = (b & ~(1 << i)) | (bit << i);
        }
    }
    SprPutCell(c, r, b, 0, NULL);
}

// sort and join the column ranges iv[0], iv[1], iv[2], iv[3] ... (n pairs: first and last column).  Returns the number of ranges left
static int SprMerge(unsigned char *iv, int n) {
    int i, j, m;
    unsigned char a, b;
    for(i = 1; i < n; i++) {                                        // insertion sort on the first column
        a = iv[2 * i]; b = iv[2 * i + 1];
        for(j = i - 1; j >= 0 && iv[2 * j] > a; j--) { iv[2 * j + 2] = iv[2 * j]; iv[2 * j + 3] = iv[2 * j + 1]; }
        iv[2 * j + 2] = a; iv[2 * j + 3] = b;
    }
    for(m = 0, i = 0; i < n; i++) {                                 // join ranges that overlap or touch
        if(m && iv[2 * i] <= iv[2 * m - 1] + 1) { if(iv[2 * i + 1] > iv[2 * m - 1]) iv[2 * m - 1] = iv[2 * i + 1]; }
        else { iv[2 * m] = iv[2 * i]; iv[2 * m + 1] = iv[2 * i + 1]; m++; }
    }
    return m;
}

// redraw the cells in a list of rectangles, from the top row down, each cell once
static void SprRecomposeRects(const SprRect *list, int n) {
    unsigned char iv[2 * SPR_SLOTS * 2], snap[SPR_COLS / 8];
    int i, k, m, r, c, r0 = SPR_ROWS, r1 = -1;

    if(!vga) return;                                                // composite video has no sprites
    for(i = 0; i < n; i++) {
        if(list[i].c1 < list[i].c0) continue;
        if(list[i].r0 < r0) r0 = list[i].r0;
        if(list[i].r1 > r1) r1 = list[i].r1;
    }
    for(r = r0; r <= r1; r++) {
        for(m = 0, i = 0; i < n; i++)
            if(list[i].c1 >= list[i].c0 && r >= list[i].r0 && r <= list[i].r1) { iv[2 * m] = list[i].c0; iv[2 * m + 1] = list[i].c1; m++; }
        m = SprMerge(iv, m);
        memcpy(snap, SprCov + r * (SPR_COLS / 8), SPR_COLS / 8);
        for(k = 0; k < m; k++)
            for(c = iv[2 * k]; c <= iv[2 * k + 1]; c++) SprRecompose(c, r, snap);
    }
}

// add a rectangle to a list (empty ones are left out)
static void SprAddRect(SprRect *list, int *n, const SprRect *q) {
    if(q->c1 < q->c0) return;
    list[(*n)++] = *q;
}

static int SprOverlap(const SprRect *a, const SprRect *b) {
    return a->c1 >= a->c0 && b->c1 >= b->c0 && a->c0 <= b->c1 && b->c0 <= a->c1 && a->r0 <= b->r1 && b->r0 <= a->r1;
}

// make the shown sprites the same as the pending ones and redraw what changed
static void SprApplyAll(void) {
    SprRect list[SPR_SLOTS * 2], a, b;
    SprSlot nw[SPR_SLOTS];
    int s, n = 0, changed = 0;

    ShowCursor(false);
    for(s = 0; s < SPR_SLOTS; s++)
        if(SprS[s].x != SprP[s].x || SprS[s].y != SprP[s].y || SprS[s].pic != SprP[s].pic || SprS[s].flags != SprP[s].flags) changed = 1;
    if(!changed) return;
    SprWaitBlank();                                                 // from here until the end is done in the blanking time if it can be
    for(s = 0; s < SPR_SLOTS; s++) {
        if(SprS[s].x == SprP[s].x && SprS[s].y == SprP[s].y && SprS[s].pic == SprP[s].pic && SprS[s].flags == SprP[s].flags) continue;
        SprCells(&SprS[s], &a);
        SprS[s] = SprP[s];
        SprCells(&SprS[s], &b);
        if(SprOverlap(&a, &b)) {                                    // join the old and new areas
            if(b.c0 < a.c0) a.c0 = b.c0;
            if(b.c1 > a.c1) a.c1 = b.c1;
            if(b.r0 < a.r0) a.r0 = b.r0;
            if(b.r1 > a.r1) a.r1 = b.r1;
            SprAddRect(list, &n, &a);
        } else {
            SprAddRect(list, &n, &a);
            SprAddRect(list, &n, &b);
        }
    }
    SprRefreshOn();
    SprRecomposeRects(list, n);
}

// redraw every cell that a showing sprite covers (used when the clip rows change)
static void SprRedrawAll2(int newTop, int newBot) {
    SprRect list[SPR_SLOTS];
    int s, top = SprClipTop, bot = SprClipBot;
    ShowCursor(false);
    SprWaitBlank();
    SprClipTop = 0; SprClipBot = SPR_ROWS - 1;                      // find the cells that sprites cover with no clipping
    for(s = 0; s < SPR_SLOTS; s++) SprCells(&SprS[s], &list[s]);
    SprClipTop = newTop; SprClipBot = newBot;
    SprRefreshOn();
    SprRecomposeRects(list, SPR_SLOTS);                             // and redraw them with the new clip rows
}

// after a change to a pending slot show it at once unless we are holding
static void SprChanged(void) {
    if(!SprHold) SprApplyAll();
}


/**************************************************************************************************
Called by the drawing code so that sprites do not get in its way
***************************************************************************************************/
// the drawing code is about to change the pixels x0 to x1-1 and y0 to y1-1
void SprBeginOp(int x0, int y0, int x1, int y1) {
    int c, r, c0, c1, r0, r1;
    unsigned char snap[SPR_COLS / 8];

    SprDepth++;
    if(x0 < 0) x0 = 0;
    if(y0 < 0) y0 = 0;
    if(x1 > SPR_COLS * 6) x1 = SPR_COLS * 6;
    if(y1 > SPR_ROWS * 12) y1 = SPR_ROWS * 12;
    if(x1 <= x0 || y1 <= y0) return;
    c0 = x0 / 6; c1 = (x1 - 1) / 6; r0 = y0 / 12; r1 = (y1 - 1) / 12;
    if(c0 < SprT0) SprT0 = c0;
    if(c1 > SprT1) SprT1 = c1;
    if(r0 < SprU0) SprU0 = r0;
    if(r1 > SprU1) SprU1 = r1;
    for(r = r0; r <= r1; r++) {                                     // put the background back so that the drawing sees it
        memcpy(snap, SprCov + r * (SPR_COLS / 8), SPR_COLS / 8);
        for(c = c0; c <= c1; c++)
            if(SNAP_GET(snap, c)) SprRestore(c, r, snap);
        for(c = c0; c <= c1; c++) COV_CLR(r * SPR_COLS + c);
    }
}

// the drawing is finished: put the sprites back on the cells that it touched
void SprEndOp(void) {
    SprRect list[SPR_SLOTS];
    int s;

    if(SprDepth > 0) SprDepth--;
    if(SprDepth > 0) return;
    if(SprT1 < SprT0 || SprU1 < SprU0) return;
    for(s = 0; s < SPR_SLOTS; s++) {                                // the part of each sprite that is in the touched area
        list[s] = SprRc[s];
        if(list[s].c0 < SprT0) list[s].c0 = SprT0;
        if(list[s].c1 > SprT1) list[s].c1 = SprT1;
        if(list[s].r0 < SprU0) list[s].r0 = SprU0;
        if(list[s].r1 > SprU1) list[s].r1 = SprU1;
    }
    SprT0 = SPR_COLS; SprT1 = -1; SprU0 = SPR_ROWS; SprU1 = -1;
    SprRecomposeRects(list, SPR_SLOTS);                             // (the background is saved first if the cell was not covered)
}

// A sideways scroll of the sprite row that starts at pixel row y has just been done (left by sigma pixels, negative for right) and the sprites
// are still lifted.  The saved backgrounds are blocks of 3 x 3 pixels so they can only move in steps of 3 pixels.  What is left over (-1, 0 or 1
// pixel) is remembered in SprD, used when the background is put back on the screen and when it is read again
void SprHShift(int y, int sigma) {
    int r = y / 12, v, n;
    if(r < 0 || r >= SPR_ROWS) return;
    v = sigma - SprD[r];
    n = v + 1 >= 0 ? (v + 1) / 3 : -((-(v + 1) + 2) / 3);           // floor((v + 1) / 3), the number of blocks that the saved background moves
    SprD[r] = 3 * n - v;
}

// the pixel rows top to bot-1 have been scrolled up (dy > 0) or down by |dy| rows.  The remainders in SprD move with them
void SprVShift(int top, int bot, int dy) {
    int d = dy < 0 ? -dy : dy, k = d / 12, r0 = top / 12, n = (bot + 11) / 12 - r0;

    if(n > SPR_ROWS - r0) n = SPR_ROWS - r0;
    if(n <= 0) return;
    if(d % 12 || top % 12 || bot % 12 || k >= n) k = n;             // not whole rows: forget the remainders
    if(k < n) {
        if(dy > 0) { memmove(SprD + r0, SprD + r0 + k, n - k); memset(SprD + r0 + n - k, 0, k); }
        else       { memmove(SprD + r0 + k, SprD + r0, n - k); memset(SprD + r0, 0, k); }
    } else
        memset(SprD + r0, 0, n);
}

// the screen has just been cleared (by ClearScreen()): nothing is covered and all the sprites are hidden
void SprScreenCleared(void) {
    int s;
    memset(SprCov, 0, sizeof(SprCov));
    for(s = 0; s < SPR_SLOTS; s++) { SprS[s].flags |= 0x80; SprP[s].flags |= 0x80; }
    SprClipTop = 0; SprClipBot = SPR_ROWS - 1;
    SprRefreshOn();
    SprOn = 0;
    SprDepth = 0;
    SprT0 = SPR_COLS; SprT1 = -1; SprU0 = SPR_ROWS; SprU1 = -1;
    memset(SprD, 0, sizeof(SprD));
}


/**************************************************************************************************
The commands
***************************************************************************************************/
// 1C 01 n w h f data - the data has now arrived, make the picture n available
static void SprCommit(int n, int off, int w, int h, int mask) {
    SprRect list[SPR_SLOTS * 2];
    int s, k = 0;

    ShowCursor(false);
    SprWaitBlank();
    for(s = 0; s < SPR_SLOTS; s++)                                  // slots showing this picture (as they are now)
        if(SprS[s].pic == n) SprCells(&SprS[s], &list[k++]);
    SprPic[n].off = off; SprPic[n].w = w; SprPic[n].hm = h | (mask ? 0x80 : 0);
    for(s = 0; s < SPR_SLOTS; s++)                                  // and as they will be
        if(SprS[s].pic == n) SprCells(&SprS[s], &list[k++]);
    SprRefreshOn();
    SprRecomposeRects(list, k);
}

// 1C 08 - hide every slot, forget every picture
static void SprClear(void) {
    SprRect list[SPR_SLOTS];
    int s;

    ShowCursor(false);
    SprWaitBlank();
    for(s = 0; s < SPR_SLOTS; s++) SprCells(&SprS[s], &list[s]);
    memset(SprS, 0, sizeof(SprS));
    memset(SprP, 0, sizeof(SprP));
    for(s = 0; s < SPR_SLOTS; s++) { SprS[s].flags = 0x80; SprP[s].flags = 0x80; }
    memset(SprPic, 0, sizeof(SprPic));
    SprPoolUsed = 0;
    SprHold = false;
    SprRefreshOn();
    SprRecomposeRects(list, SPR_SLOTS);
}

// the decoder for the arguments of a command
static unsigned char sfCmd;                                         // the command byte (0 = waiting for it)
static unsigned char sfNeed, sfGot;                                 // the number of arguments needed and received
static unsigned char sfArg[5];
static unsigned short sfData;                                       // bytes of picture data still to come
static unsigned char *sfDst;                                        // where they go (NULL to throw them away)
static unsigned char sfPicN, sfPicW, sfPicH, sfPicMask;
static unsigned short sfPicOff;

static void SprExecute(void) {
    int s = sfArg[0];

    switch(sfCmd) {
        case 0x02: if(s < SPR_SLOTS && sfArg[1] < SPR_PICS) {                    // PLACE s n x y f
                       SprP[s].pic = sfArg[1]; SprP[s].x = sfArg[2] - 32; SprP[s].y = sfArg[3] - 32; SprP[s].flags = sfArg[4] & 0x83;
                       SprChanged();
                   }
                   break;
        case 0x03: if(s < SPR_SLOTS) { SprP[s].x = sfArg[1] - 32; SprP[s].y = sfArg[2] - 32; SprChanged(); }        // MOVE s x y
                   break;
        case 0x04: if(s < SPR_SLOTS && sfArg[1] < SPR_PICS) { SprP[s].pic = sfArg[1]; SprChanged(); }              // PICTURE s n
                   break;
        case 0x05: if(s < SPR_SLOTS) { SprP[s].flags = sfArg[1] & 0x83; SprChanged(); }                            // FLAGS s f
                   break;
        case 0x06: if(s < SPR_SLOTS) { SprP[s].flags |= 0x80; SprChanged(); }                                      // HIDE s
                   break;
        case 0x07: for(s = 0; s < SPR_SLOTS; s++) SprP[s].flags |= 0x80;                                           // HIDE ALL
                   SprChanged();
                   break;
        case 0x08: SprClear(); break;                                                                              // CLEAR
        case 0x09: SprHold = true; break;                                                                          // HOLD
        case 0x0a: if(SprHold) { SprHold = false; SprApplyAll(); }                                                 // SHOW
                   break;
        case 0x0b: if(sfArg[0] <= sfArg[1] && sfArg[1] < SPR_ROWS) {                                               // CLIP t b
                       SprRedrawAll2(sfArg[0], sfArg[1]);
                   }
                   break;
        case 0x0c: putSerialString("SP1"); break;                                                                  // IDENTIFY
        case 0x0d: {                                                                                               // STATUS: replies "ST" dd pppp (hex)
                       static const char hx[] = "0123456789ABCDEF";
                       char b[8];
                       unsigned int d = RxDropped, p = RxPeak;
                       if(d > 255) d = 255;
                       RxDropped = 0; RxPeak = 0;
                       b[0] = 'S'; b[1] = 'T';
                       b[2] = hx[(d >> 4) & 15]; b[3] = hx[d & 15];
                       b[4] = hx[(p >> 12) & 15]; b[5] = hx[(p >> 8) & 15]; b[6] = hx[(p >> 4) & 15]; b[7] = 0;
                       putSerialString(b);
                       b[0] = hx[p & 15]; b[1] = 0;
                       putSerialString(b);
                   }
                   break;
    }
}

// a 0x1C has just arrived: start a new command
void SprStart(void) {
    sfCmd = 0; sfData = 0; sfDst = NULL;
}

// Feed the next byte after a 0x1C to the sprite decoder.  Returns true if more bytes are needed for the command
int SprFeed(int c) {
    int rb, len, n, w, h, m, off;

    c &= 0xff;
    if(sfData) {                                                    // picture data
        if(sfDst) *sfDst++ = c;
        if(--sfData) return true;
        if(sfDst) SprCommit(sfPicN, sfPicOff, sfPicW, sfPicH, sfPicMask);
        sfDst = NULL; sfCmd = 0;
        return false;
    }
    if(sfCmd == 0) {                                                // this is the command
        sfCmd = c; sfGot = 0;
        switch(c) {
            case 0x01: sfNeed = 4; break;
            case 0x02: sfNeed = 5; break;
            case 0x03: sfNeed = 3; break;
            case 0x04: case 0x05: case 0x0b: sfNeed = 2; break;
            case 0x06: sfNeed = 1; break;
            default:   sfNeed = 0; break;
        }
        if(sfNeed) return true;
        SprExecute();
        sfCmd = 0;
        return false;
    }
    sfArg[sfGot++] = c;                                             // one of the arguments
    if(sfGot < sfNeed) return true;
    if(sfCmd == 0x01) {                                             // DEFINE n w h f
        n = sfArg[0]; w = sfArg[1]; h = sfArg[2]; m = sfArg[3] & 1;
        rb = (w + 7) >> 3;
        len = (w >= 1 && w <= 32 && h >= 1 && h <= 32) ? h * rb * (m ? 2 : 1) : 0;
        sfDst = NULL;
        if(len == 0) {                                              // an impossible size: we cannot know how many bytes follow, so there are none
            sfCmd = 0;
            return false;
        }
        sfData = len;
        if(n < SPR_PICS) {
            off = -1;
            if(SprPic[n].w && (int)((SprPic[n].hm & 0x3f) * ((SprPic[n].w + 7) >> 3) * ((SprPic[n].hm & 0x80) ? 2 : 1)) >= len)
                off = SprPic[n].off;                                // redefine in the old place if it is no bigger
            else if(SprPoolUsed + len <= SPR_POOL_BYTES) {
                off = SprPoolUsed; SprPoolUsed += len;
            }
            if(off >= 0) {
                sfDst = SprPool + off;
                sfPicN = n; sfPicW = w; sfPicH = h; sfPicMask = m; sfPicOff = off;
            }
        }
        return true;                                                // now the data
    }
    SprExecute();
    sfCmd = 0;
    return false;
}

#ifdef HOSTTEST
void SprDebugInfo(int c, int r) {
    int s; printf("cell(%d,%d) COV=%d acc=%d dx=%d depth=%d on=%d\n", c, r, COV_GET(r*SPR_COLS+c), SprD[r], 0, SprDepth, SprOn);
    for(s = 0; s < SPR_SLOTS; s++) if(SprRc[s].c1 >= SprRc[s].c0) printf("  slot %d pic %d at %d,%d fl %02x  cells c%d-%d r%d-%d\n", s, SprS[s].pic, SprS[s].x, SprS[s].y, SprS[s].flags, SprRc[s].c0, SprRc[s].c1, SprRc[s].r0, SprRc[s].r1);
}
// for the host tests: the pixel at x, y as it will be when the sprites go (the saved background for covered cells, quantised to blocks)
int SprDebugPixel(int x, int y) {
    int c = x / 6, r = y / 12, idx = r * SPR_COLS + c, i;
    if(c < 80 && r < SPR_ROWS && COV_GET(idx)) { i = ((y % 12) / 3) * 2 + ((x % 6) / 3); return (SprBg[idx] >> i) & 1; }
    return pixel(x, y);
}
#endif
