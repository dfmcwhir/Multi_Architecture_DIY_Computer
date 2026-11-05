# TERM: a terminal for BBSs through a Zimodem

TERM joins the serial port, where the Zimodem is plugged in, to the PIC32 display card: what the BBS sends goes to the screen, and what you type goes to the BBS.

```
L TERM 0500
R
```

Then type AT commands to the Zimodem as usual, or press **Ctrl-A D** to dial a BBS.

## Local commands: Ctrl-A, then

| Key | |
|---|---|
| D | dial: asks for `host:port` and sends `ATDT"host:port"`. `:23` is added if you give no port. The `T` makes the Zimodem handle the telnet protocol, so TERM doesn't have to. |
| X | hang up: a second of silence, `+++`, another second, `ATH` |
| S | set-up: the serial port and the other settings (below) |
| E | local echo on/off |
| L | a line feed after every CR received, for systems that send CR alone |
| C | ANSI colours as mono (the default), or passed on as they are |
| K | Backspace sends BS instead of DEL |
| Z | clear the screen |
| A or Ctrl-A | send a Ctrl-A |
| H | help |
| Q | quit (it asks) |

TERM starts at 1200 8N1, the Zimodem's own default, unless `TERM.CFG` says otherwise.

## Set-up (Ctrl-A S)

A screen of the settings. Press an item's digit to step it to its next value, `S` to save them all in `TERM.CFG`, Enter or Esc to go back.

| | Setting | Values |
|---|---|---|
| 1 | baud rate | 110, 150, 300, 600, 1200, 1800, 2400, 3600, 4800, 7200, 9600, 19200, and 115200 (the 6551's 16x external clock: only if the card feeds 1.8432 MHz to RxC, as the display card does) |
| 2 | data bits | 8, 7, 6, 5 |
| 3 | parity | none, odd, even, mark, space |
| 4 | stop bits | 1, 2 |
| 5 | DTR | on, off (with DTR off the 6551 stops receiving, and the Zimodem may hang up) |
| 6 | RTS | on, off, or FLOW: RTS/CTS flow control (below) |
| 7 | local echo | off, on |
| 8 | LF after CR | off, on |
| 9 | colours | mono, as sent |
| 0 | backspace | sends DEL, or BS |

- **Changing the rate or format:** the port changes when you leave set-up. If the rate or format changed, TERM offers to tell the Zimodem first, by sending `ATB"rate,8N1"` at the old setting. Do that while not connected, and use `AT&W` on the Zimodem if it should keep the new setting.
- **RTS flow control (FLOW):** TERM lets RTS go when the ROM's serial buffer is three quarters full (192 bytes), and asserts it again under 64. With the Zimodem set for it (`AT&K3`), it then waits instead of overrunning the buffer. TERM's own pacing of what it sends works whatever /CTS does. For this TERM reads the ROM's buffer pointers (`READ_PTR` and `WRITE_PTR`, at $E2 and $E3 in the current ROM). If a later ROM moves them, change `ROM_RP` and `ROM_WP` in `term.s`.
- **`TERM.CFG`:** read at the start from the monitor's current folder, the way YMPLAY and SEQ find theirs. Without a USB drive, or without the file, the defaults are used.

## What TERM does to what the BBS sends

The display card does most of ANSI itself: cursor movement, erasing, scroll regions, insert and delete, bold, underline, reverse, and the CP437 box, block and shade characters. Its cursor position report goes back to the BBS, so ANSI detection works. TERM passes all of that on as it comes, and changes only these:

- **Colours:** the display has one colour, so TERM turns each colour change into what it can show:
  - bright text becomes bold;
  - where the background is lighter than the text (black on cyan, blue on white), the text is shown in reverse so it doesn't vanish.

  It only sends an attribute when it changes, and drops what the display would misread: SGR 3 (italic) changes its font. With Ctrl-A C the colour codes go through untouched.
- **Control codes:** in control code mode (which the games need) the display treats codes 01-1F as its own commands. A BBS means them as CP437 characters (smileys, arrows, card suits), so TERM sends them as `1A n`, which draws them. BS, TAB, LF, FF and CR still act as controls. DEL (7F) is shown as its character too.
- **NUL** is dropped (padding).
- **BEL** beeps on the AY card, if there is one.

The screen is 24 lines, not the usual 25. BBSs that ask the terminal its size will use 24.

## How it works

- **The serial port:** the ROM's interrupt and buffer receive from it as before, and TERM reads it with `SBC_CHRIN`.
- **The keyboard:** the display card's receive interrupt feeds the same buffer, so TERM turns it off and reads the keyboard itself. It checks between every byte it sends to the screen, and while it waits to send to the modem, into a 64-byte buffer of its own. A cursor position report (9 bytes back to back at 115200) arrives whole even when the screen is busy.
- **Timed sending:** bytes to the screen and to the modem are paced by time (one byte time each) rather than by the 6551's transmit bit. So a W65C51N, whose transmit bit is always set, works here too.
- **Put back on quitting:** the gamepad's interrupt is off while TERM runs, because it would type into the serial buffer. Quitting puts back the keyboard interrupt, the gamepad and the ROM's 2400 8N1.

## Building and testing

`make.bat`, as for the games. TERM uses `common.s` and `ch376r.s` from the `ay` folder (the USB drive code, for `TERM.CFG`). `test/test_term.py` runs TERM in an emulator (py65) with models of both 6551s (a byte not read in time is lost, as on the chip), the VIA timer and the AY card. It checks:

- the banner and the port setting, and that typing reaches the modem at the baud rate;
- the control codes, BEL, and that the ANSI sequences pass through;
- the colour mapping case by case, including 256-colour and RGB codes;
- a cursor position report arriving during a busy screen at 19200;
- set-up:
  - the control and command register values for rates, data bits, parity, stop bits, the external clock, DTR and RTS;
  - the `ATB` offered and sent at the old rate;
  - RTS flow control letting go and asserting again;
  - `TERM.CFG` saved, and read at the next start (with an emulated USB drive);
- dialing, hanging up, echo, Backspace, and quitting.

```
sh b.sh
PY65=path/to/py65 python3 test/test_term.py
```

## Notes

- **The ROM's own output and a W65C51N:** if you fit a W65C51N as the display card's ACIA, the ROM's `CHROUT` (which waits for the transmit bit) will need a fixed delay instead.
- **CTS on the serial port:** the 6551 only transmits while its /CTS is low. If typing never reaches the Zimodem, check how CTS is wired, and the Zimodem's flow control (`AT&K0` turns it off).
