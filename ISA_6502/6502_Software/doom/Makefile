# make      builds DOOM.BIN (needs ca65/ld65 and ../sbc_api.inc)
# make levels / make tables   regenerate the level files / lookup tables
CA65 ?= ca65
LD65 ?= ld65

DOOM.BIN: doom.s doom.cfg ../sbc_api.inc tables.inc builtin.inc ../ay/sfx.s doom_sound.inc
	$(CA65) -I .. $(DEFS) doom.s -o doom.o -l doom.lst
	$(LD65) -C doom.cfg doom.o -o DOOM.BIN -m doom.map

tables tables.inc: gen_tables.py
	python3 gen_tables.py > tables.inc

levels builtin.inc: mklevels.py
	python3 mklevels.py

clean:
	rm -f doom.o doom.lst doom.map DOOM.BIN

doom_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py doom
