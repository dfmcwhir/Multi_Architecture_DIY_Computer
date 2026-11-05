# GOLD GRABBER for the 6502 SBC

A treasure grabbing game. Your miner stands on a platform at the top of the screen, over a pit full of things. Below him a grabber on a rope swings to and fro. Fire it and it shoots out at the angle it's at, until it grabs something, which it reels in, or reaches the edge of the screen, in which case it comes back empty. Heavy things come up slowly. Each level has a money goal: meet it before the time runs out and you go on to the shop and the next level. Miss it and the game is over. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**: it uses the repeat count in the attribute byte (18 n, bits 3-6).
2. Copy `GRABBER.BIN` to the USB drive, then in the monitor:

```
L GRABBER 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| Space (or S / Down) | A (or d-pad down) | fire the grabber |
| B (or W / Up) | B (or d-pad up) | use a bomb on what the grabber holds |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title (Q on the title goes back to the boot menu) |
| G (title screen) | | switch keyboard / gamepad |

- **Controls at start:** the game starts in gamepad mode; press G on the title screen for the keyboard. The byte at $0504 sets this: 0 keyboard, 1 gamepad (default).
- **In the shop:** up/down (pad, W/S or the arrow keys) chooses, A / Space buys or goes on. On the keyboard, 1-4 buy directly and N goes on to the next level.

## Playing

| Thing | Worth | Weight |
|---|---|---|
| Gem (small, diamond shaped) | $250 | light: comes up fast |
| Small chest | $100 - $350 | middling |
| Big chest | $300 - $800 | heavy |
| Small rock | $11 - $15 | heavy for its size |
| Big rock | $20 - $29 | very heavy: a slow trip |
| Gopher | $7 | light |
| Gopher with a gem in its mouth | $257 | light |
| TNT | nothing | grabbing it sets it off |

- **The grabber** swings like a pendulum, slowest at the ends, to and fro in about 2.9 seconds. The claw turns with the rope (straight down, 45° or sideways), so it points the way it will go out. It stays at its angle while it's out.
- **Gophers** run to and fro along their own stretch of the pit. About a third of them carry a gem.
- **TNT** blows up when the grabber touches it. Everything within about 22 pixels is destroyed, and other TNT in range goes off a moment later, so you can get a chain. The grabber comes back empty.
- **Time:** 60 seconds a level. The level also ends early if nothing worth grabbing is left (only TNT).
- **Money and goals:** money adds up from level to level, and so does the goal. Each level's goal goes up by 50-70% (picked at random) of the total worth of what's in that level's pit. At the end of a level you need at least as much money as the goal.
- **Levels:** the number and placement of each kind of thing change every level. Gophers and TNT turn up from level 2. There are more big rocks, gems and gophers further on (the numbers stop growing at level 10).
- **The shop** opens between levels. Each time, each of these is for sale or not, at random (at least one always is), with a price that's partly random and rises a little with the level:

| For sale | Price | Lasts |
|---|---|---|
| Strength: things come up half as fast again | $50-150, + $10 a level | the next level |
| Gems worth double (loose gems and gophers' gems) | $100-250, + $15 a level | the next level |
| A bomb | $30-100, + $5 a level | until used (you can carry 9) |
| Laser pointer (offered only 1 time in 4) | $250-450, + $25 a level | the first 30 seconds of the next level |

  Buying spends money that counts towards the next goal, so a purchase has to earn its keep.
- **The laser pointer** shows a dotted line from the claw the way it would go out, to the edge of the pit or to whatever it would grab, which it marks with a little ring. It follows the grabber's own path step by step, so the ring is exactly where it will hit (a gopher may have moved by then).
- **Bombs:** while the grabber is reeling something in, press B to blow it up (you get nothing for it). The empty grabber comes back fast, which saves time on a big rock you didn't mean to catch.
- **The status line** shows your money, the goal, the level, the seconds left, your bombs, STR, GEMX2 and LASER while they last, and "+$..." for a moment after each catch.
- **Best:** the title screen shows the most money you've had, and the level it was at.

## Sound

GOLD GRABBER plays sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **The grabber:** a whirr when you fire it, a winch clicking while it reels in, a thump when it grabs (a sparkle for a gem), and a cha-ching when the money comes in.
- **Bangs:** TNT and bombs explode with a bang.
- **The clock:** it ticks through the last ten seconds.
- **The shop:** a buy plays a ding and a refusal a buzz. There are also tunes for meeting the goal and for GAME OVER.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `grabber_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py grabber` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py grabber OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.
  (The test files in `test/` match this version of the game again: a later copy expected sprite-layer code the game doesn't have.)

## How it works

- **The field:** text rows 1-23, 160 × 92 pixels as block graphics characters (2 × 4 pixels each). Row 0 is the status line.
- **Three buffers:** `bg` holds what stands still (the platform, the miner, specks of dirt and the things lying in the pit); `fb` is the picture as it should be; `sb` is what the terminal shows. Each frame the blocks of 8 columns that had moving things on them last frame are copied back from `bg`, then the moving things (the rope, the grabber and what it holds, the winch, the gophers, explosions) are drawn into `fb`. Only blocks drawn on this frame or last are compared with `sb`, and only the characters that differ are sent; runs of the same character use the repeat count. When something leaves the pit it is rubbed out of `bg` and its blocks are compared too.
- **The rope** is a straight line from under the platform to the grabber. Its end is worked out each frame from the rope's length and a table of 65 directions (−75° to +75°).
- **The swing:** the angle's speed changes by (32 − angle) × 25 / 2048 each frame. This works like a pendulum, with a swing of about 2.9 s.
- **The claw** has 5 pictures (pointing down, 45° and sideways each way), each with where the rope joins it. What it grabs with is its tip, 3 pixels along the rope from the rope's end; what it holds hangs with its middle 3 + half its height along the rope.
- **The laser pointer** walks the grabber's path: the rope's end is at length × direction / 128, and adding 3 × direction / 128 (in 8.8) each step lands on exactly the same pixels as the grabber going out 3 pixels a frame. Each step checks the claw's tip against the things in the pit, as the grabber does.
- **Pictures** are drawn a row at a time, straight into the text row's characters (`gen.py` turns the text drawings into bits).
- **Speed:** the header byte at $0503 is the frame time in ms (default 50, 20 frames a second). After each frame the game works out roughly how long it took and waits out the rest:
  - **serial:** the bytes sent;
  - **6502 work:** pixels drawn and rows compared, from a model measured in the emulator (`test/fit.py`), divided by `CLOCK_MHZ`.

  Measured frame times: 52 ms median at 2 MHz (57 ms at the slowest; 61 ms with the laser pointer on); 52 ms median at 1 MHz (81 ms when a big rock comes up on a long rope).
- **Memory:** no zero page is used. The program occupies $0500–$3242 and its three buffers $3300–$4AFF.
- **ROM entry points:** the game uses `sbc_api.inc` (one folder up): `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE`, `SBC_MENU` and `CLOCK_MHZ`.

## Files

| File | What it is |
|---|---|
| `grabber.s`, `grabber.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` |
| `gen.py` → `grabber_data.inc` | the pictures, the rope's directions and a table of squares (`python gen.py > grabber_data.inc` after changing it) |
| `GRABBER.BIN` | ready to load (built for 2 MHz) |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`play.py`:** a bot plays several levels (gamepad, or keyboard with `PAD=0`; `LEVELS=n`, `GARBAGE=n` for random RAM). It fires when the grabber points at the best thing it can reach, bombs big rocks, and shops. Every frame it checks that `fb` holds exactly `bg` with the moving things drawn over it, as drawn again in Python from the game's state. Every few frames, and whenever the pit changes, it also checks that `bg` holds exactly the platform, miner, dirt and the things in the pit, and that the terminal shows exactly `fb`. It also checks the money: each catch pays its value, each goal goes up by 50-70% of what's in its pit, and the shop takes its prices.
- **`features.py`:** set pieces with the pit laid out by hand: catching and its pay, a gopher with a gem, double gems, TNT and its chain, a bomb on a rock, strength, the edge, time running out (game over), the shop (prices, too poor, 9 bombs at most, what's bought shows on the next level), and the laser pointer (it marks what the grabber would grab, and goes off half way through the level).
- **`menus.py`:** the title, the controls, pause, quit and the clock.
- **`frames.py`, `fit.py`, `look.py`:** frame times, the timing model, screenshots.
