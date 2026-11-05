# ESP32-S3 VGA / keyboard / mouse / sound adapter for a W65C02S computer

An ESP32-S3 sits on the 6502 bus as four registers and provides:

- **VGA 640×480 @ 60 Hz, 64 colours.** The output uses a FabGL-style 2-resistor ladder per channel and has three layers:
  - an 80×30 text layer with a redefinable 8×16 CP437 font and per-cell foreground/background colours (background can be transparent);
  - a 320×240 bitmap with lines, rectangles, circles, blits, copy and hardware-style scrolling;
  - 16 sprites (16×16, 32 patterns, flipping, overlap test) plus a built-in mouse pointer.
- **Keyboard and mouse** over PS/2 (one of each) and USB HID (native USB host; works with a hub and with wireless combo receivers).
- **Sound:** a 4-voice synthesizer with square, triangle, saw, sine and noise waveforms, ADSR envelopes and MIDI-note playback.

The firmware is Arduino on PlatformIO (Arduino-ESP32 3.x / ESP-IDF 5.x). It
doesn't use FabGL: the S3's LCD peripheral generates the VGA timing and the
picture is drawn line by line from internal RAM, so no PSRAM is needed.

```
esp32s3-vga-adapter/
  platformio.ini
  src/            firmware
  6502/           vga.inc (register map + macros), vga.s (driver), vgademo.s, make.bat
  gal/            VGAGLUE.PLD - GAL22V10 glue logic (WinCUPL)
  LICENSE-spleen.txt   font license (Spleen 8x16, BSD-2-Clause)
```

---

## 1. How the bus interface works

At 2 MHz the 6502 gives a peripheral about 250 ns of PHI2-high time. Software
on the ESP32 can't reliably answer inside that window (one interrupt or cache
miss and the read is lost). The adapter therefore uses **RDY wait states**:

1. Your address decoder pulls **/CS** low.
2. Glue logic pulls **RDY** low straight away, because the ESP32's **ACK** is
   low. The W65C02S freezes mid-cycle with the address, R/W and (on a write)
   the data held steady.
3. Core 1 of the ESP32 runs a dedicated loop that watches /CS:
   - **Read:** it puts the register value on its side of the data buffer and raises ACK.
   - **Write:** it samples D0–D7 during a PHI2-high phase and raises ACK.
4. RDY goes high, the CPU finishes the cycle, and /CS goes high. The ESP32 drops ACK and the adapter is ready for the next access.

What this means in practice:

- **No polling before writes.** Every STA goes straight in. If the 16K-entry
  display queue is ever full, the CPU just waits a little longer.
- **Results are there on the next read.** For example, after `IO_MOUSE` the
  bytes are in `IO_RESP` at once.
- **Each access costs about one or two extra clock cycles.** This is an
  estimate from the code path; measure it on your board. Printing text is a
  single `STA VGA_DATA` per character, which is far faster than a
  115200-baud serial terminal.
- **The W65C02S is required.** The NMOS 6502 ignores RDY on write cycles.
- **Don't use read-modify-write instructions** (INC, DEC, ASL, LSR, ROL, ROR,
  TSB, TRB) on adapter registers. Their second access to the same address
  isn't stalled.
- **ACK has a pull-up,** so while the ESP32 is resetting or booting the CPU is
  never stalled. Reads just return junk, and `vga_init` waits for a valid
  ping reply.

---

## 2. Hardware

### Parts

