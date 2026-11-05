// 6502 bus interface: four registers selected by A1:A0.
//
//   reg  read                      write
//   0    STATUS                    DISPLAY COMMAND (starts a command)
//   1    DISPLAY RESPONSE          DISPLAY DATA (arguments, or text to print)
//   2    KEYBOARD (next char, 0)   I/O COMMAND (keyboard, mouse, sound, system)
//   3    I/O RESPONSE              I/O DATA (arguments)
//
// Every access is held with RDY wait states until the ESP32 has handled it,
// so the 6502 never needs to poll a "ready" bit before writing.
#pragma once
#include <stdint.h>

namespace bus {

// STATUS register bits
enum : uint8_t {
  ST_KEY = 0x80,      // key waiting in register 2
  ST_MOUSE = 0x40,    // mouse moved / buttons changed since last mouse read
  ST_VRESP = 0x20,    // display response byte waiting in register 1
  ST_IORESP = 0x10,   // I/O response byte waiting in register 3
  ST_VBL = 0x08,      // a vertical blank started since the last STATUS read
  ST_VBUSY = 0x04,    // display commands still being processed
  ST_VFULL = 0x02,    // display FIFO more than 3/4 full (writes may wait)
  ST_READY = 0x01,    // firmware running
};

// I/O command opcodes (register 2), arguments through register 3.
enum : uint8_t {
  IO_KBD_FLUSH = 0x01, IO_KEY_DOWN = 0x02, IO_KBD_MODS = 0x03,
  IO_MOUSE_READ = 0x10, IO_MOUSE_DELTA = 0x11, IO_MOUSE_BOUNDS = 0x12, IO_MOUSE_SETPOS = 0x13,
  IO_SND_FREQ = 0x20, IO_SND_WAVE = 0x21, IO_SND_VOL = 0x22, IO_SND_ENV = 0x23,
  IO_SND_GATE = 0x24, IO_SND_NOTE = 0x25, IO_SND_MASTER = 0x26, IO_SND_BEEP = 0x27,
  IO_SND_STOP = 0x28, IO_SND_STATUS = 0x29,
  IO_IRQ_ENABLE = 0xF0, IO_PING = 0xF1, IO_VERSION = 0xF2, IO_FRAME = 0xF3, IO_RESET = 0xFF,
};

void begin();   // configure pins (ACK released so a dead adapter never hangs the CPU)
void run();     // never returns; call from loop() on core 1

} // namespace bus
