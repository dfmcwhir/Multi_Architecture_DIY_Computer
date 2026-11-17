; ============================================================================
; main.s - EhBASIC 2.22 + monitor for the 6502 CPU Rev2 card
;
;   assemble:  ca65 main.s -o main.o -l main.lst
;   link:      ld65 -C sbc.cfg main.o -o rom.bin -m rom.map -Ln rom.lbl
;   (or:       make.bat           make.bat 4000   for a 4 MHz build)
;
; Which cards the ROM is built for is set in config.inc.
; Everything is assembled as ONE unit so that EhBASIC's zero page symbols are
; known when the BIOS code is assembled (the order of the includes matters).
; ============================================================================
.setcpu "6502"          ; NMOS-safe: no 65C02-only instructions are used
.debuginfo +
.feature labels_without_colons   ; basic.s (Lee Davison's source) has none

.include "config.inc"           ; build options: CPU clock, cards, IRQ jumpers

.include "basic.s"              ; EhBASIC            (segment CODE)
.include "bios.s"               ; reset, boot menu, vectors
.include "cpu_rev2.s"           ; bank register, bank count
.include "irq.s"                ; interrupt dispatch (built from config.inc)
.include "console.s"            ; CHRIN / CHROUT, input buffer
.include "drv_via.s"            ; 65C22: 60 Hz tick, LEDs (VIA names used below)
.include "drv_acia.s"           ; serial card 6551
.include "drv_avrkbd.s"         ; AVR keyboard / mouse / serial console
.if CON_DISPLAY = DISP_TERM
.include "drv_kbterm.s"         ; KB_MONITOR_TERM display card
.elseif CON_DISPLAY = DISP_ESP32
.include "drv_esp32.s"          ; ESP32_VGA card (and esp32vga.inc)
.elseif CON_DISPLAY = DISP_PICO
.include "drv_pico.s"           ; PICO9918 card (and pico_font.inc)
.endif
.include "drv_spo.s"            ; SPO256 speech chip
.include "ch376_abs.s"          ; CH376 USB/SD driver       (CHVARS, BIOS)
.include "ch376_loadsave.s"     ; LOAD / SAVE / LOAD "$"    (BIOS)
.include "drv_spi.s"            ; 65SPI
.if HAS_IDE
.include "drv_ide.s"            ; SPI-IDE / CF card (FAT16, DS1302 clock)
.endif
.include "fs.s"                 ; U: / C: - the calls LOAD, SAVE and the monitor use
.include "pcf8584.s"            ; PCF8584 I2C bridge driver (BIOS, BIOSVARS)
.include "lcd_i2c.s"            ; I2C LCD                   (BIOS, BIOSVARS, ZEROPAGE)
.include "basic_i2c.s"          ; I2CINIT/I2CWRITE/I2CREAD(), LCDINIT/PRINT/CMD
.include "basic_ay.s"           ; SOUND, NOTE, NOISE, ENVELOPE, VOICE, QUIET, AYREG, AYREAD(, SAY
.include "basic_gfx.s"          ; CLS, COLOR, LOCATE, PLOT, SPRITE
.include "gamepad.s"            ; NES gamepad on the VIA    (BIOS, BIOSVARS)
.include "jumptable.s"          ; fixed entry points for your programs (JUMPTAB)
.include "wozmon.s"             ; monitor                   (WOZMON)
.include "monitor_cmds.s"       ; monitor commands ? and L  (BIOS)
.include "shell.s"              ; SBC_DIR, SBC_RUN, SBC_SHELL, the monitor prompt (stage 6)
