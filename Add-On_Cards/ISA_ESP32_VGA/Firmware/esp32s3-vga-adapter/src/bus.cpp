// 6502 bus handler. Runs forever on core 1.
//
// Handshake (see README for the glue logic):
//   * /CS goes low -> the GAL pulls RDY low while ACK is low, so the
//     65C02 freezes in the middle of the access with address, R/W and (for
//     writes) data held stable.
//   * Read:  the ESP32 drives D0-D7 on its side of the 74LVC8T245, raises ACK.
//            RDY goes high and the CPU latches the data at the end of PHI2.
//   * Write: the ESP32 samples D0-D7 during a PHI2-high phase, raises ACK.
//   * When /CS goes high again (cycle finished) ACK drops, ready for the next.
#pragma GCC optimize("O2")

#include "bus.h"
#include "config.h"
#include "ring.h"
#include "video.h"
#include "input.h"
#include "audio.h"

#include <string.h>
#include "driver/gpio.h"
#include "soc/gpio_reg.h"
#include "freertos/FreeRTOS.h"
#include "esp_attr.h"

namespace bus {

static const uint32_t M_D    = 0xFFu << PIN_D0;
static const uint32_t M_NCS  = 1u << PIN_NCS;
static const uint32_t M_RW   = 1u << PIN_RW;
static const uint32_t M_PHI2 = 1u << PIN_PHI2;
static const uint32_t M_ACK  = 1u << PIN_ACK;
static const uint32_t M_IRQ  = 1u << PIN_IRQ;

static_assert(PIN_D0 + 7 < 32 && PIN_NCS < 32 && PIN_PHI2 < 32 && PIN_ACK < 32 && PIN_IRQ < 32,
              "bus pins must be GPIO0..31");
static_assert(PIN_A1 == PIN_A0 + 1, "A1 must follow A0");

static Ring<uint8_t, 64> s_ioResp;
static uint8_t s_irqMask = 0;
static uint8_t s_ioCmd = 0, s_ioNeed = 0, s_ioArgc = 0;
static bool s_ioActive = false;
static uint8_t s_ioArgs[8];
static uint8_t s_ioLen[256];

#define IN() REG_READ(GPIO_IN_REG)

void begin() {
  gpio_config_t io = {};
  io.pin_bit_mask = (uint64_t)M_D;
  io.mode = GPIO_MODE_INPUT_OUTPUT;
  gpio_config(&io);
  REG_WRITE(GPIO_ENABLE_W1TC_REG, M_D);          // data pins start as inputs

  io.pin_bit_mask = (1ULL << PIN_A0) | (1ULL << PIN_A1) | (1ULL << PIN_RW) |
                    (1ULL << PIN_NCS) | (1ULL << PIN_PHI2);
  io.mode = GPIO_MODE_INPUT;
  gpio_config(&io);

  io.pin_bit_mask = (1ULL << PIN_ACK) | (1ULL << PIN_IRQ);
  io.mode = GPIO_MODE_OUTPUT;
  gpio_config(&io);
  REG_WRITE(GPIO_OUT_W1TS_REG, M_ACK);           // no wait states until run()
  REG_WRITE(GPIO_OUT_W1TC_REG, M_IRQ);

  memset(s_ioLen, 0xFF, sizeof s_ioLen);
  s_ioLen[IO_KBD_FLUSH] = 0;   s_ioLen[IO_KEY_DOWN] = 1;    s_ioLen[IO_KBD_MODS] = 0;
  s_ioLen[IO_MOUSE_READ] = 0;  s_ioLen[IO_MOUSE_DELTA] = 0; s_ioLen[IO_MOUSE_BOUNDS] = 4;
  s_ioLen[IO_MOUSE_SETPOS] = 4;
  s_ioLen[IO_SND_FREQ] = 3;    s_ioLen[IO_SND_WAVE] = 3;    s_ioLen[IO_SND_VOL] = 2;
  s_ioLen[IO_SND_ENV] = 5;     s_ioLen[IO_SND_GATE] = 2;    s_ioLen[IO_SND_NOTE] = 3;
  s_ioLen[IO_SND_MASTER] = 1;  s_ioLen[IO_SND_BEEP] = 3;    s_ioLen[IO_SND_STOP] = 0;
  s_ioLen[IO_SND_STATUS] = 0;
  s_ioLen[IO_IRQ_ENABLE] = 1;  s_ioLen[IO_PING] = 0;        s_ioLen[IO_VERSION] = 0;
  s_ioLen[IO_FRAME] = 0;       s_ioLen[IO_RESET] = 0;
}

static inline uint8_t status() {
  uint8_t s = ST_READY;
  if (input::keyAvailable()) s |= ST_KEY;
  if (input::mouseChanged()) s |= ST_MOUSE;
  if (!video::resp.empty()) s |= ST_VRESP;
  if (!s_ioResp.empty()) s |= ST_IORESP;
  if (video::vblFlag) s |= ST_VBL;
  if (!video::fifo.empty() || !video::idle) s |= ST_VBUSY;
  if (video::fifo.count() > VIDEO_FIFO_SIZE * 3 / 4) s |= ST_VFULL;
  return s;
}

static inline void updateIrq() {
  bool on = false;
  if (s_irqMask) {
    uint8_t s = 0;
    if (input::keyAvailable()) s |= ST_KEY;
    if (input::mouseChanged()) s |= ST_MOUSE;
    if (video::vblFlag) s |= ST_VBL;
    on = (s & s_irqMask) != 0;
  }
  REG_WRITE(on ? GPIO_OUT_W1TS_REG : GPIO_OUT_W1TC_REG, M_IRQ);
}

static inline uint8_t readReg(uint32_t reg) {
  uint8_t v = 0;
  switch (reg) {
    case 0: v = status(); video::vblFlag = 0; break;
    case 1: video::resp.pop(v); break;
    case 2: v = input::popKey(); break;
    case 3: s_ioResp.pop(v); break;
  }
  return v;
}

static void ioExecute() {
  uint8_t *a = s_ioArgs;
  uint8_t buf[5];
  s_ioActive = false;
  switch (s_ioCmd) {
    case IO_KBD_FLUSH: input::flushKeys(); break;
    case IO_KEY_DOWN: s_ioResp.push(input::isDown(a[0]) ? 1 : 0); break;
    case IO_KBD_MODS: s_ioResp.push(input::modifiers()); break;
    case IO_MOUSE_READ:
      input::mouseRead(buf);
      for (int i = 0; i < 5; i++) s_ioResp.push(buf[i]);
      break;
    case IO_MOUSE_DELTA:
      input::mouseDelta(buf);
      for (int i = 0; i < 3; i++) s_ioResp.push(buf[i]);
      break;
    case IO_MOUSE_BOUNDS: input::mouseSetBounds(a[0] | a[1] << 8, a[2] | a[3] << 8); break;
    case IO_MOUSE_SETPOS: input::mouseSetPos(a[0] | a[1] << 8, a[2] | a[3] << 8); break;
    case IO_SND_FREQ: audio::setFreq(a[0], a[1] | a[2] << 8); break;
    case IO_SND_WAVE: audio::setWave(a[0], a[1], a[2]); break;
    case IO_SND_VOL: audio::setVolume(a[0], a[1]); break;
    case IO_SND_ENV: audio::setEnvelope(a[0], a[1], a[2], a[3], a[4]); break;
    case IO_SND_GATE: audio::gate(a[0], a[1] != 0); break;
    case IO_SND_NOTE: audio::note(a[0], a[1], a[2]); break;
    case IO_SND_MASTER: audio::master(a[0]); break;
    case IO_SND_BEEP: audio::beep(a[0] | a[1] << 8, a[2]); break;
    case IO_SND_STOP: audio::stopAll(); break;
    case IO_SND_STATUS: s_ioResp.push(audio::activeMask()); break;
    case IO_IRQ_ENABLE: s_irqMask = a[0] & (ST_KEY | ST_MOUSE | ST_VBL); break;
    case IO_PING: s_ioResp.clear(); s_ioResp.push(0xA5); s_ioResp.push(0x5A); break;
    case IO_VERSION: s_ioResp.push(FW_VERSION_MAJOR); s_ioResp.push(FW_VERSION_MINOR); break;
    case IO_FRAME: {
      uint32_t f = video::frameCount;
      s_ioResp.push(f & 0xFF); s_ioResp.push((f >> 8) & 0xFF);
      break;
    }
    case IO_RESET:
      s_ioResp.clear(); input::flushKeys(); s_irqMask = 0; audio::stopAll();
      break;
  }
}

static void ioWrite(uint32_t reg, uint8_t v) {
  if (reg == 2) {
    s_ioCmd = v;
    s_ioArgc = 0;
    s_ioNeed = s_ioLen[v];
    s_ioActive = s_ioNeed != 0xFF;
    if (s_ioNeed == 0) ioExecute();
  } else if (s_ioActive) {
    if (s_ioArgc < sizeof s_ioArgs) s_ioArgs[s_ioArgc] = v;
    if (++s_ioArgc >= s_ioNeed) ioExecute();
  }
}

void IRAM_ATTR run() {
  uint32_t idleCount = 0;
  REG_WRITE(GPIO_OUT_W1TC_REG, M_ACK);   // from now on every access waits for us
  for (;;) {
    uint32_t in = IN();
    if (in & M_NCS) {
      if ((++idleCount & 0xFF) == 0) updateIrq();
      continue;
    }
    in = IN();                           // re-check: ignore decoder glitches
    if (in & M_NCS) continue;
    uint32_t reg = (in >> PIN_A0) & 3;

    if (in & M_RW) {
      // ------------------------------------------------ CPU read
      uint8_t v = readReg(reg);
      REG_WRITE(GPIO_OUT_W1TS_REG, (uint32_t)v << PIN_D0);
      REG_WRITE(GPIO_OUT_W1TC_REG, (uint32_t)(uint8_t)~v << PIN_D0);
      REG_WRITE(GPIO_ENABLE_W1TS_REG, M_D);
      REG_WRITE(GPIO_OUT_W1TS_REG, M_ACK);
      while (!(IN() & M_NCS)) {}
      REG_WRITE(GPIO_ENABLE_W1TC_REG, M_D);
      REG_WRITE(GPIO_OUT_W1TC_REG, M_ACK);
    } else {
      // ------------------------------------------------ CPU write
      // The stalled CPU repeats the write cycle; sample during a PHI2-high
      // phase with interrupts masked so the sample can't slip into PHI2 low.
      uint32_t d;
      bool cancelled = false;
      for (;;) {
        uint32_t irq = portSET_INTERRUPT_MASK_FROM_ISR();
        uint32_t guard = 0;
        while ((IN() & M_PHI2) && ++guard < 100000) {}
        while (!(IN() & M_PHI2) && ++guard < 100000) {}
        uint32_t d1 = IN();
        d = IN();
        portCLEAR_INTERRUPT_MASK_FROM_ISR(irq);
        if (d & M_NCS) { cancelled = true; break; }        // glitch, not a real access
        if ((d1 & d & M_PHI2) && ((d1 ^ d) & M_D) == 0) break;
      }
      if (cancelled) continue;
      uint8_t v = (d >> PIN_D0) & 0xFF;

      if (reg < 2) {
        if (reg == 0 && v == video::C_RESET) video::resp.clear();
        while (!video::fifo.push((uint16_t)(reg << 8) | v)) video::kick();   // full: hold RDY
        video::kick();
      }
      REG_WRITE(GPIO_OUT_W1TS_REG, M_ACK);
      while (!(IN() & M_NCS)) {}
      REG_WRITE(GPIO_OUT_W1TC_REG, M_ACK);
      if (reg >= 2) ioWrite(reg, v);
    }
    updateIrq();
  }
}

} // namespace bus
