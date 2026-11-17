# SPACE ROCKS for the 6502 SBC (CPU Rev2, PICO9918)

The rock shooter, remade for the **PICO9918** card. The game itself is the PIC32 terminal version's, unchanged: the ship, the rocks, the saucers, the waves, the scoring and the sound, and even its drawing of the field into RAM. What's new is the screen: the field is the PICO9918's bitmap, white on black like the arcade's.

Steer a small ship through a field of drifting rocks and shoot them. Big rocks break into two medium ones, medium into two small, and small ones turn to dust. Clear the field and a new, faster wave comes in. Now and then a flying saucer crosses the field and shoots at you.

## Running

Copy `ROCKS.BIN` to the USB drive, then in the monitor:

```
L ROCKS 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title; Q on the title puts the text console back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or ← / → | d-pad left / right | turn |
| W or ↑ | d-pad up | thrust |
| Space | A | fire |
| S or ↓ | B (or d-pad down) | hyperspace: jump to a random place |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title |

The gamepad is the default; G on the title switches between keyboard and gamepad. With the keyboard, a turn or thrust key keeps working for a couple of frames after each key repeat, so holding it turns or thrusts smoothly.

## Playing

- **The ship:** it drifts with what speed it has and slows down a little by itself. The edges of the field wrap round, for the ship, rocks and bullets alike.
- **Bullets:** up to 4 in flight. Each flies a little under half the width of the field.
- **Points:** big rocks 20, medium 50, small 100; big saucer 200, small saucer 1,000. An extra ship every 10,000 points (up to 9).
- **Saucers:**
  - **When:** every 15–30 seconds or so while your ship is out, a saucer crosses the field.
  - **Big saucer:** shoots in random directions.
  - **Small saucer:** turns up from wave 3, or once you have 10,000 points. It aims at your ship, a little off before wave 6 and dead on after.
  - **Collisions:** a saucer that flies into a rock destroys both, with no points. Flying into a saucer costs you a ship but scores it.
- **Ships:** you start with 3. After a crash the ship comes back in the middle once that area is clear, and blinks for a moment while it can't be hit.
- **Waves:** 4 big rocks in the first wave and one more each wave, up to 8. Every wave the rocks are a little faster.

## The screen

- **The status line (row 0):** `SCORE`, `HI` (the high score), `S` (ships left) and `W` (the wave). PAUSED shows there too.
- **The field:** text rows 1–23, 160 × 92 game pixels. Each game pixel is 1.5 × 2 screen pixels, as in DOOM, BREAKER, CRITTERS, GRABBER and MINER.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 10 | video frames (1/60 s) for 3 frames: 10 = 18 frames a second, the original's 55 ms |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

- **At 4 MHz:** the game keeps 18 frames a second however busy the field is.
- **At 2 MHz:** with a dozen or so rocks on the field, it slows to about 16–17 frames a second.

## How it works

- **Drawing, as before:** the game draws each frame into `fb`, 80 × 23 block graphics characters of 2 × 4 pixels.
  - Rocks are pre-drawn characters ORed in; the ship, saucer, bullets and debris are pixels.
  - Each row is split into ten blocks of 8 columns, and the game notes which blocks it drew in this frame and the last.
- **New: the bitmap.** `present` compares those blocks with `sb` (what the screen shows).
  - Each block that changed is drawn as 3 bitmap cells (24 × 8 screen pixels), using tables that spread each character's pixels 1.5 across and 2 down (`gen_pico.py`).
  - The colours are set once (white on black); only the patterns are written.
- **Text:** drawn into the bitmap with the font (the status line, the title, PAUSED, GAME OVER).
- **Pacing:** the ROM's 60 Hz counter, 3 + 3 + 4 video frames for three game frames.
- **Gone:** the PIC32 terminal's sprite support, its IDENTIFY pacing and its timing model.
- **Memory:** the program runs at $0800 and uses no zero page; the screen buffers are at $4300–$52FF.
- **Testing:** an emulator test ran this version and the PIC32 original side by side, frame for frame, with a bot on the gamepad. Every frame it checked that the game was the same in both: every object, the score, the timers, and the field buffers `fb` and `sb`. Every 4 frames it checked that the bitmap shows `sb`. It ran through waves 1–8 (about 9,500 frames over two runs), with saucers and ships lost, without a difference.

## Files

| File | What it is |
|---|---|
| `rocks.s`, `rocks.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `gen.py` → `rocks_data.inc` | the sine table, the ship's headings, the rock and saucer shapes, the pre-drawn rocks (unchanged) |
| `gen_pico.py` → `rocks_gfx.inc` | the font and the bitmap spreading tables |
| `rocks_sound.inc` | the sounds (unchanged) |
| `ROCKS.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
