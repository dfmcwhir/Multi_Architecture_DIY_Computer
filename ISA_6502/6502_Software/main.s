; ============================================================================
; main.s - EhBASIC 2.22 for the custom 6502 SBC
;
;   assemble:  ca65 main.s -o main.o -l main.lst
;   link:      ld65 -C sbc.cfg main.o -o rom.bin -m rom.map
;   (or just run  make)
;
; Everything is assembled as ONE unit so that EhBASIC's zero page symbols are
; known when the BIOS code is assembled (the order of the includes matters).
; ============================================================================
.setcpu "6502"          ; NMOS-safe: no 65C02-only instructions are used
.debuginfo +
.feature labels_without_colons   ; basic.s (Lee Davison's source) has none

; ---------------------------------------------------------------------------
; CPU clock in whole MHz (round UP).  The ONE place to set it: the CH376 reset
; and timeout delays (ch376_abs.s) and the I2C/LCD delays (pcf8584.s) use it.
; ---------------------------------------------------------------------------
CPU_MHZ = 2

.include "basic.s"              ; EhBASIC            (segment CODE)
.include "bios.s"               ; hardware, boot menu, IRQ  (BIOS, vars, RESETVEC)
.include "ch376_abs.s"          ; CH376 USB/SD driver       (CHVARS, BIOS)
.include "ch376_loadsave.s"     ; LOAD / SAVE / LOAD "$"    (BIOS)
.include "pcf8584.s"            ; PCF8584 I2C bridge driver (BIOS, BIOSVARS)
.include "lcd_i2c.s"            ; I2C LCD via MCP23008      (BIOS, BIOSVARS, ZEROPAGE)
.include "basic_i2c.s"          ; I2CINIT/I2CWRITE/I2CREAD(), LCDINIT/PRINT/POS/CLS/CMD
.include "basic_ay.s"            ; SOUND, NOTE, NOISE, ENVELOPE, QUIET, AYREG, AYREAD(
.include "gamepad.s"            ; NES gamepad on the VIA    (BIOS, BIOSVARS)
.include "jumptable.s"          ; fixed entry points for your programs (JUMPTAB)
.include "wozmon.s"             ; monitor                   (WOZMON)
.include "monitor_cmds.s"       ; monitor commands ? and L  (BIOS)
