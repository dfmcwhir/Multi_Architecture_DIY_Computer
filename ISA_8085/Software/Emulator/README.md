Run it with python3 emu8085.py boot_bios.bin. It also accepts .hex, or .asm using the bundled asm8085.py. That mini-assembler is only good enough for my sources, so keep using AS for your real builds.

Options:

--disk DIR makes a host folder the CH376 USB stick. Files written by SAVE or the monitor appear there, and files you drop in can be loaded.
--no-disk is a chip with no stick. --no-ch376 is no chip at all.
--console display|serial picks which port your keyboard and screen use.
--serial tcp:2323 connects the serial card to a TCP port on 127.0.0.1 (use nc or telnet).
--serial-send FILE feeds a file into the serial card.
--speed MHz sets the clock (default 2.4576, 0 means as fast as possible). It runs about four times faster than real time on my test machine, so real-time pacing works.

It models your memory map and devices:

ROM and RAM: ROM at 0000-7FFF and RAM above it.
VIA 65C22: ports, timers T1 and T2, and IFR/IER. I tested T1 in free-run mode raising IRQ 2 together with SETISR.
Two 6551s: serial and display, with transmit and receive timed at the programmed baud rate. A control value of 10h means 115200, as on your card.
CH376: as above.
Interrupt register: at port FF with your (7 − IRQ) × 2 encoding.
RST 6.5: the interrupt line, with SIM masks.

Because receive is timed, a CPU that falls behind loses characters with an overrun flag, as on the real board. Host keystrokes are delivered at about 250 per second so pasted text doesn’t overrun.

Press Ctrl-] for the emulator prompt, which has:

regs, step, bp/unbp and dump for debugging
io on to log port reads and writes
ca1, ca2, cb1, cb2 to raise VIA interrupt flags, and pina/pinb to set the VIA port pins
type, serial and sendfile to inject input
reset, go and quit

Ctrl-C is passed to the computer, so it breaks BASIC.

Limits
Timing: it is instruction-timed (8085 T-states) but not cycle-exact on the bus.
Not emulated: the I2C card (reads FF), serial handshake lines, and the hardware quirks we hit, such as the flaky interrupt register.
VIA: it is a subset, with no shift register and no real handshaking on CA2 and CB2.
Memory-mapped programs: if converted programs PEEK/POKE addresses that you don’t map with .peek/.poke, they just read and write RAM.