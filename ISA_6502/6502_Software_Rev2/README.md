# 6502 CPU Rev2 — firmware design: address map, IRQs and drivers

Last updated: 2026-11-13. This is the reference for the modular EhBASIC + monitor ROM for the CPU Rev2 card. Which cards a ROM supports is chosen at build time in `config.inc`.

## 1. Memory map

| Range | Use |
|---|---|
| $0000–$00FF | Zero page (EhBASIC; BIOS uses $E2–$EE) |
| $0100–$01FF | Stack |
| $0200–$027F | Monitor line buffer |
| $0280–$02FF | CH376 variables |
| $0300–$037F | EhBASIC page-3 variables, IRQ/NMI code, input buffer |
| $0380–$03FF | BIOS variables |
| $0400–$04FF | Console input buffer (256 bytes) |
| $0500–$07FF | **Driver variables (new for Rev2)** |
| $0800–$7EFF | BASIC programs / monitor-loaded programs (`USER_RAM`, default $0800) |
| $1000–$7EFF | Banked window (within the range above) |
| $7F00–$7FFF | I/O page |
| $8000–$FDFF | ROM: EhBASIC, then BIOS + drivers |
| $FE00–$FEFF | Fixed jump table |
| $FF00–$FFF9 | wozmon |
| $FFFA–$FFFF | Vectors |

**Banking.** The bank register is at $7FFE: write D3–D0, read back with `AND #$0F`. /RESET clears it to bank 0. The physical address is bank × 32K + the CPU address, so bank 0 is the original 32K. An AS6C1008 gives banks 0–3, an AS6C4008 gives 0–15, and the on-board RAM gives 1. The BIOS counts the banks at reset and restores the probe bytes, so a warm start loses nothing.

**Rule:** the BIOS and every interrupt handler keep all their state in $0000–$0FFF, so interrupts are safe in any bank. Code that switches banks must itself live in ROM or in $0000–$0FFF. A BASIC program or a game in the banked window would switch itself out.

## 2. I/O map

| Address | Card | Device |
|---|---|---|
| $7F00–$7F0F | ISA6502_IO | 65C22 VIA (port A gamepad, port B LEDs, T1 tick) |
| $7F10–$7F11 | ISA6502_IO | PCF8584 I2C (LCD) |
| $7F14–$7F17 | Serial Rev3 | 6551 ACIA |
| $7F18–$7F1B | KB_MONITOR_TERM **or** ESP32_VGA | Terminal 6551 / ESP32 4 registers (only one is ever fitted) |
| $7F1C–$7F1D | PICO9918 card | VDP data / register |
| $7F1E–$7F1F | Serial Rev3 **or** PICO9918 card | AVR keyboard/mouse/serial: data / status (D7 KBAVAIL, D6 DBUSY) |
| $7F20–$7F21 | Advanced_IO | CH376 data / command (fully decoded) |
| $7F22–$7F23 | AY sound card | AY-3-8910 register / data (ports A/B readable) |
| $7F26 | AY sound card | SPO256: write = allophone, read D0 = STBY, D1 = /LRQ |
| $7F28–$7F2B | Advanced_IO | 65SPI (data, status/ctrl, slave select) |
| $7FFE | CPU Rev2 | Bank register |
| $7FFF | CPU Rev2 | Interrupt register (reads (7−n)×2) |

**Bus clocks (Rev2):** OSC = the CPU clock (74ACT74 FF1 Q, as on Rev1), CLK = /CLK, T/C = the raw oscillator (2 × the CPU clock, new on Rev2). The cards' PLDs gate their strobes with OSC, so each access gives one pulse.

The SPI IDE interface (ATmega32 at 16 MHz) is on 65SPI ss0. It speaks Daryl Rictor's FAT16 command protocol: SPI mode 0, at least 2.2 µs between the command and data shifts, SCLK no faster than 4 MHz.

## 3. Interrupts

| Line | Source | Notes |
|---|---|---|
| 0, 1 | Header | Spare; go to BASIC's ON IRQ |
| 2 | VIA | T1 tick at 60 Hz (×TICK_DIV on fast clocks) |
| 3 | Serial card 6551 | RX interrupt only when it feeds the console |
| 4 | PCF8584 | Unused |
| 5 | KB_MONITOR_TERM | Or any of the 5/6 jumper cards |
| 5/6 | PICO9918 VDP, ESP32_VGA, AVR keyboard | Jumper; set in `config.inc` |
| 7 | 65SPI, SPO256 | Jumpers. Leave the 65SPI off (polling is faster); SPO256 /LRQ drives queued speech |

