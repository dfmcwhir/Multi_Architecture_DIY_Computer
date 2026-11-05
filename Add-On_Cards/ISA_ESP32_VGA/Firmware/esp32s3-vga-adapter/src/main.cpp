// ESP32-S3 VGA / keyboard / mouse / sound adapter for a W65C02S computer.
//
// Core 0: VGA scan-line interrupt, display command task, PS/2 decoding, USB host.
// Core 1: the 6502 bus loop (this Arduino loop), PS/2 clock interrupts, audio.
#include <Arduino.h>
#include "config.h"
#include "bus.h"
#include "video.h"
#include "input.h"
#include "audio.h"
#include "ps2.h"
#include "usbhid.h"

void setup() {
  Serial.begin(115200);          // UART0 (GPIO43/44) through the board's UART port
  bus::begin();                  // ACK released: the 6502 is never stalled while we boot
  input::begin();
  audio::begin();                // timer interrupt on core 1
  ps2::begin();                  // clock interrupts on core 1, decoder task on core 0
  video::begin();                // VGA + command task on core 0
  usbhid::begin();               // USB host tasks on core 0
  while (!video::ready) delay(1);
  Serial.printf("6502 VGA adapter v%d.%d ready\n", FW_VERSION_MAJOR, FW_VERSION_MINOR);
}

void loop() {
  bus::run();                    // never returns
}
