# make      builds ROCKS.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

ROCKS.BIN: rocks.s rocks.cfg ../sbc_api.inc rocks_data.inc ../ay/sfx.s rocks_sound.inc
	$(CA65) -I .. $(DEFS) rocks.s -o rocks.o -l rocks.lst
	$(LD65) -C rocks.cfg rocks.o -o ROCKS.BIN -m rocks.map

rocks_data.inc: gen.py
	python3 gen.py > rocks_data.inc

clean:
	rm -f rocks.o rocks.lst rocks.map ROCKS.BIN

rocks_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py rocks
