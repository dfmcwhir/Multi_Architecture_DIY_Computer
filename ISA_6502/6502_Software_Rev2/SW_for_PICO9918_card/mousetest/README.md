# MOUSETEST: what the ROM gets from the mouse

```
L MOUSETEST 0800
R
```

It turns mouse reports on (`SBC_MOUSEON`) and prints every report `SBC_MOUSE` returns, one line each:

```
#0001 B00 X05 YFD T0005 FFFD
```

- `#` the report count, `B` the buttons (01 left, 02 right, 04 middle), `X` / `Y` this report's movement (hex, signed: FD = -3; right and down are positive), `T` the running x and y totals.
- Any key ends it (reports off, back to the boot menu).
- It prints through the ROM's console, so it works on any display.

What the first lines say:

| You see | Meaning |
|---|---|
| `THIS ROM HAS NO MOUSE CALLS` | an older ROM: no `JMP` at $FE21 |
| `SBC_MOUSEON: NO MOUSE INTERFACE` | the ROM found no AVR, or was built with `MOUSE_SRC = MOUSE_NONE` |
| `MOUSE REPORTS ON...` and nothing when you move the mouse | the ROM and the AVR talk, but the AVR sends no reports: its firmware, or the mouse's wiring or power |
| report lines | the mouse works up to the ROM |
