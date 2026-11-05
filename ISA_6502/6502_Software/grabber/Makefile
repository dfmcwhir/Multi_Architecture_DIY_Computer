# make      builds GRABBER.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

GRABBER.BIN: grabber.s grabber.cfg ../sbc_api.inc grabber_data.inc ../ay/sfx.s grabber_sound.inc
	$(CA65) -I .. $(DEFS) grabber.s -o grabber.o -l grabber.lst
	$(LD65) -C grabber.cfg grabber.o -o GRABBER.BIN -m grabber.map

grabber_data.inc: gen.py
	python3 gen.py > grabber_data.inc

clean:
	rm -f grabber.o grabber.lst grabber.map GRABBER.BIN

grabber_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py grabber
