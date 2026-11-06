#  <h1>Software</h1>
<p>This folder includes EhBasic ported to work with the 6502 CPU rev1 card, the monitor program (which includes commands to load programs) and all the programs I have been playing with so far. Because all of this has been written for use the current add-on cards (specifically the MON_KEYBOARD_TERM card), none of it will likely be directly compatible with any new display and/or keyboard interface cards. New/updated software for the new cards will likely be placed in a new software rev2 folder. What I would like to do is make it so the display and/or keyboard drivers are not so integrated in the rest of the code, so that the type of display card installed can be specified at the top of the firmware code and it will pull everything in correctly.</p>

<h2>EhBasic</h2>
<p>Some of the commands that have been added to EhBasic are for using I2C, LCDs (via I2C), sound, and loading/saving files via the USB. Instructions for using those features are in the EhBASIC for the 6502 SBC manual.</p><p>It can be built using CA65 and these commands:<br>
ca65 main.s -o main.o -l main.lst<br>
ld65 -C sbc.cfg main.o -o rom.bin -m rom.map<br></p>

## Boot menu
    6502 SBC - EhBASIC 2.22
    [C]old start, [W]arm start, [M]onitor?
C = EhBASIC cold start, W = warm start (keeps program), M = wozmon.
CTRL-C in wozmon returns to the menu. From BASIC: `CALL 65280` enters wozmon.
Wozmon accepts lower case; load/modify memory as usual (`0300: DE AD`, `0300.030F`, `E000R`).

## Files
| file | what |
|---|---|
| main.s | top level; includes everything (order matters) |
| basic.s | EhBASIC (patched: no .org, Ram_base $0500, Ram_top $7F00, IRQ_vec/NMI_vec defined, blank INPUT line accepted instead of ending the program) |
| bios.s | your hardware layer + boot menu + vector setup + IRQ dispatch |
| ch376_abs.s / ch376_loadsave.s | CH376 driver; LOAD/SAVE/LOAD "$" adapted to EhBASIC |
| pcf8584.s | PCF8584 I2C bridge driver (init, start/send/read/stop, delay) |
| lcd_i2c.s | HD44780 LCD behind an MCP23008 (4-bit) |
| basic_i2c.s | BASIC statements/function for the I2C bridge and LCD |
| wozmon.s | monitor (at $FF00) |
| sbc.cfg | linker memory map (edit if your decoding differs) |

## BASIC file commands
`SAVE "NAME"` -> /NAME.BAS      `LOAD "NAME"`      `LOAD "$"` or `LOAD "$*.BAS"` = directory

## Memory map (sbc.cfg)
$0200 wozmon buffer | $0280 CH376 vars | $0300 EhBASIC vars | $0380 BIOS vars |
$0400 serial buffer | $0500-$7EFF BASIC RAM | $7F00 I/O | $8000 ROM | $FF00 wozmon | $FFFA vectors
Zero page: BIOS uses $E2-$E7 (free in EhBASIC); wozmon uses $24-$2B (free in EhBASIC).

