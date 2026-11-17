# 6502 DOOM2 for the 6502 SBC (CPU Rev2, PICO9918)

The 6502 DOOM engine with a new picture and five new maps. The game itself is the same: the ray caster, the enemies and their behaviour, doors, pickups, the music and the sound.

What's new:
- **The view is drawn at the screen's own resolution** instead of 2 × 4 block characters scaled up:
  - 120 columns of 2 pixels by 144 lines;
  - wall edges in single-line steps;
  - textured walls;
  - monsters and items drawn as 32 × 48 pictures, scaled to their distance and hidden behind walls column by column.
- **The ceiling and floor** fade to black towards the horizon.
- **The gun** is drawn as colour sprites: a pistol in a hand, with a muzzle flash, bobbing while you walk.
- **Five new maps**, MAP01–MAP05, with two new wall styles, wood and metal.

## Running

Copy `DOOM2.BIN` and `MAP01.LVL` … `MAP05.LVL` to the USB drive, then in the monitor:

```
L DOOM2 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918 and SBC_LOAD (the maps are loaded from the drive).
- **Quit:** Q on the title resets the PICO9918 (its palette too) and goes back to the boot menu.
- **Controls:** the same as DOOM.
  - Keyboard: W/S move, A/D turn, `,` `.` strafe, Space fire, E use, P pause, M sound.
  - Pad: D-pad move/turn, A fire, B use, Select + left/right strafe, Start pause.
  - G on the title switches between keyboard and pad.

## The maps

| File | Name | What's in it |
|---|---|---|
| MAP01.LVL | THE GATEHOUSE | a wooden hall, a stone yard with pillars, barracks, a store, and the metal gate hall with the exit |
| MAP02.LVL | THE FOUNDRY | a long metal hall with tech workshops off it, wooden stores, and a brick furnace room full of brutes |
| MAP03.LVL | THE CATACOMBS | a stone maze with four wooden crypts; the exit is in the far corner |
| MAP04.LVL | THE DATA CENTRE | four halls of tech server racks round a metal core |
| MAP05.LVL | THE PIT | a brick arena of stone pillars and brutes, with wooden pens round it |

`mklevels.py` makes them. It carves rooms with walls of their own style, doors and passages, and checks the following:
- everything is reachable from the start;
- the exit switch can be reached;
- every door sits in a wall.

MAP03's maze is generated from a fixed seed, so it is the same every time. The file format is DOOM's, so DOOM's E1M*.LVL maps also load if renamed. DOOM ignores the two new wall styles.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 6 | the least time a game frame takes, in 1/60 s: 6 = at most 10 frames a second (the enemies' pace) |
| $0804 | 0 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

## Speed

Measured in the emulator, with the game's cap of 10 frames a second:

| Clock | Frames a second |
|---|---|
| 4 MHz | 10 (the cap) in most places; about 8 with near walls and monsters on screen. A frame takes about 340,000 cycles. |
| 2 MHz | about 6–7 |

Build for your clock (`make.bat 4`): the sound engine's timing depends on it.

## The picture

The PICO9918 runs in Graphics II (a bitmap: each 8-pixel line of a cell has 2 colours), with the F18A palette set to 16 colours chosen for the game. The view takes cell columns 1–30 and rows 0–17 (240 × 144); the status lines are rows 18–23.

**Name layout.** The view's names are arranged so that each 8-pixel-wide cell column's 144 lines sit together in VRAM:
- rows 0–7 and 8–15: name = column × 8 + row;
- rows 16–17: name = column × 2 + row − 16.

So a cell column is 64 + 64 + 16 bytes of patterns, and the same of colours.

**Each frame:**
1. **Rays:** every third column is cast, and so is the last. The two columns between are worked out from their neighbours when both hit the same face of the same block (the height, the place on the texture and the distance), otherwise they are cast too. Each ray also gives the place along the face it hit (the texture column).
2. **Cell columns:** each of the 30 is built in RAM, then sent to VRAM:
   - **Walls:** the 4 columns' tops and bottoms are sorted. Between those 8 places the same columns show wall, so each run is filled with one pattern byte and one colour by an unrolled chain of stores. The wall's colour comes from the nearest column, by style, side and distance.
   - **Textures:** each texture column is a list of dark runs (16 × 32 texels). A run's lines are y0 + v × h / 32, worked out with a quarter-square table. Neighbouring columns with the same texture column and height are done together.
   - **Things,** far to near: a column shows a thing only where the thing is nearer than the wall there. On a line, the thing's pixels take its colour; the rest of that byte takes the wall's colour (or the dark of the ceiling or floor), so there is no box of the thing's colour round it.
   - Only the lines the last cell column changed are put back to the ceiling and floor.
3. **The gun:** up to 18 sprites (16 × 16, ECM2: 3 colours each from 3 palette groups for metal, hand and flash), drawn from the gun's picture with or without the flash.

**Colours (the 16):** black, two each for the ceiling and floor, brick, tech, stone and wood (light and dark), yellow and green. Doors are yellow, the exit switch green, metal walls stone grey. Grunts are green, brutes red, the dead dark red, medkits light grey, ammo yellow.

**VRAM:**

| Address | Contents |
|---|---|
| $0000–$17FF | patterns (3 thirds) |
| $1800 / $1C00 | the gun's sprite patterns, planes 0 and 1 |
| $2000–$37FF | colours |
| $3800 | names |
| $3B00 | sprite attributes |

**Registers:** R49 = $02 (ECM2 sprites), R29 = $40 (sprite planes 1K apart), R30 = 31, R1 = $C2.

**Memory:**

| Range | Contents |
|---|---|
| $0800–$6DBF | the program |
| to $7881 | its variables |
| $7900–$7EFF | the level |

No zero page is used.

## Files

| File | What it is |
|---|---|
| `doom2.s`, `doom2.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `view.s` | the picture: rays between, cell columns, textures, things, the gun (included by doom2.s) |
| `gen_tables.py` → `tables.inc` | the engine's tables for 120 columns, the palette, wall textures, the monsters and items, the gun, the title logo, the font. `python gen_tables.py png` draws them all into `art.png`. |
| `mklevels.py` → `MAP01.LVL` … `MAP05.LVL` | the maps (`python mklevels.py show` prints them) |
| `doom_sound.inc` | the music and effects (DOOM's) |
| `DOOM2.BIN` | ready to load (4 MHz build) |
| `test_play.py`, `test_look.py`, `test_scene.py` | the emulator tests and screenshots |
