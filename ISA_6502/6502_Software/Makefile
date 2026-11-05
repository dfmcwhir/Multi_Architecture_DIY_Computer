# Requires the cc65 tools (ca65, ld65).  `make` builds rom.bin (32 KB, $8000-$FFFF).
rom.bin: main.o sbc.cfg
	ld65 -C sbc.cfg main.o -o rom.bin -m rom.map -Ln rom.lbl

main.o: main.s basic.s bios.s ch376_abs.s ch376_loadsave.s wozmon.s monitor_cmds.s gamepad.s jumptable.s lcd_i2c.s pcf8584.s basic_i2c.s
	ca65 main.s -o main.o -l main.lst

clean:
	rm -f main.o main.lst rom.bin rom.map rom.lbl