Dispatch: each line's handler is built at assembly time and calls the `_irq` routine of every driver on that line, keyboard first. A driver returns C=1 if it serviced the interrupt. If nothing claims it, it goes to EhBASIC's ON IRQ. Shared lines just work: a source that is still active interrupts again after the RTI.

## 4. Build options (`config.inc`)

`CPU_KHZ` is the one clock setting; every delay, the tick, and the serial and SPI timings come from it. The other settings: `CON_DISPLAY` (NONE / TERM / PICO / ESP32, exactly one), `CON_SERIAL` (NONE / AVR / ACIA), `CON_MIRROR`, `HAS_AVRKBD` + `AVRKBD_IRQ`, `ESP32_KBD` + `ESP32_IRQ`, `MOUSE_SRC` (AVR / ESP32 / NONE; defaults to the AVR interface if fitted), `HAS_ACIA` + `ACIA_BAUD` / `ACIA_CONSOLE` / `ACIA_WDC`, `HAS_VIA`, `HAS_GAMEPAD`, `HAS_AY`, `HAS_SPO`, `SND_DEV`, `HAS_SPI`, `HAS_IDE`, `FS_DEFAULT`, `PICO_*`, `HAS_BANKS`, `USER_RAM`, `CON_POLL`. Mistakes in the combination stop the build with an `.error`.

Clock checks: the ESP32_VGA card is only rated up to 4 MHz without its write latch. The 65SPI's SCLK is CPU/2, and the IDE interface's 4 MHz limit means the CPU can go up to 8 MHz.

## 5. Console

- **Input.** Every key source puts bytes into one 256-byte buffer from its interrupt handler. With `CON_POLL`, `CHRIN` also polls the devices (with interrupts off), so a wrong IRQ jumper doesn't kill the keyboard.
- **Output.** `CHROUT` goes to the display and/or the serial console, as chosen at boot. If the display card doesn't answer, output falls back to the serial console.
- **Control codes.** No PIC32 compatibility layer (decided 2026-11-13). Each display card is used with its own native command set, so nothing limits what the new cards can do. The console itself only relies on CR, LF, BS, TAB, FF and BEL. The old PIC32 games will be rewritten for the new cards rather than translated.
- **Key codes.** Everything is converted to the AVR set: arrows are the WordStar codes ^E ^X ^P ^D, Esc is 3, F1–F12 are 129–140 (shifted 141–152).

## 6. Driver notes

- **AVR keyboard interface.** The decoder is a state machine and reads one byte per interrupt; a mouse report is $FF $01 b x y. Output to $7F1E waits on DBUSY, with a timeout. A bare bus reads $7F (DBUSY stuck), so the card counts as missing if DBUSY never clears at boot. Mouse reports are off until a program turns them on.
- **ESP32_VGA (done, `drv_esp32.s` + `esp32vga.inc`).**
  - At boot the driver waits up to 3 s for the PING reply, then sends IO_RESET and V_RESET and sets the IRQ mask to `ST_KEY`.
  - Console output is one `STA VGA_DATA` per character.
  - Keys come from VGA_KEY on `ESP32_IRQ` (5/6, or 0 for polled) and are converted to the AVR codes.
  - The mouse uses IO_MDELTA when `MOUSE_SRC = MOUSE_ESP32`.
  - The ROM never reads STATUS, so the VBL bit belongs to the program. Its IRQ handler only reads VGA_KEY, so programs can send commands at any time.
  - Programs drive graphics, sprites and sound directly through `esp32vga.inc` (registers, every opcode and its arguments, colours, macros).
  - No read-modify-write instructions on its registers. Rated to 4 MHz.
