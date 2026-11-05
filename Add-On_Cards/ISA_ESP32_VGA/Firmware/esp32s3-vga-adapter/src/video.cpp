// VGA output and display command processor.
//
// The ESP32-S3 LCD_CAM peripheral (RGB panel mode) generates HSYNC, VSYNC and
// an 8-bit pixel stream at the VGA pixel clock. Only 6 of the 8 data lines
// are wired (2 bits each of R, G, B through the resistor ladder).
//
// No frame buffer is used: the driver calls onBounceEmpty() from an interrupt
// to fill a small bounce buffer (8 scan lines) just before DMA sends it. The
// scan lines are composed on the fly from:
//   1. backdrop colour or the 320x240 bitmap (with hardware-style scrolling)
//   2. 16 sprites of 16x16 pixels plus a mouse pointer
//   3. the 80x30 text layer (8x16 font, per-cell foreground/background)
// Everything lives in internal SRAM, so PSRAM is not needed.
#pragma GCC optimize("O2")

#include "video.h"
#include "input.h"
#include "audio.h"
#include "font8x16.h"

#include <string.h>
#include <stdlib.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_lcd_panel_rgb.h"
#include "esp_lcd_panel_ops.h"
#include "esp_log.h"
#include "esp_attr.h"

static const char *TAG = "video";

