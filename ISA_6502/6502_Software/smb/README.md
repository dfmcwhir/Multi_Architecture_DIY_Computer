# SUPER MOS BROS. for the 6502 SBC

A side-scrolling platform game in the style of the 1985 classic, set inside a computer. Nothing is taken from the original: the code, levels and pictures are all new. Run, jump and swim through 5 worlds of 4 levels (20 in all), stomp the AND and OR gates, collect bits (8 make a byte), bump ? blocks for bits, mushrooms, fire flowers and overclock devices, go down pipes into bonus rooms, find the hidden 1UP blocks, slide down the flagpole (its flag says 6502), get past KIL the dragon to press RESET at the end of each world, and at the very end meet Princess Graphics Card. It runs from the monitor at $0500 on the PIC32 terminal.

## Running

1. Turn on terminal setup item **J** (control code mode). The game needs terminal firmware **v1.4 with sideways scrolling in a scroll region**: it uses the repeat count in the attribute byte (18 n, bits 3-6), the scroll region (`ESC [ 3 ; 24 r`) and scroll left (16). On a terminal without that, set the byte at $0505 to 1 (`505: 01` in the monitor before `R`): the game then redraws the view instead of scrolling it, which is slower (see Speed).
2. Copy `SMB.BIN`, `SMBSPR.SMB` (the pictures for the terminal) and the 5 world files `WORLD1.SMB` ... `WORLD5.SMB` to the USB drive, then in the monitor:

```
L SMB 0500
R
```

- **Worlds are files:** each world (4 levels, about 2 KB) is a file, `WORLDn.SMB`. The game loads it with the ROM's **SBC_LOAD** entry point (see `../doom/SBC_LOAD.md`) each time one of its levels starts, while the "CELL 2-1" screen shows. (The status line calls a world-and-level a CELL.) No level is kept in the program, so they cost no RAM: the file goes into the view buffer, which is free until the level starts, and the level is unpacked from there into the map. (Smaller files, one per level, would save nothing more.)
- **Missing files:** if a world's file isn't on the drive the game says so and goes round again from world 1. Without SBC_LOAD in the ROM, or without `WORLD1.SMB`, it can't play: it says so and goes back to the title.
- **Two versions:**
  - **`SMB.BIN`** uses the terminal's **sprite layer** (control code 1C, the firmware with the "PIC32 Terminal Sprite Layer" spec, VGA output). At start it asks the terminal (IDENTIFY) and sends it the 41 pictures from `SMBSPR.SMB`; from then on the terminal draws MOS and everything that moves, and the game only tells it where (about 5 bytes per moving thing a frame). If the terminal doesn't answer, or `SMBSPR.SMB` can't be loaded, it says so and goes back to the boot menu.
  - **`SMBSW.BIN`** draws the sprites itself, as before, for a terminal without the sprite layer (or composite video). It doesn't need `SMBSPR.SMB`.
- **RAM:** both need RAM up to $7EFF (all of it, below the I/O page). `SMB.BIN` also keeps its sound variables at $0100-$017A, the bottom of the stack page (the stack itself never goes below about $01E0).

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| D or Right | d-pad right | walk right (press it again: run) |
| A or Left | d-pad left | walk left (press it again: run) |
| S or Down | let go | stop |
| S or Down | d-pad down | duck (the keyboard: for a moment, longer while the key repeats) |
| W, Space or Up | A | jump |
| | B (held) | run |
| F or E | B (press) | throw an electron (with the fire flower) |
| S or Down, on a pipe top | d-pad down, on a pipe top | go down the pipe (pipes with a bonus room) |
| W or Up, again and again | A, again and again | swim (in the liquid cooling levels) |
| P | Start | pause |
| Q | | quit to the title (Q on the title goes back to the boot menu) |
| G (title screen) | | switch keyboard / gamepad |
| M | | sound on / off (in the game, the title or GAME OVER) |

