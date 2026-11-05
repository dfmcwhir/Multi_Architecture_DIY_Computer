# 6502 DOOM for the 6502 SBC

A first-person shooter in the spirit of the 1993 game. Nothing is taken from the original: the code, maps, art and the DOOM banner are all new. It runs from the monitor at $0500 on the PIC32 terminal.

Walk through a raycast 3D maze drawn in block graphics, open doors, shoot grunts and brutes, pick up medkits and ammo, and press the exit switch to finish each map.

- **Loading:** the engine is loaded once (DOOM.BIN, about 14 KB). Each map is a separate file on the USB drive and is loaded only when you reach it: E1M1.LVL, then E1M2.LVL, then E1M3.LVL.
- **Disk access:** maps are read with the new ROM entry point **SBC_LOAD** ($FE15). See `SBC_LOAD.md` for the spec.
- **Older ROMs:** on a ROM without SBC_LOAD the game plays a built-in copy of E1M1, then says it can't load the next map.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**: it uses the repeat count in the attribute byte (18 n, bits 3-6) and tiles (19 SET TILE, 0B SEND TILE).
2. Copy `DOOM.BIN`, `E1M1.LVL`, `E1M2.LVL` and `E1M3.LVL` to the USB drive, then in the monitor:

```
L DOOM 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| W / S or Up / Down | d-pad up / down | walk forward / back |
| A / D or Left / Right | d-pad left / right | turn |
| , and . | Select + left / right | strafe |
| Space or F | A (hold) | fire |
| E | B | use: open a door or press the exit switch, facing it |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title (Q on the title goes back to the boot menu) |
| G (title screen) | | switch keyboard / gamepad |

- **Gamepad mode:** pressing A or Start on the pad at the title screen starts in gamepad mode. The byte at $0504 sets the controls at startup: 0 keyboard (default), 1 gamepad.
- **Typed characters:** in gamepad mode, the characters the pad driver types are ignored.
- **Key repeat:** if the keyboard's key repeat is faster than the frame rate, a held turn key turns twice as far per frame.

## Playing

- **Health and ammo:** you start with 100 health and 50 bullets. A medkit gives 25 health and is left lying if you are already at 100. An ammo box gives 10 bullets. Walk over items to pick them up.
- **Grunts:** they wake when they see you within 8 tiles, walk towards you and shoot. They have 30 health, so 2 or 3 shots kill one.
- **Brutes:** 90 health. Slower than grunts, but they hit hard up close.
- **Gunshots:** firing wakes everything within 8 tiles.
- **Shooting:** the gun hits the nearest enemy across the middle of the screen, if no wall is in the way.
- **Doors** are solid bright blocks; ordinary walls are dotted. Face one and press E to open it. Doorways are one tile wide; walking into the edge of one slides you into line with it.
- **The exit switch** is solid with dark horizontal stripes. Face it and press E to finish the map. You get a kills/items tally, then the next map loads.
- **Dying** restarts the current map (reloaded from disk) with full health and at least 20 bullets.

## Speed

Measured in the emulator, sending at 115200 baud:

| Situation | 1 MHz | 2 MHz |
|---|---|---|
| Walking | about 4–4.5 fps | about 8 fps |
| Turning | about 3.8 fps | about 7 fps |

The enemies act once per drawn frame, so on a faster clock they get faster too. Waits (and the `$0503` delay) stay in real milliseconds, set by `CLOCK_MHZ` in `sbc_api.inc`.

Turning redraws most of the view, but now takes about 390 bytes over the serial line. Before tiles and repeat counts it took about 760. Only characters that changed since the last frame are sent, and runs of the same character use the terminal's repeat count.

When nothing in view has changed (you stand still and nothing moves), nothing is drawn. The game waits about as long as a frame would take, so the enemies keep their pace, but it reacts to a key within about 60 ms.

The byte at $0503 adds a delay per frame in ms (default 0). For example, `503: 40` before `R` slows it down.

## Sound

6502 DOOM plays music and sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **Music:** a low, uneasy bass line, written for this game, loops through each level with a few quiet notes above it.
- **You:** the pistol bangs, an empty gun clicks, doors rumble open and pickups chime. Getting hit plays a grunt, and dying a long fall.
- **Enemies:** a growl when one sees you, a shot when it attacks, a cry when hit, and a bang when it dies.
- **Levels:** finishing one plays a short tune.
- **Timing while drawing:** the view takes a while to draw, so the game also checks the sound's timer for each column, each thing and each row it sends. The music keeps its beat.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `doom_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py doom` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py doom OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.

## How it works

- **Raycasting:** the map is 32 × 32 tiles. A ray is cast for every other text column and followed through the map one tile edge at a time (a DDA). Its perpendicular distance gives the wall height.
- **The other columns:** a column between two rays that hit the same face of the same block is averaged from them; otherwise it gets its own ray. About 50 rays are cast per frame instead of 80.
- **Maths:** multiplication uses quarter-square tables. Angles run 0–1023 per turn and positions are 8.8 fixed point. No zero page is used.
- **Walls:** ordinary walls are a dither that is denser on east/west faces than on north/south ones and thins out with distance. A thin line marks where one block ends and the next begins. Doors are solid and the exit switch is striped at every distance, so they stand out. The floor and ceiling are black. The patterns are in `gen_tables.py` (`WALL`, `PAT`, `FLOOR`) if you want to try others; run `python gen_tables.py > tables.inc`, then build.
- **Things:** enemies and items are 8 × 8 bitmaps (shape mask plus fill), scaled to the distance. They are clipped against a per-column wall-distance buffer and drawn far to near. Things beyond every wall in view are skipped early.
- **Screen:** the view is 80 × 18 characters (160 × 72 pixels). It is built in a frame buffer and compared with a copy of what the terminal shows. Only the differences are sent, with the cursor moved as little as possible. A changed character that starts a run of the same character (black floor, a solid door, a stretch of wall) is sent once with the repeat count in the attribute byte (18 n), and the count is left set while the next runs can use it. About half the bytes of the old method.
- **Memory:**

  | Range | Contents |
  |---|---|
  | $0500–$4B4F | program and variables (the sound included) |
  | $5000–$55FF | the level being played |
  | $5600–$61FF | the two frame buffers |

## Making maps

`mklevels.py` turns ASCII maps into .LVL files. Edit the `LEVELS` list and run `python mklevels.py`. It checks that every enemy, item and the exit can be reached.

The legend:

| Character | Meaning |
|---|---|
| `#` | brick wall |
| `%` | tech wall |
| `@` | stone wall (the three wall types all look the same for now; their patterns are in `gen_tables.py`) |
| `D` | door |
| `X` | exit switch |
| `.` | floor |
| `P` | player start |
| `g` | grunt |
| `B` | brute |
| `+` | medkit |
| `a` | ammo |