- **PICO9918 (done, `drv_pico.s` + `pico_font.inc`).**
  - Ports: data $7F1C, control/status $7F1D (`PICO_DATA` / `PICO_CTRL` if the PLD is the other way round).
  - At boot: VRAM write/read-back test, then the F18A unlock. The PICO9918 configuration registers are read (VR58 option index, SR12 through VR15): Pico model 1/2 and firmware ≥ 1.0 give **80 × 30** text (T80: R0 = $04 + R1 M1, VR49 bit 6 = 30 rows). Unlocked, R2 uses all 4 bits (name table = (R2 & $0F) << 10), so R2 = $00 for $0000. The earlier $03, the locked/V9938 rule, put the table at $0C00 and gave garbage. Otherwise **40 × 24** (`PICO_COLS = 40` forces it).
  - Text mode: names $0000, font $1000 (5×8 glyphs from X11 koi5x8, normal at $20–$7F, inverse at $A0–$FF). The cursor is an inverse cell. One colour pair for the whole screen (R7).
  - `CLS 1` switches to Graphics II, 256 × 192: patterns $0000, colours $2000, sprite patterns $1800, names $3800, sprite attributes $3B00, 16×16 sprites. The console carries on as 32 × 24 text drawn into the bitmap. `CLS 0` returns to text.
  - Points, lines (Bresenham), boxes and circles (midpoint) are computed on the 6502.
  - VDP interrupt off by default (`PICO_IRQ = 0`; `SBC_VSYNC` polls the status). With `PICO_IRQ = 5/6` the handler keeps the status bits, and programs must disable interrupts around their own VDP accesses.
  - `PICO_SLOW` adds NOPs between accesses for a real TMS9918A.
