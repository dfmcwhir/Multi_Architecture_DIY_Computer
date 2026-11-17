# GOLD GRABBER for the 6502 SBC (CPU Rev2, PICO9918)

The treasure grabbing game, remade for the **PICO9918** card. The game itself is the PIC32 terminal version's, unchanged: the swinging grabber, the pit, gophers and TNT, the shop, the goals and the sound. What's new is the picture: version 2 draws everything at the screen's full resolution, in the PICO9918's 4-colour-per-tile mode, with no more blocks.

## Running

Copy `GRABBER.BIN` to the USB drive, then in the monitor:

```
L GRABBER 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title; Q on the title puts the text console (and the palette) back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| Space, S or ↓ | A or d-pad down | fire the grabber |
| B, W or ↑ | B or d-pad up | bomb what the grabber holds |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title |

Pressing any gamepad button switches to gamepad mode (G on the title switches too). In the shop: up/down (pad, W/S or the arrow keys) choose, A / Space buys or goes on; 1-4 buy, N goes on.

## The screen

- **The status line:** your money / the goal, `L` the level, `T` the seconds left, `B` bombs, then `S` (strength), `G` (double gems) and `L` (laser pointer) while they last. "+$..." shows in the sky for a moment after each catch.
- **The field:** a blue sky with clouds, the miner in his helmet on a wooden platform with the winch (it turns while reeling in), grass, and a pit of textured dirt.
- **The things:** wooden chests with gold bands, blue gems, shaded grey rocks, bundles of red TNT, brown gophers (carrying a gem in their mouth when they have one). A thin rope, a metal claw that turns with the rope, orange and yellow bangs, and the laser pointer's dots with a ring where it would grab.
- **Colours:** the PICO9918's own palette (64 colours) is loaded at the start; quitting with Q resets the PICO9918, which puts its default palette back. If you reset the computer during the game instead, the console may show odd colours until the power goes off.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 3 | video frames (1/60 s) a frame takes: 3 = 20 frames a second, the original speed |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The pace is the same at 2 MHz and 4 MHz.

## How it works

The PICO9918 runs in Graphics I with the F18A's enhanced colour mode ECM2 (2 bits a pixel: each tile pattern and sprite has 3 colours and see-through, from one of 16 groups of 4 palette entries), both tile layers on, 16 x 16 sprites. A game pixel is 1.5 x 2 screen pixels (screen x = 8 + x + x/2, y = 8 + 2y).

- **Tile layer 1 (still):** the field's background, made by `gen_pico.py` as a whole picture and cut into 8 x 8 patterns (54 different ones with the miner's); text, white on black.
- **Tile layer 2 (on top of layer 1, under the sprites):** the miner, the platform and the winch; highlighted text (white on blue); and the things lying in the pit. When a level starts, `compose` draws each thing's picture into patterns of its own (shifted to its exact place, sharing cells with neighbours), from a pool of 133 patterns (from $9C, and 27 font letters the field's text never uses; the font is put back when the field goes). When a thing is taken, its cells are cleared and anything sharing them is drawn again. The most a level needed in testing (24 levels) was 111.
- **Sprites:** the claw (5 directions, open and shut), what it holds, the gophers and their gems, the bangs, the target ring: parts of 16 x 16 kept in the program and loaded into one of 30 sprite patterns when needed. The rope and the laser are drawn into their own pattern (for the current direction) by the program, and placed every 13 pixels along the line.
- **Speed:** a game frame takes at most a third of its time at 2 MHz, so the pace is the original's at 2 and 4 MHz.
- **VRAM:**

  | Address | Contents |
  |---|---|
  | $0000 / $0800 | tile patterns, planes 0 and 1 |
  | $1000 / $1400 | sprite patterns, planes 0 and 1 |
  | $1800 | layer 1 names |
  | $1C00 / $1D00 | layer 1 / layer 2 attributes |
  | $1E00 | sprite attributes |
  | $2000 | layer 2 names |
- **Registers:** R49 = $A2 (layer 2 on, ECM2 tiles and sprites), R29 = $40 (sprite planes 1K apart), R30 = 31 sprites a line, R50 = 1 (layer 2 under the sprites), R1 = $C2.
- **Memory:** the program runs at $0800 and uses no zero page; layer 2's copy, the pool and the sprite table end at about $6200.

## Files

| File | What it is |
|---|---|
| `grabber.s`, `grabber.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `disp2.s` | the picture (included by grabber.s) |
| `gen_pico.py` → `grabber_gfx.inc` | all the art, the palette, the font; `python gen_pico.py png` draws `sheet.png` to look at |
| `gen.py` → `grabber_data.inc` | the game's own pictures (their sizes still set what the claw can catch), the rope's directions |
| `grabber_sound.inc` | the sounds (unchanged) |
| `GRABBER.BIN` | ready to load (4 MHz build) |
| `test_play.py`, `test_scen.py`, `test_look.py` | the emulator tests and screenshots |
| `port.py`, `*_part.s` | history: how the first PICO9918 version was made from the PIC32 one |
