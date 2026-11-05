# make      builds MINER.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

MINER.BIN: miner.s miner.cfg ../sbc_api.inc miner_data.inc ../ay/sfx.s miner_sound.inc
	$(CA65) -I .. $(DEFS) miner.s -o miner.o -l miner.lst
	$(LD65) -C miner.cfg miner.o -o MINER.BIN -m miner.map

miner_data.inc: gen.py rooms.py phys.py
	python3 gen.py > miner_data.inc

clean:
	rm -f miner.o miner.lst miner.map MINER.BIN

miner_sound.inc: ../ay/tools/game_sounds.py ../ay/tools/sndgen.py
	cd ../ay/tools && python3 game_sounds.py miner
