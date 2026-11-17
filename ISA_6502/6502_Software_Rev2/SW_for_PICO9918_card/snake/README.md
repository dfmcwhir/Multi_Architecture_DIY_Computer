# SNAKE for the 6502 SBC (CPU Rev2, PICO9918)

The classic Snake game, remade for the **PICO9918** card. The game itself is the PIC32 terminal version's, unchanged: the 79 × 45 grid, the snake growing 3 cells for each food, getting faster as it eats, the scoring and the sound. What's new is the picture: a dark green snake with a light green head, red food and a grey border.

## Running

Copy `SNAKE.BIN` to the USB drive, then in the monitor:

```
L SNAKE 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q puts the text console back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| W A S D or the arrow keys | d-pad | steer |
| P | Start | pause (any key, or Start, resumes) |
| M | | sound on / off |
| Q | | quit to the boot menu |

- **Turns:** each press is a turn. Two quick presses within one move are both kept, so you can make a tight U-turn.
- **Controls:** the gamepad is the default. On the title, G switches between keyboard and gamepad; Space or A / Start plays.

## Playing

- **Food:** eat it, and don't hit the walls or yourself.
- **Points:** each food is 10 points and adds 3 cells to the snake.
- **Speed:** the snake speeds up by 2 ms a move for each food, down to about a third of its starting delay.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 90 | starting delay per move, about 1 ms per unit (90: about 10 moves a second) |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The delay is timed for the CPU clock the program was built for, so build with `make.bat 4` for a 4 MHz board.

## How it works

- **The screen:** the Graphics II bitmap.
  - Each grid cell is 3 × 4 screen pixels, so the grid is 237 × 180 pixels: x 9–245, y 10–189.
  - The status line is text row 0.
- **Colours:**
  - The border's lines are in their own 8-pixel bytes and lines, so the colour table can be set once: dark green for the grid, grey for the border, white for the text.
  - The head and the food are sprites: light green, and red. The food is a 5 × 6 sprite, a little bigger than a cell.
- **Each move:** the game draws the new head cell and clears the old tail cell, as before. Each is 4 lines of 1 or 2 bytes, set or cleared in a RAM copy of the bitmap (`shadow`) and written to VRAM.
- **The grid in RAM:** unchanged. One byte per cell; a snake cell holds the direction to the next segment toward the head, so the tail can follow the body.
- **Memory:** the program runs at $0800 and uses no zero page. The grid is at $1C00–$29FF and the bitmap copy at $2A00–$41FF.
- **Testing:** an emulator test ran this version and the PIC32 original side by side, move for move, with a bot on the gamepad, over 7,000 moves and 6 games (one snake grew to 303 cells).
  - Every move it checked that the grid, the snake, the food, the score, the speed and the turn queue were the same in both.
  - Every 5 moves it checked that every cell on the screen matched the grid, and that the head and food sprites were in the right place.

## Files

| File | What it is |
|---|---|
| `snake.s`, `snake.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `gen_pico.py` → `snake_gfx.inc` | the font |
| `SNAKE.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
