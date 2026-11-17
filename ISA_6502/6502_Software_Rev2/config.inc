; ============================================================================
; config.inc - build options for the 6502 CPU Rev2 ROM
;
; This is the ONE place to say which cards the ROM is built for.  Any setting
; can also be given on the ca65 command line, which wins over the value here:
;       ca65 -D CPU_KHZ=4000 -D CON_DISPLAY=0 main.s ...
; (make.bat passes its first argument as CPU_KHZ.)
; ============================================================================

.macro DEFAULT name, value
  .ifndef name
    name = value
  .endif
.endmacro

; ---------------------------------------------------------------------------
; CPU clock, in kHz (4000 = 4 MHz, 3686 = 3.6864 MHz).  All delays, the 60 Hz
; tick and the serial timings are worked out from it.
; ---------------------------------------------------------------------------
DEFAULT CPU_KHZ, 2000
CPU_MHZ         = (CPU_KHZ + 999) / 1000        ; whole MHz, rounded up (older code)

; ---------------------------------------------------------------------------
; Memory
;   $0000-$0FFF is never banked.  The BIOS keeps ALL of its RAM there:
;   $0200-$04FF as before, plus $0500-$07FF for the new drivers (DRVVARS).
;   BASIC programs and monitor-loaded programs now start at USER_RAM.
; ---------------------------------------------------------------------------
DEFAULT USER_RAM, $0800         ; first byte of BASIC / loaded programs
DEFAULT HAS_BANKS, 1            ; bank register at $7FFE: count the banks at boot

; ---------------------------------------------------------------------------
; Display: exactly one
; ---------------------------------------------------------------------------
DISP_NONE       = 0             ; no display card: the serial console is the console
DISP_TERM       = 1             ; KB_MONITOR_TERM (PIC32 terminal, 6551 at $7F18, IRQ5)
DISP_PICO       = 2             ; PICO9918 at $7F1C/$7F1D
DISP_ESP32      = 3             ; ESP32_VGA at $7F18-$7F1B
DEFAULT CON_DISPLAY, DISP_TERM

; ---------------------------------------------------------------------------
; ESP32_VGA card (only used when CON_DISPLAY = DISP_ESP32)
; ---------------------------------------------------------------------------
DEFAULT ESP32_KBD, 1            ; 1 = also take keys from the card's own keyboard
DEFAULT ESP32_IRQ, 5            ; jumper: 5 or 6, or 0 = not jumpered (keys polled)

; ---------------------------------------------------------------------------
; PICO9918 card (only used when CON_DISPLAY = DISP_PICO)
; ---------------------------------------------------------------------------
DEFAULT PICO_DATA, $7F1C        ; VDP data port      (MODE = 0)
DEFAULT PICO_CTRL, $7F1D        ; VDP control/status (MODE = 1)
DEFAULT PICO_COLS, 0            ; 0 = 80 x 30 if the PICO9918 has firmware 1.0+,
                                ;     else 40 x 24;  40 = always 40 x 24
DEFAULT PICO_IRQ, 0             ; 0 = VDP interrupt off (SBC_VSYNC polls the
                                ;     status);  5 or 6 = the card's jumper
DEFAULT PICO_FG, 15             ; text colours (TMS9918A colours 0-15:
DEFAULT PICO_BG, 4              ;     15 white, 4 dark blue, 1 black)
DEFAULT PICO_BOOT_MS, 3000      ; how long to wait for the PICO9918 to boot
DEFAULT PICO_SETTLE_MS, 100     ; and once it answers, before setting it up
DEFAULT PICO_SLOW, 0            ; NOPs between VDP accesses (0 for the PICO9918;
                                ;     a real TMS9918A at 4 MHz needs about 6)

; ---------------------------------------------------------------------------
; Mouse: which interface SBC_MOUSEON / SBC_MOUSE use
; ---------------------------------------------------------------------------
MOUSE_NONE      = 0
MOUSE_AVR       = 1             ; AVR keyboard interface (Serial Rev3 / PICO9918 card)
MOUSE_ESP32     = 2             ; ESP32_VGA card
; (default: the AVR interface if fitted, else the ESP32 card - see below)

