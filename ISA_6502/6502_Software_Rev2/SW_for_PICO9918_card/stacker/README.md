# STACKER for the 6502 SBC (CPU Rev2, PICO9918)

The falling-blocks game, remade for the **PICO9918** card in TMS9918A Graphics I mode.

- **The well:** 10 × 20 squares in the middle of the screen, with each kind of piece in its own colour, and a dotted ghost showing where the piece will land.
- **Around it:** the next piece, the score, lines, level and high score on the right, and the controls on the left.
- **The game itself:** pieces, turning (with the sideways nudges), the lock delay, scoring, levels, the shuffled bag of seven and the music are all the PIC32 version's, unchanged.

## Running

Copy `STACKER.BIN` to the USB drive, then in the monitor:

```
L STACKER 0800
R
```

- **Display check:** the game checks for a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title. Q on the title puts the text console back and goes to the boot menu.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 1 | frames per game tick: 1 = 60 a second (the normal speed), 2 = half speed |
| $0804 | 0 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or ← / → | d-pad left / right (held: repeats) | move |
| W, X or ↑ | A | turn clockwise |
| Z | B | turn back |
| S or ↓ | d-pad down (held) | down a row (1 point a row) |
| Space | d-pad up | drop (2 points a row) |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title (on the title: to the boot menu) |
| 0–9 (title) | | starting level |
| G (title) | | switch keyboard / gamepad |

- **Gamepad:** it works in either mode. The W A S D and space characters that the pad driver types are ignored while a pad button is held, and always in gamepad mode.
- **Arrow keys:** the AVR keyboard's arrows (^P ^D ^E ^X) and a serial terminal's ESC sequences both work.

## Timing

- **Game ticks:** one per frame (60 a second), timed by the VDP. The fall speeds by level are the PIC32 version's (48 ticks a row at level 0, down to 2 at level 19), so the game plays at the same speed whatever the CPU clock.
- **Clearing lines:** a full line flashes for 12 frames.
- **Game over:** the well fills from the bottom up.

## How it works

- **Patterns:** each kind of square (empty, 7 pieces, ghost, flash) is one pattern in its own colour group ($60, $68 … $A8), so every piece has its own colour. The well's sides are $C0 and its floor is $C8.
- **The font:** the console's 5 × 8 font, made bold, with M, W, N and 0 redrawn (`../lib/fontgen.py`).
- **Drawing:** the game builds the picture of the well in RAM (`disp`: the board, the ghost, the falling piece). It keeps what the screen shows (`shown`) and writes only the squares that differ, one name each.
- **The banner:** the title's STACKER banner is made of the piece squares.
- **Zero page:** none is used.

## Files

| File | What it is |
|---|---|
| `stacker.s`, `stacker.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`) |
| `gen.py` → `stacker_data.inc` | pieces, square patterns, colours, banner |
| `stacker_sound.inc` | the music and effects (from `../ay/tools/game_sounds.py`, unchanged) |
| `STACKER.BIN` | ready to load (2 MHz build; the speed doesn't depend on the clock) |
