# make      builds LOADTEST.BIN (needs ca65/ld65 and ../../sbc_api.inc)
CA65 ?= ca65
LD65 ?= ld65

LOADTEST.BIN: loadtest.s loadtest.cfg ../../sbc_api.inc
	$(CA65) -I ../.. loadtest.s -o loadtest.o
	$(LD65) -C loadtest.cfg loadtest.o -o LOADTEST.BIN

clean:
	rm -f loadtest.o LOADTEST.BIN