The map must be 32 × 32 with walls all round the edge, and hold at most 32 things.

The .LVL format (1–1.2 KB):

| Offset | Contents |
|---|---|
| 0 | "D6", version 1 |
| 3 | start x, start y, start angle (0–255, 0 = east, 64 = south) |
| 6 | name (16 characters) |
| 22 | next map's file name (12 bytes, zero padded; empty for the last map) |
| 34 | number of things |
| 64 | the 32 × 32 map: 0 floor, 1 brick, 2 tech, 3 stone, 4 door, 5 exit |
| 1088 | things, 4 bytes each: type (1 grunt, 2 brute, 3 medkit, 4 ammo), x, y, 0 |

Because each map names the next one, you can add E1M4 and beyond, or a different episode, without changing the engine.

## Files

| File | What it is |
|---|---|
| `doom.s`, `doom.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` (see the README one folder up). After changing the scripts below, run them with Python first. |
| `gen_tables.py` → `tables.inc` | sine and 1/cos tables, wall heights, squares for multiplying, wall patterns, sprites, the gun and the title banner |
| `mklevels.py` → `E1M1.LVL`, `E1M2.LVL`, `E1M3.LVL`, `builtin.inc` | the maps; `builtin.inc` is the built-in copy of E1M1 |
| `DOOM.BIN` | ready to load |
| `SBC_LOAD.md` | the spec for the new ROM entry point |
| `loadtest/` | LOADTEST.BIN, to check SBC_LOAD on the real board |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`sim.py`:** traps SBC_LOAD to read files from the folder.
- **`play.py`:** a bot plays E1M1 → E1M3 with the keyboard or the gamepad (`PAD=1`), with random RAM at start (`GARBAGE=n`) or on a ROM without SBC_LOAD (`NODISK=1`). Every frame, the terminal's picture is checked against the frame buffer and the status line against the game's numbers.
- **`raytest.py`:** compares the ray caster with a floating-point one at random spots in every map.
- **`unit.py`:** tests the multiply routines.
- **`menus.py`:** tests the title, pause and quit keys.
- **`prof.py`, `ftime.py`:** measure where the time goes.