## Verification
verify/ holds a ca65-subset assembler and 6502 emulator used to test this (ca65 itself wasn't available).

## tools/ebtok.py - tokenize ASCII BASIC on your PC
    python3 tools/ebtok.py hello.bas          # -> HELLO.BAS, copy to the drive's root
    python3 tools/ebtok.py prog.txt --upper   # upper-cases keywords/variables for you
Then on the SBC: `LOAD "HELLO"`. Source lines must be numbered; keywords must be UPPER CASE
(or use --upper). Same tokenizing rules as EhBASIC itself (e.g. TOTAL becomes TO+"TAL").
`verify/t4.py` checks the tokenizer's bytes against a program typed into the emulated BASIC.

## I2C and LCD keywords (pcf8584.s, lcd_i2c.s, basic_i2c.s)
    I2CINIT                      init PCF8584 (also automatic on first use)
    I2CWRITE addr, b1 [,b2...]   write up to 32 bytes to 7-bit address addr (0-127); no ACK -> "I2C Error"
    x = I2CREAD(addr)            read one byte (0-255); -1 if the device doesn't answer
    LCDINIT [addr]               (re)initialise the LCD (also automatic on first use). addr (0-127) selects an LCD at
                                 another I2C address from then on; plain LCDINIT returns to the default (0x20)
    LCDPRINT s$                  print a string at the cursor
    LCDPOS col, row              col 0-39, row 0-3
    LCDCLS                       clear
    LCDCMD n                     raw HD44780 command byte
Settings to check: CPU_MHZ (top of main.s - the ONE clock setting, used by the CH376 and I2C/LCD delays),
PCF_CLOCK and PCF_OWN in pcf8584.s; MCP_ADDR_W (default LCD address) and the nibble_tab wiring in lcd_i2c.s.
The LCD code drives an MCP23008 backpack. A PCF8574 backpack is NOT compatible (see notes below).
Don't start a variable name with I2CINIT / I2CWRITE / I2CREAD / LCDxxxx (EhBASIC tokenizes keywords anywhere).
**Tokens moved:** adding the keywords renumbers every token after NMI. Re-tokenize old programs from their
ASCII source with tools/ebtok.py; .BAS files saved by the previous ROM will not LIST/RUN correctly.
After adding keywords to basic.s, run `python3 tools/gen_keywords.py basic.s tools/ebtok.py`.
`verify/t6.py` tests all of this in the emulator with a PCF8584 / MCP23008 / HD44780 model.

## basic.s patch: stack flush vs. interrupts
LAB_1491 (stack flush) now runs SEI ... CLI around the moment its return address is parked on the stack,
so the serial receive interrupt can no longer overwrite it (this caused random jumps to address $0001).

## Disk errors
`?DISK ERROR $xx` now shows the CH376 status code: $FF = the chip never answered (timeout), $82 = drive removed,
$41/$42-type codes = file system problems.  Report that code when something fails.


## LCDINIT [addr [, type]]
- `LCDINIT` - default address 0x20, MCP23008 backpack
- `LCDINIT 39` - address 39 ($27), MCP23008
- `LCDINIT 39, 1` - PCF8574 backpack. type 0 = MCP23008 (default), 1 = PCF8574
- PCF8574 pin mapping: P0=RS, P1=RW (held low), P2=E, P3=backlight, P4-P7=D4-D7

## LOADRAW / SAVERAW (raw memory block files)
- `SAVERAW "NAME", start, end` - writes the bytes start .. end-1 (end is NOT included) to NAME.DAT
- `LOADRAW "NAME" [, start]` - reads the whole file to `start`; without `start` it goes to the first byte above BASIC memory
- ".DAT" is added if the name has no extension (LOAD/SAVE still add ".BAS"). Addresses can be hex, e.g. `$7000`.
- SAVERAW can save any memory range. LOADRAW only writes from the top of BASIC memory up to $7EFF, so it cannot damage the program, variables, strings or system RAM. To reserve space, answer the cold start question `Memory size ?` with a lower number (e.g. 28672 reserves $7000-$7EFF).
- Errors: ?Function call error (bad range or address), ?FILE TOO LARGE (does not fit), ?FILE NOT FOUND.

## SAVEARR / LOADARR (whole numeric arrays)
- `SAVEARR "NAME", A()` - saves the whole array A (any number of dimensions) to NAME.ARR
- `LOADARR "NAME", A()` - reads it back into A
- LOADARR needs the array to exist already with the same dimensions (`DIM A(9)` first). If the file's dimensions do not match, or the file is short, you get `?BAD FILE` and the array is not changed.
- Only numeric arrays. String arrays (`A$()`) give ?Type mismatch. An array that does not exist gives ?Function call error.
- The file holds the dimension header followed by the data, so a 10 element array is 1+2+10*4 = 43 bytes.

## Monitor commands (monitor_cmds.s)
At the monitor prompt (`\`):
- `?` - list the commands
- `L` - list the files on the USB drive
- `L` - list the files and sub-directories (`<DIR>`) of the current USB directory, headed by its path (`/` is the root).
- `L DIR` - change into directory DIR. `L ..` goes up one level, `L \` or `L /` back to the root. Paths work too: `L GAMES/DEEP`, `L /GAMES`. The monitor starts in the root directory. BASIC `LOAD`/`SAVE` always use the root.
- `L NAME [XXXX]` - load NAME.BIN from the current USB directory into RAM at hex address XXXX. Without XXXX the file goes to the monitor's current address (type an address and Enter first, e.g. `2000` then `L PROG`). `.BIN` is added when NAME has no extension; any other extension you type is used as is.
- Allowed load range is $0500-$7EFF; anything else gives `?SYNTAX`. A file that does not fit gives `?FILE TOO LARGE`.
- After a load the monitor's current address is the load address, so `R` runs the program.
- Disk errors print the same messages as BASIC and return to the monitor prompt.
- wozmon.s calls `MON_HOOK` when Enter is pressed (5 bytes in the WOZMON segment, which now has 4 bytes free). Add further commands in monitor_cmds.s. They must start with a character that is not a hex digit or `R`.

## NES gamepad (gamepad.s)
A NES style pad (4021 shift register) on the 65C22 VIA port A, polled 60 times a second from the VIA timer 1 interrupt (IRQ2). Button presses are put into the input buffer like typed characters, so BASIC (`GET`, `INPUT`) and the monitor see them; a held button auto-repeats.
- Wiring: PA0 <- DATA (10k pull-up to +5V), PA1 -> LATCH, PA2 -> CLOCK, plus +5V and GND. Other port A pins are not touched. Pins are set by `PAD_*_BIT` at the top of gamepad.s.
- Buttons are numbered in the order the pad shifts them out: 0=A 1=B 2=Select 3=Start 4=Up 5=Down 6=Left 7=Right.
- Defaults: Up `W`, Down `S`, Left `A`, Right `D` (upper case), A = space. B, Select, Start are unassigned.
- `PADKEY button, char` - assign a character (0-255; 0 switches the button off), e.g. `PADKEY 1,13` (B = Enter), `PADKEY 4,ASC("W")`. `PADKEY` alone restores the defaults. Edit `pad_defaults` to change the power-up mapping.
- Repeat: `PAD_REPEAT_DELAY` (20 polls = 1/3 s) then every `PAD_REPEAT_RATE` (6 polls); set the rate to 0 for no repeat. `PAD_ENABLE = 0` turns the whole feature off.
- Needs the VIA's interrupt on IRQ2 (as in bios.s). The timer period comes from `CPU_MHZ` (up to 3 MHz).
- The chip is not touched if all 8 buttons read as pressed (an unplugged or shorted data line).

## Fixed entry points for your own programs (jumptable.s, sbc_api.inc)
The BIOS routines move whenever the ROM is rebuilt, so a program you assemble separately and load with `L NAME ADDR` must not call them by address. The table at $FE00 never moves (each entry is a JMP):
- `$FE00` CHRIN (carry set + A = char; carry clear = none waiting; keyboard, serial and gamepad) - `$FE03` CHROUT (print A; A, X, Y preserved)
- `$FE06` boot menu - `$FE09` BASIC cold start - `$FE0C` BASIC warm start - `$FE0F` monitor prompt
- `$FE12` PADSTATE (A = buttons held right now, bit0 A, 1 B, 2 Select, 3 Start, 4 Up, 5 Down, 6 Left, 7 Right)
- `$FE15` LOAD (`SBC_LOAD`): load a whole file from the USB drive, silently. A/Y = low/high byte of a parameter block: `.word` load address, `.word` most bytes to write, then the 8.3 file name ending in a 0 byte. The name is relative to the monitor's current directory (`L DIR`; the root unless changed; set `SBC_LOAD_USES_CWD = 0` in monitor_cmds.s to always use the root). Returns carry clear + X/Y = length loaded (a longer file is cut at max and still counts as success), or carry set + A = error code ($42 file not found, other CH376 status codes, $FF timeout / no drive, $FE bad parameter block). It prints nothing, never jumps to the monitor, never writes past address+max-1, closes the file before returning, and mounts the drive if needed. Changes A, X, Y and flags.
`.include "sbc_api.inc"` gives the same addresses as ca65 equates. `R` runs the program with the stack reset, so end it with `JMP $FF00` (monitor) or `JMP $FE06` (menu), not RTS.


<h2>Games for the 6502 SBC</h2>

| Folder | Game |
|---|---|
| `invaders` | INVADERS: a Space Invaders style shooter |
| `snake` | SNAKE |
| `critters` | CRITTERS: a Lemmings style puzzle game |
| `muncher` | MUNCHER: a Pac-Man style maze game |
| `doom` | 6502 DOOM: a raycast first person shooter that loads its maps from the USB drive (needs `SBC_LOAD` in the ROM for maps after the first) |
| `stacker` | STACKER: a falling blocks game |
| `rocks` | SPACE ROCKS: a rock shooter in the style of the arcade classic (uses the terminal's sprite layer when it has one, and draws everything itself when not) |
| `grabber` | GOLD GRABBER: swing a grabber over a pit of treasure, rocks, gophers and TNT |
| `breaker` | BYTE BREAKER: a brick breaking game with capsules (wide paddle, three balls, laser ...); needs the terminal's sprite layer |
| `miner` | MINER MOS: a single-screen platform game: take every key, reach the portal before the air runs out; 8 rooms; needs the terminal's sprite layer |
| `smb` | SUPER MOS BROS.: a side-scrolling platform game (`L SMB 0500`; its 5 worlds are WORLDn.SMB files and its pictures SMBSPR.SMB, loaded from the USB drive with `SBC_LOAD`; it uses the terminal's sprite layer, and SMBSW.BIN is the version for older terminals) |

| Folder | Sound |
|---|---|
| `ay` | the AY-3-8910 sound card ($7F22/$7F23): a driver (`ay.s`), AYTEST (a test program), YMPLAY (plays .YM chip music from the USB drive, converted on the PC with `tools/ym2ays.py`), and `sfx.s`, the sound engine the games use |

| Folder | Tools |
|---|---|
| `term` | TERM: a terminal for BBSs through a Zimodem on the serial port |
| `edit` | EDIT: a full-screen text editor for files on the USB drive, with a view mode that shows markdown formatted |

Every game plays sound on the card: effects in all of them, and music in SMB, STACKER, MINER MOS, CRITTERS and DOOM (`SMBSW.BIN`, the version for older terminals, has no room for it). They all build with `ay/sfx.s`, so keep the `ay` folder next to them. Without the card they are just silent. In every game **M** turns the sound off and on, and the byte at $0505 ($0506 in SMB) sets it at startup.

Each one runs from the monitor at $0500 (`L NAME 0500`, then `R`) on the PIC32 terminal in control code mode (setup item J). Each folder has its own README.

## Terminal firmware

All but CRITTERS use features of terminal firmware v1.4: the repeat count in the attribute byte (18 n, bits 3-6) and tiles (19 SET TILE, 0B SEND TILE). Reverse video is `ESC [7m` / `ESC [27m`, because attribute bit 2 is now the double size font.

SUPER MOS BROS. also uses the newer sideways scrolling: the scroll region (`ESC [ top ; bottom r`) and scroll left (16), so the terminal moves the view and the game only sends the new column. On a terminal without it, set its byte at $0505 to 1.

## The CPU clock

`sbc_api.inc` (in this folder) holds the ROM's entry points and the CPU clock:

```
CLOCK_MHZ       = 2
```

The games size their delay loops from it, so their speed is the same at any clock. Change it to match your board (whole MHz, 1 to 8) and rebuild. DOOM is the exception: its enemies act once per drawn frame, so DOOM speeds up on a faster clock.

## Building on Windows

You need the cc65 tools (`ca65` and `ld65`) on the PATH. Then:

```
make_all.bat            every game (and the sound programs), for CLOCK_MHZ in sbc_api.inc
make_all.bat 1          every game, for a 1 MHz clock (overrides sbc_api.inc)
cd stacker
make.bat                just that game (make.bat 1 works too)
```

Each `make.bat` runs `ca65 -I ..` so the games find `sbc_api.inc` one folder up. The `.BIN` files in the folders are built for 2 MHz.

Some games have data generated by Python scripts. The generated files are included, so Python is only needed if you change them:

| Folder | Script | Run |
|---|---|---|
| `doom` | maps | `python mklevels.py` |
| `doom` | tables, wall patterns, sprites | `python gen_tables.py > tables.inc` |
| `muncher` | maze, sprites | `python gen.py > muncher_data.inc` |
| `stacker` | pieces, textures | `python gen.py > stacker_data.inc` |
| `rocks` | ship, rocks, saucers | `python gen.py > rocks_data.inc` |
| `smb` | tiles, sprites, levels (and the WORLDn.SMB files) | `python gen.py` |
| `grabber` | pictures, the rope's directions | `python gen.py > grabber_data.inc` |
| `breaker` | pictures, ball speeds, bricks, levels | `python gen.py > breaker_data.inc` |
| `miner` | pictures, tiles, rooms (`rooms.py`) | `python gen.py > miner_data.inc` |
| `ay` | the note table | `python tools/gen_notes.py > ay_notes.inc` |
| `ay` | the games' music and effects (`<game>_sound.inc`; SMB's are in `smb/sound.py`) | `cd ay/tools`, then `python game_sounds.py` |

(The Makefiles do the same with `make` on Linux; `make DEFS=-DCLOCK_MHZ=1` picks the clock there.)

## The test harness

Each `test/` folder has a Python emulator (py65 + Pillow) that models the terminal's control codes and plays the game with a bot, checking the screen against the game's state. (The `ay` one models the sound card, the VIA timer and the CH376 instead, and checks every register write.) Build with `sh b.sh` first; it also writes the label file the tests need. The emulator assumes a 2 MHz clock; set `CPU_MHZ=1` in the environment for 1 MHz builds.
