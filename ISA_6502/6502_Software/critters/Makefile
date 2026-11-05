# make      builds CRITTERS.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

CRITTERS.BIN: critters.s critters.cfg ../sbc_api.inc ../ay/sfx.s critters_sound.inc
	$(CA65) -I .. $(DEFS) critters.s -o critters.o -l critters.lst
	$(LD65) -C critters.cfg critters.o -o CRITTERS.BIN -m critters.map

clean:
	rm -f critters.o critters.lst critters.map CRITTERS.BIN

critters_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py critters
