# CRITTERS for the 6502 SBC

A Lemmings-style puzzle game. Critters drop out of a hatch and walk blindly forward. Give some of them jobs so that enough of the rest reach the exit. It runs from the monitor at $0500 on the PIC32 terminal at 115200 baud.

## Running

1. Turn on terminal setup item **J** (control code mode). It doesn't need the v1.4 repeat count or tiles; it works with the earlier control code firmware too.
2. Copy `CRITTERS.BIN` to the USB drive, then in the monitor:

```
L CRITTERS 0500
R
```

On the title screen, press Space to start, or 1–6 to jump to a level. With the gamepad, Up/Down choose the starting level and A or Start plays.

## Keys

| Key | Action |
|---|---|
| `,` `.` or ← → | select the critter to the left / right (a dot appears over it) |
| 1 | **climber**: climbs walls it walks into (kept for good) |
| 2 | **floater**: opens an umbrella when falling, so any drop is safe (kept for good) |
| 3 | **blocker**: stands still and turns others around |
| 4 | **builder**: lays a 12-brick staircase up and forward |
| 5 | **basher**: tunnels sideways through anything within 6 pixels ahead |
| 6 | **digger**: digs straight down until it breaks through |
| + / - | release rate (it can't go below the level's starting rate) |
| P | pause |
| M | sound on / off |
| K | nuke: everyone on the field goes splat and the level ends |
| R | restart the level |
| Q | back to the title |
| G (title screen) | switch keyboard / gamepad |

**Gamepad:**

| Button | Action |
|---|---|
| Left / Right | select the critter to the left / right (hold to step repeatedly) |
| Up / Down | choose a skill; a `>` marks it on the status line |
| A | give the chosen skill to the selected critter |
| B + Up / Down | release rate |
| Start | pause |
| Select + A | nuke |

R, Q and K stay on the keyboard.

The bottom lines show how many of each skill are left, plus:

- **OUT**: critters on the field.
- **IN**: critters saved.
- **NEED**: how many must be saved.
- **RATE**: the release rate.
- **TIME**: counts down 1 every 10 game ticks.
- **SEL**: what the selected critter is doing, with C/F if it is a climber/floater.

A fall of more than 32 pixels is fatal without an umbrella. The level ends when everyone is saved or lost (blockers left standing don't count), or when the time runs out.

## The levels

| # | Name | Skills |
|---|---|---|
| 1 | Just dig | 3 diggers |
| 2 | Hold the line | 2 blockers |
| 3 | Bash it | 2 bashers |
| 4 | Mind the gap | 4 builders |
| 5 | Up and over | 10 climbers, 10 floaters |
| 6 | The works | 3 builders, 2 bashers, 2 diggers |

**Adding levels:** levels are short byte lists at the end of `critters.s`, and the format is documented there. A level is a header followed by terrain commands: filled rectangles and left or right ramps on the 160 × 88 playfield. To add one, write its list, add it to `lv_tab_lo`/`lv_tab_hi`, and raise `NLEVELS`.

## Keyboard or gamepad

The title screen shows the current controls. Press **G** to switch between keyboard and gamepad, or just press **A** or **Start** on the pad, which starts the game in gamepad mode. The byte at $0504 sets the controls at startup: 0 for keyboard (the default) or 1 for gamepad.

In gamepad mode the game reads the buttons directly with `SBC_PADSTATE` ($FE12). It ignores the W, A, S, D and space characters that the pad driver also types, so a press doesn't act twice. The other keyboard keys (P, Q and so on) still work.

## ROM entry points

The game includes `sbc_api.inc` and calls the ROM through the fixed table at $FE00: `SBC_CHRIN`, `SBC_CHROUT` and `SBC_PADSTATE`. Q exits with `JMP SBC_MENU`. A firmware rebuild no longer breaks it, as long as that table stays put. `make` needs `sbc_api.inc` next to the source.

## Sound

CRITTERS plays music and sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **Music:** a gentle tune, written for this game, plays during each level.
- **The critters:** each one drops out of the hatch with a whistle and reaches the exit with a cheer. A long fall ends in a splat.
- **Skills and work:** giving a skill clicks, bricks tick as builders lay them, and bashing and digging crunch.
- **Levels:** a short tune when a level starts, the nuke has its own sound, and the end of a level has a fanfare if enough critters were saved or a falling phrase if not.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `critters_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py critters` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py critters OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them. The test takes the level first: `PLAYARGS=1` for level 1.

## How it works

- **Terrain:** the terrain is a 160 × 88 bitmap in RAM (1,760 bytes at $3200). It's drawn once per level as block graphics characters, skipping empty cells. Digging and building change single pixels, and the bitmap is updated to match.
- **Critters:** each critter is 1 × 2 pixels. Every tick, all critters are erased and then all are redrawn, so overlapping critters stay correct. Erasing puts back whatever terrain is under each pixel, and redraws the hatch or door if a critter passed over them.
- **Sending pixels:** the game keeps a copy of the screen in RAM as block graphics characters: what it should show, and what the terminal shows (2 × 1,920 bytes at $2200–$31FF). Setting or clearing a pixel only changes the copy and notes the character. Once per tick the characters that really changed are sent, one byte each plus short cursor moves. A critter that steps sideways usually changes one character, so a tick costs about a third less than sending each pixel as 3 bytes.
- **Header:** $0503 is the delay per tick (default 30 ms), and $0504 sets the controls at startup (0 keyboard, 1 gamepad). Each tick also takes roughly 25–50 ms of CPU and serial time at 1 MHz, depending on how many critters are out. Raise the delay to slow the game down (for example, `503: 50` before `R`).
- **Memory:** no zero page is used. The program occupies $0500–$26F6 and the terrain bitmap $2700–$3DFF.

## Files

- `critters.s`, `critters.cfg`, `make.bat` (Windows) and `Makefile`: source and build (ca65/ld65). `CRITTERS.BIN` is built for the clock set in `../sbc_api.inc`; see the README one folder up.
- `CRITTERS.BIN`: ready to load.
- `test/`: the emulator harness.
  - It solves each level with a scripted player that uses the real keys.
  - Every few ticks it checks every playfield pixel against the terrain bitmap plus the critters.
- `screenshots/`: images from that harness.
