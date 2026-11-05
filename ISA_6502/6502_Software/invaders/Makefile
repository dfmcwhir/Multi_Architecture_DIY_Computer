# make      builds INVADERS.BIN (needs ca65/ld65, ../sbc_api.inc and ../ay/sfx.s)
CA65 ?= ca65
LD65 ?= ld65

INVADERS.BIN: invaders.s invaders.cfg ../sbc_api.inc ../ay/sfx.s
	$(CA65) -I .. $(DEFS) invaders.s -o invaders.o -l invaders.lst
	$(LD65) -C invaders.cfg invaders.o -o INVADERS.BIN -m invaders.map

clean:
	rm -f invaders.o invaders.lst invaders.map INVADERS.BIN