- **Gamepad:** this is the way to play. Hold the d-pad to walk, hold B to run, and hold A for a higher jump (let go early for a little hop). The game starts in gamepad mode; press G on the title screen for the keyboard. The byte at $0504 sets the controls at startup: 0 keyboard, 1 gamepad (default).
- **Keyboard:** a terminal can't tell the game how long a key is held, so the keys work as switches. A direction key sets MOS walking that way until you press S (or the other way); pressing the same direction again makes him run. A jump key always gives a full jump.
- **Typed characters:** in gamepad mode, the characters the pad driver types are ignored.

## Playing

- **Ducking:** MOS crouches (small: 5 pixels high, big: 8) and slides to a stop; he can't walk while ducking. Jump while ducking and he jumps ducked (on the keyboard, press jump straight after S). He stands up when you let go, if there is room above him.
- **MOS:** small, he dies when an enemy touches him. A mushroom makes him big: then a hit only makes him small again, and he blinks for a moment while nothing can hurt him.
- **? blocks:** jump into one from below. Most hold a bit (200 points); some hold a mushroom (1000 points when you catch it). If MOS is big already, that block gives a **fire flower** instead (1000 points). A used block stays solid.
- **Electrons:** with the flower MOS wears dark overalls, and B (or F on the keyboard) throws an electron. Up to 2 at a time; they bounce along the ground, burst on walls and knock out any enemy they hit (100 points), fans and fish included. A hit takes the flower away along with the size.
- **OC (overclock) device:** a few ? blocks hold one instead. It bounces away; catch it (1000 points) and MOS is overclocked for 10 seconds: he flashes (more slowly in the last 2 seconds, as a warning), always runs, nothing hurts him, and any enemy he touches is knocked out. Mushrooms are rarer than before.
- **Hidden blocks:** a few blocks can't be seen until MOS jumps into one from below. Out comes a 1UP: catch it for an extra life. There is one in 1-1, 1-2 and 1-4, and some in the later worlds.
- **Bricks:** big MOS breaks them with his head (50 points). Small MOS just bumps them.
- **AND gates** walk on their two input pins: jump on them (100 points). Bumping the block under an enemy also knocks it out.
- **OR gates:** jump on one and it pulls its pins in (100 points). Touch it then to kick it (400 points): it slides along knocking out every gate it meets, bounces off walls, goes over any edge, and can hit MOS on the way back. Jump on a moving one to stop it. A shell left standing comes back out after 8 seconds (its legs show for the last 2), walking at MOS.
- **Edges:** AND gates walk off ledges; OR gates turn back at the edge of a drop, so on the ledge levels they pace up and down their ledges. Where OR and AND gates come together, the OR gate is usually in front, so it can be stomped and kicked into the rest.
- **Bits:** the round things are bits (200 points each). 8 bits make a byte, and $0C bytes give an extra life.
- **The status line:** `DATA` is the score, in hex. `BYTES` is the bytes in hex, then the byte being filled, a 1 for each bit so far. `CELL` is the world and level, `CYCLES` the time left.
- **Pipes with a bonus room:** a pipe with a notch in its top goes somewhere. Stand on it and press down: MOS goes into a one-screen room full of bits. Its pipe on the right takes him back up, out of the top of another pipe further on. There is one in most outdoor levels.
- **Liquid cooling levels (2-3, 4-3):** MOS is under the coolant. Each press of A (or W) is a stroke up (MOS swims with his legs together and kicks once for each stroke); he sinks slowly and swims slower than he walks. Fins stand up from the floor and hang from the top. The gates swim on their sides at a pixel a frame, straight at him; most bob a little, and some swim in a wave, 12 pixels up and down; they can't be stomped, only avoided or hit with electrons. Swim to the flagpole at the end.
- **Fans** fly up and down: a few under the brick ceilings of the x-2 levels (32 pixels up and back), and in the gaps between the ledges in 1-3, 3-3 and 5-3, where they fly from the bottom right up to near the top, across MOS's way over the gap: stomp them or hit them with electrons.
- **The cloud** (4-1, 5-1) floats near the top of the view, keeps above MOS and throws AND gates down at him. Stomp it (it is high up) or use electrons.
- **Pits:** falling into one (or into the lava in a castle) costs a life.
- **The timer (CYCLES):** 300 at the start of each level, one count about every 0.45 s. At 0 MOS dies.
- **The flagpole:** the higher you grab it, the more points (100 at the bottom to 5000 at the top). MOS then walks into the 6502 and the time left is added at 50 points a count.
- **KIL the dragon** (named after the 6502 opcode that halts the CPU) waits on a bridge over lava at the end of each castle. It paces, jumps now and then, and breathes fire; touching it or its fire hurts, and it can't be stomped. Get past it (under it while it jumps, or over it) to the RESET button behind it: the bridge falls away and KIL with it. Or beat it with 5 electrons (5000 points). It gets livelier world by world: it paces faster, jumps more often and higher, and breathes fire sooner.
- **Princess Graphics Card** waits behind the RESET button in 5-4, the last castle. Press RESET, walk on to her, and she has a few words for MOS. Then the game is over (with the time bonus).
- **Lives:** 3 to start. A lost life starts the level again (small).
- **The worlds:** each has 4 levels: x-1 outside, x-2 under a brick ceiling with a few fans, x-3 high up on ledges with fans rising from the gaps (worlds 1, 3, 5) or under the coolant (worlds 2, 4), x-4 a castle with KIL. From world 3 on they are harder: wider pits, taller pipes, more OR gates.

