# INVADERS for the 6502 SBC

A Space Invaders style game that runs from the monitor at $0500 and draws on the PIC32 terminal.

## Before the first run

1. **Terminal:** turn on setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**. It uses codes 02, 05, 06, 0B, 0C, 0E, 0F, 18 (including the repeat count in bits 3-6), 19 and 1A.
2. Copy `INVADERS.BIN` to the USB drive.

## Running

```
L INVADERS 0500
R
```

**Speed:** the byte at $0503 is the delay per game tick in about 1 ms units (default 10). Lower is faster. For example, `503: 06` before `R`.

**Exit:** Q goes back to the boot menu.

## Sound

The game plays sound on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

| Sound | Channel |
|---|---|
| the march: four low notes, one each time the formation steps, so it speeds up as the invaders thin out | A |
| your shot; the saucer's warbling hum while it crosses | B |
| an invader hit (noise); the saucer hit (falling notes) | C |
| your cannon hit: an explosion and a falling tone | A and C |
| a short fanfare for a cleared wave, and a falling phrase at GAME OVER | A |

- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at GAME OVER. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2. The game checks the timer in its main loop and while it waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared with SUPER MOS BROS. See `../ay/README.md`. The sounds themselves are short scripts at the end of `invaders.s` (`s_march0` ... `s_over`).
- **Test:** `SOUND=1` makes the emulator in `test/` model the card and timer 2. `test/sound_check.py` plays a game with the bot and counts the sounds the game asked for.

## Keyboard or gamepad

The title screen shows the current controls. Press **G** to switch between keyboard and gamepad, or just press **A** or **Start** on the pad, which starts the game in gamepad mode. The byte at $0504 sets the controls at startup: 0 for keyboard (the default) or 1 for gamepad.

In gamepad mode the game reads the buttons directly with `SBC_PADSTATE` ($FE12). It ignores the W, A, S, D and space characters that the pad driver also types, so a press doesn't act twice. The other keyboard keys (P, Q and so on) still work.

## ROM entry points

The game includes `sbc_api.inc` and calls the ROM through the fixed table at $FE00: `SBC_CHRIN`, `SBC_CHROUT` and `SBC_PADSTATE`. Q exits with `JMP SBC_MENU`. A firmware rebuild no longer breaks it, as long as that table stays put. `make` needs `sbc_api.inc` next to the source.


## Keys

**Gamepad:** Left/Right move, A or B fires (hold to keep firing), Start pauses.


| Key | Action |
|---|---|
| A / D, `,` / `.`, ← / → | move |
| SPACE or W | fire |
| P | pause (any key resumes) |
| M | sound on / off |
| G (title screen) | switch keyboard / gamepad |
| Q | quit |

## About the load address and branches

Branch instructions (BEQ, BNE, …) are relative, so they work wherever the code is loaded. Only JMP, JSR and absolute data addresses are tied to an address. ld65 fixes those for $0500 using `invaders.cfg` (`start = $0500`). To load somewhere else, change that one number and re-link.

The variables live just after the program (up to $18FB) rather than in zero page, so EhBASIC's and the BIOS's zero page are left alone. Loading the game overwrites whatever is at $0500–$18FB, including a BASIC program if one is there.

## Graphics used

- **Block graphics** (attribute $80, 2×4 blocks per character cell): invaders (2 animation frames), cannon, saucer, explosions and shields. Each block is one graphics pixel, so these line up exactly with the pixel grid (160×96).
- **Set/reset pixel** (05/06): bullets, bombs, the ground line, the box on the title screen, and the damage shot into the shields.
- **Tiles and the repeat count:** each invader picture plus the gap after it is stored in the terminal as a 4 × 1 tile when the game starts. A row of the formation is then sent as runs, one tile with a repeat count for each run of live invaders or of gaps. A full row of 11 takes about 10 bytes instead of about 60. Rows that move down are blanked with repeated spaces.

## Files

- `invaders.s`, `invaders.cfg`, `make.bat` (Windows) and `Makefile`: source and build (ca65/ld65). The build includes `../ay/sfx.s`, the sound engine. `INVADERS.BIN` is built for the clock set in `../sbc_api.inc`; see the README one folder up.
- `INVADERS.BIN`: built with the addresses unset; patch or rebuild as above.
- `test/`: a Python emulator harness (needs py65 and Pillow). It models the terminal's control codes, plays the game with a bot, checks the screen against the game state and saves screenshots.
- `screenshots/`: images from that harness.
