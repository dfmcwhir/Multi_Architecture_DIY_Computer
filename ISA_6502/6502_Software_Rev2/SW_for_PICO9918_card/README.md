# SBC games for the CPU Rev2 ROM

These are the games remade for the new display cards. Each game folder builds with its own `make.bat` (ca65/ld65, `-I ..`), which finds these shared files one folder up:

| File | What it is |
|---|---|
| `sbc_api.inc` | the Rev2 ROM's jump table ($FE00), key codes, display types and `CLOCK_MHZ` (copied from the firmware) |
| `ay/sfx.s` | the AY-3-8910 sound effects engine (unchanged) |
| `lib/vdp.s` | PICO9918 / TMS9918A routines: setup, VRAM copy and fill, text, frame wait |
| `lib/font5x8.inc`, `lib/fontgen.py` | the console's 5 × 8 font, and the games' bold version of it (used by each game's gen.py) |

Every game loads and runs at **$0800**, for example `L INVADERS 0800` then `R`.

| Game | Display | State |
|---|---|---|
| INVADERS | PICO9918 | done |
| STACKER | PICO9918 | done |
| SMB | PICO9918 | next |
| DOOM, the rest | | to do |