## Speed

The header byte at $0503 is the frame time in ms (default 50: 20 frames a second). After each frame the game works out roughly how long it took and waits the rest:

- **serial:** the bytes sent at 115200 baud;
- **6502 work:** from how much was drawn and compared, using a model measured in the emulator (`test/fit.py`) and divided by `CLOCK_MHZ`.

Measured in the emulator with the bot playing (frame times; the target is 50 ms). `SMB.BIN` with the terminal's sprites, running: 51 ms median and 53 at the slowest at 2 MHz, 52 ms median at 1 MHz, about 47 bytes a frame. (The terminal's own time drawing the sprites isn't in these figures: it works while the next bytes arrive.) `SMBSW.BIN`:

| | 2 MHz | 1 MHz |
|---|---|---|
| Walking | 50 ms median, 50 average | 50 ms median, 51 average |
| Running | 51 ms median, 51 average | 49 ms median, 50 average |
| Redrawing instead of scrolling ($0505 = 1), running | 59 ms median, 61 average | 91 ms median, 84 average |

With the terminal doing the scrolling a frame sends about 70 bytes instead of about 200, and the 6502 only compares the new column, so the game keeps its speed even at 1 MHz.

## Sound

`SMB.BIN` plays music and sound effects on the **AY-3-8910 card** (`../ay`; registers at $7F22, data at $7F23). Without the card the game is simply silent. `SMBSW.BIN` has no sound: it already uses every byte of RAM.

- **Music:** four tunes, written for this game: outdoors (a quick, bouncy one, with an octave-jumping bass), underground (also the bonus rooms and under the coolant), the castle, and a faster one while MOS is overclocked. The melody plays on channel A and the bass on B.
- **Effects:** these play on channel C, over the music: jumps, bits, stomps, kicks, bumps, bricks, a power-up rising out of a block, the power-up and 1UP, getting hurt, pipes, electrons, KIL's fire and KIL being hit, the bridge falling, the flagpole slide and the time bonus ticking.
- **Jingles:** when MOS dies, at the end of a level, at the end of a world and at GAME OVER, the music stops and a jingle plays on A and B instead. With 100 left on the clock, a warning plays over the melody.
- **On / off:** **M** turns the sound on and off at any time. The byte at $0506 sets it at startup: 0 on (the default), 1 off. Pausing silences it.
- **Timing:** the sound runs 50 times a second, timed by the VIA's timer 2, which the game checks while it draws and waits. Timer 2's interrupt stays off, and timer 1 and the gamepad are untouched. The beat keeps time however long a frame takes to draw.
- **The engine:** `../ay/sfx.s`, shared with INVADERS. Its README is `../ay/README.md`.
- **The tunes and effects:** these are in `sound.py`, in a small note language. Run `python sound.py > smb_sound.inc` after changing them, then build. There is very little room left: `SMB.BIN` ends 34 bytes short of the buffers, so a longer tune means a shorter one somewhere else.
- **The title banner:** to make room for the sound, `SMB.BIN` sends the banner to the terminal once, as two terminal tiles at the end of `SMBSPR.SMB` (slots 0 and 1, 328 bytes of its 512-byte tile pool), and draws it with SEND TILE.

