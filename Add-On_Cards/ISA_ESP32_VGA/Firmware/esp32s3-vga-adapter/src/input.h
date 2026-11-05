// Keyboard and mouse state shared by the PS/2 and USB drivers.
// Producers (PS/2 task, USB task) run on core 0; the 6502 bus loop on core 1
// consumes keys and reads the mouse.
#pragma once
#include <stdint.h>

namespace input {

// Key codes. Printable keys use their unshifted ASCII value ('a', '1', ';',
// ' ', 0x0D Enter, 0x08 Backspace, 0x09 Tab, 0x1B Esc, 0x7F Delete).
// The key queue (register 2) returns the shifted / ctrl-translated ASCII for
// printable keys and these codes for the others.
enum : uint8_t {
  K_UP = 0x80, K_DOWN, K_LEFT, K_RIGHT, K_HOME, K_END, K_PGUP, K_PGDN, K_INS,
  K_F1 = 0x90, K_F2, K_F3, K_F4, K_F5, K_F6, K_F7, K_F8, K_F9, K_F10, K_F11, K_F12,
  K_LSHIFT = 0xA0, K_RSHIFT, K_LCTRL, K_RCTRL, K_LALT, K_RALT, K_CAPS, K_NUMLOCK,
  K_SCROLL, K_GUI, K_MENU, K_PRTSC, K_PAUSE,
};

// Keyboard LED bits (PS/2 order)
enum : uint8_t { LED_SCROLL = 1, LED_NUM = 2, LED_CAPS = 4 };

void begin();

// --- producer side (core 0) ---
void keyEvent(uint8_t code, bool down);   // code from the table above
void keyRepeat(uint8_t code);             // software typematic (USB)
void mouseEvent(int dx, int dy, uint8_t buttons);  // dy > 0 = down
uint8_t leds();                           // current LED state
extern volatile uint32_t ledsVersion;     // bumped when leds() changes

// --- consumer side (core 1) ---
bool keyAvailable();
uint8_t popKey();                         // 0 if empty
void flushKeys();
bool isDown(uint8_t code);
uint8_t modifiers();                      // b0 shift b1 ctrl b2 alt b3 caps
bool mouseChanged();
void mouseRead(uint8_t out[5]);           // buttons, x lo, x hi, y lo, y hi
void mouseDelta(uint8_t out[3]);          // buttons, dx, dy (signed, since last)
void mouseSetBounds(int xmax, int ymax);
void mouseSetPos(int x, int y);

// Read by the video ISR to draw the pointer (320x240 coordinates).
extern volatile int16_t mouseX, mouseY;

} // namespace input