; ---------------------------------------------------------------------------
; Serial console: where console output goes when there is no display (or the
; display card doesn't answer), and where CON_MIRROR copies it to.
; ---------------------------------------------------------------------------
SER_NONE        = 0
SER_AVR         = 1             ; serial port of the AVR keyboard interface ($7F1E)
SER_ACIA        = 2             ; 6551 on the serial card ($7F14)
DEFAULT CON_SERIAL, SER_AVR
DEFAULT CON_MIRROR, 0           ; 1 = copy everything printed to the serial console too

; ---------------------------------------------------------------------------
; AVR keyboard / mouse / serial interface, $7F1E/$7F1F
; (on the Serial Rev3 card, or on the PICO9918 card - only one is fitted)
; ---------------------------------------------------------------------------
DEFAULT HAS_AVRKBD, 1
DEFAULT AVRKBD_IRQ, 5           ; jumper: 5 or 6

; ---------------------------------------------------------------------------
; Serial card 6551, $7F14-$7F17, IRQ3
; ---------------------------------------------------------------------------
DEFAULT HAS_ACIA, 1
DEFAULT ACIA_BAUD, 2400         ; 1200, 2400, 4800, 9600 or 19200 (1.8432 MHz crystal)
DEFAULT ACIA_CONSOLE, 0         ; 1 = what it receives is typed into the console
DEFAULT ACIA_WDC, 0             ; 1 = W65C51N fitted (its "TX empty" flag is broken:
                                ;     a timed wait is used instead)

; ---------------------------------------------------------------------------
; KB_MONITOR_TERM display card (only used when CON_DISPLAY = DISP_TERM)
; ---------------------------------------------------------------------------
DEFAULT TERM_WDC, 0             ; 1 = W65C51N fitted on that card
DEFAULT TERM_BOOT_MS, 500       ; wait after power-up before the first character
                                ;     (the PIC32 terminal starting up; 100-25500)

; ---------------------------------------------------------------------------
; ISA6502_IO card and the rest
;   Storage (CH376), I2C/LCD and AY sound stay in every build because BASIC
;   has keywords for them; these switches only control the boot-time setup
;   and the interrupt hookup.
; ---------------------------------------------------------------------------
DEFAULT HAS_VIA, 1              ; 65C22 at $7F00, IRQ2: 60 Hz system tick
DEFAULT HAS_GAMEPAD, 1          ; NES pad on VIA port A (needs HAS_VIA)
DEFAULT HAS_AY, 1               ; AY-3-8910 at $7F22/$7F23
DEFAULT HAS_SPI, 1              ; 65SPI on the Advanced_IO card, $7F28-$7F2B
DEFAULT HAS_IDE, 1              ; SPI-IDE/CF card on 65SPI SS0 (needs HAS_SPI)
DEFAULT FS_DEFAULT, 0           ; storage at reset: 0 = U: USB drive, 1 = C: CF card
DEFAULT HAS_SPO, 1              ; SPO256A-AL2 at $7F26 (keep its IRQ7 jumper OFF)

; Sound for BASIC's SOUND / NOTE / NOISE / QUIET and the SBC_SND... calls:
SND_NONE        = 0
SND_AY          = 1             ; the AY-3-8910 card
SND_ESP         = 2             ; the ESP32_VGA card's synthesizer
; (default: the AY if fitted, else the ESP32 card if it is the display)

; ---------------------------------------------------------------------------
; Console input polling.  1 = CHRIN also checks the input devices directly,
; so typing still works if an IRQ jumper doesn't match this file.
; ---------------------------------------------------------------------------
DEFAULT CON_POLL, 1


; ===========================================================================
; Derived values and checks - nothing to set below here
; ===========================================================================
ACIA_TO_CON     = ACIA_CONSOLE .or (CON_SERIAL = SER_ACIA)
ESP_KEYS        = (CON_DISPLAY = DISP_ESP32) .and ESP32_KBD

.ifndef SND_DEV
  .if HAS_AY
    SND_DEV     = SND_AY
  .elseif CON_DISPLAY = DISP_ESP32
    SND_DEV     = SND_ESP
  .else
    SND_DEV     = SND_NONE
  .endif
.endif

.ifndef MOUSE_SRC
  .if HAS_AVRKBD
    MOUSE_SRC   = MOUSE_AVR
  .elseif CON_DISPLAY = DISP_ESP32
    MOUSE_SRC   = MOUSE_ESP32
  .else
    MOUSE_SRC   = MOUSE_NONE
  .endif
.endif

.if CON_DISPLAY = DISP_PICO
  .if PICO_IRQ <> 0 .and PICO_IRQ <> 5 .and PICO_IRQ <> 6
    .error "config.inc: PICO_IRQ must be 0, 5 or 6"
  .endif
  .if PICO_COLS <> 0 .and PICO_COLS <> 40
    .error "config.inc: PICO_COLS must be 0 (auto) or 40"
  .endif
.endif
.if SND_DEV = SND_ESP .and CON_DISPLAY <> DISP_ESP32
  .error "config.inc: SND_DEV = SND_ESP needs CON_DISPLAY = DISP_ESP32"
.endif
.if SND_DEV = SND_AY .and .not HAS_AY
  .error "config.inc: SND_DEV = SND_AY needs HAS_AY = 1"
.endif
.if HAS_IDE .and .not HAS_SPI
  .error "config.inc: HAS_IDE needs HAS_SPI = 1"
.endif
.if FS_DEFAULT = 1 .and .not HAS_IDE
  .error "config.inc: FS_DEFAULT = 1 (CF) needs HAS_IDE = 1"
.endif
.if MOUSE_SRC = MOUSE_AVR .and .not HAS_AVRKBD
  .error "config.inc: MOUSE_SRC = MOUSE_AVR needs HAS_AVRKBD = 1"
.endif
.if MOUSE_SRC = MOUSE_ESP32 .and CON_DISPLAY <> DISP_ESP32
  .error "config.inc: MOUSE_SRC = MOUSE_ESP32 needs CON_DISPLAY = DISP_ESP32"
.endif
.if ESP_KEYS
  .if ESP32_IRQ <> 0 .and ESP32_IRQ <> 5 .and ESP32_IRQ <> 6
    .error "config.inc: ESP32_IRQ must be 5, 6 or 0 (not jumpered)"
  .endif
  .if ESP32_IRQ = 0 .and .not CON_POLL
    .error "config.inc: ESP32_IRQ = 0 needs CON_POLL = 1 (keys are polled)"
  .endif
.endif
.if CON_DISPLAY = DISP_ESP32 .and CPU_KHZ > 4000
  .warning "config.inc: the ESP32_VGA card is only rated to 4 MHz without its write latch"
.endif
.if CON_DISPLAY > DISP_ESP32
  .error "config.inc: CON_DISPLAY must be DISP_NONE, DISP_TERM, DISP_PICO or DISP_ESP32"
.endif
.if CON_SERIAL = SER_AVR .and .not HAS_AVRKBD
  .error "config.inc: CON_SERIAL = SER_AVR needs HAS_AVRKBD = 1"
.endif
.if CON_SERIAL = SER_ACIA .and .not HAS_ACIA
  .error "config.inc: CON_SERIAL = SER_ACIA needs HAS_ACIA = 1"
.endif
.if CON_DISPLAY = DISP_NONE .and CON_SERIAL = SER_NONE
  .error "config.inc: no display and no serial console - nothing to talk to"
.endif
.if HAS_AVRKBD
  .if AVRKBD_IRQ <> 5 .and AVRKBD_IRQ <> 6
    .error "config.inc: AVRKBD_IRQ must be 5 or 6 (the card's jumper)"
  .endif
.endif
.if HAS_GAMEPAD .and .not HAS_VIA
  .error "config.inc: HAS_GAMEPAD needs HAS_VIA = 1"
.endif
.if USER_RAM < $0800 .or (USER_RAM .mod 256) <> 0
  .error "config.inc: USER_RAM must be page aligned and at least $0800"
.endif
.if CPU_KHZ < 500 .or CPU_KHZ > 16000
  .error "config.inc: CPU_KHZ out of range (500-16000)"
.endif
.if CPU_KHZ > 8000
  .warning "config.inc: above 8 MHz the CH376 delays and some cards are untested"
.endif