## How it works

- **The map:** levels are 11 tiles high and up to 255 wide. A tile is 8 × 8 pixels: 4 × 2 block graphics characters. The view is text rows 2-23 (80 × 22 characters, 160 × 88 pixels); row 0 is the status line.
- **The view in RAM:** a page for each text row, indexed by the world column (mod 256). Scrolling never moves anything in memory: only the tile columns coming into view on the right are filled in from the map.
- **Sending:** the view is compared with a copy of what the terminal shows, and only the characters that differ are sent. A run of the same character is sent once with the repeat count. Only the cells under the sprites (this frame and the last), tiles that changed and new columns are compared.
- **Scrolling:** a character (2 pixels) at a time. The game sets the terminal's scroll region to text rows 3-24 (the status line stays put), and when the view moves it sends 16 (scroll left one character; the repeat count is 0 then, since 1-15 would mean pixels). The copy of what the terminal shows is kept by world column, like the view, so the scroll needs no work in RAM: the column that comes in on the right is blank, and is drawn from the map.
- **Sprites in the terminal (`SMB.BIN`):** each object has a slot in the terminal's sprite layer (MOS: 15, drawn on top; object n: n). The pictures go to the terminal once, facing one way with their masks (906 bytes of its 1280-byte pool); the terminal mirrors them. Each frame, between HOLD and SHOW, the game sends only what changed: MOVE (5 bytes) when only the place did, PICTURE or FLAGS (4) when only the legs or the facing did, PLACE (7) for the rest, HIDE (3) when a thing goes. The view in RAM then holds only the map, so only the new columns and changed tiles are compared and sent. The sprites are clipped to the view (CLIP 2 23), so they never cover the status lines; the scroll moves the scenery under them, and they move to their new places in the same frame. Each frame goes to the terminal between HOLD and SHOW (the scroll, the scenery and the sprites), and then IDENTIFY (1C 0C): the terminal answers S P 1 when it has drawn everything before it, and the next frame waits for that answer (any one of the three characters, up to 150 ms) before it sends anything. So the terminal never falls behind and its receive buffer never fills; the 6502 works out the next frame meanwhile, so there is usually nothing left to wait for. The answer's S, P and 1 are not taken as keys. A frame that scrolls two characters sends one 12-pixel scroll instead of two (the terminal waits for its vertical blank once per scroll with sprites showing). (`SMBSW.BIN` still scrolls a character at a time, for older firmware.)
- **Bits that left pixels behind (fixed):** a tile that changed in a frame where the view also scrolled (a bit taken while running) was compared a few columns too far to the right, so some of its characters were never sent. The marks for comparing are now moved with the scroll. As a backstop against a lost byte, every changed tile is also sent again 10 frames later, once no sprite covers it (about 20 bytes).
- **GAME OVER** shows the terminal's STATUS (1C 0D, newer firmware): `LOST` is the bytes it dropped since the last STATUS (should be 00), `PEAK` its fullest receive buffer, `MISSED` the IDENTIFY answers that didn't come in time. A terminal without STATUS shows nothing there. Frames send about 47 bytes instead of 78.
- **Sprites while scrolling (`SMBSW.BIN`):** the scroll moves everything on the view, sprites too. So in a frame that scrolls, the sprites are first drawn at their new places on the view as it is before the scroll (a character further right), then the scroll code is sent: they move together with the background, and MOS is never shown out of place behind himself. Then the new column is sent.
- **Without terminal scrolling** ($0505 = 1): the view moves 2 characters at a time, the copy is moved along in RAM, and every row is compared and the changes sent (rows of empty sky the terminal already shows empty are skipped). The tiles are drawn to suit this: textures that repeat every character (the ground, bricks, ledges) look the same after a scroll, so only edges have to be sent.
- **Sprites (`SMBSW.BIN`):** 8 pixels wide (KIL, the fans, the fish and the cloud 16), 4 to 16 high. Each one is stored pre-drawn for both pixel positions across a character cell, facing one way, with a mask. As it is drawn it is shifted down 0-3 pixel rows (2 bits a row, through the cell above) and mirrored with a 256-byte table if it faces the other way; then each character is an AND with the mask and an OR. The black parts of a sprite (eyes, pins) cut out the background.
- **World files:** "SM", version 2, the number of levels, an offset to each, then for each level its width, start, time, flags (a castle, under the coolant, the last level, the last of its world), the bonus room's first column and its exit pipe, the 11 rows of tiles run-length coded, and the enemies (column, row, kind). A file is loaded into the view buffer, which is free until the level starts; the level is unpacked into the map and its enemy list copied out. After a level whose "last of its world" flag is set, the next is level 1 of the next WORLDn.SMB.
- **Bonus rooms** are stored in the same map, after the level's end (a level with one is at most 232 tiles wide). Going down the pipe saves the view, moves it to the room and keeps it there; coming out puts it back on the exit pipe.
- **Physics:** positions are 16.8 fixed point pixels across and 8.8 down; speeds are 8.8. Walking is 1.75 pixels a frame, running 3. A jump starts at 6 pixels a frame up (a little more when running) and gravity is 0.5 a frame while A is held on the way up, 1.5 otherwise: about 5 tiles high at most, or 2 for a quick tap.
- **Enemies** come in as their column nears the right of the view and go when they are well off the left.
- **Memory:** no zero page is used. `SMB.BIN`: the program occupies $0500–$4467, its variables $4468–$47DD, the map and screen buffers $4800–$7EFF, and the sound's variables $0100–$017A. `SMBSW.BIN`: the program $0500–$44C9, its variables $44CA–$47E7, and the buffers $4800–$7EFF: all the RAM there is.
- **ROM entry points:** the game uses `sbc_api.inc` (one folder up): `SBC_CHRIN`, `SBC_CHROUT`, `SBC_PADSTATE`, `SBC_MENU`, `SBC_LOAD` (if the ROM has it) and `CLOCK_MHZ`.

