# MUNCHER for the 6502 SBC

A maze chase game in the style of Pac-Man: eat every dot in the maze while four ghosts hunt you. A power pellet turns the tables for a few seconds. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**: it uses the repeat count in the attribute byte (18 n, bits 3-6) and tiles (19 SET TILE, 0B SEND TILE).
2. Copy `MUNCHER.BIN` to the USB drive, then in the monitor:

```
L MUNCHER 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| W A S D or arrow keys | d-pad | steer (a turn is remembered until the way is open) |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title (Q on the title goes back to the boot menu) |
| G (title screen) | | switch keyboard / gamepad |

Pressing A or Start on the pad at the title screen starts the game in gamepad mode. The byte at $0504 sets the controls at startup: 0 for keyboard (the default) or 1 for gamepad. In gamepad mode the W A S D and space characters the pad driver types are ignored, so a press doesn't act twice.

## Scoring

- **Dots and pellets:** a dot is worth 10 and a power pellet 50.
- **Ghosts:** after a pellet, the ghosts run away for a few seconds and can be eaten. They are worth 200, 400, 800 and 1600 in a row, and their eyes then hurry home to the ghost house.
- **Lives and levels:** you have 3 lives. Each new level is faster and gives less time after a pellet.

## The ghosts

At every tile, a ghost picks the direction (never straight back) that brings it closest to its target. They alternate between scatter phases, when each ghost heads for its own corner, and chase phases:

- **Ghost 1** heads straight for you.
- **Ghost 2** heads for 4 tiles ahead of you.
- **Ghost 3** heads for a point that traps you between it and ghost 1.
- **Ghost 4** chases you, but heads for its corner when it gets close.

The ghosts leave the house one at a time, slow down in the side tunnel, and turn round when a phase changes.

## Sound

MUNCHER plays sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **Background:** a tune before the first READY. While the ghosts hunt a siren plays on channel A; after a power pellet it changes to a faster one until they recover.
- **Effects:** two alternating sounds as dots are eaten, and sounds for a power pellet, eating a ghost, being caught, a cleared maze and GAME OVER.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `muncher_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py muncher` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py muncher OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.

## How it works

- **Maze:** the maze is 39 × 21 tiles. A tile is 4 × 4 pixels, which is two block-graphics characters, so tile (x, y) is at text column 2x, row y.
- **Walls:** they are drawn as outlines. A wall tile gets a 1-pixel line on each side that faces an open tile, which gives the double-line look.
- **Movement:** the muncher and the ghosts move one tile at a time. Each has a speed that is added to an accumulator every game tick, and it moves when that carries. The sprites and the maze tiles (dot, pellet, door) are stored in the terminal as 2 × 1 tiles when the game starts, so drawing one is 2 bytes (0B n) with no 1A prefixes. The cursor is only moved when it isn't already in place: a column-only move on the same row is 2 bytes. Runs of dots in the maze are sent as one tile with a repeat count. In play this sends about 13% fewer bytes per tick than drawing the characters one by one.
- **Changing the maze:** edit `maze.py`, then run `python gen.py > muncher_data.inc` and build. The maze is written as the left half and mirrored. Running `python3 maze.py` checks that every tile is reachable and there are no dead ends.
- **Header:** $0503 is the delay per game tick (default 25 ms). Raise it to slow the game down, for example `503: 30` before `R`.
- **Memory:** no zero page is used. The program occupies $0500–$1E1C and the maze being played $1F00–$22FF.
- **ROM entry points:** the game uses `sbc_api.inc`: `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE` and `SBC_MENU`.

## Files

- `muncher.s`, `muncher.cfg`, `make.bat` (Windows) and `Makefile`: source and build (ca65/ld65). `MUNCHER.BIN` is built for the clock set in `../sbc_api.inc`; see the README one folder up.
- `maze.py`, `gen.py`, `muncher_data.inc`: the maze and the sprites.
- `MUNCHER.BIN`: ready to load.
- `test/`: the emulator harness. A bot plays through two levels, with the keyboard or with `PAD=1` the gamepad. Every few ticks every tile on the screen is checked against the maze in RAM and the actors.
- `screenshots/`: images from that harness.
