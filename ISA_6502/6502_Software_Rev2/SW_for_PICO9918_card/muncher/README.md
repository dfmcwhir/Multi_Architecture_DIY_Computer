# MUNCHER for the 6502 SBC (CPU Rev2, PICO9918)

The maze chase game, remade for the **PICO9918** card. The game itself is the PIC32 terminal version's, unchanged: the maze, the muncher, the four ghosts and their rules, the scoring, the levels and the sound. What's new is the picture: a blue maze with yellow dots, colour sprites, and actors that glide smoothly from tile to tile.

Eat every dot in the maze while four ghosts hunt you. A power pellet turns the tables for a few seconds.

## Running

Copy `MUNCHER.BIN` to the USB drive, then in the monitor:

```
L MUNCHER 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title; Q on the title puts the text console back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| W A S D or the arrow keys | d-pad | steer (a turn is remembered until the way is open) |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title |

The gamepad is the default. On the title, G switches between keyboard and gamepad; Space or A / Start plays.

## Scoring

- **Dots and pellets:** a dot is 10, a power pellet 50.
- **Ghosts:** after a pellet the ghosts turn blue and run; eaten, they are worth 200, 400, 800 and 1600 in a row, and their eyes hurry home. They flash white when the time is nearly up.
- **Lives and levels:** 3 lives. Each level is faster and gives less time after a pellet.

## The ghosts

At every tile a ghost picks the way (never straight back) that brings it closest to its target. They switch between scatter phases (each to its own corner) and chase phases:

| Ghost | Colour | Chasing, it heads for |
|---|---|---|
| 1 | red | you |
| 2 | light green | 4 tiles ahead of you |
| 3 | cyan | a point that traps you between it and ghost 1 |
| 4 | dark yellow | you, but its corner when it gets close |

They leave the house one at a time, slow down in the side tunnel, and turn round when a phase changes.

## The screen

- **The maze:** 39 × 21 tiles, each 6 × 8 screen pixels, on rows 0–20. The status lines are rows 22–23: score, high score, lives and level.
- **Colours:** blue walls, yellow dots and pellets (the pellets flash), a white door on the ghost house. The muncher is yellow.
- **Moving:** the game moves the muncher and the ghosts a whole tile at a time, as before; on the screen each one glides there. The picture runs a tile behind the game, so a dot disappears just ahead of the muncher's mouth.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 2 | video frames (1/60 s) a game tick: 2 = 30 ticks a second; 3 is slower |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The pace is the same at 2 MHz and 4 MHz.

## How it works

- **Two tile layers (Graphics I and the F18A's second layer):**
  - Layer 1 has the walls. Their patterns are made from the maze by `gen_pico.py`, so walls never change.
  - Layer 2, on top, has the dots, the pellets and the door. Its blank pixels are see-through.
  - In Graphics I one 8-pixel line of a cell has only one colour. With the dots on their own layer, a dot next to a wall keeps its colour.
  - Four tiles make 3 cells. A tile's change redraws its group of 4: 3 names from a table indexed by the 4 tiles' codes.
- **Sprites:** 8 × 8. Sprite 0 is the muncher, 1–4 the ghosts' eyes, 5–8 their bodies.
  - Each actor's sprite moves from the tile it was on towards the one it is on, by how full its speed accumulator is.
  - When the game moves an actor (the accumulator carries), the sprite has just arrived at the old tile.
- **Text:** READY!, PAUSED and GAME OVER go on layer 2 (yellow), the status lines on layer 1 (white). The font is the games' bold one.
- **The pellets flash:** by changing their colour groups in layer 2's colour table every 8 ticks.
- **Memory:** the program runs at $0800 and uses no zero page. The maze being played is at $3000–$33FF.
- **Testing:** an emulator test ran this version and the PIC32 original side by side, tick for tick, with a bot on the gamepad. After every tick it checked:
  - the whole game state is the same in both;
  - layer 1 shows the walls and layer 2 the dots of the maze in RAM;
  - each sprite has the right picture and colour, within a tile of its actor.

  It ran through levels 1–2, with deaths, pellets and eaten ghosts, without a difference.

## Changing the maze

Edit `maze.py` (the left half; it is mirrored), then:

```
python3 maze.py                 every tile reachable, no dead ends?
python3 gen.py > muncher_data.inc
python3 gen_pico.py             the wall patterns and dot tables
make.bat
```

## Files

| File | What it is |
|---|---|
| `muncher.s`, `muncher.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `maze.py`, `gen.py` → `muncher_data.inc` | the maze (unchanged) |
| `gen_pico.py` → `muncher_gfx.inc` | the wall patterns, the dot layer's tables, the colours, the sprites, the font |
| `muncher_sound.inc` | the sounds (unchanged) |
| `MUNCHER.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