## Making levels

The levels are in `levels.py`. World 1 is laid out by hand with a few helpers: `pipe(x, height)`, `stairs(x, n)`, `pit(x, width)`, `put(x, y, "B?B")`, `hidden(x, y)`, `andg(x)`, `org(x)`, `fan(x, y, hi)` (hi: flies up to near the top), `fish(x, y, wave)` (wave: swims in a wave), `cloud(x)`, `bonus(x, out)` for a pipe down to a bonus room that comes back out on a pipe at `out`, `finish(x)` for the flagpole and the 6502, `castle_end(x)` for KIL's bridge and RESET. Worlds 2 to 5 are put together from pieces (`outdoor`, `ledges`, `water`, `castle`) with a random seed for each level; change a seed for a different level. The map characters:

| Character | Tile |
|---|---|
| `#` | ground |
| `B` | brick |
| `?` | ? block with a bit |
| `M` | ? block with a mushroom (a flower when big) |
| `O` | ? block with an OC device |
| `*` | hidden block with a 1UP |
| `H` | hard block (stairs) |
| `L` | ledge |
| `W`, `v` | castle wall, lava |
| `=`, `R` | KIL's bridge, the RESET button |
| `[ ] { }` | pipe top, pipe |
| `< >` | the top of a pipe that goes down (to the bonus room, or back out of it) |
| `w`, `f`, `u` | the coolant's surface, a fin, a bubble |
| `o` | bit |
| `r s`, `p`, `b d`, `t` | resistor, capacitor, chip, transistor (scenery) |

Run `python gen.py` after changing it: it writes `smb_data.inc` and the `WORLDn.SMB` files; then build. Add a world to `WORLDS` for a WORLD6.SMB (up to 9 worlds). `python test/reach.py` checks that each level can still be finished (see below).

