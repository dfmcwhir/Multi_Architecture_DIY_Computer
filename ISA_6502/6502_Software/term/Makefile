# make      builds TERM.BIN (needs ca65/ld65 and ../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

TERM.BIN: term.s term.cfg ../sbc_api.inc
	$(CA65) -I .. $(DEFS) term.s -o term.o -l term.lst
	$(LD65) -C term.cfg term.o -o TERM.BIN -m term.map

clean:
	rm -f *.o *.lst *.map *.lbl TERM.BIN
