// PS/2 keyboard and mouse (host side, interrupt driven, bidirectional).
#pragma once
namespace ps2 {
// Call from setup() on core 1: the clock-edge interrupts are placed on core 1
// at high priority so the VGA interrupt on core 0 can never make them miss a
// bit. Decoding runs in a task on core 0.
void begin();
}
