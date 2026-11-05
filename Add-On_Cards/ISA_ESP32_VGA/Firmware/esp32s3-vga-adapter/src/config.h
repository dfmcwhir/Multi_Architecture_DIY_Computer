// ESP32-S3 VGA / keyboard / mouse / sound adapter for a W65C02S computer.
// Pin map and build-time configuration.
//
// Board: ESP32-S3-DevKitC-1 (WROOM-1 N16R8 or N8R2 etc.). GPIO 33-37 are left
// free because octal-PSRAM modules use them. GPIO 19/20 are the native USB
// pins (USB host for keyboard/mouse). GPIO 43/44 stay as UART0 for upload and
// debug through the board's "UART" USB port.
#pragma once
#include <stdint.h>

// ---------------------------------------------------------------- 6502 bus
// All bus pins must be < 32 so one read of GPIO_IN_REG captures everything.
// D0..D7 must be consecutive GPIOs starting at PIN_D0.
#define PIN_D0        4     // D0..D7 = GPIO4..GPIO11 (via 74LVC8T245)
#define PIN_A0        12    // register select bit 0   (from GAL, open drain + 1k pull-up)
#define PIN_A1        13    // register select bit 1   (input)
#define PIN_RW        14    // R/W from CPU, 1 = read  (input)
#define PIN_NCS       15    // /CS for $7F18-$7F1B, decoded by the GAL, active low
#define PIN_PHI2      16    // PHI2 clock (input)
#define PIN_ACK       17    // to GAL ACK: 0 = hold RDY low while selected
#define PIN_IRQ       18    // to GAL IRQREQ: 1 = pull /IRQ low

// ---------------------------------------------------------------- VGA
// 2-bit-per-channel resistor DAC like FabGL (64 colours).
// Pixel byte format: 0b00RRGGBB.
#define PIN_VGA_B0    46
#define PIN_VGA_B1    45
#define PIN_VGA_G0    48
#define PIN_VGA_G1    47
#define PIN_VGA_R0    42
#define PIN_VGA_R1    41
#define PIN_VGA_HSYNC 39
#define PIN_VGA_VSYNC 40

// ---------------------------------------------------------------- PS/2
// Through a BSS138 4-channel bidirectional level shifter (5 V <-> 3.3 V).
#define PIN_KBD_CLK   1
#define PIN_KBD_DAT   2
#define PIN_MOUSE_CLK 21
#define PIN_MOUSE_DAT 3

// ---------------------------------------------------------------- Audio
// Sigma-delta output -> RC low-pass filter -> amplifier / line out.
#define PIN_AUDIO     38

// ---------------------------------------------------------------- Video timing
// 640x480 @ 60 Hz industry standard timing, negative sync polarity.
#define VGA_PCLK_HZ   25175000
#define VGA_H_RES     640
#define VGA_V_RES     480
#define VGA_HFP       16
#define VGA_HSYNC     96
#define VGA_HBP       48
#define VGA_VFP       10
#define VGA_VSYNC     2
#define VGA_VBP       33
#define VGA_BOUNCE_LINES 8      // lines per bounce buffer (480 must be a multiple)

// Text layer: 80x30 cells of 8x16 pixels.
#define TEXT_COLS     80
#define TEXT_ROWS     30

// Bitmap layer: 320x240, 1 byte per pixel, shown pixel-doubled.
#define GFX_W         320
#define GFX_H         240

#define NUM_SPRITES   16
#define NUM_PATTERNS  32
#define SPRITE_SIZE   16

// Any colour byte with bit 6 set is transparent (sprites, text background).
#define COLOR_TRANSPARENT 0x40

// Size of the 6502 -> video command FIFO (entries, power of two).
#define VIDEO_FIFO_SIZE 16384

// ---------------------------------------------------------------- Audio synth
#define AUDIO_SAMPLE_RATE 31250
#define AUDIO_VOICES      4

#define FW_VERSION_MAJOR 1
#define FW_VERSION_MINOR 0