| Qty | Part | Purpose |
|---|---|---|
| 1 | ESP32-S3-DevKitC-1 (WROOM-1 N8, N16R8, …) | the adapter |
| 1 | SN74LVC8T245 (dual-supply, direction-controlled) | D0–D7, 5 V ↔ 3.3 V |
| 1 | GAL22V10D (or ATF22V10C) | address decode, RDY/IRQ glue, 5 V → 3.3 V for A0, A1, R/W, /CS, PHI2 |
| 5 | 1 kΩ | pull-ups to 3.3 V on the GAL's open-drain outputs to the ESP32 |
| 5 | 100 Ω (optional) | series protection, GAL → ESP32 |
| 1 | 4-channel BSS138 level-shifter module | PS/2 keyboard + mouse |
| 6 | 390 Ω + 820 Ω (3 of each) | VGA DAC (or keep FabGL's 270 Ω / 560 Ω) |
| 2 | 100 Ω | HSYNC / VSYNC series |
| 2+2 | 1 kΩ, 10 nF, 10 µF | audio filter |
| | DE-15 VGA socket, 2× mini-DIN-6, USB-A socket, 10 kΩ ×2 (ACK pull-up, IRQREQ pull-down) | |

The 74LVC8T245 only comes in SMD packages; a TSSOP-to-DIP adapter makes it
breadboard-friendly.

### ESP32-S3 pin map (`src/config.h`)

| GPIO | Signal | GPIO | Signal |
|---|---|---|---|
| 4–11 | D0–D7 (via 8T245 A side) | 41 / 42 | VGA R1 (MSB) / R0 |
| 12, 13 | A0, A1 | 47 / 48 | VGA G1 / G0 |
| 14 | R/W | 45 / 46 | VGA B1 / B0 |
| 15 | /CS | 39 / 40 | HSYNC / VSYNC |
| 16 | PHI2 | 1 / 2 | PS/2 keyboard CLK / DATA |
| 17 | ACK (out) | 21 / 3 | PS/2 mouse CLK / DATA |
| 18 | IRQ drive (out) | 38 | audio (sigma-delta) |
| 19 / 20 | USB D− / D+ (host) | 43 / 44 | UART0: upload + debug |

GPIO 33–37 are left free for octal-PSRAM modules. GPIO 45 and 46 are
strapping pins, which is safe here: the VGA ladder and the monitor's 75 Ω
termination hold them low at boot. The DevKitC's on-board RGB LED sits on
GPIO 38 or 48 (depending on board revision) and will flicker. That's harmless,
or you can remove the LED.

### Glue logic and buffers

The adapter answers at **$7F18–$7F1B**. One GAL22V10D does the rest of the
address decode, the RDY and /IRQ logic, and the level shifting toward the
ESP32. The source is in [`gal/VGAGLUE.PLD`](gal/VGAGLUE.PLD) (WinCUPL, device `g22v10`).

**How the decode works.**
- The SBC's /IO_EN is low for page `$7F`.
- The GAL adds A7–A2 = `%000110` to select `$18–$1B`.
- **/IO_EN must come from the address only, not qualified with PHI2.** The
  select has to stay active for the whole stretched cycle while RDY holds
  the CPU.

| GAL pin | Signal | Direction | Connects to |
|---|---|---|---|
| 1 | PHI2 | in | CPU PHI2 |
| 2 | RW | in | CPU R/W |
| 3–10 | A0–A7 | in | CPU address bus |
| 11 | nIO_EN | in | SBC /IO_EN |
| 13 | ACK | in | ESP32 GPIO17, 10 kΩ pull-up to 3.3 V |
| 23 | IRQREQ | in | ESP32 GPIO18, 10 kΩ pull-down |
| 14 | RDY | open drain | CPU RDY (SBC pull-up to 5 V) |
| 15 | nIRQ | open drain | CPU /IRQ (SBC pull-up to 5 V) |
| 16 | nBUSEN | push-pull | 74LVC8T245 /OE |
| 17 | nCS_33 | open drain | ESP32 GPIO15, 1 kΩ to 3.3 V |
| 18 | PHI2_33 | open drain | ESP32 GPIO16, 1 kΩ to 3.3 V |
| 19 | RW_33 | open drain | ESP32 GPIO14, 1 kΩ to 3.3 V |
| 20 | A1_33 | open drain | ESP32 GPIO13, 1 kΩ to 3.3 V |
| 21 | A0_33 | open drain | ESP32 GPIO12, 1 kΩ to 3.3 V |
| 22 | — | spare | |
| 12 / 24 | GND / +5 V | | |

**How the open-drain outputs work.** Each output is fixed at 0, and its
`.oe` term turns the driver on only when the line should be low. The rest of
the time the pin is Hi-Z and the pull-up sets the level. That way the ESP32
only ever sees 0 V or 3.3 V.

**Pull-up value.** Use **1 kΩ**, not 10 kΩ, because rising edges are only as
fast as the pull-up can charge the line. At 10 kΩ the PHI2 copy would take
about as long to rise as the whole 250 ns PHI2-high time at 2 MHz. At 1 kΩ
the ESP32 sees it high after about 35 ns.

**Before you connect the ESP32,** check each `*_33` pin with a meter. It
should read 3.3 V (pull-up only) or near 0 V, never 5 V. The optional
100 Ω series resistors limit the damage from a mis-programmed GAL.

**RDY and /IRQ** are true open-drain outputs, so the 65C02's WAI instruction
and other devices sharing those lines still work. RDY must be pulled up
through a resistor (3.3 kΩ) on the SBC, not tied straight to +5 V.

**ACK pull-up.** The 10 kΩ pull-up on ACK means the CPU is never stalled
while the ESP32 is resetting or booting.

**SN74LVC8T245 (data bus):**
- VCCA = 3.3 V; A1–A8 = GPIO4–11.
- VCCB = 5 V; B1–B8 = CPU D0–D7.
- DIR = CPU R/W. High is a read, so data flows A→B, toward the CPU.
- /OE = GAL nBUSEN, so the bus is driven only while selected and PHI2 is high.

### VGA

| DE-15 pin | Signal |
|---|---|
| 1 | Red: GPIO41 via 390 Ω, GPIO42 via 820 Ω |
| 2 | Green: GPIO47 via 390 Ω, GPIO48 via 820 Ω |
| 3 | Blue: GPIO45 via 390 Ω, GPIO46 via 820 Ω |
| 13 / 14 | HSYNC / VSYNC via 100 Ω |
| 5, 6, 7, 8, 10 | GND |

With the monitor's 75 Ω termination, 390/820 Ω gives levels of about 0, 0.24,
0.49 and 0.73 V. That's evenly spaced and right at the VGA 0.7 V full scale.
If you already have FabGL's ladder (270/560 Ω), keep it: the picture is just a
bit brighter. The pixel byte is `%00RRGGBB`.

### PS/2

Mini-DIN-6 pinout: 1 = DATA, 3 = GND, 4 = +5 V, 5 = CLK. Each line goes through the BSS138 shifter: the HV side to the
connector with +5 V, the LV side to the ESP32 with 3.3 V. The module's
built-in 10 kΩ pull-ups are all the bus needs. Keyboard and mouse can be
plugged in after power-up: the mouse is re-probed every 3 s and the keyboard
LEDs are restored after a hot-plug.

### USB host

Wire a USB-A socket to D− = GPIO19, D+ = GPIO20, GND, and VBUS = +5 V. A
500 mA polyfuse in VBUS is a good idea. Boot-protocol keyboards and mice work
directly, through a hub, or through a wireless combo receiver (up to 4
devices). USB keyboards get software key repeat (500 ms delay, 30/s).

### Audio

```
GPIO38 ──1k──┬──1k──┬──||── amplifier (PAM8403 / LM386) or line out
           10nF   10nF  10µF
             │      │
            GND    GND
```

### Power

Feed the DevKitC's **5V** pin from the SBC's +5 V, and take 3.3 V for the
buffers from its **3V3** pin. Check your board before plugging USB in for
programming while the SBC is powered: on many DevKitC boards the USB 5 V is
tied to the 5V pin. Either power from one source at a time or add a Schottky
diode in the SBC feed.

---

## 3. Register map

| A1:A0 | Read | Write |
|---|---|---|
| 0 | **STATUS** | **VGA_CMD**: display command opcode |
| 1 | **VGA_RESP**: display query results | **VGA_DATA**: command arguments, or text to print |
| 2 | **VGA_KEY**: next key, 0 = none | **IO_CMD**: keyboard / mouse / sound / system opcode |
| 3 | **IO_RESP**: I/O query results | **IO_DATA**: I/O command arguments |

**STATUS bits:**

| Bit | Name | Meaning |
|---|---|---|
| 7 | KEY | a key is waiting |
| 6 | MOUSE | mouse moved or buttons changed |
| 5 | VRESP | display response byte waiting |
| 4 | IORESP | I/O response byte waiting |
| 3 | VBL | vblank started since the last STATUS read (cleared by reading) |
| 2 | VBUSY | display commands still executing |
| 1 | VFULL | display queue over ¾ full |
| 0 | READY | firmware running |

**Display channel.** Writing an opcode to VGA_CMD starts a command, and its
arguments go to VGA_DATA. While no command is collecting arguments, bytes
written to VGA_DATA are printed at the cursor. The control codes are CR, LF,
BS, TAB, FF (clear screen) and BEL (beep). A new opcode always aborts an
unfinished command, so a confused stream recovers on its own. Display commands
run in order on the other core. To wait for one to finish, send `V_SYNC` and
read `$AA` from VGA_RESP.

**I/O channel.** These commands execute as soon as their last argument is
written, so results are already in IO_RESP on the next read.

The full opcode list with arguments is in [`6502/vga.inc`](6502/vga.inc). Summary:

| Display | Args → response | | I/O | Args → response |
|---|---|---|---|---|
| `$01` RESET | | | `$01` KBDFLUSH | |
| `$02` CLS | | | `$02` KEYDOWN | code → 0/1 |
| `$03` COLOR | fg, bg | | `$03` KBDMODS | → caps/alt/ctrl/shift |
| `$04` LOCATE | col, row | | `$10` MOUSE | → btn, x16, y16 |
| `$05` CURSOR | 0/1/2 | | `$11` MDELTA | → btn, dx, dy |
| `$06` SCROLLRGN | top, bottom | | `$12` MBOUNDS | xmax16, ymax16 |
| `$07` PUTRAW | n, glyphs | | `$13` MSETPOS | x16, y16 |
| `$08` TSCROLL | 0 up / 1 down | | `$20` SNDFREQ | v, hz16 |
| `$09` FILLTEXT | c, r, w, h, ch | | `$21` SNDWAVE | v, wave, duty |
| `$0A` DEFGLYPH | ch, 16 bytes | | `$22` SNDVOL | v, vol |
| `$0B` SETATTR | c, r, w, h | | `$23` SNDENV | v, a, d, s, r |
| `$0D` GETCHAR | c, r → ch, fg, bg | | `$24` SNDGATE | v, on |
| `$0E` DEFFONT | | | `$25` SNDNOTE | v, midi, frames |
| `$10` LAYERS | mask | | `$26` SNDMAST | vol |
| `$11` BACKDROP | colour | | `$27` SNDBEEP | hz16, frames |
| `$12` WAITVBL | | | `$28` SNDSTOP | |
| `$13` SCROLL | x16, y | | `$29` SNDSTAT | → voice mask |
| `$20`–`$26` | GCLS, PLOT, LINE, RECT, FILLRECT, CIRCLE, FILLCIRC | | `$F0` IRQEN | mask |
| `$27` BLIT | x16, y, w16, h, pixels | | `$F1` PING | → `$A5`, `$5A` |
| `$28` COPYRECT | sx16, sy, w16, h, dx16, dy | | `$F2` VERSION | → major, minor |
| `$29` GETPIXEL | x16, y → colour | | `$F3` FRAME | → frame lo, hi |
| `$2B` GTEXT | x16, y, fg, bg, n, chars | | `$FF` RESET | |
| `$30`–`$35` | SPRDEF, SPRSET, SPRMOVE, SPRHIDE, SPRHITS, SPRPAT | | | |
| `$40`–`$42` | INFO, GETCURSOR, SYNC | | | |
| `$50` MOUSEPTR | on/off | | | |

**Coordinates.**
- Bitmap, sprites and mouse use 320×240 space.
- Sprite x/y are signed 16-bit, so sprites can slide off the edges.
- The text grid is 80×30. Mouse x/4 and y/8 give the text cell.

**Colours.** Bytes are `%00RRGGBB`. Any byte with bit 6 set (`$40`) is
transparent: as a text background (the bitmap shows through), as a sprite
pixel, or as a BLIT pixel.

**Keys.** The keyboard queue returns ASCII with shift, caps and ctrl applied.
Arrows are `$80`–`$83`, Home/End/PgUp/PgDn/Ins are `$84`–`$88`, and F1–F12
are `$90`–`$9B`. For games, `IO_KEYDOWN` with the unshifted code (`'a'`,
`KEY_LEFT`, `KEY_LSHIFT` …) tells whether a key is held right now.

**Interrupts.** `IO_IRQEN` with any of `ST_KEY | ST_MOUSE | ST_VBL` makes the
adapter hold /IRQ low while that condition is true. Each condition clears
naturally: read the keys, read the mouse, or read STATUS.

---

## 4. Using it from the 6502

```asm
        .include "vga.inc"          ; adapter at $7F18
        jsr vga_init                ; C=1 if the adapter didn't answer
        VCMD V_COLOR
        VARG YELLOW
        VARG BLACK
        lda #<msg
        ldx #>msg
        jsr vga_puts                ; or: STA VGA_DATA per character
        VCMD V_LAYERS               ; text + bitmap + sprites
        VARG 7
        VCMD V_FILLCIRC             ; x=160, y=120, r=40, red
        VARG16 160
        VARG 120
        VARG 40
        VARG RED
        IOCMD IO_SNDNOTE            ; voice 0, middle C, half a second
        IOARG 0
        IOARG 60
        IOARG 30
```

**EhBASIC / BIOS hooks.**
- Output vector: `vga_chrout`, which is just `STA VGA_DATA`.
- Input vector: `vga_chrin`, which returns C=1 with the key in A, or C=0 when
  no key is waiting.
- Your existing `SBC_CHROUT`/`SBC_CHRIN` jump-table entries can point at these
  so the games pick up the new console without changes.

**Demo.** Build it with `6502\make.bat`, which writes `VGADEMO.BIN` to load
and run at `$0500`. It puts up a bitmap scene with text over it and a bouncing
sprite synced to vblank that plays a sound on each bounce. Keys play notes and
the left mouse button paints. ESC returns to the monitor. Zero page `$E0–$FF`
is used; change it in `vgademo.cfg` if needed.

---

## 5. Building the firmware

**PlatformIO:** open the folder and build/upload `env:esp32s3`. The ini uses
the pioarduino platform, because the stock `espressif32` platform still ships
Arduino 2.x. For an N16R8 board, uncomment the two lines in `platformio.ini`.

**Arduino IDE (3.x core):** make a folder `vga_adapter` and copy every file
from `src/` into it. Rename `main.cpp` to `vga_adapter.ino`. Use these settings:
- Board: ESP32S3 Dev Module
- USB Mode: Hardware CDC and JTAG
- USB CDC On Boot: Disabled

Upload through the board's **UART** USB port. The native USB port is the USB
host for the keyboard and mouse. Serial output (115200 baud) shows the boot
log, the PS/2 detection result and USB devices as they come and go.

### Resource use

| | |
|---|---|
| Internal RAM | about 155 KB (bitmap 75 KB, display queue 32 KB, text/font/sprites ~20 KB) |
| Core 0 | VGA scan-line interrupt, display commands, PS/2 decoding, USB host |
| Core 1 | the bus loop, PS/2 clock interrupts (level 3), 31.25 kHz audio interrupt |

---

## 6. Bring-up checklist

1. **VGA only, nothing on the bus.** Flash the firmware and connect a monitor:
   you should get a black screen in sync. Over the serial log, confirm "VGA
   640x480 running".
2. **Program and check the GAL, then wire it and the 8T245.** With the ESP32 unplugged, confirm the `*_33` pins only ever read 0 V or 3.3 V. Leave ACK's 10 k pull-up in place.
3. **Ping test.** Run a 6502 loop that writes `$F1` to IO_CMD and reads two
   bytes from IO_RESP. Expect `$A5 $5A`.
4. **Print text** with `STA VGA_DATA`, then run the demo.
5. **Check RDY on a scope.** It should go low for well under a microsecond per
   access. If writes come out corrupted, look at the PHI2 and data timing on
   the ESP32 side of the buffers.

### Known limits

- **CPU clock.** Write data is sampled 50–100 ns after the ESP32 sees PHI2
  rise. That is comfortable at 2 MHz and should be fine at 4 MHz. Faster
  clocks would need a write latch (a 74HC574 clocked by the end of the write
  cycle).
- **No double buffering.** Drawing happens while the screen is displayed, so
  fast-moving bitmap drawing can tear. Sprites and the scroll registers don't
  tear. Use `V_WAITVBL` or poll `ST_VBL` to time updates.
- **USB HID.** Boot protocol only. Most keyboards and mice support it; some
  gaming mice don't.
- **Not FabGL-compatible.** The command set is new and designed around the
  4-register interface. It isn't compatible with the PIC32 terminal protocol
  either; a translation layer could be added if your existing games need it.

`docs/demo-frame.png` is a frame of the demo rendered by the firmware's own scan-line code on a PC (6502 emulator → command stream → video.cpp).

Font: Spleen 8×16 (CP437 variant) by Frederic Cambus, BSD 2-Clause, see `LICENSE-spleen.txt`.
