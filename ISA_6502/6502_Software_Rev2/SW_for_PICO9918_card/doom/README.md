# 6502 DOOM for the 6502 SBC (CPU Rev2, PICO9918)

The raycasting shooter, remade for the **PICO9918** card in TMS9918A Graphics II (bitmap) mode. These are all the PIC32 version's, unchanged:
- the engine (the ray caster, the scaled things, the gun, doors, enemies, pickups);
- the maps E1M1–E1M3, loaded with SBC_LOAD;
- the music and the sound.

What's new is how the picture gets to the screen, and its colours.

## Running

Copy `DOOM.BIN` and `E1M1.LVL`, `E1M2.LVL`, `E1M3.LVL` to the USB drive, then in the monitor:

```
L DOOM 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q on the title puts the text console back and goes to the boot menu.
- **Controls:** the same as before. The AVR keyboard's arrow keys move and turn.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 6 | the least time a game frame takes, in 1/60 s: 6 = at most 10 frames a second. The enemies act once a frame, so this sets the game's pace; a smaller number makes everything faster. |
| $0804 | 0 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |
| $0806 | 1 | ceiling and floor: 0 black, 1 solid dark slate / dark brown, 2 stripes (blue / grey) |

## Speed

Measured in the emulator, with the default cap of 10 frames a second:

| Clock | Turning | Walking |
|---|---|---|
| 4 MHz | 10 fps (the cap; about 13 without it) | 10 fps (the cap) |
| 2 MHz | about 7 fps | about 7 fps |

The colours cost about 15% of the time.

## The picture

- **The view:** the engine still draws the view into its frame buffer: 80 × 18 block graphics characters of 2 × 4 pixels (160 × 72).
  - `present` turns that into the bitmap. A block pixel becomes 1.5 × 2 screen pixels, in the same proportions as on the PIC32 terminal, so the view is 240 × 144 in the middle of the screen.
  - Eight characters become three bitmap cells. Only the groups of eight that changed since the last frame are drawn.
- **Text:** the title, loading and end screens are drawn into the bitmap with the bold console font. The status lines (text rows 18–23) are names of font patterns, in yellow.
- **The title banner:** the original block graphics, put into the frame buffer and shown the same way.

## Colours

A Graphics II cell row (8 pixels across, 1 line) has one colour for its set pixels and one for the rest. `build_colours` works out, after each frame is drawn, what each of the view's 30 cell columns shows; `draw_group` then writes the colours with the patterns:

- **Walls:** by style and side, from the wall in the cell's middle column: brick red, tech blue, stone white/grey, doors yellow, the exit switch green. The side facing y is darker. On the lighter side the gaps in the dither get a dark shade of the colour; brick keeps black gaps.
- **Ceiling and floor:** chosen by the byte at $0806 (see the header table).
  - The dark colours of choice 1 aren't in the TMS9918 palette. The game redefines two colours it doesn't otherwise use through the F18A palette registers: 13 (magenta) becomes dark slate and 9 (light red) dark brown.
  - Quitting with Q writes the default values back and asks the PICO9918 to restore its own palette (VR50 = $C0). If you reset the computer while DOOM is running instead, those two colours stay dark in other programs until the power is switched off.
- **Things:** grunts light green, brutes red, the dead dark red, medkits white, ammo yellow; the gun grey, yellow when it fires.

The numbers are all in `gen_colours.py`: change them, run `python gen_colours.py`, rebuild.

A cell can only have two colours, so a thing standing in front of a wall colours the wall pixels in its cells too, and a cell with two kinds of wall takes the colour of its middle one.

## How it works

- **Spreading:** a character at an even column becomes left, left, right; at an odd column, left, right, right. So two characters fill 3 screen pixels each and line up exactly. Each block row is written twice (2 screen lines). Small tables in `font.inc` (made by `gen_font.py`) put the pixels in place.
- **VRAM (Graphics II):** patterns $0000, colours $2000, names $3800.
  - Rows 0–17 are the bitmap (names in order).
  - Rows 18–23 use font patterns $80–$BF in the third third.
- **Pacing:** each game frame waits until at least `speed` ticks of the ROM's 60 Hz counter (`SBC_TICKS`) have passed since the last. That replaces the PIC32 version's wait for the terminal.
- **R1 = $C2:** display on, 16K, and bit 5 (the VDP interrupt) off. The ROM doesn't handle the VDP's interrupt, so with bit 5 on the CPU is stuck in the IRQ handler (the first version's black screen).
- **Memory:**

  | Range | Contents |
  |---|---|
  | $0800–$57FF | program and variables |
  | $5800–$5DFF | the level |
  | $5E00–$69FF | the two frame buffers |
  | $6A00–$6BDF | the colour tables |

  No zero page is used.

## Files

| File | What it is |
|---|---|
| `doom.s`, `doom.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`) |
| `gen_tables.py` → `tables.inc` | the engine's tables, wall patterns, sprites, gun, banner (unchanged) |
| `gen_font.py` → `font.inc` | the font and the spreading tables |
| `gen_colours.py` → `colours.inc` | the colours |
| `mklevels.py` → `E1M1.LVL` … `E1M3.LVL`, `builtin.inc` | the maps (unchanged) |
| `doom_sound.inc` | the music and effects (unchanged) |
| `DOOM.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
