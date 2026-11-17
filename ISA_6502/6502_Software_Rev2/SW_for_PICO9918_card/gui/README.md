# GUI - a file manager for the CPU Rev2 (PICO9918)

The files on the USB drive (U:) or the CF card (C:) as a list with icons.
Point and double-click, or use the keys or the gamepad. A program you start
comes back to the file manager when it quits, and so do BASIC (`EXIT`) and
the monitor (Ctrl-C).

**Needs ROM stage 6b** (`CPU_Rev2_FW_stage6b.zip`): SBC_DIR, SBC_RUN, SBC_SHELL, SBC_COPY and SBC_DELETE. (With the first stage 6 ROM everything but copy / delete works.)
It also needs the PICO9918 and at least two RAM banks.

## Starting it

1. Copy `GUI.BIN` to the USB drive (or the CF card).
2. In the monitor: `L GUI 0800`, then `R`.
3. It copies itself into the top RAM bank and starts. You only do this once
   after each power-up or reset.
4. From then on, the boot menu shows `[G]o to the file manager`.

## Using it

| | Mouse | Keyboard | Gamepad |
|---|---|---|---|
| Select | click | Up / Down | Up / Down (repeats) |
| Open | double click | Enter or Right | A, Start or Right |
| Up a folder | right click, or the UP button | Backspace, Left or Esc | B or Left |
| Drive | the U: / C: buttons (top right) | U / C | Select |
| Scroll | the scroll bar's arrows and track | `<` `>` a screen | |
| BASIC / monitor / boot menu | BASIC, MON, MENU at the bottom | B / M / Q | |
| Copy the selected file | COPY | F5 or K | |
| Paste it into this folder | PASTE | F6 or P | |
| Delete the selected file | DEL | F8 or X | |
| Answer YES / NO | click YES or NO | Y, Enter / N, Esc | A / B |
| Read the folder again | | R | |

**What opening does:**

- **A folder:** goes into it. `..` at the top goes back up.
- **.BIN:** loaded into bank 0 at $0800 and run.
- **.BAS:** BASIC is started, and the program is loaded and run.
- **Anything else:** shown as text. TXT, DOC, ASM, S, INC, LST, CFG, BAT and similar files say TEXT in the TYPE column.

**Copying:** select a file and press COPY. Go to any folder on either drive and press PASTE. The copy is remembered until you copy something else, so you can paste it in several places. If a file with that name is already there, it asks before replacing it. Folders can't be copied or deleted.

**Size limit:** the ROM reads the whole file into the RAM banks other than the file manager's, then writes it. That gives 85,248 bytes with 4 banks, and bigger files give ?TOO BIG TO COPY. Whatever was in bank 0 (a program you ran) is overwritten, which doesn't matter because programs are loaded again when you start them.

**Deleting** asks first (DELETE NAME? YES / NO). It works on both drives; on the CF card it uses the interface's erase command ($C4).

**The text viewer** uses the ROM's text console, 79 characters a line and 21 lines a page.

- Space, Enter, Down, S or a click: the next page.
- Up or W: the page before.
- Q, Esc, Backspace, a right click, or gamepad B / Start: back to the list.

**MENU** turns the file manager off (`SBC_SHELL` 0) and goes to the boot
menu. **G** there brings it back as it was.

## How it works

- `install.s` sits at $0800 in GUI.BIN and the file manager at $0B00, linked to run at $1000.
  - The installer copies the file manager a page at a time into the top bank. The copy goes through a buffer in $0800-$0AFF, which is never banked.
  - It then calls `SBC_SHELL` with that bank and jumps to `SBC_MENU`, which the ROM now sends to the shell.
- **Programs keep all of bank 0.** The file manager and all its variables (the folder list, the viewer's text buffer, the selection) stay in the top bank while a program runs. So when you come back, the same folder is shown with the same file selected.
- **Listing:** `SBC_DIR` reads the folder into a table of 16-byte entries.
  - The list is sorted folders first, then by name.
  - It reads up to 200 entries.
- **Copy / delete:** `SBC_COPY` (block: source drive, → full path, destination drive, → full path) and `SBC_DELETE` (drive, → full path). The ROM does the bank switching for the buffer.
- **Running:** `SBC_RUN` loads and starts a program. The ROM switches the bank, so the file manager never has to.
  - For BASIC, the monitor and the boot menu, the file manager puts 8 bytes at $0F80 (`LDA #0 / JSR SBC_BANKSET / JMP ...`), because code running in a bank can't switch that bank away.
- **Folder:** the file manager keeps its own folder and drive, and copies the folder into the ROM's (`SBC_CWD`) before each listing, load or run.
- **Display:** Graphics I with ECM2 tiles and an ECM2 sprite for the pointer.
  - Tile patterns: $0000 and $0800 (the two planes).
  - Sprite patterns: $1000 and $1800.
  - Names: $2000. Attributes: $2400. Sprite attributes: $2600.
  - It sets palette entries 16-63.
  - Before a program or the viewer starts, it writes VR50 = $C0, which resets the PICO9918 (registers and palette).
- **Zero page:** none is used.
- **A program that uses the top RAM bank** overwrites the file manager. The ROM checks the "SH65" mark before it goes back there, so you get the boot menu instead; load GUI.BIN again to get it back. None of the current games use the banks.

## Files

| File | |
|---|---|
| `gui.s` | the file manager |
| `install.s` | the installer at $0800 |
| `gui.cfg` | ld65 layout: INSTALL $0800 (filled to $0B00), then CODE/RODATA/BSS at $1000 |
| `gen_gui.py` | font, icons, pointer, palette -> `gui_gfx.inc` |
| `make.bat` | build (ca65 / ld65) |
| `test_gui.py` | emulator test with a made-up USB drive and CF card |
| `shots/` | screens from the test |

Not yet tried on real hardware.
