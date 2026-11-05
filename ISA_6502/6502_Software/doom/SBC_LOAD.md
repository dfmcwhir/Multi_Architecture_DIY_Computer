# SBC_LOAD: proposed ROM entry point at $FE15

A new entry in the ROM's fixed jump table that loads a whole file from the USB drive (CH376) into RAM. Programs call it to fetch data while they run. 6502 DOOM uses it to load one map at a time.

## Jump table

```
$FE00  JMP chrin        SBC_CHRIN
$FE03  JMP chrout       SBC_CHROUT
$FE06  JMP menu         SBC_MENU
$FE09  JMP cold         SBC_COLD
$FE0C  JMP warm         SBC_WARM
$FE0F  JMP monitor      SBC_MONITOR
$FE12  JMP padstate     SBC_PADSTATE
$FE15  JMP load_file    SBC_LOAD        <- new
```

It must be a real `JMP` (opcode $4C). Programs check that byte to decide whether the ROM has SBC_LOAD. On an older ROM they see something else there and fall back.

Line for `sbc_api.inc`:

```
SBC_LOAD        = $FE15         ; load a file: A/Y = parameter block (.word addr, .word max, "NAME.EXT",0)
                                ;   carry clear = loaded, X/Y = length; carry set = failed, A = error code
```

## Calling it

```
        lda     #<block
        ldy     #>block
        jsr     SBC_LOAD
        bcs     failed          ; A = error code
        ; X = length low byte, Y = length high byte
        ...
block:  .word   $5000           ; +0  load address
        .word   $0600           ; +2  most bytes to load
        .byte   "E1M1.LVL", 0   ; +4  file name, zero terminated
```

**In:** A = low byte and Y = high byte of the parameter block. The block can be anywhere in RAM.

**The parameter block:**

| Offset | Size | Contents |
|---|---|---|
| +0 | word | address to load to |
| +2 | word | the most bytes to write (the buffer size) |
| +4 | 1–13 | file name in 8.3 form, upper case, ending with a 0 byte. It is in the root directory, the same place the monitor's `L` command looks. |

**Out, success:**
- Carry clear.
- X/Y = number of bytes loaded (X low, Y high).
- If the file is longer than the limit, only the first *max* bytes are loaded and it still counts as success, with X/Y = max.

**Out, failure:**
- Carry set.
- A = error code: the CH376 status byte where there is one (for example $42 `ERR_MISS_FILE`), or $FF for a timeout or no drive.
- What happened to the buffer doesn't matter.

**Changes:** A, X, Y and the flags. The stack must be balanced on return. It may use any zero page or other workspace the firmware already owns: DOOM uses no zero page at all and nothing at $0200–$04FF.

## Rules that matter to programs

1. **Never write past *address + max − 1*.** DOOM's frame buffers are right after its level buffer.
2. **Print nothing.** The terminal is in graphics mode while a game runs: no "LOADING…" text, prompts, error messages or CR/LF. Report everything through the carry and A.
3. **Close the file before returning**, on success and on failure, so the next call starts clean. DOOM calls it again when you finish a map, and again when you die and the map restarts.
4. **Mount the drive if needed.** Do whatever the monitor's `L` command does when the drive was just plugged in or has not been used since reset.
5. **Leave the terminal and pad state alone.** No change to the UART setup or the gamepad driver.
6. **Return; don't jump.** Even on a fatal error, return with the carry set rather than going to the monitor.
7. **Use any speed.** A one-second load is fine: the game shows "LOADING E1M2.LVL" first.

## Implementation notes

The monitor's `L NAME ADDR` command already does nearly all of this. The simplest SBC_LOAD is a wrapper around the same routine:

1. Copy the name from block+4 into whatever buffer the `L` code uses. Add a leading `/` if your code expects a path.
2. Take the address from block+0 and the limit from block+2.
3. Run the existing open / read / close sequence, writing at most *limit* bytes.
4. Count the bytes as they are written; return the count in X/Y with the carry clear, or the CH376 status in A with the carry set.

For reference, the usual CH376 sequence is:

| Step | Command | Expect |
|---|---|---|
| set name | `CMD_SET_FILE_NAME` $2F + "/E1M1.LVL" + 0 | — |
| open | `CMD_FILE_OPEN` $32 | interrupt status `USB_INT_SUCCESS` $14 (else $42 = no such file) |
| read | `CMD_BYTE_READ` $3A + 16-bit count | `USB_INT_DISK_READ` $1D while there is data |
| get data | `CMD_RD_USB_DATA0` $27 → count byte, then that many bytes | — |
| continue | `CMD_BYTE_RD_GO` $3B | $1D again, or $14 at the end |
| close | `CMD_FILE_CLOSE` $36 + 0 | $14 |

## Testing it: LOADTEST.BIN

`loadtest/` holds a small program that exercises SBC_LOAD. Copy LOADTEST.BIN and E1M1.LVL to the drive, then `L LOADTEST 0500`, `R`. With a working SBC_LOAD it prints:

```
SBC_LOAD TEST
1. LOAD E1M1.LVL TO $5000 (MAX $0600): OK, LENGTH $048C
   FIRST BYTES (WANT 44 36 01 ...): 44 36 01 01 01 00 54 48
2. LOAD NOFILE.XYZ (MUST FAIL): FAILED, ERROR $42
3. LOAD E1M1.LVL, MAX 16 BYTES (WANT LENGTH 0010): OK, LENGTH $0010
DONE
```

It then returns to the monitor (`SBC_MONITOR`).
- On a ROM without the entry it prints `NO JMP AT $FE15: THIS ROM HAS NO SBC_LOAD`.
- If test 3 shows `WRONG: MORE THAN 16 BYTES WERE WRITTEN`, the length limit is not being honoured.
