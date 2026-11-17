# INVADERS for the 6502 SBC (CPU Rev2, PICO9918)

The Space Invaders style game, remade for the **PICO9918** card. It uses TMS9918A Graphics I mode: the invaders, shields and text are patterns on the name table, and the cannon, shots, bombs, saucer and explosions are hardware sprites. It runs at 60 frames a second, timed by the VDP's frame flag.

## Running

Copy `INVADERS.BIN` to the USB drive, then in the monitor:

```
L INVADERS 0800
R
```

- **Load address:** programs now load at **$0800**. On the CPU Rev2 ROM, $0500–$07FF holds the drivers' variables, so the old $0500 address would overwrite them.
- **Display check:** the game checks for a CPU Rev2 ROM with the PICO9918 as its display (`SBC_SYSINFO`). With anything else, it prints a message and goes back to the boot menu.
- **Quit:** Q puts the console's text screen back (`SBC_CONRESET`) and goes to the boot menu.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 1 | frames per game tick: 1 = full speed, 2 = half speed |
| $0804 | 0 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D, `,` / `.`, ← / → | left / right | move |
| S or ↓ | (let go) | stop |
| SPACE or W | A or B (hold to keep firing) | fire |
| P | Start | pause |
| M | | sound on / off |
| G (title screen) | | switch keyboard / gamepad |
| Q | | quit (from GAME OVER: back to the title) |

- **Arrow keys:** the AVR keyboard sends ^P / ^D for left and right. ESC [ D / ESC [ C sequences from a serial terminal work too.
- **Keyboard movement:** a keyboard can't report how long a key is held. So a tap moves the cannon about 11 pixels, and a held key's auto-repeat keeps it moving; after you let go it runs on a few pixels at most. S or ↓ stops it at once. There is a short hitch before the auto-repeat starts.
- **Gamepad:** it works in either mode. The cannon moves while the d-pad is held and stops the moment you let go. The W A S D and space characters that the pad driver types are ignored while a pad button is held, and always in gamepad mode.

## The game

- **Formation:** 5 rows of 8: squids (30 points), crabs (20) and octopuses (10).
  - The rows step 2 pixels at a time, in turn from the bottom up, as in the arcade game. They speed up as you shoot them, and the march sound plays a note with each step.
  - Each wave starts a row lower, up to 4 rows.
- **Bombs:** up to 3 at once, more often each wave. They fall a pixel a frame, or 2 a frame from wave 4.
- **Shields:** 4 of them, worn away pixel by pixel by shots and bombs. They disappear when the invaders come down to touch them.
- **The saucer:** crosses every 10–18 seconds while 8 or more invaders are left, and is worth 50, 100, 150 or 300 points.
- **Lives and game over:** you have 3 lives. The game ends when they run out, or when the invaders land.

## Sound

The sound plays on the AY-3-8910 card through `../ay/sfx.s`, timed by the VIA's timer 2, as before. The sounds are the same scripts as the PIC32 version.

## How it works

- **VRAM:**

  | Address | Contents |
  |---|---|
  | $0000 | patterns |
  | $1800 | names |
  | $1B00 | sprite attributes |
  | $2000 | colours |
  | $3800 | sprite patterns |

  Sprites are 16 × 16.
- **Startup:** `lib/vdp.s` (`vdp_setup`) puts a PICO9918 back to plain TMS9918A behaviour:
  - It unlocks the F18A registers and sets VR49 = 0 and VR51 = 32.
  - It then clears VRAM and loads R0–R7.

  So the same code also suits a real TMS9918A.
- **Invaders:** each one has a 24-pixel cell (3 patterns). Every kind and animation frame is stored in 4 positions (0, 2, 4, 6 pixels to the right): 72 patterns in all. A row is redrawn as one line of 26 names, clipped at the screen edges. Its position is a cell column (`rowc`, signed) plus a 2-pixel step (`rowph`).
- **Shields:** each shield has 6 patterns of its own, with a copy in RAM. A hit clears the shield's pixels in a 3 × 3 square plus a few at random. Only the changed bytes are written to VRAM.
- **Sprites:** 7 of them (cannon, shot, 3 bombs, saucer, explosion). They're kept in a RAM table and written to VRAM once a frame.
- **Zero page:** none is used.
- **The pictures:** these are in `gen.py`. Run `python gen.py` after changing one; it writes `invaders_gfx.inc`. The font is the console's 5 × 8 font (`../lib/font5x8.inc`), made bold.

## Files

| File | What it is |
|---|---|
| `invaders.s`, `invaders.cfg`, `make.bat` | source and build (ca65/ld65; `-I ..` finds `sbc_api.inc`, `ay/sfx.s` and `lib/vdp.s`) |
| `gen.py` → `invaders_gfx.inc` | patterns, colours, sprites |
| `INVADERS.BIN` | ready to load (2 MHz build) |
