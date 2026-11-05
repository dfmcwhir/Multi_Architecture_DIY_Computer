# make      builds STACKER.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

STACKER.BIN: stacker.s stacker.cfg ../sbc_api.inc stacker_data.inc ../ay/sfx.s stacker_sound.inc
	$(CA65) -I .. $(DEFS) stacker.s -o stacker.o -l stacker.lst
	$(LD65) -C stacker.cfg stacker.o -o STACKER.BIN -m stacker.map

stacker_data.inc: gen.py
	python3 gen.py > stacker_data.inc

clean:
	rm -f stacker.o stacker.lst stacker.map STACKER.BIN

stacker_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py stacker