## Files

| File | What it is |
|---|---|
| `smb.s`, `smb.cfg`, `make.bat` (Windows), `Makefile` | source and build (ca65/ld65), for the clock set in `../sbc_api.inc` |
| `gen.py`, `levels.py` → `smb_data.inc`, `WORLD1.SMB` ... `WORLD5.SMB`, `SMBSPR.SMB` | the tiles, the sprites, the title banner and the levels |
| `sound.py` → `smb_sound.inc` | the music and sound effects (for `../ay/sfx.s`) |
| `SMB.BIN`, `SMBSPR.SMB`, `SMBSW.BIN`, `WORLD1.SMB` ... `WORLD5.SMB` | ready to load (built for 2 MHz) |
| `test/` | the emulator harness (`sh b.sh` builds with a label file for it) |
| `screenshots/` | images from that harness |

The `test/` folder holds:
- **`sound_check.py`:** plays the levels with the bot, as `play.py` does, with the sound card and timer 2 modelled. It checks that the sound runs 50 times a second, which sounds the game asked for, the music and effects heard on each channel, and that the stack stays clear of $0100-$017A. It also writes the first 40 seconds to `smb_sound.wav`.
- **`phys.py`:** MOS's physics in Python, the same fixed point arithmetic as the game, with rough enemies. `physcheck.py` compares it with the game frame by frame.
- **`reach.py`:** searches the inputs, frame by frame, for a way from the start of each of the 20 levels to the flagpole or RESET (without enemies). `WALK=1` allows walking only.
- **`finish.py`:** plays each level in the emulator along the way `reach.py` found. The game must follow it frame for frame and reach the flag.
- **`play.py`:** a bot plans a few frames ahead with `phys.py` and plays with the gamepad (`WORLD=n` and `START=n` pick where, `LIVES=n` keeps it going, `GARBAGE=n` starts from random RAM). The emulator's SBC_LOAD reads the WORLDn.SMB files from the folder. Every frame it checks two things:
  - the terminal shows exactly what the game's copy of the screen holds;
  - the game's view holds exactly the map at the scroll position with the sprites over it, drawn again in Python from the game's state.
- **`features.py`:** set pieces: ducking, ? blocks, bits and bytes, the mushroom, the flower and electrons, a hidden 1UP, bricks, stomping, shells, getting hurt, dying, the timer, pits, game over, the flagpole, KIL (beaten with electrons, breathing fire, RESET), loading 2-1, a missing level file and a ROM without SBC_LOAD. `newfeat.py` adds the newer ones: the bonus room pipes, the OC device, fans, swimming and the fish, the cloud, KIL in world 5, the princess, OR gates at ledges, shells coming back out, high fans and wavy fish. `runf.py OUTDIR scene ...` runs some of them (each scene takes a minute or so).
- **`menus.py`:** the keyboard controls, the title, pause and quit.
- **`duckcheck.py`:** small and big MOS run, duck and slide on, jump while ducked (still ducked in the air), land and stand up.
- **`ghost.py`** (`SOFT=1`): at every scroll code, the picture just after it must already show MOS where he is at the end of the frame.
- **Which version:** the tests run `SMB.BIN` against a model of the terminal's sprite layer in `sim.py` (pictures, slots, HOLD/SHOW, CLIP, IDENTIFY); every frame the terminal's sprites must be exactly the objects the game has (slot, picture, place, facing). `SOFT=1` runs them against `SMBSW.BIN`. `NOSPRITES=1` makes the model an older terminal. `STALE=1` makes it keep a covered cell's background from when the sprite arrived (the left-behind pixels); `NOUNC=1` turns off the game's hiding of sprites over changed tiles in a `UNC_TILE=1` build (an old workaround, off by default and no longer needed); `NOSHIFT=1` and `NOHEAL=1` turn off the two fixes for the bits, and `play.py` then shows the characters that were never sent. `play.py` also prints how many vertical blank waits each frame would cause.
- **`frames.py`, `fit.py`, `prof.py`:** frame times, the timing model, and where the time goes.
