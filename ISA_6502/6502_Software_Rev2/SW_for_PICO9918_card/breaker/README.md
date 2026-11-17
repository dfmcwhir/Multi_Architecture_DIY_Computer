# BYTE BREAKER for the 6502 SBC (CPU Rev2, PICO9918)

The brick breaking game, remade for the **PICO9918** card. The game itself is the PIC32 terminal version's, unchanged:
- the ball physics, the 10 levels, the capsules and the scoring;
- the sound on the AY-3-8910 card.

What's new is the picture: tiles and hardware sprites instead of the terminal.

## Running

Copy `BREAKER.BIN` to the USB drive, then in the monitor:

```
L BREAKER 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title; Q on the title puts the text console back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or the arrow keys | d-pad left / right | move the paddle |
| Space | A or B | launch the ball; with the laser, fire |
| P | Start | pause |
| M | | sound on / off |
| Q | | back to the title |

Pressing any gamepad button switches to gamepad mode (G on the title switches too).

## Playing

The same as before: outlined bricks take two hits, checked (steel) bricks never break, and about one broken brick in six drops a capsule:

| Capsule | Power |
|---|---|
| blue, W | **wide** paddle |
| cyan, three dots | **three balls** |
| orange, a line | **slower** ball |
| red, two beams | **laser**: fire shoots from the paddle's ends |
| green, a cup | **catch**: the ball sticks to the paddle |
| grey, a plus | an **extra ball** |

The paddle's ends show its power: red normally, yellow with the laser, green with catch.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 2 | video frames (1/60 s) a game frame takes: 2 = 30 a second. 3 makes the game slower, 1 twice as fast. |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The game keeps its pace at 2 MHz and at 4 MHz (it waits for the video frames).

## How it works

- **Scale:** the game still plays in the terminal's 160 × 96 pixels. A game pixel is 1.5 × 2 screen pixels (screen x = 8 + 1.5 x, y = 2 y), so a text row of the old screen is a tile row and the field is 240 × 192.
- **Graphics II as tiles:** each third of the screen (8 rows) has its own 256 patterns, and each pattern line its own two colours. So every brick row has its own colour, with a white top line.
- **Bricks:** 12 × 8 pixels each. Three tiles hold two bricks, so a tile can show the end of one brick and the start of the next. Each brick row has 21 patterns, one for every combination of neighbours (none, one hit, two hits, steel); `tile_name` picks the pattern from the brick map. A brick that changes rewrites its two tiles.
- **Sprites:** the list is rebuilt each frame (balls on top, then laser shots, capsules, the paddle) and written when the frame is up. The paddle is 2 or 3 sprites for its grey body plus 2 or 3 for its coloured ends; a capsule is a white sign over a coloured pill. Up to 31 sprites a line are allowed (the PICO9918's F18A mode).
- **Text:** `print` reads the texts: TC_ROW / TC_COL set the cursor, RV_ON / RV_OFF switch to the highlighted font (white on blue, patterns $C0–$FF in the top and bottom thirds).
- **VRAM:** patterns $0000, sprite patterns $1800, colours $2000, names $3800, sprite attributes $3B00.
- **Memory:** the program runs at $0800 and uses no zero page.

## Files

| File | What it is |
|---|---|
| `breaker.s`, `breaker.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `gen_pico.py` → `breaker_gfx.inc` | the tiles, bricks, sprites and colours |
| `gen.py` → `breaker_data.inc` | the levels and the ball's speeds (unchanged) |
| `breaker_sound.inc` | the sounds (unchanged) |
| `BREAKER.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
