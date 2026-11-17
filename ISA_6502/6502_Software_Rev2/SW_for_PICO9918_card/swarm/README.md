# SWARM for the 6502 SBC (CPU Rev2, PICO9918)

The swarm shooter, remade for the **PICO9918** card with new graphics, and with the aliens diving and shooting the way they should.

The aliens fly in, in streams that loop and curve, and take their places in a formation that sways across the top of the screen. From there they peel off and dive at your ship, shooting as they come. Clear every alien to finish a stage. Every third stage is a **challenging stage**: the aliens fly past in patterns and don't shoot, and you score for every one you hit.

## Running

Copy `SWARM.BIN` to the USB drive, then in the monitor:

```
L SWARM 0800
R
```

- **Display check:** the game needs a CPU Rev2 ROM with the PICO9918. Otherwise it prints a message and goes back to the boot menu.
- **Quit:** Q in the game goes to the title. Q on the title resets the PICO9918 (its palette too), puts the text console back and goes to the boot menu.

## Controls

| Keyboard | Gamepad | Action |
|---|---|---|
| A / D or ← / → | d-pad left / right | move |
| Space | A or B | fire (two shots can be in the air at once) |
| P | Start | pause |
| M | | sound on / off |
| Q | | quit to the title |

The gamepad is the default; G on the title switches between keyboard and gamepad.

## What's new

- **Diving fixed:** in the PIC32 version, a lone alien leaving the formation was given the wrong flight path (the one for coming in), so it flew a loop and went home without attacking. Only the butterflies escorting a boss ever dived at you. Now every diver climbs, rolls over and dives at your ship, firing as it comes.
- **More of it:**
  - Up to 3 aliens dive at once at the start, one more every second normal stage.
  - A new dive starts about every 1⅓ seconds at the start, sooner on later stages.
  - Each diver fires 3 shots, 4 from the third normal stage on, every time; before, it fired 2 or 3, and each with a 1-in-10 chance of holding fire.
  - Up to 20 aliens and bullets can be in flight at once (10 before).
- **The graphics:**
  - Every alien is a 16 × 16 sprite in 3 colours of its own (the F18A's enhanced colour mode, ECM2):

    | Alien | Colours |
    |---|---|
    | bee | yellow and blue, with red |
    | butterfly | red and white wings, a blue body |
    | boss | green with purple wings, yellow eyes |
    | boss hit once | purple and blue |

  - Flying aliens turn smoothly through 16 headings, and their wings beat.
  - Your ship is white with red and blue.
  - The formation is drawn the same way, as tiles. It sways a pixel at a time using the PICO9918's hardware scroll.
  - Stars drift down behind everything.
  - The status line and the messages are in white and red.

## Playing

- **The formation:** 4 bosses on top, 16 butterflies, then 20 bees. Each stage they come in as 5 groups of 8, two streams at a time (one the mirror image of the other). You can shoot them as they come in.
- **Dives:** once all the aliens are in, they leave the formation now and then. Each climbs, rolls over and dives at your ship, steering towards it and firing. One that misses goes off the bottom, comes back in from the top and returns to its place. A boss that dives takes up to two of the butterflies beside it along.
- **Bosses** take two hits. The first turns them purple and blue.
- **Points:**

| Alien | In the formation | In flight |
|---|---|---|
| bee | 50 | 100 |
| butterfly | 80 | 160 |
| boss | 150 | 400 |

- **Your ships:** you start with 3. The ones waiting are shown bottom left. Extra ships come at 20,000 and 70,000 points. When your ship is hit, the divers go back to the formation, and the next ship comes when the air is clear ("READY").
- **Challenging stages** (stages 3, 6, 9 ...): 40 aliens in 5 groups fly through on set paths and leave, and none of them shoots. Each hit is 100 points. At the end you get the number of hits and a bonus of 100 a hit, or 10,000 for all 40 ("PERFECT!").

## Header (patch from the monitor before `R`)

| Address | Default | Meaning |
|---|---|---|
| $0803 | 2 | video frames (1/60 s) a frame: 30 frames a second, as before |
| $0804 | 1 | controls at the start: 0 keyboard, 1 gamepad |
| $0805 | 0 | sound at the start: 0 on, 1 off |

The game keeps 30 frames a second at 2 MHz and at 4 MHz.

## How it works

- **The PICO9918's F18A features:** Graphics I with both tile layers, enhanced colour mode 2 for the tiles and the sprites, 16 × 16 sprites, 31 sprites a line, the palette, and the horizontal scroll.
  - **ECM2:** each pixel has 2 bits, and the sprite's colour nibble (or the tile's attribute byte) picks a group of 4 palette entries. The game sets entries 16–63 for its 12 groups, so the standard 16 colours (0–15) are untouched.
  - **Pattern planes:** sprites at $1000 and $1800, tiles at $0000 and $0800.
- **Sprites:** one per object (26).
  - Sprite k has its own pattern, names 4k. When the object's picture changes (a new heading, the wings, an explosion frame), its 64 bytes are copied in from the pictures kept in the program.
  - Left-facing headings are the right-facing pictures mirrored, using the F18A's flip bit.
  - Positions keep the half pixels, so they move smoothly. Sprites going off the left edge use the early clock bit.
- **Layer 1:** the formation. Each place is 2 × 2 tiles at name column 9 + 2·column. The sway is the scroll register R27 = 72 − x. The places are 16 screen pixels apart, so the game's positions for them are worked out from the screen (`grid_xy`).
- **Layer 2:** the status line, messages, stars and the ships in reserve.
  - It lies under the sprites (R50 bit 0 with the tiles' priority bit clear).
  - Its blank pixels are see-through (the attribute's TRANS bit).
- **Layout:**
  - VRAM: tile patterns $0000/$0800, sprite patterns $1000/$1800, layer 1 names $2000, attributes $2400 (layer 1) and $2500 (layer 2), sprite attributes $2600, layer 2 names $2800.
  - Memory: the program runs at $0800 and uses no zero page. It ends at about $5500.
- **Testing:** an emulator test played 6,000 frames with a bot, through stages 1–8 including the challenging stages, at 2 and 4 MHz. Every frame it checked:
  - every sprite's place, picture, pattern and colours against the game's objects;
  - the formation on layer 1 against the game's grid;
  - the scroll against the sway;
  - that no alien stays in flight.

  The emulator models ECM2, the flips and the layer priority from the F18A documentation. This is the first game here to use those features, so on the real PICO9918 they still need confirming.

## Files

| File | What it is |
|---|---|
| `swarm.s`, `swarm.cfg`, `make.bat` | source and build (ca65/ld65, `-I ..`); `make.bat 4` for 4 MHz |
| `gen.py` → `swarm_data.inc` | the sine and arctangent tables and the flight paths (unchanged) |
| `gen_pico.py` → `swarm_gfx.inc` | the new art (16 × 16, 3 colours), its 16 headings, the palette, the tiles; `python gen_pico.py png` draws `sheet.png` |
| `swarm_sound.inc` | the sounds (unchanged) |
| `SWARM.BIN` | ready to load (2 MHz build; use `make.bat 4` for 4 MHz) |