namespace video {

Ring<uint16_t, VIDEO_FIFO_SIZE> fifo;
Ring<uint8_t, 256> resp;
volatile uint32_t frameCount = 0;
volatile uint8_t vblFlag = 0;
volatile bool idle = true;
volatile bool ready = false;

static TaskHandle_t s_task = nullptr;
static volatile bool s_sleeping = false;

// ------------------------------------------------------------------ state
struct Sprite {
  int16_t x, y;
  uint8_t pattern;
  uint8_t flags;   // bit0 visible, bit1 h-flip, bit2 v-flip
};

static uint8_t  s_bitmap[GFX_W * GFX_H];
static uint8_t  s_textCh[TEXT_COLS * TEXT_ROWS];
static uint8_t  s_textFg[TEXT_COLS * TEXT_ROWS];
static uint8_t  s_textBg[TEXT_COLS * TEXT_ROWS];
static uint8_t  s_font[256 * 16];
static uint8_t  s_patterns[NUM_PATTERNS][SPRITE_SIZE * SPRITE_SIZE];
static uint8_t  s_pointer[SPRITE_SIZE * SPRITE_SIZE];
static Sprite   s_sprites[NUM_SPRITES];

static volatile uint8_t  s_layers = LAYER_TEXT;
static volatile uint8_t  s_backdrop = 0;
static volatile uint16_t s_scrollX = 0;
static volatile uint8_t  s_scrollY = 0;
static volatile bool     s_pointerOn = false;

// Text cursor (read by the ISR for drawing)
static volatile uint8_t s_curCol = 0, s_curRow = 0;
static volatile uint8_t s_curMode = 1;     // 0 off, 1 underline, 2 block
static uint8_t s_fg = 0x3F, s_bg = 0x00;
static uint8_t s_scrTop = 0, s_scrBot = TEXT_ROWS - 1;

// ISR scratch
static uint8_t  s_comp[GFX_W + 2 * SPRITE_SIZE];
static uint32_t s_line[VGA_H_RES / 4];

// Nibble -> byte mask for expanding font bits (bit 3 of the nibble = leftmost
// pixel = lowest byte in the little-endian word).
static DRAM_ATTR const uint32_t NIB[16] = {
  0x00000000, 0xFF000000, 0x00FF0000, 0xFFFF0000,
  0x0000FF00, 0xFF00FF00, 0x00FFFF00, 0xFFFFFF00,
  0x000000FF, 0xFF0000FF, 0x00FF00FF, 0xFFFF00FF,
  0x0000FFFF, 0xFF00FFFF, 0x00FFFFFF, 0xFFFFFFFF,
};

// ------------------------------------------------------------------ ISR side
static inline void IRAM_ATTR drawSpriteRow(const uint8_t *pat, int16_t sx, int16_t sy,
                                           uint8_t flags, int y) {
  int row = y - sy;
  if ((unsigned)row >= SPRITE_SIZE) return;
  if (flags & 4) row = SPRITE_SIZE - 1 - row;
  const uint8_t *p = pat + row * SPRITE_SIZE;
  for (int i = 0; i < SPRITE_SIZE; i++) {
    int x = sx + i;
    if ((unsigned)x >= GFX_W) continue;
    uint8_t c = (flags & 2) ? p[SPRITE_SIZE - 1 - i] : p[i];
    if (!(c & COLOR_TRANSPARENT)) s_comp[x] = c;
  }
}

// Compose one 320-pixel source line (bitmap/backdrop + sprites) and expand it
// to 640 pixels in s_line.
static void IRAM_ATTR composeLine(int y) {
  uint8_t layers = s_layers;
  if (layers & LAYER_BITMAP) {
    int by = y + s_scrollY;
    if (by >= GFX_H) by -= GFX_H;
    const uint8_t *row = s_bitmap + by * GFX_W;
    int sx = s_scrollX;
    if (sx >= GFX_W) sx = 0;
    memcpy(s_comp, row + sx, GFX_W - sx);
    if (sx) memcpy(s_comp + GFX_W - sx, row, sx);
  } else {
    memset(s_comp, s_backdrop, GFX_W);
  }
  if (layers & LAYER_SPRITES) {
    // Sprite 0 has the highest priority, so draw it last.
    for (int i = NUM_SPRITES - 1; i >= 0; i--) {
      const Sprite &s = s_sprites[i];
      if (s.flags & 1)
        drawSpriteRow(s_patterns[s.pattern & (NUM_PATTERNS - 1)], s.x, s.y, s.flags, y);
    }
  }
  if (s_pointerOn) drawSpriteRow(s_pointer, input::mouseX, input::mouseY, 0, y);

  const uint8_t *c = s_comp;
  for (int i = 0; i < VGA_H_RES / 4; i++, c += 2) {
    uint32_t a = c[0], b = c[1];
    s_line[i] = (a | (a << 8)) | ((b | (b << 8)) << 16);
  }
}

// Draw one scan line of the text layer over out[] (640 pixels).
static void IRAM_ATTR textLine(uint32_t *out, int y) {
  int row = y >> 4, gy = y & 15;
  int base = row * TEXT_COLS;
  const uint8_t *ch = s_textCh + base, *fg = s_textFg + base, *bg = s_textBg + base;
  const uint8_t *fnt = s_font + gy;
  int curCol = -1;
  uint8_t mode = s_curMode;
  if (mode && row == s_curRow && ((frameCount >> 4) & 1) && (mode == 2 || gy >= 14))
    curCol = s_curCol;
  for (int c = 0; c < TEXT_COLS; c++, out += 2) {
    uint8_t g = fnt[ch[c] << 4];
    if (c == curCol) g ^= 0xFF;
    uint32_t f = fg[c] * 0x01010101u;
    uint32_t m0 = NIB[g >> 4], m1 = NIB[g & 15];
    uint8_t b = bg[c];
    if (!(b & COLOR_TRANSPARENT)) {
      uint32_t bb = b * 0x01010101u;
      out[0] = (bb & ~m0) | (f & m0);
      out[1] = (bb & ~m1) | (f & m1);
    } else if (g) {
      out[0] = (out[0] & ~m0) | (f & m0);
      out[1] = (out[1] & ~m1) | (f & m1);
    }
  }
}

static bool IRAM_ATTR onBounceEmpty(esp_lcd_panel_handle_t, void *buf, int pos_px,
                                    int len_bytes, void *) {
  int y = pos_px / VGA_H_RES;
  int lines = len_bytes / VGA_H_RES;
  uint32_t *out = (uint32_t *)buf;
  bool text = s_layers & LAYER_TEXT;
  for (int k = 0; k < lines; k++, y++, out += VGA_H_RES / 4) {
    if (!(y & 1)) composeLine(y >> 1);
    memcpy(out, s_line, VGA_H_RES);
    if (text) textLine(out, y);
  }
  return false;
}

static bool IRAM_ATTR onVsync(esp_lcd_panel_handle_t, const esp_lcd_rgb_panel_event_data_t *,
                              void *) {
  frameCount = frameCount + 1;
  vblFlag = 1;
  return false;
}

// ------------------------------------------------------------------ text
static void textClear() {
  memset(s_textCh, ' ', sizeof s_textCh);
  memset(s_textFg, s_fg, sizeof s_textFg);
  memset(s_textBg, s_bg, sizeof s_textBg);
  s_curCol = 0;
  s_curRow = s_scrTop;
}

static void textScrollUp(int top, int bot) {
  if (top >= bot) {
    int o = top * TEXT_COLS;
    memset(s_textCh + o, ' ', TEXT_COLS);
    memset(s_textFg + o, s_fg, TEXT_COLS);
    memset(s_textBg + o, s_bg, TEXT_COLS);
    return;
  }
  int o = top * TEXT_COLS, n = (bot - top) * TEXT_COLS;
  memmove(s_textCh + o, s_textCh + o + TEXT_COLS, n);
  memmove(s_textFg + o, s_textFg + o + TEXT_COLS, n);
  memmove(s_textBg + o, s_textBg + o + TEXT_COLS, n);
  int last = bot * TEXT_COLS;
  memset(s_textCh + last, ' ', TEXT_COLS);
  memset(s_textFg + last, s_fg, TEXT_COLS);
  memset(s_textBg + last, s_bg, TEXT_COLS);
}

static void textScrollDown(int top, int bot) {
  int o = top * TEXT_COLS, n = (bot - top) * TEXT_COLS;
  if (n > 0) {
    memmove(s_textCh + o + TEXT_COLS, s_textCh + o, n);
    memmove(s_textFg + o + TEXT_COLS, s_textFg + o, n);
    memmove(s_textBg + o + TEXT_COLS, s_textBg + o, n);
  }
  memset(s_textCh + o, ' ', TEXT_COLS);
  memset(s_textFg + o, s_fg, TEXT_COLS);
  memset(s_textBg + o, s_bg, TEXT_COLS);
}

static void newline() {
  uint8_t r = s_curRow;
  if (r == s_scrBot) textScrollUp(s_scrTop, s_scrBot);
  else if (r < TEXT_ROWS - 1) r++;
  s_curRow = r;
}

static void putGlyph(uint8_t c) {
  int i = s_curRow * TEXT_COLS + s_curCol;
  s_textCh[i] = c;
  s_textFg[i] = s_fg;
  s_textBg[i] = s_bg;
  if (s_curCol >= TEXT_COLS - 1) {
    s_curCol = 0;
    newline();
  } else {
    s_curCol = s_curCol + 1;
  }
}

static void termPutc(uint8_t c) {
  switch (c) {
    case 0x07: audio::beep(880, 6); break;
    case 0x08: if (s_curCol) s_curCol = s_curCol - 1; break;
    case 0x09: {
      int col = (s_curCol + 8) & ~7;
      s_curCol = col >= TEXT_COLS ? TEXT_COLS - 1 : col;
      break;
    }
    case 0x0A: newline(); break;
    case 0x0C: textClear(); break;
    case 0x0D: s_curCol = 0; break;
    default:
      if (c >= 0x20) putGlyph(c);
      break;
  }
}

// ------------------------------------------------------------------ graphics
static inline void plot(int x, int y, uint8_t c) {
  if ((unsigned)x < GFX_W && (unsigned)y < GFX_H) s_bitmap[y * GFX_W + x] = c;
}

static void hline(int x0, int x1, int y, uint8_t c) {
  if ((unsigned)y >= GFX_H) return;
  if (x0 > x1) { int t = x0; x0 = x1; x1 = t; }
  if (x0 < 0) x0 = 0;
  if (x1 >= GFX_W) x1 = GFX_W - 1;
  if (x0 > x1) return;
  memset(s_bitmap + y * GFX_W + x0, c, x1 - x0 + 1);
}

static void fillRect(int x, int y, int w, int h, uint8_t c) {
  for (int j = 0; j < h; j++) hline(x, x + w - 1, y + j, c);
}

static void line(int x0, int y0, int x1, int y1, uint8_t c) {
  int dx = abs(x1 - x0), sx = x0 < x1 ? 1 : -1;
  int dy = -abs(y1 - y0), sy = y0 < y1 ? 1 : -1;
  int err = dx + dy;
  for (;;) {
    plot(x0, y0, c);
    if (x0 == x1 && y0 == y1) break;
    int e2 = 2 * err;
    if (e2 >= dy) { err += dy; x0 += sx; }
    if (e2 <= dx) { err += dx; y0 += sy; }
  }
}

static void rect(int x, int y, int w, int h, uint8_t c) {
  if (w <= 0 || h <= 0) return;
  hline(x, x + w - 1, y, c);
  hline(x, x + w - 1, y + h - 1, c);
  for (int j = 1; j < h - 1; j++) { plot(x, y + j, c); plot(x + w - 1, y + j, c); }
}

static void circle(int xc, int yc, int r, uint8_t c, bool fill) {
  int x = r, y = 0, err = 1 - r;
  while (x >= y) {
    if (fill) {
      hline(xc - x, xc + x, yc + y, c);
      hline(xc - x, xc + x, yc - y, c);
      hline(xc - y, xc + y, yc + x, c);
      hline(xc - y, xc + y, yc - x, c);
    } else {
      plot(xc + x, yc + y, c); plot(xc - x, yc + y, c);
      plot(xc + x, yc - y, c); plot(xc - x, yc - y, c);
      plot(xc + y, yc + x, c); plot(xc - y, yc + x, c);
      plot(xc + y, yc - x, c); plot(xc - y, yc - x, c);
    }
    y++;
    if (err < 0) err += 2 * y + 1;
    else { x--; err += 2 * (y - x) + 1; }
  }
}

static void copyRect(int sx, int sy, int w, int h, int dx, int dy) {
  int i0 = 0, i1 = w;
  if (-sx > i0) i0 = -sx;
  if (-dx > i0) i0 = -dx;
  if (GFX_W - sx < i1) i1 = GFX_W - sx;
  if (GFX_W - dx < i1) i1 = GFX_W - dx;
  if (i0 >= i1) return;
  bool up = dy > sy;   // copy bottom-up when moving down
  for (int k = 0; k < h; k++) {
    int r = up ? h - 1 - k : k;
    int ys = sy + r, yd = dy + r;
    if ((unsigned)ys >= GFX_H || (unsigned)yd >= GFX_H) continue;
    memmove(s_bitmap + yd * GFX_W + dx + i0, s_bitmap + ys * GFX_W + sx + i0, i1 - i0);
  }
}

static void gChar(int x, int y, uint8_t ch, uint8_t fg, uint8_t bg) {
  const uint8_t *g = s_font + ch * 16;
  for (int r = 0; r < 16; r++) {
    uint8_t bits = g[r];
    for (int i = 0; i < 8; i++) {
      if (bits & (0x80 >> i)) plot(x + i, y + r, fg);
      else if (!(bg & COLOR_TRANSPARENT)) plot(x + i, y + r, bg);
    }
  }
}

// ------------------------------------------------------------------ setup
static void makePointer() {
  static const char *art[16] = {
    "X               ",
    "XX              ",
    "X.X             ",
    "X..X            ",
    "X...X           ",
    "X....X          ",
    "X.....X         ",
    "X......X        ",
    "X.......X       ",
    "X........X      ",
    "X.....XXXXX     ",
    "X..X..X         ",
    "X.X X..X        ",
    "XX  X..X        ",
    "X    X..X       ",
    "     XXXX       ",
  };
  for (int y = 0; y < 16; y++)
    for (int x = 0; x < 16; x++) {
      char a = art[y][x];
      s_pointer[y * 16 + x] = a == 'X' ? 0x00 : a == '.' ? 0x3F : COLOR_TRANSPARENT;
    }
}

static void resetAll() {
  s_layers = LAYER_TEXT;
  s_backdrop = 0;
  s_scrollX = 0;
  s_scrollY = 0;
  s_pointerOn = false;
  s_fg = 0x3F;
  s_bg = 0x00;
  s_scrTop = 0;
  s_scrBot = TEXT_ROWS - 1;
  s_curMode = 1;
  memcpy(s_font, FONT8X16_DEFAULT, sizeof s_font);
  memset(s_bitmap, 0, sizeof s_bitmap);
  memset(s_patterns, COLOR_TRANSPARENT, sizeof s_patterns);
  memset(s_sprites, 0, sizeof s_sprites);
  textClear();
}

// ------------------------------------------------------------------ commands
// Number of fixed argument bytes for each opcode. 0xFF = unknown opcode.
static uint8_t s_argLen[256];

static void initArgTable() {
  memset(s_argLen, 0xFF, sizeof s_argLen);
  s_argLen[C_NOP] = 0;        s_argLen[C_RESET] = 0;     s_argLen[C_CLS] = 0;
  s_argLen[C_COLOR] = 2;      s_argLen[C_LOCATE] = 2;    s_argLen[C_CURSOR] = 1;
  s_argLen[C_SCROLLREGION] = 2; s_argLen[C_PUTRAW] = 1;  s_argLen[C_TEXTSCROLL] = 1;
  s_argLen[C_FILLTEXT] = 5;   s_argLen[C_DEFGLYPH] = 17; s_argLen[C_SETATTR] = 4;
  s_argLen[C_GETCHAR] = 2;    s_argLen[C_DEFAULTFONT] = 0;
  s_argLen[C_LAYERS] = 1;     s_argLen[C_BACKDROP] = 1;  s_argLen[C_WAITVBL] = 0;
  s_argLen[C_SCROLL] = 3;
  s_argLen[C_GCLS] = 1;       s_argLen[C_PLOT] = 4;      s_argLen[C_LINE] = 7;
  s_argLen[C_RECT] = 7;       s_argLen[C_FILLRECT] = 7;  s_argLen[C_CIRCLE] = 5;
  s_argLen[C_FILLCIRCLE] = 5; s_argLen[C_BLIT] = 6;      s_argLen[C_COPYRECT] = 9;
  s_argLen[C_GETPIXEL] = 3;   s_argLen[C_GTEXT] = 6;
  s_argLen[C_SPRDEF] = 1;     s_argLen[C_SPRSET] = 7;    s_argLen[C_SPRMOVE] = 5;
  s_argLen[C_SPRHIDE] = 1;    s_argLen[C_SPRHITS] = 1;   s_argLen[C_SPRPAT] = 2;
  s_argLen[C_INFO] = 0;       s_argLen[C_GETCURSOR] = 0; s_argLen[C_SYNC] = 0;
  s_argLen[C_MOUSEPTR] = 1;
}

static bool    s_inCmd = false;    // collecting arguments
static uint8_t s_cmd, s_argc, s_need;
static uint8_t s_args[24];
// Streamed payload after the fixed arguments (PUTRAW, BLIT, GTEXT, SPRDEF)
static uint32_t s_stream = 0;
static int s_bx, s_by, s_bx0, s_bw;

static inline int a16(int i) { return s_args[i] | (s_args[i + 1] << 8); }
static inline int s16(int i) { return (int16_t)(s_args[i] | (s_args[i + 1] << 8)); }

static void respond(uint8_t b) { resp.push(b); }

static void execute() {
  uint8_t *a = s_args;
  s_inCmd = false;
  switch (s_cmd) {
    case C_NOP: break;
    case C_RESET: resetAll(); break;   // the bus loop flushes resp
    case C_CLS: textClear(); break;
    case C_COLOR: s_fg = a[0] & 0x3F; s_bg = a[1] & 0x7F; break;
    case C_LOCATE:
      s_curCol = a[0] < TEXT_COLS ? a[0] : TEXT_COLS - 1;
      s_curRow = a[1] < TEXT_ROWS ? a[1] : TEXT_ROWS - 1;
      break;
    case C_CURSOR: s_curMode = a[0] > 2 ? 2 : a[0]; break;
    case C_SCROLLREGION: {
      int t = a[0], b = a[1];
      if (b >= TEXT_ROWS) b = TEXT_ROWS - 1;
      if (t > b) t = b;
      s_scrTop = t; s_scrBot = b;
      if (s_curRow < t || s_curRow > b) s_curRow = t;
      break;
    }
    case C_PUTRAW: s_stream = a[0]; if (s_stream) s_inCmd = true; break;
    case C_TEXTSCROLL:
      if (a[0] == 1) textScrollDown(s_scrTop, s_scrBot); else textScrollUp(s_scrTop, s_scrBot);
      break;
    case C_FILLTEXT:
    case C_SETATTR: {
      int c0 = a[0], r0 = a[1], w = a[2], h = a[3];
      for (int r = r0; r < r0 + h && r < TEXT_ROWS; r++)
        for (int c = c0; c < c0 + w && c < TEXT_COLS; c++) {
          int i = r * TEXT_COLS + c;
          if (s_cmd == C_FILLTEXT) s_textCh[i] = a[4];
          s_textFg[i] = s_fg;
          s_textBg[i] = s_bg;
        }
      break;
    }
    case C_DEFGLYPH: memcpy(s_font + a[0] * 16, a + 1, 16); break;
    case C_GETCHAR: {
      int c = a[0] < TEXT_COLS ? a[0] : TEXT_COLS - 1, r = a[1] < TEXT_ROWS ? a[1] : TEXT_ROWS - 1;
      int i = r * TEXT_COLS + c;
      respond(s_textCh[i]); respond(s_textFg[i]); respond(s_textBg[i]);
      break;
    }
    case C_DEFAULTFONT: memcpy(s_font, FONT8X16_DEFAULT, sizeof s_font); break;

    case C_LAYERS: s_layers = a[0] & 7; break;
    case C_BACKDROP: s_backdrop = a[0] & 0x3F; break;
    case C_WAITVBL: {
      uint32_t f = frameCount;
      while (frameCount == f) vTaskDelay(1);
      break;
    }
    case C_SCROLL: {
      int x = a16(0) % GFX_W, y = a[2] % GFX_H;
      s_scrollX = x; s_scrollY = y;
      break;
    }

    case C_GCLS: memset(s_bitmap, a[0] & 0x3F, sizeof s_bitmap); break;
    case C_PLOT: plot(a16(0), a[2], a[3] & 0x3F); break;
    case C_LINE: line(a16(0), a[2], a16(3), a[5], a[6] & 0x3F); break;
    case C_RECT: rect(a16(0), a[2], a16(3), a[5], a[6] & 0x3F); break;
    case C_FILLRECT: fillRect(a16(0), a[2], a16(3), a[5], a[6] & 0x3F); break;
    case C_CIRCLE: circle(a16(0), a[2], a[3], a[4] & 0x3F, false); break;
    case C_FILLCIRCLE: circle(a16(0), a[2], a[3], a[4] & 0x3F, true); break;
    case C_BLIT:
      s_bx0 = s_bx = a16(0); s_by = a[2]; s_bw = a16(3);
      s_stream = (uint32_t)s_bw * a[5];
      if (s_stream) s_inCmd = true;
      break;
    case C_COPYRECT: copyRect(a16(0), a[2], a16(3), a[5], a16(6), a[8]); break;
    case C_GETPIXEL: {
      int x = a16(0), y = a[2];
      respond(((unsigned)x < GFX_W && (unsigned)y < GFX_H) ? s_bitmap[y * GFX_W + x] : 0);
      break;
    }
    case C_GTEXT:
      s_bx = a16(0); s_by = a[2];
      s_stream = a[5];
      if (s_stream) s_inCmd = true;
      break;

    case C_SPRDEF:
      s_bx = 0;
      s_stream = SPRITE_SIZE * SPRITE_SIZE;
      s_inCmd = true;
      break;
    case C_SPRSET:
      if (a[0] < NUM_SPRITES) {
        Sprite &s = s_sprites[a[0]];
        s.pattern = a[1] & (NUM_PATTERNS - 1);
        s.x = s16(2); s.y = s16(4);
        s.flags = a[6];
      }
      break;
    case C_SPRMOVE:
      if (a[0] < NUM_SPRITES) { s_sprites[a[0]].x = s16(1); s_sprites[a[0]].y = s16(3); }
      break;
    case C_SPRHIDE:
      if (a[0] == 0xFF) for (auto &s : s_sprites) s.flags &= ~1;
      else if (a[0] < NUM_SPRITES) s_sprites[a[0]].flags &= ~1;
      break;
    case C_SPRHITS: {
      uint16_t mask = 0;
      if (a[0] < NUM_SPRITES && (s_sprites[a[0]].flags & 1)) {
        const Sprite &me = s_sprites[a[0]];
        for (int j = 0; j < NUM_SPRITES; j++) {
          const Sprite &o = s_sprites[j];
          if (j == a[0] || !(o.flags & 1)) continue;
          if (abs(o.x - me.x) < SPRITE_SIZE && abs(o.y - me.y) < SPRITE_SIZE) mask |= 1u << j;
        }
      }
      respond(mask & 0xFF); respond(mask >> 8);
      break;
    }
    case C_SPRPAT:
      if (a[0] < NUM_SPRITES) s_sprites[a[0]].pattern = a[1] & (NUM_PATTERNS - 1);
      break;

    case C_INFO:
      respond('V'); respond(FW_VERSION_MAJOR); respond(FW_VERSION_MINOR);
      respond(TEXT_COLS); respond(TEXT_ROWS);
      respond(GFX_W & 0xFF); respond(GFX_W >> 8); respond(GFX_H);
      break;
    case C_GETCURSOR: respond(s_curCol); respond(s_curRow); break;
    case C_SYNC: respond(0xAA); break;
    case C_MOUSEPTR: s_pointerOn = a[0] != 0; break;
  }
}

// One byte of streamed payload for the current command.
static void streamByte(uint8_t v) {
  switch (s_cmd) {
    case C_PUTRAW: putGlyph(v); break;
    case C_BLIT:
      if (!(v & COLOR_TRANSPARENT)) plot(s_bx, s_by, v);
      if (++s_bx >= s_bx0 + s_bw) { s_bx = s_bx0; s_by++; }
      break;
    case C_GTEXT:
      gChar(s_bx, s_by, v, s_args[3] & 0x3F, s_args[4]);
      s_bx += 8;
      break;
    case C_SPRDEF:
      s_patterns[s_args[0] & (NUM_PATTERNS - 1)][s_bx++] = v;
      break;
  }
  if (--s_stream == 0) s_inCmd = false;
}

static void handle(uint16_t e) {
  uint8_t v = e & 0xFF;
  if ((e >> 8) == 0) {               // command register
    s_cmd = v;
    s_argc = 0;
    s_stream = 0;
    s_need = s_argLen[v];
    if (s_need == 0xFF) { s_inCmd = false; return; }  // unknown: ignore
    s_inCmd = true;
    if (s_need == 0) execute();
    return;
  }
  // data register
  if (!s_inCmd) { termPutc(v); return; }
  if (s_stream) { streamByte(v); return; }
  s_args[s_argc++] = v;
  if (s_argc >= s_need) execute();
}

// ------------------------------------------------------------------ task
static void videoTask(void *) {
  esp_lcd_rgb_panel_config_t cfg = {};
  cfg.clk_src = LCD_CLK_SRC_DEFAULT;
  cfg.timings.pclk_hz = VGA_PCLK_HZ;
  cfg.timings.h_res = VGA_H_RES;
  cfg.timings.v_res = VGA_V_RES;
  cfg.timings.hsync_pulse_width = VGA_HSYNC;
  cfg.timings.hsync_back_porch = VGA_HBP;
  cfg.timings.hsync_front_porch = VGA_HFP;
  cfg.timings.vsync_pulse_width = VGA_VSYNC;
  cfg.timings.vsync_back_porch = VGA_VBP;
  cfg.timings.vsync_front_porch = VGA_VFP;
  // VGA 640x480 uses negative sync pulses: idle high, so *_idle_low = 0.
  cfg.data_width = 8;
  cfg.bits_per_pixel = 8;
  cfg.bounce_buffer_size_px = VGA_H_RES * VGA_BOUNCE_LINES;
  cfg.hsync_gpio_num = PIN_VGA_HSYNC;
  cfg.vsync_gpio_num = PIN_VGA_VSYNC;
  cfg.de_gpio_num = -1;
  cfg.pclk_gpio_num = -1;
  cfg.disp_gpio_num = -1;
  for (int i = 0; i < SOC_LCDCAM_RGB_DATA_WIDTH; i++) cfg.data_gpio_nums[i] = -1;
  // Pixel byte 0b00RRGGBB: bit n of the byte drives data line n.
  cfg.data_gpio_nums[0] = PIN_VGA_B0;
  cfg.data_gpio_nums[1] = PIN_VGA_B1;
  cfg.data_gpio_nums[2] = PIN_VGA_G0;
  cfg.data_gpio_nums[3] = PIN_VGA_G1;
  cfg.data_gpio_nums[4] = PIN_VGA_R0;
  cfg.data_gpio_nums[5] = PIN_VGA_R1;
  cfg.flags.no_fb = 1;

  esp_lcd_panel_handle_t panel = nullptr;
  ESP_ERROR_CHECK(esp_lcd_new_rgb_panel(&cfg, &panel));
  esp_lcd_rgb_panel_event_callbacks_t cbs = {};
  cbs.on_vsync = onVsync;
  cbs.on_bounce_empty = onBounceEmpty;
  ESP_ERROR_CHECK(esp_lcd_rgb_panel_register_event_callbacks(panel, &cbs, nullptr));
  ESP_ERROR_CHECK(esp_lcd_panel_reset(panel));
  ESP_ERROR_CHECK(esp_lcd_panel_init(panel));
  ready = true;
  ESP_LOGI(TAG, "VGA 640x480 running");

  TickType_t lastYield = xTaskGetTickCount();
  for (;;) {
    uint16_t e;
    int n = 0;
    idle = false;
    while (fifo.pop(e)) {
      handle(e);
      // Let the core 0 idle task run now and then (task watchdog).
      if (++n >= 512) {
        n = 0;
        if (xTaskGetTickCount() - lastYield >= pdMS_TO_TICKS(50)) {
          vTaskDelay(1);
          lastYield = xTaskGetTickCount();
        }
      }
    }
    idle = true;
    s_sleeping = true;
    if (fifo.empty()) ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(10));
    s_sleeping = false;
    lastYield = xTaskGetTickCount();
  }
}

void kick() {
  if (s_sleeping) {
    s_sleeping = false;
    xTaskNotifyGive(s_task);
  }
}

void begin() {
  initArgTable();
  makePointer();
  resetAll();
  // Created on core 0 so the LCD interrupt is allocated there too.
  xTaskCreatePinnedToCore(videoTask, "video", 4096, nullptr, 2, &s_task, 0);   // below input tasks
}

} // namespace video
