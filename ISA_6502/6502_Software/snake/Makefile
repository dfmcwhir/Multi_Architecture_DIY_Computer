# make      builds SNAKE.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

SNAKE.BIN: snake.s snake.cfg ../sbc_api.inc ../ay/sfx.s
	$(CA65) -I .. $(DEFS) snake.s -o snake.o -l snake.lst
	$(LD65) -C snake.cfg snake.o -o SNAKE.BIN -m snake.map

clean:
	rm -f snake.o snake.lst snake.map SNAKE.BIN