- **Sound (done, `basic_ay.s`).** `SND_DEV` picks the device: the AY if `HAS_AY`, else the ESP32 synth when it's the display.
  - BASIC SOUND / NOTE / NOISE / QUIET work on either device, with the same timed-note queueing.
  - ESP32 notes are MIDI n+24 and volume ×17. NOISE becomes the noise wave at 125000/period Hz. A timed note ends with a gate-off sent from the VIA tick.
  - ENVELOPE, AYREG and AYREAD( are AY only. VOICE ch,wave[,a,d,s,r] is ESP32 only.
  - The AY mixer keeps R7 bits 6–7 (port A/B direction) in SOUND, NOISE and QUIET, so AYREG 7 sets the port directions and AYREAD(14/15) reads the ports.
  - API: SBC_SNDNOTE / SNDQUIET / SNDBUSY / AYREAD / AYWRITE.
- **SPO256 (done, `drv_spo.s`).**
  - Fed from a 64-byte queue by the VIA timer interrupt (every timeout). The chip's IRQ7 jumper must stay **off**: /LRQ is level and can't be silenced.
  - Without the VIA, SAY speaks synchronously.
  - BASIC: `SAY a,b,...` or `SAY s$`, with a pause allophone added at the end. API: SBC_SAY / SBC_SAYBUSY.
  - Detection: the status reads STBY=1, /LRQ=0 when idle.
- **Tokens.** The LCDPOS, LCDCLS, LOADARR and SAVEARR slots were reused, so every later token keeps its value: SAY (was LCDPOS), VOICE (was LCDCLS), and two free slots (was LOADARR/SAVEARR; they LIST as `?` and give ?SN). Use `LCDPRINT col,row,s$` and `LCDCMD 1` instead of the old LCD statements. Free tokens now: 2 statement slots plus $FF.
- **BASIC display statements (`basic_gfx.s`).** CLS [0|1], COLOR fg[,bg], LOCATE col,row, PLOT x,y,c[,r[,f]] (point / circle), PLOT x,y TO x2,y2,c[,f] (line / box / filled box), SPRITE n,p,x,y[,c], SPRITE DEF p,addr. Tokens $FA–$FE, dispatched through SND_CTBL like the sound statements; $FF was kept free. Coordinates and colours are each card's own (ESP32 320×240, 0–63 colours; PICO9918 256×192, 0–15 colours). PEEK(65279) gives the display type.
- **Storage (done: `drv_spi.s`, `drv_ide.s`, `fs.s`).**
  - 65SPI: soft reset, mode 0, polled TC, and a presence check (mode bits read back in the status).
  - SPI-IDE: every transaction is SS0 low, two shifts ($01 send / $02 status / $03 get), a 2.2 µs gap computed from `CPU_KHZ`, then SS0 high. Waits: bit 7 before a command, bit 5 = 0 before each byte sent, bit 6 before each byte read, then bit 7 again for the error code. Timeout ≈ 5 s gives $FF.
  - `drv_ide.s` mimics the CH376 calls the LOAD/SAVE code and the monitor already use. Open first tries a CD, so a directory returns $41 and becomes current, as on the CH376. Reads are clipped to the file size taken from D0. Errors map to the CH376 codes (04 → $42 not found, 0B/0C → $B1 full, others $E0+code).
  - `fs.s` dispatches on `fs_dev`: **U:** = CH376, **C:** = CF. A prefix on any name switches device and the choice sticks (`LOAD "C:GAME"`, `LOAD "C:$"`, monitor `L C:`). `FS_DEFAULT` sets the device at reset. Switching device in the monitor returns to its root.
  - **Text LOAD.** `LOAD` checks the file it read: one with no $00 byte is a plain-text listing (CR, LF or CR/LF). It is moved to the top of memory, the end of memory is lowered below it (BASIC's own ?Out of memory check protects it), the program is cleared, and CHRIN feeds the text to BASIC's line entry with CHROUT muted (`ld_on`). Lines without a line number are skipped, TABs become spaces, lines over 71 characters are cut and reported. At the end the end of memory is restored and Ready printed. An error during the load (LAB_XERR calls `ld_abort`) stops it and is shown. SAVE still writes tokenised files, which load as before.
  - The CF listing is the interface's own text listing (no pattern filter).
  - The DS1302 is reached through monitor `T` / `T dwyymmddHHMMSS` and SBC_TIME / SBC_SETTIME.
  - CH376 timing now uses `DELAY_MS`, NOPs scaled to the clock and a timeout scaled to the clock, so the 8-bit delay limit is gone.

## 7. Fixed jump table ($FE00)

| Address | Entry | Description |
|---|---|---|
| $FE00 | CHRIN | Get a character |
| $FE03 | CHROUT | Print a character |
| $FE06 | MENU | Boot menu |
| $FE09 | COLD | BASIC cold start |
| $FE0C | WARM | BASIC warm start |
| $FE0F | MONITOR | Monitor prompt |
| $FE12 | PADSTATE | Gamepad buttons |
| $FE15 | LOAD | Load a file |
| $FE18 | CWD | Current folder |
| $FE1B | SYSINFO | A = display type, X = device bits, Y = API version (2) |
| $FE1E | SEROUT | Send to the serial console |
| $FE21 | MOUSEON | Mouse reports on/off |
| $FE24 | MOUSE | Buttons and movement since the last call |
| $FE27 | BANKSET | Select a bank |
| $FE2A | BANKGET | Current bank and bank count |
| $FE2D | TICKS | 60 Hz counter |
| $FE30 | ACIAIN | Serial card 6551 input |
| $FE33 | ACIAOUT | Serial card 6551 output |
| $FE36 | VSYNC | C=1 if a frame ended since the last call; A = status |
| $FE39 | CONRESET | Display back to the text console |
| $FE3C | SNDNOTE | A/Y → voice, note, volume, time (16 bit) |
| $FE3F | SNDQUIET | All sound off |
| $FE42 | SNDBUSY | A = voice: C=1 while its timed note plays |
| $FE45 | SAY | A/Y → allophones ended by $FF (queued) |
| $FE48 | SAYBUSY | C=1 while speaking |
| $FE4B | AYREAD | X = register → A |
| $FE4E | AYWRITE | Register X = A |
| $FE51 | TIME | A/Y → buffer ← "mm/dd/yy hh:mm:ss" (DS1302) |
| $FE54 | SETTIME | A/Y → "dwyymmddHHMMSS" |
| $FE57 | DIR | A/Y → block: .word table, .byte most, .byte device ('U'/'C'/0). The current folder, 16 bytes an entry: name 8, ext 3, attributes ($10 = folder), size 4. C=0: A = count |
| $FE5A | RUN | A/Y → block: .byte kind (0 = .BIN at $0800 in bank 0, 1 = BASIC program), .byte device, "NAME.EXT",0. Returns only on an error (C=1, A = code) |
| $FE5D | SHELL | A = RAM bank of a shell ($1000 JMP entry, $1003 "SH65"); MENU then returns there. A = 0: none |
| $FE60 | COPY | A/Y → block: .byte src device, .word → src path, .byte dst device, .word → dst path (full paths "/A/NAME.EXT"). Reads the whole file into the RAM banks other than the caller's, then writes it. C=1, A = error ($F0 too big) |
| $FE63 | DELETE | A/Y → block: .byte device, .word → path. C=1, A = error ($42 not found) |
| $FEFF | (byte) | Display type, for PEEK(65279) |

New entries are only ever added at the end.


