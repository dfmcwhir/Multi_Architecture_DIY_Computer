# SNAKE for the 6502 SBC

The classic Snake game. It runs from the monitor at $0500 and draws on the PIC32 terminal, mostly with the set and reset pixel codes.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**: it uses the repeat count in the attribute byte (18 n, bits 3-6) and tiles (19 SET TILE, 0B SEND TILE).
2. Copy `SNAKE.BIN` to the USB drive, then in the monitor:

```
L SNAKE 0500
R
```


**Header:** the layout is the same as INVADERS. $0503 is the starting delay per move, about 1 ms per unit. The default is $5A (90 ms), which is roughly 10 moves a second. The snake speeds up by 2 ms per food, down to about 30% of the starting delay. To start faster, for example, enter `503: 40` before `R`. $0504 sets the controls at startup (0 keyboard, 1 gamepad).

## Keys

**Gamepad:** each press on the d-pad is a turn (two quick presses within one move are both kept), and Start pauses.


| Key | Action |
|---|---|
| W A S D or arrow keys | steer |
| P | pause (any key resumes) |
| M | sound on / off |
| Q | quit to the boot menu |
| G (title screen) | switch keyboard / gamepad |

Two quick key presses within one move are both kept, so you can make a tight U-turn.

## Keyboard or gamepad

The title screen shows the current controls. Press **G** to switch between keyboard and gamepad, or just press **A** or **Start** on the pad, which starts the game in gamepad mode. The byte at $0504 sets the controls at startup: 0 for keyboard (the default) or 1 for gamepad.

In gamepad mode the game reads the buttons directly with `SBC_PADSTATE` ($FE12). It ignores the W, A, S, D and space characters that the pad driver also types, so a press doesn't act twice. The other keyboard keys (P, Q and so on) still work.

## ROM entry points

The game includes `sbc_api.inc` and calls the ROM through the fixed table at $FE00: `SBC_CHRIN`, `SBC_CHROUT` and `SBC_PADSTATE`. Q exits with `JMP SBC_MENU`. A firmware rebuild no longer breaks it, as long as that table stays put. `make` needs `sbc_api.inc` next to the source.

## Sound

SNAKE plays sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **The sounds:** a short tune when a game starts, a blip for each bite of food, a crash (noise and a falling tone), and at GAME OVER a falling phrase, or a fanfare for a new high score.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** short scripts at the end of `snake.s` (`s_start` ... `s_hi`).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py snake OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.

## How it works

- **Screen:** the screen is 160 × 96 pixels. The snake moves on a grid of 79 × 45 cells, each 2 × 2 pixels, so the cells are square on the screen. The border is a 1-pixel line, drawn as block graphics characters: the top and bottom with the repeat count, the sides as two 1 × 21 tiles. That is about 130 bytes instead of about 1,500 as pixels.
- **Each move:** the game sets the 4 pixels of the new head cell and resets the 4 of the old tail cell. That is about 24 bytes per move, whatever the snake's length.
- **The grid in RAM:** the playfield is also kept in RAM at $0E00–$1BFF, one byte per cell. Each snake cell holds the direction to the next segment toward the head, so the tail can follow the body. There is no length limit.
- **Food:** 2 diagonal pixels in a cell. Each food is worth 10 points and adds 3 segments.
- **Memory:** no zero page is used. Grid cells are reached with self-modifying code. The program occupies $0500–$1269 and the grid $1300–$20FF.

## Files

- `snake.s`, `snake.cfg`, `make.bat` (Windows) and `Makefile`: source and build (ca65/ld65). `SNAKE.BIN` is built for the clock set in `../sbc_api.inc`; see the README one folder up.
- `SNAKE.BIN`: ready to load.
- `test/`: the emulator harness. A bot plays the game, and after every few moves the screen is checked against the grid in RAM.
- `screenshots/`: images from that harness.
