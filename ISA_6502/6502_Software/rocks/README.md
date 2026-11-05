# SPACE ROCKS for the 6502 SBC

A rock shooter in the style of the arcade classic. Steer a small ship through a field of drifting rocks and shoot them. Big rocks break into two medium ones, medium into two small, and small ones turn to dust. Clear the field and a new, faster wave comes in. Now and then a flying saucer crosses the field and shoots at you. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**: it uses the repeat count in the attribute byte (18 n, bits 3-6). With the newer firmware that has the **sprite layer** (control code 1C, VGA), it uses the terminal's sprites and moves smoother; it finds out by itself at start (see below).
2. Copy `ROCKS.BIN` to the USB drive, then in the monitor:

```
L ROCKS 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or Left / Right | d-pad left / right | turn |
| W or Up | d-pad up | thrust |
| Space | A | fire |
| S or Down | B (or d-pad down) | hyperspace: jump to a random place |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title (Q on the title goes back to the boot menu) |
| G (title screen) | | switch keyboard / gamepad |

- **Gamepad mode:** pressing A or Start on the pad at the title screen starts in gamepad mode. The byte at $0504 sets the controls at startup: 0 keyboard (default), 1 gamepad.
- **Holding keys:** a keyboard's key repeat is slower than the frames, so a turn or thrust key keeps working for a couple of frames after each repeat. Holding it down turns or thrusts smoothly.

## Playing

- **The ship:** it drifts with what speed it has and slows down a little by itself. The edges of the field wrap round, for the ship, rocks and bullets alike.
- **Bullets:** up to 4 in flight. Each flies about 70 pixels, a little under half the width of the field.
- **Points:** big rocks 20, medium 50, small 100; big saucer 200, small saucer 1,000. An extra ship every 10,000 points (up to 9).
- **Saucers:**
  - **When:** every 15–30 seconds or so while your ship is out, a saucer crosses the field from one side to the other, drifting up and down.
  - **Big saucer:** shoots in random directions.
  - **Small saucer:** turns up from wave 3, or once you have 10,000 points. It aims at your ship, a little off before wave 6 and dead on after.
  - **Collisions:** a saucer that flies into a rock destroys both, and you get no points for that. Flying into a saucer costs you a ship but scores it.
- **Ships:** you start with 3. After a crash the ship comes back in the middle once that area is clear of rocks, and blinks for a moment while it can't be hit.
- **Waves:** 4 big rocks in the first wave and one more each wave, up to 8. Every wave the rocks are a little faster.

## Sound

SPACE ROCKS plays sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **Heartbeat:** two low alternating notes play while there are rocks on the field. They start slow at each wave and get faster.
- **Your ship:** the engine rumbles while you thrust, shots zap, and hyperspace has a sweep. Losing the ship is a big explosion.
- **Rocks and saucers:** rocks explode with a bang that is shorter for smaller rocks. A saucer hums while it is on the field, low for a big one and high for a small one.
- **Jingles:** an extra ship and GAME OVER each have a short tune.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `rocks_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py rocks` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py rocks OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.

## How it works

- **The terminal's sprites (newer firmware):** at start the game sends IDENTIFY (1C 0C). If the terminal answers, it sends it 44 pictures (391 bytes of its pool): the ship at its 32 headings, the 9 rock outlines, the 2 saucers and a bullet. Then each frame:
  - the ship (slot 15, on top), the saucer (14) and up to 14 rocks and bullets (slots 0-13, the big rocks first) are sprites; a rock going over an edge takes two slots, one on each side, so it wraps round as before. Debris, the flame, and anything that doesn't get a slot (or is over a corner) are drawn in the field as before;
  - only the sprites' changes go (MOVE, PICTURE, PLACE, HIDE), between HOLD and SHOW;
  - **half way through the frame time** the sprites move on by half their speed, so the ship, saucer, rocks and bullets move twice a frame (about 36 times a second) while the game itself still runs at 18 frames a second, at the same speed;
  - after each update IDENTIFY goes out, and the next update waits until every IDENTIFY has been answered (up to 150 ms), so the terminal never falls behind. Each answer is counted once, even if the 6502 misses some of its three characters, and a capital S, P or 1 from the terminal is never taken as a key (a late answer used to be read as P, pause, or S, hyperspace). If the terminal is still busy with the frame at the half-way point, that half-way update is skipped;
  - every 64 frames (about 3.5 seconds) all the sprites are sent again in full (CLIP, HIDE ALL, a PLACE for each), so if the terminal ever loses them they come back within a few seconds.

  A busy frame went from about 190 bytes to about 75, and the 6502's work from about 35 ms to about 17 ms at 2 MHz. An older terminal doesn't answer, and the game draws everything itself as before.

- **The field:** text rows 1–23, 160 × 92 pixels. Each frame it is drawn in RAM as block graphics characters (2 × 4 pixels each) and compared with a copy of what the terminal shows. Only the characters that changed are sent, and runs of the same character use the terminal's repeat count.
- **Tracking changes:** each row is split into ten blocks of 8 columns. Only blocks that had something drawn in them this frame or the last are compared or cleared, so empty space costs nothing.
- **Rocks:** each rock outline is stored pre-drawn as block characters, for each of the 8 ways it can sit inside a character cell (`gen.py`). Drawing a big rock is about 30 character ORs instead of about 40 separate pixels. The field is exactly 80 × 23 characters, so wrapping round the edges works in whole characters.
- **The ship:** 32 headings, drawn pixel by pixel from outlines made by `gen.py`. The flame flickers when thrusting.
- **Aiming:** the small saucer tries all 32 headings and picks the one that points most nearly at the ship (the biggest dx·cos + dy·sin), allowing for the wrap.
- **Moving things:** every object is in one table: ship, bullets, rocks, debris, the saucer and its 2 bullets, 48 in all. Positions and speeds are 8.8 fixed point pixels. Hits are a box test round each rock, measured round the wrap.
- **Speed:** the header byte at $0503 is the frame time in ms (default 55). After each frame the game works out roughly how long it took and waits the rest:
  - **serial:** the bytes sent at 115200 baud;
  - **6502 work:** from how much was drawn and compared, using a model measured in the emulator (`test/fit.py`) and divided by `CLOCK_MHZ`.

  At 2 MHz frames stay at about 55 ms (18 a second) however busy the screen is. At 1 MHz a busy screen takes longer than that, so the game slows down by up to about a quarter (not with the terminal's sprites: then 1 MHz keeps up too). With the sprites the model is a different one (fewer things drawn, but the slots to work out), and the half-way update comes about half a frame after the frame's SHOW.
- **Memory:** no zero page is used. The program occupies $0500–$417F and the two screen buffers $4200–$51FF.
- **ROM entry points:** the game uses `sbc_api.inc` (one folder up): `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE`, `SBC_MENU` and `CLOCK_MHZ`.

## Files

| File | What it is |
|---|---|
| `rocks.s`, `rocks.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` |
| `gen.py` → `rocks_data.inc` | the sine table, the ship's 32 headings, the rock and saucer outlines, the pre-drawn rocks and the sprite pictures (`python gen.py > rocks_data.inc` after changing it) |
| `ROCKS.BIN` | ready to load (built for 2 MHz) |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`play.py`:** a bot turns to the nearest rock, shoots, and jumps out of trouble, with the keyboard or the gamepad (`PAD=1`), from random RAM (`GARBAGE=n`). `IDLE=1` sits still, to test crashing, coming back and game over. Every frame it checks two things:
  - the terminal shows exactly what is in the game's screen buffer;
  - the buffer holds exactly the ship, rocks, bullets and debris, drawn again in Python from the game's object table (less the ones that are sprites);
  - the terminal's sprites are exactly the ones the game's slot tables say, half a frame on, each sprite thing has all the slots it needs, and the whole screen (field and sprites together) looks as it should.

  The harness models the terminal's sprite layer; `NOSPRITES=1` makes it an older terminal (the game then draws everything).
- **`saucer.py`:** sits still and calls saucers in: checks they fire, measures how well the small one aims, and that its bullets can destroy the ship.
- **`slowterm.py SPR_MS FRAMES`:** plays against a terminal that takes time, as the real one does: SHOW waits for the vertical blank and then costs SPR_MS a sprite change, bytes wait in a 6144-byte receive buffer and are dropped when it's full. `LOSS=0.1` loses that share of the answer's characters, `SLOW_EVERY=25 SLOW_MS=80` makes every 25th update 80 ms slower. It reports the bytes dropped, how far behind the terminal fell, and whether its sprites match the game's at the end.
- **`menus.py`:** tests the title, pause and quit keys.
- **`frames.py`, `fit.py`, `prof.py`:** frame times, the timing model, and where the time goes.
