# BYTE BREAKER for the 6502 SBC

A brick breaking game. Bounce the ball off your paddle and knock out every brick. Outlined bricks take two hits, and checked (steel) bricks never break. Some bricks drop a capsule when they break: catch it with the paddle for its power. There are 10 levels; after the last they start again, a little faster. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. The game needs the terminal firmware with the **sprite layer** (control code 1C, VGA output), in control code mode (setup item **J**). On a terminal without it, the game says so and goes back to the boot menu.
2. Copy `BREAKER.BIN` to the USB drive, then in the monitor:

```
L BREAKER 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or Left / Right | d-pad left / right | move the paddle |
| Space | A or B | launch the ball; with the laser, fire |
| P | Start | pause |
| M | | sound on / off |
| Q | | back to the title |

On the title screen, **G** switches between the keyboard and the gamepad (the gamepad is the default). Holding a key moves the paddle smoothly; key repeat is slower than the frames, so each press keeps it going for a few frames.

## Playing

- **The ball** starts on the paddle; launch it, or it goes by itself after about 3 seconds. Where it hits the paddle sets its angle: near the middle it goes up steeply, near the ends it goes out flat, to that side.
- **Speed:** the ball gets faster every 12 bricks hit, up to 8 steps.
- **Points:** 10 to 70 a brick (the higher the row, the more), 50 for cracking a two-hit brick, 100 for a capsule. Every 10,000 points gives an extra ball.
- **Capsules** (about one broken brick in six drops one; two can fall at once):

| Sign | Power |
|---|---|
| a bar between two posts | **wide** paddle |
| three dots | **three balls** |
| a line | **slower** ball (back to the first speed) |
| two beams | **laser**: fire shoots two beams from the paddle's ends |
| a cup | **catch**: the ball sticks to the paddle; launch it again |
| a plus | an **extra ball** |

  Wide, laser and catch replace each other, and go when a ball is lost.

## Sound

BYTE BREAKER plays sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **The ball:** a tick off the walls and a blip off the paddle. Bricks ring at a pitch that is higher the higher the brick is, and outlined and checked bricks clank.
- **Capsules and lasers:** catching a capsule plays a rising run (a different one for an extra ball), and the laser zaps.
- **Jingles:** sounds for a lost ball, the start of a level, a cleared level and GAME OVER.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `breaker_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py breaker` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py breaker OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.

## How it works

- **The screen:** the status line on row 0; walls round text rows 1–23 (block graphics, drawn once); the bricks in rows 4–13: 19 across and up to 10 rows, each 4 block graphics characters (8 × 4 pixels, the bottom row and the last column a gap). A brick is drawn only when it changes.
- **The terminal's sprites:** the paddle (slot 15, on top), the balls (12–14), the capsules (10–11) and the laser shots (6–9) are sprites. At start the game asks the terminal (IDENTIFY) and sends it the 11 pictures (56 bytes of its pool). Each frame only what changed goes (MOVE, PICTURE, PLACE, HIDE), between HOLD and SHOW. The sprites are clipped to rows 1–23, so they never cover the status line.
- **Pacing:** after each frame the game sends IDENTIFY, and the next frame waits for the answer (any of S, P, 1; up to 60 ms). The terminal never falls behind and its buffer never fills. The answer's characters are not taken as keys.
- **Frames:** 30 ms (header byte $0503). A typical frame sends about 16 bytes: a ball and the paddle moving, plus 8–10 bytes for each brick that changes.
- **The ball:** positions and speeds are 8.8 fixed point pixels (the sprite layer's 160 × 96). Its speed comes from a table of 8 speeds × 4 angles (30, 45, 60 and 72 degrees, `gen.py`), with a direction on each axis. Each frame it moves in 4 quarter steps, x then y; after each, a brick or wall at its leading edge turns it back on that axis. So it never passes through a brick, and hitting a corner turns it on both axes.
- **Memory:** no zero page is used. The program occupies $0500–$27C9.
- **ROM entry points:** the game uses `sbc_api.inc` (one folder up): `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE`, `SBC_MENU` and `CLOCK_MHZ`.

## Files

| File | What it is |
|---|---|
| `breaker.s`, `breaker.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` |
| `gen.py` → `breaker_data.inc` | the pictures, the ball's speeds, the brick characters and the 10 levels (`python gen.py > breaker_data.inc` after changing it) |
| `BREAKER.BIN` | ready to load (built for 2 MHz) |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`play.py`:** a bot keeps the paddle under the ball and fires now and then, with the gamepad or the keyboard (`KEYS=1`). `START=n` plays level n's bricks first, and `MISS=1` lets the balls fall, to test losing balls and game over. Every frame it checks:
  - the terminal shows exactly the walls and the bricks in the game's brick map;
  - the terminal's sprites are exactly the paddle, balls, capsules and shots in the game's tables;
  - no ball is inside a brick or outside the walls.
- **`frames.py`:** frame times and bytes a frame.
- **`sim.py`:** the emulator, with a model of the terminal (control codes, tiles, the sprite layer).
