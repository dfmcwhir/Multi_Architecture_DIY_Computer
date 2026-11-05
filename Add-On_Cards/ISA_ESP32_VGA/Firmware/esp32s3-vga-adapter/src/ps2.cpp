// PS/2 host driver for one keyboard and one mouse.
#include "ps2.h"
#include "input.h"
#include "ring.h"
#include "config.h"

#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/gpio.h"
#include "soc/gpio_reg.h"
#include "esp_timer.h"
#include "esp_rom_sys.h"
#include "esp_log.h"

static const char *TAG = "ps2";

namespace ps2 {

struct Port {
  uint8_t clk, dat;
  Ring<uint8_t, 64> rx;
  // receive state (ISR)
  uint8_t bits = 0, shift = 0, parity = 0;
  int64_t lastUs = 0;
  // transmit state: 0 idle, 1 sending, 2 host is inhibiting the clock
  volatile uint8_t tx = 0;
  uint8_t txBit = 0, txByte = 0;
  volatile bool txAck = false;
};

static Port s_kbd, s_mouse;

static inline void IRAM_ATTR pinHigh(uint8_t p) { REG_WRITE(GPIO_OUT_W1TS_REG, 1u << p); }
static inline void IRAM_ATTR pinLow(uint8_t p)  { REG_WRITE(GPIO_OUT_W1TC_REG, 1u << p); }
static inline int  IRAM_ATTR pinRead(uint8_t p) { return (REG_READ(GPIO_IN_REG) >> p) & 1; }

// Falling edge of the device clock.
static void IRAM_ATTR clkIsr(void *arg) {
  Port *p = (Port *)arg;
  int64_t now = esp_timer_get_time();
  if (p->tx == 2) return;            // our own inhibit pulse
  if (p->tx == 1) {
    uint8_t b = p->txBit++;
    if (b < 8) {
      if ((p->txByte >> b) & 1) pinHigh(p->dat); else pinLow(p->dat);
    } else if (b == 8) {             // odd parity
      if (__builtin_parity(p->txByte)) pinLow(p->dat); else pinHigh(p->dat);
    } else if (b == 9) {             // stop bit: release data
      pinHigh(p->dat);
    } else {                          // device acknowledge
      p->txAck = pinRead(p->dat) == 0;
      p->tx = 0;
      p->bits = 0;
      p->lastUs = now;
    }
    return;
  }
  if (now - p->lastUs > 250) p->bits = 0;   // stale partial frame
  p->lastUs = now;
  int d = pinRead(p->dat);
  if (p->bits == 0) {
    if (d == 0) { p->bits = 1; p->shift = 0; p->parity = 0; }
  } else if (p->bits <= 8) {
    p->shift |= d << (p->bits - 1);
    p->parity += d;
    p->bits++;
  } else if (p->bits == 9) {
    p->parity += d;
    p->bits++;
  } else {
    if (d == 1 && (p->parity & 1)) p->rx.push(p->shift);
    p->bits = 0;
  }
}

// Send one byte to the device. Returns true if the device acknowledged the
// frame; the device's 0xFA reply arrives later through the receive ring.
static bool sendRaw(Port &p, uint8_t b) {
  p.txByte = b;
  p.txBit = 0;
  p.txAck = false;
  p.tx = 2;
  pinLow(p.clk);                 // request-to-send
  esp_rom_delay_us(120);
  pinLow(p.dat);                 // start bit
  p.tx = 1;
  pinHigh(p.clk);                // release clock; device clocks the bits in
  for (int i = 0; i < 25 && p.tx; i++) vTaskDelay(1);
  if (p.tx) {                    // no device / timeout: clean up
    p.tx = 0;
    pinHigh(p.dat);
    pinHigh(p.clk);
    return false;
  }
  return p.txAck;
}

// Wait for a byte from the device.
static bool readByte(Port &p, uint8_t &b, int ms) {
  for (int i = 0; i <= ms; i++) {
    if (p.rx.pop(b)) return true;
    vTaskDelay(1);
  }
  return false;
}

// Send a command byte and wait for the 0xFA acknowledge.
static bool command(Port &p, uint8_t b) {
  for (int attempt = 0; attempt < 3; attempt++) {
    if (!sendRaw(p, b)) continue;
    uint8_t r;
    while (readByte(p, r, 50)) {
      if (r == 0xFA) return true;
      if (r == 0xFE) break;      // resend request
    }
  }
  return false;
}

// ---------------------------------------------------------------- keyboard
// Scan code set 2 -> key code (see input.h)
static uint8_t s_set2[0x90];
static uint8_t s_set2e0[0x80];

static void buildTables() {
  struct M { uint8_t sc, code; };
  static const M n[] = {
    {0x76,0x1B},{0x05,input::K_F1},{0x06,input::K_F2},{0x04,input::K_F3},{0x0C,input::K_F4},
    {0x03,input::K_F5},{0x0B,input::K_F6},{0x83,input::K_F7},{0x0A,input::K_F8},
    {0x01,input::K_F9},{0x09,input::K_F10},{0x78,input::K_F11},{0x07,input::K_F12},
    {0x0E,'`'},{0x16,'1'},{0x1E,'2'},{0x26,'3'},{0x25,'4'},{0x2E,'5'},{0x36,'6'},{0x3D,'7'},
    {0x3E,'8'},{0x46,'9'},{0x45,'0'},{0x4E,'-'},{0x55,'='},{0x66,0x08},
    {0x0D,0x09},{0x15,'q'},{0x1D,'w'},{0x24,'e'},{0x2D,'r'},{0x2C,'t'},{0x35,'y'},{0x3C,'u'},
    {0x43,'i'},{0x44,'o'},{0x4D,'p'},{0x54,'['},{0x5B,']'},{0x5D,'\\'},
    {0x58,input::K_CAPS},{0x1C,'a'},{0x1B,'s'},{0x23,'d'},{0x2B,'f'},{0x34,'g'},{0x33,'h'},
    {0x3B,'j'},{0x42,'k'},{0x4B,'l'},{0x4C,';'},{0x52,'\''},{0x5A,0x0D},
    {0x12,input::K_LSHIFT},{0x1A,'z'},{0x22,'x'},{0x21,'c'},{0x2A,'v'},{0x32,'b'},{0x31,'n'},
    {0x3A,'m'},{0x41,','},{0x49,'.'},{0x4A,'/'},{0x59,input::K_RSHIFT},
    {0x14,input::K_LCTRL},{0x11,input::K_LALT},{0x29,' '},
    {0x77,input::K_NUMLOCK},{0x7E,input::K_SCROLL},
    {0x7C,'*'},{0x7B,'-'},{0x79,'+'},{0x71,'.'},{0x70,'0'},{0x69,'1'},{0x72,'2'},{0x7A,'3'},
    {0x6B,'4'},{0x73,'5'},{0x74,'6'},{0x6C,'7'},{0x75,'8'},{0x7D,'9'},
  };
  static const M e[] = {
    {0x75,input::K_UP},{0x72,input::K_DOWN},{0x6B,input::K_LEFT},{0x74,input::K_RIGHT},
    {0x6C,input::K_HOME},{0x69,input::K_END},{0x7D,input::K_PGUP},{0x7A,input::K_PGDN},
    {0x70,input::K_INS},{0x71,0x7F},{0x5A,0x0D},{0x4A,'/'},{0x14,input::K_RCTRL},
    {0x11,input::K_RALT},{0x1F,input::K_GUI},{0x27,input::K_GUI},{0x2F,input::K_MENU},
    {0x7C,input::K_PRTSC},
  };
  for (auto &m : n) s_set2[m.sc] = m.code;
  for (auto &m : e) s_set2e0[m.sc] = m.code;
}

struct KbdState { bool e0 = false, f0 = false; uint8_t skip = 0; };

static void kbdByte(KbdState &s, uint8_t b) {
  if (s.skip) { s.skip--; return; }
  switch (b) {
    case 0xE0: s.e0 = true; return;
    case 0xF0: s.f0 = true; return;
    case 0xE1:                      // Pause: E1 14 77 E1 F0 14 F0 77
      s.skip = 7;
      input::keyEvent(input::K_PAUSE, true);
      input::keyEvent(input::K_PAUSE, false);
      return;
    case 0xAA: case 0xFA: case 0xEE: case 0xFE: case 0x00: case 0xFF:
      s.e0 = s.f0 = false;
      return;
  }
  uint8_t code = 0;
  if (s.e0) { if (b < sizeof s_set2e0) code = s_set2e0[b]; }
  else if (b < sizeof s_set2) code = s_set2[b];
  if (s.e0 && b == 0x12) code = 0;  // fake shift around Print Screen
  bool down = !s.f0;
  s.e0 = s.f0 = false;
  if (code) input::keyEvent(code, down);
}

static void setLeds(uint8_t leds) {
  if (command(s_kbd, 0xED)) command(s_kbd, leds);
}

// ---------------------------------------------------------------- mouse
static bool mouseInit() {
  uint8_t b;
  while (s_mouse.rx.pop(b)) {}
  if (!command(s_mouse, 0xFF)) return false;          // reset
  if (!readByte(s_mouse, b, 1000) || b != 0xAA) return false;
  readByte(s_mouse, b, 100);                            // device id 00
  command(s_mouse, 0xF3); command(s_mouse, 100);        // 100 samples/s
  return command(s_mouse, 0xF4);                        // enable reporting
}

// ---------------------------------------------------------------- task
static void ps2Task(void *) {
  buildTables();
  vTaskDelay(pdMS_TO_TICKS(600));   // let devices finish their power-on test
  uint8_t b;
  while (s_kbd.rx.pop(b)) {}
  bool kbdOk = command(s_kbd, 0xFF);
  if (kbdOk) readByte(s_kbd, b, 1000);   // 0xAA
  setLeds(0);
  bool mouseOk = mouseInit();
  ESP_LOGI(TAG, "keyboard %s, mouse %s", kbdOk ? "ok" : "not found", mouseOk ? "ok" : "not found");

  KbdState ks;
  uint32_t ledsSeen = input::ledsVersion;
  uint8_t pkt[3];
  int pktLen = 0;
  TickType_t lastMouseByte = 0, lastProbe = xTaskGetTickCount();

  for (;;) {
    bool any = false;
    while (s_kbd.rx.pop(b)) {
      any = true;
      if (b == 0xAA) ledsSeen = input::ledsVersion - 1;  // hot-plugged: restore LEDs
      kbdByte(ks, b);
    }
    if (ledsSeen != input::ledsVersion) {
      ledsSeen = input::ledsVersion;
      setLeds(input::leds());
    }

    while (s_mouse.rx.pop(b)) {
      any = true;
      TickType_t now = xTaskGetTickCount();
      if (now - lastMouseByte > pdMS_TO_TICKS(20)) pktLen = 0;   // resync on gaps
      lastMouseByte = now;
      if (pktLen == 0 && !(b & 0x08)) continue;                    // bit 3 always set
      pkt[pktLen++] = b;
      if (pktLen == 2 && pkt[0] == 0xAA && pkt[1] == 0x00) {       // mouse re-plugged
        pktLen = 0;
        mouseOk = mouseInit();
        continue;
      }
      if (pktLen == 3) {
        pktLen = 0;
        if (pkt[0] & 0xC0) continue;                               // overflow
        int dx = pkt[1] - ((pkt[0] << 4) & 0x100);
        int dy = pkt[2] - ((pkt[0] << 3) & 0x100);
        input::mouseEvent(dx, -dy, pkt[0] & 7);
      }
    }

    // Retry a missing mouse now and then so it can be plugged in later.
    if (!mouseOk && xTaskGetTickCount() - lastProbe > pdMS_TO_TICKS(3000)) {
      lastProbe = xTaskGetTickCount();
      mouseOk = mouseInit();
      if (mouseOk) ESP_LOGI(TAG, "mouse found");
    }
    if (!any) vTaskDelay(pdMS_TO_TICKS(2));
  }
}

static void setupPort(Port &p, uint8_t clk, uint8_t dat) {
  p.clk = clk;
  p.dat = dat;
  gpio_config_t io = {};
  io.pin_bit_mask = (1ULL << clk) | (1ULL << dat);
  io.mode = GPIO_MODE_INPUT_OUTPUT_OD;
  io.pull_up_en = GPIO_PULLUP_ENABLE;   // weak; the level shifter has the real pull-ups
  io.intr_type = GPIO_INTR_DISABLE;
  gpio_config(&io);
  pinHigh(clk);
  pinHigh(dat);
  gpio_set_intr_type((gpio_num_t)clk, GPIO_INTR_NEGEDGE);
  gpio_isr_handler_add((gpio_num_t)clk, clkIsr, &p);
}

void begin() {
  // Level 3 so these short handlers preempt anything else on core 1.
  esp_err_t err = gpio_install_isr_service(ESP_INTR_FLAG_LEVEL3 | ESP_INTR_FLAG_IRAM);
  if (err != ESP_OK && err != ESP_ERR_INVALID_STATE) ESP_LOGE(TAG, "isr service: %d", err);
  setupPort(s_kbd, PIN_KBD_CLK, PIN_KBD_DAT);
  setupPort(s_mouse, PIN_MOUSE_CLK, PIN_MOUSE_DAT);
  xTaskCreatePinnedToCore(ps2Task, "ps2", 3072, nullptr, 4, nullptr, 0);
}

} // namespace ps2
