# MINER MOS for the 6502 SBC

A single-screen platform game in the style of the 1983 classic. MOS the miner is deep inside the 6502, and his air is running out. In each room, take every key, then get to the portal before the air is gone. Keep clear of the guardians and the spikes, and don't fall too far. There are 8 rooms; after the last they start again. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. The game needs the terminal firmware with the **sprite layer** (control code 1C, VGA output), in control code mode (setup item **J**). On a terminal without it, the game says so and goes back to the boot menu.
2. Copy `MINER.BIN` to the USB drive, then in the monitor:

```
L MINER 0500
R
```

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or Left / Right | d-pad left / right | walk |
| Space, W or Up | A, B or d-pad up | jump |
| P | Start | pause |
| M | | sound on / off |
| Q | | back to the title |

On the title screen, **G** switches between the keyboard and the gamepad (the gamepad is the default). Key repeat is slower than the frames, so each key press keeps MOS walking for a few frames; holding the key walks smoothly.

## Playing

- **Jumping:** MOS jumps 3 tiles up and about 4 across, always the same arc. Once he is in the air you can't steer him. He can jump up through a floor from below, but walls stop him every way.
- **Falling:** walking off an edge drops him straight down. A fall of more than 6 tiles (from the top of a jump) kills him.
- **Floors:**

| Looks like | It is |
|---|---|
| a solid line with dots under it | a floor |
| bricks | a wall |
| a line with a zigzag under it | a conveyor: it carries MOS its way, and he can't walk against it |
| a broken line | a crumbling floor: it gives way under him a little at a time |
| a little plant | spikes: deadly |
| a small loop | a key |

- **Guardians** walk to and fro along a line, or bob up and down. Touching one costs a life.
- **Air:** the bar under the room's name. When it runs out, a life goes.
- **The portal** in each room is shut until every key is taken; then it flashes. Walk into it: the air left goes to the score, and the next room starts.
- **Points:** 100 a key, 10 for each unit of air left at the portal. Every 10,000 points gives an extra life. You start with 3.
- **Losing a life** starts the room again from the beginning (keys, air and crumbling floors too).

The rooms are THE BOOT SECTOR, STACK OVERFLOW, ZERO PAGE, THE INTERRUPT VECTOR, BUS CONTENTION, DECIMAL MODE, THE ILLEGAL OPCODES and THE RESET VECTOR.

## Sound

MINER MOS plays music and sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card it is simply silent.

- **Music:** "In the Hall of the Mountain King" (Grieg, 1875; public domain) plays in every room, melody on channel A and bass on B.
- **Effects:** jumping, landing, taking a key, dying (the music stops), a jingle at the portal and ticks as the air is counted into the score.
- **Jingles:** a fanfare after the last room, and a phrase at GAME OVER.
- **On / off:** **M** turns the sound on and off, on the title screen, in the game or at the end. The byte at $0505 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks in its loops and while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched.
- **The engine:** `../ay/sfx.s`, shared by all the games; see `../ay/README.md`.
- **The sounds:** these are in `miner_sound.inc`, made by `../ay/tools/game_sounds.py` (run `python game_sounds.py miner` there after changing them).
- **Test:** `PY65=path/to/py65 python3 ../ay/test/gamesound.py miner OUTDIR` runs this game's bot test with the card modelled. It checks the sound's timing, counts the sounds played and writes a .WAV of them.

## How it works

- **The screen:** the room on text rows 0–19: 40 × 20 tiles of 4 × 4 pixels, each 2 block graphics characters. Its name is on row 20, the air on row 21 and the score on row 23. A room is drawn once when it starts (runs of the same character go once, with the repeat count), and after that a tile is sent again only when it changes: a key taken, or a crumbling floor giving way.
- **The terminal's sprites:** MOS (slot 15, on top), up to 7 guardians (slots 8–14) and the portal (slot 0) are sprites, with masks so they are solid over the scenery. At start the game asks the terminal (IDENTIFY) and sends it the 19 pictures (304 bytes of its pool): MOS's 4 walking frames (the terminal mirrors them for walking left), 2 frames for each of the 6 kinds of guardian (robot, bird, blob, spinner, skull, jellyfish) and the portal shut and flashing. Each frame only what changed goes (MOVE, PICTURE, PLACE, HIDE), between HOLD and SHOW. The sprites are clipped to the room's rows.
- **Pacing:** after each frame the game sends IDENTIFY, and the next frame waits for the answer (any of S, P, 1; up to 60 ms), so the terminal never falls behind. The answer's characters are not taken as keys. Frames are 40 ms (header byte $0503) and usually send about 21 bytes.
- **Movement:** the rules (walking, conveyors, crumbling, the jump's arc, falling, landing, the guardians) are written twice, in `miner.s` and in `phys.py`. The Python copy is used to check the rooms and to test the game frame by frame.
- **The rooms** are in `rooms.py`, drawn as text (`gen.py` packs them two tiles to a byte, about 450 bytes a room, all in `MINER.BIN`). `check_rooms.py` checks that every key and the portal can be reached, and `check_rooms.traps(n)` finds places MOS can get to but can't get back from.
- **Memory:** no zero page is used. The program occupies $0500–$3184.
- **ROM entry points:** the game uses `sbc_api.inc` (one folder up): `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE`, `SBC_MENU` and `CLOCK_MHZ`.

## Making rooms

Edit `rooms.py`: each room is 19 lines of 38 characters (the rows inside the walls) and a list of guardians. The legend is at the top of the file. Then:

```
python3 check_rooms.py         every key and the portal can be reached, the start safe?
python3 gen.py > miner_data.inc
make.bat
python3 test/plan.py N         (optional) a way through room N, guardians and all
```

`plan.py` searches frame by frame with the exact rules, so it also finds rooms the guardians make impossible.

## Files

| File | What it is |
|---|---|
| `miner.s`, `miner.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` |
| `rooms.py`, `phys.py`, `gen.py` → `miner_data.inc` | the rooms, the rules of movement, and the generator for the pictures, tiles and packed rooms |
| `check_rooms.py` | checks the rooms can be done (keys and portal reachable, no traps, and MOS can stand still at the start for 10 seconds without a guardian reaching him) |
| `MINER.BIN` | ready to load (built for 2 MHz) |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`plan.py`:** finds a way through each room (a beam search over frames with the exact rules, guardians and all) and writes it to `plans/roomN.txt`.
- **`play.py`:** plays all 8 rooms in the emulator with those plans on the gamepad, and checks every frame that the game does exactly what `model.py` does: MOS's place and state, the guardians, the keys and the air. It also checks that the terminal's sprites are MOS, the guardians and the portal as they should be, and that the screen shows the room's tiles. Every room must be finished without losing a life.
- **`lose.py`:** no input: the lives go one by one, the room restarts each time, GAME OVER, then back to the title.
- **`keys.py`:** the keyboard, pause and quit.
- **`frames.py`:** frame times and bytes a frame.
- **`model.py`, `sim.py`:** the room model, and the emulator with a model of the terminal (control codes, the sprite layer).
