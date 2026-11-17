# CRITTERS for the 6502 SBC (CPU Rev2, PICO9918, mouse)

The Lemmings-style puzzle game, remade for the **PICO9918** card, with the **mouse** on the AVR keyboard interface. The game itself is the PIC32 terminal version's, unchanged: the critters, the six skills, the six levels and the music.

## Running

Copy `CRITTERS.BIN` to the USB drive, then in the monitor:

```
L CRITTERS 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Mouse:** the game turns mouse reports on (`SBC_MOUSEON`) at the start and off when you quit. Without a mouse (or with a ROM built without one) there is no pointer and everything works from the keyboard and the gamepad.
- **Quit:** Q on the title puts the text console back and goes to the boot menu.

## The mouse

| Action | What it does |
|---|---|
| point at a critter | selects it (the yellow mark appears over it, and its job shows on the status line) |
| left click on a critter | gives it the chosen skill |
| left click on the skill bar (bottom row) | chooses that skill (the `>` moves to it) |
| right click | pause; any click, key or Start goes on |
| left click on the title, the level page, or the end of a level | play / go on (as Space) |

## Keys and gamepad

The same as before:

| Key | Action |
|---|---|
| `,` `.` or ← → | select the critter to the left / right |
| 1–6 | give the selected critter a skill: 1 climber, 2 floater, 3 blocker, 4 builder, 5 basher, 6 digger |
| ↑ ↓ (arrow keys) | choose the skill the mouse and A give |
| + / - | release rate |
| P | pause |
| K | nuke |
| R | restart the level |
| M | sound on / off |
| Q | back to the title |

Gamepad: left / right select, up / down choose the skill, A gives it, B + up / down release rate, Start pauses, Select + A nukes. Pressing any pad button switches to gamepad mode.

## The screen

- **The status lines:**
  - Row 22 is the skill bar: `CL FL BL BU BA DI` (climber, floater, blocker, builder, basher, digger), each with how many are left. `>` marks the chosen one.
  - Row 23: `O` critters out, `IN` saved / needed, `R` release rate, `T` time, then what the selected critter is doing (C / F: it is a climber / floater).
- **Colours:** the terrain has a colour for each level; the hatch is blue and the exit yellow. The critters are coloured by what they do:

| Colour | Critter |
|---|---|
| light green | walking, falling, climbing |
| white | walking or falling with a skill kept for good (climber or floater) |
| light blue | floating |
| red | blocking |
| yellow | building |
| magenta | bashing |
| cyan | digging |

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 4 | video frames (1/60 s) a game tick takes: 4 = 15 ticks a second. Raise it to slow the game down. |
| $0804 | 0 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The pace is the same at 2 MHz and at 4 MHz.

## How it works

- **The picture:** the playfield (160 × 88 game pixels) is the Graphics II bitmap. A game pixel is 1.5 × 2 screen pixels (screen x = 8 + 1.5 x, y = 2 y), as in DOOM and BREAKER.
- **Drawing the terrain:** the game still keeps the screen in RAM as block graphics characters (`want`, and `shown`, what the screen shows). Digging and building change single pixels there. `flush_px` redraws each group of 8 characters that changed as 3 bitmap cells (DOOM's spreading tables).
- **Text:** drawn into the bitmap with the font (`putc`: 8 pattern bytes and 8 colour bytes a character).
- **Sprites:** sprite 0 is the mouse pointer, then the selection mark, then one 8 × 8 sprite for each critter on the field, rebuilt every tick. The pointer moves every video frame, between ticks too.
- **The mouse:** `SBC_MOUSE` gives the movement since the last call and the buttons; the pointer is kept on the screen, and button presses are noted for the next tick.
- **Memory:** the program runs at $0800 and uses no zero page; the screen copies and the terrain bitmap are at $3300–$49FF.

## Files

| File | What it is |
|---|---|
| `critters.s`, `critters.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `gen_pico.py` → `critters_gfx.inc` | the font, the spreading tables, the sprites and the colours |
| `critters_sound.inc` | the music and effects (unchanged) |
| `CRITTERS.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
