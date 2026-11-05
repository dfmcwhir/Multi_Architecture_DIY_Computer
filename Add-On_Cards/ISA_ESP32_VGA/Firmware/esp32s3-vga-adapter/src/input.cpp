// Keyboard translation, key queue and mouse state.
#include "input.h"
#include "ring.h"
#include "config.h"
#include "freertos/FreeRTOS.h"
#include <string.h>

namespace input {

static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;
static Ring<uint8_t, 64> s_keys;
static uint8_t s_down[32];                  // bitmap of keys held, by key code
static uint8_t s_shift, s_ctrl, s_alt;      // counts of held modifier keys
static uint8_t s_leds = 0;
volatile uint32_t ledsVersion = 0;

volatile int16_t mouseX = GFX_W / 2, mouseY = GFX_H / 2;
static int s_maxX = GFX_W - 1, s_maxY = GFX_H - 1;
static int s_dx = 0, s_dy = 0;
static uint8_t s_buttons = 0;
static volatile bool s_mouseChanged = false;

// US layout shifted characters for the unshifted ASCII range 0x20..0x7E.
static char shifted(char c) {
  static const char from[] = "`1234567890-=[]\\;',./";
  static const char to[]   = "~!@#$%^&*()_+{}|:\"<>?";
  if (c >= 'a' && c <= 'z') return c - 32;
  const char *p = strchr(from, c);
  return p ? to[p - from] : c;
}

void begin() {}

uint8_t leds() { return s_leds; }

static uint8_t translate(uint8_t code) {
  if (code >= 0x80) return code;              // specials pass through
  char c = code;
  bool letter = c >= 'a' && c <= 'z';
  bool sh = s_shift != 0;
  if (letter && (s_leds & LED_CAPS)) sh = !sh;
  if (sh && c >= 0x20) c = shifted(c);
  if (s_ctrl) {
    if (letter) return code - 'a' + 1;        // Ctrl-A .. Ctrl-Z = 1..26
    switch (code) {
      case '[': return 0x1B; case '\\': return 0x1C; case ']': return 0x1D;
      case '6': return 0x1E; case '-': return 0x1F; case ' ': return 0x00;
    }
  }
  return (uint8_t)c;
}

static void enqueue(uint8_t code) {
  if (code >= K_LSHIFT) return;               // modifiers / locks: no character
  uint8_t ch = translate(code);
  if (ch == 0 && code != ' ') return;
  s_keys.push(ch);
}

void keyEvent(uint8_t code, bool down) {
  portENTER_CRITICAL(&s_mux);
  bool was = s_down[code >> 3] & (1 << (code & 7));
  if (down) s_down[code >> 3] |= 1 << (code & 7);
  else s_down[code >> 3] &= ~(1 << (code & 7));
  switch (code) {
    case K_LSHIFT: case K_RSHIFT: if (down != was) s_shift += down ? 1 : -1; break;
    case K_LCTRL: case K_RCTRL:   if (down != was) s_ctrl += down ? 1 : -1; break;
    case K_LALT: case K_RALT:     if (down != was) s_alt += down ? 1 : -1; break;
    case K_CAPS:    if (down && !was) { s_leds ^= LED_CAPS; ledsVersion = ledsVersion + 1; } break;
    case K_NUMLOCK: if (down && !was) { s_leds ^= LED_NUM; ledsVersion = ledsVersion + 1; } break;
    case K_SCROLL:  if (down && !was) { s_leds ^= LED_SCROLL; ledsVersion = ledsVersion + 1; } break;
    default:
      if (down) enqueue(code);   // includes PS/2 typematic repeats
      break;
  }
  portEXIT_CRITICAL(&s_mux);
}

void keyRepeat(uint8_t code) {
  portENTER_CRITICAL(&s_mux);
  if (s_down[code >> 3] & (1 << (code & 7))) enqueue(code);
  portEXIT_CRITICAL(&s_mux);
}

void mouseEvent(int dx, int dy, uint8_t buttons) {
  portENTER_CRITICAL(&s_mux);
  int x = mouseX + dx, y = mouseY + dy;
  if (x < 0) x = 0;
  if (x > s_maxX) x = s_maxX;
  if (y < 0) y = 0;
  if (y > s_maxY) y = s_maxY;
  mouseX = x;
  mouseY = y;
  s_dx += dx;
  s_dy += dy;
  s_buttons = buttons;
  s_mouseChanged = true;
  portEXIT_CRITICAL(&s_mux);
}

bool keyAvailable() { return !s_keys.empty(); }
uint8_t popKey() { uint8_t c = 0; s_keys.pop(c); return c; }
void flushKeys() { s_keys.clear(); }
bool isDown(uint8_t code) { return s_down[code >> 3] & (1 << (code & 7)); }
uint8_t modifiers() {
  return (s_shift ? 1 : 0) | (s_ctrl ? 2 : 0) | (s_alt ? 4 : 0) | ((s_leds & LED_CAPS) ? 8 : 0);
}
bool mouseChanged() { return s_mouseChanged; }

void mouseRead(uint8_t out[5]) {
  portENTER_CRITICAL(&s_mux);
  out[0] = s_buttons;
  out[1] = mouseX & 0xFF; out[2] = mouseX >> 8;
  out[3] = mouseY & 0xFF; out[4] = mouseY >> 8;
  s_mouseChanged = false;
  portEXIT_CRITICAL(&s_mux);
}

void mouseDelta(uint8_t out[3]) {
  portENTER_CRITICAL(&s_mux);
  int dx = s_dx < -128 ? -128 : s_dx > 127 ? 127 : s_dx;
  int dy = s_dy < -128 ? -128 : s_dy > 127 ? 127 : s_dy;
  out[0] = s_buttons;
  out[1] = (uint8_t)(int8_t)dx;
  out[2] = (uint8_t)(int8_t)dy;
  s_dx = s_dy = 0;
  s_mouseChanged = false;
  portEXIT_CRITICAL(&s_mux);
}

void mouseSetBounds(int xmax, int ymax) {
  portENTER_CRITICAL(&s_mux);
  s_maxX = xmax; s_maxY = ymax;
  if (mouseX > xmax) mouseX = xmax;
  if (mouseY > ymax) mouseY = ymax;
  portEXIT_CRITICAL(&s_mux);
}

void mouseSetPos(int x, int y) {
  portENTER_CRITICAL(&s_mux);
  mouseX = x < 0 ? 0 : x > s_maxX ? s_maxX : x;
  mouseY = y < 0 ? 0 : y > s_maxY ? s_maxY : y;
  portEXIT_CRITICAL(&s_mux);
}

} // namespace input
