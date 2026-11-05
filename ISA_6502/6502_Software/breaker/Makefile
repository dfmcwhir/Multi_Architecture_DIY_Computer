# make      builds BREAKER.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

BREAKER.BIN: breaker.s breaker.cfg ../sbc_api.inc breaker_data.inc ../ay/sfx.s breaker_sound.inc
	$(CA65) -I .. $(DEFS) breaker.s -o breaker.o -l breaker.lst
	$(LD65) -C breaker.cfg breaker.o -o BREAKER.BIN -m breaker.map

breaker_data.inc: gen.py
	python3 gen.py > breaker_data.inc

clean:
	rm -f breaker.o breaker.lst breaker.map BREAKER.BIN

breaker_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py breaker
