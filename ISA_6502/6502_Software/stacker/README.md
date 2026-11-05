# STACKER for the 6502 SBC

A falling-blocks game in the style of Tetris. Seven kinds of pieces fall into a well 10 squares wide and 20 deep. Turn and slide them so they fill whole rows; a full row disappears. The game ends when the stack reaches the top. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 or later**: it uses the repeat count in the attribute byte (18 n, bits 3-6) and tiles (19 SET TILE, 0B SEND TILE).
2. Copy `STACKER.BIN` to the USB drive, then in the monitor:

```
L STACKER 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or Left / Right | d-pad left / right (held: repeats) | move |
| W, X or Up | A | rotate clockwise |
| Z | B | rotate back |
| S or Down | d-pad down (held) | down one row (1 point a row) |
| Space | d-pad up | drop (2 points a row) |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title (Q on the title goes back to the boot menu) |
| 0–9 (title screen) | | starting level |
| G (title screen) | | switch keyboard / gamepad |

- **Gamepad mode:** pressing A or Start on the pad at the title screen starts in gamepad mode. The byte at $0504 sets the controls at startup: 0 keyboard (default), 1 gamepad. In gamepad mode the characters the pad driver types are ignored.
- **Turning:** if a piece can't turn where it is, the game tries it one square to each side, and two for the long piece.
- **Landing:** a piece that lands can still slide or turn for about half a second before it locks.

## Scoring

- **Lines:** clearing 1, 2, 3 or 4 rows at once scores 40, 100, 300 or 1200 points, times (level + 1).
- **Dropping:** S/down scores 1 point a row and Space/up scores 2 points a row.
- **Levels:** every 10 lines the level goes up and the pieces fall faster, from about 0.8 s a row at level 0 to a few hundredths of a second at level 19.
- **Next piece:** shown on the right.
- **Ghost:** four dots show where the falling piece will land.
- **Piece order:** pieces come in shuffled sets of seven, so each kind turns up once in every seven.
- **High score:** kept until the machine is reset.

## Sound

STACKER plays music and sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **Music:** "Korobeiniki", a Russian folk song from 1861 (public domain). The melody plays on channel A and the bass on B, looping while you play.
- **Effects:** these play on channel C, over the music: a tick for each move, a blip for each turn, a thump when a piece locks, a whoosh for a drop, a rising run for cleared lines (a longer one for four), and a fanfare for each new level.
- **GAME OVER:** the music stops and a falling phrase plays.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `stacker_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py stacker` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py stacker OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.
  The test script's line count now also allows for lines being cleared just as the run ends.

## How it works

- **Squares:** each square is 4 × 4 pixels, two block-graphics characters, so the well is 20 characters wide. Each kind of piece has its own texture, so they can be told apart on a one-colour screen. Empty squares are black.
- **Board:** kept in RAM, 10 × 22 bytes. The top two rows are hidden, where new pieces appear.
- **Drawing:** every game tick, the picture of the well is put together in RAM: the locked squares, then the ghost, then the falling piece. It is compared with what the terminal shows, and only the squares that changed are sent. Each kind of square is stored in the terminal as a 2 × 1 tile, so a square is 2 bytes (0B n), and a run of the same square in a row is one tile with the repeat count (a cleared line, the game over fill). The sides of the well are two 1 × 20 tiles. A piece costs about 280 bytes from appearing to locking (it was about 430).
- **Header:** $0503 is the length of a game tick in ms (default 15; real milliseconds at any clock, see `CLOCK_MHZ`). A bigger number makes everything slower.
- **Memory:** no zero page is used. The program occupies $0500–$1B01 and its variables $1B02–$1E2D.
- **ROM entry points:** the game uses `sbc_api.inc`: `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE` and `SBC_MENU`.

## Files

| File | What it is |
|---|---|
| `stacker.s`, `stacker.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` (see the README one folder up) |
| `gen.py` → `stacker_data.inc` | the pieces, square textures and title banner (`python gen.py > stacker_data.inc` after changing it) |
| `STACKER.BIN` | ready to load |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`play.py`:** a bot plays with the keyboard or the gamepad (`PAD=1`), with random RAM at start (`GARBAGE=n`), from any level (`LEVEL=n`), or badly on purpose to reach game over (`BAD=1`). For each piece it tries every turn and column and plays the best with real key presses. After every piece, the board, lines and level are checked against its own model, and every square on the terminal against what the game says it shows.
- **`menus.py`:** tests the title, pause and quit keys.
