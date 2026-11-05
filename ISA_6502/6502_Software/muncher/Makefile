# make      builds MUNCHER.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

MUNCHER.BIN: muncher.s muncher.cfg ../sbc_api.inc muncher_data.inc ../ay/sfx.s muncher_sound.inc
	$(CA65) -I .. $(DEFS) muncher.s -o muncher.o -l muncher.lst
	$(LD65) -C muncher.cfg muncher.o -o MUNCHER.BIN -m muncher.map

clean:
	rm -f muncher.o muncher.lst muncher.map MUNCHER.BIN

muncher_data.inc: maze.py gen.py
	python3 gen.py > muncher_data.inc

muncher_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py muncher
