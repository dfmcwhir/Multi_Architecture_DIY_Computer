# SUPER MOS BROS. for the 6502 SBC (CPU Rev2, PICO9918)

The platform game, remade for the **PICO9918** card using its F18A features. Everything the game does is the PIC32 version's, unchanged:
- MOS, the gates, KIL, the electrons and the physics;
- the 20 levels in WORLD1.SMB … WORLD5.SMB;
- the music and the sound.

Only the drawing is new.

## Running

Copy `SMB.BIN` and `WORLD1.SMB` … `WORLD5.SMB` to the USB drive, then in the monitor:

```
L SMB 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q on the title puts the text console back and goes to the boot menu.
- **Controls:** the same as the PIC32 version (see the title screen). The gamepad is the way to play. Pressing a pad button switches from keyboard to gamepad mode by itself. The AVR keyboard's arrow keys work too.

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 3 | frames (1/60 s) per game frame: 3 = 20 a second, the speed the game was made for (2 = faster, 4 = slower) |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0806 | 0 | sound at the start: 0 on, 1 off |

## The picture

Version 2 uses the PICO9918's **ECM2** mode (4 colours per tile and per sprite pixel, from a 64-colour palette) and new 16 × 16 art, drawn at full screen resolution instead of magnified blocks. A game tile (8 × 8 game pixels) is one 16 × 16 picture.

- **The level:** each game tile is 2 × 2 cells of tile layer 1. The 11 tile rows fill the screen below the status lines, and 16 tiles show across, as on the NES.
  - New art: brick ground with rivets, shaded blocks and question blocks, round pipes, coins, the castle chip with its legs and "6502" label, coolant with waves, molten solder with flames, the flag and pole.
  - 107 tile patterns, each with its own palette group, so the same picture can't come out in the wrong colours.
- **Scrolling:** smooth, a game pixel at a time, with the hardware scroll.
  - The two name table pages side by side make a ring 32 tiles wide (R27, R29, the page bit).
  - Only the tile columns coming into view are written, plus any tile that changes (a block bumped, a bit taken, a brick broken).
- **Status lines and texts:** on tile layer 2, which stays still on top: white and yellow letters on black bands.
- **Sprites:** everything that moves, drawn as 16 × 16 ECM2 sprites (3 colours each, plus see-through).
  - MOS is two sprites stacked per 16 × 16 part (a base and an overlay), so he has 6 colours: hat, face, eyes, overalls, shoes. With the flower he turns white and red.
  - The gates, KIL the dragon, the princess, the electrons and the rest have their own pictures; each is cut into 16 × 16 parts.
  - Each of the 32 sprite slots has its own pattern. When a slot's picture changes, its part (64 bytes) is copied from the program into VRAM, so only parts in use are loaded.
  - Up to 31 sprites a line are shown, so nothing flickers.
- **The sky:** light blue outdoors, black under the bricks, in the bonus rooms and in the castles, and dark blue under the coolant.
- **On exit** the VDP and its palette are reset (VR50 = $C0), so the text console comes back in its own colours.

## How it works

- **The drawing code:** `put_tile`, `put_col`, `render`, `make_sprites`, `add_obj`, `set_scroll` and `pace` in `smb.s`.
  - The view's left edge is `sc2` (game pixels). It follows MOS a pixel at a time.
  - `scroll` (in the old 2-pixel units) is kept for the rest of the game.
- **Timing:** each game frame waits `speed` VDP frames (`pace`). The scroll register and the sprite table then go to the VDP at the start of the frame's blank.
- **VRAM:**

  | Address | Contents |
  |---|---|
  | $0000 / $0800 | tile patterns, planes 0 and 1 |
  | $1000 / $1400 | sprite patterns, planes 0 and 1 (slot k = names 4k) |
  | $1800 / $1C00 | layer 1 names (2 pages) |
  | $2000 | layer 2 names |
  | $2300 / $2400 | layer 1 / layer 2 attributes (one byte a pattern: palette group, see-through) |
  | $2500 | sprite attributes |
- **Registers:** R49 = $A2 (layer 2 on, ECM2 tiles and sprites), R29 = $42 (sprite planes 1K apart, two name pages), R30 = 31 sprites a line, R50 = 0. The palette (64 entries, 16 groups of 4) goes in through R47.
- **`art_hd.py`** holds all the art as text pictures (`.123` = see-through and the 3 colours of a group) and the palette.
- **`gen_pico.py`** makes `smb_pico.inc` from art_hd.py: the tile planes, attributes and palette, the sprite parts, and each picture's list of parts (offset, part, palette group, mirrored or not). Run `python gen_pico.py` after changing a picture or a colour; `python gen_pico.py png` also draws everything into `sheet.png` to look at.
- **The levels:** these are still made by `gen.py` from `levels.py`. Run `python gen.py` for new WORLD files; it also writes smb_data.inc, which this version doesn't use.
- **Memory and zero page:** RAM from $0800 up to $79FF (the program to about $5ACD, then the map and the world file buffer). No zero page is used.

## Files

| File | What it is |
|---|---|
| `smb.s`, `smb.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`) |
| `art_hd.py`, `gen_pico.py` → `smb_pico.inc` | the art, the palette and the sprites |
| `gen.py`, `levels.py` → `WORLD1.SMB` … `WORLD5.SMB` | the levels (and the pictures gen_pico.py uses) |
| `sound.py` → `smb_sound.inc` | the music and effects |
| `SMB.BIN` | ready to load |
