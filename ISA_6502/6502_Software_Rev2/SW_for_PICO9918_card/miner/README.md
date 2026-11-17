# MINER MOS for the 6502 SBC (CPU Rev2, PICO9918)

The single-screen platform game, remade for the **PICO9918** card. The game itself is the PIC32 terminal version's, unchanged: the 8 rooms, the movement, the jump, the guardians, the air, the score and the sound. What's new is the picture, now in colour.

MOS the miner is deep inside the 6502, and his air is running out. In each room, take every key, then get to the portal before the air is gone. Keep clear of the guardians and the spikes, and don't fall too far. After the last room they start again.

## Running

Copy `MINER.BIN` to the USB drive, then in the monitor:

```
L MINER 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title; Q on the title puts the text console back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or ← / → | d-pad left / right | walk |
| Space, W or ↑ | A, B or d-pad up | jump |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title |

Pressing any gamepad button switches to gamepad mode (G on the title switches between keyboard and gamepad). On the title and at GAME OVER, Space or A / Start plays.

## Playing

- **Jumping:** MOS jumps 3 tiles up and about 4 across, always the same arc, and can't be steered in the air. He can jump up through a floor from below; walls stop him every way.
- **Falling:** walking off an edge drops him straight down. A fall of more than 6 tiles kills him.
- **Floors:** a solid floor; bricks (a wall); a conveyor (grey, with a zigzag), which carries MOS its way; a broken line, a crumbling floor that gives way under him; a little green plant, the spikes. Keys are the yellow loops.
- **Guardians** walk to and fro or bob up and down. Touching one costs a life.
- **Air:** the white bar on row 21. When it runs out, a life goes.
- **The portal** is shut (grey) until every key is taken, then it flashes. Walk into it: the air left goes to the score, and the next room starts.
- **Points:** 100 a key, 10 for each unit of air left at the portal; an extra life every 10,000. You start with 3.

## The screen

- **The room:** rows 0–19, 40 × 20 tiles; its name on row 20, the air on row 21, and on row 23 the score, `HI` the high score, `L` the lives and `RM` the room.
- **Colours:** each room has its own floor and wall colours on black. The conveyors are grey, the spikes green, the keys yellow.

| Colour | Guardian |
|---|---|
| cyan | robot |
| yellow | bird |
| green | blob |
| magenta | spinner |
| grey | skull |
| blue | jellyfish |

  MOS is white. No palette colours are changed.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 5 | video frames (1/60 s) for two game frames: 5 = 24 frames a second, the original's 40 ms |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The pace is the same at 2 MHz and 4 MHz (checked in the emulator in the busiest rooms).

## How it works

- **The room:** drawn into the Graphics II bitmap, a game pixel 1.5 × 2 screen pixels, as in DOOM, BREAKER, CRITTERS and GRABBER. A tile is 4 × 4 game pixels, 2 block graphics characters; 4 tiles make 3 bitmap cells, each coloured by the tiles in it. The whole room is drawn when it starts; after that only the group with a changed tile (a key taken, a floor crumbling) and the air bar's last cell.
- **Sprites:** MOS, the portal and up to 7 guardians are 16 × 16 sprites. Each of the 19 pictures comes in 4 versions (facing either way, at an even or odd x, for the 1.5 × scaling), made by `gen_pico.py`; a sprite's pattern is reloaded only when its version changes.
- **Text:** drawn into the bitmap with the font.
- **Pacing:** the 60 Hz tick counter; two game frames take 5 video frames (2 + 3).
- **Sound:** the AY card, as before (`../ay`).
- **Memory:** the program runs at $0800 and uses no zero page; it ends at about $42A0.
- **Testing:** an emulator test played all 8 rooms with planned inputs, checking every frame against the Python rules (MOS, the guardians, the keys, the air, every sprite) and the bitmap against the room's tiles. All 8 rooms finished without losing a life.

## Making rooms

Edit `rooms.py` (19 lines of 38 characters per room, plus the guardians; the legend is at the top), then:

```
python3 check_rooms.py          every key and the portal can be reached?
python3 gen.py > miner_data.inc
python3 gen_pico.py             (only if the pictures or room colours changed)
make.bat
```

The room colours are `ROOM_COL` (floor, wall) in `gen_pico.py`.

## Files

| File | What it is |
|---|---|
| `miner.s`, `miner.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `rooms.py`, `gen.py` → `miner_data.inc` | the rooms and pictures (unchanged) |
| `gen_pico.py` → `miner_gfx.inc` | the colours, the sprite versions, the font, the spreading tables |
| `phys.py`, `check_rooms.py` | the rules in Python; the room checker |
| `miner_sound.inc` | the music and sounds (unchanged) |
| `MINER.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
