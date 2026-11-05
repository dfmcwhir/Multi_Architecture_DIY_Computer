// VGA output (640x480@60) and the display command processor.
#pragma once
#include <stdint.h>
#include "config.h"
#include "ring.h"

namespace video {

// Layer enable bits (command 0x10 LAYERS)
enum : uint8_t { LAYER_TEXT = 0x01, LAYER_BITMAP = 0x02, LAYER_SPRITES = 0x04 };

// Display command opcodes (written to register 0, arguments to register 1).
enum : uint8_t {
  C_NOP = 0x00, C_RESET = 0x01, C_CLS = 0x02, C_COLOR = 0x03, C_LOCATE = 0x04,
  C_CURSOR = 0x05, C_SCROLLREGION = 0x06, C_PUTRAW = 0x07, C_TEXTSCROLL = 0x08,
  C_FILLTEXT = 0x09, C_DEFGLYPH = 0x0A, C_SETATTR = 0x0B, C_GETCHAR = 0x0D,
  C_DEFAULTFONT = 0x0E,
  C_LAYERS = 0x10, C_BACKDROP = 0x11, C_WAITVBL = 0x12, C_SCROLL = 0x13,
  C_GCLS = 0x20, C_PLOT = 0x21, C_LINE = 0x22, C_RECT = 0x23, C_FILLRECT = 0x24,
  C_CIRCLE = 0x25, C_FILLCIRCLE = 0x26, C_BLIT = 0x27, C_COPYRECT = 0x28,
  C_GETPIXEL = 0x29, C_GTEXT = 0x2B,
  C_SPRDEF = 0x30, C_SPRSET = 0x31, C_SPRMOVE = 0x32, C_SPRHIDE = 0x33,
  C_SPRHITS = 0x34, C_SPRPAT = 0x35,
  C_INFO = 0x40, C_GETCURSOR = 0x41, C_SYNC = 0x42,
  C_MOUSEPTR = 0x50,
};

// FIFO entries are (register << 8) | value, register 0 = command, 1 = data.
extern Ring<uint16_t, VIDEO_FIFO_SIZE> fifo;
// Bytes returned by query commands, read by the 6502 from register 1.
extern Ring<uint8_t, 256> resp;

extern volatile uint32_t frameCount;   // incremented every vertical sync
extern volatile uint8_t  vblFlag;      // set every vsync, cleared by STATUS read
extern volatile bool     idle;         // command processor waiting for work
extern volatile bool     ready;        // VGA running

// Start the VGA output and the command task. Both live on core 0.
void begin();
// Wake the command task after pushing into the FIFO (cheap if it is awake).
void kick();

} // namespace video
